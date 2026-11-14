import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:journalist_app_1/core/constants/app_colors.dart';
import 'package:journalist_app_1/models/news.dart';
import 'package:journalist_app_1/models/news_draft.dart';
import 'package:journalist_app_1/models/news_status.dart';
import 'package:journalist_app_1/providers/app_providers.dart';
import 'package:journalist_app_1/screens/submit_news_screen.dart';

/// The MyNewsScreen displays field news stories submitted by the journalist,
/// populated from local SQLite persistence and synced with the Laravel backend API.
/// Includes status badges, tracking codes, and locked/correction review states.
class MyNewsScreen extends ConsumerStatefulWidget {
  final String initialFilter;

  const MyNewsScreen({super.key, this.initialFilter = 'All'});

  @override
  ConsumerState<MyNewsScreen> createState() => _MyNewsScreenState();
}

class _MyNewsScreenState extends ConsumerState<MyNewsScreen> {
  late String _activeFilter;

  static const List<String> _filters = [
    'All',
    'Submitted',
    'Under Review',
    'Correction',
    'Approved',
    'Published',
    'Rejected',
  ];

  @override
  void initState() {
    super.initState();
    _activeFilter = widget.initialFilter == 'Pending' ? 'Submitted' : widget.initialFilter;
  }

  bool _matchesFilter(News news, String filter) {
    switch (filter) {
      case 'All':
        return true;
      case 'Pending':
      case 'Submitted':
        return news.status == NewsStatus.pending;
      case 'Under Review':
        return news.status == NewsStatus.underReview;
      case 'Correction':
        return news.status == NewsStatus.correctionRequested;
      case 'Approved':
        return news.status == NewsStatus.approved;
      case 'Published':
        return news.status == NewsStatus.published;
      case 'Rejected':
        return news.status == NewsStatus.rejected;
      default:
        return true;
    }
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final day = dt.day.toString().padLeft(2, '0');
    final month = months[dt.month - 1];
    final year = dt.year;
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final min = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$day $month $year, $hour:$min $ampm';
  }

  @override
  Widget build(BuildContext context) {
    const navyPrimary = AppColors.navyPrimary;
    const navyDark = AppColors.navyDark;
    const neutralLight = Color(0xFFF7F9FC);

    final newsAsync = ref.watch(newsListProvider(null));

    return Scaffold(
      backgroundColor: neutralLight,
      appBar: AppBar(
        backgroundColor: navyPrimary,
        elevation: 0,
        title: const Text(
          'My News',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.2,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Refresh',
            onPressed: () {
              ref.invalidate(newsListProvider);
              ref.invalidate(newsStatusCountsProvider);
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // --- Top Filter Bar ---
            newsAsync.when(
              data: (allNews) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  color: Colors.white,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _filters.map((filter) {
                        final count = allNews.where((n) => _matchesFilter(n, filter)).length;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: _buildFilterChip(filter, count),
                        );
                      }).toList(),
                    ),
                  ),
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
            const Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0)),

            // --- Submissions List or Empty State ---
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(newsListProvider);
                  ref.invalidate(newsStatusCountsProvider);
                  await ref.read(newsListProvider(null).future);
                },
                child: newsAsync.when(
                  data: (allNews) {
                    final filtered = allNews.where((n) => _matchesFilter(n, _activeFilter)).toList();

                    if (filtered.isEmpty) {
                      return ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.6,
                            child: _buildEmptyState(),
                          ),
                        ],
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        return _buildNewsCard(filtered[index], navyPrimary, navyDark);
                      },
                    );
                  },
                  loading: () => const Center(
                    child: CircularProgressIndicator(color: navyPrimary),
                  ),
                  error: (error, _) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline, size: 48, color: AppColors.statusRejected),
                          const SizedBox(height: 12),
                          Text(
                            'Failed to load news: $error',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 14, color: Color(0xFF64748B)),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () => ref.invalidate(newsListProvider),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: navyPrimary,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Filter chip widget with count pill
  Widget _buildFilterChip(String label, int count) {
    final isSelected = _activeFilter == label;
    const navyPrimary = AppColors.navyPrimary;

    return InkWell(
      onTap: () {
        setState(() {
          _activeFilter = label;
        });
      },
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? navyPrimary : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? Colors.white : const Color(0xFF475569),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: isSelected ? Colors.white.withValues(alpha: 0.25) : Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : const Color(0xFF64748B),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Single news submission card widget
  Widget _buildNewsCard(News news, Color navyPrimary, Color navyDark) {
    return InkWell(
      onTap: () => _showNewsDetails(news),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Category & Status Badge
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: navyPrimary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    news.category.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: navyPrimary,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: news.status.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        radius: 3.5,
                        backgroundColor: news.status.color,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        news.status.displayName,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: news.status.color,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // News Headline
            Text(
              news.headline,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: navyDark,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 8),

            // Location & Media Badges (if present)
            if (news.location.isNotEmpty ||
                news.mediaRegistrationStatus != MediaRegistrationStatus.none)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  children: [
                    if (news.location.isNotEmpty) ...[
                      Icon(
                        Icons.location_on_outlined,
                        size: 13,
                        color: Colors.grey.shade500,
                      ),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          news.location,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (news.mediaRegistrationStatus !=
                        MediaRegistrationStatus.none) ...[
                      Icon(
                        Icons.attachment,
                        size: 13,
                        color: Colors.blue.shade600,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        'Media: ${news.mediaRegistrationStatus.toValue()}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

            // Submission Date and Tracking Code
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today_outlined,
                      size: 13,
                      color: Colors.grey.shade500,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _formatDate(news.submittedAt),
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                Text(
                  news.trackingCode,
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Story details modal sheet showing full review details and locked/edit state
  void _showNewsDetails(News news) {
    final isCorrectionRequested = news.status == NewsStatus.correctionRequested;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Drag Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Tracking Code & Status
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    news.trackingCode,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: AppColors.navyPrimary,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: news.status.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      news.status.displayName,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: news.status.color,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Headline
              Text(
                news.headline,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.navyDark,
                ),
              ),
              const SizedBox(height: 8),

              // Metadata row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      news.category,
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                    ),
                  ),
                  if (news.location.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Icon(Icons.location_on_outlined, size: 13, color: Colors.grey.shade500),
                    const SizedBox(width: 2),
                    Text(
                      news.location,
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                  ],
                  const Spacer(),
                  Text(
                    _formatDate(news.submittedAt),
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                ],
              ),
              const Divider(height: 24),

              // Incident Details
              const Text(
                'Story Content:',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: SingleChildScrollView(
                  child: Text(
                    news.incidentDetails,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Media Status & Attachments Info
              if (news.mediaRegistrationStatus != MediaRegistrationStatus.none ||
                  news.mediaAttachments.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade100),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.attachment, size: 15, color: Colors.blue.shade700),
                      const SizedBox(width: 6),
                      Text(
                        'Media (${news.mediaAttachments.length} attachments): ',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.blue.shade900,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade100,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          news.mediaRegistrationStatus.toValue().toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // Editorial Notice / Correction Box
              if (isCorrectionRequested)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7ED),
                    border: Border.all(color: const Color(0xFFFDBA74)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFEA580C)),
                          SizedBox(width: 6),
                          Text(
                            'Corrections Requested by Editor',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFC2410C),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        news.editorialNotes ??
                            news.rejectionReason ??
                            'The editorial team requested adjustments before publication.',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF9A3412)),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.lock_outline, size: 15, color: Colors.grey.shade600),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Locked for editorial review. Editing is disabled unless corrections are requested.',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),

              // Action Buttons
              if (isCorrectionRequested)
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _loadStoryIntoDraftAndEdit(news);
                    },
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text('Edit & Resubmit Story'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEA580C),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                )
              else
                SizedBox(
                  width: double.infinity,
                  height: 42,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.navyPrimary,
                      side: const BorderSide(color: AppColors.navyPrimary),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Close'),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// Copies submitted story back into an active draft and opens SubmitNewsScreen
  void _loadStoryIntoDraftAndEdit(News news) {
    final draft = NewsDraft(
      id: news.id,
      reporterId: news.reporterId,
      headline: news.headline,
      category: news.category,
      location: news.location,
      incidentDetails: news.incidentDetails,
      mediaAttachments: news.mediaAttachments,
      voiceDispatch: news.voiceDispatch,
      isAiAssisted: news.isAiAssisted,
      lastSavedAt: DateTime.now(),
    );

    ref.read(activeDraftProvider.notifier).selectDraft(draft);

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SubmitNewsScreen()),
    );
  }

  /// Clean empty state widget
  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF0D253F).withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.article_outlined,
                size: 54,
                color: Color(0xFF0D253F),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'No Submissions Found',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Color(0xFF091B2E),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'You have no news submissions in "$_activeFilter".\nField stories will appear here once submitted.',
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
}
