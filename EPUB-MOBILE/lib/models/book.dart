class Book {
  const Book({
    required this.id,
    required this.title,
    required this.path,
    this.author,
    this.coverPath,
    this.categoryId,
    this.progress = 0,
    this.currentCfi,
    this.lastReadAt,
    required this.addedAt,
    this.synced = false,
    this.cloudId,
  });

  final int id;
  final String title;
  final String path;
  final String? author;
  final String? coverPath;
  final int? categoryId;
  final double progress;
  final String? currentCfi;
  final DateTime? lastReadAt;
  final DateTime addedAt;
  final bool synced;
  final int? cloudId;

  Book copyWith({
    int? id,
    String? title,
    String? path,
    String? author,
    String? coverPath,
    int? categoryId,
    double? progress,
    String? currentCfi,
    DateTime? lastReadAt,
    DateTime? addedAt,
    bool? synced,
    int? cloudId,
    bool clearCloudId = false,
  }) {
    return Book(
      id: id ?? this.id,
      title: title ?? this.title,
      path: path ?? this.path,
      author: author ?? this.author,
      coverPath: coverPath ?? this.coverPath,
      categoryId: categoryId ?? this.categoryId,
      progress: progress ?? this.progress,
      currentCfi: currentCfi ?? this.currentCfi,
      lastReadAt: lastReadAt ?? this.lastReadAt,
      addedAt: addedAt ?? this.addedAt,
      synced: synced ?? this.synced,
      cloudId: clearCloudId ? null : (cloudId ?? this.cloudId),
    );
  }

  factory Book.fromMap(Map<String, Object?> map) {
    return Book(
      id: map['id'] as int,
      title: map['title'] as String,
      path: map['path'] as String,
      author: map['author'] as String?,
      coverPath: map['cover_path'] as String?,
      categoryId: map['category_id'] as int?,
      progress: (map['progress'] as num?)?.toDouble() ?? 0,
      currentCfi: map['current_cfi'] as String?,
      lastReadAt: _parseDate(map['last_read_at']),
      addedAt: _parseDate(map['added_at']) ?? DateTime.now(),
      synced: (map['synced'] as int? ?? 0) == 1,
      cloudId: map['cloud_id'] as int?,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id == 0 ? null : id,
      'title': title,
      'path': path,
      'author': author,
      'cover_path': coverPath,
      'category_id': categoryId,
      'progress': progress,
      'current_cfi': currentCfi,
      'last_read_at': lastReadAt?.toIso8601String(),
      'added_at': addedAt.toIso8601String(),
      'synced': synced ? 1 : 0,
      'cloud_id': cloudId,
    };
  }

  static DateTime? _parseDate(Object? value) {
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }
}
