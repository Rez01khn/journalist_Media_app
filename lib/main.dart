import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:journalist_app_1/core/constants/app_colors.dart';
import 'package:journalist_app_1/screens/login_screen.dart';
import 'package:journalist_app_1/screens/main_navigation_screen.dart';

void main() {
  runApp(
    const ProviderScope(
      child: JournalistApp(),
    ),
  );
}

class JournalistApp extends StatelessWidget {
  const JournalistApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Journalist Portal',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.navyPrimary,
          primary: AppColors.navyPrimary,
        ),
        scaffoldBackgroundColor: AppColors.neutralLight,
      ),
      // Set initialRoute to MainNavigationScreen for easy multi-tab inspection,
      // keeping LoginScreen cleanly separated outside the bottom navigation bar.
      initialRoute: '/',
      routes: {
        '/': (context) => const MainNavigationScreen(),
        '/login': (context) => const LoginScreen(),
      },
    );
  }
}
