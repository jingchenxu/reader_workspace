import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _authService = AuthService();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _captchaController = TextEditingController();
  bool _acceptedTerms = false;
  bool _obscurePassword = true;
  bool _loading = false;
  bool _captchaLoading = false;
  Uint8List? _captchaBytes;

  @override
  void initState() {
    super.initState();
    _loadCaptcha();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _captchaController.dispose();
    super.dispose();
  }

  Future<void> _loadCaptcha() async {
    if (mounted) setState(() => _captchaLoading = true);
    try {
      final bytes = await _authService.fetchCaptcha();
      if (!mounted) return;
      setState(() {
        _captchaBytes = bytes;
        _captchaLoading = false;
      });
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() => _captchaLoading = false);
      _showMessage(error.message);
    }
  }

  void _refreshCaptcha() {
    _captchaController.clear();
    _loadCaptcha();
  }

  Future<void> _login() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final captcha = _captchaController.text.trim();
    if (username.isEmpty || password.isEmpty) {
      _showMessage('请输入账号和密码');
      return;
    }
    if (captcha.isEmpty) {
      _showMessage('请输入图形验证码');
      return;
    }
    if (!_acceptedTerms) {
      _showMessage('请先阅读并同意用户服务条款及隐私条款');
      return;
    }

    setState(() => _loading = true);
    try {
      final session = await _authService.login(
        username: username,
        password: password,
        captcha: captcha,
      );
      if (mounted) Navigator.pop(context, session);
    } on AuthException catch (error) {
      _showMessage(error.message);
      _refreshCaptcha();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton.filledTonal(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ),
                const SizedBox(height: 22),
                Container(
                  width: 68,
                  height: 68,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    gradient: const LinearGradient(
                      colors: [AppColors.primary, AppColors.accent],
                    ),
                  ),
                  child: const Icon(
                    Icons.auto_stories,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 22),
                const Text(
                  '欢迎回来',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '登录后在手机与 PC 之间同步书架、进度、书签和批注。',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 15,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 28),
                AppSectionCard(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    children: [
                      _LoginTextField(
                        controller: _usernameController,
                        hintText: '账号或邮箱',
                        prefixIcon: const Icon(Icons.person_outline),
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [
                          AutofillHints.username,
                          AutofillHints.email,
                        ],
                      ),
                      const SizedBox(height: 14),
                      _LoginTextField(
                        controller: _passwordController,
                        hintText: '密码',
                        prefixIcon: const Icon(Icons.lock_outline),
                        obscureText: _obscurePassword,
                        autofillHints: const [AutofillHints.password],
                        suffixIcon: IconButton(
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: _LoginTextField(
                              controller: _captchaController,
                              hintText: '图形验证码',
                              prefixIcon: const Icon(Icons.verified_outlined),
                              keyboardType: TextInputType.text,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _login(),
                            ),
                          ),
                          const SizedBox(width: 12),
                          InkWell(
                            onTap: _captchaLoading ? null : _refreshCaptcha,
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              width: 116,
                              height: 54,
                              clipBehavior: Clip.antiAlias,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: const Color(0xfff0f3f8),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: _captchaLoading
                                  ? const SizedBox.square(
                                      dimension: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : _captchaBytes == null
                                  ? const Icon(Icons.refresh)
                                  : Image.memory(
                                      _captchaBytes!,
                                      width: 116,
                                      height: 54,
                                      fit: BoxFit.cover,
                                      gaplessPlayback: true,
                                    ),
                            ),
                          ),
                        ],
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: _captchaLoading ? null : _refreshCaptcha,
                          icon: const Icon(Icons.refresh, size: 17),
                          label: const Text('刷新验证码'),
                        ),
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Checkbox(
                            value: _acceptedTerms,
                            onChanged: (value) =>
                                setState(() => _acceptedTerms = value ?? false),
                          ),
                          const SizedBox(width: 4),
                          const Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(top: 11),
                              child: Text.rich(
                                TextSpan(
                                  text: '我已阅读并同意 ',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13,
                                  ),
                                  children: [
                                    TextSpan(
                                      text: '《用户服务条款》与《隐私条款》',
                                      style: TextStyle(
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _loading ? null : _login,
                          child: _loading
                              ? const SizedBox.square(
                                  dimension: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('登录'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LoginTextField extends StatelessWidget {
  const _LoginTextField({
    required this.controller,
    required this.hintText,
    this.keyboardType,
    this.obscureText = false,
    this.suffixIcon,
    this.prefixIcon,
    this.autofillHints,
    this.textInputAction,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hintText;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? suffixIcon;
  final Widget? prefixIcon;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      autofillHints: autofillHints,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      style: const TextStyle(fontSize: 16),
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: prefixIcon,
        suffixIcon: suffixIcon,
      ),
    );
  }
}
