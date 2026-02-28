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
///
/// Gemini handles 100+ languages natively. This is the full list of
/// languages that Gemini's Live API reliably supports for real-time
/// translation via the `live_translate` tool.
const Map<String, String> availableLanguages = {
  'auto': 'Auto-detect',
  // ── Major world languages ──────────────────────────────────────
  'en': 'English',
  'es': 'Spanish',
  'fr': 'French',
  'de': 'German',
  'it': 'Italian',
  'pt': 'Portuguese',
  'zh': 'Chinese (Mandarin)',
  'ja': 'Japanese',
  'ko': 'Korean',
  'ar': 'Arabic',
  'hi': 'Hindi',
  'ru': 'Russian',
  // ── European languages ─────────────────────────────────────────
  'tr': 'Turkish',
  'nl': 'Dutch',
  'pl': 'Polish',
  'sv': 'Swedish',
  'da': 'Danish',
  'no': 'Norwegian',
  'fi': 'Finnish',
  'el': 'Greek',
  'cs': 'Czech',
  'sk': 'Slovak',
  'ro': 'Romanian',
  'hu': 'Hungarian',
  'bg': 'Bulgarian',
  'hr': 'Croatian',
  'sr': 'Serbian',
  'sl': 'Slovenian',
  'uk': 'Ukrainian',
  'lt': 'Lithuanian',
  'lv': 'Latvian',
  'et': 'Estonian',
  'ga': 'Irish',
  'cy': 'Welsh',
  'is': 'Icelandic',
  'mt': 'Maltese',
  'sq': 'Albanian',
  'mk': 'Macedonian',
  'bs': 'Bosnian',
  'ca': 'Catalan',
  'gl': 'Galician',
  'eu': 'Basque',
  'lb': 'Luxembourgish',
  // ── Asian languages ────────────────────────────────────────────
  'th': 'Thai',
  'vi': 'Vietnamese',
  'id': 'Indonesian',
  'ms': 'Malay',
  'tl': 'Filipino (Tagalog)',
  'bn': 'Bengali',
  'ta': 'Tamil',
  'te': 'Telugu',
  'ml': 'Malayalam',
  'kn': 'Kannada',
  'mr': 'Marathi',
  'gu': 'Gujarati',
  'pa': 'Punjabi',
  'ur': 'Urdu',
  'ne': 'Nepali',
  'si': 'Sinhala',
  'my': 'Burmese',
  'km': 'Khmer',
  'lo': 'Lao',
  'ka': 'Georgian',
  'hy': 'Armenian',
  'az': 'Azerbaijani',
  'kk': 'Kazakh',
  'uz': 'Uzbek',
  'mn': 'Mongolian',
  'zh-TW': 'Chinese (Traditional)',
  // ── Middle Eastern & African languages ─────────────────────────
  'he': 'Hebrew',
  'fa': 'Persian (Farsi)',
  'sw': 'Swahili',
  'am': 'Amharic',
  'ha': 'Hausa',
  'yo': 'Yoruba',
  'ig': 'Igbo',
  'zu': 'Zulu',
  'xh': 'Xhosa',
  'af': 'Afrikaans',
  'so': 'Somali',
  'rw': 'Kinyarwanda',
  'mg': 'Malagasy',
  'sn': 'Shona',
  // ── Latin American & Caribbean ─────────────────────────────────
  'ht': 'Haitian Creole',
  'qu': 'Quechua',
  // ── Other languages ────────────────────────────────────────────
  'eo': 'Esperanto',
  'la': 'Latin',
  'jv': 'Javanese',
  'su': 'Sundanese',
  'ceb': 'Cebuano',
  'ny': 'Chichewa',
  'co': 'Corsican',
  'fy': 'Frisian',
  'gd': 'Scottish Gaelic',
  'ku': 'Kurdish',
  'ps': 'Pashto',
  'sd': 'Sindhi',
  'sm': 'Samoan',
  'st': 'Sesotho',
  'tg': 'Tajik',
  'tk': 'Turkmen',
  'tt': 'Tatar',
  'ug': 'Uyghur',
  'yi': 'Yiddish',
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
