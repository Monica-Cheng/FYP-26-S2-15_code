// lib/screens/onboarding/onboarding_step2_screen.dart
// Onboarding Step 2 — Goals Survey.
// 6 questions shown one at a time. Saves via FirestoreService.saveOnboardingStep2()
// then navigates to Routes.onboardingStep3.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../core/router.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';

// ── Data models ────────────────────────────────────────────────────────────────

class _CardOption {
  final String id;
  final String title;
  final String desc;
  final Color iconBg;
  final Color iconColor;
  final IconData iconData;

  const _CardOption({
    required this.id,
    required this.title,
    required this.desc,
    required this.iconBg,
    required this.iconColor,
    required this.iconData,
  });
}

class _ChipOption {
  final String id;
  final String label;
  const _ChipOption({required this.id, required this.label});
}

// ── Screen ─────────────────────────────────────────────────────────────────────

class OnboardingStep2Screen extends StatefulWidget {
  const OnboardingStep2Screen({super.key});

  @override
  State<OnboardingStep2Screen> createState() => _OnboardingStep2ScreenState();
}

class _OnboardingStep2ScreenState extends State<OnboardingStep2Screen> {
  final _authService = AuthService();
  final _firestoreService = FirestoreService();

  int _questionIndex = 0;
  String? _primaryGoal;
  String? _sportPreference;
  String? _experienceLevel;
  List<String> _equipment = [];
  int? _daysPerWeek;
  String? _sessionLength;
  bool _isLoading = false;

  static const int _kTotal = 6;

  bool get _canAdvance {
    switch (_questionIndex) {
      case 0:
        return _primaryGoal != null;
      case 1:
        return _sportPreference != null;
      case 2:
        return _experienceLevel != null;
      case 3:
        return _equipment.isNotEmpty;
      case 4:
        return _daysPerWeek != null;
      case 5:
        return _sessionLength != null;
      default:
        return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Navigation helpers
  // ---------------------------------------------------------------------------
  void _back() {
    if (_questionIndex == 0) {
      context.go(Routes.onboardingStep1);
    } else {
      setState(() => _questionIndex--);
    }
  }

  void _skip() {
    if (_questionIndex < _kTotal - 1) {
      setState(() => _questionIndex++);
    } else {
      _save();
    }
  }

  void _next() {
    if (!_canAdvance) return;
    if (_questionIndex < _kTotal - 1) {
      setState(() => _questionIndex++);
    } else {
      _save();
    }
  }

  // ---------------------------------------------------------------------------
  // Persists survey answers then navigates to step 3.
  // ---------------------------------------------------------------------------
  Future<void> _save() async {
    final uid = _authService.getCurrentUser()?.uid;
    if (uid == null) return;

    setState(() => _isLoading = true);
    try {
      final data = <String, dynamic>{
        if (_primaryGoal != null) 'primaryGoal': _primaryGoal,
        if (_sportPreference != null) 'sportPreference': _sportPreference,
        if (_experienceLevel != null) 'experienceLevel': _experienceLevel,
        if (_equipment.isNotEmpty) 'equipmentAvailable': _equipment,
        if (_daysPerWeek != null) 'daysPerWeek': _daysPerWeek,
        if (_sessionLength != null) 'sessionLength': _sessionLength,
      };
      await _firestoreService.saveOnboardingStep2(uid, data);
      if (mounted) context.go(Routes.onboardingStep3);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Something went wrong. Please try again.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: WW.bg,
        body: Center(child: CircularProgressIndicator(color: WW.primary)),
      );
    }

    return Scaffold(
      backgroundColor: WW.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                transitionBuilder: (child, animation) => SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.06, 0),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(parent: animation, curve: Curves.easeOut),
                  ),
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: KeyedSubtree(
                  key: ValueKey(_questionIndex),
                  child: _buildQuestion(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Progress header ──────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Back arrow
              GestureDetector(
                onTap: _back,
                child: const Icon(
                  Icons.chevron_left_rounded,
                  color: WW.textSec,
                  size: 24,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'Step 2 of 3 · Q${_questionIndex + 1}/$_kTotal',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: WW.textSec,
                  letterSpacing: 0.3,
                ),
              ),
              const Spacer(),
              // Three dot indicators — second dot active
              Row(
                children: List.generate(3, (i) {
                  final active = i == 1;
                  return Container(
                    margin: const EdgeInsets.only(left: 6),
                    width: active ? 20 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: active ? WW.primary : WW.border,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: (_questionIndex + 1) / _kTotal,
              backgroundColor: WW.elevated,
              color: WW.primary,
              minHeight: 5,
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ── Question dispatcher ──────────────────────────────────────────────────

  Widget _buildQuestion() {
    switch (_questionIndex) {
      case 0:
        return _SurveyPage(
          title: "What's your primary goal?",
          subtitle: "We'll build your entire plan around this.",
          canAdvance: _canAdvance,
          isLastQuestion: false,
          onNext: _next,
          onSkip: _skip,
          child: _SingleSelectCards(
            options: const [
              _CardOption(
                id: 'lose_weight',
                title: 'Lose Weight',
                desc: 'Burn fat and get leaner',
                iconBg: Color(0xFFFFF3E0),
                iconColor: Color(0xFFF97316),
                iconData: Icons.local_fire_department_rounded,
              ),
              _CardOption(
                id: 'build_muscle',
                title: 'Build Muscle',
                desc: 'Gain size and definition',
                iconBg: WW.chipBg,
                iconColor: WW.primary,
                iconData: Icons.fitness_center_rounded,
              ),
              _CardOption(
                id: 'improve_endurance',
                title: 'Improve Endurance',
                desc: 'Boost cardio and stamina',
                iconBg: WW.lavenderBg,
                iconColor: WW.lavender,
                iconData: Icons.bolt_rounded,
              ),
              _CardOption(
                id: 'general_fitness',
                title: 'General Fitness',
                desc: 'Stay active and healthy',
                iconBg: Color(0xFFFFF0F0),
                iconColor: Color(0xFFEF4444),
                iconData: Icons.favorite_rounded,
              ),
            ],
            selected: _primaryGoal,
            onSelect: (v) => setState(() => _primaryGoal = v),
          ),
        );

      case 1:
        return _SurveyPage(
          title: 'What type of training?',
          subtitle: 'Choose the style that fits your lifestyle best.',
          canAdvance: _canAdvance,
          isLastQuestion: false,
          onNext: _next,
          onSkip: _skip,
          child: _SingleSelectCards(
            options: const [
              _CardOption(
                id: 'gym',
                title: 'Gym Only',
                desc: 'Weights, machines and resistance training',
                iconBg: WW.chipBg,
                iconColor: WW.primary,
                iconData: Icons.fitness_center_rounded,
              ),
              _CardOption(
                id: 'running',
                title: 'Running Only',
                desc: 'Outdoor runs, treadmill and track sessions',
                iconBg: WW.tealBg,
                iconColor: WW.teal,
                iconData: Icons.directions_run_rounded,
              ),
              _CardOption(
                id: 'both',
                title: 'Both',
                desc: 'Combined gym and cardio training',
                iconBg: WW.lavenderBg,
                iconColor: WW.lavender,
                iconData: Icons.sports_rounded,
              ),
            ],
            selected: _sportPreference,
            onSelect: (v) => setState(() => _sportPreference = v),
          ),
        );

      case 2:
        return _SurveyPage(
          title: "What's your experience?",
          subtitle: "Be honest — your plan will be calibrated to match.",
          canAdvance: _canAdvance,
          isLastQuestion: false,
          onNext: _next,
          onSkip: _skip,
          child: _SingleSelectCards(
            options: const [
              _CardOption(
                id: 'beginner',
                title: 'Beginner',
                desc: 'New to regular structured training',
                iconBg: WW.tealBg,
                iconColor: WW.teal,
                iconData: Icons.emoji_people_rounded,
              ),
              _CardOption(
                id: 'intermediate',
                title: 'Intermediate',
                desc: 'Training a few times a week consistently',
                iconBg: WW.chipBg,
                iconColor: WW.primary,
                iconData: Icons.trending_up_rounded,
              ),
              _CardOption(
                id: 'advanced',
                title: 'Advanced',
                desc: 'Experienced with a structured programme',
                iconBg: Color(0xFFFFF3E0),
                iconColor: Color(0xFFF97316),
                iconData: Icons.star_rounded,
              ),
            ],
            selected: _experienceLevel,
            onSelect: (v) => setState(() => _experienceLevel = v),
          ),
        );

      case 3:
        return _SurveyPage(
          title: 'What equipment do you have?',
          subtitle: "Select all that apply — we'll only programme what you have.",
          canAdvance: _canAdvance,
          isLastQuestion: false,
          onNext: _next,
          onSkip: _skip,
          child: _MultiSelectChips(
            options: const [
              _ChipOption(id: 'bodyweight', label: 'Home (bodyweight)'),
              _ChipOption(id: 'gym_weights', label: 'Gym with weights'),
              _ChipOption(id: 'outdoor', label: 'Outdoor'),
              _ChipOption(id: 'both', label: 'Both'),
            ],
            selected: _equipment,
            onToggle: (id) => setState(() {
              _equipment.contains(id)
                  ? _equipment.remove(id)
                  : _equipment.add(id);
            }),
          ),
        );

      case 4:
        return _SurveyPage(
          title: 'How many days per week?',
          subtitle: "Pick what's realistic — consistency beats intensity.",
          canAdvance: _canAdvance,
          isLastQuestion: false,
          onNext: _next,
          onSkip: _skip,
          child: _DaysPicker(
            selected: _daysPerWeek,
            onSelect: (v) => setState(() => _daysPerWeek = v),
          ),
        );

      case 5:
        return _SurveyPage(
          title: 'How long are your sessions?',
          subtitle: "Shorter and focused often beats long and inconsistent.",
          canAdvance: _canAdvance,
          isLastQuestion: true,
          onNext: _next,
          onSkip: _skip,
          child: _SingleSelectCards(
            options: const [
              _CardOption(
                id: '30',
                title: '~30 min',
                desc: 'Quick and focused',
                iconBg: WW.tealBg,
                iconColor: WW.teal,
                iconData: Icons.timer_rounded,
              ),
              _CardOption(
                id: '45',
                title: '~45 min',
                desc: 'Efficient and balanced',
                iconBg: WW.chipBg,
                iconColor: WW.primary,
                iconData: Icons.timer_rounded,
              ),
              _CardOption(
                id: '60',
                title: '~60 min',
                desc: 'Well-rounded sessions',
                iconBg: WW.lavenderBg,
                iconColor: WW.lavender,
                iconData: Icons.timer_rounded,
              ),
              _CardOption(
                id: '75',
                title: '75+ min',
                desc: 'All in, no rush',
                iconBg: Color(0xFFFFF3E0),
                iconColor: Color(0xFFF97316),
                iconData: Icons.timer_rounded,
              ),
            ],
            selected: _sessionLength,
            onSelect: (v) => setState(() => _sessionLength = v),
          ),
        );

      default:
        return const SizedBox.shrink();
    }
  }
}

// ── Survey page wrapper ────────────────────────────────────────────────────────
// Provides title, subtitle, scrollable options area, and a sticky footer
// containing the Next button and a right-aligned Skip link.

class _SurveyPage extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool canAdvance;
  final bool isLastQuestion;
  final VoidCallback onNext;
  final VoidCallback onSkip;
  final Widget child;

  const _SurveyPage({
    required this.title,
    required this.subtitle,
    required this.canAdvance,
    required this.isLastQuestion,
    required this.onNext,
    required this.onSkip,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: WW.primaryDark,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 14,
                    color: WW.textSec,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
                child,
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),

        // Sticky footer
        Container(
          decoration: BoxDecoration(
            color: WW.bg,
            border: Border(top: BorderSide(color: WW.border, width: 0.5)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: canAdvance ? onNext : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: WW.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: WW.border,
                    disabledForegroundColor: WW.textSec,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                    shadowColor: Colors.transparent,
                  ),
                  child: Text(
                    isLastQuestion ? 'Build my plan →' : 'Next →',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: onSkip,
                  child: const Text(
                    'Skip',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: WW.textSec,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Single-select card list ────────────────────────────────────────────────────

class _SingleSelectCards extends StatelessWidget {
  final List<_CardOption> options;
  final String? selected;
  final ValueChanged<String> onSelect;

  const _SingleSelectCards({
    required this.options,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: options.map((opt) {
        final sel = selected == opt.id;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: GestureDetector(
            onTap: () => onSelect(opt.id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              decoration: BoxDecoration(
                color: sel ? WW.chipBg : WW.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: sel ? WW.primary : WW.border,
                  width: sel ? 1.5 : 1.0,
                ),
                boxShadow: WW.shadow,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  // Icon container
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: sel
                          ? WW.primary.withOpacity(0.14)
                          : opt.iconBg,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(opt.iconData, color: opt.iconColor, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          opt.title,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: sel ? WW.primary : WW.text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          opt.desc,
                          style: const TextStyle(
                            fontSize: 12,
                            color: WW.textSec,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (sel) ...[
                    const SizedBox(width: 10),
                    Container(
                      width: 22,
                      height: 22,
                      decoration: const BoxDecoration(
                        color: WW.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 14,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── Multi-select chip grid ─────────────────────────────────────────────────────

class _MultiSelectChips extends StatelessWidget {
  final List<_ChipOption> options;
  final List<String> selected;
  final ValueChanged<String> onToggle;

  const _MultiSelectChips({
    required this.options,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((opt) {
        final sel = selected.contains(opt.id);
        return GestureDetector(
          onTap: () => onToggle(opt.id),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: sel ? WW.primary : WW.card,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: sel ? WW.primary : WW.border,
                width: 1.5,
              ),
              boxShadow: sel
                  ? [
                      BoxShadow(
                        color: WW.primary.withOpacity(0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : WW.shadow,
            ),
            child: Text(
              opt.label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: sel ? Colors.white : WW.text,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── Days-per-week pill selector ────────────────────────────────────────────────

class _DaysPicker extends StatelessWidget {
  final int? selected;
  final ValueChanged<int> onSelect;

  const _DaysPicker({required this.selected, required this.onSelect});

  static const _labels = {
    2: 'Light',
    3: 'Moderate',
    4: 'Active',
    5: 'Dedicated',
    6: 'Intensive',
  };

  static const _details = {
    2: '2 sessions: perfect for getting started without burning out.',
    3: '3 sessions: the sweet spot for steady, sustainable progress.',
    4: '4 sessions: solid training volume with good recovery built in.',
    5: '5 sessions: suits dedicated athletes ready to push limits.',
    6: '6 sessions: intensive schedule for peak performance goals.',
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [2, 3, 4, 5, 6].map((day) {
            final sel = selected == day;
            final isLast = day == 6;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: isLast ? 0 : 8),
                child: GestureDetector(
                  onTap: () => onSelect(day),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: 68,
                    decoration: BoxDecoration(
                      color: sel ? WW.chipBg : WW.card,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: sel ? WW.primary : WW.border,
                        width: sel ? 1.5 : 1.0,
                      ),
                      boxShadow: WW.shadow,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$day',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: sel ? WW.primary : WW.text,
                          ),
                        ),
                        const SizedBox(height: 3),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            _labels[day]!,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: sel ? WW.primary : WW.textSec,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),

        // Detail card shown when a day is selected
        if (selected != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: WW.chipBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: WW.primary.withOpacity(0.2)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: WW.primary,
                  size: 16,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$selected days / week — ${_labels[selected]!.toLowerCase()}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: WW.primaryDark,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _details[selected]!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: WW.textSec,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
