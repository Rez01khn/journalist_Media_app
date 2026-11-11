import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:journalist_app_1/core/constants/app_colors.dart';
import 'package:journalist_app_1/providers/app_providers.dart';
import 'package:journalist_app_1/screens/drafts_screen.dart';

/// Model representing a sample news item for the Dashboard
class NewsSubmissionItem {
  final String title;
  final String category;
  final String timeAgo;
  final String status;
  final Color statusColor;

  const NewsSubmissionItem({
    required this.title,
    required this.category,
    required this.timeAgo,
    required this.status,
    required this.statusColor,
  });
}

/// The DashboardScreen provides an overview of field reporting activities,
/// quick submission actions, and status tracking for journalists.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  // Local sample mock data for recent submissions
  static const List<NewsSubmissionItem> _mockSubmissions = [
    NewsSubmissionItem(
      title: 'Metro Rail Phase 2 Construction Begins in Motijheel',
      category: 'Infrastructure',
      timeAgo: 'Today, 11:30 AM',
      status: 'Published',
      statusColor: Color(0xFF16A34A), // Green
    ),
    NewsSubmissionItem(
      title: 'Chittagong Port Cargo Handling Breaks Monthly Record',
      category: 'Economy',
      timeAgo: 'Yesterday, 4:15 PM',
      status: 'Pending Review',
      statusColor: Color(0xFFD97706), // Amber
    ),
    NewsSubmissionItem(
      title: 'Dhaka Book Fair 2026 Preparations Enter Final Week',
      category: 'Culture',
      timeAgo: '27 Oct 2026',
      status: 'Draft',
      statusColor: Color(0xFF64748B), // Slate Grey
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const navyPrimary = AppColors.navyPrimary;
    const navyDark = AppColors.navyDark;
    const neutralLight = AppColors.neutralLight;

    final draftCount = ref.watch(draftCountProvider);
    final draftCountText = '$draftCount';

    return Scaffold(
      backgroundColor: neutralLight,
      appBar: AppBar(
        backgroundColor: navyPrimary,
        elevation: 0,
        title: const Text(
          'Journalist Dashboard',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.2,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none_rounded, color: Colors.white),
            tooltip: 'Notifications',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Notifications will be available in a future update.'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // --- Welcome Greeting Header ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Welcome, Reporter',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: navyDark,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Newsroom Field Reporting Portal',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: navyPrimary.withValues(alpha: 0.1),
                    child: const Icon(
                      Icons.person_rounded,
                      color: navyPrimary,
                      size: 26,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // --- Prominent "Submit News" Card ---
              Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0D253F), Color(0xFF1E3A5F)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: navyPrimary.withValues(alpha: 0.25),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.post_add_rounded,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'File Field Story',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Submit breaking news or full reports',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Row(
                                children: [
                                  Icon(Icons.info_outline, color: Colors.white),
                                  SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Navigate to Submit News tab to write field stories.',
                                    ),
                                  ),
                                ],
                              ),
                              backgroundColor: navyPrimary,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: navyPrimary,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
                        label: const Text(
                          'Submit News',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // --- Section: Status Summary ---
              const Text(
                'Submission Status',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: navyDark,
                ),
              ),
              const SizedBox(height: 12),

              // Three Compact Status Summary Cards
              Row(
                children: [
                  Expanded(
                    child: _buildStatusCard(
                      label: 'Drafts',
                      count: draftCountText,
                      icon: Icons.edit_note_rounded,
                      accentColor: const Color(0xFF64748B),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const DraftsScreen()),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildStatusCard(
                      label: 'Pending',
                      count: '4',
                      icon: Icons.hourglass_top_rounded,
                      accentColor: const Color(0xFFD97706),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildStatusCard(
                      label: 'Published',
                      count: '12',
                      icon: Icons.check_circle_outline_rounded,
                      accentColor: const Color(0xFF16A34A),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),

              // --- Section: Recent Submissions ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Recent Submissions',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: navyDark,
                    ),
                  ),
                  Text(
                    'Mock Data',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // List of 2–3 clearly identified sample news items
              ..._mockSubmissions.map((item) => _buildNewsItemCard(item)),
            ],
          ),
        ),
      ),
    );
  }

  /// Compact status summary card widget
  Widget _buildStatusCard({
    required String label,
    required String count,
    required IconData icon,
    required Color accentColor,
    VoidCallback? onTap,
  }) {
    final cardContent = Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: accentColor, size: 22),
          const SizedBox(height: 6),
          Text(
            count,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: accentColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: cardContent,
      );
    }

    return cardContent;
  }

  /// Single news submission card widget
  Widget _buildNewsItemCard(NewsSubmissionItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
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
          // Category and Status Badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D253F).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  item.category.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0D253F),
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: item.statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  item.status,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: item.statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // News Title
          Text(
            item.title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF091B2E),
              height: 1.3,
            ),
          ),
          const SizedBox(height: 8),

          // Timestamp
          Row(
            children: [
              Icon(
                Icons.access_time_rounded,
                size: 13,
                color: Colors.grey.shade500,
              ),
              const SizedBox(width: 4),
              Text(
                item.timeAgo,
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
    );
  }
}
