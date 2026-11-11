import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:journalist_app_1/providers/draft_sync_provider.dart';
import 'package:journalist_app_1/screens/dashboard_screen.dart';
import 'package:journalist_app_1/screens/my_news_screen.dart';
import 'package:journalist_app_1/screens/profile_screen.dart';
import 'package:journalist_app_1/screens/submit_news_screen.dart';

/// MainNavigationScreen acts as the primary app shell, providing bottom navigation
/// across the four core field-reporting destinations while keeping Login outside.
class MainNavigationScreen extends ConsumerStatefulWidget {
  final int initialIndex;

  const MainNavigationScreen({
    super.key,
    this.initialIndex = 0,
  });

  @override
  ConsumerState<MainNavigationScreen> createState() =>
      _MainNavigationScreenState();
}

class _MainNavigationScreenState extends ConsumerState<MainNavigationScreen>
    with WidgetsBindingObserver {
  late int _currentIndex;

  // The four core destinations required by Task 9
  final List<Widget> _screens = const [
    DashboardScreen(),
    SubmitNewsScreen(),
    MyNewsScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(draftSyncServiceProvider);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      ref.read(draftSyncServiceProvider).syncAllPendingDrafts();
    }
  }

  void _onDestinationSelected(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    const navyPrimary = Color(0xFF0D253F);
    const navyDark = Color(0xFF091B2E);

    return Scaffold(
      // IndexedStack preserves state and scroll positions of each screen when switching
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(
              color: Colors.grey.shade200,
              width: 1,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: NavigationBarTheme(
          data: NavigationBarThemeData(
            backgroundColor: Colors.white,
            indicatorColor: navyPrimary.withValues(alpha: 0.12),
            labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>(
              (Set<WidgetState> states) {
                if (states.contains(WidgetState.selected)) {
                  return const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: navyDark,
                  );
                }
                return TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade600,
                );
              },
            ),
            iconTheme: WidgetStateProperty.resolveWith<IconThemeData>(
              (Set<WidgetState> states) {
                if (states.contains(WidgetState.selected)) {
                  return const IconThemeData(
                    color: navyPrimary,
                    size: 24,
                  );
                }
                return IconThemeData(
                  color: Colors.grey.shade600,
                  size: 22,
                );
              },
            ),
          ),
          child: NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: _onDestinationSelected,
            elevation: 0,
            height: 65,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard_rounded),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.post_add_outlined),
                selectedIcon: Icon(Icons.post_add_rounded),
                label: 'Submit News',
              ),
              NavigationDestination(
                icon: Icon(Icons.article_outlined),
                selectedIcon: Icon(Icons.article_rounded),
                label: 'My News',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline_rounded),
                selectedIcon: Icon(Icons.person_rounded),
                label: 'Profile',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

