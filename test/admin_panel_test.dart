import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yatra_canvas/admin/data/admin_repository.dart';
import 'package:yatra_canvas/admin/screens/admin_shell.dart';
import 'package:yatra_canvas/models/auth_session.dart';

import 'support/auth_fakes.dart';

Future<http.Response> adminResponse(http.Request request) async {
  final path = request.url.path;
  if (path.endsWith('city-lab/summary')) {
    return http.Response(jsonEncode({'configured': false}), 200);
  }
  final value = path.endsWith('dashboard')
      ? {
          'total_users': 7,
          'total_trips': 2,
          'total_places': 30,
          'total_destinations': 1,
          'active_destinations': 1,
          'open_reports_count': 0,
          'places_by_status': {'ACTIVE': 30},
          'recent_trips': [],
          'recent_reports': [],
        }
      : path.endsWith('system-health')
      ? {
          'jobs': {},
          'cache_rows': 0,
          'stale_cache_rows': 0,
          'image_status': {},
          'provider_cooldowns': [],
          'api': 'responding',
          'database': 'readable',
        }
      : path.endsWith('city-lab/cities') ||
            path.endsWith('audit-log') ||
            path.endsWith('city-packs')
      ? {'items': [], 'has_more': false}
      : [];
  return http.Response(jsonEncode(value), 200);
}

void main() {
  testWidgets('audit filters apply and clear without exposing session data', (
    tester,
  ) async {
    final auth = testAuth(
      repository: FakeAuthRepository()..role = UserRole.admin,
    );
    addTearDown(auth.dispose);
    await auth.login('email', 'secret');
    final requests = <Uri>[];
    final repository = AdminRepository(
      auth: auth,
      baseUrl: 'https://api.test',
      client: MockClient((request) async {
        requests.add(request.url);
        if (request.url.queryParameters.values.any((value) => value.isEmpty)) {
          return http.Response(
            '{"detail":"Invalid empty optional filter"}',
            422,
          );
        }
        return http.Response('{"items":[],"has_more":false}', 200);
      }),
    );
    addTearDown(repository.close);
    await tester.pumpWidget(
      MaterialApp(home: AuditListScreen(repository: repository)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Filters'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'City ID'), 'jaipur');
    await tester.enterText(
      find.widgetWithText(TextField, 'Action'),
      'CITY_VALIDATED',
    );
    await tester.tap(find.text('Apply filters'));
    await tester.pumpAndSettle();
    expect(requests.last.queryParameters['city'], 'jaipur');
    expect(requests.last.queryParameters['action'], 'CITY_VALIDATED');
    expect(requests.last.queryParameters.keys, isNot(contains('token')));
    await tester.tap(find.byTooltip('Filters'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear filters'));
    await tester.tap(find.text('Apply filters'));
    await tester.pumpAndSettle();
    expect(requests.last.queryParameters.containsKey('city'), isFalse);
    expect(find.textContaining('could not pass validation'), findsNothing);
    expect(tester.takeException(), isNull);
    await auth.logout();
  });
  for (final size in [const Size(320, 740), const Size(1440, 1000)]) {
    testWidgets('AC-4 integrated admin navigates all operations at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      final semantics = tester.ensureSemantics();
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final auth = testAuth(
        repository: FakeAuthRepository()..role = UserRole.admin,
      );
      addTearDown(auth.dispose);
      await auth.login('email', 'secret');
      final repository = AdminRepository(
        auth: auth,
        baseUrl: 'https://api.test',
        client: MockClient(adminResponse),
      );
      addTearDown(repository.close);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(size.width < 400 ? 1.6 : 1),
            ),
            child: AdminShell(auth: auth, repository: repository),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Your operational overview'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('7'),
        120,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('7'), findsOneWidget);
      expect(tester.takeException(), isNull);
      for (final section in [
        'Overview',
        'City Quality',
        'Trips',
        'Users',
        'Operations',
      ]) {
        expect(
          tester.semantics.simulatedAccessibilityTraversal().any(
            (node) =>
                node.label.contains(section) &&
                node.getSemanticsData().hasAction(ui.SemanticsAction.tap),
          ),
          isTrue,
          reason: '$section must be reachable by assistive technology',
        );
      }
      for (final title in ['City Quality', 'Trips', 'Users', 'Operations']) {
        await tester.tap(find.text(title).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      for (final title in [
        'Online Place Manager',
        'Place Reports',
        'Fix Center',
        'Review Queue',
        'City Releases',
        'System Health',
        'Audit Log',
        'Settings',
      ]) {
        await tester.ensureVisible(find.text(title));
        await tester.tap(find.text(title));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
      await auth.logout();
      semantics.dispose();
    });
  }
  testWidgets('AC-7 direct admin shell denies ordinary users', (tester) async {
    final auth = testAuth();
    addTearDown(auth.dispose);
    await auth.login('email', 'secret');
    await tester.pumpWidget(MaterialApp(home: AdminShell(auth: auth)));
    await tester.pumpAndSettle();
    expect(find.text('Administrator access required.'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await auth.logout();
  });
}
