class Annotation {
  const Annotation({
    required this.id,
    required this.bookId,
    required this.cfi,
    required this.selectedText,
    required this.note,
    required this.color,
    required this.createdAt,
  });

  final int id;
  final int bookId;
  final String cfi;
  final String selectedText;
  final String note;
  final String color;
  final DateTime createdAt;

  factory Annotation.fromMap(Map<String, Object?> map) {
    return Annotation(
      id: map['id'] as int,
      bookId: map['book_id'] as int,
      cfi: map['cfi'] as String,
      selectedText: map['selected_text'] as String? ?? '',
      note: map['note'] as String? ?? '',
      color: map['color'] as String? ?? '#FFEB3B',
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id == 0 ? null : id,
      'book_id': bookId,
      'cfi': cfi,
      'selected_text': selectedText,
      'note': note,
      'color': color,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
