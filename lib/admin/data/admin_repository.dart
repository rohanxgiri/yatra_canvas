import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../config/api_config.dart';
import '../../models/auth_controller.dart';

class AdminFailure implements Exception {
  const AdminFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class AdminPage {
  const AdminPage(this.items, this.hasMore, {this.inventoryProblems = 0});
  final List<Map<String, dynamic>> items;
  final bool hasMore;
  final int inventoryProblems;
}

class AdminRepository {
  AdminRepository({required this.auth, http.Client? client, String? baseUrl})
    : client = client ?? http.Client(),
      baseUrl = baseUrl ?? ApiConfig.baseUrl;
  final AuthController auth;
  final http.Client client;
  final String baseUrl;
  void _checkIdentity(String token, int generation) {
    if (!auth.isAdmin ||
        auth.generation != generation ||
        auth.session?.token != token ||
        auth.session!.expired) {
      throw const AdminFailure('Your session changed. Sign in again.');
    }
  }

  Future<dynamic> request(
    String path, {
    Map<String, String> query = const {},
    Map<String, dynamic>? body,
    String method = 'GET',
  }) async {
    if (!auth.isAdmin || auth.session == null || auth.session!.expired) {
      if (auth.session?.expired == true) await auth.logout();
      throw const AdminFailure('Sign in with an administrator account.');
    }
    final token = auth.session!.token;
    final generation = auth.generation;
    try {
      final uri = Uri.parse('$baseUrl/api/admin/$path')
          .replace(queryParameters: query.isEmpty ? null : query);
      final request = http.Request(method, uri)
        ..headers.addAll({
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        });
      if (body != null) request.body = jsonEncode(body);
      final response = await http.Response.fromStream(
        await client.send(request).timeout(const Duration(seconds: 45)),
      ).timeout(const Duration(seconds: 45));
      // A response from an old identity must neither expose records nor log
      // out the new identity after a sign-out/sign-in transition.
      _checkIdentity(token, generation);
      if (response.statusCode == 401 || response.statusCode == 403) {
        await auth.logout();
        throw const AdminFailure(
          'Your administrator session is unavailable. Sign in again.',
        );
      }
      if (response.statusCode >= 400) {
        throw AdminFailure(switch (response.statusCode) {
          404 => 'This record is no longer available.',
          409 => 'The record changed. Reload it before saving.',
          422 => 'The action could not pass validation. Check the values and source evidence.',
          503 => 'This workflow is unavailable. Check backend source files and DataFactory configuration.',
          _ => 'Unable to load admin data. Please retry.',
        });
      }
      return jsonDecode(response.body);
    } on AdminFailure {
      rethrow;
    } catch (_) {
      throw const AdminFailure(
        'Unable to connect to the backend. Please retry.',
      );
    }
  }

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String> query = const {},
  }) async =>
      Map<String, dynamic>.from(await request(path, query: query) as Map);
  Future<AdminPage> list(
    String path, {
    Map<String, String> query = const {},
    int offset = 0,
    int limit = 30,
  }) async {
    final value = await request(
      path,
      query: {...query, 'offset': '$offset', 'limit': '$limit'},
    );
    final rows = value is List ? value : (value as Map)['items'] as List;
    return AdminPage(
      rows.map((r) => Map<String, dynamic>.from(r as Map)).toList(),
      value is List ? rows.length == limit : value['has_more'] == true,
      inventoryProblems: value is Map
          ? (value['inventory_problems'] as List? ?? []).length
          : 0,
    );
  }

  Future<Map<String, dynamic>> mutate(
    String path,
    Map<String, dynamic> body, {
    bool patch = false,
    Map<String, String> query = const {},
  }) async => Map<String, dynamic>.from(
    await request(
      path,
      method: patch ? 'PATCH' : 'POST',
      body: body,
      query: query,
    ) as Map,
  );
  Uri media(String key, String path) =>
      Uri.parse('$baseUrl/api/admin/city-lab/cities/$key/media')
          .replace(queryParameters: {'path': path});
  Future<Uint8List> mediaBytes(String key, String path) async {
    if (!auth.isAdmin || auth.session == null || auth.session!.expired) {
      throw const AdminFailure('Sign in with an administrator account.');
    }
    final token = auth.session!.token;
    final generation = auth.generation;
    try {
      final response = await client
          .get(media(key, path), headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 15));
      _checkIdentity(token, generation);
      if (response.statusCode == 401 || response.statusCode == 403) {
        await auth.logout();
      }
      if (response.statusCode != 200 || response.bodyBytes.length > 20000000) {
        throw const AdminFailure(
          'Referenced image unavailable. Mark it for research.',
        );
      }
      return response.bodyBytes;
    } on AdminFailure {
      rethrow;
    } catch (_) {
      throw const AdminFailure(
        'Image unavailable. Check the reference or retry.',
      );
    }
  }

  void close() => client.close();
}
