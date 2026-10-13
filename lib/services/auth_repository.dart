import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/auth_session.dart';

class AuthFailure implements Exception {
  const AuthFailure(this.message, {this.connection = false});
  final String message;
  final bool connection;
}

abstract interface class SessionStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

class SecureSessionStore implements SessionStore {
  static const _storage = FlutterSecureStorage();
  static const _key = 'yatracanvas.auth.v1';
  String? _webSession;
  @override
  Future<String?> read() async =>
      kIsWeb ? _webSession : await _storage.read(key: _key);
  @override
  Future<void> write(String value) async {
    if (kIsWeb) {
      _webSession = value;
    } else {
      await _storage.write(key: _key, value: value);
    }
  }

  @override
  Future<void> clear() async {
    _webSession = null;
    if (!kIsWeb) await _storage.delete(key: _key);
  }
}

abstract interface class AuthRepository {
  Future<AuthSession> login(String email, String password);
  Future<AuthSession> signup(String name, String email, String password);
  Future<AuthUser> me(String token);
  Future<String> reset(String email);
}

class BackendAuthRepository implements AuthRepository {
  BackendAuthRepository({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _base = baseUrl ?? ApiConfig.baseUrl;
  final http.Client _client;
  final String _base;
  Future<Map<String, dynamic>> _request(
    String path, {
    Map<String, dynamic>? body,
    String? token,
  }) async {
    try {
      final uri = Uri.parse('$_base/api/auth/$path');
      final headers = {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };
      final response =
          await (body == null
                  ? _client.get(uri, headers: headers)
                  : _client.post(uri, headers: headers, body: jsonEncode(body)))
              .timeout(const Duration(seconds: 15));
      if (response.statusCode >= 400) {
        throw AuthFailure(switch (response.statusCode) {
          401 => 'Incorrect email or password.',
          403 => 'This account is unavailable. Contact support.',
          409 =>
            'Unable to create an account with these details. Try signing in.',
          422 => 'Check your details and try again.',
          _ => 'Authentication is unavailable. Please try again.',
        });
      }
      return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    } on AuthFailure {
      rethrow;
    } on TimeoutException {
      throw const AuthFailure(
        'Unable to connect. Check your connection and try again.',
        connection: true,
      );
    } on http.ClientException {
      throw const AuthFailure(
        'Unable to connect. Check your connection and try again.',
        connection: true,
      );
    } catch (_) {
      throw const AuthFailure(
        'Unable to complete authentication. Please try again.',
      );
    }
  }

  @override
  Future<AuthSession> login(String email, String password) async =>
      AuthSession.fromJson(
        await _request(
          'login',
          body: {'email': email.trim(), 'password': password},
        ),
      );
  @override
  Future<AuthSession> signup(
    String name,
    String email,
    String password,
  ) async => AuthSession.fromJson(
    await _request(
      'signup',
      body: {'name': name.trim(), 'email': email.trim(), 'password': password},
    ),
  );
  @override
  Future<AuthUser> me(String token) async =>
      AuthUser.fromJson(await _request('me', token: token));
  @override
  Future<String> reset(String email) async =>
      (await _request(
            'forgot-password',
            body: {'email': email.trim()},
          ))['message']
          as String;
}
