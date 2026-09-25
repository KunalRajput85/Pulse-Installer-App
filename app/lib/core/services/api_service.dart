import 'dart:convert';

import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../models/app_config.dart' show ApiUrls;

/// HTTP client for the mobile_services backend.
///
/// Auth model: the backend uses HTTP Basic auth where the credential is the
/// exact base64 token returned by login (server validates user == pass == token).
/// So we send `Authorization: Basic <token>` on every authenticated request.
///
/// Response envelope: every app endpoint returns
///   { "status": 200|400|300, "message": "...", "response": <data|null>, "custom": {...} }
/// Use [unwrap] to check status and pull `response`.
class ApiService {
  final Dio dio;
  String? _basicToken;

  /// Live endpoint table (canonical key -> path/URL). Seeded from [AppEnv]
  /// defaults; [applyJsonUrls] layers the per-installer JSON `apiUrls` on top.
  /// Dio resolves a relative path against the base URL and uses a full http URL
  /// as-is, so an endpoint can point at a different host if needed.
  final Map<String, String> _endpoints =
      Map<String, String>.from(AppEnv.defaultEndpoints);

  ApiService()
      : dio = Dio(BaseOptions(
          baseUrl: AppEnv.apiBaseUrl,
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 40),
          // Do not throw on non-2xx; we read the envelope's own status field.
          validateStatus: (_) => true,
        )) {
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        if (_basicToken != null && _basicToken!.isNotEmpty) {
          options.headers['Authorization'] = 'Basic $_basicToken';
        }
        handler.next(options);
      },
    ));
  }

  /// Store the base64 token returned by login (used as the Basic credential).
  void setToken(String? token) => _basicToken = token;

  bool get hasToken => _basicToken != null && _basicToken!.isNotEmpty;

  // ── Resolved endpoint URLs (use these instead of AppEnv.*Path directly) ────
  String get loginUrl => _endpoints['login']!;
  String get sendOtpUrl => _endpoints['sendOtp']!;
  String get validateOtpUrl => _endpoints['validateOtp']!;
  String get dataUploadUrl => _endpoints['dataUpload']!;
  String get fileUploadUrl => _endpoints['fileUpload']!;
  String get homeScreenUrl => _endpoints['homeScreen']!;
  String get summaryUrl => _endpoints['summary']!;
  String get offlineDropdownUrl => _endpoints['offlineDropdown']!;
  String get jsonUpdateUrl => _endpoints['jsonUpdate']!;
  String get reworkUrl => _endpoints['rework']!;

  /// Layers the per-installer JSON `apiUrls` overrides over the AppEnv defaults.
  /// Call after each config fetch. Login/OTP are included for completeness but
  /// are normally only meaningful before the JSON is loaded.
  void applyJsonUrls(ApiUrls urls) {
    for (final key in AppEnv.endpointKeys) {
      final override = urls[key];
      if (override != null) _endpoints[key] = override;
    }
  }

  /// Absolute form of an endpoint (handy for logging/debugging).
  String endpointUrl(String canonicalKey) =>
      AppEnv.resolve(_endpoints[canonicalKey] ?? '');

  /// POST a JSON body and return the decoded envelope map.
  Future<Map<String, dynamic>> postJson(String url, dynamic body) async {
    try {
      final res = await dio.post(
        url,
        data: body,
        options: Options(headers: {'Content-Type': 'application/json'}),
      );
      return _asMap(res.data, res.statusCode, url);
    } on DioException catch (e) {
      return _networkError(e, url);
    }
  }

  /// GET and return the decoded envelope map (or a raw map for json_link).
  Future<Map<String, dynamic>> getJson(String url) async {
    try {
      final res = await dio.get(url);
      return _asMap(res.data, res.statusCode, url);
    } on DioException catch (e) {
      return _networkError(e, url);
    }
  }

  /// GET and return the decoded body as-is — a JSON array or object. Used by
  /// endpoints (like the offline-dropdown tree) whose top-level response is an
  /// array, which [getJson] cannot represent.
  Future<dynamic> getDynamic(String url) async {
    final res = await dio.get(url);
    final data = res.data;
    if (data is String && data.trim().isNotEmpty) {
      try {
        return jsonDecode(data);
      } catch (_) {/* not JSON — return the raw string */}
    }
    return data;
  }

  /// POST multipart form data (photo upload) and return the envelope map.
  Future<Map<String, dynamic>> postMultipart(String url, FormData form) async {
    try {
      final res = await dio.post(url, data: form);
      return _asMap(res.data, res.statusCode, url);
    } on DioException catch (e) {
      return _networkError(e, url);
    }
  }

  Map<String, dynamic> _asMap(dynamic data, [int? httpStatus, String? url]) {
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String && data.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {/* not JSON */}
    }
    // Couldn't parse a JSON object — surface WHY so the wrong URL / HTML error
    // page is obvious instead of a generic "unexpected response".
    final code = httpStatus ?? 0;
    String hint;
    if (code == 404) {
      hint = 'Endpoint not found (HTTP 404). Check the API URL: $url';
    } else if (code == 401 || code == 403) {
      hint = 'Not authorised (HTTP $code).';
    } else if (code >= 500) {
      hint = 'Server error (HTTP $code).';
    } else {
      final snippet = data == null
          ? 'empty response'
          : data.toString().replaceAll('\n', ' ').trim();
      final short =
          snippet.length > 120 ? '${snippet.substring(0, 120)}…' : snippet;
      hint = 'Server did not return JSON (HTTP $code): $short';
    }
    return {'status': code == 200 || code == 0 ? 400 : code, 'message': hint, 'response': null};
  }

  Map<String, dynamic> _networkError(DioException e, String url) {
    final msg = switch (e.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout =>
        'Connection timed out. Check your internet and try again.',
      DioExceptionType.connectionError =>
        'Cannot reach the server. Check your internet or the API URL: $url',
      _ => 'Network error: ${e.message ?? e.type.name}',
    };
    return {'status': 400, 'message': msg, 'response': null};
  }

  /// Returns the `response` payload if status == 200, else throws [ApiException].
  static dynamic unwrap(Map<String, dynamic> envelope) {
    final status = (envelope['status'] as num?)?.toInt() ?? 400;
    if (status == 200) return envelope['response'];
    final msg = _firstMessage(envelope['message']) ?? 'Request failed';
    throw ApiException(msg, status);
  }

  static String? _firstMessage(dynamic message) {
    if (message is String) return message;
    if (message is List && message.isNotEmpty) return message.first.toString();
    return null;
  }
}

class ApiException implements Exception {
  final String message;
  final int status;
  ApiException(this.message, this.status);
  @override
  String toString() => message;
}
