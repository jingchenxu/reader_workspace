import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../main.dart';
import '../models/annotation.dart';
import '../models/book.dart';
import '../models/bookmark.dart';
import '../services/cloud_service.dart';
import '../services/storage_service.dart';

const _readerBlue = Color(0xff36a9e8);

String _encodeBookBytes(List<int> bytes) => base64Encode(bytes);

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, required this.book});

  final Book book;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final _storage = StorageService();
  final _cloudService = CloudService();
  late final WebViewController _controller;
  Timer? _cloudProgressTimer;

  List<Bookmark> _bookmarks = [];
  List<Annotation> _annotations = [];
  double _progress = 0;
  String? _currentCfi;
  String _readerTheme = 'paper';
  String _fontFamily = 'system';
  String _flow = 'scrolled';
  double _fontSize = 18;
  double _lineHeight = 1.6;
  bool _showChapterName = true;
  bool _showTime = true;
  bool _showBattery = true;
  bool _keepScreenOn = false;
  bool _loading = true;
  bool _chromeVisible = true;

  @override
  void initState() {
    super.initState();
    _progress = widget.book.progress;
    _currentCfi = widget.book.currentCfi;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel(
        'ReaderBridge',
        onMessageReceived: (message) => _handleBridgeMessage(message.message),
      )
      ..setNavigationDelegate(
        NavigationDelegate(onPageFinished: (_) => _loadBookIntoReader()),
      )
      ..loadFlutterAsset('assets/reader/index.html');
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadNotes());
  }

  @override
  void dispose() {
    _cloudProgressTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadBookmarks() async {
    final bookmarks = await AppScope.readDatabase(
      context,
    ).getBookmarks(widget.book.id);
    if (mounted) setState(() => _bookmarks = bookmarks);
  }

  Future<void> _loadNotes() async {
    final database = AppScope.readDatabase(context);
    final results = await Future.wait([
      database.getBookmarks(widget.book.id),
      database.getAnnotations(widget.book.id),
    ]);
    if (!mounted) return;
    setState(() {
      _bookmarks = results[0] as List<Bookmark>;
      _annotations = results[1] as List<Annotation>;
    });
  }

  Future<void> _loadBookIntoReader() async {
    final absolutePath = await _storage.absolutePath(widget.book.path);
    final bytes = await File(absolutePath).readAsBytes();
    final encodedBook = await compute(_encodeBookBytes, bytes);
    final payload = jsonEncode({
      'title': widget.book.title,
      'base64': encodedBook,
      'cfi': widget.book.currentCfi,
      'progress': widget.book.progress,
    });
    await _controller.runJavaScript('window.reader.openBook($payload);');
  }

  Future<void> _handleBridgeMessage(String rawMessage) async {
    final data = jsonDecode(rawMessage) as Map<String, dynamic>;
    switch (data['type'] as String?) {
      case 'ready':
        if (mounted) setState(() => _loading = false);
        break;
      case 'progress':
        final progress = ((data['progress'] as num?)?.toDouble() ?? 0)
            .clamp(0, 100)
            .toDouble();
        final cfi = data['cfi'] as String?;
        _progress = progress;
        _currentCfi = cfi;
        unawaited(
          AppScope.readDatabase(
            context,
          ).saveProgress(bookId: widget.book.id, progress: progress, cfi: cfi),
        );
        _scheduleCloudProgressSync(progress, cfi);
        if (mounted) setState(() {});
        break;
      case 'toggleChrome':
        if (mounted) setState(() => _chromeVisible = !_chromeVisible);
        break;
      case 'bookmark':
        await _addBookmark(data['cfi'] as String?);
        break;
      case 'annotation':
        await _saveAnnotation(data);
        break;
      case 'error':
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(data['message'] as String? ?? '阅读器加载失败')),
          );
        }
        break;
    }
  }

  Future<void> _addBookmark(String? cfi) async {
    final target = cfi ?? _currentCfi;
    if (target == null || target.isEmpty) return;
    final now = DateTime.now();
    final bookmark = Bookmark(
      id: 0,
      bookId: widget.book.id,
      cfi: target,
      title:
          '书签 ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
      createdAt: now,
    );
    await AppScope.readDatabase(context).addBookmark(bookmark);
    unawaited(_syncBookmarkSilently(bookmark));
    await _loadBookmarks();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已添加书签')));
    }
  }

  Future<void> _saveAnnotation(Map<String, dynamic> data) async {
    final cfi = data['cfi'] as String? ?? _currentCfi;
    final note = data['note'] as String? ?? '';
    if (cfi == null || note.trim().isEmpty) return;
    final annotation = Annotation(
      id: 0,
      bookId: widget.book.id,
      cfi: cfi,
      selectedText: data['selectedText'] as String? ?? '',
      note: note.trim(),
      color: '#FFEB3B',
      createdAt: DateTime.now(),
    );
    await AppScope.readDatabase(context).addAnnotation(annotation);
    unawaited(_syncAnnotationSilently(annotation));
    await _loadNotes();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('批注已保存')));
    }
  }

  void _scheduleCloudProgressSync(double progress, String? cfi) {
    if (widget.book.cloudId == null) return;
    _cloudProgressTimer?.cancel();
    _cloudProgressTimer = Timer(const Duration(seconds: 2), () async {
      try {
        await _cloudService.syncProgress(widget.book, progress, cfi);
      } catch (_) {
        // Cloud sync is best-effort and must never interrupt local reading.
      }
    });
  }

  Future<void> _syncBookmarkSilently(Bookmark bookmark) async {
    try {
      await _cloudService.syncBookmark(widget.book, bookmark);
    } catch (_) {
      // Keep the local bookmark when cloud sync is unavailable.
    }
  }

  Future<void> _syncAnnotationSilently(Annotation annotation) async {
    try {
      await _cloudService.syncAnnotation(widget.book, annotation);
    } catch (_) {
      // Keep the local annotation when cloud sync is unavailable.
    }
  }

  Future<void> _goToBookmark(Bookmark bookmark) async {
    await _controller.runJavaScript(
      'window.reader.display(${jsonEncode(bookmark.cfi)});',
    );
    if (mounted) Navigator.pop(context);
  }

  Future<void> _openBookmarks() async {
    await _loadNotes();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              ListTile(
                leading: const Icon(Icons.bookmark_add_outlined),
                title: const Text('添加当前位置为书签'),
                onTap: () {
                  Navigator.pop(context);
                  _addBookmark(_currentCfi);
                },
              ),
              const Divider(),
              if (_bookmarks.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('暂无书签')),
                )
              else
                for (final bookmark in _bookmarks)
                  ListTile(
                    leading: const Icon(Icons.bookmark_outline),
                    title: Text(bookmark.title),
                    subtitle: bookmark.note == null
                        ? null
                        : Text(bookmark.note!),
                    trailing: IconButton(
                      tooltip: '删除书签',
                      onPressed: () async {
                        await AppScope.readDatabase(
                          context,
                        ).deleteBookmark(bookmark.id);
                        if (context.mounted) Navigator.pop(context);
                        await _loadNotes();
                      },
                      icon: const Icon(Icons.delete_outline),
                    ),
                    onTap: () => _goToBookmark(bookmark),
                  ),
              const Divider(height: 28),
              const ListTile(
                leading: Icon(Icons.edit_note_outlined),
                title: Text(
                  '批注',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              if (_annotations.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('暂无批注，长按或划选正文可添加')),
                )
              else
                for (final annotation in _annotations)
                  ListTile(
                    leading: Container(
                      width: 10,
                      height: 42,
                      decoration: BoxDecoration(
                        color: const Color(0xffffd54f),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    title: Text(
                      annotation.selectedText.isEmpty
                          ? annotation.note
                          : annotation.selectedText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: annotation.selectedText.isEmpty
                        ? null
                        : Text(
                            annotation.note,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                    trailing: IconButton(
                      tooltip: '删除批注',
                      onPressed: () async {
                        await AppScope.readDatabase(
                          context,
                        ).deleteAnnotation(annotation.id);
                        if (context.mounted) Navigator.pop(context);
                        await _loadNotes();
                      },
                      icon: const Icon(Icons.delete_outline),
                    ),
                    onTap: () async {
                      await _controller.runJavaScript(
                        'window.reader.display(${jsonEncode(annotation.cfi)});',
                      );
                      if (context.mounted) Navigator.pop(context);
                    },
                  ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            void refresh(VoidCallback action) {
              action();
              setSheetState(() {});
            }

            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 20, 28, 26),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        _ThemeButton(
                          label: 'Aa',
                          selected: _readerTheme == 'paper',
                          color: Colors.white,
                          borderColor: _readerBlue,
                          onTap: () => refresh(() => _setTheme('paper')),
                        ),
                        _ThemeButton(
                          label: 'Aa',
                          selected: _readerTheme == 'cream',
                          color: const Color(0xfff7f4e8),
                          onTap: () => refresh(() => _setTheme('cream')),
                        ),
                        _ThemeButton(
                          label: 'Aa',
                          selected: _readerTheme == 'green',
                          color: const Color(0xffdceec8),
                          onTap: () => refresh(() => _setTheme('green')),
                        ),
                        _ThemeButton(
                          label: 'Aa',
                          selected: _readerTheme == 'gray',
                          color: const Color(0xff666666),
                          textColor: Colors.white70,
                          onTap: () => refresh(() => _setTheme('gray')),
                        ),
                        _ThemeButton(
                          icon: Icons.dark_mode,
                          selected: _readerTheme == 'dark',
                          color: const Color(0xff303735),
                          textColor: Colors.white70,
                          onTap: () => refresh(() => _setTheme('dark')),
                        ),
                      ],
                    ),
                    const Divider(height: 34),
                    _SettingsRow(
                      label: '间距',
                      children: [
                        _IconChoice(
                          icon: Icons.density_small,
                          selected: _lineHeight <= 1.35,
                          onTap: () => refresh(() => _changeLineHeight(-0.1)),
                        ),
                        _IconChoice(
                          icon: Icons.density_medium,
                          selected: _lineHeight > 1.35 && _lineHeight < 1.85,
                          onTap: () => refresh(() => _changeLineHeight(0.1)),
                        ),
                        _IconChoice(
                          icon: Icons.density_large,
                          selected: _lineHeight >= 1.85,
                          onTap: () => refresh(() => _changeLineHeight(0.2)),
                        ),
                      ],
                    ),
                    const Divider(height: 34),
                    _SettingsRow(
                      label: '文字',
                      children: [
                        _TextAdjustButton(
                          text: 'A-',
                          onTap: () => refresh(() => _changeFontSize(-1)),
                        ),
                        _TextAdjustButton(
                          text: 'A+',
                          onTap: () => refresh(() => _changeFontSize(1)),
                        ),
                      ],
                    ),
                    const Divider(height: 28),
                    _SettingsListTile(
                      title: '字体',
                      value: _fontFamilyLabel,
                      onTap: () {
                        Navigator.pop(context);
                        _openFontSettings();
                      },
                    ),
                    const Divider(height: 1),
                    _SettingsListTile(
                      title: '更多设置',
                      onTap: () {
                        Navigator.pop(context);
                        _openMoreSettings();
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _setTheme(String value) {
    setState(() => _readerTheme = value);
    _controller.runJavaScript('window.reader.setTheme(${jsonEncode(value)});');
  }

  void _changeFontSize(double delta) {
    setState(() => _fontSize = (_fontSize + delta).clamp(12, 32));
    _controller.runJavaScript('window.reader.changeFontSize($delta);');
  }

  void _changeLineHeight(double delta) {
    setState(() => _lineHeight = (_lineHeight + delta).clamp(1.2, 2.2));
    _controller.runJavaScript('window.reader.changeLineHeight($delta);');
  }

  String get _fontFamilyLabel {
    return switch (_fontFamily) {
      'serif' => '宋体',
      'sans' => '黑体',
      'kai' => '楷体',
      _ => '系统默认',
    };
  }

  void _setFontFamily(String value) {
    setState(() => _fontFamily = value);
    _controller.runJavaScript(
      'window.reader.setFontFamily(${jsonEncode(value)});',
    );
  }

  void _setFlow(String value) {
    setState(() => _flow = value);
    _controller.runJavaScript('window.reader.setFlow(${jsonEncode(value)});');
  }

  Future<void> _openFontSettings() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => _FontSettingsPage(
          selected: _fontFamily,
          onSelected: _setFontFamily,
        ),
      ),
    );
  }

  Future<void> _openMoreSettings() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => _MoreReaderSettingsPage(
          flow: _flow,
          showChapterName: _showChapterName,
          showTime: _showTime,
          showBattery: _showBattery,
          keepScreenOn: _keepScreenOn,
          onFlowChanged: _setFlow,
          onShowChapterNameChanged: (value) {
            setState(() => _showChapterName = value);
          },
          onShowTimeChanged: (value) {
            setState(() => _showTime = value);
          },
          onShowBatteryChanged: (value) {
            setState(() => _showBattery = value);
          },
          onKeepScreenOnChanged: (value) {
            setState(() => _keepScreenOn = value);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: !_chromeVisible,
      appBar: _chromeVisible ? _buildAppBar() : null,
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            const ColoredBox(
              color: Colors.white,
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
      bottomNavigationBar: _chromeVisible ? _buildBottomBar() : null,
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      leading: IconButton(
        tooltip: '返回',
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.chevron_left, size: 34),
      ),
      title: const SizedBox.shrink(),
      actions: [
        IconButton(
          tooltip: '目录',
          onPressed: () =>
              _controller.runJavaScript('window.reader.toggleToc();'),
          icon: const Icon(Icons.format_list_bulleted),
        ),
        IconButton(
          tooltip: '书签与批注',
          onPressed: _openBookmarks,
          icon: const Icon(Icons.collections_bookmark_outlined),
        ),
        IconButton(
          tooltip: '搜索',
          onPressed: () =>
              _controller.runJavaScript('window.reader.toggleSearch();'),
          icon: const Icon(Icons.search, size: 30),
        ),
        IconButton(
          tooltip: '阅读设置',
          onPressed: _openSettings,
          icon: const Icon(Icons.tune),
        ),
      ],
    );
  }

  Widget _buildBottomBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
        child: Row(
          children: [
            IconButton(
              tooltip: '上一页',
              onPressed: () =>
                  _controller.runJavaScript('window.reader.prev();'),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(value: _progress / 100),
                  const SizedBox(height: 4),
                  Text('${_progress.round()}%'),
                ],
              ),
            ),
            IconButton(
              tooltip: '下一页',
              onPressed: () =>
                  _controller.runJavaScript('window.reader.next();'),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeButton extends StatelessWidget {
  const _ThemeButton({
    required this.color,
    required this.onTap,
    this.label,
    this.icon,
    this.selected = false,
    this.borderColor,
    this.textColor = const Color(0xff555555),
  });

  final String? label;
  final IconData? icon;
  final Color color;
  final Color textColor;
  final Color? borderColor;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: selected
                    ? (borderColor ?? _readerBlue)
                    : const Color(0xffe4e4e4),
                width: selected ? 2 : 1,
              ),
            ),
            child: icon == null
                ? Text(
                    label ?? '',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : Icon(icon, color: textColor, size: 28),
          ),
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 70,
          child: Text(label, style: const TextStyle(fontSize: 18)),
        ),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: children,
          ),
        ),
      ],
    );
  }
}

class _IconChoice extends StatelessWidget {
  const _IconChoice({
    required this.icon,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, color: selected ? _readerBlue : const Color(0xff777777)),
    );
  }
}

class _TextAdjustButton extends StatelessWidget {
  const _TextAdjustButton({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xff333333),
            side: const BorderSide(color: Color(0xffeeeeee)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          child: Text(text, style: const TextStyle(fontSize: 20)),
        ),
      ),
    );
  }
}

class _SettingsListTile extends StatelessWidget {
  const _SettingsListTile({
    required this.title,
    required this.onTap,
    this.value,
  });

  final String title;
  final VoidCallback onTap;
  final String? value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: const TextStyle(fontSize: 18)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != null)
            Text(
              value!,
              style: const TextStyle(color: Color(0xff999999), fontSize: 16),
            ),
          const Icon(Icons.chevron_right, size: 34),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _FontSettingsPage extends StatelessWidget {
  const _FontSettingsPage({required this.selected, required this.onSelected});

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final options = const [
      ('system', '系统默认'),
      ('serif', '宋体'),
      ('sans', '黑体'),
      ('kai', '楷体'),
    ];

    return Scaffold(
      backgroundColor: const Color(0xfff7f7fb),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        centerTitle: true,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.chevron_left, size: 34),
        ),
        title: const Text('字体', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.only(top: 20),
        itemCount: options.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final option = options[index];
          final active = selected == option.$1;
          return Material(
            color: Colors.white,
            child: ListTile(
              minTileHeight: 68,
              title: Text(option.$2, style: const TextStyle(fontSize: 20)),
              trailing: active
                  ? const Icon(Icons.check, color: _readerBlue)
                  : null,
              onTap: () {
                onSelected(option.$1);
                Navigator.pop(context);
              },
            ),
          );
        },
      ),
    );
  }
}

class _MoreReaderSettingsPage extends StatefulWidget {
  const _MoreReaderSettingsPage({
    required this.flow,
    required this.showChapterName,
    required this.showTime,
    required this.showBattery,
    required this.keepScreenOn,
    required this.onFlowChanged,
    required this.onShowChapterNameChanged,
    required this.onShowTimeChanged,
    required this.onShowBatteryChanged,
    required this.onKeepScreenOnChanged,
  });

  final String flow;
  final bool showChapterName;
  final bool showTime;
  final bool showBattery;
  final bool keepScreenOn;
  final ValueChanged<String> onFlowChanged;
  final ValueChanged<bool> onShowChapterNameChanged;
  final ValueChanged<bool> onShowTimeChanged;
  final ValueChanged<bool> onShowBatteryChanged;
  final ValueChanged<bool> onKeepScreenOnChanged;

  @override
  State<_MoreReaderSettingsPage> createState() =>
      _MoreReaderSettingsPageState();
}

class _MoreReaderSettingsPageState extends State<_MoreReaderSettingsPage> {
  late String _flow = widget.flow;
  late bool _showChapterName = widget.showChapterName;
  late bool _showTime = widget.showTime;
  late bool _showBattery = widget.showBattery;
  late bool _keepScreenOn = widget.keepScreenOn;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff7f7fb),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        centerTitle: true,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.chevron_left, size: 34),
        ),
        title: const Text(
          '更多设置',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 28),
          _MoreValueTile(
            title: '阅读模式',
            value: _flow == 'scrolled' ? '滚动' : '翻页',
            onTap: _chooseFlow,
          ),
          const Divider(height: 1),
          _MoreValueTile(
            title: '轻点页面左侧',
            subtitle: '仅对翻页模式有效',
            value: '翻到上一页',
            onTap: () {},
          ),
          const Divider(height: 1),
          _MoreSwitchTile(
            title: '显示章节名',
            value: _showChapterName,
            onChanged: (value) {
              setState(() => _showChapterName = value);
              widget.onShowChapterNameChanged(value);
            },
          ),
          const Divider(height: 1),
          _MoreSwitchTile(
            title: '显示时间',
            value: _showTime,
            onChanged: (value) {
              setState(() => _showTime = value);
              widget.onShowTimeChanged(value);
            },
          ),
          const Divider(height: 1),
          _MoreSwitchTile(
            title: '显示电量',
            value: _showBattery,
            onChanged: (value) {
              setState(() => _showBattery = value);
              widget.onShowBatteryChanged(value);
            },
          ),
          const Divider(height: 1),
          _MoreSwitchTile(
            title: '屏幕保持常亮',
            value: _keepScreenOn,
            onChanged: (value) {
              setState(() => _keepScreenOn = value);
              widget.onKeepScreenOnChanged(value);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _chooseFlow() async {
    final value = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('滚动'),
                trailing: _flow == 'scrolled'
                    ? const Icon(Icons.check, color: _readerBlue)
                    : null,
                onTap: () => Navigator.pop(context, 'scrolled'),
              ),
              ListTile(
                title: const Text('翻页'),
                trailing: _flow == 'paginated'
                    ? const Icon(Icons.check, color: _readerBlue)
                    : null,
                onTap: () => Navigator.pop(context, 'paginated'),
              ),
            ],
          ),
        );
      },
    );
    if (value == null) return;
    setState(() => _flow = value);
    widget.onFlowChanged(value);
  }
}

class _MoreValueTile extends StatelessWidget {
  const _MoreValueTile({
    required this.title,
    required this.value,
    required this.onTap,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: ListTile(
        minTileHeight: subtitle == null ? 76 : 96,
        title: Text(title, style: const TextStyle(fontSize: 22)),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle!,
                style: const TextStyle(color: Color(0xffb1b1b1), fontSize: 16),
              ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: const TextStyle(color: Color(0xffb1b1b1), fontSize: 20),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, color: Color(0xffc8c8c8), size: 32),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

class _MoreSwitchTile extends StatelessWidget {
  const _MoreSwitchTile({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        title: Text(title, style: const TextStyle(fontSize: 22)),
        value: value,
        activeThumbColor: _readerBlue,
        onChanged: onChanged,
      ),
    );
  }
}
