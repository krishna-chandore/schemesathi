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
        return 'http://10.0.2.2:8001';
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
