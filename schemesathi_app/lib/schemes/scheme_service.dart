import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import 'scheme_model.dart';

/// Service responsible for fetching real government schemes from SchemeSathi MongoDB backend.
class SchemeService {
  SchemeService._();
  static final SchemeService instance = SchemeService._();

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

  /// Fetches schemes stored in MongoDB via the backend `/schemes` endpoint.
  /// Falls back to default schemes if the backend is unreachable.
  Future<List<SchemeItem>> fetchSchemes({
    String? state,
    int limit = 200,
    int skip = 0,
  }) async {
    try {
      final queryParams = <String, String>{
        'limit': limit.toString(),
        'skip': skip.toString(),
      };
      if (state != null && state.trim().isNotEmpty && state.trim().toLowerCase() != 'all') {
        queryParams['state'] = state.trim();
      }

      final uri = Uri.parse('$baseUrl/schemes').replace(queryParameters: queryParams);
      final response = await http.get(uri).timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        // Run json decoding in compute background isolate to prevent UI thread frame drops
        final List<SchemeItem> fetched = await compute(_parseSchemesInBackground, response.bodyBytes);
        if (fetched.isNotEmpty) {
          return fetched;
        }
      }
    } catch (e) {
      debugPrint('SchemeService.fetchSchemes failed: $e');
    }

    // Graceful fallback to verified schemes if backend server isn't reachable
    return SchemeItem.getDefaultSchemes();
  }

  /// Fetches personalized scheme recommendations from /eligibility/recommendations
  /// Returning categorized results: eligible, needs_more_information, application_closed, ineligible.
  Future<Map<String, List<SchemeItem>>> fetchPersonalizedRecommendations({
    String? clerkUserId,
    String? sessionToken,
    String? email,
    String? state,
    int limit = 100,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/eligibility/recommendations');
      final headers = <String, String>{
        'Content-Type': 'application/json',
      };
      if (sessionToken != null && sessionToken.isNotEmpty) {
        headers['Authorization'] = 'Bearer $sessionToken';
      }

      final Map<String, dynamic> body = {
        'limit': limit,
        'allow_unapproved': false,
      };
      if (clerkUserId != null) body['clerk_user_id'] = clerkUserId;
      if (email != null) body['email'] = email;
      if (state != null && state != 'All States') body['state'] = state;

      final response = await http
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
        final Map<String, List<SchemeItem>> result = {
          'eligible': [],
          'needs_more_information': [],
          'application_closed': [],
          'ineligible': [],
        };

        for (final key in result.keys) {
          final list = data[key];
          if (list is List) {
            for (final item in list) {
              if (item is Map<String, dynamic>) {
                result[key]!.add(SchemeItem.fromJson(item));
              }
            }
          }
        }
        return result;
      }
    } catch (e) {
      debugPrint('SchemeService.fetchPersonalizedRecommendations failed: $e');
    }
    return {};
  }

  /// Fetches upcoming milestones & reminders for a citizen
  Future<List<Map<String, dynamic>>> fetchUpcomingMilestones({
    String? email,
    String? clerkUserId,
  }) async {
    try {
      final queryParams = <String, String>{};
      if (email != null && email.isNotEmpty) queryParams['email'] = email;
      if (clerkUserId != null && clerkUserId.isNotEmpty) queryParams['clerk_user_id'] = clerkUserId;

      final uri = Uri.parse('$baseUrl/upcoming-milestones').replace(queryParameters: queryParams);
      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final raw = data['milestones'];
        if (raw is List) {
          return raw.cast<Map<String, dynamic>>();
        }
      }
    } catch (e) {
      debugPrint('SchemeService.fetchUpcomingMilestones failed: $e');
    }
    return [];
  }

  /// Fetches the newest schemes added to the platform from /schemes/latest
  Future<List<SchemeItem>> fetchLatestSchemes({String? state, int limit = 10}) async {
    try {
      final queryParams = <String, String>{
        'limit': limit.toString(),
      };
      if (state != null && state.trim().isNotEmpty && state.trim().toLowerCase() != 'all' && state.trim().toLowerCase() != 'all states') {
        queryParams['state'] = state.trim();
      }

      final uri = Uri.parse('$baseUrl/schemes/latest').replace(queryParameters: queryParams);
      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<SchemeItem> fetched = await compute(_parseSchemesInBackground, response.bodyBytes);
        if (fetched.isNotEmpty) {
          return fetched;
        }
      }
    } catch (e) {
      debugPrint('SchemeService.fetchLatestSchemes failed: $e');
    }
    return [];
  }

  static List<SchemeItem> _parseSchemesInBackground(Uint8List bodyBytes) {
    try {
      final Map<String, dynamic> body = jsonDecode(utf8.decode(bodyBytes));
      final dynamic rawList = body['schemes'];
      if (rawList is List && rawList.isNotEmpty) {
        final List<SchemeItem> fetched = [];
        for (final item in rawList) {
          if (item is Map<String, dynamic>) {
            try {
              fetched.add(SchemeItem.fromJson(item));
            } catch (_) {}
          }
        }
        return fetched;
      }
    } catch (e) {
      debugPrint('Error parsing schemes in background: $e');
    }
    return [];
  }

  /// Fetches the list of states present in the database.
  Future<List<String>> fetchStates() async {
    try {
      final uri = Uri.parse('$baseUrl/schemes/states');
      final response = await http.get(uri).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final body = jsonDecode(utf8.decode(response.bodyBytes));
        final dynamic rawStates = body['states'];
        if (rawStates is List) {
          return rawStates.map((e) => e.toString()).toList();
        }
      }
    } catch (_) {}
    return [];
  }

  /// Fetches personalized notifications (alerts, milestones, newly released schemes).
  Future<Map<String, dynamic>> fetchNotifications({
    String? email,
    String? clerkUserId,
    String? state,
  }) async {
    try {
      final queryParams = <String, String>{};
      if (email != null && email.isNotEmpty) queryParams['email'] = email;
      if (clerkUserId != null && clerkUserId.isNotEmpty) queryParams['clerk_user_id'] = clerkUserId;
      if (state != null && state.isNotEmpty && state.toLowerCase() != 'all') {
        queryParams['state'] = state;
      }

      final uri = Uri.parse('$baseUrl/notifications').replace(queryParameters: queryParams);
      final response = await http.get(uri).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final Map<String, dynamic> body = jsonDecode(utf8.decode(response.bodyBytes));
        return body;
      }
    } catch (e) {
      debugPrint('SchemeService.fetchNotifications failed: $e');
    }
    return {'notifications': [], 'unread_count': 0, 'total': 0};
  }

  /// Fetches the count of schemes in the database.
  Future<int?> fetchSchemeCount({String? state}) async {
    try {
      final queryParams = <String, String>{};
      if (state != null && state.trim().isNotEmpty && state.trim().toLowerCase() != 'all') {
        queryParams['state'] = state.trim();
      }
      final uri = Uri.parse('$baseUrl/schemes/count').replace(queryParameters: queryParams);
      final response = await http.get(uri).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        return body['count'] as int?;
      }
    } catch (_) {}
    return null;
  }
}
