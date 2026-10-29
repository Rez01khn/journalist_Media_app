import 'package:flutter/material.dart';

/// Model representing a journalist's submitted news story
class MyNewsItem {
  final String id;
  final String headline;
  final String category;
  final String submittedDate;
  final String status;
  final Color statusColor;

  const MyNewsItem({
    required this.id,
    required this.headline,
    required this.category,
    required this.submittedDate,
    required this.status,
    required this.statusColor,
  });
}

/// The MyNewsScreen displays a list of field news stories submitted by the journalist,
/// including category, timestamp, and status badges (Pending, Approved, Published, Rejected).
class MyNewsScreen extends StatefulWidget {
  const MyNewsScreen({super.key});

  @override
  State<MyNewsScreen> createState() => _MyNewsScreenState();
}

class _MyNewsScreenState extends State<MyNewsScreen> {
  // Filter options for news items
  String _activeFilter = 'All';

  // Local sample mock data representing submissions with all 4 required statuses
  static const List<MyNewsItem> _mockSubmissions = [
    MyNewsItem(
      id: 'REP-101',
      headline: 'Metro Rail Phase 2 Work Gains Momentum Across South Dhaka',
      category: 'Infrastructure',
      submittedDate: '29 Oct 2026, 11:30 AM',
      status: 'Published',
      statusColor: Color(0xFF16A34A), // Green
    ),
    MyNewsItem(
      id: 'REP-102',
      headline: 'Chittagong Port Breaks Monthly Container Handling Record',
      category: 'Economy',
      submittedDate: '28 Oct 2026, 04:15 PM',
      status: 'Approved',
      statusColor: Color(0xFF0284C7), // Blue
    ),
    MyNewsItem(
      id: 'REP-103',
      headline: 'Inter-District Highway Safety Improvements Initiated',
      category: 'National',
      submittedDate: '27 Oct 2026, 09:20 AM',
      status: 'Pending',
      statusColor: Color(0xFFD97706), // Amber
    ),
    MyNewsItem(
      id: 'REP-104',
      headline: 'Unverified Spot Report on Warehouse Fire in Old Town',
      category: 'Crime',
      submittedDate: '25 Oct 2026, 08:05 PM',
      status: 'Rejected',
      statusColor: Color(0xFFDC2626), // Red
    ),
  ];

  // Filtered list based on active filter
  List<MyNewsItem> get _filteredSubmissions {
    if (_activeFilter == 'All') {
      return _mockSubmissions;
    }
    return _mockSubmissions
        .where((item) => item.status.toLowerCase() == _activeFilter.toLowerCase())
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    const navyPrimary = Color(0xFF0D253F);
    const navyDark = Color(0xFF091B2E);
    const neutralLight = Color(0xFFF7F9FC);

    final displayList = _filteredSubmissions;

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
      ),
      body: SafeArea(
        child: Column(
          children: [
            // --- Top Filter Bar ---
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Colors.white,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildFilterChip('All', _mockSubmissions.length),
                    const SizedBox(width: 8),
                    _buildFilterChip(
                      'Pending',
                      _mockSubmissions.where((i) => i.status == 'Pending').length,
                    ),
                    const SizedBox(width: 8),
                    _buildFilterChip(
                      'Approved',
                      _mockSubmissions.where((i) => i.status == 'Approved').length,
                    ),
                    const SizedBox(width: 8),
                    _buildFilterChip(
                      'Published',
                      _mockSubmissions.where((i) => i.status == 'Published').length,
                    ),
                    const SizedBox(width: 8),
                    _buildFilterChip(
                      'Rejected',
                      _mockSubmissions.where((i) => i.status == 'Rejected').length,
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0)),

            // --- Submissions List or Empty State ---
            Expanded(
              child: displayList.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 16.0,
                      ),
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: displayList.length,
                      itemBuilder: (context, index) {
                        return _buildNewsCard(displayList[index], navyPrimary, navyDark);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Compact filter chip widget
  Widget _buildFilterChip(String label, int count) {
    final isSelected = _activeFilter == label;
    const navyPrimary = Color(0xFF0D253F);

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
  Widget _buildNewsCard(MyNewsItem item, Color navyPrimary, Color navyDark) {
    return Container(
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
          // Header: Category Badge and Status Badge
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
                  item.category.toUpperCase(),
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
                  color: item.statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 3.5,
                      backgroundColor: item.statusColor,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      item.status,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: item.statusColor,
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
            item.headline,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: navyDark,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),

          // Submission Date and Tracking ID
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
                    item.submittedDate,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              Text(
                item.id,
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: Colors.grey.shade400,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
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

