import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:journalist_app_1/models/news.dart';
import 'package:journalist_app_1/models/news_draft.dart';
import 'package:journalist_app_1/providers/app_providers.dart';

/// Persistence contract for draft IDs held offline for automatic submission.
abstract class OfflineSubmissionQueueStorage {
  Future<List<String>> readQueuedDraftIds();
  Future<void> writeQueuedDraftIds(List<String> ids);
}

class FlutterOfflineSubmissionQueueStorage
    implements OfflineSubmissionQueueStorage {
  static const String _storageKey = 'offline_pending_submission_draft_ids';
  final FlutterSecureStorage _storage;

  const FlutterOfflineSubmissionQueueStorage([
    FlutterSecureStorage? storage,
  ]) : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<List<String>> readQueuedDraftIds() async {
    try {
      final raw = await _storage.read(key: _storageKey);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.whereType<String>().toList();
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> writeQueuedDraftIds(List<String> ids) async {
    try {
      await _storage.write(key: _storageKey, value: jsonEncode(ids));
    } catch (_) {}
  }
}

class InMemoryOfflineSubmissionQueueStorage
    implements OfflineSubmissionQueueStorage {
  List<String> _ids = [];

  @override
  Future<List<String>> readQueuedDraftIds() async => List.unmodifiable(_ids);

  @override
  Future<void> writeQueuedDraftIds(List<String> ids) async {
    _ids = List<String>.from(ids);
  }
}

class SubmissionOutcome {
  final bool submitted;
  final bool queuedOffline;
  final News? submittedNews;
  final String message;

  const SubmissionOutcome({
    required this.submitted,
    required this.queuedOffline,
    this.submittedNews,
    required this.message,
  });
}

typedef ConnectivityProbe = Future<bool> Function();

Future<bool> _defaultConnectivityProbe() async {
  try {
    final result = await InternetAddress.lookup('google.com')
        .timeout(const Duration(seconds: 2));
    return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
  } catch (_) {
    return false;
  }
}

final offlineSubmissionQueueStorageProvider =
    Provider<OfflineSubmissionQueueStorage>((ref) {
      return const FlutterOfflineSubmissionQueueStorage();
    });

final connectivityProbeProvider = Provider<ConnectivityProbe>((ref) {
  return _defaultConnectivityProbe;
});

final offlineSubmissionQueueProvider =
    NotifierProvider<OfflineSubmissionQueueNotifier, Set<String>>(
      OfflineSubmissionQueueNotifier.new,
    );

/// Manages offline news submission holds in SQLite drafts and automatically
/// submits held drafts once the device returns online.
class OfflineSubmissionQueueNotifier extends Notifier<Set<String>> {
  static const EventChannel _connectivityChannel = EventChannel(
    'com.example.journalist_app_1/connectivity',
  );

  StreamSubscription<dynamic>? _connectivitySub;
  bool _isLoaded = false;
  bool _isProcessing = false;
  bool _isDisposed = false;

  @override
  Set<String> build() {
    _isDisposed = false;
    _loadInitialQueue();
    _startConnectivityListener();
    ref.onDispose(() {
      _isDisposed = true;
      _connectivitySub?.cancel();
      _connectivitySub = null;
    });
    return const <String>{};
  }

  Future<void> _loadInitialQueue() async {
    if (_isLoaded) return;
    final ids = await ref
        .read(offlineSubmissionQueueStorageProvider)
        .readQueuedDraftIds();
    _isLoaded = true;
    if (!_isDisposed && ids.isNotEmpty) {
      state = ids.toSet();
      Future.microtask(processPendingSubmissions);
    }
  }

  void _startConnectivityListener() {
    if (!Platform.isAndroid ||
        Platform.environment.containsKey('FLUTTER_TEST')) {
      return;
    }
    try {
      _connectivitySub?.cancel();
      _connectivitySub = _connectivityChannel.receiveBroadcastStream().listen((
        dynamic event,
      ) {
        if (!_isDisposed && event == true) {
          Future.microtask(processPendingSubmissions);
        }
      }, onError: (_) {});
    } catch (_) {}
  }

  Future<void> _ensureLoaded() async {
    if (_isLoaded) return;
    final ids = await ref
        .read(offlineSubmissionQueueStorageProvider)
        .readQueuedDraftIds();
    _isLoaded = true;
    if (!_isDisposed) {
      state = ids.toSet();
    }
  }

  Future<void> _persistState() async {
    await ref
        .read(offlineSubmissionQueueStorageProvider)
        .writeQueuedDraftIds(state.toList());
  }

  /// Submits [draft] immediately if online; otherwise saves it in SQLite
  /// drafts and holds it in the offline queue until connectivity returns.
  Future<SubmissionOutcome> submitOrHoldDraft(NewsDraft draft) async {
    await _ensureLoaded();

    final isOnline = await ref.read(connectivityProbeProvider)();
    if (!isOnline) {
      return _holdDraftOffline(draft);
    }

    try {
      final submittedNews = await ref
          .read(newsSubmissionRepositoryProvider)
          .submitNewsStory(draft);
      await _removeDraftAfterSubmit(draft.id);
      return SubmissionOutcome(
        submitted: true,
        queuedOffline: false,
        submittedNews: submittedNews,
        message: 'News submitted successfully for editorial review.',
      );
    } on SocketException {
      return _holdDraftOffline(draft);
    } on TimeoutException {
      return _holdDraftOffline(draft);
    }
  }

  Future<SubmissionOutcome> _holdDraftOffline(NewsDraft draft) async {
    final savedDraft = draft.copyWith(lastSavedAt: DateTime.now());
    await ref.read(draftRepositoryProvider).saveDraft(savedDraft);

    if (!state.contains(savedDraft.id)) {
      state = {...state, savedDraft.id};
      await _persistState();
    }

    if (!_isDisposed) {
      ref.invalidate(draftsListProvider);
      ref.invalidate(draftCountProvider);
    }

    return const SubmissionOutcome(
      submitted: false,
      queuedOffline: true,
      message:
          'You are offline. News saved to Drafts and held — it will auto-submit as soon as you are back online.',
    );
  }

  Future<void> _removeDraftAfterSubmit(String draftId) async {
    if (state.contains(draftId)) {
      final updated = Set<String>.from(state)..remove(draftId);
      state = updated;
      await _persistState();
    }
    try {
      await ref.read(draftRepositoryProvider).deleteDraft(draftId);
    } catch (e) {
      debugPrint('Could not remove submitted draft $draftId: $e');
    }
    if (!_isDisposed) {
      final active = ref.read(activeDraftProvider);
      if (active != null && active.id == draftId) {
        ref.read(activeDraftProvider.notifier).selectDraft(null);
      }
      ref.invalidate(draftsListProvider);
      ref.invalidate(draftCountProvider);
    }
  }

  /// Automatically submits all held offline drafts once connectivity is available.
  /// Returns the number of drafts successfully submitted.
  Future<int> processPendingSubmissions() async {
    await _ensureLoaded();
    if (_isProcessing || state.isEmpty || _isDisposed) return 0;

    final isOnline = await ref.read(connectivityProbeProvider)();
    if (!isOnline) return 0;

    _isProcessing = true;
    int submittedCount = 0;

    try {
      // If session was restored offline, ensure backend still accepts it first.
      await ref
          .read(authStateProvider.notifier)
          .revalidateOfflineSessionIfNeeded();

      if (!_isDisposed && !ref.read(authStateProvider).isAuthenticated) {
        return 0;
      }

      final pendingIds = state.toList();
      final draftRepo = ref.read(draftRepositoryProvider);
      final submitRepo = ref.read(newsSubmissionRepositoryProvider);

      for (final draftId in pendingIds) {
        if (_isDisposed) break;
        final draft = await draftRepo.getDraftById(draftId);
        if (draft == null) {
          final updated = Set<String>.from(state)..remove(draftId);
          state = updated;
          await _persistState();
          continue;
        }

        try {
          await submitRepo.submitNewsStory(draft);
          await _removeDraftAfterSubmit(draftId);
          submittedCount++;
        } on SocketException {
          break;
        } on TimeoutException {
          break;
        } catch (e) {
          debugPrint('Auto-submit failed for draft $draftId: $e');
        }
      }
    } finally {
      _isProcessing = false;
    }

    return submittedCount;
  }

  /// Removes a draft ID from the auto-submit queue (e.g., if user deletes it).
  Future<void> unqueueDraft(String draftId) async {
    await _ensureLoaded();
    if (!state.contains(draftId)) return;
    final updated = Set<String>.from(state)..remove(draftId);
    state = updated;
    await _persistState();
  }
}
