import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/annotation.dart';
import '../models/book.dart';
import '../models/bookmark.dart';
import '../models/category.dart';
import 'storage_service.dart';

class DatabaseService {
  DatabaseService(this._storageService);

  final StorageService _storageService;
  Database? _database;

  Future<Database> get database async {
    _database ??= await _open();
    return _database!;
  }

  Future<Database> _open() async {
    final root = await _storageService.rootDir;
    return openDatabase(
      p.join(root.path, 'epub_mobile.db'),
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE categories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            color TEXT NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE books (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            author TEXT,
            path TEXT NOT NULL UNIQUE,
            cover_path TEXT,
            category_id INTEGER,
            progress REAL NOT NULL DEFAULT 0,
            current_cfi TEXT,
            last_read_at TEXT,
            added_at TEXT NOT NULL,
            synced INTEGER NOT NULL DEFAULT 0,
            cloud_id INTEGER,
            FOREIGN KEY(category_id) REFERENCES categories(id) ON DELETE SET NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE bookmarks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            book_id INTEGER NOT NULL,
            cfi TEXT NOT NULL,
            title TEXT NOT NULL,
            note TEXT,
            created_at TEXT NOT NULL,
            FOREIGN KEY(book_id) REFERENCES books(id) ON DELETE CASCADE
          )
        ''');
        await db.execute('''
          CREATE TABLE annotations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            book_id INTEGER NOT NULL,
            cfi TEXT NOT NULL,
            selected_text TEXT,
            note TEXT,
            color TEXT NOT NULL,
            created_at TEXT NOT NULL,
            FOREIGN KEY(book_id) REFERENCES books(id) ON DELETE CASCADE
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_books_category ON books(category_id)',
        );
        await db.execute('CREATE INDEX idx_books_cloud_id ON books(cloud_id)');
        await db.execute(
          'CREATE INDEX idx_bookmarks_book ON bookmarks(book_id)',
        );
        await db.execute(
          'CREATE INDEX idx_annotations_book ON annotations(book_id)',
        );
      },
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE books ADD COLUMN cloud_id INTEGER');
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_books_cloud_id ON books(cloud_id)',
          );
        }
      },
    );
  }

  Future<List<Book>> getBooks({int? categoryId, String query = ''}) async {
    final db = await database;
    final where = <String>[];
    final args = <Object?>[];

    if (categoryId != null) {
      where.add('category_id = ?');
      args.add(categoryId);
    }
    if (query.trim().isNotEmpty) {
      where.add('LOWER(title) LIKE ?');
      args.add('%${query.trim().toLowerCase()}%');
    }

    final rows = await db.query(
      'books',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args,
      orderBy: 'COALESCE(last_read_at, added_at) DESC',
    );
    return rows.map(Book.fromMap).toList();
  }

  Future<bool> hasBooks() async {
    final db = await database;
    final rows = await db.rawQuery('SELECT COUNT(*) AS count FROM books');
    final count = rows.first['count'] as int? ?? 0;
    return count > 0;
  }

  Future<int> addBook(Book book) async {
    final db = await database;
    return db.insert('books', book.toMap()..remove('id'));
  }

  Future<int> addOrUpdateDownloadedBook(Book book) async {
    final db = await database;
    final existingRows = await db.query(
      'books',
      columns: ['id'],
      where: 'path = ? OR title = ?',
      whereArgs: [book.path, book.title],
      limit: 1,
    );

    final values = book.toMap()..remove('id');
    if (existingRows.isNotEmpty) {
      final id = existingRows.first['id'] as int;
      await db.update('books', values, where: 'id = ?', whereArgs: [id]);
      return id;
    }

    return db.insert(
      'books',
      values,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteBook(int id) async {
    final db = await database;
    await db.delete('books', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateBookCategory(int bookId, int? categoryId) async {
    final db = await database;
    await db.update(
      'books',
      {'category_id': categoryId},
      where: 'id = ?',
      whereArgs: [bookId],
    );
  }

  Future<void> updateBookCover(int bookId, String coverPath) async {
    final db = await database;
    await db.update(
      'books',
      {'cover_path': coverPath},
      where: 'id = ?',
      whereArgs: [bookId],
    );
  }

  Future<void> markBookSynced(int bookId, int cloudId) async {
    final db = await database;
    await db.update(
      'books',
      {'synced': 1, 'cloud_id': cloudId},
      where: 'id = ?',
      whereArgs: [bookId],
    );
  }

  Future<void> markBookUnsynced(int bookId) async {
    final db = await database;
    await db.update(
      'books',
      {'synced': 0, 'cloud_id': null},
      where: 'id = ?',
      whereArgs: [bookId],
    );
  }

  Future<void> saveProgress({
    required int bookId,
    required double progress,
    required String? cfi,
  }) async {
    final db = await database;
    await db.update(
      'books',
      {
        'progress': progress.clamp(0, 100),
        'current_cfi': cfi,
        'last_read_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [bookId],
    );
  }

  Future<List<BookCategory>> getCategories() async {
    final db = await database;
    final rows = await db.query('categories', orderBy: 'created_at ASC');
    return rows.map(BookCategory.fromMap).toList();
  }

  Future<int> addCategory(String name, String color) async {
    final db = await database;
    return db.insert('categories', {
      'name': name,
      'color': color,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> updateCategory(int id, String name, String color) async {
    final db = await database;
    await db.update(
      'categories',
      {'name': name, 'color': color},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteCategory(int id) async {
    final db = await database;
    await db.delete('categories', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Bookmark>> getBookmarks(int bookId) async {
    final db = await database;
    final rows = await db.query(
      'bookmarks',
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'created_at DESC',
    );
    return rows.map(Bookmark.fromMap).toList();
  }

  Future<int> addBookmark(Bookmark bookmark) async {
    final db = await database;
    return db.insert('bookmarks', bookmark.toMap()..remove('id'));
  }

  Future<void> deleteBookmark(int id) async {
    final db = await database;
    await db.delete('bookmarks', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Annotation>> getAnnotations(int bookId) async {
    final db = await database;
    final rows = await db.query(
      'annotations',
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'created_at DESC',
    );
    return rows.map(Annotation.fromMap).toList();
  }

  Future<int> addAnnotation(Annotation annotation) async {
    final db = await database;
    return db.insert('annotations', annotation.toMap()..remove('id'));
  }

  Future<void> deleteAnnotation(int id) async {
    final db = await database;
    await db.delete('annotations', where: 'id = ?', whereArgs: [id]);
  }
}
