import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/theme.dart';
import '../providers/auth_provider.dart';

/// Sign-in / create-account screen — coffee brown × white design.
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
            _emailController.text, _passwordController.text);
      } else {
        await auth.createAccountWithEmail(
            _emailController.text, _passwordController.text);
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = _friendlyError(e.code));
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      await ref.read(authServiceProvider).signInWithGoogle();
    } catch (e) {
      setState(
          () => _errorMessage = 'Google sign-in failed. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signInWithApple() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      await ref.read(authServiceProvider).signInWithApple();
    } catch (e) {
      setState(() => _errorMessage = 'Apple sign-in failed. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _errorMessage = 'Enter your email first, then tap Reset.');
      return;
    }
    try {
      await ref.read(authServiceProvider).sendPasswordReset(email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Password reset email sent!')));
      }
    } catch (e) {
      setState(() => _errorMessage = 'Could not send reset email.');
    }
  }

  String _friendlyError(String code) => switch (code) {
        'user-not-found' => 'No account found for that email.',
        'wrong-password' => 'Incorrect password.',
        'invalid-email' => 'Please enter a valid email address.',
        'email-already-in-use' => 'An account already exists with that email.',
        'weak-password' => 'Password must be at least 6 characters.',
        'invalid-credential' => 'Invalid credentials. Please try again.',
        _ => 'Authentication failed ($code).',
      };

  @override
  Widget build(BuildContext context) {
    final appleAvailable = ref.read(authServiceProvider).isAppleSignInAvailable;

    return Scaffold(
      backgroundColor: ArqivoTheme.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 52),

                  // ── Logo + wordmark ────────────────────────
                  Center(
                    child: Column(children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x22000000),
                              blurRadius: 20,
                              offset: Offset(0, 6),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Image.asset(
                            'assets/images/logo.png',
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Arqivo',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: ArqivoTheme.espresso,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'The Living Lens',
                        style: TextStyle(
                          fontSize: 13,
                          color: ArqivoTheme.warmGrey,
                        ),
                      ),
                    ]),
                  ),

                  const SizedBox(height: 40),

                  // ── Auth card ──────────────────────────────
                  Container(
                    decoration: BoxDecoration(
                      color: ArqivoTheme.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFE8D9CF)),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x0A3E1F0D),
                          blurRadius: 24,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(24),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            _isLogin ? 'Welcome back' : 'Create account',
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                              color: ArqivoTheme.inkBrown,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _isLogin
                                ? 'Sign in to continue'
                                : 'Join Arqivo today',
                            style: const TextStyle(
                              fontSize: 13,
                              color: ArqivoTheme.warmGrey,
                            ),
                          ),
                          const SizedBox(height: 22),

                          // Email
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            style: const TextStyle(
                                fontSize: 14, color: ArqivoTheme.inkBrown),
                            decoration: const InputDecoration(
                              labelText: 'Email address',
                              prefixIcon: Icon(Icons.email_outlined, size: 19),
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Email is required';
                              }
                              if (!v.contains('@')) {
                                return 'Enter a valid email';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),

                          // Password
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _submitEmail(),
                            style: const TextStyle(
                                fontSize: 14, color: ArqivoTheme.inkBrown),
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon:
                                  const Icon(Icons.lock_outline, size: 19),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  size: 19,
                                  color: ArqivoTheme.warmGrey,
                                ),
                                onPressed: () => setState(
                                    () => _obscurePassword = !_obscurePassword),
                              ),
                            ),
                            validator: (v) {
                              if (v == null || v.isEmpty) {
                                return 'Password is required';
                              }
                              if (v.length < 6) {
                                return 'At least 6 characters';
                              }
                              return null;
                            },
                          ),

                          if (_isLogin) ...[
                            const SizedBox(height: 6),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: _resetPassword,
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: const Text('Forgot password?',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: ArqivoTheme.caramel)),
                              ),
                            ),
                          ] else
                            const SizedBox(height: 14),

                          // Error
                          if (_errorMessage != null) ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF0F0),
                                borderRadius: BorderRadius.circular(10),
                                border:
                                    Border.all(color: const Color(0xFFFFCCCC)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.error_outline,
                                      size: 16, color: ArqivoTheme.errorRed),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(_errorMessage!,
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: ArqivoTheme.errorRed)),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          const SizedBox(height: 20),

                          // Submit
                          SizedBox(
                            height: 50,
                            child: FilledButton(
                              onPressed: _loading ? null : _submitEmail,
                              style: FilledButton.styleFrom(
                                backgroundColor: ArqivoTheme.espresso,
                                disabledBackgroundColor:
                                    const Color(0xFFBBA090),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                              child: _loading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: Colors.white))
                                  : Text(
                                      _isLogin ? 'Sign In' : 'Create Account',
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                            ),
                          ),

                          const SizedBox(height: 16),

                          // Toggle
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _isLogin
                                    ? "Don't have an account?"
                                    : 'Already have an account?',
                                style: const TextStyle(
                                    fontSize: 13, color: ArqivoTheme.warmGrey),
                              ),
                              TextButton(
                                onPressed: () => setState(() {
                                  _isLogin = !_isLogin;
                                  _errorMessage = null;
                                }),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.only(left: 6),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: Text(
                                  _isLogin ? 'Sign Up' : 'Sign In',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: ArqivoTheme.caramel,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  // ── Divider ────────────────────────────────
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'or continue with',
                          style: TextStyle(
                              fontSize: 12,
                              color: ArqivoTheme.warmGrey.withOpacity(0.8)),
                        ),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // ── Social ─────────────────────────────────
                  Row(
                    children: [
                      Expanded(
                        child: _SocialButton(
                          onPressed: _loading ? null : _signInWithGoogle,
                          icon: const _GoogleIcon(),
                          label: 'Google',
                        ),
                      ),
                      if (appleAvailable) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: _SocialButton(
                            onPressed: _loading ? null : _signInWithApple,
                            icon: const Icon(Icons.apple_rounded,
                                size: 20, color: ArqivoTheme.espresso),
                            label: 'Apple',
                          ),
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: 48),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Social button ──────────────────────────────────────────────────────────────
class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.onPressed,
    required this.icon,
    required this.label,
  });

  final VoidCallback? onPressed;
  final Widget icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: ArqivoTheme.inkBrown,
          backgroundColor: ArqivoTheme.cream,
          side: const BorderSide(color: Color(0xFFDDD0C8)),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            const SizedBox(width: 10),
            Text(label,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: ArqivoTheme.inkBrown)),
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
  Widget build(BuildContext context) => SizedBox(
      width: 20, height: 20, child: CustomPaint(painter: _GooglePainter()));
}

class _GooglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, h / 2);
    final radius = w / 2;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), -0.52, 1.82,
        true, Paint()..color = const Color(0xFF4285F4));
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), 1.30, 1.18,
        true, Paint()..color = const Color(0xFF34A853));
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), 2.48, 1.00,
        true, Paint()..color = const Color(0xFFFBBC05));
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), 3.48, 1.34,
        true, Paint()..color = const Color(0xFFEA4335));
    canvas.drawCircle(center, radius * 0.60, Paint()..color = Colors.white);
    canvas.drawRect(Rect.fromLTWH(w * 0.48, h * 0.38, w * 0.52, h * 0.24),
        Paint()..color = const Color(0xFF4285F4));
    canvas.drawRect(Rect.fromLTWH(w * 0.48, h * 0.38, w * 0.02, h * 0.24),
        Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}
