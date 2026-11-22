import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../models/cloud_book.dart';
import '../models/annotation.dart';
import '../models/book.dart';
import '../models/bookmark.dart';
import '../models/category.dart';
import '../models/storage_quota.dart';
import 'api_config.dart';
import 'auth_service.dart';
import 'storage_service.dart';

class CloudService {
  CloudService({
    AuthService? authService,
    StorageService? storageService,
    String? baseUrl,
  }) : baseUrl = ApiConfig.normalizeBaseUrl(baseUrl ?? ApiConfig.rawBaseUrl),
       _authService = authService ?? AuthService(baseUrl: baseUrl),
       _storageService = storageService ?? StorageService();

  final AuthService _authService;
  final StorageService _storageService;
  final String baseUrl;

  Future<List<CloudBook>> fetchBooks({
    required Set<String> localTitles,
    required Map<String, int> localIdsByTitle,
  }) async {
    final response = await _request('GET', '/api/books');
    final body = await response.transform(utf8.decoder).join();
    final json = _decodeObject(body);
    if (json['success'] != true || json['data'] is! List) {
      throw CloudException(_messageFrom(json) ?? '云端书籍加载失败');
    }

    return (json['data'] as List).whereType<Map>().map((item) {
      final book = CloudBook.fromJson(Map<String, dynamic>.from(item));
      final localBookId = localIdsByTitle[book.title];
      return book.copyWith(
        downloaded: book.downloaded || localTitles.contains(book.title),
        localBookId: localBookId,
      );
    }).toList();
  }

  Future<File> downloadBook(CloudBook book) async {
    final response = await _request(
      'GET',
      '/api/books/${book.id}/download',
      accept: 'application/epub+zip, application/octet-stream, */*',
    );
    final contentDisposition = response.headers.value('content-disposition');
    final fallbackName = '${book.title}.epub';
    final fileName =
        _fileNameFromDisposition(contentDisposition) ?? fallbackName;
    final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
    final bytes = await _readResponseBytes(response);

    if (!_looksLikeZip(bytes)) {
      throw CloudException(_messageFromDownloadBytes(bytes));
    }

    final target = File(
      p.join(
        (await _storageService.booksDir).path,
        'cloud_${book.id}_${DateTime.now().millisecondsSinceEpoch}_$safeName',
      ),
    );
    await target.writeAsBytes(bytes, flush: true);
    return target;
  }

  Future<StorageQuota> fetchQuota() async {
    final json = await _jsonRequest('GET', '/api/storage/quota');
    final data = json['data'];
    if (json['success'] != true || data is! Map) {
      throw CloudException(_messageFrom(json) ?? '存储空间加载失败');
    }
    return StorageQuota.fromJson(Map<String, dynamic>.from(data));
  }

  Future<void> deleteBook(int cloudBookId) async {
    final json = await _jsonRequest('DELETE', '/api/books/$cloudBookId');
    if (json['success'] != true) {
      throw CloudException(_messageFrom(json) ?? '云端图书删除失败');
    }
  }

  Future<int> uploadBook(
    Book book, {
    String? categoryName,
    int? localCategoryId,
  }) async {
    final session = await _requireSession();
    final absoluteBookPath = await _storageService.absolutePath(book.path);
    final bookFile = File(absoluteBookPath);
    if (!await bookFile.exists()) {
      throw const CloudException('本地图书文件不存在');
    }

    final boundary = '----epub-mobile-${DateTime.now().microsecondsSinceEpoch}';
    final body = BytesBuilder(copy: false);

    void addField(String name, Object? value) {
      if (value == null || '$value'.trim().isEmpty) return;
      body.add(utf8.encode('--$boundary\r\n'));
      body.add(
        utf8.encode(
          'Content-Disposition: form-data; name="$name"\r\n\r\n$value\r\n',
        ),
      );
    }

    Future<void> addFile(
      String name,
      File file,
      String fileName,
      String contentType,
    ) async {
      body.add(utf8.encode('--$boundary\r\n'));
      body.add(
        utf8.encode(
          'Content-Disposition: form-data; name="$name"; filename="$fileName"\r\n'
          'Content-Type: $contentType\r\n\r\n',
        ),
      );
      body.add(await file.readAsBytes());
      body.add(utf8.encode('\r\n'));
    }

    addField('title', book.title);
    addField('author', book.author);
    addField('bookPath', book.path);
    addField('localCategoryId', localCategoryId);
    addField('categoryName', categoryName);
    await addFile(
      'file',
      bookFile,
      p.basename(absoluteBookPath),
      'application/epub+zip',
    );

    if (book.coverPath != null && book.coverPath!.isNotEmpty) {
      final coverFile = File(
        await _storageService.absolutePath(book.coverPath!),
      );
      if (await coverFile.exists()) {
        await addFile(
          'coverFile',
          coverFile,
          p.basename(coverFile.path),
          'image/jpeg',
        );
      }
    }
    body.add(utf8.encode('--$boundary--\r\n'));

    final client = HttpClient();
    try {
      final request = await client.postUrl(
        Uri.parse('$baseUrl/api/books/sync'),
      );
      _applyAuthorization(request, session);
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'multipart/form-data; boundary=$boundary',
      );
      final payload = body.takeBytes();
      request.contentLength = payload.length;
      request.add(payload);
      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();
      final json = _decodeObject(responseBody);
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          json['success'] != true ||
          json['data'] is! Map) {
        throw CloudException(_messageFrom(json) ?? '同步到云端失败');
      }
      final id = _intValue((json['data'] as Map)['id']);
      if (id == null) throw const CloudException('同步响应缺少云端图书 ID');
      return id;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> syncCategories(
    List<BookCategory> categories,
    List<Book> books,
  ) async {
    final json = await _jsonRequest(
      'POST',
      '/api/categories/sync',
      body: {
        'categories': categories
            .map(
              (category) => {
                'localId': '${category.id}',
                'name': category.name,
                'color': category.color,
              },
            )
            .toList(),
        'bookCategories': books
            .where((book) => book.cloudId != null && book.categoryId != null)
            .map((book) {
              final category = categories
                  .where((item) => item.id == book.categoryId)
                  .firstOrNull;
              return {
                'bookId': book.cloudId,
                'title': book.title,
                'localCategoryId': '${book.categoryId}',
                'categoryName': category?.name,
              };
            })
            .toList(),
      },
    );
    if (json['success'] != true) {
      throw CloudException(_messageFrom(json) ?? '分类同步失败');
    }
  }

  Future<void> syncProgress(Book book, double progress, String? cfi) async {
    if (book.cloudId == null) return;
    final json = await _jsonRequest(
      'POST',
      '/api/sync/progress',
      body: {
        'bookId': book.cloudId,
        'cfi': cfi,
        'page': 0,
        'percentage': progress.clamp(0, 100) / 100,
      },
    );
    if (json['success'] != true) {
      throw CloudException(_messageFrom(json) ?? '阅读进度同步失败');
    }
  }

  Future<void> syncBookmark(Book book, Bookmark bookmark) async {
    if (book.cloudId == null) return;
    final json = await _jsonRequest(
      'POST',
      '/api/sync/bookmark',
      body: {
        'bookId': book.cloudId,
        'cfi': bookmark.cfi,
        'title': bookmark.title,
        'note': bookmark.note,
      },
    );
    if (json['success'] != true) {
      throw CloudException(_messageFrom(json) ?? '书签同步失败');
    }
  }

  Future<void> syncAnnotation(Book book, Annotation annotation) async {
    if (book.cloudId == null) return;
    final json = await _jsonRequest(
      'POST',
      '/api/sync/annotation',
      body: {
        'bookId': book.cloudId,
        'cfi': annotation.cfi,
        'selectedText': annotation.selectedText,
        'annotation': annotation.note,
        'color': annotation.color,
      },
    );
    if (json['success'] != true) {
      throw CloudException(_messageFrom(json) ?? '批注同步失败');
    }
  }

  Future<List<Map<String, dynamic>>> fetchAdminUsers() async {
    final json = await _jsonRequest('GET', '/api/admin/users');
    final data = json['data'];
    if (json['success'] != true || data is! List) {
      throw CloudException(_messageFrom(json) ?? '用户列表加载失败');
    }
    return data
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<List<Map<String, dynamic>>> fetchAdminBooks() async {
    final json = await _jsonRequest('GET', '/api/admin/books');
    final data = json['data'];
    if (json['success'] != true || data is! List) {
      throw CloudException(_messageFrom(json) ?? '书籍列表加载失败');
    }
    return data
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<Map<String, dynamic>> fetchAdminStorageConfig() async {
    final json = await _jsonRequest('GET', '/api/admin/config/storage');
    final data = json['data'];
    if (json['success'] != true || data is! Map) {
      throw CloudException(_messageFrom(json) ?? '系统配置加载失败');
    }
    return Map<String, dynamic>.from(data);
  }

  Future<void> updateAdminUser(int userId, String field, Object value) async {
    final path = switch (field) {
      'role' => 'role',
      'membershipType' => 'membership',
      'enabled' => 'enabled',
      _ => throw const CloudException('不支持的用户字段'),
    };
    final json = await _jsonRequest(
      'PUT',
      '/api/admin/users/$userId/$path',
      body: {field: value},
    );
    if (json['success'] != true) {
      throw CloudException(_messageFrom(json) ?? '用户信息更新失败');
    }
  }

  Future<void> deleteAdminUser(int userId) async {
    final json = await _jsonRequest('DELETE', '/api/admin/users/$userId');
    if (json['success'] != true) {
      throw CloudException(_messageFrom(json) ?? '用户删除失败');
    }
  }

  Future<void> saveAdminStorageConfig({
    required int readerQuotaBytes,
    required int memberQuotaBytes,
  }) async {
    final json = await _jsonRequest(
      'PUT',
      '/api/admin/config/storage',
      body: {
        'storage.reader.quota-bytes': readerQuotaBytes,
        'storage.member.quota-bytes': memberQuotaBytes,
      },
    );
    if (json['success'] != true) {
      throw CloudException(_messageFrom(json) ?? '系统配置保存失败');
    }
  }

  Future<Map<String, dynamic>> _jsonRequest(
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    final response = await _request(method, path, jsonBody: body);
    final responseBody = await response.transform(utf8.decoder).join();
    return _decodeObject(responseBody);
  }

  Future<HttpClientResponse> _request(
    String method,
    String path, {
    String accept = 'application/json',
    Map<String, Object?>? jsonBody,
  }) async {
    final session = await _requireSession();

    final client = HttpClient();
    try {
      final request = await client.openUrl(method, Uri.parse('$baseUrl$path'));
      _applyAuthorization(request, session);
      request.headers.set(HttpHeaders.acceptHeader, accept);
      if (jsonBody != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(jsonBody));
      }
      final response = await request.close();
      if (response.statusCode == 401 ||
          response.statusCode == 403 ||
          response.statusCode >= 500) {
        await _authService.logout();
        throw const AuthRequiredException('登录已失效，请重新登录');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = await response.transform(utf8.decoder).join();
        final json = _decodeObject(body);
        throw CloudException(_messageFrom(json) ?? '云端请求失败');
      }
      return response;
    } catch (_) {
      client.close(force: true);
      rethrow;
    }
  }

  Future<AuthSession> _requireSession() async {
    final session = await _authService.loadSession();
    if (session == null) throw const AuthRequiredException('请先登录');
    return session;
  }

  void _applyAuthorization(HttpClientRequest request, AuthSession session) {
    request.headers.set(
      HttpHeaders.authorizationHeader,
      session.fullToken.startsWith('Bearer ')
          ? session.fullToken
          : 'Bearer ${session.fullToken}',
    );
  }

  int? _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value');
  }

  Map<String, dynamic> _decodeObject(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // Normalize non-JSON responses.
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

  bool _looksLikeZip(Uint8List bytes) {
    if (bytes.length < 4) return false;
    return bytes[0] == 0x50 &&
        bytes[1] == 0x4b &&
        (bytes[2] == 0x03 || bytes[2] == 0x05 || bytes[2] == 0x07) &&
        (bytes[3] == 0x04 || bytes[3] == 0x06 || bytes[3] == 0x08);
  }

  String _messageFromDownloadBytes(Uint8List bytes) {
    final text = utf8.decode(bytes.take(2048).toList(), allowMalformed: true);
    final json = _decodeObject(text);
    return _messageFrom(json) ?? '下载失败：服务未返回 EPUB 文件';
  }

  String? _fileNameFromDisposition(String? value) {
    if (value == null || value.isEmpty) return null;
    final match = RegExp(
      "filename\\*?=(?:UTF-8'')?\"?([^\";]+)\"?",
    ).firstMatch(value);
    return match == null ? null : Uri.decodeFull(match.group(1)!);
  }
}

class CloudException implements Exception {
  const CloudException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AuthRequiredException extends CloudException {
  const AuthRequiredException(super.message);
}
