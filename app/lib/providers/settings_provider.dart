import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/agent_mode.dart';

/// Eagerly-resolved SharedPreferences instance.
/// Overridden in ProviderScope from main() so it's available synchronously.
final sharedPrefsProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPrefsProvider must be overridden in main()');
});

/// App settings state.
class AppSettings {
  final ThemeMode themeMode;
  final String selectedVoice;
  final AgentMode defaultMode;
  final String sourceLang;
  final String targetLang;

  const AppSettings({
    this.themeMode = ThemeMode.dark,
    this.selectedVoice = 'Aoede',
    this.defaultMode = AgentMode.general,
    this.sourceLang = 'auto',
    this.targetLang = 'en',
  });

  AppSettings copyWith({
    ThemeMode? themeMode,
    String? selectedVoice,
    AgentMode? defaultMode,
    String? sourceLang,
    String? targetLang,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      selectedVoice: selectedVoice ?? this.selectedVoice,
      defaultMode: defaultMode ?? this.defaultMode,
      sourceLang: sourceLang ?? this.sourceLang,
      targetLang: targetLang ?? this.targetLang,
    );
  }

  bool get isDarkMode => themeMode == ThemeMode.dark;
}

/// Available AI voice options.
const List<String> availableVoices = [
  'Aoede',
  'Puck',
  'Charon',
  'Kore',
  'Fenrir',
  'Leda',
];

/// Available languages for the translator.
const Map<String, String> availableLanguages = {
  'auto': 'Auto-detect',
  'en': 'English',
  'es': 'Spanish',
  'fr': 'French',
  'de': 'German',
  'it': 'Italian',
  'pt': 'Portuguese',
  'zh': 'Chinese',
  'ja': 'Japanese',
  'ko': 'Korean',
  'ar': 'Arabic',
  'hi': 'Hindi',
  'ru': 'Russian',
  'tr': 'Turkish',
  'nl': 'Dutch',
  'pl': 'Polish',
  'sv': 'Swedish',
  'th': 'Thai',
  'vi': 'Vietnamese',
};

/// Settings notifier – persists to SharedPreferences.
class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    // Load synchronously from the eagerly-resolved SharedPreferences
    // to avoid a dark → light theme flicker on startup.
    final prefs = ref.read(sharedPrefsProvider);
    final isDark = prefs.getBool('dark_mode') ?? true;
    final voice = prefs.getString('voice') ?? 'Aoede';
    final modeName = prefs.getString('default_mode') ?? 'general';
    final srcLang = prefs.getString('source_lang') ?? 'auto';
    final tgtLang = prefs.getString('target_lang') ?? 'en';
    return AppSettings(
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      selectedVoice: voice,
      defaultMode: AgentMode.values.firstWhere(
        (m) => m.name == modeName,
        orElse: () => AgentMode.general,
      ),
      sourceLang: srcLang,
      targetLang: tgtLang,
    );
  }

  Future<void> toggleTheme() async {
    final newMode =
        state.themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    state = state.copyWith(themeMode: newMode);
    final prefs = ref.read(sharedPrefsProvider);
    await prefs.setBool('dark_mode', newMode == ThemeMode.dark);
  }

  Future<void> setVoice(String voice) async {
    state = state.copyWith(selectedVoice: voice);
    final prefs = ref.read(sharedPrefsProvider);
    await prefs.setString('voice', voice);
  }

  Future<void> setDefaultMode(AgentMode mode) async {
    state = state.copyWith(defaultMode: mode);
    final prefs = ref.read(sharedPrefsProvider);
    await prefs.setString('default_mode', mode.name);
  }

  Future<void> setSourceLang(String lang) async {
    state = state.copyWith(sourceLang: lang);
    final prefs = ref.read(sharedPrefsProvider);
    await prefs.setString('source_lang', lang);
  }

  Future<void> setTargetLang(String lang) async {
    state = state.copyWith(targetLang: lang);
    final prefs = ref.read(sharedPrefsProvider);
    await prefs.setString('target_lang', lang);
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
