import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';

/// HTTP failures are surfaced to admins, never replaced with sample data.
class AdminApiException implements Exception {
  const AdminApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// A thin client around the existing FastAPI auth and /api/admin contracts.
class AdminApiClient {
  AdminApiClient({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _ownsClient = client == null,
      _baseUrl = (baseUrl ?? ApiConfig.baseUrl).replaceFirst(RegExp(r'/$'), '');

  static const _timeout = Duration(seconds: 20);
  final http.Client _client;
  final bool _ownsClient;
  final String _baseUrl;

  Future<Map<String, dynamic>> login(String email, String password) async {
    final result = await _request(
      'POST',
      '/api/auth/login',
      body: {'email': email.trim().toLowerCase(), 'password': password},
    );
    if (result is! Map<String, dynamic>) {
      throw const AdminApiException('Unexpected sign-in response.');
    }
    return result;
  }

  Future<dynamic> get(String path, {required String token}) {
    return _request('GET', path, token: token);
  }

  Future<dynamic> patch(
    String path, {
    required String token,
    required Map<String, dynamic> body,
  }) {
    return _request('PATCH', path, token: token, body: body);
  }

  Future<dynamic> _request(
    String method,
    String path, {
    String? token,
    Map<String, dynamic>? body,
  }) async {
    try {
      final request = http.Request(method, Uri.parse('$_baseUrl$path'))
        ..headers.addAll({
          'Accept': 'application/json',
          if (body != null) 'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        });
      if (body != null) request.body = jsonEncode(body);

      final streamed = await _client.send(request).timeout(_timeout);
      final response = await http.Response.fromStream(streamed).timeout(_timeout);
      dynamic data;
      try {
        data = jsonDecode(response.body);
      } on FormatException {
        throw const AdminApiException('Server returned an invalid response.');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final detail = data is Map<String, dynamic> ? data['detail'] : null;
        throw AdminApiException(
          detail is String && detail.isNotEmpty
              ? detail
              : 'Request failed (HTTP ${response.statusCode}).',
          statusCode: response.statusCode,
        );
      }
      return data;
    } on TimeoutException {
      throw const AdminApiException('Request timed out. Please try again.');
    } on http.ClientException {
      throw const AdminApiException('Cannot reach the YatraCanvas backend.');
    }
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}

/// In-memory admin session: requires a server-issued JWT and /api/auth/me
/// confirmation. Neither a hardcoded email nor a client-side flag grants access.
class AdminSession extends ChangeNotifier {
  AdminSession({AdminApiClient? api}) : _api = api ?? AdminApiClient();

  static final AdminSession instance = AdminSession();

  final AdminApiClient _api;
  String? _token;
  Map<String, dynamic>? _user;

  bool get isAuthenticated =>
      _token != null && _user?['role'] == 'ADMIN';
  String get displayName => (_user?['name'] as String?) ?? 'Administrator';

  Future<void> signIn(String email, String password) async {
    clear();
    final result = await _api.login(email, password);
    final token = result['access_token'];
    if (token is! String || token.isEmpty) {
      throw const AdminApiException('Sign-in response did not contain a token.');
    }

    // Always check the current server-side role rather than trusting an email.
    final profile = await _api.get('/api/auth/me', token: token);
    if (profile is! Map<String, dynamic> || profile['role'] != 'ADMIN') {
      throw const AdminApiException(
        'This account does not have administrator access.',
        statusCode: 403,
      );
    }
    _token = token;
    _user = profile;
    notifyListeners();
  }

  Future<dynamic> get(String path) async {
    return _withSession(() => _api.get(path, token: _requiredToken));
  }

  Future<dynamic> patch(String path, Map<String, dynamic> body) async {
    return _withSession(
      () => _api.patch(path, token: _requiredToken, body: body),
    );
  }

  String get _requiredToken {
    if (!isAuthenticated) {
      throw const AdminApiException('Sign in as an administrator first.', statusCode: 401);
    }
    return _token!;
  }

  Future<dynamic> _withSession(Future<dynamic> Function() action) async {
    try {
      return await action();
    } on AdminApiException catch (error) {
      if (error.statusCode == 401 || error.statusCode == 403) clear();
      rethrow;
    }
  }

  void clear() {
    _token = null;
    _user = null;
    notifyListeners();
  }
}
