import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../models/storage_quota.dart';
import '../services/auth_service.dart';
import '../services/cloud_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.session, this.onLoggedOut});

  final AuthSession? session;
  final VoidCallback? onLoggedOut;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _authService = AuthService();
  final _cloudService = CloudService();
  final _storageService = StorageService();

  StorageQuota? _quota;
  int _booksBytes = 0;
  int _cacheBytes = 0;
  bool _loading = true;
  bool _clearingCache = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final booksDir = await _storageService.booksDir;
    final cacheDir = await getTemporaryDirectory();
    final results = await Future.wait([
      _directorySize(booksDir),
      _directorySize(cacheDir),
    ]);

    StorageQuota? quota;
    if (widget.session != null) {
      try {
        quota = await _cloudService.fetchQuota();
      } catch (_) {
        quota = null;
      }
    }
    if (!mounted) return;
    setState(() {
      _booksBytes = results[0];
      _cacheBytes = results[1];
      _quota = quota;
      _loading = false;
    });
  }

  Future<int> _directorySize(Directory directory) async {
    if (!await directory.exists()) return 0;
    var total = 0;
    await for (final entity in directory.list(recursive: true)) {
      if (entity is File) {
        try {
          total += await entity.length();
        } catch (_) {
          // Ignore files that disappear while the size is being calculated.
        }
      }
    }
    return total;
  }

  Future<void> _clearCache() async {
    if (_clearingCache) return;
    setState(() => _clearingCache = true);
    final cacheDir = await getTemporaryDirectory();
    if (await cacheDir.exists()) {
      await for (final entity in cacheDir.list()) {
        try {
          await entity.delete(recursive: true);
        } catch (_) {
          // Some active WebView files may be locked; keep them and continue.
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _cacheBytes = 0;
      _clearingCache = false;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('缓存已清理')));
  }

  Future<void> _logout() async {
    await _authService.logout();
    widget.onLoggedOut?.call();
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                _SectionTitle('账号'),
                AppSectionCard(
                  child: Column(
                    children: [
                      _SettingRow(
                        icon: Icons.account_circle_outlined,
                        title: '当前账号',
                        value: widget.session?.username ?? '未登录',
                      ),
                      if (widget.session?.email?.isNotEmpty == true) ...[
                        const Divider(),
                        _SettingRow(
                          icon: Icons.mail_outline,
                          title: '邮箱',
                          value: widget.session!.email!,
                        ),
                      ],
                      if (widget.session != null) ...[
                        const Divider(),
                        _SettingRow(
                          icon: Icons.verified_user_outlined,
                          title: '账号类型',
                          value: widget.session!.isAdmin ? '管理员' : '阅读用户',
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _SectionTitle('存储管理'),
                AppSectionCard(
                  child: Column(
                    children: [
                      _SettingRow(
                        icon: Icons.library_books_outlined,
                        title: '本地图书',
                        value: _formatSize(_booksBytes),
                      ),
                      const Divider(),
                      _SettingRow(
                        icon: Icons.cached_outlined,
                        title: '缓存空间',
                        value: _formatSize(_cacheBytes),
                      ),
                      if (_quota != null) ...[
                        const Divider(),
                        _CloudQuotaRow(quota: _quota!),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _clearingCache ? null : _clearCache,
                  icon: _clearingCache
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cleaning_services_outlined),
                  label: const Text('清理缓存'),
                ),
                const SizedBox(height: 24),
                _SectionTitle('应用信息'),
                const AppSectionCard(
                  child: Column(
                    children: [
                      _SettingRow(
                        icon: Icons.language_outlined,
                        title: '语言',
                        value: '简体中文',
                      ),
                      Divider(),
                      _SettingRow(
                        icon: Icons.info_outline,
                        title: '版本',
                        value: '1.0.0',
                      ),
                    ],
                  ),
                ),
                if (widget.session != null) ...[
                  const SizedBox(height: 28),
                  FilledButton.tonalIcon(
                    onPressed: _logout,
                    icon: const Icon(Icons.logout),
                    label: const Text('退出登录'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xffffecec),
                      foregroundColor: AppColors.danger,
                    ),
                  ),
                ],
              ],
            ),
    );
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xffedf4ff),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 21, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CloudQuotaRow extends StatelessWidget {
  const _CloudQuotaRow({required this.quota});

  final StorageQuota quota;

  @override
  Widget build(BuildContext context) {
    String format(int bytes) {
      if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
      if (bytes < 1024 * 1024 * 1024) {
        return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
      }
      return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.cloud_outlined, color: AppColors.primary),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  '云端空间',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                quota.unlimited
                    ? '${format(quota.usedBytes)} / 不限'
                    : '${format(quota.usedBytes)} / ${format(quota.quotaBytes)}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          if (!quota.unlimited) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                minHeight: 7,
                value: quota.usageRatio,
                backgroundColor: const Color(0xffeaf0f8),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
