import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:journalist_app_1/core/constants/app_colors.dart';
import 'package:journalist_app_1/providers/auth_provider.dart';
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
      initialRoute: '/',
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/login':
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => const AuthGate(preferLoginWhenUnauthenticated: true),
            );
          case '/':
          case '/portal':
          default:
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => const AuthGate(),
            );
        }
      },
    );
  }
}

/// Authentication gate that validates saved Sanctum sessions against the
/// Laravel backend on startup and blocks unauthenticated access to protected screens.
class AuthGate extends ConsumerStatefulWidget {
  final bool preferLoginWhenUnauthenticated;

  const AuthGate({
    super.key,
    this.preferLoginWhenUnauthenticated = false,
  });

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(authStateProvider.notifier).restoreSession();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);

    if (authState.isValidatingSession) {
      return Scaffold(
        key: const Key('auth_gate_loading'),
        backgroundColor: AppColors.neutralLight,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.navyPrimary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.newspaper_rounded,
                  size: 48,
                  color: AppColors.navyPrimary,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Journalist Portal',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.navyDark,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Checking session...',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 18),
              const CircularProgressIndicator(color: AppColors.navyPrimary),
            ],
          ),
        ),
      );
    }

    if (authState.status == AuthStatus.sessionValidationError) {
      return Scaffold(
        key: const Key('auth_gate_retry_screen'),
        backgroundColor: AppColors.neutralLight,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.statusPending.withValues(
                              alpha: 0.12,
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.wifi_off_rounded,
                            size: 36,
                            color: AppColors.statusPending,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Unable to Verify Session',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.navyDark,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        authState.errorMessage ??
                            'Could not reach the newsroom server. Your session has not been revoked.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        key: const Key('auth_gate_retry_button'),
                        onPressed: () {
                          ref
                              .read(authStateProvider.notifier)
                              .retrySessionValidation();
                        },
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text(
                          'Retry Verification',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.navyPrimary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextButton(
                        key: const Key('auth_gate_use_login_button'),
                        onPressed: () {
                          ref
                              .read(authStateProvider.notifier)
                              .proceedToLogin();
                        },
                        child: const Text(
                          'Sign In with Another Account',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.navyPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (authState.isAuthenticated) {
      return const MainNavigationScreen();
    }

    return const LoginScreen();
  }
}
