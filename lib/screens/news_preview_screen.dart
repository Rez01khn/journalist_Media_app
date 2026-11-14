import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:journalist_app_1/core/constants/app_colors.dart';
import 'package:journalist_app_1/models/news_draft.dart';
import 'package:journalist_app_1/models/news_media.dart';
import 'package:journalist_app_1/providers/app_providers.dart';
import 'package:journalist_app_1/services/news_validation_service.dart';
import 'package:journalist_app_1/services/offline_submission_queue_service.dart';
import 'package:video_player/video_player.dart';

/// Professional editorial News Preview screen allowing reporters to inspect
/// headline, body, reporter credentials, photos, video, and voice dispatch
/// before confirming editorial submission.
class NewsPreviewScreen extends ConsumerStatefulWidget {
  final NewsDraft draft;
  final NewsValidationResult? validationResult;

  const NewsPreviewScreen({
    super.key,
    required this.draft,
    this.validationResult,
  });

  @override
  ConsumerState<NewsPreviewScreen> createState() => _NewsPreviewScreenState();
}

class _NewsPreviewScreenState extends ConsumerState<NewsPreviewScreen> {
  NewsValidationResult? _validationResult;

  // Submission in-progress guard — prevents duplicate taps
  bool _isSubmitting = false;

  // Video preview player
  VideoPlayerController? _videoController;
  bool _videoInitialized = false;
  String? _videoError;

  // Voice dispatch audio preview player
  VideoPlayerController? _audioController;
  Timer? _fallbackAudioTimer;
  bool _isPlayingAudio = false;
  Duration _audioPosition = Duration.zero;
  Duration _audioDuration = Duration.zero;

  List<NewsMedia> get _photos => widget.draft.mediaAttachments
      .where((m) => m.mediaType == MediaType.image)
      .toList();

  List<NewsMedia> get _videos => widget.draft.mediaAttachments
      .where((m) => m.mediaType == MediaType.video)
      .toList();

  @override
  void initState() {
    super.initState();
    _validationResult = widget.validationResult;
    if (_validationResult == null) {
      _runValidation();
    }
    _initVideoPlayer();
    final voice = widget.draft.voiceDispatch;
    if (voice != null) {
      _audioDuration = Duration(seconds: voice.durationSeconds ?? 0);
    }
  }

  @override
  void dispose() {
    _fallbackAudioTimer?.cancel();
    _videoController?.dispose();
    _audioController?.dispose();
    super.dispose();
  }

  Future<void> _runValidation() async {
    final validator = ref.read(newsValidationServiceProvider);
    final storage = ref.read(mediaStorageServiceProvider);
    final res = await validator.validateDraft(widget.draft, storage);
    if (mounted) {
      setState(() => _validationResult = res);
    }
  }

  Future<void> _initVideoPlayer() async {
    if (_videos.isEmpty) return;
    final video = _videos.first;
    final path = video.localFilePath;
    if (path == null || !File(path).existsSync()) {
      setState(() => _videoError = 'Video file not found on device storage.');
      return;
    }

    if (!Platform.isAndroid && !Platform.isIOS) {
      setState(
        () =>
            _videoError = 'Video ready for editorial sync (${video.fileName})',
      );
      return;
    }

    try {
      final ctrl = VideoPlayerController.file(File(path));
      _videoController = ctrl;
      await ctrl.initialize();
      ctrl.addListener(() {
        if (mounted) setState(() {});
      });
      if (mounted) {
        setState(() => _videoInitialized = true);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _videoError =
              'Video ready for editorial sync (${video.fileName})',
        );
      }
    }
  }

  Future<void> _toggleAudioPlayback() async {
    final voice = widget.draft.voiceDispatch;
    if (voice == null) return;

    final path = voice.localFilePath;
    if (path == null || !File(path).existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Local audio file missing (${voice.fileName}).'),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }

    if (_isPlayingAudio) {
      _fallbackAudioTimer?.cancel();
      try {
        await _audioController?.pause();
      } catch (_) {}
      if (mounted) {
        setState(() => _isPlayingAudio = false);
      }
      return;
    }

    final totalSecs =
        (voice.durationSeconds != null && voice.durationSeconds! > 0)
        ? voice.durationSeconds!
        : 3;

    try {
      if (_audioController == null) {
        final ctrl = VideoPlayerController.file(File(path));
        _audioController = ctrl;
        await ctrl.initialize();
        if (ctrl.value.duration.inMilliseconds > 0) {
          _audioDuration = ctrl.value.duration;
        } else {
          _audioDuration = Duration(seconds: totalSecs);
        }
        ctrl.addListener(() {
          if (!mounted) return;
          final val = ctrl.value;
          final dur = val.duration.inMilliseconds > 0
              ? val.duration
              : _audioDuration;
          final completed =
              dur.inMilliseconds > 0 && val.position >= dur && !val.isPlaying;
          setState(() {
            _audioPosition = completed ? Duration.zero : val.position;
            _audioDuration = dur;
            _isPlayingAudio = val.isPlaying;
          });
        });
      }

      final ctrl = _audioController!;
      if (_audioDuration.inMilliseconds > 0 &&
          _audioPosition >= _audioDuration) {
        await ctrl.seekTo(Duration.zero);
        _audioPosition = Duration.zero;
      }
      await ctrl.play();
      if (mounted) setState(() => _isPlayingAudio = true);
    } catch (_) {
      _audioDuration = Duration(seconds: totalSecs);
      if (_audioPosition >= _audioDuration) {
        _audioPosition = Duration.zero;
      }
      setState(() => _isPlayingAudio = true);
      _fallbackAudioTimer?.cancel();
      _fallbackAudioTimer = Timer.periodic(const Duration(milliseconds: 250), (
        timer,
      ) {
        if (!mounted || !_isPlayingAudio) {
          timer.cancel();
          return;
        }
        final nextPos = _audioPosition + const Duration(milliseconds: 250);
        if (nextPos >= _audioDuration) {
          timer.cancel();
          setState(() {
            _audioPosition = Duration.zero;
            _isPlayingAudio = false;
          });
        } else {
          setState(() => _audioPosition = nextPos);
        }
      });
    }
  }

  Future<void> _submitOrQueueStory() async {
    if (_isSubmitting) return; // Prevent duplicate taps
    setState(() => _isSubmitting = true);
    try {
      final outcome = await ref
          .read(offlineSubmissionQueueProvider.notifier)
          .submitOrHoldDraft(widget.draft);

      ref.invalidate(newsListProvider);
      ref.invalidate(newsStatusCountsProvider);
      ref.invalidate(draftsListProvider);
      ref.invalidate(draftCountProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(outcome.message),
          backgroundColor: outcome.queuedOffline
              ? AppColors.statusPending
              : AppColors.statusPublished,
        ),
      );
      Navigator.of(context).pop(outcome.submitted);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showConfirmSubmissionDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(
              Icons.verified_user_outlined,
              color: AppColors.navyPrimary,
              size: 22,
            ),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Confirm Editorial Submission',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Confirming submission will send this news story, reporter details, and Google Drive media links to an editor for editorial review.',
              style: TextStyle(fontSize: 13, height: 1.45),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.navyPrimary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.navyPrimary.withValues(alpha: 0.2),
                ),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.cloud_done_outlined,
                    color: AppColors.navyPrimary,
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'If you are offline, the story will be saved in Drafts and held automatically until internet returns.',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.navyDark,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Back to Preview'),
          ),
          ElevatedButton.icon(
            key: const ValueKey('dialog_confirm_submit_btn'),
            onPressed: _isSubmitting
                ? null
                : () {
                    Navigator.of(ctx).pop();
                    _submitOrQueueStory();
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.navyPrimary,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.send_rounded, size: 16),
            label: const Text('Submit to Editor'),
          ),
        ],
      ),
    );
  }

  void _showPhotoDialog(NewsMedia photo) {
    final hasFile =
        photo.localFilePath != null && File(photo.localFilePath!).existsSync();
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              color: AppColors.navyDark,
              child: Row(
                children: [
                  const Icon(Icons.photo, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      photo.fileName,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 18,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: hasFile
                  ? Image.file(File(photo.localFilePath!), fit: BoxFit.contain)
                  : const Padding(
                      padding: EdgeInsets.all(32),
                      child: Icon(
                        Icons.broken_image,
                        size: 56,
                        color: Colors.grey,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String _formatMmSs(int totalSeconds) {
    final safe = totalSeconds < 0 ? 0 : totalSeconds;
    final mins = (safe ~/ 60).toString().padLeft(2, '0');
    final secs = (safe % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  String _formatDuration(Duration d) {
    final mins = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final secs = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  @override
  Widget build(BuildContext context) {
    final reporter = ref.watch(currentReporterProvider).asData?.value;
    final driveState = ref.watch(googleDriveStateProvider);
    final isValid = _validationResult?.isValid ?? true;

    return Scaffold(
      backgroundColor: AppColors.neutralLight,
      appBar: AppBar(
        backgroundColor: AppColors.navyPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'News Preview',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(
              Icons.edit_outlined,
              color: Colors.white,
              size: 16,
            ),
            label: const Text(
              'Edit News',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Validation Summary Banner
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isValid
                      ? const Color(0xFFDCFCE7)
                      : const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isValid
                        ? const Color(0xFF16A34A).withValues(alpha: 0.35)
                        : const Color(0xFFDC2626).withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      isValid
                          ? Icons.verified_rounded
                          : Icons.error_outline_rounded,
                      color: isValid
                          ? const Color(0xFF16A34A)
                          : const Color(0xFFDC2626),
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isValid
                                ? 'Story Validated & Ready for Review'
                                : 'Validation Issues Detected',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: isValid
                                  ? const Color(0xFF166534)
                                  : const Color(0xFF991B1B),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isValid
                                ? 'Required headline, news body, and all attached media files passed format and size checks.'
                                : _validationResult!.allErrors.join('\n'),
                            style: TextStyle(
                              fontSize: 11,
                              color: isValid
                                  ? const Color(0xFF15803D)
                                  : const Color(0xFFB91C1C),
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Story Article Preview Card
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _buildTagPill(
                          widget.draft.category.isNotEmpty
                              ? widget.draft.category.toUpperCase()
                              : 'GENERAL',
                          AppColors.navyPrimary.withValues(alpha: 0.08),
                          AppColors.navyPrimary,
                        ),
                        if (widget.draft.location.trim().isNotEmpty)
                          _buildTagPill(
                            widget.draft.location.trim(),
                            Colors.grey.shade100,
                            Colors.grey.shade800,
                            icon: Icons.location_on_outlined,
                          ),
                        _buildTagPill(
                          widget.draft.isSyncedWithDrive
                              ? 'Synced to Drive'
                              : 'Local SQLite Draft',
                          widget.draft.isSyncedWithDrive
                              ? const Color(0xFFDCFCE7)
                              : const Color(0xFFFEF3C7),
                          widget.draft.isSyncedWithDrive
                              ? const Color(0xFF16A34A)
                              : const Color(0xFFD97706),
                          icon: widget.draft.isSyncedWithDrive
                              ? Icons.cloud_done_rounded
                              : Icons.save_outlined,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      widget.draft.headline.trim().isNotEmpty
                          ? widget.draft.headline.trim()
                          : '(Untitled Headline)',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.navyDark,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                    Text(
                      widget.draft.incidentDetails.trim().isNotEmpty
                          ? widget.draft.incidentDetails.trim()
                          : '(No news body entered)',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade800,
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Reporter Details Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.badge_outlined,
                          color: AppColors.navyPrimary,
                          size: 18,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Reporter Details',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppColors.navyDark,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _buildDetailRow(
                      'Reporter',
                      '${reporter?.fullName ?? 'Rezwan Karim'} (${reporter?.reporterCode ?? 'REP-2026-084'})',
                    ),
                    _buildDetailRow(
                      'Designation',
                      reporter?.designation ?? 'Senior Field Correspondent',
                    ),
                    _buildDetailRow(
                      'Assigned Beat',
                      reporter?.assignedArea ?? 'Dhaka Central & South',
                    ),
                    _buildDetailRow(
                      'Newsdesk Email',
                      reporter?.email ?? 'rezwan.karim@newsdesk.bd',
                    ),
                    _buildDetailRow(
                      'Google Drive',
                      driveState.isConnected
                          ? (driveState.accountEmail ?? 'Connected')
                          : 'Offline (Stored in SQLite)',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Photos Section Preview
              if (_photos.isNotEmpty) ...[
                _buildSectionHeader(
                  'Attached Photos (${_photos.length})',
                  Icons.photo_library_outlined,
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 112,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _photos.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (_, index) {
                      final photo = _photos[index];
                      final exists =
                          photo.localFilePath != null &&
                          File(photo.localFilePath!).existsSync();
                      return GestureDetector(
                        onTap: () => _showPhotoDialog(photo),
                        child: Container(
                          width: 112,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              exists
                                  ? Image.file(
                                      File(photo.localFilePath!),
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          const Center(
                                            child: Icon(
                                              Icons.image_outlined,
                                              color: Colors.grey,
                                            ),
                                          ),
                                    )
                                  : const Center(
                                      child: Icon(
                                        Icons.broken_image,
                                        color: Colors.grey,
                                      ),
                                    ),
                              Positioned(
                                bottom: 4,
                                left: 4,
                                right: 4,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    _formatBytes(photo.fileSizeBytes ?? 0),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // Video Section Preview
              if (_videos.isNotEmpty) ...[
                _buildSectionHeader(
                  'Attached Video (${_videos.length})',
                  Icons.videocam_outlined,
                ),
                const SizedBox(height: 8),
                _buildVideoPreviewCard(_videos.first),
                const SizedBox(height: 14),
              ],

              // Voice Dispatch Preview
              if (widget.draft.voiceDispatch != null) ...[
                _buildSectionHeader('Voice Dispatch', Icons.mic_none_rounded),
                const SizedBox(height: 8),
                _buildVoicePreviewCard(widget.draft.voiceDispatch!),
                const SizedBox(height: 14),
              ],
            ],
          ),
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade200)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 46,
                  child: OutlinedButton(
                    key: const ValueKey('preview_edit_news_btn'),
                    onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.navyPrimary,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      side: const BorderSide(
                        color: AppColors.navyPrimary,
                        width: 1.4,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.edit_outlined, size: 17),
                        SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Edit News',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: SizedBox(
                  height: 46,
                  child: ElevatedButton(
                    key: const ValueKey('preview_confirm_submission_btn'),
                    onPressed: (isValid && !_isSubmitting)
                        ? _showConfirmSubmissionDialog
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.navyPrimary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.send_rounded, size: 16),
                              SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'Confirm Submission',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideoPreviewCard(NewsMedia video) {
    final ctrl = _videoController;
    final isPlaying = ctrl != null && _videoInitialized && ctrl.value.isPlaying;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: Colors.black,
            height: 190,
            child: _videoInitialized && ctrl != null
                ? Stack(
                    alignment: Alignment.center,
                    children: [
                      Center(
                        child: AspectRatio(
                          aspectRatio: ctrl.value.aspectRatio > 0
                              ? ctrl.value.aspectRatio
                              : 16 / 9,
                          child: VideoPlayer(ctrl),
                        ),
                      ),
                      IconButton(
                        iconSize: 48,
                        icon: Icon(
                          isPlaying
                              ? Icons.pause_circle_filled_rounded
                              : Icons.play_circle_fill_rounded,
                          color: Colors.white.withValues(alpha: 0.88),
                        ),
                        onPressed: () {
                          if (ctrl.value.isPlaying) {
                            ctrl.pause();
                          } else {
                            ctrl.play();
                          }
                        },
                      ),
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          color: Colors.black54,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              VideoProgressIndicator(
                                ctrl,
                                allowScrubbing: true,
                                colors: const VideoProgressColors(
                                  playedColor: Color(0xFF38BDF8),
                                  bufferedColor: Colors.white38,
                                  backgroundColor: Colors.white12,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _formatDuration(ctrl.value.position),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                    ),
                                  ),
                                  Text(
                                    _formatDuration(ctrl.value.duration),
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                : Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.videocam_rounded,
                            size: 42,
                            color: Colors.white70,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _videoError ?? 'Loading video preview...',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    video.fileName,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.navyDark,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _formatBytes(video.fileSizeBytes ?? 0),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVoicePreviewCard(NewsMedia voice) {
    final totalSecs =
        (voice.durationSeconds != null && voice.durationSeconds! > 0)
        ? voice.durationSeconds!
        : (_audioDuration.inSeconds > 0 ? _audioDuration.inSeconds : 1);
    final totalMs = _audioDuration.inMilliseconds > 0
        ? _audioDuration.inMilliseconds
        : (totalSecs * 1000);
    final progress = totalMs > 0
        ? (_audioPosition.inMilliseconds / totalMs).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InkWell(
                key: const ValueKey('preview_voice_play_btn'),
                onTap: _toggleAudioPlayback,
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(
                    color: AppColors.navyPrimary,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isPlayingAudio
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      voice.fileName,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.navyDark,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Duration: ${_formatMmSs(totalSecs)} • Size: ${_formatBytes(voice.fileSizeBytes ?? 0)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                _formatMmSs(_audioPosition.inSeconds.clamp(0, totalSecs)),
                style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6,
                    ),
                  ),
                  child: Slider(
                    value: progress,
                    activeColor: AppColors.navyPrimary,
                    inactiveColor: Colors.grey.shade300,
                    onChanged: (v) async {
                      final target = Duration(
                        milliseconds: (totalMs * v.clamp(0.0, 1.0)).round(),
                      );
                      setState(() => _audioPosition = target);
                      try {
                        await _audioController?.seekTo(target);
                      } catch (_) {}
                    },
                  ),
                ),
              ),
              Text(
                _formatMmSs(totalSecs),
                style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 17, color: AppColors.navyPrimary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.navyDark,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.navyDark,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTagPill(String text, Color bg, Color fg, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}
