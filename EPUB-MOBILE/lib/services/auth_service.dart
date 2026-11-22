import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'api_config.dart';

class AuthSession {
  const AuthSession({
    required this.token,
    required this.fullToken,
    required this.username,
    this.userId,
    this.email,
    this.role = 'READER',
  });

  final String token;
  final String fullToken;
  final String username;
  final int? userId;
  final String? email;
  final String role;

  bool get isAdmin => role.toUpperCase() == 'ADMIN';

  Map<String, Object?> toJson() {
    return {
      'token': token,
      'fullToken': fullToken,
      'username': username,
      'userId': userId,
      'email': email,
      'role': role,
    };
  }

  factory AuthSession.fromJson(Map<String, Object?> json) {
    return AuthSession(
      token: json['token'] as String? ?? '',
      fullToken: json['fullToken'] as String? ?? '',
      username: json['username'] as String? ?? '',
      userId: _intValue(json['userId']),
      email: json['email'] as String?,
      role: json['role'] as String? ?? 'READER',
    );
  }

  static int? _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value');
  }
}

class AuthService {
  AuthService({String? baseUrl})
    : baseUrl = ApiConfig.normalizeBaseUrl(baseUrl ?? ApiConfig.rawBaseUrl);

  final String baseUrl;
  String? _captchaCookie;

  Future<File> get _sessionFile async {
    final directory = await getApplicationDocumentsDirectory();
    return File(p.join(directory.path, 'auth_session.json'));
  }

  Future<AuthSession?> loadSession() async {
    final file = await _sessionFile;
    if (!await file.exists()) return null;
    try {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final session = AuthSession.fromJson(json);
      if (session.token.isEmpty || session.username.isEmpty) return null;
      return session;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveSession(AuthSession session) async {
    final file = await _sessionFile;
    await file.writeAsString(jsonEncode(session.toJson()), flush: true);
  }

  Future<void> logout() async {
    final file = await _sessionFile;
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<Uint8List> fetchCaptcha() async {
    final client = HttpClient();
    try {
      final uri = Uri.parse(
        '$baseUrl/api/auth/captcha?t=${DateTime.now().millisecondsSinceEpoch}',
      );
      final request = await client.getUrl(uri);
      if (_captchaCookie != null) {
        request.headers.set(HttpHeaders.cookieHeader, _captchaCookie!);
      }
      request.headers.set(HttpHeaders.acceptHeader, 'image/png,*/*');

      final response = await request.close();
      final bytes = await _readResponseBytes(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final text = utf8.decode(bytes, allowMalformed: true);
        throw AuthException(text.isEmpty ? '验证码加载失败' : text);
      }

      final cookie = _cookieHeaderFrom(response.cookies);
      if (cookie != null) _captchaCookie = cookie;
      return bytes;
    } on AuthException {
      rethrow;
    } catch (error) {
      throw AuthException('验证码加载失败：$error');
    } finally {
      client.close(force: true);
    }
  }

  Future<AuthSession> login({
    required String username,
    required String password,
    required String captcha,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(
        Uri.parse('$baseUrl/api/auth/login'),
      );
      request.headers.contentType = ContentType.json;
      if (_captchaCookie != null) {
        request.headers.set(HttpHeaders.cookieHeader, _captchaCookie!);
      }
      request.write(
        jsonEncode({
          'username': username,
          'password': password,
          'captcha': captcha,
        }),
      );

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      final json = _decodeObject(body);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AuthException(_messageFrom(json) ?? '登录失败');
      }
      if (json['success'] != true || json['data'] is! Map) {
        throw AuthException(_messageFrom(json) ?? '用户名或密码错误');
      }

      final data = json['data'] as Map<String, dynamic>;
      final token = data['token'] as String? ?? '';
      final type = data['type'] as String?;
      final respUsername = data['username'] as String? ?? username;
      if (token.isEmpty) {
        throw const AuthException('登录响应缺少 token');
      }

      final session = AuthSession(
        token: token,
        fullToken: type == null || type.isEmpty ? token : '$type $token',
        username: respUsername,
        userId: AuthSession._intValue(data['userId']),
        email: data['email'] as String?,
        role: data['role'] as String? ?? 'READER',
      );
      await saveSession(session);
      return session;
    } on AuthException {
      rethrow;
    } catch (error) {
      throw AuthException('登录失败：$error');
    } finally {
      client.close(force: true);
    }
  }

  Map<String, dynamic> _decodeObject(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // Fall through to a normalized error object.
    }
    return {'success': false, 'message': body.isEmpty ? '服务响应为空' : body};
  }

  String? _messageFrom(Map<String, dynamic> json) {
    return json['message'] as String? ?? json['msg'] as String?;
  }

  Future<Uint8List> _readResponseBytes(HttpClientResponse response) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  String? _cookieHeaderFrom(List<Cookie> cookies) {
    if (cookies.isEmpty) return null;
    return cookies.map((cookie) => '${cookie.name}=${cookie.value}').join('; ');
  }
}

class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}
