import 'dart:async';

import 'package:clerk_flutter/clerk_flutter.dart';
import 'package:flutter/material.dart';

import 'auth/auth.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Show errors on screen instead of a silent blank page.
    ErrorWidget.builder = (details) => Material(
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Text(
                'Something went wrong:\n\n${details.exceptionAsString()}',
                style: const TextStyle(color: Colors.red, fontSize: 13),
              ),
            ),
          ),
        );

    await ClerkAuthService.instance.initialize();
    runApp(const SchemeSathiApp());
  }, (error, stack) => debugPrint('Uncaught: $error\n$stack'));
}

class SchemeSathiApp extends StatelessWidget {
  const SchemeSathiApp({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = ClerkAuthService.instance;

    return MaterialApp(
      title: 'SchemeSathi - Civic AI Platform',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      // ClerkAuth sits below MaterialApp (Localizations/Overlay available) and
      // above every route. It is only mounted when the key is valid, because an
      // invalid key crashes the SDK on start-up.
      builder: (context, child) {
        final content = child ?? const SizedBox.shrink();
        if (!auth.hasValidPublishableKey) return content;
        return ClerkAuth(config: auth.createAuthConfig(), child: content);
      },
      initialRoute: '/',
      routes: {
        '/': (context) => const AuthScreen(),
        '/help': (context) => const AuthHelpScreen(),
      },
    );
  }
}