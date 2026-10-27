import 'package:clerk_flutter/clerk_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'auth/auth.dart';
import 'citizen_form/form.dart';
import 'citizen_form/form_service.dart';
import 'home/home_page.dart';
import 'profile/profile_page.dart';
import 'schemes/schemes_page.dart';

// ---------------------------------------------------------------------------
// 2. LOGIN PAGE (Step 2 in flow: Get Started -> Gmail Login -> Citizen Form)
// ---------------------------------------------------------------------------
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _isLoading = false;
  bool _isRedirecting = false;

  @override
  void initState() {
    super.initState();
    ClerkAuthService.instance.addListener(_onAuthStateChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final authService = ClerkAuthService.instance;
      if (kIsWeb) {
        await authService.syncUser(context);
      }
      if (authService.isSignedIn && mounted && !_isRedirecting) {
        _isRedirecting = true;
        _proceedAfterLogin(authService.userEmail, authService.userName);
      }
    });
  }

  @override
  void dispose() {
    ClerkAuthService.instance.removeListener(_onAuthStateChanged);
    super.dispose();
  }

  void _onAuthStateChanged() {
    final authService = ClerkAuthService.instance;
    if (authService.isSignedIn && mounted && !_isRedirecting) {
      _isRedirecting = true;
      _proceedAfterLogin(authService.userEmail, authService.userName);
    }
  }

  void _proceedToForm([String? email]) {
    Navigator.pushNamed(context, '/form', arguments: email);
  }

  void _proceedAfterLogin([String? email, String? name]) async {
    bool hasProfile = false;
    try {
      if (email != null && email.isNotEmpty) {
        hasProfile = await FormService.instance.checkProfile(email);
      } else {
        hasProfile = await FormService.instance.isProfileCompletedLocally();
      }
    } catch (_) {}

    if (!mounted) return;

    if (hasProfile) {
      // Returning user: go straight to home
      Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false, arguments: name);
    } else {
      // First-time user: show form
      Navigator.pushNamed(context, '/form', arguments: email);
    }
  }

  void _handleGoogleLogin() async {
    setState(() => _isLoading = true);
    try {
      final authService = ClerkAuthService.instance;
      final success = await authService.signInWithGoogle(context);

      if (!mounted) return;

      if (success || authService.isSignedIn) {
        final email = authService.userEmail;
        final name = authService.userName;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text('Welcome, $name! Authenticated with Google.')),
              ],
            ),
            backgroundColor: AppColors.primaryContainer,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 2),
          ),
        );
        _proceedAfterLogin(email, name);
      } else if (authService.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(authService.errorMessage!),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('[LoginPage] Sign in error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sign in failed: $e'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF8FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFAF8FF),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF131B2E)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Citizen Login',
          style: TextStyle(
            color: Color(0xFF131B2E),
            fontSize: 18,
            fontWeight: FontWeight.bold,
            fontFamily: 'Plus Jakarta Sans',
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              // App / Shield Icon
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAEDFF),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF4F46E5).withValues(alpha: 0.12),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(
                    Icons.shield_rounded,
                    color: Color(0xFF3525CD),
                    size: 38,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              const Text(
                'Citizen Sign-In',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF131B2E),
                  fontFamily: 'Plus Jakarta Sans',
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'नागरिक लॉगिन',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF4F46E5),
                  fontFamily: 'Plus Jakarta Sans',
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Authenticate securely with your Gmail account to verify your identity and view government welfare schemes.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF464555),
                  height: 1.5,
                  fontFamily: 'Plus Jakarta Sans',
                ),
              ),
              const SizedBox(height: 36),

              // Dedicated Gmail / Google Sign-In Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFFC7C4D8).withValues(alpha: 0.35),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE2DFFF).withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.mail_lock_rounded,
                            color: Color(0xFF3525CD),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'ONE-CLICK GOOGLE LOGIN',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF4F46E5),
                                  letterSpacing: 0.8,
                                  fontFamily: 'Plus Jakarta Sans',
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Use your Gmail Address',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF131B2E),
                                  fontFamily: 'Plus Jakarta Sans',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
                    const SizedBox(height: 20),

                    // Google Login Action Button
                    ElevatedButton(
                      onPressed: _isLoading ? null : _handleGoogleLogin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF131B2E),
                        side: const BorderSide(color: Color(0xFFE2E8F0), width: 1.5),
                        minimumSize: const Size(double.infinity, 54),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 1,
                        shadowColor: Colors.black.withValues(alpha: 0.06),
                      ),
                      child: _isLoading
                          ? const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4F46E5)),
                                  ),
                                ),
                                SizedBox(width: 12),
                                Flexible(
                                  child: Text(
                                    'Connecting to Google...',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w600,
                                      fontFamily: 'Plus Jakarta Sans',
                                      color: Color(0xFF131B2E),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                GoogleLogo(size: 20),
                                SizedBox(width: 12),
                                Flexible(
                                  child: Text(
                                    'Continue with Google (Gmail)',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      fontFamily: 'Plus Jakarta Sans',
                                      color: Color(0xFF131B2E),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Security & Privacy note
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFFA7F3D0).withValues(alpha: 0.8),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.verified_user_rounded,
                      color: Color(0xFF006E4B),
                      size: 20,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Passwordless & Secure. Your credentials remain private and protected under Clerk Auth.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF005338),
                          fontFamily: 'Plus Jakarta Sans',
                          fontWeight: FontWeight.w500,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Direct Link to Citizen Profile Form for test / quick access
              TextButton.icon(
                onPressed: () => _proceedToForm(),
                icon: const Icon(Icons.arrow_forward_rounded, size: 16, color: Color(0xFF4F46E5)),
                label: const Text(
                  'Skip login & open Citizen Profile Form',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF4F46E5),
                    fontFamily: 'Plus Jakarta Sans',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Main Application
// ---------------------------------------------------------------------------
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ClerkAuthService.instance.initialize();
  runApp(const SchemeSathiApp());
}

class SchemeSathiApp extends StatelessWidget {
  const SchemeSathiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SchemeSathi - Civic AI Platform',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      builder: (context, child) {
        final content = child ?? const SizedBox.shrink();
        final auth = ClerkAuthService.instance;
        if (!auth.hasValidPublishableKey) return content;
        return ClerkAuth(
          config: auth.createAuthConfig(),
          child: content,
        );
      },
      initialRoute: '/',
      routes: {
        // Step 1: Get Started / Hero Page
        '/': (context) => const AuthScreen(),
        // Step 2: Gmail Login Interface
        '/login': (context) => const LoginPage(),
        // Step 3: Exact Form Design
        '/form': (context) {
          final email = ModalRoute.of(context)?.settings.arguments as String?;
          return CitizenProfileSetupPage(initialEmail: email);
        },
        // Step 4: Home Dashboard
        '/home': (context) {
          final name = ModalRoute.of(context)?.settings.arguments as String?;
          return SchemeSathiHomePage(userName: name);
        },
        // Step 5: Profile Page
        '/profile': (context) {
          final name = ModalRoute.of(context)?.settings.arguments as String?;
          return SchemeSathiProfilePage(userName: name);
        },
        // Step 6: Schemes Discovery Page
        '/schemes': (context) => const SchemeSathiSchemesPage(),
      },
    );
  }
}
