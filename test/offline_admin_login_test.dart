import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yatra_canvas/admin/data/admin_repository.dart';
import 'package:yatra_canvas/models/auth_controller.dart';
import 'package:yatra_canvas/models/auth_session.dart';
import 'package:yatra_canvas/screens/auth/auth_gate.dart';
import 'package:yatra_canvas/services/auth_repository.dart';

import 'support/auth_fakes.dart';

class CountingRepository extends FakeAuthRepository {
  int calls = 0;
  @override
  Future<AuthSession> login(String email, String password) {
    calls++;
    return super.login(email, password);
  }

  @override
  Future<AuthUser> me(String token) {
    calls++;
    return super.me(token);
  }
}

class FailingWriteStore extends MemorySessionStore {
  @override
  Future<void> write(String value) async => throw StateError('locked store');
}

void main() {
  test(
    'fresh offline credential login makes zero backend calls and no JWT',
    () async {
      final repository = CountingRepository()
        ..failure = const AuthFailure('offline', connection: true);
      final store = MemorySessionStore();
      final auth = testAuth(repository: repository, store: store);
      addTearDown(auth.dispose);
      expect(
        await auth.loginOfflineAdmin(' ADMIN@yatracanvas.com ', 'admin'),
        isTrue,
      );
      expect(auth.isOfflineAdmin, isTrue);
      expect(auth.offline, isTrue);
      expect(auth.isAdmin, isFalse);
      expect(auth.signedIn, isFalse);
      expect(auth.session, isNull);
      expect(repository.calls, 0);
      expect(jsonDecode(store.value!) as Map, {
        'mode': 'offline_admin',
        'schema_version': 1,
      });
    },
  );

  test(
    'incorrect offline email or password fails without contacting a backend',
    () async {
      for (final credentials in [
        ['admin@yatracanvas.com', 'wrong'],
        ['someone@example.org', 'admin'],
        ['admin@yatracanvas.com', ''],
      ]) {
        final repository = CountingRepository();
        final store = MemorySessionStore();
        final auth = testAuth(repository: repository, store: store);
        expect(
          await auth.loginOfflineAdmin(credentials[0], credentials[1]),
          isFalse,
        );
        expect(auth.isOfflineAdmin, isFalse);
        expect(auth.isAdmin, isFalse);
        expect(store.value, isNull);
        expect(repository.calls, 0);
        auth.dispose();
      }
    },
  );

  test('offline marker restores without HTTP and logout clears it', () async {
    final store = MemorySessionStore();
    final first = testAuth(store: store);
    await first.loginOfflineAdmin('admin@yatracanvas.com', 'admin');
    first.dispose();
    final repository = CountingRepository()
      ..failure = const AuthFailure('offline', connection: true);
    final restored = testAuth(repository: repository, store: store);
    addTearDown(restored.dispose);
    await restored.restore();
    expect(restored.isOfflineAdmin, isTrue);
    expect(restored.isAdmin, isFalse);
    expect(repository.calls, 0);
    await restored.logout();
    expect(store.value, isNull);
    expect(restored.status, AuthStatus.unauthenticated);
    expect(restored.isOfflineAdmin, isFalse);
  });

  test('offline mode cannot access or mutate server admin APIs', () async {
    var requests = 0;
    final auth = testAuth();
    addTearDown(auth.dispose);
    await auth.loginOfflineAdmin('admin@yatracanvas.com', 'admin');
    final admin = AdminRepository(
      auth: auth,
      client: MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      }),
    );
    addTearDown(admin.close);
    await expectLater(admin.get('stats'), throwsA(isA<AdminFailure>()));
    await expectLater(
      admin.mutate('places/id', {'moderation_status': 'HIDDEN'}),
      throwsA(isA<AdminFailure>()),
    );
    await expectLater(
      admin.mediaBytes('city', 'photo.webp'),
      throwsA(isA<AdminFailure>()),
    );
    expect(requests, 0);
  });

  test(
    'online login never falls back to local demo after a rejection',
    () async {
      final repository = CountingRepository()
        ..failure = const AuthFailure('Incorrect email or password.');
      final auth = testAuth(repository: repository);
      addTearDown(auth.dispose);
      expect(await auth.login('admin@yatracanvas.com', 'admin'), isFalse);
      expect(auth.isOfflineAdmin, isFalse);
      expect(repository.calls, 1);
    },
  );

  test('late online response cannot replace the offline session', () async {
    final repository = CountingRepository()..pending = Completer<AuthSession>();
    final store = MemorySessionStore();
    final auth = testAuth(repository: repository, store: store);
    addTearDown(auth.dispose);
    final pending = auth.login('online@example.org', 'password');
    expect(
      await auth.loginOfflineAdmin('admin@yatracanvas.com', 'admin'),
      isTrue,
    );
    repository.pending!.complete(testSession(UserRole.admin));
    expect(await pending, isFalse);
    expect(auth.isOfflineAdmin, isTrue);
    expect(auth.isAdmin, isFalse);
    expect((jsonDecode(store.value!) as Map)['mode'], 'offline_admin');
  });

  test('failed secure storage write does not enter offline admin', () async {
    final auth = testAuth(store: FailingWriteStore());
    addTearDown(auth.dispose);
    expect(
      await auth.loginOfflineAdmin('admin@yatracanvas.com', 'admin'),
      isFalse,
    );
    expect(auth.isOfflineAdmin, isFalse);
    expect(auth.status, AuthStatus.authenticationError);
  });

  test('unknown offline marker schema fails closed', () async {
    final store = MemorySessionStore()
      ..value = jsonEncode({'mode': 'offline_admin', 'schema_version': 99});
    final repository = CountingRepository();
    final auth = testAuth(repository: repository, store: store);
    addTearDown(auth.dispose);
    await auth.restore();
    expect(auth.isOfflineAdmin, isFalse);
    expect(auth.isAdmin, isFalse);
    expect(repository.calls, 0);
  });

  testWidgets(
    'explicit offline credentials enter local admin and reset history',
    (tester) async {
      final repository = CountingRepository()
        ..failure = const AuthFailure('offline', connection: true);
      final auth = testAuth(repository: repository);
      addTearDown(auth.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: AuthGate(
            auth: auth,
            requireAuthentication: true,
            offlineAdminBuilder: (_) =>
                const Scaffold(body: Text('Device admin workspace')),
            adminBuilder: (_) =>
                const Scaffold(body: Text('Server admin workspace')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(SegmentedButton<bool>),
          matching: find.text('Offline admin'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('Password')), 'admin');
      await tester.ensureVisible(find.text('Sign In'));
      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();
      expect(find.text('Device admin workspace'), findsOneWidget);
      expect(find.text('Server admin workspace'), findsNothing);
      expect(repository.calls, 0);
      final navigator = Navigator.of(
        tester.element(find.text('Device admin workspace')),
      );
      expect(navigator.canPop(), isFalse);
      navigator.push(
        MaterialPageRoute<void>(builder: (_) => const Text('Local details')),
      );
      await tester.pumpAndSettle();
      await auth.logout();
      await tester.pumpAndSettle();
      expect(find.text('Local details'), findsNothing);
      expect(find.text('Device admin workspace'), findsNothing);
      expect(find.text('Sign In'), findsOneWidget);
    },
  );
}
