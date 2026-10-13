import 'dart:async';
import 'dart:convert';

import 'package:yatra_canvas/models/auth_controller.dart';
import 'package:yatra_canvas/models/auth_session.dart';
import 'package:yatra_canvas/services/auth_repository.dart';

String testToken({bool expired = false}) {
  final seconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return 'test.${base64Url.encode(utf8.encode(jsonEncode({'exp': seconds + (expired ? -5 : 3600)}))).replaceAll('=', '')}.signature';
}

AuthSession testSession([UserRole role = UserRole.user]) => AuthSession(
  token: testToken(),
  user: AuthUser(
    id: 'test-${role.value}',
    name: 'Traveller',
    email: 'traveller@example.org',
    role: role,
  ),
);

class MemorySessionStore implements SessionStore {
  String? value;
  bool failClear = false;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async => this.value = value;
  @override
  Future<void> clear() async {
    if (failClear) throw StateError('storage unavailable');
    value = null;
  }
}

class FakeAuthRepository implements AuthRepository {
  UserRole role = UserRole.user;
  AuthFailure? failure;
  Completer<AuthSession>? pending;
  @override
  Future<AuthSession> login(String email, String password) async {
    if (failure != null) throw failure!;
    return pending?.future ?? testSession(role);
  }

  @override
  Future<AuthSession> signup(String name, String email, String password) =>
      login(email, password);
  @override
  Future<AuthUser> me(String token) async {
    if (failure != null) throw failure!;
    return testSession(role).user;
  }

  @override
  Future<String> reset(String email) async =>
      'Password reset email delivery is not configured. No email was sent.';
}

AuthController testAuth({
  FakeAuthRepository? repository,
  MemorySessionStore? store,
}) => AuthController(
  repository: repository ?? FakeAuthRepository(),
  store: store ?? MemorySessionStore(),
);
