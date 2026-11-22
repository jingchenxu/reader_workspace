class BookCategory {
  const BookCategory({
    required this.id,
    required this.name,
    required this.color,
    required this.createdAt,
  });

  final int id;
  final String name;
  final String color;
  final DateTime createdAt;

  factory BookCategory.fromMap(Map<String, Object?> map) {
    return BookCategory(
      id: map['id'] as int,
      name: map['name'] as String,
      color: map['color'] as String? ?? '#667eea',
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id == 0 ? null : id,
      'name': name,
      'color': color,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
