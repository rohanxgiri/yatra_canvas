import 'dart:convert';

enum UserRole {
  user('USER'),
  admin('ADMIN'),
  unknown('UNKNOWN');

  const UserRole(this.value);
  final String value;
  static UserRole parse(Object? value) =>
      values.firstWhere((role) => role.value == value, orElse: () => unknown);
}

class AuthUser {
  const AuthUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
  });
  final String id, name, email;
  final UserRole role;
  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
    id: json['id'] as String,
    name: json['name'] as String,
    email: json['email'] as String,
    role: UserRole.parse(json['role']),
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'email': email,
    'role': role.value,
  };
}

class AuthSession {
  const AuthSession({required this.token, required this.user});
  final String token;
  final AuthUser user;
  DateTime? get expiresAt {
    try {
      final parts = token.split('.');
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      ) as Map;
      return DateTime.fromMillisecondsSinceEpoch(
        (payload['exp'] as num).toInt() * 1000,
      );
    } catch (_) {
      return null;
    }
  }

  bool get expired => expiresAt == null || !expiresAt!.isAfter(DateTime.now());

  Map<String, dynamic> toJson() => {
    'access_token': token,
    'user': user.toJson(),
  };
  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
    token: json['access_token'] as String,
    user: AuthUser.fromJson(Map<String, dynamic>.from(json['user'] as Map)),
  );
}
