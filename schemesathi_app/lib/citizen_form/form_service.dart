import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class CitizenFormData {
  // Step 1: Personal Details
  final String fullName;
  final String dob;
  final String gender;
  final String maritalStatus;

  // Step 2: Residence Details
  final String state;
  final String district;
  final String tehsil;
  final String areaType;
  final String domicileStatus;
  final bool localResidenceOutside;
  final String familyId;

  // Step 3: Occupation & Study
  final String occupation;
  final String studyLevel;
  final String educationCourse;
  final String institutionType;
  final String schoolOrCollegeName;

  // Step 4: Special Eligibility
  final String socialCategory;
  final String casteCertificateStatus;
  final String pwdStatus;
  final String minorityStatus;
  final String incomeCertificateStatus;

  // Step 5: Documents & Review
  final List<String> documents;

  // App settings & backward compatibility
  final String language;
  final String? email;
  final String? clerkUserId;
  final String? annualIncome;
  final String? tenthBoard;
  final String? tenthMarks;
  final String? twelfthBoard;
  final String? twelfthMarks;
  final String? twelfthStream;

  CitizenFormData({
    required this.fullName,
    required this.dob,
    this.gender = 'Male',
    this.maritalStatus = 'Never Married',
    this.state = 'Madhya Pradesh',
    this.district = 'Bhopal',
    this.tehsil = '',
    this.areaType = 'rural',
    this.domicileStatus = 'yes',
    this.localResidenceOutside = false,
    this.familyId = '',
    required this.occupation,
    this.studyLevel = 'College / University',
    this.educationCourse = 'Undergraduate Year 2 (B.Tech / B.Sc / B.A / B.Com)',
    this.institutionType = 'Government',
    this.schoolOrCollegeName = '',
    this.socialCategory = 'General (Unreserved)',
    this.casteCertificateStatus = 'Yes (Available)',
    this.pwdStatus = 'No',
    this.minorityStatus = 'No',
    this.incomeCertificateStatus = 'Yes (Available & Valid)',
    this.documents = const [],
    this.language = 'EN',
    this.email,
    this.clerkUserId,
    this.annualIncome,
    this.tenthBoard,
    this.tenthMarks,
    this.twelfthBoard,
    this.twelfthMarks,
    this.twelfthStream,
  });

  Map<String, dynamic> toJson() {
    return {
      'full_name': fullName,
      'dob': dob,
      'gender': gender,
      'marital_status': maritalStatus,
      'state': state,
      'district': district,
      'tehsil': tehsil,
      'area_type': areaType,
      'domicile_status': domicileStatus,
      'local_residence_outside': localResidenceOutside,
      'family_id': familyId,
      'occupation': occupation,
      'study_level': studyLevel,
      'education_course': educationCourse,
      'institution_type': institutionType,
      'school_or_college_name': schoolOrCollegeName,
      'social_category': socialCategory,
      'caste_certificate_status': casteCertificateStatus,
      'pwd_status': pwdStatus,
      'minority_status': minorityStatus,
      'income_certificate_status': incomeCertificateStatus,
      'documents': documents,
      'language': language,
      if (email != null && email!.isNotEmpty) 'email': email,
      if (clerkUserId != null && clerkUserId!.isNotEmpty) 'clerk_user_id': clerkUserId,
      if (annualIncome != null) 'annual_income': annualIncome,
      if (tenthBoard != null) 'tenth_board': tenthBoard,
      if (tenthMarks != null) 'tenth_marks': tenthMarks,
      if (twelfthBoard != null) 'twelfth_board': twelfthBoard,
      if (twelfthMarks != null) 'twelfth_marks': twelfthMarks,
      if (twelfthStream != null) 'twelfth_stream': twelfthStream,
    };
  }
}

class FormService {
  FormService._();
  static final FormService instance = FormService._();

  static const String defaultLocalHost = '10.154.62.106';

  /// In-memory cache of the user's selected state from the form submission
  static String? cachedUserState;

  static String get baseUrl {
    if (kIsWeb) {
      return 'http://127.0.0.1:8001';
    }

    final envUrl = dotenv.env['BACKEND_URL'];
    if (envUrl != null && envUrl.trim().isNotEmpty) {
      final trimmed = envUrl.trim();
      return trimmed.endsWith('/')
          ? trimmed.substring(0, trimmed.length - 1)
          : trimmed;
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'http://10.154.62.106:8001';
      default:
        return 'http://127.0.0.1:8001';
    }
  }

  /// Checks whether a citizen profile already exists for [email] or locally.
  Future<bool> checkProfile(String email) async {
    // 1. Check local persistent storage for this specific email or any completed profile
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasCompletedEmail = prefs.getBool('profile_completed_${email.trim().toLowerCase()}');
      if (hasCompletedEmail == true) {
        return true;
      }
      final hasCompletedGeneral = prefs.getBool('profile_completed_general');
      if (hasCompletedGeneral == true) {
        return true;
      }
    } catch (_) {}

    // 2. Check remote backend MongoDB
    final url = Uri.parse('$baseUrl/profile').replace(
      queryParameters: {'email': email.trim().toLowerCase()},
    );

    try {
      final res = await http.get(url).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final exists = body['exists'] == true;
        if (exists) {
          // Cache locally for future instant checks
          markProfileCompletedLocally(email: email, state: body['state']);
        }
        return exists;
      }
      return false;
    } catch (_) {
      // If network fails, check if we have any cached state or local profile indicator
      try {
        final prefs = await SharedPreferences.getInstance();
        return prefs.getString('user_state') != null || prefs.getBool('profile_completed_general') == true;
      } catch (_) {
        return false;
      }
    }
  }

  /// Mark the profile completed in SharedPreferences so form never shows again
  Future<void> markProfileCompletedLocally({String? email, String? state}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('profile_completed_general', true);
      if (email != null && email.trim().isNotEmpty) {
        await prefs.setBool('profile_completed_${email.trim().toLowerCase()}', true);
      }
      if (state != null && state.trim().isNotEmpty) {
        await prefs.setString('user_state', state.trim());
        cachedUserState = state.trim();
      }
    } catch (_) {}
  }

  /// Quick check if profile was completed locally on this device
  Future<bool> isProfileCompletedLocally([String? email]) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (email != null && email.trim().isNotEmpty) {
        final emailCompleted = prefs.getBool('profile_completed_${email.trim().toLowerCase()}');
        return emailCompleted == true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Fetches the user profile state from backend (or fallback to cached/last submitted state).
  Future<String?> fetchUserProfileState({String? email, String? name}) async {
    final queryParams = <String, String>{};
    if (email != null && email.trim().isNotEmpty) {
      queryParams['email'] = email.trim();
    } else if (name != null && name.trim().isNotEmpty) {
      queryParams['name'] = name.trim();
    }

    final url = Uri.parse('$baseUrl/profile').replace(queryParameters: queryParams);

    try {
      final res = await http.get(url).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final state = body['state'];
        if (state is String && state.trim().isNotEmpty) {
          return state.trim();
        }
      }
    } catch (_) {}
    return null;
  }

  /// Submits the citizen profile data to the backend.
  Future<Map<String, dynamic>> submitCitizenProfile(
      CitizenFormData data) async {
    final url = Uri.parse('$baseUrl/submit');

    final response = await http
        .post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(data.toJson()),
        )
        .timeout(
          const Duration(seconds: 10),
          onTimeout: () => throw Exception(
              'Connection timed out. Check if backend is running at $baseUrl.'),
        );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception(
        'Server returned ${response.statusCode}: ${response.body}',
      );
    }
  }

  /// Syncs Clerk user identity with MongoDB backend
  Future<Map<String, dynamic>?> syncClerkUser({
    required String clerkUserId,
    required String email,
    String? fullName,
    String? avatarUrl,
  }) async {
    try {
      final url = Uri.parse('$baseUrl/users/sync');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'clerk_user_id': clerkUserId,
          'email': email,
          'full_name': fullName,
          'avatar_url': avatarUrl,
          'provider': 'google',
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('[CitizenFormService] syncClerkUser error: $e');
    }
    return null;
  }

  /// Retrieves the complete citizen profile by clerkUserId or email
  Future<Map<String, dynamic>?> fetchFullProfile({
    String? clerkUserId,
    String? email,
  }) async {
    try {
      final queryParams = <String, String>{};
      if (clerkUserId != null && clerkUserId.trim().isNotEmpty) {
        queryParams['clerk_user_id'] = clerkUserId.trim();
      } else if (email != null && email.trim().isNotEmpty) {
        queryParams['email'] = email.trim();
      }
      final url = Uri.parse('$baseUrl/profiles/me').replace(queryParameters: queryParams);
      final response = await http.get(url).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('[CitizenFormService] fetchFullProfile error: $e');
    }
    return null;
  }

  /// Partially or fully updates citizen profile fields
  Future<Map<String, dynamic>?> updateProfile(Map<String, dynamic> updates) async {
    try {
      final url = Uri.parse('$baseUrl/profiles/me');
      final response = await http.put(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(updates),
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('[CitizenFormService] updateProfile error: $e');
    }
    return null;
  }

  /// Fetches personalized scheme recommendations from eligibility engine
  Future<Map<String, dynamic>?> fetchRecommendations({
    String? clerkUserId,
    String? email,
    String? state,
    int limit = 100,
  }) async {
    try {
      final url = Uri.parse('$baseUrl/eligibility/recommendations');
      final Map<String, dynamic> body = {
        'limit': limit,
        'allow_unapproved': false,
      };
      if (clerkUserId != null) body['clerk_user_id'] = clerkUserId;
      if (email != null) body['email'] = email;
      if (state != null) body['state'] = state;

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('[CitizenFormService] fetchRecommendations error: $e');
    }
    return null;
  }
}
