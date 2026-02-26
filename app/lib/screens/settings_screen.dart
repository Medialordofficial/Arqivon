import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/agent_mode.dart';
import '../config/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/glassmorphic_card.dart';
import 'memories_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _authLoading = false;

  @override
  Widget build(BuildContext context) {
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
                    backgroundColor: ArqivonTheme.primary.withValues(
                      alpha: 0.15,
                    ),
                    backgroundImage: user?.photoURL != null
                        ? NetworkImage(user!.photoURL!)
                        : null,
                    child: user?.photoURL == null
                        ? Icon(
                            Icons.person_rounded,
                            color: Theme.of(context).colorScheme.primary,
                            size: 28,
                          )
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
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.5),
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
                    leading: Icon(
                      mode.icon,
                      color: isSelected
                          ? mode.color
                          : Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.3),
                    ),
                    title: Text(mode.label),
                    subtitle: Text(
                      mode.description,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.4),
                      ),
                    ),
                    trailing: isSelected
                        ? Icon(Icons.check_circle_rounded, color: mode.color)
                        : null,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      ref.read(settingsProvider.notifier).setDefaultMode(mode);
                    },
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
                      settings.isDarkMode ? 'Dark' : 'Light',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                    secondary: Icon(
                      settings.isDarkMode
                          ? Icons.dark_mode_rounded
                          : Icons.light_mode_rounded,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    value: settings.isDarkMode,
                    onChanged: (_) {
                      HapticFeedback.lightImpact();
                      ref.read(settingsProvider.notifier).toggleTheme();
                    },
                    activeThumbColor: Theme.of(context).colorScheme.primary,
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
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.3),
                    ),
                    title: Text(voice),
                    trailing: isSelected
                        ? Icon(
                            Icons.check_circle_rounded,
                            color: Theme.of(context).colorScheme.primary,
                          )
                        : null,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      ref.read(settingsProvider.notifier).setVoice(voice);
                    },
                  );
                }).toList(),
              ),
            ),

            // ── Account ────────────────────────────────────────────
            // ── My Memories ────────────────────────────────────────
            _sectionHeader(context, 'MY MEMORIES'),
            GlassmorphicCard(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.psychology_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: const Text('View AI Memories'),
                subtitle: Text(
                  'See what Arqivon remembers about you',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.4),
                  ),
                ),
                trailing: Icon(
                  Icons.chevron_right_rounded,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.3),
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const MemoriesScreen(),
                  ),
                ),
              ),
            ),

            // ── Account ────────────────────────────────────────────
            _sectionHeader(context, 'ACCOUNT'),
            GlassmorphicCard(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
              child: _authLoading
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  : user != null
                      ? Column(
                          children: [
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                Icons.logout_rounded,
                                color: Theme.of(context).colorScheme.error,
                              ),
                              title: Text(
                                'Sign Out',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                              onTap: () async {
                                setState(() => _authLoading = true);
                                try {
                                  await ref.read(authServiceProvider).signOut();
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Signed out'),
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  }
                                } finally {
                                  if (mounted) {
                                    setState(() => _authLoading = false);
                                  }
                                }
                              },
                            ),
                            const Divider(height: 1),
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                Icons.delete_forever_rounded,
                                color: Theme.of(context).colorScheme.error,
                              ),
                              title: Text(
                                'Delete Account',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                              subtitle: Text(
                                'Permanently remove your account and data',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(
                                    context,
                                  )
                                      .colorScheme
                                      .onSurface
                                      .withValues(alpha: 0.4),
                                ),
                              ),
                              onTap: () => _confirmDeleteAccount(context),
                            ),
                          ],
                        )
                      : ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.login_rounded,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          title: const Text('Sign in with Google'),
                          onTap: () async {
                            setState(() => _authLoading = true);
                            try {
                              await ref
                                  .read(authServiceProvider)
                                  .signInWithGoogle();
                            } finally {
                              if (mounted) setState(() => _authLoading = false);
                            }
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
                            'Arqivon',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.3,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'The Living Lens · v1.0.0',
                            style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.6),
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
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
            ),

            // ── Legal ──────────────────────────────────────────────
            _sectionHeader(context, 'LEGAL'),
            GlassmorphicCard(
              margin: const EdgeInsets.only(bottom: 32),
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.privacy_tip_rounded,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    title: const Text('Privacy Policy'),
                    trailing: Icon(
                      Icons.open_in_new_rounded,
                      size: 18,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.3),
                    ),
                    onTap: () => launchUrl(
                      Uri.parse('https://arqivon-inc.web.app/privacy'),
                      mode: LaunchMode.externalApplication,
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.description_rounded,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    title: const Text('Terms of Service'),
                    trailing: Icon(
                      Icons.open_in_new_rounded,
                      size: 18,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.3),
                    ),
                    onTap: () => launchUrl(
                      Uri.parse('https://arqivon-inc.web.app/terms'),
                      mode: LaunchMode.externalApplication,
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

  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Account?'),
        content: const Text(
          'This will permanently delete your account and all associated data. '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _authLoading = true);
    try {
      await ref.read(authServiceProvider).deleteAccount();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account deleted'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.code == 'requires-recent-login'
                  ? 'Please sign in again before deleting your account'
                  : 'Failed to delete account: ${e.message}',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete account: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _authLoading = false);
    }
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
          Icon(
            Icons.language_rounded,
            size: 20,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.5),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
          DropdownButton<String>(
            value: langs.containsKey(value) ? value : langs.keys.first,
            underline: const SizedBox.shrink(),
            dropdownColor: Theme.of(context).colorScheme.surface,
            items: langs.entries
                .map(
                  (e) => DropdownMenuItem(
                    value: e.key,
                    child: Text(e.value, style: const TextStyle(fontSize: 13)),
                  ),
                )
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
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
        ),
      ),
    );
  }
}
