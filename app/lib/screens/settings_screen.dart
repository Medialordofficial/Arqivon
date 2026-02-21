import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/agent_mode.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/glassmorphic_card.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final authState = ref.watch(authStateProvider);
    final user = authState.valueOrNull;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(title: const Text('SETTINGS')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          physics: const BouncingScrollPhysics(),
          children: [
            // ── User profile card ──────────────────────────────────
            GlassmorphicCard(
              margin: const EdgeInsets.only(bottom: 16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: const Color(0xFF3E1F0D).withOpacity(0.3),
                    backgroundImage: user?.photoURL != null
                        ? NetworkImage(user!.photoURL!)
                        : null,
                    child: user?.photoURL == null
                        ? const Icon(Icons.person_rounded,
                            color: Color(0xFF3E1F0D), size: 28)
                        : null,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.displayName ?? 'Guest User',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          user?.email ?? 'Sign in to sync your data',
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Default Mode ───────────────────────────────────────
            _sectionHeader(context, 'DEFAULT MODE'),
            GlassmorphicCard(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
              child: Column(
                children: AgentMode.values.map((mode) {
                  final isSelected = settings.defaultMode == mode;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(mode.icon,
                        color: isSelected
                            ? mode.color
                            : Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.3)),
                    title: Text(mode.label),
                    subtitle: Text(mode.description,
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.4),
                        )),
                    trailing: isSelected
                        ? Icon(Icons.check_circle_rounded, color: mode.color)
                        : null,
                    onTap: () => ref
                        .read(settingsProvider.notifier)
                        .setDefaultMode(mode),
                  );
                }).toList(),
              ),
            ),

            // ── Translator Language ────────────────────────────────
            _sectionHeader(context, 'TRANSLATOR LANGUAGES'),
            GlassmorphicCard(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: Column(
                children: [
                  _languageDropdown(
                    context: context,
                    label: 'Source Language',
                    value: settings.sourceLang,
                    includeAuto: true,
                    onChanged: (v) =>
                        ref.read(settingsProvider.notifier).setSourceLang(v),
                  ),
                  const Divider(height: 1),
                  _languageDropdown(
                    context: context,
                    label: 'Target Language',
                    value: settings.targetLang,
                    includeAuto: false,
                    onChanged: (v) =>
                        ref.read(settingsProvider.notifier).setTargetLang(v),
                  ),
                ],
              ),
            ),

            // ── Appearance ─────────────────────────────────────────
            _sectionHeader(context, 'APPEARANCE'),
            GlassmorphicCard(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('Dark Mode'),
                    subtitle: Text(
                      settings.isDarkMode ? 'Glassmorphism Dark' : 'Light',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.5),
                      ),
                    ),
                    secondary: Icon(
                      settings.isDarkMode
                          ? Icons.dark_mode_rounded
                          : Icons.light_mode_rounded,
                      color: const Color(0xFF3E1F0D),
                    ),
                    value: settings.isDarkMode,
                    onChanged: (_) =>
                        ref.read(settingsProvider.notifier).toggleTheme(),
                    activeThumbColor: const Color(0xFF3E1F0D),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),

            // ── AI Voice ───────────────────────────────────────────
            _sectionHeader(context, 'AI VOICE'),
            GlassmorphicCard(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
              child: Column(
                children: availableVoices.map((voice) {
                  final isSelected = settings.selectedVoice == voice;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.record_voice_over_rounded,
                      color: isSelected
                          ? const Color(0xFF3E1F0D)
                          : Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.3),
                    ),
                    title: Text(voice),
                    trailing: isSelected
                        ? const Icon(Icons.check_circle_rounded,
                            color: Color(0xFF3E1F0D))
                        : null,
                    onTap: () =>
                        ref.read(settingsProvider.notifier).setVoice(voice),
                  );
                }).toList(),
              ),
            ),

            // ── Account ────────────────────────────────────────────
            _sectionHeader(context, 'ACCOUNT'),
            GlassmorphicCard(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
              child: user != null
                  ? ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.logout_rounded,
                          color: Color(0xFFEF4444)),
                      title: const Text('Sign Out',
                          style: TextStyle(color: Color(0xFFEF4444))),
                      onTap: () async {
                        await ref.read(authServiceProvider).signOut();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Signed out'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                    )
                  : ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.login_rounded,
                          color: Color(0xFF3E1F0D)),
                      title: const Text('Sign in with Google'),
                      onTap: () async {
                        await ref.read(authServiceProvider).signInWithGoogle();
                      },
                    ),
            ),

            // ── About ──────────────────────────────────────────────
            _sectionHeader(context, 'ABOUT'),
            GlassmorphicCard(
              margin: const EdgeInsets.only(bottom: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.asset(
                          'assets/images/logo.png',
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Arqivo',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.3,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'The Living Lens · v2.0.0',
                            style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.6),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Modes: Assistant · Translator · Tutor · Support\n'
                    'Powered by Gemini 2.0 Flash Live · Google Cloud Run · Firebase',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _languageDropdown({
    required BuildContext context,
    required String label,
    required String value,
    required bool includeAuto,
    required ValueChanged<String> onChanged,
  }) {
    final langs = Map<String, String>.from(availableLanguages);
    if (!includeAuto) langs.remove('auto');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(Icons.language_rounded,
              size: 20,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 14)),
          ),
          DropdownButton<String>(
            value: langs.containsKey(value) ? value : langs.keys.first,
            underline: const SizedBox.shrink(),
            dropdownColor: Theme.of(context).colorScheme.surface,
            items: langs.entries
                .map((e) => DropdownMenuItem(
                      value: e.key,
                      child:
                          Text(e.value, style: const TextStyle(fontSize: 13)),
                    ))
                .toList(),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.5,
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
        ),
      ),
    );
  }
}
