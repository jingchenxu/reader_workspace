import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../main.dart';
import '../models/book.dart';
import '../models/category.dart';
import '../models/cloud_book.dart';
import '../services/cloud_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';
import 'reader_screen.dart';

enum _ShelfSort { recent, title }

class _ShelfCategoryOption {
  const _ShelfCategoryOption({
    required this.key,
    required this.label,
    this.localCategoryId,
    this.cloudCategory,
  });

  final String key;
  final String label;
  final int? localCategoryId;
  final String? cloudCategory;

  static const all = _ShelfCategoryOption(
    key: 'all',
    label: '\u5168\u90e8\u56fe\u4e66',
  );
}

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _storage = StorageService();
  final _cloudService = CloudService();
  final _searchController = TextEditingController();
  List<Book> _books = [];
  List<_ShelfCategoryOption> _categoryOptions = const [
    _ShelfCategoryOption.all,
  ];
  String _selectedCategoryKey = _ShelfCategoryOption.all.key;
  _ShelfSort _sort = _ShelfSort.recent;
  bool _hideCloudBooks = false;
  bool _loading = true;
  final Set<int> _syncingBookIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final db = AppScope.readDatabase(context);
    await _seedDefaultBooksIfNeeded();
    final categories = await db.getCategories();
    final books = await db.getBooks(query: _searchController.text);
    await _extractMissingCovers(books);
    var refreshedBooks = await db.getBooks(query: _searchController.text);
    final cloudBooks = await _loadCloudBooksForCategories(refreshedBooks);
    final cloudCategoryByTitle = <String, String>{
      for (final book in cloudBooks) book.title: book.category,
    };
    final categoryOptions = _buildCategoryOptions(categories, cloudBooks);
    var selectedCategory = categoryOptions
        .where((option) => option.key == _selectedCategoryKey)
        .firstOrNull;
    selectedCategory ??= _ShelfCategoryOption.all;

    if (selectedCategory.localCategoryId != null) {
      refreshedBooks = refreshedBooks
          .where((book) => book.categoryId == selectedCategory!.localCategoryId)
          .toList();
    } else if (selectedCategory.cloudCategory != null) {
      refreshedBooks = refreshedBooks
          .where(
            (book) =>
                cloudCategoryByTitle[book.title] ==
                selectedCategory!.cloudCategory,
          )
          .toList();
    }
    refreshedBooks = _sortBooks(
      refreshedBooks,
      hideCloudBooks: _hideCloudBooks,
      sort: _sort,
    );
    if (!mounted) return;
    setState(() {
      _categoryOptions = categoryOptions;
      _selectedCategoryKey = selectedCategory!.key;
      _books = refreshedBooks;
      _loading = false;
    });
  }

  List<_ShelfCategoryOption> _buildCategoryOptions(
    List<BookCategory> localCategories,
    List<CloudBook> cloudBooks,
  ) {
    final cloudCategoryNames =
        cloudBooks
            .map((book) => book.category.trim())
            .where(
              (category) =>
                  category.isNotEmpty && category != '\u672a\u5206\u7c7b',
            )
            .toSet()
            .toList()
          ..sort();

    return [
      _ShelfCategoryOption.all,
      for (final category in localCategories)
        _ShelfCategoryOption(
          key: 'local:${category.id}',
          label: category.name,
          localCategoryId: category.id,
        ),
      for (final category in cloudCategoryNames)
        _ShelfCategoryOption(
          key: 'cloud:$category',
          label: '\u4e91\u7aef\uff1a$category',
          cloudCategory: category,
        ),
    ];
  }

  Future<List<CloudBook>> _loadCloudBooksForCategories(
    List<Book> localBooks,
  ) async {
    try {
      return await _cloudService.fetchBooks(
        localTitles: localBooks.map((book) => book.title).toSet(),
        localIdsByTitle: {for (final book in localBooks) book.title: book.id},
      );
    } on AuthRequiredException {
      return const [];
    } catch (_) {
      return const [];
    }
  }

  List<Book> _sortBooks(
    List<Book> books, {
    required bool hideCloudBooks,
    required _ShelfSort sort,
  }) {
    final sorted = hideCloudBooks
        ? books.where((book) => !book.synced).toList()
        : List<Book>.of(books);
    if (sort == _ShelfSort.title) {
      sorted.sort((a, b) => a.title.compareTo(b.title));
    }
    return sorted;
  }

  Future<void> _extractMissingCovers(List<Book> books) async {
    final db = AppScope.readDatabase(context);
    for (final book in books) {
      if (book.coverPath != null && book.coverPath!.isNotEmpty) continue;
      var coverPath = await _storage.extractCover(book.path);
      if (coverPath == null && book.path.endsWith('default_notes.epub')) {
        await _storage.importAssetBook(
          assetPath: 'assets/books/default_notes.epub',
          fileName: 'default_notes.epub',
          overwrite: true,
        );
        coverPath = await _storage.extractCover(book.path);
      }
      if (coverPath != null) {
        await db.updateBookCover(book.id, coverPath);
      }
    }
  }

  Future<void> _seedDefaultBooksIfNeeded() async {
    final db = AppScope.readDatabase(context);
    final books = await db.getBooks();
    await _seedDefaultBookIfMissing(
      existingBooks: books,
      assetPath: 'assets/books/default_notes.epub',
      fileName: 'default_notes.epub',
      title: '\u6781\u7b80\u8d44\u6cbb\u901a\u9274 - \u9605\u8bfb\u7b14\u8bb0',
      author: '\u5f20\u5b8f\u5112',
    );
    await _seedDefaultBookIfMissing(
      existingBooks: books,
      assetPath: 'assets/books/default_logic.epub',
      fileName: 'default_logic.epub',
      title:
          '\u903b\u8f91\u5b66\u5165\u95e8\uff1a\u6e05\u6670\u601d\u8003\u3001\u7406\u6027\u751f\u6d3b\u768488\u4e2a\u903b\u8f91\u5b66\u5e38\u8bc6',
      author: '\u683c\u6851',
    );
  }

  Future<void> _seedDefaultBookIfMissing({
    required List<Book> existingBooks,
    required String assetPath,
    required String fileName,
    required String title,
    required String author,
  }) async {
    final db = AppScope.readDatabase(context);
    final relativePath = 'books/$fileName';
    final alreadyExists = existingBooks.any(
      (book) => book.path == relativePath || book.title == title,
    );
    if (alreadyExists) return;

    final imported = await _storage.importAssetBook(
      assetPath: assetPath,
      fileName: fileName,
    );
    final relative = await _storage.relativePath(imported.path);
    final coverPath = await _storage.extractCover(relative);
    await db.addBook(
      Book(
        id: 0,
        title: title,
        author: author,
        path: relative,
        coverPath: coverPath,
        addedAt: DateTime.now(),
      ),
    );
  }

  Future<void> _importEpub() async {
    final db = AppScope.readDatabase(context);
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['epub'],
    );
    if (result == null) return;

    var added = 0;
    for (final file in result.files) {
      if (file.path == null) continue;
      final imported = await _storage.importBookFile(file.path!);
      final relative = await _storage.relativePath(imported.path);
      final coverPath = await _storage.extractCover(relative);
      await db.addBook(
        Book(
          id: 0,
          title: p.basenameWithoutExtension(file.name),
          path: relative,
          coverPath: coverPath,
          addedAt: DateTime.now(),
        ),
      );
      added++;
    }

    await _load();
    if (!mounted || added == 0) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('\u5df2\u6dfb\u52a0 $added \u672c\u56fe\u4e66')),
    );
  }

  Future<void> _deleteBook(Book book) async {
    final db = AppScope.readDatabase(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('\u5220\u9664\u56fe\u4e66'),
        content: Text(
          '\u786e\u5b9a\u5220\u9664\u300a${book.title}\u300b\u5417\uff1f\u672c\u5730\u6587\u4ef6\u4e5f\u4f1a\u79fb\u9664\u3002',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('\u53d6\u6d88'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('\u5220\u9664'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _storage.deleteRelativeFile(book.path);
    await db.deleteBook(book.id);
    await _load();
  }

  Future<void> _openReader(Book book) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ReaderScreen(book: book)),
    );
    await _load();
  }

  Future<void> _showCreateCategoryDialog() async {
    final controller = TextEditingController();
    var selectedColor = '#2F80ED';
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('新建分类'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                maxLength: 30,
                decoration: const InputDecoration(hintText: '输入分类名称'),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final color in const [
                    '#2F80ED',
                    '#27AE60',
                    '#F2994A',
                    '#EB5757',
                    '#9B51E0',
                    '#00A6A6',
                  ])
                    InkWell(
                      onTap: () => setDialogState(() => selectedColor = color),
                      borderRadius: BorderRadius.circular(99),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _hexColor(color),
                          border: Border.all(
                            color: selectedColor == color
                                ? AppColors.textPrimary
                                : Colors.transparent,
                            width: 3,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                final name = controller.text.trim();
                if (name.isEmpty) return;
                try {
                  await AppScope.readDatabase(
                    context,
                  ).addCategory(name, selectedColor);
                  if (context.mounted) Navigator.pop(context, true);
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('分类名称已存在')));
                  }
                }
              },
              child: const Text('创建'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (created == true) await _load();
  }

  Future<void> _showCategoryManager() async {
    final categories = await AppScope.readDatabase(context).getCategories();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '管理分类',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 14),
              if (categories.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(child: Text('暂无自定义分类')),
                )
              else
                for (final category in categories)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      radius: 8,
                      backgroundColor: _hexColor(category.color),
                    ),
                    title: Text(category.name),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: '重命名',
                          onPressed: () async {
                            Navigator.pop(sheetContext);
                            await _editCategory(category);
                          },
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          tooltip: '删除',
                          onPressed: () async {
                            Navigator.pop(sheetContext);
                            await _removeCategory(category);
                          },
                          icon: const Icon(
                            Icons.delete_outline,
                            color: AppColors.danger,
                          ),
                        ),
                      ],
                    ),
                  ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  _showCreateCategoryDialog();
                },
                icon: const Icon(Icons.add),
                label: const Text('新建分类'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editCategory(BookCategory category) async {
    final controller = TextEditingController(text: category.name);
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名分类'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 30,
          decoration: const InputDecoration(hintText: '分类名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              await AppScope.readDatabase(
                context,
              ).updateCategory(category.id, name, category.color);
              if (context.mounted) Navigator.pop(context, true);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (saved == true) await _load();
  }

  Future<void> _removeCategory(BookCategory category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除分类'),
        content: Text('删除“${category.name}”后，分类内图书会保留在书架。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    await AppScope.readDatabase(context).deleteCategory(category.id);
    _selectedCategoryKey = _ShelfCategoryOption.all.key;
    await _load();
  }

  Future<void> _assignCategory(Book book) async {
    final categories = await AppScope.readDatabase(context).getCategories();
    if (!mounted) return;
    final categoryId = await showModalBottomSheet<int?>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
          children: [
            const ListTile(
              title: Text(
                '移动到分类',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.inbox_outlined),
              title: const Text('未分类'),
              trailing: book.categoryId == null
                  ? const Icon(Icons.check, color: AppColors.primary)
                  : null,
              onTap: () => Navigator.pop(context, -1),
            ),
            for (final category in categories)
              ListTile(
                leading: CircleAvatar(
                  radius: 7,
                  backgroundColor: _hexColor(category.color),
                ),
                title: Text(category.name),
                trailing: book.categoryId == category.id
                    ? const Icon(Icons.check, color: AppColors.primary)
                    : null,
                onTap: () => Navigator.pop(context, category.id),
              ),
          ],
        ),
      ),
    );
    if (categoryId == null) return;
    if (!mounted) return;
    await AppScope.readDatabase(
      context,
    ).updateBookCategory(book.id, categoryId == -1 ? null : categoryId);
    await _load();
  }

  Future<void> _syncBook(Book book) async {
    if (_syncingBookIds.contains(book.id)) return;
    setState(() => _syncingBookIds.add(book.id));
    try {
      final db = AppScope.readDatabase(context);
      final categories = await db.getCategories();
      final category = categories
          .where((item) => item.id == book.categoryId)
          .firstOrNull;
      final cloudId = await _cloudService.uploadBook(
        book,
        categoryName: category?.name,
        localCategoryId: category?.id,
      );
      await db.markBookSynced(book.id, cloudId);
      final refreshedBooks = await db.getBooks();
      await _cloudService.syncCategories(categories, refreshedBooks);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('《${book.title}》已同步到云端')));
      await _load();
    } on AuthRequiredException {
      if (!mounted) return;
      final result = await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
      if (result != null && mounted) await _syncBook(book);
    } on CloudException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _syncingBookIds.remove(book.id));
    }
  }

  Future<void> _deleteCloudCopy(Book book) async {
    if (book.cloudId == null) return;
    await _cloudService.deleteBook(book.cloudId!);
    if (!mounted) return;
    await AppScope.readDatabase(context).markBookUnsynced(book.id);
    await _load();
  }

  Future<void> _showBookActions(Book book) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
          children: [
            ListTile(
              title: Text(
                book.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(book.author ?? '未知作者'),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.menu_book_outlined),
              title: const Text('阅读'),
              onTap: () {
                Navigator.pop(context);
                _openReader(book);
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('移动到分类'),
              onTap: () {
                Navigator.pop(context);
                _assignCategory(book);
              },
            ),
            ListTile(
              leading: Icon(
                book.synced
                    ? Icons.cloud_done_outlined
                    : Icons.cloud_upload_outlined,
              ),
              title: Text(book.synced ? '重新同步到云端' : '同步到云端'),
              onTap: () {
                Navigator.pop(context);
                _syncBook(book);
              },
            ),
            if (book.cloudId != null)
              ListTile(
                leading: const Icon(Icons.cloud_off_outlined),
                title: const Text('仅删除云端副本'),
                onTap: () {
                  Navigator.pop(context);
                  _deleteCloudCopy(book);
                },
              ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline,
                color: AppColors.danger,
              ),
              title: const Text(
                '删除本地图书',
                style: TextStyle(color: AppColors.danger),
              ),
              onTap: () {
                Navigator.pop(context);
                _deleteBook(book);
              },
            ),
          ],
        ),
      ),
    );
  }

  static Color _hexColor(String value) {
    final normalized = value.replaceFirst('#', '');
    return Color(int.parse('ff$normalized', radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        toolbarHeight: 76,
        titleSpacing: 18,
        title: const Text('\u4e66\u67b6'),
        actions: [
          PopupMenuButton<String>(
            tooltip: '书架操作',
            icon: const Icon(
              Icons.add_circle_outline,
              color: AppColors.primary,
            ),
            onSelected: (value) {
              switch (value) {
                case 'import':
                  _importEpub();
                case 'create':
                  _showCreateCategoryDialog();
                case 'manage':
                  _showCategoryManager();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'import', child: Text('添加 EPUB 图书')),
              PopupMenuItem(value: 'create', child: Text('新建分类')),
              PopupMenuItem(value: 'manage', child: Text('管理分类')),
            ],
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Column(
        children: [
          _SearchBox(controller: _searchController, onChanged: (_) => _load()),
          _ShelfToolbar(
            count: _books.length,
            categories: _categoryOptions,
            selectedCategoryKey: _selectedCategoryKey,
            sort: _sort,
            hideCloudBooks: _hideCloudBooks,
            onCategoryChanged: (categoryKey) {
              setState(() => _selectedCategoryKey = categoryKey);
              _load();
            },
            onSortChanged: (sort) {
              setState(() => _sort = sort);
              _load();
            },
            onHideCloudChanged: (value) {
              setState(() => _hideCloudBooks = value);
              _load();
            },
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _books.isEmpty
                ? const _EmptyShelf()
                : RefreshIndicator(
                    onRefresh: _load,
                    child: GridView.builder(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 26,
                            crossAxisSpacing: 22,
                            childAspectRatio: 0.46,
                          ),
                      itemCount: _books.length,
                      itemBuilder: (context, index) {
                        final book = _books[index];
                        return _BookCard(
                          book: book,
                          onTap: () => _openReader(book),
                          onLongPress: () => _showBookActions(book),
                          syncing: _syncingBookIds.contains(book.id),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _SearchBox extends StatelessWidget {
  const _SearchBox({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
      child: SizedBox(
        height: 56,
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          style: const TextStyle(fontSize: 16),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search, size: 24),
            hintText: '输入书名或作者进行筛选',
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ),
    );
  }
}

class _ShelfToolbar extends StatelessWidget {
  const _ShelfToolbar({
    required this.count,
    required this.categories,
    required this.selectedCategoryKey,
    required this.sort,
    required this.hideCloudBooks,
    required this.onCategoryChanged,
    required this.onSortChanged,
    required this.onHideCloudChanged,
  });

  final int count;
  final List<_ShelfCategoryOption> categories;
  final String selectedCategoryKey;
  final _ShelfSort sort;
  final bool hideCloudBooks;
  final ValueChanged<String> onCategoryChanged;
  final ValueChanged<_ShelfSort> onSortChanged;
  final ValueChanged<bool> onHideCloudChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _ShelfDropdown<String>(
                  value: selectedCategoryKey,
                  items: categories
                      .map(
                        (category) => DropdownMenuItem<String>(
                          value: category.key,
                          child: Text(category.label),
                        ),
                      )
                      .toList(),
                  onChanged: onCategoryChanged,
                ),
              ),
              const SizedBox(width: 18),
              SizedBox(
                width: 128,
                child: _ShelfDropdown<_ShelfSort>(
                  value: sort,
                  items: const [
                    DropdownMenuItem<_ShelfSort>(
                      value: _ShelfSort.recent,
                      child: Text('\u6700\u8fd1\u6392\u5e8f'),
                    ),
                    DropdownMenuItem<_ShelfSort>(
                      value: _ShelfSort.title,
                      child: Text('\u4e66\u7c4d\u6392\u5e8f'),
                    ),
                  ],
                  onChanged: onSortChanged,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                height: 34,
                child: Checkbox(
                  value: hideCloudBooks,
                  activeColor: const Color(0xff36a9e8),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (value) => onHideCloudChanged(value ?? false),
                ),
              ),
              GestureDetector(
                onTap: () => onHideCloudChanged(!hideCloudBooks),
                child: const Text(
                  '\u9690\u85cf\u4e91\u7aef\u4e66\u7c4d',
                  style: TextStyle(fontSize: 15, color: Color(0xff666666)),
                ),
              ),
              const Spacer(),
              Text(
                '$count \u672c',
                style: const TextStyle(fontSize: 14, color: Color(0xff999999)),
              ),
            ],
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _ShelfDropdown<T> extends StatelessWidget {
  const _ShelfDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        value: value,
        isExpanded: true,
        icon: const Icon(Icons.arrow_drop_down, color: Color(0xff9a9a9a)),
        borderRadius: BorderRadius.circular(8),
        dropdownColor: Colors.white,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Colors.black,
        ),
        selectedItemBuilder: (context) => items
            .map(
              (item) => Align(
                alignment: Alignment.centerLeft,
                child: DefaultTextStyle.merge(
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  child: item.child,
                ),
              ),
            )
            .toList(),
        items: items,
        onChanged: (value) {
          if (value != null) onChanged(value);
        },
      ),
    );
  }
}

class _BookCard extends StatelessWidget {
  const _BookCard({
    required this.book,
    required this.onTap,
    required this.onLongPress,
    required this.syncing,
  });

  final Book book;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool syncing;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _bookStatusText(book),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: book.progress > 0
                  ? AppColors.textSecondary
                  : AppColors.warning,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: _BookCover(book: book)),
                if (book.synced || syncing)
                  Positioned(
                    right: 7,
                    top: 7,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.92),
                        shape: BoxShape.circle,
                      ),
                      child: syncing
                          ? const Padding(
                              padding: EdgeInsets.all(6),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(
                              Icons.cloud_done,
                              size: 18,
                              color: AppColors.success,
                            ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            book.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              height: 1.15,
            ),
          ),
        ],
      ),
    );
  }

  String _bookStatusText(Book book) {
    final time = book.lastReadAt ?? book.addedAt;
    final difference = DateTime.now().difference(time);
    if (book.progress <= 0) return '新添加';
    if (difference.inHours < 1) return '刚刚读过';
    if (difference.inDays < 1) return '${difference.inHours} 小时前读过';
    if (difference.inDays < 7) return '${difference.inDays} 天前读过';
    return '${time.month}月${time.day}日读过';
  }
}

class _BookCover extends StatelessWidget {
  const _BookCover({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context) {
    final coverPath = book.coverPath;
    if (coverPath != null && coverPath.isNotEmpty) {
      return FutureBuilder<String>(
        future: StorageService().absolutePath(coverPath),
        builder: (context, snapshot) {
          if (snapshot.hasData && File(snapshot.data!).existsSync()) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: Image.file(
                File(snapshot.data!),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    _GeneratedBookCover(book: book),
              ),
            );
          }
          return _GeneratedBookCover(book: book);
        },
      );
    }
    return _GeneratedBookCover(book: book);
  }
}

class _GeneratedBookCover extends StatelessWidget {
  const _GeneratedBookCover({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context) {
    final colors = _coverColors(book.title);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(2),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 4,
              width: 36,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            const Spacer(),
            Text(
              book.title,
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                height: 1.12,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (book.author != null && book.author!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                book.author!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.82),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Color> _coverColors(String title) {
    final palettes = [
      const [Color(0xffa84a3d), Color(0xff3b1512)],
      const [Color(0xff1f7a8c), Color(0xff0f2f3a)],
      const [Color(0xff215a4c), Color(0xff0f2f2b)],
      const [Color(0xffb7791f), Color(0xff4a2f0c)],
      const [Color(0xff354a77), Color(0xff17213c)],
    ];
    final index =
        title.codeUnits.fold<int>(0, (sum, unit) => sum + unit) %
        palettes.length;
    return palettes[index];
  }
}

class _EmptyShelf extends StatelessWidget {
  const _EmptyShelf();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.library_books_outlined,
              size: 78,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 14),
            const Text(
              '暂无图书',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              '鐐瑰嚮鍙充笂瑙掑姞鍙峰鍏?EPUB',
              style: TextStyle(color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }
}
