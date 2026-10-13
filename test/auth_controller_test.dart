import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yatra_canvas/models/auth_controller.dart';
import 'package:yatra_canvas/models/auth_session.dart';
import 'package:yatra_canvas/services/auth_repository.dart';

import 'support/auth_fakes.dart';

void main() {
  test(
    'AC-2 login persists token/profile and central role; logout clears both',
    () async {
      final store = MemorySessionStore(),
          repository = FakeAuthRepository()..role = UserRole.admin;
      final auth = testAuth(store: store, repository: repository);
      addTearDown(auth.dispose);
      expect(await auth.login('email', 'password-never-stored'), isTrue);
      expect(auth.status, AuthStatus.authenticatedAdmin);
      expect(auth.isAdmin, isTrue);
      expect(store.value, isNot(contains('password-never-stored')));
      await auth.logout();
      expect(store.value, isNull);
      expect(auth.session, isNull);
      expect(auth.status, AuthStatus.unauthenticated);
    },
  );
  test('AC-2 restart validates saved role with backend', () async {
    final store = MemorySessionStore()
      ..value = jsonEncode(testSession(UserRole.admin).toJson());
    final auth = testAuth(store: store); // Live role was demoted.
    addTearDown(auth.dispose);
    await auth.restore();
    expect(auth.status, AuthStatus.authenticatedUser);
    expect(auth.isAdmin, isFalse);
  });
  test('AC-2 offline restoration permits unexpired traveller only', () async {
    for (final role in [UserRole.user, UserRole.admin]) {
      final store = MemorySessionStore()
        ..value = jsonEncode(testSession(role).toJson());
      final repo = FakeAuthRepository()
        ..failure = const AuthFailure('offline', connection: true);
      final auth = testAuth(store: store, repository: repo);
      await auth.restore();
      expect(auth.signedIn, role == UserRole.user);
      expect(auth.isAdmin, isFalse);
      auth.dispose();
    }
  });
  test('AC-2 expiry and rejected session clear persistence', () async {
    final user = testSession().user;
    final store = MemorySessionStore()
      ..value = jsonEncode(
        AuthSession(token: testToken(expired: true), user: user).toJson(),
      );
    final auth = testAuth(store: store);
    addTearDown(auth.dispose);
    await auth.restore();
    expect(auth.signedIn, isFalse);
    expect(store.value, isNull);
  });
  test('AC-2 late authentication cannot undo logout', () async {
    final repo = FakeAuthRepository()..pending = Completer<AuthSession>();
    final store = MemorySessionStore();
    final controller = testAuth(repository: repo, store: store);
    addTearDown(controller.dispose);
    final pending = controller.login('email', 'secret');
    await controller.logout();
    repo.pending!.complete(testSession(UserRole.admin));
    expect(await pending, isFalse);
    expect(controller.signedIn, isFalse);
    expect(store.value, isNull);
  });
  test('AC-2 failed storage deletion remains retryable', () async {
    final store = MemorySessionStore()..failClear = true;
    final auth = testAuth(store: store);
    addTearDown(auth.dispose);
    await auth.logout();
    expect(auth.logoutIncomplete, isTrue);
    store.failClear = false;
    await auth.logout();
    expect(auth.logoutIncomplete, isFalse);
  });
  test('AC-3 unknown role fails closed', () async {
    final repo = FakeAuthRepository()..role = UserRole.unknown;
    final auth = testAuth(repository: repo);
    addTearDown(auth.dispose);
    expect(await auth.login('email', 'secret'), isFalse);
    expect(auth.signedIn, isFalse);
  });
}
