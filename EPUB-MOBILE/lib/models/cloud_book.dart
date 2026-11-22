class CloudBook {
  const CloudBook({
    required this.id,
    required this.title,
    this.author,
    this.coverPath,
    this.size,
    this.category = '未分类',
    this.lastRead = '',
    this.progress,
    this.downloaded = false,
    this.localBookId,
  });

  final int id;
  final String title;
  final String? author;
  final String? coverPath;
  final int? size;
  final String category;
  final String lastRead;
  final double? progress;
  final bool downloaded;
  final int? localBookId;

  CloudBook copyWith({
    bool? downloaded,
    int? localBookId,
  }) {
    return CloudBook(
      id: id,
      title: title,
      author: author,
      coverPath: coverPath,
      size: size,
      category: category,
      lastRead: lastRead,
      progress: progress,
      downloaded: downloaded ?? this.downloaded,
      localBookId: localBookId ?? this.localBookId,
    );
  }

  factory CloudBook.fromJson(Map<String, dynamic> json) {
    return CloudBook(
      id: _intValue(json['id']) ?? 0,
      title: _stringValue(json['title']) ?? '未命名图书',
      author: _stringValue(json['author']),
      coverPath: _stringValue(json['coverPath']) ??
          _stringValue(json['cover_path']) ??
          _stringValue(json['cover']),
      size: _sizeValue(json),
      category: _categoryValue(json),
      lastRead: _lastReadValue(json),
      progress: _progressValue(json),
      downloaded: _boolValue(
        json['downloaded'] ??
            json['isDownloaded'] ??
            json['is_downloaded'] ??
            json['downloadStatus'] ??
            json['download_status'],
      ),
    );
  }

  static String? _stringValue(Object? value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static int? _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static int? _sizeValue(Map<String, dynamic> json) {
    final value = json['size'] ??
        json['fileSize'] ??
        json['file_size'] ??
        json['fileSizeBytes'] ??
        json['file_size_bytes'] ??
        json['bookSize'] ??
        json['book_size'] ??
        json['bytes'];
    return _parseSize(value);
  }

  static int? _parseSize(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();

    final raw = value.toString().trim();
    if (raw.isEmpty) return null;
    final normalized = raw.replaceAll(',', '').toLowerCase();
    final match =
        RegExp(r'([\d.]+)\s*([kmgt]?i?b|bytes?)?').firstMatch(normalized);
    if (match == null) return int.tryParse(normalized);

    final number = double.tryParse(match.group(1) ?? '');
    if (number == null) return null;
    final unit = match.group(2) ?? 'b';
    final multiplier = switch (unit) {
      'kb' || 'kib' => 1024,
      'mb' || 'mib' => 1024 * 1024,
      'gb' || 'gib' => 1024 * 1024 * 1024,
      'tb' || 'tib' => 1024 * 1024 * 1024 * 1024,
      _ => 1,
    };
    return (number * multiplier).round();
  }

  static bool _boolValue(Object? value) {
    if (value is bool) return value;
    if (value is num) return value > 0;
    final text = value?.toString().toLowerCase();
    return ['true', '1', 'yes', 'downloaded', '已下载'].contains(text);
  }

  static String _categoryValue(Map<String, dynamic> json) {
    final value = json['category'] ??
        json['categoryName'] ??
        json['category_name'] ??
        json['cloudCategory'] ??
        json['cloud_category'] ??
        json['folder'] ??
        json['folderName'] ??
        json['folder_name'];
    if (value is Map) {
      return _stringValue(value['name'] ?? value['title'] ?? value['label']) ??
          '未分类';
    }
    return _stringValue(value) ?? '未分类';
  }

  static double? _progressValue(Map<String, dynamic> json) {
    final value = json['percentage'] ??
        json['progress'] ??
        json['readingProgress'] ??
        json['reading_progress'] ??
        json['progressPercentage'] ??
        json['progress_percentage'];
    final number = value is num ? value.toDouble() : double.tryParse('$value');
    if (number == null || number <= 0) return null;
    return number > 1 ? number : number * 100;
  }

  static String _lastReadValue(Map<String, dynamic> json) {
    final value = json['lastRead'] ??
        json['last_read'] ??
        json['lastReadAt'] ??
        json['last_read_at'] ??
        json['lastReadingAt'] ??
        json['last_reading_at'] ??
        json['last_read_time'] ??
        json['progressUpdatedAt'] ??
        json['progress_updated_at'];
    final text = _stringValue(value);
    if (text == null) return '';
    final date = DateTime.tryParse(text);
    if (date == null) return text;
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
