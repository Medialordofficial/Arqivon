import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../widgets/glassmorphic_card.dart';

/// Full-screen authentication screen with Email, Google, and Apple sign-in.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isLogin = true; // toggle between sign-in & create account
  bool _loading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ── Helpers ─────────────────────────────────────────────────────

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
          _emailController.text,
          _passwordController.text,
        );
      } else {
        await auth.createAccountWithEmail(
          _emailController.text,
          _passwordController.text,
        );
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
          const SnackBar(
            content: Text('Password reset email sent!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      setState(() => _errorMessage = 'Could not send reset email.');
    }
  }

  String _friendlyError(String code) {
    switch (code) {
      case 'user-not-found':
        return 'No account found for that email.';
      case 'wrong-password':
        return 'Incorrect password.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'email-already-in-use':
        return 'An account already exists with that email.';
      case 'weak-password':
        return 'Password must be at least 6 characters.';
      case 'invalid-credential':
        return 'Invalid credentials. Please try again.';
      default:
        return 'Authentication failed ($code).';
    }
  }

  // ── Build ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final appleAvailable = ref.read(authServiceProvider).isAppleSignInAvailable;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [const Color(0xFF0F0F1A), const Color(0xFF1A1A2E)]
                : [const Color(0xFFF5F3FF), const Color(0xFFEDE9FE)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 420,
                  minHeight: size.height * 0.7,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // ── Logo ──────────────────────────────────
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF7C3AED).withOpacity(0.3),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: Image.asset(
                          'assets/images/logo.png',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Arqivon',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'The Living Lens',
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.5),
                      ),
                    ),
                    const SizedBox(height: 36),

                    // ── Email / Password form ────────────────
                    GlassmorphicCard(
                      padding: const EdgeInsets.all(24),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              _isLogin ? 'Welcome back' : 'Create account',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 20),
                            TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              decoration: _inputDecoration(
                                label: 'Email',
                                icon: Icons.email_outlined,
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
                            TextFormField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) => _submitEmail(),
                              decoration: _inputDecoration(
                                label: 'Password',
                                icon: Icons.lock_outline_rounded,
                                suffix: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    size: 20,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withOpacity(0.4),
                                  ),
                                  onPressed: () => setState(() =>
                                      _obscurePassword = !_obscurePassword),
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

                            // Forgot password
                            if (_isLogin) ...[
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: _resetPassword,
                                  child: Text(
                                    'Forgot password?',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: const Color(0xFF7C3AED)
                                          .withOpacity(0.8),
                                    ),
                                  ),
                                ),
                              ),
                            ] else
                              const SizedBox(height: 16),

                            // Error message
                            if (_errorMessage != null) ...[
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.redAccent.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.error_outline,
                                        size: 18, color: Colors.redAccent),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _errorMessage!,
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.redAccent),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],

                            // Submit button
                            SizedBox(
                              height: 50,
                              child: FilledButton(
                                onPressed: _loading ? null : _submitEmail,
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF7C3AED),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: _loading
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Text(
                                        _isLogin ? 'Sign In' : 'Create Account',
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                              ),
                            ),

                            const SizedBox(height: 12),

                            // Toggle sign-in / create account
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _isLogin
                                      ? "Don't have an account?"
                                      : 'Already have an account?',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withOpacity(0.5),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => setState(() {
                                    _isLogin = !_isLogin;
                                    _errorMessage = null;
                                  }),
                                  child: Text(
                                    _isLogin ? 'Sign Up' : 'Sign In',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF7C3AED),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ── Divider ──────────────────────────────
                    Row(
                      children: [
                        Expanded(
                          child: Divider(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.12),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'or continue with',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.4),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Divider(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.12),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // ── Social buttons ───────────────────────
                    Row(
                      children: [
                        // Google
                        Expanded(
                          child: _SocialButton(
                            onPressed: _loading ? null : _signInWithGoogle,
                            icon: _googleIcon(),
                            label: 'Google',
                          ),
                        ),
                        if (appleAvailable) ...[
                          const SizedBox(width: 12),
                          // Apple
                          Expanded(
                            child: _SocialButton(
                              onPressed: _loading ? null : _signInWithApple,
                              icon: Icon(
                                Icons.apple_rounded,
                                size: 22,
                                color: isDark ? Colors.white : Colors.black,
                              ),
                              label: 'Apple',
                            ),
                          ),
                        ],
                      ],
                    ),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20),
      suffixIcon: suffix,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.12),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.12),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF7C3AED), width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  Widget _googleIcon() {
    return SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(
        painter: _GoogleLogoPainter(),
      ),
    );
  }
}

// ── Social button widget ──────────────────────────────────────────────────────
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
      height: 52,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          side: BorderSide(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Google logo painter ─────────────────────────────────────────────────────
class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    // Blue
    final bluePaint = Paint()..color = const Color(0xFF4285F4);
    canvas.drawArc(
      Rect.fromLTWH(0, 0, w, h),
      -0.5,
      1.8,
      true,
      bluePaint,
    );

    // Green
    final greenPaint = Paint()..color = const Color(0xFF34A853);
    canvas.drawArc(
      Rect.fromLTWH(0, 0, w, h),
      1.3,
      1.2,
      true,
      greenPaint,
    );

    // Yellow
    final yellowPaint = Paint()..color = const Color(0xFFFBBC05);
    canvas.drawArc(
      Rect.fromLTWH(0, 0, w, h),
      2.5,
      1.0,
      true,
      yellowPaint,
    );

    // Red
    final redPaint = Paint()..color = const Color(0xFFEA4335);
    canvas.drawArc(
      Rect.fromLTWH(0, 0, w, h),
      3.5,
      1.3,
      true,
      redPaint,
    );

    // White center
    final whitePaint = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(w / 2, h / 2), w * 0.32, whitePaint);

    // Blue horizontal bar
    canvas.drawRect(
      Rect.fromLTWH(w * 0.48, h * 0.38, w * 0.54, h * 0.24),
      bluePaint,
    );
    // White cutout under bar
    canvas.drawRect(
      Rect.fromLTWH(w * 0.48, h * 0.38, w * 0.04, h * 0.24),
      whitePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
