import 'dart:async';

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
import 'providers/settings_provider.dart';
import 'screens/archive_screen.dart';
import 'screens/home_screen.dart';
import 'screens/live_screen.dart';
import 'screens/login_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/settings_screen.dart';
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
    FirebaseCrashlytics.instance.recordFlutterFatalError(errorDetails);
  };

  // Catch async Dart errors not handled by Flutter framework.
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  // Disable crash collection in debug builds to avoid noise.
  await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
    kReleaseMode,
  );

  // Structured logging — replaces raw print() everywhere.
  AppLogger.init();

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

    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: isDark ? const Color(0xFF0B0F1A) : Colors.white,
      systemNavigationBarIconBrightness:
          isDark ? Brightness.light : Brightness.dark,
    ));

    return MaterialApp(
      title: 'Arqivon',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: ArqivonTheme.lightTheme,
      darkTheme: ArqivonTheme.darkTheme,
      home: const AuthGate(),
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
  bool _onboardingDone = true; // default true until we load prefs

  @override
  void initState() {
    super.initState();
    _checkOnboarding();
  }

  Future<void> _checkOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
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
    // Show onboarding on first launch
    if (!_onboardingDone) {
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
          error: (_, __) => const LoginScreen(),
          data: (user) {
            if (user == null) return const LoginScreen();
            return const MainNavigator();
          },
        );
      },
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // App icon
            const SizedBox(
              width: 100,
              height: 100,
              child: Image(
                image: AssetImage('assets/images/logo.png'),
                errorBuilder: _iconFallback,
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'Arqivon',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                color: cs.onSurface,
                letterSpacing: -0.8,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'The Living Lens',
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurface.withValues(alpha: 0.5),
                letterSpacing: 1.5,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _iconFallback(BuildContext ctx, Object err, StackTrace? st) {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF7C3AED), Color(0xFF5B5FEF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x667C3AED),
            blurRadius: 32,
            spreadRadius: 4,
          ),
        ],
      ),
      child: const Icon(Icons.mic_rounded, color: Colors.white, size: 48),
    );
  }
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

class MainNavigator extends StatefulWidget {
  const MainNavigator({super.key});

  @override
  State<MainNavigator> createState() => _MainNavigatorState();
}

class _MainNavigatorState extends State<MainNavigator> {
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

    final screens = <Widget>[
      HomeScreen(onGoLive: _goLive),
      _activatedTabs.contains(1)
          ? LiveScreen(tabNotifier: _tabNotifier)
          : const SizedBox.shrink(),
      _activatedTabs.contains(2)
          ? const ArchiveScreen()
          : const SizedBox.shrink(),
      _activatedTabs.contains(3)
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
