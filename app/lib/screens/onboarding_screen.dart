import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// First-launch onboarding walkthrough.
///
/// Shows 4 swipeable pages explaining what Arqivon does and how to use it.
/// Saves a flag to SharedPreferences so it only shows once.
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const OnboardingScreen({super.key, required this.onComplete});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _currentPage = 0;

  static const _pages = [
    _OnboardingPage(
      icon: Icons.auto_awesome_rounded,
      color: Color(0xFF7C74A8),
      title: 'Meet Arqivon',
      body:
          'Your AI voice assistant that sees, hears, and acts in real time — powered by Gemini.',
    ),
    _OnboardingPage(
      icon: Icons.view_carousel_rounded,
      color: Color(0xFF9389C4),
      title: 'Four Modes, One App',
      body:
          'Switch between Assistant, Translator, Tutor, and Support — each with specialised AI tools and overlays.',
    ),
    _OnboardingPage(
      icon: Icons.videocam_rounded,
      color: Color(0xFF6B9F5B),
      title: 'See & Speak',
      body:
          'Point your camera at anything while you talk. Arqivon understands both audio and video simultaneously.',
    ),
    _OnboardingPage(
      icon: Icons.bolt_rounded,
      color: Color(0xFF8A7DB8),
      title: 'Smart Actions',
      body:
          'The AI creates actionable cards — open links, save contacts, share translations, and more — with a single tap.',
    ),
  ];

  void _next() {
    if (_currentPage < _pages.length - 1) {
      HapticFeedback.selectionClick();
      _controller.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    } else {
      HapticFeedback.mediumImpact();
      widget.onComplete();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _currentPage == _pages.length - 1;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Skip button
            Align(
              alignment: Alignment.topRight,
              child: TextButton(
                onPressed: widget.onComplete,
                child: Text(
                  'Skip',
                  style: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.4),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),

            // Pages
            Expanded(
              child: PageView.builder(
                controller: _controller,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemCount: _pages.length,
                itemBuilder: (_, i) {
                  final page = _pages[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Icon circle
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              center: const Alignment(-0.3, -0.3),
                              colors: [
                                page.color.withValues(alpha: 0.15),
                                page.color.withValues(alpha: 0.05),
                              ],
                            ),
                            border: Border.all(
                              color: page.color.withValues(alpha: 0.3),
                              width: 2.5,
                            ),
                          ),
                          child: Icon(page.icon, size: 52, color: page.color),
                        ),
                        const SizedBox(height: 40),
                        Text(
                          page.title,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: Theme.of(context).colorScheme.onSurface,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          page.body,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.6),
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Dots + Continue button
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
              child: Column(
                children: [
                  // Dots
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _pages.length,
                      (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: _currentPage == i ? 28 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _currentPage == i
                              ? _pages[i].color
                              : Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton(
                      onPressed: _next,
                      style: FilledButton.styleFrom(
                        backgroundColor: _pages[_currentPage].color,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        isLast ? 'Get Started' : 'Continue',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
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
}

class _OnboardingPage {
  final IconData icon;
  final Color color;
  final String title;
  final String body;

  const _OnboardingPage({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });
}
