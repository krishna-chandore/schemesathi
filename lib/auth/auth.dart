import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:clerk_auth/clerk_auth.dart' as clerk;
import 'package:clerk_flutter/clerk_flutter.dart';
// The public config requires this unexported cache interface.
// ignore: implementation_imports
import 'package:clerk_flutter/src/utils/clerk_file_cache.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../citizen_form/form_service.dart';
import '../citizen_form/form.dart';

// ============================================================================
// SchemeSathi - single-file auth module (Clerk, Google-only sign-in).
// Sections: config, theme, service, widgets, help screen, auth screen.
// ============================================================================

// ---------------------------------------------------------------------------
// clerk_config
// ---------------------------------------------------------------------------
/// TEST-ONLY hardcoded Clerk config.
///
/// Before deployment: leave [publishableKey] empty ('') and supply the key via
/// `.env` (CLERK_PUBLISHABLE_KEY=...) or `--dart-define=CLERK_PUBLISHABLE_KEY=...`.
///
/// Only the PUBLISHABLE key belongs in app code. Never put the secret key
/// (sk_...) in a Flutter app.
class ClerkConfig {
  ClerkConfig._();

  static const String publishableKey =
      'pk_test_ZmxleGlibGUtaGF3ay04NjM5LmNsZXJrLmFjY291bnRzLmRldiQ';

  // Informational (not required by the SDK; it derives this from the key).
  static const String frontendApiUrl =
      'https://flexible-hawk-8639.clerk.accounts.dev';
}

// ---------------------------------------------------------------------------
// app_theme
// ---------------------------------------------------------------------------
/// Design tokens and theme definition based on the SchemeSathi Modern Civic Design System.
class AppColors {
  AppColors._();

  // Primary palette (Electric Indigo)
  static const Color primary = Color(0xFF3525CD);
  static const Color primaryContainer = Color(0xFF4F46E5);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color onPrimaryContainer = Color(0xFFDAD7FF);
  static const Color primaryFixed = Color(0xFFE2DFFF);
  static const Color primaryFixedDim = Color(0xFFC3C0FF);
  static const Color onPrimaryFixed = Color(0xFF0F0069);
  static const Color onPrimaryFixedVariant = Color(0xFF3323CC);

  // Secondary palette (Precision Sky)
  static const Color secondary = Color(0xFF006591);
  static const Color secondaryContainer = Color(0xFF39B8FD);
  static const Color onSecondary = Color(0xFFFFFFFF);
  static const Color onSecondaryContainer = Color(0xFF004666);
  static const Color secondaryFixed = Color(0xFFC9E6FF);
  static const Color secondaryFixedDim = Color(0xFF89CEFF);
  static const Color onSecondaryFixed = Color(0xFF001E2F);
  static const Color onSecondaryFixedVariant = Color(0xFF004C6E);

  // Tertiary palette (Verified Mint & Emerald)
  static const Color tertiary = Color(0xFF005338);
  static const Color tertiaryContainer = Color(0xFF006E4B);
  static const Color onTertiary = Color(0xFFFFFFFF);
  static const Color onTertiaryContainer = Color(0xFF67F4B7);
  static const Color tertiaryFixed = Color(0xFF6FFBBE);
  static const Color tertiaryFixedDim = Color(0xFF4EDEA3);
  static const Color onTertiaryFixed = Color(0xFF002113);
  static const Color onTertiaryFixedVariant = Color(0xFF005236);

  // Surfaces & Backgrounds
  static const Color surface = Color(0xFFFAF8FF);
  static const Color background = Color(0xFFFAF8FF);
  static const Color surfaceContainerLowest = Color(0xFFFFFFFF);
  static const Color surfaceContainerLow = Color(0xFFF2F3FF);
  static const Color surfaceContainer = Color(0xFFEAEDFF);
  static const Color surfaceContainerHigh = Color(0xFFE2E7FF);
  static const Color surfaceContainerHighest = Color(0xFFDAE2FD);

  // Neutral typography & Outlines
  static const Color onSurface = Color(0xFF131B2E);
  static const Color onSurfaceVariant = Color(0xFF464555);
  static const Color outline = Color(0xFF777587);
  static const Color outlineVariant = Color(0xFFC7C4D8);

  // Accents
  static const Color amberStar = Color(0xFFF59E0B);
  static const Color emeraldOnlineBg = Color(0xFFD1FAE5);
  static const Color emeraldOnlineText = Color(0xFF065F46);
  static const Color emeraldShieldBg = Color(0xFFECFDF5);
  static const Color emeraldShieldBorder = Color(0xFFA7F3D0);
}

class AppTheme {
  AppTheme._();

  static ThemeData get lightTheme {
    final String fontFamily =
        GoogleFonts.plusJakartaSans().fontFamily ?? 'Plus Jakarta Sans';

    return ThemeData(
      useMaterial3: true,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: AppColors.surface,
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        onPrimary: AppColors.onPrimary,
        primaryContainer: AppColors.primaryContainer,
        onPrimaryContainer: AppColors.onPrimaryContainer,
        secondary: AppColors.secondary,
        onSecondary: AppColors.onSecondary,
        secondaryContainer: AppColors.secondaryContainer,
        onSecondaryContainer: AppColors.onSecondaryContainer,
        tertiary: AppColors.tertiary,
        onTertiary: AppColors.onTertiary,
        surface: AppColors.surface,
        onSurface: AppColors.onSurface,
        onSurfaceVariant: AppColors.onSurfaceVariant,
        outline: AppColors.outline,
        outlineVariant: AppColors.outlineVariant,
      ),
      textTheme: TextTheme(
        headlineLarge: TextStyle(
          fontFamily: fontFamily,
          fontSize: 26,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
          color: AppColors.onSurface,
        ),
        headlineMedium: TextStyle(
          fontFamily: fontFamily,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          color: AppColors.onSurface,
        ),
        titleLarge: TextStyle(
          fontFamily: fontFamily,
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: AppColors.onSurface,
        ),
        titleMedium: TextStyle(
          fontFamily: fontFamily,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.onSurface,
        ),
        titleSmall: TextStyle(
          fontFamily: fontFamily,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.onSurface,
        ),
        bodyLarge: TextStyle(
          fontFamily: fontFamily,
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: AppColors.onSurfaceVariant,
          height: 1.45,
        ),
        bodyMedium: TextStyle(
          fontFamily: fontFamily,
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: AppColors.onSurfaceVariant,
          height: 1.4,
        ),
        bodySmall: TextStyle(
          fontFamily: fontFamily,
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: AppColors.onSurfaceVariant,
          height: 1.35,
        ),
        labelLarge: TextStyle(
          fontFamily: fontFamily,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
          color: AppColors.onSurface,
        ),
        labelMedium: TextStyle(
          fontFamily: fontFamily,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
          color: AppColors.onSurface,
        ),
        labelSmall: TextStyle(
          fontFamily: fontFamily,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
          color: AppColors.onSurfaceVariant,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// clerk_auth_service
// ---------------------------------------------------------------------------
class _PrefsClerkPersistor implements clerk.Persistor {
  SharedPreferences? _prefs;

  @override
  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
  }

  @override
  void terminate() {}

  @override
  Future<T?> read<T>(String key) async {
    _prefs ??= await SharedPreferences.getInstance();
    final raw = _prefs?.getString(key);
    if (raw == null) return null;
    if (T == String) return raw as T;
    try {
      return jsonDecode(raw) as T;
    } catch (_) {
      return raw as T?;
    }
  }

  @override
  Future<void> write<T>(String key, T value) async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs?.setString(key, value is String ? value : jsonEncode(value));
  }

  @override
  Future<void> delete(String key) async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs?.remove(key);
  }
}

class _NoopClerkFileCache implements ClerkFileCache {
  @override
  Future<void> initialize() async {}

  @override
  void terminate() {}

  @override
  Stream<File> stream(
    Uri uri, {
    Duration ttl = ClerkFileCache.defaultTTL,
    Map<String, String>? headers,
  }) => const Stream.empty();
}

/// Google-only authentication on top of Clerk.
///
/// The publishable key is read (in this order) from:
///   1. `--dart-define=CLERK_PUBLISHABLE_KEY=pk_test_...`
///   2. the `.env` asset (`CLERK_PUBLISHABLE_KEY=pk_test_...`)
///   3. the hardcoded test key in clerk_config.dart
class ClerkAuthService extends ChangeNotifier {
  ClerkAuthService._();

  static final ClerkAuthService instance = ClerkAuthService._();

  static const String _definedKey = String.fromEnvironment(
    'CLERK_PUBLISHABLE_KEY',
  );

  bool _isInitialized = false;
  bool _isLoading = false;
  bool _isSignedIn = false;
  String _publishableKey = '';
  String _userName = 'Citizen';
  String? _userEmail;
  String? _errorMessage;

  bool get isInitialized => _isInitialized;
  bool get isLoading => _isLoading;
  bool get isSignedIn => _isSignedIn;
  String get userName => _userName;
  String? get userEmail => _userEmail;
  String? get errorMessage => _errorMessage;
  String get publishableKey => _publishableKey;

  /// A real Clerk key looks like `pk_test_<base64 of "your-domain.clerk.accounts.dev$">`.
  /// Anything else makes the Clerk SDK throw at start-up (= blank white screen),
  /// so we validate it before ever handing it to ClerkAuth.
  bool get hasValidPublishableKey {
    final match = RegExp(r'^pk_(test|live)_(.+)$').firstMatch(_publishableKey);
    if (match == null) return false;
    try {
      final decoded = utf8.decode(
        base64.decode(base64.normalize(match.group(2)!)),
      );
      return decoded.endsWith(r'$') && decoded.contains('.');
    } catch (_) {
      return false;
    }
  }

  Future<void> initialize() async {
    if (_isInitialized) return;

    var key = _definedKey.trim();
    if (key.isEmpty) {
      try {
        await dotenv.load(fileName: '.env', isOptional: true);
        key = dotenv.maybeGet('CLERK_PUBLISHABLE_KEY')?.trim() ?? '';
      } catch (e) {
        debugPrint('[ClerkAuthService] .env not loaded: $e');
      }
    }
    if (key.isEmpty) key = ClerkConfig.publishableKey.trim();
    _publishableKey = key.replaceAll('"', '').replaceAll("'", '');

    if (!hasValidPublishableKey) {
      debugPrint(
        '[ClerkAuthService] CLERK_PUBLISHABLE_KEY missing or invalid. '
        'App will run, but Google sign-in is disabled until a valid key is set.',
      );
    }

    _isInitialized = true;
    notifyListeners();
  }

  /// Only call when [hasValidPublishableKey] is true.

  ClerkAuthConfig createAuthConfig() {
    return ClerkAuthConfig(
      publishableKey: _publishableKey,

      // Enable persistent session storage on web so OAuth redirect doesn't lose state.
      persistor: kIsWeb ? _PrefsClerkPersistor() : null,

      // In web, stay in the same tab instead of launching a new window/tab.
      defaultLaunchMode: LaunchMode.platformDefault,

      // Avoid the default path_provider-based file cache on web.
      fileCache: kIsWeb ? _NoopClerkFileCache() : null,

      // Return to the current page after web OAuth.
      redirectionGenerator: kIsWeb
          ? (BuildContext context, clerk.Strategy strategy) => Uri.base
          : null,
    );
  }

  /// Reads the current Clerk session (e.g. after returning from Google on web).
  /// On web after OAuth redirect, Clerk needs time to hydrate session — retry with delays.
  Future<void> syncUser(BuildContext context) async {
    if (!hasValidPublishableKey) return;

    // Capture authState before any awaits to avoid BuildContext-across-async-gap warning
    ClerkAuthState? authState;
    try {
      authState = ClerkAuth.of(context, listen: false);
    } catch (e) {
      debugPrint('[ClerkAuthService] syncUser: could not get authState: $e');
      return;
    }

    if (kIsWeb && Uri.base.queryParameters.isNotEmpty) {
      try {
        debugPrint('[ClerkAuthService] Parsing web OAuth redirect URI: ${Uri.base}');
        await authState.parseDeepLink(Uri.base);
      } catch (e) {
        debugPrint('[ClerkAuthService] parseDeepLink error: $e');
      }
    }

    const maxRetries = kIsWeb ? 4 : 1;

    for (int attempt = 0; attempt < maxRetries; attempt++) {
      if (attempt > 0) {
        await Future.delayed(Duration(milliseconds: 350 * attempt));
      }

      try {
        try {
          await authState.refreshClient();
        } catch (_) {}

        _applyClerkState(authState);

        // If signed in, success — break out and notify
        if (_isSignedIn) {
          debugPrint('[ClerkAuthService] syncUser signed in on attempt ${attempt + 1}: $_userEmail');
          notifyListeners();
          return;
        }
      } catch (e) {
        debugPrint('[ClerkAuthService] syncUser attempt ${attempt + 1} error: $e');
      }
    }

    debugPrint('[ClerkAuthService] syncUser exhausted retries, email still null');
    notifyListeners();
  }

  Future<bool> signInWithGoogle(BuildContext context) async {
    if (_isLoading) return false;
    _errorMessage = null;

    if (!hasValidPublishableKey) {
      _errorMessage = 'Clerk is not configured. Add a valid CLERK_PUBLISHABLE_KEY (see .env.example).';
      notifyListeners();
      return false;
    }

    _setLoading(true);
    try {
      final authState = ClerkAuth.of(context, listen: false);

      await authState.ssoSignIn(
        context,
        clerk.Strategy.oauthGoogle,
        onError: (clerk.ClerkError error) {
          debugPrint('[ClerkAuthService] SSO error: ${error.message} (${error.code})');
          _errorMessage = error.message;
        },
      );

      // Refresh clerk client and hydrate user email with retries
      for (int i = 0; i < 4; i++) {
        if (i > 0) {
          await Future.delayed(Duration(milliseconds: 300 * i));
        }
        try {
          await authState.refreshClient();
        } catch (re) {
          debugPrint('[ClerkAuthService] refreshClient error: $re');
        }
        _applyClerkState(authState);
        if (_userEmail != null && _userEmail!.isNotEmpty) {
          break;
        }
      }

      debugPrint(
        '[ClerkAuthService] Sign-in complete. Email: $_userEmail, Name: $_userName, SignedIn: $_isSignedIn',
      );
      _setLoading(false);
      notifyListeners();
      return _isSignedIn;
    } catch (e) {
      debugPrint('[ClerkAuthService] Google sign-in failed: $e');
      _errorMessage = e.toString();
      _setLoading(false);
      return false;
    }
  }

  Future<void> signOut(BuildContext context) async {
    _setLoading(true);
    try {
      if (hasValidPublishableKey) {
        await ClerkAuth.of(context, listen: false).signOut();
      }
    } catch (e) {
      debugPrint('[ClerkAuthService] Sign-out error: $e');
    } finally {
      _isSignedIn = false;
      _userName = 'Citizen';
      _userEmail = null;
      _setLoading(false);
    }
  }

  void _applyClerkState(ClerkAuthState authState) {
    // Try multiple paths to get user object
    var user = authState.user;

    if (user == null) {
      try {
        user = authState.client.activeSession?.user;
      } catch (_) {}
    }

    if (user == null) {
      try {
        final sessions = authState.client.sessions;
        if (sessions.isNotEmpty) {
          user = sessions.first.user;
        }
      } catch (_) {}
    }

    _applyUser(user);

    // If activeSession exists, user IS signed in
    if (authState.client.activeSession != null ||
        authState.client.sessions.isNotEmpty) {
      _isSignedIn = true;
    }

    // Fallback 1: session identifier (often the email)
    if (_userEmail == null || _userEmail!.isEmpty) {
      try {
        final pubData = authState.client.activeSession?.publicUserData;
        final id = pubData?.identifier;
        if (id != null && id.contains('@')) {
          _userEmail = id.trim();
          _isSignedIn = true;
          debugPrint('[ClerkAuthService] Email from session identifier: $_userEmail');
        }
        final pubFirst = pubData?.firstName;
        if (pubFirst != null && pubFirst.isNotEmpty) {
          _userName = pubFirst;
        }
      } catch (_) {}
    }

    // Fallback 2: email from first session's user emailAddresses
    if (_userEmail == null || _userEmail!.isEmpty) {
      try {
        final sessions = authState.client.sessions;
        if (sessions.isNotEmpty) {
          final u = sessions.first.user;
          if (u.emailAddresses != null && u.emailAddresses!.isNotEmpty) {
            final e = u.emailAddresses!.first.emailAddress;
            if (e.isNotEmpty) {
              _userEmail = e;
              _isSignedIn = true;
              debugPrint('[ClerkAuthService] Email from first session emailAddresses: $_userEmail');
            }
          }
        }
      } catch (_) {}
    }

    if (_userEmail != null && _userEmail!.isNotEmpty) {
      _isSignedIn = true;
    }
  }

  void _applyUser(clerk.User? user) {
    _isSignedIn = user != null;
    if (user != null) {
      final name = user.firstName ?? user.username;
      if (name != null && name.trim().isNotEmpty) {
        _userName = name.trim();
      }
      String? email = user.email;
      if (email == null || email.isEmpty) {
        final emails = user.emailAddresses;
        if (emails != null && emails.isNotEmpty) {
          email = emails.first.emailAddress;
        }
      }
      if (email != null && email.isNotEmpty) {
        _userEmail = email;
      }
    } else {
      _userName = 'Citizen';
      _userEmail = null;
    }
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}

// ---------------------------------------------------------------------------
// google_logo
// ---------------------------------------------------------------------------
/// Pixel-perfect Google 'G' brand mark rendered via CustomPainter.
/// Does not depend on external assets or internet access.
class GoogleLogo extends StatelessWidget {
  final double size;

  const GoogleLogo({super.key, this.size = 20});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _GoogleLogoPainter()),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final double strokeWidth = w * 0.22;
    final Rect bounds = Rect.fromLTWH(
      strokeWidth / 2,
      strokeWidth / 2,
      w - strokeWidth,
      h - strokeWidth,
    );

    final Paint bluePaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    final Paint greenPaint = Paint()
      ..color = const Color(0xFF34A853)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    final Paint yellowPaint = Paint()
      ..color = const Color(0xFFFBBC05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    final Paint redPaint = Paint()
      ..color = const Color(0xFFEA4335)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    // Red arc: Top
    canvas.drawArc(bounds, -math.pi * 0.75, math.pi * 0.5, false, redPaint);

    // Blue arc: Right
    canvas.drawArc(bounds, -math.pi * 0.25, math.pi * 0.45, false, bluePaint);

    // Green arc: Bottom
    canvas.drawArc(bounds, math.pi * 0.20, math.pi * 0.55, false, greenPaint);

    // Yellow arc: Left
    canvas.drawArc(bounds, math.pi * 0.75, math.pi * 0.5, false, yellowPaint);

    // Blue horizontal bar
    final Paint barPaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.fill;

    final double barHeight = strokeWidth;
    final double barLeft = w * 0.45;
    final double barTop = (h - barHeight) / 2;
    final double barWidth = w * 0.55;

    final RRect barRRect = RRect.fromRectAndCorners(
      Rect.fromLTWH(barLeft, barTop, barWidth, barHeight),
      topRight: Radius.circular(barHeight / 4),
      bottomRight: Radius.circular(barHeight / 4),
    );
    canvas.drawRRect(barRRect, barPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// app_header
// ---------------------------------------------------------------------------
class AppHeader extends StatelessWidget {
  final VoidCallback? onLanguageTap;

  const AppHeader({super.key, this.onLanguageTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // App Identity Brand
        Expanded(
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.bottomLeft,
                    end: Alignment.topRight,
                    colors: [AppColors.primary, AppColors.primaryContainer],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.25),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.shield_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            'SchemeSathi',
                            style: Theme.of(context).textTheme.headlineMedium
                                ?.copyWith(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.3,
                                  color: AppColors.onSurface,
                                ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF10B981)
                                    .withValues(alpha: 0.6),
                                blurRadius: 4,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    Text(
                      'CIVIC AI PLATFORM',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.secondary,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Language Switcher Pill
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap:
                onLanguageTap ??
                () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Language switched / भाषा बदली गई'),
                      duration: Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
            borderRadius: BorderRadius.circular(999),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: AppColors.outlineVariant.withValues(alpha: 0.35),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.translate_rounded,
                    color: AppColors.secondary,
                    size: 16,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'EN / हिंदी',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurface,
                    ),
                  ),
                  const SizedBox(width: 3),
                  const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: AppColors.outline,
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// feature_card
// ---------------------------------------------------------------------------
class FeatureCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBgColor;
  final String title;
  final String badgeText;
  final Color badgeBgColor;
  final Color badgeTextColor;
  final String description;

  const FeatureCard({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.iconBgColor,
    required this.title,
    required this.badgeText,
    required this.badgeBgColor,
    required this.badgeTextColor,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.25),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.onSurface.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: iconBgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.onSurface,
                            ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: badgeBgColor,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        badgeText,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: badgeTextColor,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.onSurfaceVariant,
                    fontSize: 11.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// helpdesk_card
// ---------------------------------------------------------------------------
class HelpdeskCard extends StatelessWidget {
  final VoidCallback? onWhatsAppTap;
  final VoidCallback? onEmailTap;

  const HelpdeskCard({super.key, this.onWhatsAppTap, this.onEmailTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryFixed.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.primaryFixedDim.withValues(alpha: 0.7),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(
                      Icons.support_agent_rounded,
                      color: AppColors.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'SchemeSathi Citizen Helpdesk',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                          color: AppColors.onSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.emeraldOnlineBg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Online',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.emeraldOnlineText,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Still unable to log in? Reach our dedicated support team via WhatsApp or Email.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: AppColors.onSurfaceVariant, fontSize: 11.5),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap:
                        onWhatsAppTap ??
                        () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Opening SchemeSathi WhatsApp Help...',
                              ),
                              duration: Duration(seconds: 2),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.outlineVariant.withValues(
                            alpha: 0.35,
                          ),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.02),
                            blurRadius: 3,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.chat_bubble_outline_rounded,
                            color: Color(0xFF059669),
                            size: 16,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'WhatsApp Help',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap:
                        onEmailTap ??
                        () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Opening support@schemesathi.in...',
                              ),
                              duration: Duration(seconds: 2),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.outlineVariant.withValues(
                            alpha: 0.35,
                          ),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.02),
                            blurRadius: 3,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.mail_outline_rounded,
                            color: AppColors.primary,
                            size: 16,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Email Support',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// responsive_scaffold
// ---------------------------------------------------------------------------
/// Scaffold with soft ambient glows (cheap radial gradients, no BackdropFilter)
/// and a 480px max-width clamp for tablet / web.
class ResponsiveScaffold extends StatelessWidget {
  final Widget body;

  const ResponsiveScaffold({super.key, required this.body});

  Widget _glow(double size, Color color) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Stack(
        children: [
          Positioned(
            top: -100,
            right: -80,
            child: _glow(360, AppColors.primaryFixed.withValues(alpha: 0.8)),
          ),
          Positioned(
            top: height * 0.35,
            left: -110,
            child: _glow(340, AppColors.secondaryFixed.withValues(alpha: 0.7)),
          ),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: body,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// auth_help_screen
// ---------------------------------------------------------------------------
class AuthHelpScreen extends StatefulWidget {
  const AuthHelpScreen({super.key});

  @override
  State<AuthHelpScreen> createState() => _AuthHelpScreenState();
}

class _AuthHelpScreenState extends State<AuthHelpScreen> {
  bool _isConnecting = false;
  final String _btnText = 'Continue with Google';
  final IconData _btnIcon = Icons.arrow_forward_rounded;
  final Color _btnBgColor = AppColors.primaryContainer;


  @override
  Widget build(BuildContext context) {
    return ResponsiveScaffold(
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Top Clean Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLowest,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.outlineVariant.withValues(
                            alpha: 0.35,
                          ),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.arrow_back_rounded,
                        color: AppColors.onSurface,
                        size: 20,
                      ),
                    ),
                  ),
                ),
                Text(
                  'GOOGLE SIGN-IN HELP',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    fontSize: 11,
                    color: AppColors.onSurfaceVariant.withValues(alpha: 0.8),
                  ),
                ),
                const SizedBox(width: 40),
              ],
            ),
            const SizedBox(height: 20),

            // Passwordless Google Security Hero Badge
            Center(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: AppColors.primaryFixed.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppColors.primaryFixedDim.withValues(alpha: 0.8),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: AppColors.outlineVariant.withValues(
                              alpha: 0.3,
                            ),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Center(child: GoogleLogo(size: 26)),
                      ),
                    ),
                  ),

                  // Bottom-right Lock Badge
                  Positioned(
                    bottom: -6,
                    right: -6,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: AppColors.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.surfaceContainerLowest,
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.lock_open_rounded,
                          color: Colors.white,
                          size: 15,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Verified Badge Pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.emeraldShieldBg,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: AppColors.emeraldShieldBorder.withValues(alpha: 0.7),
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.verified_user_rounded,
                    color: AppColors.tertiaryContainer,
                    size: 14,
                  ),
                  SizedBox(width: 5),
                  Text(
                    '100% Passwordless & Secure',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.tertiaryContainer,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Title
            Text(
              'No Password Needed',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: AppColors.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),

            // Subtitle
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.onSurfaceVariant,
                  fontSize: 13,
                  height: 1.45,
                ),
                children: const [
                  TextSpan(text: 'SchemeSathi connects directly with your '),
                  TextSpan(
                    text: 'Google Account',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.onSurface,
                    ),
                  ),
                  TextSpan(
                    text:
                        '. There are no passwords to remember, reset, or leak.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Primary Google Sign-In Action Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.outlineVariant.withValues(alpha: 0.3),
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.onSurface.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.primaryFixed.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.login_rounded,
                          color: AppColors.primary,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'QUICK SIGN-IN',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.onSurfaceVariant,
                                  fontSize: 10.5,
                                  letterSpacing: 0.8,
                                ),
                          ),
                          Text(
                            'Return to SchemeSathi',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.5,
                                  color: AppColors.onSurface,
                                ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Divider(
                    height: 1,
                    thickness: 1,
                    color: Color(0xFFF1F5F9),
                  ),
                  const SizedBox(height: 14),

                  // Google Instant Login Button
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _isConnecting
                          ? null
                          : () async {
                              setState(() => _isConnecting = true);
                              try {
                                final authService = ClerkAuthService.instance;
                                final success = await authService.signInWithGoogle(context);
                                if (!context.mounted) return;
                                if (success || authService.isSignedIn) {
                                  final email = authService.userEmail;
                                  final name = authService.userName;
                                  bool hasProfile = false;
                                  if (email != null && email.isNotEmpty) {
                                    hasProfile = await FormService.instance.checkProfile(email);
                                  } else {
                                    hasProfile = await FormService.instance.isProfileCompletedLocally();
                                  }
                                  if (!context.mounted) return;
                                  if (hasProfile) {
                                    Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false, arguments: name);
                                  } else {
                                    Navigator.of(context).pushAndRemoveUntil(
                                      MaterialPageRoute(builder: (_) => CitizenProfileSetupPage(initialEmail: email)),
                                      (_) => false,
                                    );
                                  }
                                }
                              } finally {
                                if (mounted) setState(() => _isConnecting = false);
                              }
                            },
                      borderRadius: BorderRadius.circular(14),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        height: 48,
                        decoration: BoxDecoration(
                          color: _btnBgColor,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: _btnBgColor.withValues(alpha: 0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 26,
                              height: 26,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                              child: const Center(child: GoogleLogo(size: 15)),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              _btnText,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (_isConnecting &&
                                _btnIcon == Icons.arrow_forward_rounded)
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            else
                              Icon(_btnIcon, color: Colors.white, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Troubleshooting Solutions Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.outlineVariant.withValues(alpha: 0.3),
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.onSurface.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.help_outline_rounded,
                        color: AppColors.primary,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Trouble signing in with Google?',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Tip 1: Switch Account
                  _buildTipCard(
                    icon: Icons.switch_account_rounded,
                    iconColor: AppColors.primary,
                    title: 'Switch or verify your Google Account',
                    description: 'Ensure you choose the specific Gmail/Workspace account linked with your SchemeSathi citizen profile.',
                  ),
                  const SizedBox(height: 10),

                  // Tip 2: Google Recovery
                  _buildTipCard(
                    icon: Icons.security_rounded,
                    iconColor: AppColors.secondary,
                    title: 'Forgot your Google password?',
                    description: "Use Google's official recovery flow to regain access to your Google identity.",
                    actionWidget: InkWell(
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Opening Google Account Recovery (accounts.google.com)...',
                            ),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                      child: const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Open Google Account Recovery',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                            SizedBox(width: 4),
                            Icon(
                              Icons.open_in_new_rounded,
                              size: 13,
                              color: AppColors.primary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Tip 3: Clear Cookies / Cache
                  _buildTipCard(
                    icon: Icons.cached_rounded,
                    iconColor: AppColors.onSurfaceVariant,
                    title: 'Popup blocked or stuck loading?',
                    description: 'Allow popups or clear your default mobile browser cookies to refresh authentication tokens.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Dedicated Helpdesk Card
            const HelpdeskCard(),
            const SizedBox(height: 20),

            // Return to Sign In Screen link
            Center(
              child: TextButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  size: 15,
                  color: AppColors.onSurfaceVariant,
                ),
                label: Text(
                  'Return to Sign In screen',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Footer note
            Center(
              child: Text(
                'SchemeSathi • Civic Portal by Government Support Initiative',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AppColors.onSurfaceVariant.withValues(alpha: 0.7),
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _buildTipCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String description,
    Widget? actionWidget,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.surfaceContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.4,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                ?actionWidget,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// auth_screen
// ---------------------------------------------------------------------------
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isHindi = false;
  bool _isRedirecting = false;

  @override
  void initState() {
    super.initState();
    ClerkAuthService.instance.addListener(_onAuthStateChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) {
        await ClerkAuthService.instance.syncUser(context);
        if (mounted) {
          _checkAndRedirect();
        }
      }
    });
  }

  @override
  void dispose() {
    ClerkAuthService.instance.removeListener(_onAuthStateChanged);
    super.dispose();
  }

  void _onAuthStateChanged() {
    if (mounted) {
      _checkAndRedirect();
    }
  }

  void _checkAndRedirect() {
    final authService = ClerkAuthService.instance;
    if (authService.isSignedIn && !_isRedirecting && mounted) {
      _isRedirecting = true;
      _routeAfterLogin();
    }
  }

  /// Checks if this user already has a profile.
  /// Navigates to /home if yes, /form if no (first-time login only).
  Future<void> _routeAfterLogin() async {
    final authService = ClerkAuthService.instance;
    final email = authService.userEmail;
    final name = authService.userName;

    bool hasProfile = false;
    try {
      if (email != null && email.isNotEmpty) {
        hasProfile = await FormService.instance.checkProfile(email);
      } else {
        hasProfile = await FormService.instance.isProfileCompletedLocally();
      }
    } catch (e) {
      debugPrint('[AuthScreen] Profile check error: $e');
    }

    if (!mounted) return;

    if (hasProfile) {
      // Returning user: go straight to home dashboard
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/home',
        (_) => false,
        arguments: name,
      );
    } else {
      // First-time user: show form setup
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => CitizenProfileSetupPage(initialEmail: email),
        ),
        (_) => false,
      );
    }
  }

  void _navigateToLogin() async {
    final authService = ClerkAuthService.instance;
    final success = await authService.signInWithGoogle(context);
    if (!mounted) return;
    if (success || authService.isSignedIn) {
      _routeAfterLogin();
    } else if (authService.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(authService.errorMessage!),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _handleGuestExplore() async {
    final hasProfile = await FormService.instance.isProfileCompletedLocally();
    if (!mounted) return;
    if (hasProfile) {
      Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
    } else {
      Navigator.of(context).pushNamed('/form');
    }
  }

  void _navigateToHelp() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (context) => const AuthHelpScreen()));
  }

  void _toggleLanguage() {
    setState(() {
      _isHindi = !_isHindi;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isHindi ? 'हिंदी सक्रिय (Hindi Active)' : 'English Active',
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF8FF),
      body: Stack(
        children: [
          // Ambient Cultural Glow Accents
          Positioned(
            top: -96,
            left: -80,
            child: IgnorePointer(
              child: Container(
                width: 288,
                height: 288,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF39B8FD).withValues(alpha: 0.20),
                      const Color(0xFF39B8FD).withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).size.height * 0.25,
            right: -96,
            child: IgnorePointer(
              child: Container(
                width: 320,
                height: 320,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF4EDEA3).withValues(alpha: 0.25),
                      const Color(0xFF4EDEA3).withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).size.height * 0.65,
            left: MediaQuery.of(context).size.width * 0.5 - 192,
            child: IgnorePointer(
              child: Container(
                width: 384,
                height: 384,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFFE2DFFF).withValues(alpha: 0.30),
                      const Color(0xFFE2DFFF).withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),

          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Top App Bar Navigation Area
                      _buildTopBar(),
                      const SizedBox(height: 16),

                      // Hero Visual Stage: Radiant Card with Floating Scheme Pills
                      _buildHeroCard(),
                      const SizedBox(height: 24),

                      // Warm Cultural Greeting & High-Impact Typography
                      _buildWelcomeSection(),
                      const SizedBox(height: 28),

                      // Sticky Bottom Interactive Action Panel
                      _buildActionPanel(),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Brand Micro-Badge: SCHEMESATHI • Civic AI
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFF2F3FF),
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: Color(0xFF3525CD),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'SCHEMESATHI',
                style: TextStyle(
                  fontFamily: 'Plus Jakarta Sans',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: Color(0xFF3525CD),
                ),
              ),
              const Text(
                ' • Civic AI',
                style: TextStyle(
                  fontFamily: 'Plus Jakarta Sans',
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFFC7C4D8),
                ),
              ),
            ],
          ),
        ),

        // Right Controls: Language Selector Pill & Quick Sign In
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Language Pill
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _toggleLanguage,
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.translate_rounded,
                        size: 14,
                        color: Color(0xFF3525CD),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        _isHindi ? 'हि' : 'EN',
                        style: const TextStyle(
                          fontFamily: 'Plus Jakarta Sans',
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF131B2E),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),

            // Quick Sign In Link
            TextButton(
              onPressed: _navigateToLogin,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'Sign In',
                style: TextStyle(
                  fontFamily: 'Plus Jakarta Sans',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF3525CD),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildHeroCard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Mandala & Center Family Image Stage with Floating Pills
          SizedBox(
            height: 220,
            width: double.infinity,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Mandala Geometry Underlay
                CustomPaint(
                  size: const Size(200, 200),
                  painter: _MandalaPainter(),
                ),

                // Background Ambient Glow Rings
                Container(
                  width: 176,
                  height: 176,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFE2E7FF).withValues(alpha: 0.6),
                  ),
                  child: Center(
                    child: Container(
                      width: 144,
                      height: 144,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFE2DFFF).withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                ),

                // Center Image of Happy Family
                Container(
                  width: 144,
                  height: 144,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Image.network(
                      'https://lh3.googleusercontent.com/aida-public/AB6AXuCJwux0oK5cavwdzWWz9vL9nLMXdA8HsVUVFd7o8_Lvlo4jgD0yDxTixjofjBULAMTbGPqxvbZiunBTxaOxVR9hhe7QQJ1KuyKTq6S_CELXqZhAqQXljHUq5tczPndGpkJaEKczRRE2fkm4ELb3W1TBS4InEGA-oEGn5mpNWkrxJnKGQQfvCyI1eNIYBxyn6Cd44yAh5zIjLnIM-jVNIdPqS70rBq02miHgeQ_1kL_FAHMlkUuwTVYzfA',
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          color: const Color(0xFFEAEDFF),
                          child: const Icon(
                            Icons.family_restroom_rounded,
                            size: 64,
                            color: Color(0xFF3525CD),
                          ),
                        );
                      },
                    ),
                  ),
                ),

                // Floating Entitlement Pill 1: PM-Kisan ₹6,000/yr (Top Left)
                Positioned(
                  top: 8,
                  left: 4,
                  child: Transform.rotate(
                    angle: -0.05,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: const Color(0xFF006E4B),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.agriculture_rounded,
                              size: 15,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'PM-Kisan',
                                style: TextStyle(
                                  fontFamily: 'Plus Jakarta Sans',
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF005338),
                                  height: 1.1,
                                ),
                              ),
                              Text(
                                '₹6,000/yr',
                                style: TextStyle(
                                  fontFamily: 'Plus Jakarta Sans',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF131B2E),
                                  height: 1.1,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Floating Entitlement Pill 2: Beti Padhao (Top Right)
                Positioned(
                  top: 14,
                  right: 8,
                  child: Transform.rotate(
                    angle: 0.08,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFF39B8FD),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          const Text(
                            'Beti Padhao',
                            style: TextStyle(
                              fontFamily: 'Plus Jakarta Sans',
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF464555),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Floating Entitlement Pill 3: Mudra Subsidy (Bottom Left)
                Positioned(
                  bottom: 12,
                  left: 10,
                  child: Transform.rotate(
                    angle: -0.08,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.storefront_rounded,
                            size: 13,
                            color: Color(0xFF3525CD),
                          ),
                          SizedBox(width: 5),
                          Text(
                            'Mudra Subsidy',
                            style: TextStyle(
                              fontFamily: 'Plus Jakarta Sans',
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF131B2E),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Floating Entitlement Pill 4: Ayushman ₹5L Cover (Bottom Right)
                Positioned(
                  bottom: 12,
                  right: 4,
                  child: Transform.rotate(
                    angle: 0.04,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: const Color(0xFF4F46E5),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.health_and_safety_rounded,
                              size: 15,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Ayushman',
                                style: TextStyle(
                                  fontFamily: 'Plus Jakarta Sans',
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF3525CD),
                                  height: 1.1,
                                ),
                              ),
                              Text(
                                '₹5L Cover',
                                style: TextStyle(
                                  fontFamily: 'Plus Jakarta Sans',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF131B2E),
                                  height: 1.1,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Real-time Verified Counter Pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFEAEDFF),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Pulsing Green Dot
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFF005338),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: RichText(
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    text: const TextSpan(
                      style: TextStyle(
                        fontFamily: 'Plus Jakarta Sans',
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF131B2E),
                      ),
                      children: [
                        TextSpan(
                          text: '3,240+ ',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF3525CD),
                          ),
                        ),
                        TextSpan(text: 'Schemes Verified for FY 2025'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomeSection() {
    return Column(
      children: [
        // Traditional Namaste Welcome Tag
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFFE2E7FF),
            borderRadius: BorderRadius.circular(999),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('🙏', style: TextStyle(fontSize: 13)),
              SizedBox(width: 5),
              Text(
                'नमस्ते • A WARM WELCOME',
                style: TextStyle(
                  fontFamily: 'Plus Jakarta Sans',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: Color(0xFF3525CD),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Primary Bilingual Anthem
        const Text(
          'Har Nagrik Ka Haq,\nSeedhe Aapke Haath',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Plus Jakarta Sans',
            fontSize: 27,
            fontWeight: FontWeight.w700,
            height: 1.25,
            letterSpacing: -0.4,
            color: Color(0xFF131B2E),
          ),
        ),
        const SizedBox(height: 10),

        // Conversational, Jargon-Free Subtitle
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            "India's first citizen-friendly AI platform. Uncover eligible welfare, scholarships, and grants tailored to your family within 60 seconds.",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Plus Jakarta Sans',
              fontSize: 13.5,
              fontWeight: FontWeight.w400,
              height: 1.45,
              color: Color(0xFF464555),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionPanel() {
    return Column(
      children: [
        // Primary CTA: Get Started / शुरू करें
        ListenableBuilder(
          listenable: ClerkAuthService.instance,
          builder: (context, _) {
            final authService = ClerkAuthService.instance;
            final isLoading = authService.isLoading;

            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _navigateToLogin,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: double.infinity,
                  height: 52,
                  decoration: BoxDecoration(
                    color: const Color(0xFF4F46E5),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF4F46E5).withValues(alpha: 0.35),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: isLoading
                            ? const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 10),
                                  Text(
                                    'Connecting...',
                                    style: TextStyle(
                                      fontFamily: 'Plus Jakarta Sans',
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.fingerprint_rounded,
                                    size: 20,
                                    color: Colors.white,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Get Started / शुरू करें',
                                    style: TextStyle(
                                      fontFamily: 'Plus Jakarta Sans',
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Icon(
                                    Icons.arrow_forward_rounded,
                                    size: 18,
                                    color: Colors.white,
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 10),

        // Secondary Guest / Instant Exploration Option
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _handleGuestExplore,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: double.infinity,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFFF2F3FF),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.explore_rounded,
                        size: 17,
                        color: Color(0xFF3525CD),
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Explore 3,200+ Schemes as Guest',
                        style: TextStyle(
                          fontFamily: 'Plus Jakarta Sans',
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF131B2E),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Need Help? Quick link
        TextButton(
          onPressed: _navigateToHelp,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text(
            'Trouble signing in? Need Help?',
            style: TextStyle(
              fontFamily: 'Plus Jakarta Sans',
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: Color(0xFF777587),
            ),
          ),
        ),
        const SizedBox(height: 6),

        // Micro Civic Footer
        const Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          children: [
            Icon(
              Icons.enhanced_encryption_rounded,
              size: 13,
              color: Color(0xFF777587),
            ),
            Text(
              'Digital India Compliant • 256-Bit Bank-Grade Encryption',
              style: TextStyle(
                fontFamily: 'Plus Jakarta Sans',
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.1,
                color: Color(0xFF464555),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Mandala geometry painter for decorative underlay
// ---------------------------------------------------------------------------
class _MandalaPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF131B2E).withValues(alpha: 0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final center = Offset(size.width / 2, size.height / 2);

    canvas.drawCircle(center, 80, paint);
    canvas.drawCircle(center, 55, paint);
    canvas.drawCircle(center, 30, paint);

    final path = Path()
      ..moveTo(center.dx, center.dy - 80)
      ..lineTo(center.dx + 80, center.dy)
      ..lineTo(center.dx, center.dy + 80)
      ..lineTo(center.dx - 80, center.dy)
      ..close();
    canvas.drawPath(path, paint);

    final path2 = Path()
      ..moveTo(center.dx, center.dy - 65)
      ..lineTo(center.dx + 65, center.dy)
      ..lineTo(center.dx, center.dy + 65)
      ..lineTo(center.dx - 65, center.dy)
      ..close();
    canvas.drawPath(path2, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
