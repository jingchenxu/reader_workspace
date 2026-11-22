class Bookmark {
  const Bookmark({
    required this.id,
    required this.bookId,
    required this.cfi,
    required this.title,
    this.note,
    required this.createdAt,
  });

  final int id;
  final int bookId;
  final String cfi;
  final String title;
  final String? note;
  final DateTime createdAt;

  factory Bookmark.fromMap(Map<String, Object?> map) {
    return Bookmark(
      id: map['id'] as int,
      bookId: map['book_id'] as int,
      cfi: map['cfi'] as String,
      title: map['title'] as String? ?? '书签',
      note: map['note'] as String?,
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id == 0 ? null : id,
      'book_id': bookId,
      'cfi': cfi,
      'title': title,
      'note': note,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
