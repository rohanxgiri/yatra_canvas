import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yatra_canvas/admin/data/admin_repository.dart';
import 'package:yatra_canvas/admin/screens/admin_dashboard_screen.dart';
import 'package:yatra_canvas/admin/screens/admin_collection_screen.dart';
import 'package:yatra_canvas/admin/screens/catalog_screens.dart';
import 'package:yatra_canvas/models/auth_session.dart';

import 'admin_panel_test.dart' show adminResponse;
import 'support/auth_fakes.dart';

void main() {
  testWidgets(
    'failed refresh retries the first page and failed new filters hide old rows',
    (tester) async {
      final auth = testAuth(
        repository: FakeAuthRepository()..role = UserRole.admin,
      );
      await auth.login('email', 'secret');
      addTearDown(auth.dispose);
      final requests = <Uri>[];
      final repository = AdminRepository(
        auth: auth,
        client: MockClient((request) async {
          requests.add(request.url);
          if (requests.length == 2 ||
              request.url.queryParameters['q'] == 'new filter') {
            return http.Response('{}', 500);
          }
          return http.Response(
            jsonEncode([
              {
                'id': 'one',
                'name': requests.length == 1 ? 'Previous row' : 'Updated row',
              },
            ]),
            200,
          );
        }),
      );
      addTearDown(repository.close);
      await tester.pumpWidget(
        MaterialApp(
          home: AdminCollectionScreen(
            title: 'Users',
            path: 'users',
            repository: repository,
            onOpen: (_, _) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();
      expect(find.text('Previous row'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(requests.last.queryParameters['offset'], '0');
      expect(find.text('Updated row'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'new filter');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('Updated row'), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
      await auth.logout();
    },
  );
  testWidgets(
    'overview keeps real counts when optional integrations fail and refreshes',
    (tester) async {
      final auth = testAuth(
        repository: FakeAuthRepository()..role = UserRole.admin,
      );
      await auth.login('email', 'secret');
      addTearDown(auth.dispose);
      var users = 37;
      var offline = false;
      final repository = AdminRepository(
        auth: auth,
        client: MockClient((request) async {
          if (request.url.path.endsWith('dashboard')) {
            if (offline) return http.Response('{}', 500);
            final value =
                jsonDecode((await adminResponse(request)).body) as Map;
            value['total_users'] = users;
            return http.Response(jsonEncode(value), 200);
          }
          if (request.url.path.contains('city-lab')) {
            return http.Response('{}', 503);
          }
          return adminResponse(request);
        }),
      );
      addTearDown(repository.close);
      await tester.pumpWidget(
        MaterialApp(home: AdminDashboardScreen(repository: repository)),
      );
      await tester.pumpAndSettle();
      expect(find.text('37'), findsOneWidget);
      expect(find.textContaining('Last refreshed'), findsOneWidget);
      expect(
        find.textContaining('Canonical could not refresh'),
        findsOneWidget,
      );
      users = 38;
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('38'), 150);
      expect(find.text('38'), findsOneWidget);
      offline = true;
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();
      expect(find.text('38'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.textContaining('Showing the last successful result'),
        -150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.textContaining('Showing the last successful result'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await auth.logout();
    },
  );

  testWidgets('optional slow sources do not delay operational counts', (
    tester,
  ) async {
    final auth = testAuth(
      repository: FakeAuthRepository()..role = UserRole.admin,
    );
    await auth.login('email', 'secret');
    addTearDown(auth.dispose);
    final pending = Completer<http.Response>();
    final repository = AdminRepository(
      auth: auth,
      client: MockClient((request) async {
        if (request.url.path.endsWith('city-lab/summary')) {
          return pending.future;
        }
        return adminResponse(request);
      }),
    );
    addTearDown(repository.close);
    await tester.pumpWidget(
      MaterialApp(home: AdminDashboardScreen(repository: repository)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('7'), findsOneWidget);
    pending.complete(http.Response('{"configured":false}', 200));
    await tester.pumpAndSettle();
    await auth.logout();
  });

  test('responses from a previous account cannot sign out or expose data to a new account', () async {
    final auth = testAuth(
      repository: FakeAuthRepository()..role = UserRole.admin,
    );
    await auth.login('email', 'secret');
    addTearDown(auth.dispose);
    final pending = Completer<http.Response>();
    final repository = AdminRepository(
      auth: auth,
      client: MockClient((_) => pending.future),
    );
    addTearDown(repository.close);
    final request = repository.get('dashboard');
    final assertion = expectLater(request, throwsA(isA<AdminFailure>()));
    await auth.logout();
    await auth.login('next-account', 'secret');
    pending.complete(http.Response('{}', 401));
    await assertion;
    expect(auth.isAdmin, isTrue);
    await auth.logout();
  });

  testWidgets(
    'report decision requires evidence, confirmation and loaded revision',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final auth = testAuth(
        repository: FakeAuthRepository()..role = UserRole.admin,
      );
      await auth.login('email', 'secret');
      addTearDown(auth.dispose);
      Map<String, dynamic>? saved;
      final repository = AdminRepository(
        auth: auth,
        client: MockClient((request) async {
          if (request.method == 'PATCH') {
            saved = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
            return http.Response('{}', 200);
          }
          return http.Response(
            jsonEncode({
              'id': 'report-1',
              'place_id': 'place-1',
              'place_name': 'Fort',
              'city_name': 'Jaipur',
              'reason': 'wrong_category',
              'details': 'Review the source category',
              'status': 'OPEN',
              'admin_notes': null,
              'updated_at': '2026-10-12T00:00:00Z',
            }),
            200,
          );
        }),
      );
      addTearDown(repository.close);
      await tester.pumpWidget(
        MaterialApp(
          home: ReportDetailScreen(repository: repository, id: 'report-1'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Save decision'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Save decision'));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      expect(find.textContaining('Add a reason'), findsOneWidget);
      await tester.enterText(
        find.byType(TextFormField),
        'Official source confirms the issue.',
      );
      await tester.ensureVisible(find.text('Save decision'));
      await tester.tap(find.text('Save decision'));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(saved?['expected_updated_at'], '2026-10-12T00:00:00Z');
      expect(saved?['admin_notes'], 'Official source confirms the issue.');
      expect(
        find.text('Decision saved to the backend audit log.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await auth.logout();
    },
  );
}
