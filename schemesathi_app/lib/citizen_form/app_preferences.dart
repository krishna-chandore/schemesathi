import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'form_service.dart';

/// Centralized state and preference controller for SchemeSathi.
/// Synchronizes language and state across Home, Profile, Form, and Header.
class AppPreferences extends ChangeNotifier {
  AppPreferences._();
  static final AppPreferences instance = AppPreferences._();

  static const List<String> supportedLanguages = [
    'English',
    'हिन्दी',
    'मराठी',
    'বাংলা',
    'ગુજરાતી',
    'தமிழ்',
  ];

  static const List<String> supportedStates = [
    'Andhra Pradesh',
    'Arunachal Pradesh',
    'Assam',
    'Bihar',
    'Chhattisgarh',
    'Goa',
    'Gujarat',
    'Haryana',
    'Himachal Pradesh',
    'Jharkhand',
    'Karnataka',
    'Kerala',
    'Madhya Pradesh',
    'Maharashtra',
    'Manipur',
    'Meghalaya',
    'Mizoram',
    'Nagaland',
    'Odisha',
    'Punjab',
    'Rajasthan',
    'Sikkim',
    'Tamil Nadu',
    'Telangana',
    'Tripura',
    'Uttar Pradesh',
    'Uttarakhand',
    'West Bengal',
    'Delhi (NCT)',
    'Jammu and Kashmir',
    'Ladakh',
  ];

  String _currentLanguage = 'English';
  String _currentState = 'Madhya Pradesh';
  bool _initialized = false;

  String get currentLanguage => _currentLanguage;
  String get currentState => _currentState;
  bool get isInitialized => _initialized;

  /// Loads cached language and state from local persistent storage (and remote profile if available)
  Future<void> initialize({String? email, String? clerkUserId}) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final savedLang = prefs.getString('app_language');
      if (savedLang != null && savedLang.isNotEmpty) {
        _currentLanguage = savedLang;
      }

      final savedState = prefs.getString('user_state');
      if (savedState != null && savedState.isNotEmpty) {
        _currentState = savedState;
        FormService.cachedUserState = savedState;
      }

      // Check remote profile if user is logged in
      if ((email != null && email.isNotEmpty) || (clerkUserId != null && clerkUserId.isNotEmpty)) {
        final profile = await FormService.instance.fetchFullProfile(
          clerkUserId: clerkUserId,
          email: email,
        );
        if (profile != null) {
          final pState = profile['state']?.toString().trim();
          if (pState != null && pState.isNotEmpty && supportedStates.contains(pState)) {
            _currentState = pState;
            FormService.cachedUserState = pState;
            await prefs.setString('user_state', pState);
          }

          final pLang = profile['language']?.toString().trim();
          if (pLang != null && pLang.isNotEmpty) {
            _currentLanguage = pLang;
            await prefs.setString('app_language', pLang);
          }
        }
      }
    } catch (e) {
      debugPrint('[AppPreferences] initialize error: $e');
    } finally {
      _initialized = true;
      notifyListeners();
    }
  }

  /// Sets and persists application language
  Future<void> setLanguage(String language, {String? email, String? clerkUserId}) async {
    if (_currentLanguage == language) return;
    _currentLanguage = language;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('app_language', language);

      // Sync with backend if user has session or email
      if ((email != null && email.isNotEmpty) || (clerkUserId != null && clerkUserId.isNotEmpty)) {
        await FormService.instance.updateProfile({
          if (clerkUserId != null && clerkUserId.isNotEmpty) 'clerk_user_id': clerkUserId,
          if (email != null && email.isNotEmpty) 'email': email,
          'language': language,
        });
      }
    } catch (e) {
      debugPrint('[AppPreferences] setLanguage persist error: $e');
    }
  }

  /// Sets and persists user state, syncing with backend and SharedPreferences
  Future<void> setStateName(String stateName, {String? email, String? clerkUserId}) async {
    if (_currentState == stateName) return;
    _currentState = stateName;
    FormService.cachedUserState = stateName;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_state', stateName);

      // Sync with backend
      if ((email != null && email.isNotEmpty) || (clerkUserId != null && clerkUserId.isNotEmpty)) {
        await FormService.instance.updateProfile({
          if (clerkUserId != null && clerkUserId.isNotEmpty) 'clerk_user_id': clerkUserId,
          if (email != null && email.isNotEmpty) 'email': email,
          'state': stateName,
        });
      }
    } catch (e) {
      debugPrint('[AppPreferences] setStateName persist error: $e');
    }
  }
}
