import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:journalist_app_1/core/constants/app_colors.dart';
import 'package:journalist_app_1/models/news_draft.dart';
import 'package:journalist_app_1/models/news_media.dart';
import 'package:journalist_app_1/providers/app_providers.dart';
import 'package:journalist_app_1/services/offline_submission_queue_service.dart';

/// Screen displaying offline SQLite news drafts with Edit, Delete, and New Story actions.
class DraftsScreen extends ConsumerWidget {
  final Function(NewsDraft)? onSelectDraft;

  const DraftsScreen({super.key, this.onSelectDraft});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draftsAsync = ref.watch(draftsListProvider);

    return Scaffold(
      backgroundColor: AppColors.neutralLight,
      appBar: AppBar(
        backgroundColor: AppColors.navyPrimary,
        elevation: 0,
        title: const Text(
          'Offline Drafts',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.2,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: draftsAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.navyPrimary),
          ),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Text(
                'Failed to load drafts: $error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ),
          data: (drafts) {
            if (drafts.isEmpty) {
              return _buildEmptyState(context);
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: drafts.length,
              itemBuilder: (context, index) {
                final draft = drafts[index];
                return _buildDraftCard(context, ref, draft);
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildDraftCard(BuildContext context, WidgetRef ref, NewsDraft draft) {
    final title = draft.headline.trim().isNotEmpty
        ? draft.headline.trim()
        : 'Untitled Field Draft';
    final category = draft.category.isNotEmpty ? draft.category : 'General';
    final dateStr = _formatTimestamp(draft.lastSavedAt);
    final isHeldForAutoSubmit =
        ref.watch(offlineSubmissionQueueProvider).contains(draft.id);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: () {
          // Select and restore draft for editing
          if (onSelectDraft != null) {
            onSelectDraft!(draft);
            Navigator.of(context).pop(draft);
          } else {
            ref.read(activeDraftProvider.notifier).selectDraft(draft);
            Navigator.of(context).pop(draft);
          }
        },
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top tags
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.navyPrimary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      category.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppColors.navyPrimary,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      if (isHeldForAutoSubmit) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.statusPending.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.schedule_send_rounded,
                                size: 11,
                                color: AppColors.statusPending,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Held • Auto-Submit',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.statusPending,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFF64748B,
                          ).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.save_outlined,
                              size: 12,
                              color: Color(0xFF64748B),
                            ),
                            SizedBox(width: 4),
                            Text(
                              'SQLite Draft',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      _buildDriveSyncBadge(context, ref, draft),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 20,
                          color: Colors.red,
                        ),
                        tooltip: 'Delete Draft',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => _confirmDelete(context, ref, draft),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Title
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppColors.navyDark,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),

              if (draft.incidentDetails.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  draft.incidentDetails.trim(),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 12),

              // Bottom footer: Location & Timestamp
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      if (draft.location.isNotEmpty) ...[
                        Icon(
                          Icons.location_on_outlined,
                          size: 13,
                          color: Colors.grey.shade500,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          draft.location,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (draft.mediaAttachments.any(
                        (m) => m.mediaType == MediaType.image,
                      )) ...[
                        Row(
                          children: [
                            Icon(
                              Icons.photo_outlined,
                              size: 12,
                              color: Colors.grey.shade600,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '${draft.mediaAttachments.where((m) => m.mediaType == MediaType.image).length}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (draft.mediaAttachments.any(
                        (m) => m.mediaType == MediaType.video,
                      )) ...[
                        Row(
                          children: [
                            Icon(
                              Icons.videocam_outlined,
                              size: 13,
                              color: Colors.grey.shade600,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '${draft.mediaAttachments.where((m) => m.mediaType == MediaType.video).length}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (draft.voiceDispatch != null ||
                          draft.mediaAttachments.any(
                            (m) => m.mediaType == MediaType.audio,
                          ))
                        Row(
                          children: [
                            Icon(
                              Icons.mic_none_rounded,
                              size: 13,
                              color: Colors.grey.shade600,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              draft.voiceDispatch?.durationSeconds != null
                                  ? '${draft.voiceDispatch!.durationSeconds}s'
                                  : '1',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                  Row(
                    children: [
                      Icon(
                        Icons.access_time_rounded,
                        size: 12,
                        color: Colors.grey.shade500,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        dateStr,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDriveSyncBadge(
    BuildContext context,
    WidgetRef ref,
    NewsDraft draft,
  ) {
    Color color;
    IconData icon;
    String text;

    switch (draft.driveSyncStatus) {
      case DraftSyncStatus.synced:
        color = const Color(0xFF16A34A);
        icon = Icons.cloud_done_rounded;
        text = 'Synced';
        break;
      case DraftSyncStatus.syncing:
        color = const Color(0xFF2563EB);
        icon = Icons.sync_rounded;
        text = 'Syncing...';
        break;
      case DraftSyncStatus.pending:
        color = const Color(0xFFD97706);
        icon = Icons.cloud_queue_rounded;
        text = 'Pending';
        break;
      case DraftSyncStatus.failed:
        color = const Color(0xFFDC2626);
        icon = Icons.cloud_off_rounded;
        text = 'Failed';
        break;
    }

    final isStuckSyncing =
        draft.driveSyncStatus == DraftSyncStatus.syncing &&
        !ref.read(draftSyncServiceProvider).isSyncing(draft.id);

    return InkWell(
      onTap:
          (draft.driveSyncStatus == DraftSyncStatus.failed ||
              draft.driveSyncStatus == DraftSyncStatus.pending ||
              isStuckSyncing)
          ? () async {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Retrying Google Drive sync...'),
                  duration: Duration(seconds: 1),
                ),
              );
              await ref.read(draftSyncServiceProvider).syncDraft(draft);
            }
          : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(
              text,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, NewsDraft draft) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Delete Draft?'),
        content: Text(
          'Are you sure you want to delete "${draft.headline.isEmpty ? 'Untitled Draft' : draft.headline}"? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.of(dialogCtx).pop();
              final draftRepo = ref.read(draftRepositoryProvider);
              await draftRepo.deleteDraft(draft.id);

              // Clean up local media files associated with draft
              ref.read(mediaStorageServiceProvider).cleanupDraftMedia(draft.id);

              // If this was the active draft, clear it
              final active = ref.read(activeDraftProvider);
              if (active?.id == draft.id) {
                ref.read(activeDraftProvider.notifier).selectDraft(null);
              }

              // Invalidate providers to refresh list and count
              ref.invalidate(draftsListProvider);
              ref.invalidate(draftCountProvider);

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Draft deleted from SQLite storage.'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.navyPrimary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.edit_note_rounded,
                size: 54,
                color: AppColors.navyPrimary,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'No Saved Drafts',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: AppColors.navyDark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Stories you save or auto-save in the Submit News form will be safely preserved offline in SQLite.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final difference = now.difference(dt);

    if (difference.inMinutes < 1) {
      return 'Saved just now';
    } else if (difference.inMinutes < 60) {
      return 'Saved ${difference.inMinutes}m ago';
    } else if (difference.inHours < 24 && dt.day == now.day) {
      final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      final minute = dt.minute.toString().padLeft(2, '0');
      return 'Today, $hour:$minute $ampm';
    } else {
      return '${dt.day}/${dt.month}/${dt.year}';
    }
  }
}
