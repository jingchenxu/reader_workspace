import 'package:flutter/material.dart';

import '../services/cloud_service.dart';
import '../theme/app_theme.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final _cloudService = CloudService();
  final _readerQuotaController = TextEditingController();
  final _memberQuotaController = TextEditingController();

  List<Map<String, dynamic>> _users = const [];
  List<Map<String, dynamic>> _books = const [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _readerQuotaController.dispose();
    _memberQuotaController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _cloudService.fetchAdminUsers(),
        _cloudService.fetchAdminBooks(),
        _cloudService.fetchAdminStorageConfig(),
      ]);
      final config = results[2] as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _users = results[0] as List<Map<String, dynamic>>;
        _books = results[1] as List<Map<String, dynamic>>;
        _readerQuotaController.text = _bytesToMb(
          config['storage.reader.quota-bytes'],
        ).toString();
        _memberQuotaController.text = _bytesToMb(
          config['storage.member.quota-bytes'],
        ).toString();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _mutate(Future<void> Function() action) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await action();
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteUser(Map<String, dynamic> user) async {
    if (user['username'] == 'admin') return;
    final confirmed = await _confirm('删除用户', '确定删除用户 ${user['username']} 吗？');
    if (!confirmed) return;
    await _mutate(() => _cloudService.deleteAdminUser(_intValue(user['id'])));
  }

  Future<void> _deleteBook(Map<String, dynamic> book) async {
    final confirmed = await _confirm(
      '删除云端图书',
      '确定删除《${book['title'] ?? '未命名图书'}》及其云端文件吗？',
    );
    if (!confirmed) return;
    await _mutate(() => _cloudService.deleteBook(_intValue(book['id'])));
  }

  Future<bool> _confirm(String title, String message) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.danger,
                ),
                child: const Text('确认'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _saveConfig() async {
    final readerMb = int.tryParse(_readerQuotaController.text.trim());
    final memberMb = int.tryParse(_memberQuotaController.text.trim());
    if (readerMb == null ||
        readerMb <= 0 ||
        memberMb == null ||
        memberMb <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入有效的存储配额')));
      return;
    }
    await _mutate(
      () => _cloudService.saveAdminStorageConfig(
        readerQuotaBytes: readerMb * 1024 * 1024,
        memberQuotaBytes: memberMb * 1024 * 1024,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('后台管理'),
          actions: [
            IconButton(
              tooltip: '刷新',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: '用户'),
              Tab(text: '书籍'),
              Tab(text: '配置'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? _AdminError(message: _error!, onRetry: _load)
            : TabBarView(
                children: [_buildUsers(), _buildBooks(), _buildConfig()],
              ),
      ),
    );
  }

  Widget _buildUsers() {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _users.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final user = _users[index];
          final locked = user['username'] == 'admin';
          final enabled = _boolValue(user['enabled'], fallback: true);
          return AppSectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: const Color(0xffe7f0ff),
                      child: Text(
                        '${user['username'] ?? '?'}'.characters.first,
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${user['username'] ?? '未知用户'}',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            '${user['email'] ?? ''}',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: enabled,
                      onChanged: locked || _saving
                          ? null
                          : (value) => _mutate(
                              () => _cloudService.updateAdminUser(
                                _intValue(user['id']),
                                'enabled',
                                value,
                              ),
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: '${user['role'] ?? 'READER'}',
                        decoration: const InputDecoration(labelText: '角色'),
                        items: const [
                          DropdownMenuItem(
                            value: 'READER',
                            child: Text('阅读用户'),
                          ),
                          DropdownMenuItem(value: 'ADMIN', child: Text('管理员')),
                        ],
                        onChanged: locked || _saving
                            ? null
                            : (value) {
                                if (value == null) return;
                                _mutate(
                                  () => _cloudService.updateAdminUser(
                                    _intValue(user['id']),
                                    'role',
                                    value,
                                  ),
                                );
                              },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: '${user['membershipType'] ?? 'READER'}',
                        decoration: const InputDecoration(labelText: '会员'),
                        items: const [
                          DropdownMenuItem(value: 'READER', child: Text('普通')),
                          DropdownMenuItem(value: 'MEMBER', child: Text('会员')),
                        ],
                        onChanged: _saving
                            ? null
                            : (value) {
                                if (value == null) return;
                                _mutate(
                                  () => _cloudService.updateAdminUser(
                                    _intValue(user['id']),
                                    'membershipType',
                                    value,
                                  ),
                                );
                              },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_formatSize(_intValue(user['storageUsedBytes']))} / '
                        '${user['role'] == 'ADMIN' ? '不限' : _formatSize(_intValue(user['storageQuotaBytes']))}',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '删除用户',
                      onPressed: locked || _saving
                          ? null
                          : () => _deleteUser(user),
                      icon: const Icon(
                        Icons.delete_outline,
                        color: AppColors.danger,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildBooks() {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _books.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final book = _books[index];
          return AppSectionCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 54,
                  height: 74,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    gradient: const LinearGradient(
                      colors: [AppColors.primary, AppColors.accent],
                    ),
                  ),
                  child: const Icon(Icons.auto_stories, color: Colors.white),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${book['title'] ?? '未命名图书'}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${book['ownerCount'] ?? 1} 位用户 · '
                        '${_formatSize(_intValue(book['fileSize']))}',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                      if ('${book['fileHash'] ?? ''}'.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          '${book['fileHash']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '删除图书',
                  onPressed: _saving ? null : () => _deleteBook(book),
                  icon: const Icon(
                    Icons.delete_outline,
                    color: AppColors.danger,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildConfig() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          '云端存储配额',
          style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 14),
        AppSectionCard(
          child: Column(
            children: [
              TextField(
                controller: _readerQuotaController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '普通用户配额',
                  suffixText: 'MB',
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _memberQuotaController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '会员用户配额',
                  suffixText: 'MB',
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _saveConfig,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('保存配置'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  int _bytesToMb(Object? value) => (_intValue(value) / 1024 / 1024).round();

  int _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }

  bool _boolValue(Object? value, {required bool fallback}) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value == null) return fallback;
    return value.toString().toLowerCase() == 'true';
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
  }
}

class _AdminError extends StatelessWidget {
  const _AdminError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.admin_panel_settings_outlined,
              size: 58,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 14),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 18),
            FilledButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
