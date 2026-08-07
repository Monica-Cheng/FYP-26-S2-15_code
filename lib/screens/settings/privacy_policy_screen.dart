// lib/screens/settings/privacy_policy_screen.dart
// Settings → Privacy Policy. Static placeholder copy — honest and generic,
// not final legal copy. Replaces the previous "coming soon" snackbar stub.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';

const _kDivider = Color(0xFFE8EAF8);

class _PolicySection {
  final String title;
  final String body;
  const _PolicySection(this.title, this.body);
}

const List<_PolicySection> _kSections = [
  _PolicySection(
    'What We Collect',
    'To provide WiseWorkout\'s features, we collect: account information '
        '(email, display name, username, profile photo); health data you '
        'connect via Apple Health, such as heart rate, step count, and '
        'active calories; workout and session data you log or track '
        'through the app (exercises, sets, reps, cardio routes, duration, '
        'nutrition entries); and photos you choose to attach to a workout '
        'or nutrition entry.',
  ),
  _PolicySection(
    'How We Use Your Data',
    'Your data is used to power WiseWorkout\'s own features — tracking '
        'your progress, calculating calories and XP, showing your streak '
        'and stats, generating AI-assisted nutrition and coaching '
        'insights, and enabling social features like friends and feed '
        'posts you choose to share. We do not sell your personal data to '
        'third parties.',
  ),
  _PolicySection(
    'Data Storage',
    'Your data is stored using Firebase and Google Cloud infrastructure. '
        'Certain sensitive health fields are encrypted before storage and '
        'are only ever decrypted server-side. Reasonable technical '
        'safeguards are in place, but no system can guarantee absolute '
        'security.',
  ),
  _PolicySection(
    'Your Control',
    'You can control which Apple Health categories WiseWorkout uses under '
        'Settings → Manage App, control what\'s visible to other users '
        'under Settings → Community, and request deletion or deactivation '
        'of your account at any time from Settings.',
  ),
  _PolicySection(
    'Changes to This Policy',
    'This is a placeholder policy that will be finalized and updated as '
        'WiseWorkout develops. We\'ll let you know if any future changes '
        'materially affect how your data is handled.',
  ),
];

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WW.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildTopBar(context),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: WW.chipBg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'This is a draft privacy policy for WiseWorkout '
                        'during development — it will be reviewed and '
                        'finalized before public release.',
                        style: TextStyle(
                          fontSize: 12,
                          color: WW.primaryDark,
                          height: 1.5,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    for (final section in _kSections) ...[
                      Text(
                        section.title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: WW.text,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        section.body,
                        style: const TextStyle(
                          fontSize: 13,
                          color: WW.textSec,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Container(
      height: 56,
      decoration: const BoxDecoration(
        color: WW.card,
        border: Border(bottom: BorderSide(color: _kDivider, width: 0.5)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              onTap: () => context.pop(),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: WW.elevated,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(
                  child: Icon(Icons.chevron_left_rounded,
                      size: 22, color: WW.textSec),
                ),
              ),
            ),
          ),
          const Text(
            'Privacy Policy',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: WW.primaryDark,
            ),
          ),
        ],
      ),
    );
  }
}
