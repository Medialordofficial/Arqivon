import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config/theme.dart';
import 'firebase_options.dart';
import 'providers/auth_provider.dart';
import 'providers/firebase_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/archive_screen.dart';
import 'screens/home_screen.dart';
import 'screens/live_screen.dart';
import 'screens/login_screen.dart';
import 'screens/settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialise Firebase and SharedPreferences in parallel before the first
  // frame — both are fast on-device and this removes the loading splash delay.
  await Future.wait([
    Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform),
    SharedPreferences.getInstance(),
  ]);
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0D0820),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const ProviderScope(child: ArqivonApp()));
}

class ArqivonApp extends ConsumerWidget {
  const ArqivonApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(settingsProvider).themeMode;

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

/// Shows [LoginScreen] when not authenticated, [MainNavigator] otherwise.
/// Waits for Firebase to finish initialising before rendering auth state.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Wait for Firebase to init — shows branded splash until ready.
    final firebaseAsync = ref.watch(firebaseInitProvider);

    return firebaseAsync.when(
      // Firebase was already initialised in main() — this state is instant.
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
    return const Scaffold(
      backgroundColor: Color(0xFF0D0820),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // App icon
            SizedBox(
              width: 100,
              height: 100,
              child: Image(
                image: AssetImage('assets/images/logo.png'),
                errorBuilder: _iconFallback,
              ),
            ),
            SizedBox(height: 28),
            Text(
              'Arqivon',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: -0.8,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'The Living Lens',
              style: TextStyle(
                fontSize: 13,
                color: Color(0x99FFFFFF),
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

class MainNavigator extends StatefulWidget {
  const MainNavigator({super.key});

  @override
  State<MainNavigator> createState() => _MainNavigatorState();
}

class _MainNavigatorState extends State<MainNavigator> {
  int _currentIndex = 0;

  void _goLive() => setState(() => _currentIndex = 1);

  @override
  Widget build(BuildContext context) {
    final screens = <Widget>[
      HomeScreen(onGoLive: _goLive),
      const LiveScreen(),
      const ArchiveScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: screens),
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
          onDestinationSelected: (i) => setState(() => _currentIndex = i),
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
