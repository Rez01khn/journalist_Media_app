import 'dart:async';
import 'package:journalist_app_1/models/news.dart';
import 'package:journalist_app_1/models/news_draft.dart';
import 'package:journalist_app_1/models/news_media.dart';
import 'package:journalist_app_1/models/news_status.dart';
import 'package:journalist_app_1/models/reporter.dart';
import 'package:journalist_app_1/repositories/auth_repository.dart';
import 'package:journalist_app_1/repositories/draft_repository.dart';
import 'package:journalist_app_1/repositories/google_drive_repository.dart';
import 'package:journalist_app_1/repositories/news_repository.dart';
import 'package:journalist_app_1/repositories/news_submission_repository.dart';

/// In-memory mock implementation of [AuthRepository] for Phase 1 UI and testing.
class MockAuthRepository implements AuthRepository {
  final _controller = StreamController<Reporter?>.broadcast();

  final Reporter _mockReporter = Reporter(
    id: 'user-001',
    reporterCode: 'REP-2026-084',
    fullName: 'Rezwan Karim',
    email: 'rezwan.karim@newsdesk.bd',
    phoneNumber: '+880 1712-345678',
    designation: 'Senior Field Correspondent',
    assignedArea: 'Dhaka Central & South (Motijheel, Old Town)',
    googleAccountEmail: 'rezwan.karim.field@gmail.com',
    isActive: true,
    isVerified: true,
    createdAt: DateTime(2026, 1, 15),
  );

  @override
  Stream<Reporter?> get authStateChanges => _controller.stream;

  @override
  Future<Reporter?> getCurrentReporter() async {
    return _mockReporter;
  }

  @override
  Future<bool> login({
    required String emailOrUsername,
    required String password,
  }) async {
    // Prototype only - does not authenticate with real servers yet
    return true;
  }

  @override
  Future<void> logout() async {
    _controller.add(null);
  }
}

/// In-memory mock implementation of [NewsRepository].
class MockNewsRepository implements NewsRepository {
  static final List<News> _sampleNews = [
    News(
      id: 'news-101',
      trackingCode: 'REP-101',
      reporterId: 'user-001',
      reporterName: 'Rezwan Karim',
      headline: 'Metro Rail Phase 2 Work Gains Momentum Across South Dhaka',
      category: 'Infrastructure',
      location: 'Motijheel, Dhaka',
      incidentDetails:
          'Construction teams have begun the foundation works for Phase 2 extension...',
      status: NewsStatus.published,
      submittedAt: DateTime(2026, 10, 29, 11, 30),
      publishedAt: DateTime(2026, 10, 29, 13, 00),
    ),
    News(
      id: 'news-102',
      trackingCode: 'REP-102',
      reporterId: 'user-001',
      reporterName: 'Rezwan Karim',
      headline: 'Chittagong Port Breaks Monthly Container Handling Record',
      category: 'Economy',
      location: 'Chattogram Port',
      incidentDetails:
          'Container handling statistics at Chattogram Port exceeded expectations this month...',
      status: NewsStatus.approved,
      submittedAt: DateTime(2026, 10, 28, 16, 15),
      reviewedAt: DateTime(2026, 10, 28, 18, 00),
    ),
    News(
      id: 'news-103',
      trackingCode: 'REP-103',
      reporterId: 'user-001',
      reporterName: 'Rezwan Karim',
      headline: 'Inter-District Highway Safety Improvements Initiated',
      category: 'National',
      location: 'Dhaka-Chattogram Highway',
      incidentDetails:
          'Roads and Highways department has introduced enhanced lane markers and speed controls...',
      status: NewsStatus.pending,
      submittedAt: DateTime(2026, 10, 27, 9, 20),
    ),
    News(
      id: 'news-104',
      trackingCode: 'REP-104',
      reporterId: 'user-001',
      reporterName: 'Rezwan Karim',
      headline: 'Unverified Spot Report on Warehouse Fire in Old Town',
      category: 'Crime',
      location: 'Armanitola, Old Dhaka',
      incidentDetails:
          'Preliminary field observations regarding small warehouse smoke sighting...',
      status: NewsStatus.rejected,
      submittedAt: DateTime(2026, 10, 25, 20, 5),
      rejectionReason:
          'Facts require further multi-source verification and fire brigade confirmation.',
    ),
  ];

  @override
  Future<List<News>> getReporterNews({
    required String reporterId,
    NewsStatus? statusFilter,
  }) async {
    if (statusFilter == null) {
      return _sampleNews;
    }
    return _sampleNews.where((item) => item.status == statusFilter).toList();
  }

  @override
  Future<News?> getNewsById(String newsId) async {
    return _sampleNews.firstWhere(
      (n) => n.id == newsId,
      orElse: () => _sampleNews.first,
    );
  }

  @override
  Future<Map<NewsStatus, int>> getNewsStatusCounts({
    required String reporterId,
  }) async {
    return {
      NewsStatus.draft: 2,
      NewsStatus.pending: _sampleNews
          .where((n) => n.status == NewsStatus.pending)
          .length,
      NewsStatus.approved: _sampleNews
          .where((n) => n.status == NewsStatus.approved)
          .length,
      NewsStatus.published: _sampleNews
          .where((n) => n.status == NewsStatus.published)
          .length,
      NewsStatus.rejected: _sampleNews
          .where((n) => n.status == NewsStatus.rejected)
          .length,
    };
  }
}

/// In-memory mock implementation of [DraftRepository].
class MockDraftRepository implements DraftRepository {
  final List<NewsDraft> _drafts = [
    NewsDraft(
      id: 'draft-001',
      reporterId: 'user-001',
      headline: 'Dhaka Book Fair 2026 Preparations Enter Final Week',
      category: 'Culture',
      location: 'Bangla Academy, Dhaka',
      incidentDetails:
          'Publishers and stall contractors are finalizing construction ahead of inaugural day...',
      lastSavedAt: DateTime(2026, 10, 27),
    ),
  ];

  void clear() {
    _drafts.clear();
  }

  @override
  Future<List<NewsDraft>> getAllDrafts({required String reporterId}) async {
    return _drafts;
  }

  @override
  Future<NewsDraft?> getDraftById(String draftId) async {
    for (final d in _drafts) {
      if (d.id == draftId) return d;
    }
    return null;
  }

  @override
  Future<void> saveDraft(NewsDraft draft) async {
    final index = _drafts.indexWhere((d) => d.id == draft.id);
    if (index >= 0) {
      _drafts[index] = draft;
    } else {
      _drafts.add(draft);
    }
  }

  @override
  Future<void> deleteDraft(String draftId) async {
    _drafts.removeWhere((d) => d.id == draftId);
  }

  @override
  Future<List<NewsDraft>> getPendingSyncDrafts({
    required String reporterId,
  }) async {
    return _drafts
        .where(
          (d) =>
              d.reporterId == reporterId &&
              (!d.isSyncedWithDrive ||
                  d.driveSyncStatus != DraftSyncStatus.synced),
        )
        .toList();
  }
}

/// In-memory mock implementation of [GoogleDriveRepository].
class MockGoogleDriveRepository implements GoogleDriveRepository {
  String? _connectedEmail;
  final List<NewsMedia> _files = [];
  final Map<String, String> _newsFolders =
      {}; // folderId -> folderName (News Title)
  final Map<String, String> _newsFolderOwners =
      {}; // folderId -> reporterGoogleEmail
  bool _authorized = false;
  int _idCounter = 0;

  Map<String, String> get newsFolders => Map.unmodifiable(_newsFolders);

  List<NewsMedia> filesForAccount(String email) => _files
      .where((f) => f.reporterGoogleAccountEmail == email)
      .toList(growable: false);

  void seedFiles(List<NewsMedia> files) {
    _files.clear();
    _files.addAll(files);
  }

  @override
  Future<String?> getCurrentAccountEmail() async {
    return _connectedEmail;
  }

  @override
  Future<bool> isDriveAuthorized({required String reporterGoogleEmail}) async {
    return _authorized && _connectedEmail == reporterGoogleEmail;
  }

  @override
  Future<String> authorizeDrive({required String reporterGoogleEmail}) async {
    _connectedEmail = reporterGoogleEmail;
    _authorized = true;
    return 'mock-oauth-token-for-$reporterGoogleEmail';
  }

  @override
  Future<void> disconnectDrive() async {
    _connectedEmail = null;
    _authorized = false;
  }

  @override
  Future<String> getOrCreateAppFolder({
    required String folderName,
    required String reporterGoogleEmail,
  }) async {
    return 'mock-folder-id-for-$folderName';
  }

  @override
  Future<String> getOrCreateNewsFolder({
    required String newsTitle,
    required String reporterGoogleEmail,
    String? appFolderName,
    String? existingNewsFolderId,
  }) async {
    final cleanTitle = newsTitle.trim().isNotEmpty
        ? newsTitle.trim()
        : 'Untitled News';

    if (existingNewsFolderId != null &&
        existingNewsFolderId.isNotEmpty &&
        (_newsFolderOwners[existingNewsFolderId] == null ||
            _newsFolderOwners[existingNewsFolderId] == reporterGoogleEmail)) {
      _newsFolders[existingNewsFolderId] = cleanTitle;
      _newsFolderOwners[existingNewsFolderId] = reporterGoogleEmail;
      return existingNewsFolderId;
    }

    // Check if folder with same title already exists for this reporter account
    for (final entry in _newsFolders.entries) {
      if (entry.value == cleanTitle &&
          _newsFolderOwners[entry.key] == reporterGoogleEmail) {
        return entry.key;
      }
    }

    _idCounter++;
    final folderId = 'mock-news-folder-$_idCounter';
    _newsFolders[folderId] = cleanTitle;
    _newsFolderOwners[folderId] = reporterGoogleEmail;
    return folderId;
  }

  @override
  Future<List<NewsMedia>> listFiles({
    required String reporterGoogleEmail,
    String? folderId,
  }) async {
    return List.unmodifiable(
      _files.where(
        (f) =>
            f.reporterGoogleAccountEmail == null ||
            f.reporterGoogleAccountEmail == reporterGoogleEmail,
      ),
    );
  }

  @override
  Future<NewsMedia> uploadMediaToReporterDrive({
    required String localFilePath,
    required MediaType mediaType,
    required String reporterGoogleEmail,
    String? targetFolderName,
    String? targetFolderId,
  }) async {
    _idCounter++;
    final media = NewsMedia(
      id: 'media-$_idCounter-${DateTime.now().millisecondsSinceEpoch}',
      fileName: localFilePath.split(RegExp(r'[\\/]')).last,
      localFilePath: localFilePath,
      driveFileId:
          'drive-file-$_idCounter-${DateTime.now().millisecondsSinceEpoch}',
      driveWebViewLink: 'https://drive.google.com/file/d/mock-preview/view',
      driveDownloadLink:
          'https://drive.google.com/uc?id=mock-preview&export=download',
      mimeType: mediaType == MediaType.image
          ? 'image/jpeg'
          : mediaType == MediaType.video
          ? 'video/mp4'
          : mediaType == MediaType.audio
          ? 'audio/mp4'
          : 'application/octet-stream',
      mediaType: mediaType,
      isUploadedToDrive: true,
      reporterGoogleAccountEmail: reporterGoogleEmail,
      createdAt: DateTime.now(),
    );
    _files.add(media);
    return media;
  }

  @override
  Future<NewsMedia> uploadDraftFile({
    required String localFilePath,
    required String draftId,
    required String reporterGoogleEmail,
    String? targetFolderName,
    String? targetFolderId,
    String? existingDriveFileId,
  }) async {
    final fileName = localFilePath.split(RegExp(r'[\\/]')).last;

    // 1. If existingDriveFileId provided for this account, update that file in-place
    if (existingDriveFileId != null) {
      final index = _files.indexWhere(
        (f) =>
            f.driveFileId == existingDriveFileId &&
            (f.reporterGoogleAccountEmail == null ||
                f.reporterGoogleAccountEmail == reporterGoogleEmail),
      );
      if (index != -1) {
        final existing = _files[index];
        final updated = existing.copyWith(
          localFilePath: localFilePath,
          fileName: fileName,
          reporterGoogleAccountEmail: reporterGoogleEmail,
          createdAt: DateTime.now(),
        );
        _files[index] = updated;
        return updated;
      }
    }

    // 2. Prevent duplicate by checking if a draft with same file name already exists for this account
    final nameIndex = _files.indexWhere(
      (f) =>
          f.fileName == fileName &&
          (f.reporterGoogleAccountEmail == null ||
              f.reporterGoogleAccountEmail == reporterGoogleEmail),
    );
    if (nameIndex != -1) {
      final existing = _files[nameIndex];
      final updated = existing.copyWith(
        localFilePath: localFilePath,
        reporterGoogleAccountEmail: reporterGoogleEmail,
        createdAt: DateTime.now(),
      );
      _files[nameIndex] = updated;
      return updated;
    }

    _idCounter++;
    final media = NewsMedia(
      id: 'draft-file-$_idCounter-${DateTime.now().millisecondsSinceEpoch}',
      fileName: fileName,
      localFilePath: localFilePath,
      driveFileId: 'drive-draft-$_idCounter-$draftId',
      driveWebViewLink:
          'https://drive.google.com/file/d/mock-draft-$draftId/view',
      driveDownloadLink:
          'https://drive.google.com/uc?id=mock-draft-$draftId&export=download',
      mimeType: 'application/json',
      mediaType: MediaType.document,
      isUploadedToDrive: true,
      reporterGoogleAccountEmail: reporterGoogleEmail,
      createdAt: DateTime.now(),
    );
    _files.add(media);
    return media;
  }

  @override
  Future<bool> deleteMediaFromReporterDrive({
    required String driveFileId,
    required String reporterGoogleEmail,
  }) async {
    _files.removeWhere((f) => f.driveFileId == driveFileId);
    return true;
  }
}

/// In-memory mock implementation of [NewsSubmissionRepository].
class MockNewsSubmissionRepository implements NewsSubmissionRepository {
  @override
  Future<News> submitNewsStory(NewsDraft draft) async {
    return News(
      id: 'news-${DateTime.now().millisecondsSinceEpoch}',
      trackingCode: 'REP-${100 + DateTime.now().millisecond}',
      reporterId: draft.reporterId,
      reporterName: 'Reporter',
      headline: draft.headline,
      category: draft.category,
      location: draft.location,
      incidentDetails: draft.incidentDetails,
      status: NewsStatus.pending,
      mediaAttachments: draft.mediaAttachments,
      voiceDispatch: draft.voiceDispatch,
      submittedAt: DateTime.now(),
      isAiAssisted: draft.isAiAssisted,
    );
  }

  @override
  Future<News> previewNewsStory(NewsDraft draft) async {
    return submitNewsStory(draft);
  }

  @override
  Future<bool> exportApprovedStoryToLaravelWebsite({
    required String newsId,
  }) async {
    return false; // Reserved for Future Phase
  }
}
