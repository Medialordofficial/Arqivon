import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:arqivon/models/agent_mode.dart';
import 'package:arqivon/providers/settings_provider.dart';

void main() {
  group('AppSettings', () {
    test('default values are correct', () {
      const settings = AppSettings();
      expect(settings.themeMode, ThemeMode.dark);
      expect(settings.selectedVoice, 'Aoede');
      expect(settings.defaultMode, AgentMode.general);
      expect(settings.sourceLang, 'auto');
      expect(settings.targetLang, 'en');
      expect(settings.isDarkMode, true);
    });

    test('copyWith preserves unchanged fields', () {
      const settings = AppSettings(
        selectedVoice: 'Puck',
        defaultMode: AgentMode.translator,
      );
      final updated = settings.copyWith(sourceLang: 'fr');
      expect(updated.selectedVoice, 'Puck');
      expect(updated.defaultMode, AgentMode.translator);
      expect(updated.sourceLang, 'fr');
      expect(updated.targetLang, 'en');
    });

    test('copyWith overrides specified fields', () {
      const settings = AppSettings();
      final updated = settings.copyWith(
        themeMode: ThemeMode.light,
        selectedVoice: 'Kore',
        defaultMode: AgentMode.tutor,
        sourceLang: 'ja',
        targetLang: 'de',
      );
      expect(updated.themeMode, ThemeMode.light);
      expect(updated.isDarkMode, false);
      expect(updated.selectedVoice, 'Kore');
      expect(updated.defaultMode, AgentMode.tutor);
      expect(updated.sourceLang, 'ja');
      expect(updated.targetLang, 'de');
    });

    test('isDarkMode reflects themeMode', () {
      const dark = AppSettings(themeMode: ThemeMode.dark);
      const light = AppSettings(themeMode: ThemeMode.light);
      expect(dark.isDarkMode, true);
      expect(light.isDarkMode, false);
    });
  });

  group('availableVoices', () {
    test('contains expected voices', () {
      expect(availableVoices, contains('Aoede'));
      expect(availableVoices, contains('Puck'));
      expect(availableVoices, contains('Charon'));
      expect(availableVoices, contains('Kore'));
      expect(availableVoices, contains('Fenrir'));
      expect(availableVoices, contains('Leda'));
      expect(availableVoices.length, 6);
    });
  });

  group('availableLanguages', () {
    test('contains common languages', () {
      expect(availableLanguages.containsKey('en'), true);
      expect(availableLanguages.containsKey('es'), true);
      expect(availableLanguages.containsKey('fr'), true);
      expect(availableLanguages.containsKey('auto'), true);
    });

    test('auto-detect is included', () {
      expect(availableLanguages['auto'], 'Auto-detect');
    });

    test('has at least 10 languages', () {
      expect(availableLanguages.length, greaterThanOrEqualTo(10));
    });
  });

  group('SettingsNotifier', () {
    late ProviderContainer container;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      container = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('initial state uses defaults from SharedPreferences', () {
      final settings = container.read(settingsProvider);
      expect(settings.themeMode, ThemeMode.dark);
      expect(settings.selectedVoice, 'Aoede');
      expect(settings.defaultMode, AgentMode.general);
    });

    test('toggleTheme switches from dark to light', () async {
      await container.read(settingsProvider.notifier).toggleTheme();
      final settings = container.read(settingsProvider);
      expect(settings.themeMode, ThemeMode.light);
    });

    test('toggleTheme switches from light to dark', () async {
      await container.read(settingsProvider.notifier).toggleTheme();
      await container.read(settingsProvider.notifier).toggleTheme();
      final settings = container.read(settingsProvider);
      expect(settings.themeMode, ThemeMode.dark);
    });

    test('setVoice updates voice', () async {
      await container.read(settingsProvider.notifier).setVoice('Puck');
      final settings = container.read(settingsProvider);
      expect(settings.selectedVoice, 'Puck');
    });

    test('setDefaultMode updates mode', () async {
      await container
          .read(settingsProvider.notifier)
          .setDefaultMode(AgentMode.translator);
      final settings = container.read(settingsProvider);
      expect(settings.defaultMode, AgentMode.translator);
    });

    test('setSourceLang updates source language', () async {
      await container.read(settingsProvider.notifier).setSourceLang('fr');
      final settings = container.read(settingsProvider);
      expect(settings.sourceLang, 'fr');
    });

    test('setTargetLang updates target language', () async {
      await container.read(settingsProvider.notifier).setTargetLang('ja');
      final settings = container.read(settingsProvider);
      expect(settings.targetLang, 'ja');
    });

    test('settings persist to SharedPreferences', () async {
      final notifier = container.read(settingsProvider.notifier);
      await notifier.setVoice('Charon');
      await notifier.setDefaultMode(AgentMode.support);
      await notifier.setSourceLang('ko');
      await notifier.setTargetLang('es');

      final prefs = container.read(sharedPrefsProvider);
      expect(prefs.getString('voice'), 'Charon');
      expect(prefs.getString('default_mode'), 'support');
      expect(prefs.getString('source_lang'), 'ko');
      expect(prefs.getString('target_lang'), 'es');
    });

    test('loads persisted settings on build', () async {
      SharedPreferences.setMockInitialValues({
        'dark_mode': false,
        'voice': 'Fenrir',
        'default_mode': 'tutor',
        'source_lang': 'de',
        'target_lang': 'zh',
      });
      final prefs = await SharedPreferences.getInstance();
      final c2 = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(c2.dispose);

      final settings = c2.read(settingsProvider);
      expect(settings.themeMode, ThemeMode.light);
      expect(settings.selectedVoice, 'Fenrir');
      expect(settings.defaultMode, AgentMode.tutor);
      expect(settings.sourceLang, 'de');
      expect(settings.targetLang, 'zh');
    });
  });
}
