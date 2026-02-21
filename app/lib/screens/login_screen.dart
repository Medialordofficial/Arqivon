import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/theme.dart';
import '../providers/auth_provider.dart';

/// Sign-in / create-account screen — dark Indigo design.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isLogin = true;
  bool _loading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submitEmail() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final auth = ref.read(authServiceProvider);
      if (_isLogin) {
        await auth.signInWithEmail(
            _emailController.text.trim(), _passwordController.text);
      } else {
        await auth.createAccountWithEmail(
            _emailController.text.trim(), _passwordController.text);
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = _friendlyError(e.code));
    } catch (_) {
      setState(() => _errorMessage = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() { _loading = true; _errorMessage = null; });
    try {
      await ref.read(authServiceProvider).signInWithGoogle();
    } catch (_) {
      setState(() => _errorMessage = 'Google sign-in failed. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signInWithApple() async {
    setState(() { _loading = true; _errorMessage = null; });
    try {
      await ref.read(authServiceProvider).signInWithApple();
    } catch (_) {
      setState(() => _errorMessage = 'Apple sign-in failed. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _errorMessage = 'Enter your email first, then tap Forgot.');
      return;
    }
    try {
      await ref.read(authServiceProvider).sendPasswordReset(email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Password reset email sent!'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
      }
    } catch (_) {
      setState(() => _errorMessage = 'Could not send reset email.');
    }
  }

  String _friendlyError(String code) => switch (code) {
        'user-not-found' => 'No account found for that email.',
        'wrong-password' => 'Incorrect password.',
        'invalid-email' => 'Please enter a valid email address.',
        'email-already-in-use' => 'That email is already registered.',
        'weak-password' => 'Password must be at least 6 characters.',
        'invalid-credential' => 'Incorrect email or password.',
        _ => 'Authentication failed. Please try again.',
      };

  @override
  Widget build(BuildContext context) {
    final appleAvailable = ref.read(authServiceProvider).isAppleSignInAvailable;
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0F1A),
      resizeToAvoidBottomInset: true,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0B0F1A), Color(0xFF131929), Color(0xFF1A1F35)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(24, 0, 24, bottom + 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 48),

                    // ── Logo ──────────────────────────────────────────
                    Center(
                      child: Column(
                        children: [
                          Container(
                            width: 76,
                            height: 76,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              gradient: const LinearGradient(
                                colors: [Color(0xFF5B5FEF), Color(0xFF0EA5E9)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF5B5FEF).withValues(alpha: 0.4),
                                  blurRadius: 24,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: Image.asset(
                                'assets/images/logo.png',
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.auto_awesome_rounded,
                                  color: Colors.white,
                                  size: 36,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Arqivon',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Your real-time AI assistant',
                            style: TextStyle(
                              fontSize: 14,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 40),

                    // ── Title ─────────────────────────────────────────
                    Text(
                      _isLogin ? 'Welcome back' : 'Create account',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isLogin ? 'Sign in to continue' : 'Start using Arqivon today',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF64748B),
                      ),
                    ),

                    const SizedBox(height: 28),

                    // ── Email ─────────────────────────────────────────
                    _DarkField(
                      controller: _emailController,
                      label: 'Email address',
                      icon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Email is required';
                        if (!v.contains('@')) return 'Enter a valid email';
                        return null;
                      },
                    ),

                    const SizedBox(height: 14),

                    // ── Password ──────────────────────────────────────
                    _DarkField(
                      controller: _passwordController,
                      label: 'Password',
                      icon: Icons.lock_outline,
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submitEmail(),
                      suffix: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 20,
                          color: const Color(0xFF64748B),
                        ),
                        onPressed: () =>
                            setState(() => _obscurePassword = !_obscurePassword),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Password is required';
                        if (v.length < 6) return 'At least 6 characters';
                        return null;
                      },
                    ),

                    if (_isLogin) ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: GestureDetector(
                          onTap: _resetPassword,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              'Forgot password?',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF818CF8),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ] else
                      const SizedBox(height: 14),

                    // ── Error message ─────────────────────────────────
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2D1515),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF7F1D1D)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline,
                                size: 18, color: Color(0xFFFCA5A5)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFFFCA5A5),
                                    fontWeight: FontWeight.w500),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),

                    // ── Primary action ────────────────────────────────
                    SizedBox(
                      height: 56,
                      child: FilledButton(
                        onPressed: _loading ? null : _submitEmail,
                        style: FilledButton.styleFrom(
                          backgroundColor: ArqivonTheme.primary,
                          disabledBackgroundColor: const Color(0xFF2D3256),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        child: _loading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.5, color: Colors.white))
                            : Text(
                                _isLogin ? 'Sign In' : 'Create Account',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ── Toggle ────────────────────────────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _isLogin
                              ? "Don't have an account?"
                              : 'Already have an account?',
                          style: const TextStyle(
                              fontSize: 14, color: Color(0xFF64748B)),
                        ),
                        const SizedBox(width: 2),
                        GestureDetector(
                          onTap: () => setState(() {
                            _isLogin = !_isLogin;
                            _errorMessage = null;
                          }),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 8),
                            child: Text(
                              _isLogin ? 'Sign Up' : 'Sign In',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF818CF8),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 28),

                    // ── Divider ───────────────────────────────────────
                    Row(
                      children: [
                        Expanded(
                          child: Divider(
                              color: Colors.white.withValues(alpha: 0.1),
                              thickness: 1),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'or',
                            style: TextStyle(
                                fontSize: 13, color: Color(0xFF475569)),
                          ),
                        ),
                        Expanded(
                          child: Divider(
                              color: Colors.white.withValues(alpha: 0.1),
                              thickness: 1),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // ── Social buttons ────────────────────────────────
                    Row(
                      children: [
                        Expanded(
                          child: _SocialBtn(
                            onTap: _loading ? null : _signInWithGoogle,
                            icon: const _GoogleIcon(),
                            label: 'Google',
                          ),
                        ),
                        if (appleAvailable) ...[
                          const SizedBox(width: 12),
                          Expanded(
                            child: _SocialBtn(
                              onTap: _loading ? null : _signInWithApple,
                              icon: const Icon(Icons.apple_rounded,
                                  size: 22, color: Colors.white),
                              label: 'Apple',
                            ),
                          ),
                        ],
                      ],
                    ),

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Dark input field ──────────────────────────────────────────────────────────
class _DarkField extends StatelessWidget {
  const _DarkField({
    required this.controller,
    required this.label,
    required this.icon,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
    this.suffix,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final Widget? suffix;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onFieldSubmitted: onSubmitted,
      validator: validator,
      style: const TextStyle(
        fontSize: 16,
        color: Colors.white,
        fontWeight: FontWeight.w500,
      ),
      cursorColor: ArqivonTheme.primary,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          fontSize: 14,
          color: Color(0xFF64748B),
        ),
        floatingLabelStyle: const TextStyle(
          fontSize: 13,
          color: Color(0xFF818CF8),
        ),
        prefixIcon: Icon(icon, size: 20, color: const Color(0xFF64748B)),
        suffixIcon: suffix,
        filled: true,
        fillColor: const Color(0xFF1E2640),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF2D3A5A), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              const BorderSide(color: ArqivonTheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
        ),
        errorStyle: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 12),
      ),
    );
  }
}

// ── Social button ─────────────────────────────────────────────────────────────
class _SocialBtn extends StatelessWidget {
  const _SocialBtn({
    required this.onTap,
    required this.icon,
    required this.label,
  });

  final VoidCallback? onTap;
  final Widget icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: const Color(0xFF1E2640),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF2D3A5A), width: 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Google icon ────────────────────────────────────────────────────────────────
class _GoogleIcon extends StatelessWidget {
  const _GoogleIcon();

  @override
  Widget build(BuildContext context) =>
      SizedBox(width: 22, height: 22, child: CustomPaint(painter: _GooglePainter()));
}

class _GooglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, h / 2);
    final radius = w / 2;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), -0.52,
        1.82, true, Paint()..color = const Color(0xFF4285F4));
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), 1.30,
        1.18, true, Paint()..color = const Color(0xFF34A853));
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), 2.48,
        1.00, true, Paint()..color = const Color(0xFFFBBC05));
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), 3.48,
        1.34, true, Paint()..color = const Color(0xFFEA4335));
    canvas.drawCircle(center, radius * 0.60, Paint()..color = const Color(0xFF1E2640));
    canvas.drawRect(
        Rect.fromLTWH(w * 0.48, h * 0.38, w * 0.52, h * 0.24),
        Paint()..color = const Color(0xFF4285F4));
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}
