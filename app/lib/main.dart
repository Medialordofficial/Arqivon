import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config/logger.dart';
import 'config/theme.dart';
import 'firebase_options.dart';
import 'providers/auth_provider.dart';
import 'providers/firebase_provider.dart';
import 'providers/live_session_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/archive_screen.dart';
import 'screens/home_screen.dart';
import 'screens/live_screen.dart';
import 'screens/login_screen.dart';
import 'screens/notes_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/settings_screen.dart';
import 'services/fcm_service.dart';
import 'services/notification_service.dart';
import 'widgets/offline_banner.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialise Firebase and SharedPreferences in parallel before the first
  // frame — both are fast on-device and this removes the loading splash delay.
  final results = await Future.wait([
    Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform),
    SharedPreferences.getInstance(),
  ]);
  final prefs = results[1] as SharedPreferences;

  // ── Firebase Crashlytics ─────────────────────────────────────────
  // Catch Flutter framework errors (widget build, layout, paint).
  FlutterError.onError = (errorDetails) {
    FirebaseCrashlytics.instance.recordFlutterError(errorDetails);
  };

  // Catch async Dart errors not handled by Flutter framework.
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: false);
    return true;
  };

  // Disable crash collection in debug builds to avoid noise.
  await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
    kReleaseMode,
  );

  // Structured logging — replaces raw print() everywhere.
  AppLogger.init();

  // ── Firebase Cloud Messaging ──────────────────────────────────────
  // Request permissions, obtain device token, and save it to Firestore
  // so the backend can send push notifications.
  unawaited(FcmService.init());

  // ── Local Notifications (Reminders) ───────────────────────────────
  unawaited(NotificationService.instance.init());

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
    ),
  );

  runApp(ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
    ],
    child: const ArqivonApp(),
  ));
}

class ArqivonApp extends ConsumerWidget {
  const ArqivonApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(settingsProvider).themeMode;
    final isDark = themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        systemNavigationBarColor:
            isDark ? const Color(0xFF1A130D) : Colors.white,
        systemNavigationBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
      ),
      child: MaterialApp(
        title: 'Arqivon',
        debugShowCheckedModeBanner: false,
        themeMode: themeMode,
        theme: ArqivonTheme.lightTheme,
        darkTheme: ArqivonTheme.darkTheme,
        home: const AuthGate(),
      ),
    );
  }
}

/// Shows onboarding → [LoginScreen] → [MainNavigator] based on state.
/// Waits for Firebase to finish initialising before rendering auth state.
class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  /// Start as null (unknown) — show splash until prefs are loaded.
  bool? _onboardingDone;

  /// Ensure splash stays visible long enough to show slogan animation.
  bool _splashMinTimeElapsed = false;

  @override
  void initState() {
    super.initState();
    _checkOnboarding();
    Future.delayed(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _splashMinTimeElapsed = true);
    });
  }

  Future<void> _checkOnboarding() async {
    final prefs = ref.read(sharedPrefsProvider);
    final done = prefs.getBool('onboarding_complete') ?? false;
    if (mounted) setState(() => _onboardingDone = done);
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_complete', true);
    if (mounted) setState(() => _onboardingDone = true);
  }

  @override
  Widget build(BuildContext context) {
    // Show splash until onboarding status is loaded from SharedPreferences
    if (_onboardingDone == null) {
      return const _SplashScreen();
    }

    // Show onboarding on first launch
    if (!_onboardingDone!) {
      return OnboardingScreen(onComplete: _completeOnboarding);
    }

    // Wait for Firebase to init — shows branded splash until ready.
    final firebaseAsync = ref.watch(firebaseInitProvider);

    return firebaseAsync.when(
      loading: () => const _SplashScreen(),
      error: (e, _) => Scaffold(
        body: Center(child: Text('Startup error: $e')),
      ),
      data: (_) {
        final authState = ref.watch(authStateProvider);
        return authState.when(
          loading: () => const _SplashScreen(),
          error: (_, __) {
            // Keep splash until minimum time has elapsed.
            if (!_splashMinTimeElapsed) return const _SplashScreen();
            return const LoginScreen();
          },
          data: (user) {
            // Keep splash until minimum time has elapsed.
            if (!_splashMinTimeElapsed) return const _SplashScreen();
            if (user == null) return const LoginScreen();
            // Save/refresh FCM token whenever user signs in.
            unawaited(FcmService.onUserSignIn());
            return const MainNavigator();
          },
        );
      },
    );
  }
}

class _SplashScreen extends StatefulWidget {
  const _SplashScreen();

  @override
  State<_SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<_SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final AnimationController _spinCtrl;
  late final AnimationController _pulseCtrl;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _titleOpacity;
  late final Animation<double> _wordsOpacity;
  late final Animation<double> _glowRadius;
  late final Animation<double> _ringOpacity;

  @override
  void initState() {
    super.initState();
    // ── Intro animation ──
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    // ── Continuous spin for orbital ring ──
    _spinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();

    // ── Pulsing glow ──
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _logoScale = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(
          parent: _ctrl,
          curve: const Interval(0, 0.5, curve: Curves.elasticOut)),
    );
    _logoOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
          parent: _ctrl, curve: const Interval(0, 0.3, curve: Curves.easeOut)),
    );
    _titleOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
          parent: _ctrl,
          curve: const Interval(0.2, 0.5, curve: Curves.easeOut)),
    );
    _wordsOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
          parent: _ctrl,
          curve: const Interval(0.35, 0.65, curve: Curves.easeOut)),
    );
    _glowRadius = Tween<double>(begin: 0, end: 40).animate(
      CurvedAnimation(
          parent: _ctrl,
          curve: const Interval(0.1, 0.6, curve: Curves.easeOut)),
    );
    _ringOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
          parent: _ctrl,
          curve: const Interval(0.3, 0.7, curve: Curves.easeOut)),
    );

    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _spinCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: AnimatedBuilder(
        animation: Listenable.merge([_ctrl, _spinCtrl, _pulseCtrl]),
        builder: (context, _) {
          return Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: isDark
                    ? [const Color(0xFF1A130D), const Color(0xFF251C14)]
                    : [const Color(0xFFFFF8F0), const Color(0xFFFFF0E0)],
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 3),
                // ── Glowing logo with spinning orbital ring ──
                Opacity(
                  opacity: _logoOpacity.value,
                  child: Transform.scale(
                    scale: _logoScale.value,
                    child: SizedBox(
                      width: 180,
                      height: 180,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Spinning orbital ring
                          Opacity(
                            opacity: _ringOpacity.value,
                            child: Transform.rotate(
                              angle: _spinCtrl.value * 2 * math.pi,
                              child: CustomPaint(
                                size: const Size(180, 180),
                                painter: _OrbitalRingPainter(
                                  progress: _spinCtrl.value,
                                  pulseValue: _pulseCtrl.value,
                                ),
                              ),
                            ),
                          ),
                          // Pulsing glow + logo
                          Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFC98B4E).withValues(
                                      alpha: 0.35 + 0.2 * _pulseCtrl.value),
                                  blurRadius:
                                      _glowRadius.value + 8 * _pulseCtrl.value,
                                  spreadRadius: _glowRadius.value * 0.3 +
                                      4 * _pulseCtrl.value,
                                ),
                              ],
                            ),
                            child: const ClipOval(
                              child: Image(
                                image: AssetImage('assets/images/logo.png'),
                                width: 120,
                                height: 120,
                                fit: BoxFit.cover,
                                errorBuilder: _iconFallback,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                // ── App name ──
                Opacity(
                  opacity: _titleOpacity.value,
                  child: Text(
                    'ARQIVON',
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                      color: isDark
                          ? const Color(0xFFF5EDE5)
                          : const Color(0xFF2C1810),
                      letterSpacing: 6,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // ── Slogan ──
                Opacity(
                  opacity: _wordsOpacity.value,
                  child: Text(
                    'Speak freely. Remember everything.',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFFC98B4E).withValues(alpha: 0.85),
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const Spacer(flex: 3),
                // ── Subtle loading indicator ──
                Opacity(
                  opacity: _wordsOpacity.value * 0.5,
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        const Color(0xFFC98B4E).withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 48),
              ],
            ),
          );
        },
      ),
    );
  }

  static Widget _iconFallback(BuildContext ctx, Object err, StackTrace? st) {
    return Container(
      width: 120,
      height: 120,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [Color(0xFFC98B4E), Color(0xFFE8943A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x66C98B4E),
            blurRadius: 40,
            spreadRadius: 8,
          ),
        ],
      ),
      child: const Icon(Icons.mic_rounded, color: Colors.white, size: 52),
    );
  }
}

/// Paints a spinning orbital ring with gradient arc and orbiting dots.
class _OrbitalRingPainter extends CustomPainter {
  _OrbitalRingPainter({required this.progress, required this.pulseValue});
  final double progress;
  final double pulseValue;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    // Gradient arc — sweeps ~270°
    final rect = Rect.fromCircle(center: center, radius: radius);
    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: math.pi * 1.5,
        colors: [
          const Color(0xFFC98B4E).withValues(alpha: 0.0),
          const Color(0xFFC98B4E).withValues(alpha: 0.6 + 0.2 * pulseValue),
          const Color(0xFFE8943A).withValues(alpha: 0.8),
          const Color(0xFFC98B4E).withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.3, 0.7, 1.0],
      ).createShader(rect);
    canvas.drawArc(rect, 0, math.pi * 1.5, false, arcPaint);

    // Orbiting dot at the leading edge
    const dotAngle = math.pi * 1.5;
    final dotX = center.dx + radius * math.cos(dotAngle);
    final dotY = center.dy + radius * math.sin(dotAngle);
    final dotRadius = 3.5 + 1.0 * pulseValue;
    canvas.drawCircle(
      Offset(dotX, dotY),
      dotRadius,
      Paint()..color = const Color(0xFFE8943A),
    );

    // Second smaller dot at ~90° behind
    const dot2Angle = math.pi * 0.5;
    final dot2X = center.dx + radius * math.cos(dot2Angle);
    final dot2Y = center.dy + radius * math.sin(dot2Angle);
    canvas.drawCircle(
      Offset(dot2X, dot2Y),
      2.0 + 0.5 * pulseValue,
      Paint()
        ..color =
            const Color(0xFFC98B4E).withValues(alpha: 0.5 + 0.2 * pulseValue),
    );

    // Third tiny dot at ~200°
    const dot3Angle = math.pi * 1.1;
    final dot3X = center.dx + radius * math.cos(dot3Angle);
    final dot3Y = center.dy + radius * math.sin(dot3Angle);
    canvas.drawCircle(
      Offset(dot3X, dot3Y),
      1.5,
      Paint()..color = const Color(0xFFC98B4E).withValues(alpha: 0.3),
    );
  }

  @override
  bool shouldRepaint(_OrbitalRingPainter oldDelegate) => true;
}

/// Notifier so child widgets (LiveScreen) can observe tab changes.
class TabIndexNotifier extends ChangeNotifier {
  int _index = 0;
  int get index => _index;
  void setIndex(int i) {
    if (_index != i) {
      _index = i;
      notifyListeners();
    }
  }
}

class MainNavigator extends ConsumerStatefulWidget {
  const MainNavigator({super.key});

  @override
  ConsumerState<MainNavigator> createState() => _MainNavigatorState();
}

class _MainNavigatorState extends ConsumerState<MainNavigator> {
  int _currentIndex = 0;
  final TabIndexNotifier _tabNotifier = TabIndexNotifier();

  /// Tracks which tabs have been navigated to (lazy init).
  final Set<int> _activatedTabs = {0}; // Home is always active

  void _goLive() => _selectTab(1);

  void _selectTab(int i) {
    setState(() {
      _currentIndex = i;
      _activatedTabs.add(i);
    });
    _tabNotifier.setIndex(i);
  }

  @override
  void dispose() {
    _tabNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Mark current tab as activated
    _activatedTabs.add(_currentIndex);

    // Watch for external tab changes (e.g., from session resume).
    ref.listen<int>(activeTabProvider, (prev, next) {
      if (next != _currentIndex) _selectTab(next);
    });

    final screens = <Widget>[
      HomeScreen(onGoLive: _goLive),
      _activatedTabs.contains(1)
          ? LiveScreen(tabNotifier: _tabNotifier)
          : const SizedBox.shrink(),
      _activatedTabs.contains(2)
          ? const NotesScreen()
          : const SizedBox.shrink(),
      _activatedTabs.contains(3)
          ? const ArchiveScreen()
          : const SizedBox.shrink(),
      _activatedTabs.contains(4)
          ? const SettingsScreen()
          : const SizedBox.shrink(),
    ];

    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(index: _currentIndex, children: screens),
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: OfflineBanner(),
          ),
        ],
      ),
      extendBody: true,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color:
                  Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: _selectTab,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          animationDuration: const Duration(milliseconds: 400),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.camera_alt_outlined),
              selectedIcon: Icon(Icons.camera_alt_rounded),
              label: 'Live',
            ),
            NavigationDestination(
              icon: Icon(Icons.note_alt_outlined),
              selectedIcon: Icon(Icons.note_alt_rounded),
              label: 'Notes',
            ),
            NavigationDestination(
              icon: Icon(Icons.archive_outlined),
              selectedIcon: Icon(Icons.archive_rounded),
              label: 'Archive',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings_rounded),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}
