import 'package:flutter/material.dart';
import 'package:journalist_app_1/screens/login_screen.dart';
import 'package:journalist_app_1/screens/main_navigation_screen.dart';

void main() {
  runApp(const JournalistApp());
}

class JournalistApp extends StatelessWidget {
  const JournalistApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Restrained navy-blue and white color scheme matching design system
    const primaryNavy = Color(0xFF0D253F);

    return MaterialApp(
      title: 'Journalist Portal',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryNavy,
          primary: primaryNavy,
        ),
        scaffoldBackgroundColor: const Color(0xFFF7F9FC),
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
