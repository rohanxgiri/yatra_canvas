import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'auth_session.dart';
import 'yatra_session.dart';
import '../services/auth_repository.dart';

enum AuthStatus {
  unknown,
  unauthenticated,
  authenticating,
  authenticatedUser,
  authenticatedAdmin,
  authenticationError,
}

class AuthController extends ChangeNotifier {
  AuthController({AuthRepository? repository, SessionStore? store})
    : repository = repository ?? BackendAuthRepository(),
      store = store ?? SecureSessionStore();
  static final instance = AuthController();
  final AuthRepository repository;
  final SessionStore store;
  AuthStatus status = AuthStatus.unknown;
  AuthSession? session;
  String? error;
  bool offline = false, guest = false;
  int generation = 0;
  int _operation = 0;
  Future<void> _storageTail = Future.value();
  Timer? _expiryTimer;
  bool logoutIncomplete = false;
  Future<void> _storageAction(Future<void> Function() action) {
    final pending = _storageTail.then((_) => action());
    _storageTail = pending.catchError((Object _) {});
    return pending;
  }

  bool get isAdmin => session?.user.role == UserRole.admin;
  bool get signedIn => session != null;
  bool get busy => status == AuthStatus.authenticating;
  Future<void> restore() async {
    if (status != AuthStatus.unknown) return;
    final operation = ++_operation;
    try {
      final raw = await store.read();
      if (operation != _operation) return;
      if (raw == null) {
        status = AuthStatus.unauthenticated;
        notifyListeners();
        return;
      }
      final saved = AuthSession.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
      if (saved.expired) {
        await logout();
        return;
      }
      try {
        final user = await repository.me(saved.token);
        await _accept(AuthSession(token: saved.token, user: user), operation);
      } on AuthFailure catch (failure) {
        if (operation != _operation) return;
        if (failure.connection && saved.user.role == UserRole.user) {
          offline = true;
          await _accept(saved, operation);
        } else if (failure.connection) {
          error = 'Connect to restore your administrator session.';
          status = AuthStatus.unauthenticated;
        } else {
          await logout();
        }
      }
    } catch (_) {
      if (operation != _operation) return;
      session = null;
      status = AuthStatus.unauthenticated;
      error = 'Your saved session could not be restored. Please sign in.';
    }
    notifyListeners();
  }

  Future<bool> _authenticate(Future<AuthSession> Function() action) async {
    if (busy) return false;
    final operation = ++_operation;
    error = null;
    status = AuthStatus.authenticating;
    notifyListeners();
    try {
      offline = false;
      await _accept(await action(), operation);
      return operation == _operation;
    } on AuthFailure catch (failure) {
      error = failure.message;
    } catch (_) {
      error = 'Unable to securely save your session. Please try again.';
    }
    if (operation != _operation) return false;
    session = null;
    status = AuthStatus.authenticationError;
    notifyListeners();
    return false;
  }

  Future<bool> login(String email, String password) =>
      _authenticate(() => repository.login(email, password));
  Future<bool> signup(String name, String email, String password) =>
      _authenticate(() => repository.signup(name, email, password));
  Future<void> _accept(AuthSession value, int operation) async {
    if (operation != _operation) return;
    if (value.expired) {
      throw const AuthFailure('Your session expired. Please sign in again.');
    }
    if (value.user.role == UserRole.unknown) {
      throw const AuthFailure(
        'This role is not supported by this app version.',
      );
    }
    await _storageAction(() async {
      if (operation == _operation) {
        await store.write(jsonEncode(value.toJson()));
      }
    });
    if (operation != _operation) return;
    session = value;
    guest = false;
    error = null;
    logoutIncomplete = false;
    status = isAdmin
        ? AuthStatus.authenticatedAdmin
        : AuthStatus.authenticatedUser;
    generation++;
    _expiryTimer?.cancel();
    final expiresAt = value.expiresAt;
    if (expiresAt != null) {
      final remaining = expiresAt.difference(DateTime.now());
      _expiryTimer = Timer(
        remaining.isNegative ? Duration.zero : remaining,
        logout,
      );
    }
    YatraSession.instance.clearRecentTrips();
    YatraSession.instance.markSignedIn(
      email: value.user.email,
      displayName: value.user.name,
    );
    notifyListeners();
  }

  void enterGuest() {
    ++_operation;
    _expiryTimer?.cancel();
    session = null;
    guest = true;
    error = null;
    offline = false;
    status = AuthStatus.authenticatedUser;
    generation++;
    YatraSession.instance.enterAsGuest();
    notifyListeners();
  }

  Future<void> logout() async {
    ++_operation;
    _expiryTimer?.cancel();
    session = null;
    guest = false;
    offline = false;
    generation++;
    status = AuthStatus.unauthenticated;
    error = null;
    YatraSession.instance.signOut();
    YatraSession.instance.clearRecentTrips();
    notifyListeners();
    try {
      await _storageAction(store.clear);
      logoutIncomplete = false;
    } catch (_) {
      logoutIncomplete = true;
      error = 'Unable to clear saved sign-in. Retry signing out before closing the app.';
    }
    notifyListeners();
  }

  Future<String> reset(String email) => repository.reset(email);
  @override
  void dispose() {
    ++_operation;
    _expiryTimer?.cancel();
    super.dispose();
  }
}
