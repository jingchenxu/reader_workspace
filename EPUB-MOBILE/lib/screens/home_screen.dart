import 'dart:io';

import 'package:flutter/material.dart';

import '../main.dart';
import '../models/book.dart';
import '../models/cloud_book.dart';
import '../models/storage_quota.dart';
import '../services/api_config.dart';
import '../services/auth_service.dart';
import '../services/cloud_service.dart';
import '../services/database_service.dart';
import '../services/storage_service.dart';
import 'library_screen.dart';
import 'login_screen.dart';
import 'reader_screen.dart';
import 'settings_screen.dart';
import 'admin_screen.dart';
import '../theme/app_theme.dart';

const _brandBlue = AppColors.primary;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _authService = AuthService();
  int _currentIndex = 0;
  int _cloudTabVersion = 0;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const ReadingTab(),
      const LibraryScreen(),
      CloudTab(
        key: ValueKey(_cloudTabVersion),
        onAuthChanged: _handleAuthChanged,
      ),
      AccountTab(onAuthChanged: _handleAuthChanged),
    ];
    const destinations = <NavigationDestination>[
      NavigationDestination(icon: Icon(Icons.menu_book_outlined), label: '阅读中'),
      NavigationDestination(
        icon: Icon(Icons.library_books_outlined),
        label: '书架',
      ),
      NavigationDestination(icon: Icon(Icons.cloud_outlined), label: '云端'),
      NavigationDestination(icon: Icon(Icons.person_outline), label: '账号'),
    ];
    final currentIndex = _currentIndex >= pages.length
        ? pages.length - 1
        : _currentIndex;

    return Scaffold(
      body: IndexedStack(index: currentIndex, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        height: 72,
        backgroundColor: AppColors.surface,
        indicatorColor: const Color(0xffe7f0ff),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: _handleTabTap,
        destinations: destinations,
      ),
    );
  }

  void _handleAuthChanged(bool loggedIn) {
    setState(() {
      _cloudTabVersion++;
      if (!loggedIn && _currentIndex == 2) _currentIndex = 3;
    });
  }

  Future<void> _handleTabTap(int index) async {
    if (index != 2) {
      setState(() => _currentIndex = index);
      return;
    }

    final session = await _authService.loadSession();
    if (session == null) {
      if (!mounted) return;
      final result = await Navigator.push<AuthSession>(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
      if (result == null || !mounted) return;
      _handleAuthChanged(true);
    }

    setState(() {
      _cloudTabVersion++;
      _currentIndex = 2;
    });
  }
}

class ReadingTab extends StatefulWidget {
  const ReadingTab({super.key});

  @override
  State<ReadingTab> createState() => _ReadingTabState();
}

class _ReadingTabState extends State<ReadingTab> {
  late Future<List<Book>> _booksFuture;

  @override
  void initState() {
    super.initState();
    _booksFuture = _loadBooks();
  }

  Future<List<Book>> _loadBooks() {
    return AppScope.readDatabase(context).getBooks();
  }

  Future<void> _refresh() async {
    setState(() {
      _booksFuture = _loadBooks();
    });
    await _booksFuture;
  }

  Future<void> _openBook(Book book) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ReaderScreen(book: book)),
    );
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return _PlainTabScaffold(
      title: '阅读中',
      child: FutureBuilder<List<Book>>(
        future: _booksFuture,
        builder: (context, snapshot) {
          final books = snapshot.data ?? const <Book>[];
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (books.isEmpty) {
            return const _EmptyState(
              icon: Icons.menu_book_outlined,
              message: '最近阅读的图书会显示在这里',
            );
          }

          final reading = books.first;
          final recent = books.skip(1).toList();
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 28, 18, 30),
                  child: _LargeReadingCard(
                    book: reading,
                    actionText: reading.progress > 0 ? '继续' : '阅读',
                    onTap: () => _openBook(reading),
                  ),
                ),
                const _SectionTitle('最近读过'),
                for (final book in recent.isEmpty ? books : recent)
                  _ReadingListTile(
                    book: book,
                    actionText: book.progress > 0 ? '继续' : '阅读',
                    onTap: () => _openBook(book),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class CloudTab extends StatefulWidget {
  const CloudTab({super.key, this.onAuthChanged});

  final ValueChanged<bool>? onAuthChanged;

  @override
  State<CloudTab> createState() => _CloudTabState();
}

class _CloudTabState extends State<CloudTab> {
  final _authService = AuthService();
  final _cloudService = CloudService();
  final _storageService = StorageService();
  final _searchController = TextEditingController();
  late Future<List<CloudBook>> _booksFuture;
  late Future<StorageQuota?> _quotaFuture;
  Set<String> _localTitles = const {};
  Map<String, int> _localIdsByTitle = const {};
  final Set<int> _downloadingIds = {};

  @override
  void initState() {
    super.initState();
    _booksFuture = _loadBooks();
    _quotaFuture = _loadQuota();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<CloudBook>> _loadBooks() async {
    final database = AppScope.readDatabase(context);
    final session = await _authService.loadSession();
    if (session == null) {
      throw const AuthRequiredException('请先登录后查看云端书籍');
    }

    final localBooks = await database.getBooks();
    _localTitles = localBooks.map((book) => book.title).toSet();
    _localIdsByTitle = {for (final book in localBooks) book.title: book.id};

    final books = await _cloudService.fetchBooks(
      localTitles: _localTitles,
      localIdsByTitle: _localIdsByTitle,
    );
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return books;
    return books
        .where(
          (book) =>
              book.title.toLowerCase().contains(query) ||
              (book.author ?? '').toLowerCase().contains(query),
        )
        .toList();
  }

  Future<StorageQuota?> _loadQuota() async {
    try {
      return await _cloudService.fetchQuota();
    } catch (_) {
      return null;
    }
  }

  void _search() {
    setState(() {
      _booksFuture = _loadBooks();
      _quotaFuture = _loadQuota();
    });
  }

  Future<void> _deleteCloudBook(CloudBook cloudBook) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除云端图书'),
        content: Text('确定从云端删除《${cloudBook.title}》吗？本地图书会保留。'),
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

    try {
      await _cloudService.deleteBook(cloudBook.id);
      final localId =
          cloudBook.localBookId ?? _localIdsByTitle[cloudBook.title];
      if (localId != null && mounted) {
        await AppScope.readDatabase(context).markBookUnsynced(localId);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('云端图书已删除，本地文件已保留')));
      _search();
    } on CloudException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _openBook(CloudBook cloudBook) async {
    final database = AppScope.readDatabase(context);
    final localId = cloudBook.localBookId ?? _localIdsByTitle[cloudBook.title];
    if (localId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先下载到本地后再阅读')));
      return;
    }

    final books = await database.getBooks();
    final book = books.where((item) => item.id == localId).firstOrNull;
    if (!mounted) return;
    if (book == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('本地未找到该书籍，请重新下载')));
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ReaderScreen(book: book)),
    );
    _search();
  }

  Future<void> _downloadBook(CloudBook cloudBook) async {
    final database = AppScope.readDatabase(context);
    if (_downloadingIds.contains(cloudBook.id)) return;
    setState(() => _downloadingIds.add(cloudBook.id));
    try {
      final existingId = _localIdsByTitle[cloudBook.title];
      if (existingId != null) {
        _markCloudBookDownloaded(cloudBook, existingId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('《${cloudBook.title}》已在本地书架中')),
          );
        }
        _search();
        return;
      }

      final file = await _cloudService.downloadBook(cloudBook);
      final relativePath = await _storageService.relativePath(file.path);
      final coverPath = await _tryExtractCover(relativePath);
      final book = Book(
        id: 0,
        title: cloudBook.title,
        author: cloudBook.author,
        path: relativePath,
        coverPath: coverPath,
        addedAt: DateTime.now(),
        synced: true,
        cloudId: cloudBook.id,
      );
      final bookId = await _insertDownloadedBook(database, book);
      _markCloudBookDownloaded(cloudBook, bookId);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('《${cloudBook.title}》已下载到书架')));
      }
      _search();
    } on AuthRequiredException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
      final result = await Navigator.push<AuthSession>(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
      if (result != null) {
        widget.onAuthChanged?.call(true);
        _search();
      }
    } on CloudException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (error, stackTrace) {
      debugPrint('Failed to add downloaded book to shelf: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('文件已下载，但添加到书架失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _downloadingIds.remove(cloudBook.id));
    }
  }

  Future<int> _insertDownloadedBook(DatabaseService database, Book book) {
    return database.addOrUpdateDownloadedBook(book);
  }

  void _markCloudBookDownloaded(CloudBook cloudBook, int bookId) {
    _localTitles = {..._localTitles, cloudBook.title};
    _localIdsByTitle = {..._localIdsByTitle, cloudBook.title: bookId};
  }

  Future<String?> _tryExtractCover(String relativePath) async {
    try {
      return await _storageService.extractCover(relativePath);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return _PlainTabScaffold(
      title: '云端',
      trailing: _CloudStorageMeter(quotaFuture: _quotaFuture),
      child: Column(
        children: [
          _SearchBox(
            controller: _searchController,
            hintText: '输入书名,进行筛选',
            onChanged: (_) => _search(),
          ),
          const Divider(height: 1),
          Expanded(
            child: FutureBuilder<List<CloudBook>>(
              future: _booksFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.error is AuthRequiredException) {
                  return _LoginRequiredCloudState(
                    onLogin: () async {
                      final result = await Navigator.push<AuthSession>(
                        context,
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                      );
                      if (result != null) {
                        widget.onAuthChanged?.call(true);
                        _search();
                      }
                    },
                  );
                }
                if (snapshot.hasError) {
                  return _CloudErrorState(
                    message: snapshot.error.toString(),
                    onRetry: _search,
                  );
                }

                final books = snapshot.data ?? const <CloudBook>[];
                if (books.isEmpty) {
                  return const _EmptyState(
                    icon: Icons.cloud_outlined,
                    message: '暂无云端书籍',
                  );
                }
                return ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: books.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final book = books[index];
                    return _CloudListTile(
                      book: book,
                      downloading: _downloadingIds.contains(book.id),
                      onTap: () => _openBook(book),
                      onAction: book.downloaded
                          ? () => _openBook(book)
                          : () => _downloadBook(book),
                      onDelete: () => _deleteCloudBook(book),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class MembershipTab extends StatelessWidget {
  const MembershipTab({super.key});

  @override
  Widget build(BuildContext context) {
    return _PlainTabScaffold(
      title: '会员',
      child: Container(
        color: const Color(0xfff6f6fb),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 24, 18, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.card_membership, color: _brandBlue, size: 42),
                  SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '开通会员',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          '会员权益和云端空间将在这里展示',
                          style: TextStyle(
                            fontSize: 16,
                            color: Color(0xff9e9e9e),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AccountTab extends StatefulWidget {
  const AccountTab({super.key, this.onAuthChanged});

  final ValueChanged<bool>? onAuthChanged;

  @override
  State<AccountTab> createState() => _AccountTabState();
}

class _AccountTabState extends State<AccountTab> {
  final _authService = AuthService();
  AuthSession? _session;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  Future<void> _loadSession() async {
    final session = await _authService.loadSession();
    if (mounted) {
      setState(() {
        _session = session;
        _loading = false;
      });
    }
  }

  Future<void> _openLogin() async {
    final result = await Navigator.push<AuthSession>(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
    if (result != null && mounted) {
      setState(() => _session = result);
      widget.onAuthChanged?.call(true);
    }
  }

  Future<void> _logout() async {
    await _authService.logout();
    if (!mounted) return;
    setState(() => _session = null);
    widget.onAuthChanged?.call(false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已退出登录')));
  }

  @override
  Widget build(BuildContext context) {
    return _PlainTabScaffold(
      title: '账号',
      child: Container(
        color: const Color(0xfff6f6fb),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: EdgeInsets.zero,
                children: [
                  const SizedBox(height: 36),
                  _ProfileHeader(session: _session, onLoginTap: _openLogin),
                  const SizedBox(height: 28),
                  _AccountMenuItem(
                    icon: Icons.settings_outlined,
                    title: '设置',
                    subtitle: '账号、存储与缓存管理',
                    onTap: _openSettings,
                  ),
                  _AccountMenuItem(
                    icon: Icons.cloud_outlined,
                    title: '云空间',
                    subtitle: '查看配额与本地占用',
                    onTap: _openSettings,
                  ),
                  if (_session?.isAdmin == true)
                    _AccountMenuItem(
                      icon: Icons.admin_panel_settings_outlined,
                      title: '后台管理',
                      subtitle: '用户、书籍与存储配额',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AdminScreen()),
                      ),
                    ),
                  _AccountMenuItem(
                    icon: Icons.info_outline,
                    title: '关于 EPUB Reader',
                    subtitle: '移动端 1.0.0',
                    onTap: () => showAboutDialog(
                      context: context,
                      applicationName: 'EPUB Reader',
                      applicationVersion: '1.0.0',
                      applicationLegalese: '移动端与 PC 端共享阅读和云同步能力',
                    ),
                  ),
                  if (_session != null)
                    _AccountMenuItem(
                      icon: Icons.logout,
                      title: '退出登录',
                      onTap: _logout,
                    ),
                ],
              ),
      ),
    );
  }

  Future<void> _openSettings() async {
    final loggedOut = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          session: _session,
          onLoggedOut: () => widget.onAuthChanged?.call(false),
        ),
      ),
    );
    if (loggedOut == true && mounted) {
      setState(() => _session = null);
    }
  }
}

class _PlainTabScaffold extends StatelessWidget {
  const _PlainTabScaffold({
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        toolbarHeight: 76,
        titleSpacing: 18,
        title: Text(title),
        actions: trailing == null
            ? null
            : [
                Padding(
                  padding: const EdgeInsets.only(right: 18),
                  child: Center(child: trailing),
                ),
              ],
      ),
      body: child,
    );
  }
}

class _SearchBox extends StatelessWidget {
  const _SearchBox({
    required this.controller,
    required this.hintText,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
      child: SizedBox(
        height: 52,
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          style: const TextStyle(fontSize: 16),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search, size: 24),
            hintText: hintText,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
      child: Text(
        title,
        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _LargeReadingCard extends StatelessWidget {
  const _LargeReadingCard({
    required this.book,
    required this.actionText,
    required this.onTap,
  });

  final Book book;
  final String actionText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 132,
                height: 184,
                child: _MiniBookCover(book: book),
              ),
              const SizedBox(width: 26),
              Expanded(
                child: SizedBox(
                  height: 184,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        book.title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Icon(
                            book.synced
                                ? Icons.cloud_done_outlined
                                : Icons.history,
                            color: AppColors.textSecondary,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _relativeTime(book),
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Align(
                        alignment: Alignment.centerRight,
                        child: _PillActionButton(text: actionText),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReadingListTile extends StatelessWidget {
  const _ReadingListTile({
    required this.book,
    required this.actionText,
    required this.onTap,
  });

  final Book book;
  final String actionText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xffeeeeee))),
        ),
        child: Row(
          children: [
            SizedBox(width: 68, height: 96, child: _MiniBookCover(book: book)),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    _relativeTime(book),
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _PillActionButton(text: actionText),
          ],
        ),
      ),
    );
  }
}

class _CloudListTile extends StatelessWidget {
  const _CloudListTile({
    required this.book,
    required this.downloading,
    required this.onTap,
    required this.onAction,
    required this.onDelete,
  });

  final CloudBook book;
  final bool downloading;
  final VoidCallback onTap;
  final VoidCallback onAction;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onDelete,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
        child: Row(
          children: [
            _CloudCover(book: book),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, color: Colors.black87),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: downloading ? null : onAction,
              child: downloading
                  ? const SizedBox(
                      width: 82,
                      height: 42,
                      child: Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  : _PillActionButton(text: book.downloaded ? '阅读' : '下载'),
            ),
            PopupMenuButton<String>(
              tooltip: '更多操作',
              onSelected: (value) {
                if (value == 'delete') onDelete();
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, color: AppColors.danger),
                      SizedBox(width: 10),
                      Text('删除云端副本'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String get _subtitle {
    final parts = <String>[];
    if (book.author != null && book.author!.isNotEmpty) parts.add(book.author!);
    if (book.size != null) parts.add(_formatSize(book.size!));
    if (book.lastRead.isNotEmpty) parts.add(book.lastRead);
    return parts.isEmpty ? book.category : parts.join(' · ');
  }

  String _formatSize(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).round()} KB';
    return '$bytes B';
  }
}

class _CloudCover extends StatelessWidget {
  const _CloudCover({required this.book});

  final CloudBook book;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 98,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xfff5f5f5),
          borderRadius: BorderRadius.circular(2),
          border: Border.all(color: const Color(0xffeeeeee)),
        ),
        child: book.coverPath == null
            ? _GeneratedCloudCover(book: book)
            : Image.network(
                _coverUrl(book.coverPath!),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    _GeneratedCloudCover(book: book),
              ),
      ),
    );
  }

  String _coverUrl(String coverPath) {
    if (coverPath.startsWith('http://') || coverPath.startsWith('https://')) {
      return coverPath
          .replaceFirst(
            RegExp(r'https?://localhost(?::\d+)?'),
            ApiConfig.baseUrl,
          )
          .replaceFirst(
            RegExp(r'https?://10\.0\.2\.2(?::\d+)?'),
            ApiConfig.baseUrl,
          );
    }
    final normalized = coverPath.startsWith('/') ? coverPath : '/$coverPath';
    return '${ApiConfig.baseUrl}$normalized';
  }
}

class _GeneratedCloudCover extends StatelessWidget {
  const _GeneratedCloudCover({required this.book});

  final CloudBook book;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      color: const Color(0xffeef7fb),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('EPUB', style: TextStyle(color: _brandBlue, fontSize: 11)),
          const SizedBox(height: 8),
          Expanded(
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Text(
                book.title,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PillActionButton extends StatelessWidget {
  const _PillActionButton({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 82,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _brandBlue,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MiniBookCover extends StatelessWidget {
  const _MiniBookCover({required this.book});

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
                    _GeneratedMiniCover(book: book),
              ),
            );
          }
          return _GeneratedMiniCover(book: book);
        },
      );
    }

    return _GeneratedMiniCover(book: book);
  }
}

class _GeneratedMiniCover extends StatelessWidget {
  const _GeneratedMiniCover({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context) {
    final colors = _coverColors(book.title);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(2),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 3,
              width: 28,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            const Spacer(),
            Text(
              book.title,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 12,
                height: 1.08,
              ),
            ),
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

class _CloudStorageMeter extends StatelessWidget {
  const _CloudStorageMeter({required this.quotaFuture});

  final Future<StorageQuota?> quotaFuture;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<StorageQuota?>(
      future: quotaFuture,
      builder: (context, snapshot) {
        final quota = snapshot.data;
        final used = quota?.usedBytes ?? 0;
        final total = quota?.quotaBytes ?? 0;
        final value = quota?.usageRatio ?? 0;
        return SizedBox(
          width: 142,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                quota?.unlimited == true
                    ? '${_formatSize(used)} / 不限'
                    : '${_formatSize(used)} / ${_formatSize(total)}',
                style: const TextStyle(fontSize: 15, color: Color(0xff666666)),
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: value,
                  minHeight: 5,
                  color: _brandBlue,
                  backgroundColor: Colors.grey.shade200,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex++;
    }
    final digits = unitIndex == 0 ? 0 : 1;
    return '${value.toStringAsFixed(digits)} ${units[unitIndex]}';
  }
}

class _LoginRequiredCloudState extends StatelessWidget {
  const _LoginRequiredCloudState({required this.onLogin});

  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FilledButton(
        onPressed: onLogin,
        style: FilledButton.styleFrom(backgroundColor: _brandBlue),
        child: const Text('登录后查看云端书籍'),
      ),
    );
  }
}

class _CloudErrorState extends StatelessWidget {
  const _CloudErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 72,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 14),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 18),
            OutlinedButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.session, required this.onLoginTap});

  final AuthSession? session;
  final VoidCallback onLoginTap;

  @override
  Widget build(BuildContext context) {
    final loggedIn = session != null;
    return Column(
      children: [
        Container(
          width: 96,
          height: 96,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.primary, AppColors.accent],
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.22),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(Icons.person, size: 54, color: Colors.white),
        ),
        const SizedBox(height: 24),
        GestureDetector(
          onTap: loggedIn ? null : onLoginTap,
          child: Text(
            loggedIn ? session!.username : '登录/注册',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: loggedIn ? Colors.black : _brandBlue,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          loggedIn
              ? (session!.isAdmin ? '管理员账号' : '阅读用户 · 云端同步已开启')
              : '登录后同步书架、进度、书签和批注',
          style: const TextStyle(fontSize: 15, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _AccountMenuItem extends StatelessWidget {
  const _AccountMenuItem({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        child: ListTile(
          onTap: onTap,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 8,
          ),
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xffedf4ff),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: AppColors.primary, size: 23),
          ),
          title: Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          subtitle: subtitle == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    subtitle!,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
          trailing: const Icon(
            Icons.chevron_right,
            color: AppColors.textSecondary,
            size: 26,
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 72, color: Colors.grey.shade300),
          const SizedBox(height: 14),
          Text(message, style: TextStyle(color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}

String _relativeTime(Book book) {
  final time = book.lastReadAt ?? book.addedAt;
  final difference = DateTime.now().difference(time);
  if (difference.isNegative || difference.inMinutes < 1) return '刚刚';
  if (difference.inHours < 1) return '${difference.inMinutes} 分钟前';
  if (difference.inDays < 1) return '${difference.inHours} 小时前';
  if (difference.inDays < 7) return '${difference.inDays} 天前';
  if (difference.inDays < 30) return '${(difference.inDays / 7).floor()} 周前';
  return '${time.month}月${time.day}日';
}
