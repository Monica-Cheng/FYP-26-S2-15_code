// lib/screens/settings/help_faq_screen.dart
// Settings → Help & FAQ. Static FAQ content grouped by section (expandable
// rows, tap a question to reveal its answer), plus Contact Us / Report a
// Bug — both mailto: links via url_launcher, same pattern already used by
// find_professional_screen.dart's _contact(). No Firestore read/write, no
// admin dashboard — purely static content + two mailto launches.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_theme.dart';

const _kDivider = Color(0xFFE8EAF8);
const _kGreen = Color(0xFF22C55E);
const _kSupportEmail = 'WiseWorkout@gmail.com';

class _FaqItem {
  final String question;
  final String answer;
  const _FaqItem(this.question, this.answer);
}

class _FaqSection {
  final String title;
  final List<_FaqItem> items;
  const _FaqSection(this.title, this.items);
}

const List<_FaqSection> _kFaqSections = [
  _FaqSection('Getting Started', [
    _FaqItem(
      'How do I log a workout?',
      'Start a gym or cardio session from the Home or Plans tab, or log '
          'one manually from the Activities tab if you forgot to track it '
          'live.',
    ),
    _FaqItem(
      "What's the difference between a Plan and a Custom Routine?",
      'Plans are pre-built programs (some from Explore, admin-curated) you '
          'can track progress through day by day. Custom Routines are ones '
          'you build yourself.',
    ),
  ]),
  _FaqSection('Health Data', [
    _FaqItem(
      'Why does the app need Health access?',
      'WiseWorkout reads Heart Rate, Steps, and Active Calories from '
          'Apple Health (iOS) to give you more accurate session data. You '
          'can control which categories the app uses under Settings → '
          'Manage App.',
    ),
    _FaqItem(
      'Can I control what health data the app uses?',
      'Yes, under Settings → Manage App you can toggle Heart Rate, Steps, '
          "and Active Calories individually. Note: this controls what the "
          "app uses, not your underlying HealthKit permission — Apple "
          "doesn't let apps show or change that directly, so you may also "
          "need to check the Health app's own permission settings.",
    ),
    _FaqItem(
      'Is Android health tracking supported?',
      "Not yet fully — this is a known gap we're actively working on.",
    ),
  ]),
  _FaqSection('Progress & Streaks', [
    _FaqItem(
      'How is my streak calculated?',
      'Your streak counts consecutive days with a logged session, shown '
          'on your Profile.',
    ),
    _FaqItem(
      'Why did my stats change (e.g. kg Lifted became Workout Time)?',
      'We recently updated profile stats to be monthly and more '
          'meaningful, rather than unbounded lifetime totals.',
    ),
  ]),
  _FaqSection('Social', [
    _FaqItem(
      'Can other users see all my stats?',
      'No — only your Level and XP are visible on your public profile. '
          'Detailed stats like streaks and session history stay private '
          'to you.',
    ),
    _FaqItem(
      'How do I add friends?',
      'Use "Add Friends" from your Profile page or the Friends screen.',
    ),
  ]),
  _FaqSection('Account', [
    _FaqItem(
      'How do I change my email?',
      'Settings → Change Email (under Account) — you\'ll need to '
          're-verify via your current password or Google sign-in, then '
          'confirm the new email via a verification link sent to it.',
    ),
    _FaqItem(
      'What sign-in methods are supported?',
      'Email/Password and Google. Apple Sign-In is not currently '
          'supported.',
    ),
  ]),
];

class HelpFaqScreen extends StatefulWidget {
  const HelpFaqScreen({super.key});

  @override
  State<HelpFaqScreen> createState() => _HelpFaqScreenState();
}

class _HelpFaqScreenState extends State<HelpFaqScreen> {
  // Keyed by question text — unique across all sections, so a flat Set
  // works fine without needing per-section indices.
  final Set<String> _expanded = {};

  Future<void> _launchMailto({String? subject}) async {
    final uri = Uri(
      scheme: 'mailto',
      path: _kSupportEmail,
      query: subject == null ? null : 'subject=${Uri.encodeComponent(subject)}',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Email: $_kSupportEmail'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WW.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _sectionHeader('Contact'),
                    Container(
                      decoration: WW.cardDecoration,
                      clipBehavior: Clip.hardEdge,
                      child: Column(
                        children: [
                          _contactRow(
                            icon: Icons.mail_rounded,
                            iconBg: WW.primary,
                            title: 'Contact Us',
                            subtitle: _kSupportEmail,
                            first: true,
                            onTap: () => _launchMailto(),
                          ),
                          _contactRow(
                            icon: Icons.bug_report_rounded,
                            iconBg: _kGreen,
                            title: 'Report a Bug',
                            subtitle: 'Email us the details — we read every one.',
                            onTap: () =>
                                _launchMailto(subject: 'WiseWorkout Bug Report'),
                          ),
                        ],
                      ),
                    ),
                    for (final section in _kFaqSections) ...[
                      _sectionHeader(section.title),
                      Container(
                        decoration: WW.cardDecoration,
                        clipBehavior: Clip.hardEdge,
                        child: Column(
                          children: [
                            for (int i = 0; i < section.items.length; i++)
                              _faqRow(section.items[i], first: i == 0),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
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

  // ── Top bar ───────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
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
            'Help & FAQ',
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

  Widget _sectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: WW.textSec,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  Widget _contactRow({
    required IconData icon,
    required Color iconBg,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool first = false,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 60),
        decoration: BoxDecoration(
          border: first
              ? null
              : const Border(top: BorderSide(color: _kDivider, width: 0.5)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(child: Icon(icon, color: Colors.white, size: 17)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: WW.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 12, color: WW.textSec),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 18, color: WW.border),
          ],
        ),
      ),
    );
  }

  Widget _faqRow(_FaqItem item, {bool first = false}) {
    final isExpanded = _expanded.contains(item.question);
    return Container(
      decoration: BoxDecoration(
        border: first
            ? null
            : const Border(top: BorderSide(color: _kDivider, width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() {
              if (isExpanded) {
                _expanded.remove(item.question);
              } else {
                _expanded.add(item.question);
              }
            }),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      item.question,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: WW.text,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    duration: const Duration(milliseconds: 200),
                    turns: isExpanded ? 0.5 : 0,
                    child: const Icon(Icons.expand_more_rounded,
                        size: 20, color: WW.textSec),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState:
                isExpanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Text(
                item.answer,
                style: const TextStyle(
                  fontSize: 13,
                  color: WW.textSec,
                  height: 1.5,
                ),
              ),
            ),
            secondChild: const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}
