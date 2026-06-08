// lib/screens/club/club_screen.dart
import 'package:flutter/material.dart';

import '../../core/app_theme.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

String _fmtXp(int xp) {
  if (xp >= 1000) {
    return '${xp ~/ 1000},${(xp % 1000).toString().padLeft(3, '0')}';
  }
  return '$xp';
}

// ── Data types ────────────────────────────────────────────────────────────────

class _LeaderEntry {
  final int rank;
  final String initial;
  final Color color;
  final String name;
  final String level;
  final int xp;
  final bool isMe;
  const _LeaderEntry({
    required this.rank,
    required this.initial,
    required this.color,
    required this.name,
    required this.level,
    required this.xp,
    this.isMe = false,
  });
}

class _Challenge {
  final String name;
  final String detail;
  final Color gradStart;
  final Color gradEnd;
  final int pct;
  final Color pctColor;
  const _Challenge({
    required this.name,
    required this.detail,
    required this.gradStart,
    required this.gradEnd,
    required this.pct,
    required this.pctColor,
  });
}

class _DiscoverCard {
  final String name;
  final int participants;
  final int xp;
  final Color gradStart;
  final Color gradEnd;
  const _DiscoverCard({
    required this.name,
    required this.participants,
    required this.xp,
    required this.gradStart,
    required this.gradEnd,
  });
}

class _Friend {
  final String initial;
  final Color color;
  final String name;
  final String username;
  final String level;
  final int weeklyXp;
  const _Friend({
    required this.initial,
    required this.color,
    required this.name,
    required this.username,
    required this.level,
    required this.weeklyXp,
  });
}

class _MiniEntry {
  final String initial;
  final Color color;
  final String name;
  final int pct;
  const _MiniEntry({
    required this.initial,
    required this.color,
    required this.name,
    required this.pct,
  });
}

// ── Hardcoded data ────────────────────────────────────────────────────────────

// Color(0xFF4CAF50) is a data-specific accent green not present in WW.
const _kGreen = Color(0xFF4CAF50);

const _kLeaderboard = <_LeaderEntry>[
  _LeaderEntry(rank: 1, initial: 'A', color: WW.gold,     name: 'Alex Chen', level: 'Level 9', xp: 3120),
  _LeaderEntry(rank: 2, initial: 'M', color: WW.primary,  name: 'You',       level: 'Level 7', xp: 2840, isMe: true),
  _LeaderEntry(rank: 3, initial: 'S', color: WW.teal,     name: 'Sarah K',   level: 'Level 6', xp: 2210),
  _LeaderEntry(rank: 4, initial: 'J', color: WW.lavender, name: 'James L',   level: 'Level 5', xp: 1890),
  _LeaderEntry(rank: 5, initial: 'R', color: _kGreen,     name: 'Riya P',    level: 'Level 4', xp: 1240),
];

const _kActiveChallenges = <_Challenge>[
  _Challenge(
    name: '10k Steps Squad',
    detail: '50,000 steps total · 4 participants · Ends May 18',
    gradStart: WW.primaryDark,
    gradEnd: WW.teal,
    pct: 68,
    pctColor: WW.teal,
  ),
  _Challenge(
    name: 'Weekly Run Club',
    detail: '20 km this week · 3 participants · Ends May 17',
    gradStart: WW.teal,
    gradEnd: WW.primary,
    pct: 45,
    pctColor: WW.primary,
  ),
];

const _kDiscoverChallenges = <_DiscoverCard>[
  _DiscoverCard(name: 'May Strength Month', participants: 142, xp: 500, gradStart: WW.primaryDark, gradEnd: WW.primary),
  _DiscoverCard(name: '5K Every Week',      participants: 89,  xp: 300, gradStart: WW.primary,     gradEnd: WW.lavender),
  _DiscoverCard(name: '30-Day Core',        participants: 67,  xp: 400, gradStart: WW.gold,        gradEnd: WW.primary),
];

const _kFriends = <_Friend>[
  _Friend(initial: 'A', color: WW.gold,     name: 'Alex Chen', username: '@alexchen', level: 'Level 9', weeklyXp: 3120),
  _Friend(initial: 'S', color: WW.teal,     name: 'Sarah K',   username: '@sarahk',   level: 'Level 6', weeklyXp: 2210),
  _Friend(initial: 'J', color: WW.lavender, name: 'James L',   username: '@jamesl',   level: 'Level 5', weeklyXp: 1890),
  _Friend(initial: 'R', color: _kGreen,     name: 'Riya P',    username: '@riyap',    level: 'Level 4', weeklyXp: 1240),
];

// Participants in the 10k Steps Squad challenge
const _kMiniLeader = <_MiniEntry>[
  _MiniEntry(initial: 'M', color: WW.primary,  name: 'You',       pct: 68),
  _MiniEntry(initial: 'A', color: WW.gold,     name: 'Alex Chen', pct: 55),
  _MiniEntry(initial: 'S', color: WW.teal,     name: 'Sarah K',   pct: 42),
  _MiniEntry(initial: 'J', color: WW.lavender, name: 'James L',   pct: 30),
];

// ── Screen ────────────────────────────────────────────────────────────────────

class ClubScreen extends StatefulWidget {
  const ClubScreen({super.key});

  @override
  State<ClubScreen> createState() => _ClubScreenState();
}

class _ClubScreenState extends State<ClubScreen> {
  int _subtab = 0;
  String _searchQuery = '';

  static const _subtabLabels = ['Leaderboard', 'Challenges', 'Friends'];
  static const _kDivider = Color(0xFFE8EAF8);

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: WW.primaryDark,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: WW.bg,
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTopBar(),
            _buildSubtabs(),
            Expanded(
              child: IndexedStack(
                index: _subtab,
                children: [
                  _buildLeaderboardTab(),
                  _buildChallengesTab(),
                  _buildFriendsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Top bar ───────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Club',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: WW.primaryDark,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => _snack('Add friend coming soon'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: WW.primary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.person_add_rounded, color: Colors.white, size: 15),
                  SizedBox(width: 6),
                  Text(
                    'Add Friend',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Subtabs ───────────────────────────────────────────────────────────────

  Widget _buildSubtabs() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Row(
        children: List.generate(_subtabLabels.length, (i) {
          final active = i == _subtab;
          return Padding(
            padding: EdgeInsets.only(right: i < _subtabLabels.length - 1 ? 8 : 0),
            child: GestureDetector(
              onTap: () => setState(() => _subtab = i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: active ? WW.primary : const Color(0xFFF2F2F7),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Text(
                    _subtabLabels[i],
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: active ? Colors.white : WW.textSec,
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // LEADERBOARD TAB
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildLeaderboardTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'THIS WEEK · FRIENDS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: WW.textSec,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 10),
          _buildYourRankCard(),
          const SizedBox(height: 10),
          Container(
            decoration: WW.cardDecoration,
            child: Column(
              children: () {
                final others = _kLeaderboard.where((e) => !e.isMe).toList();
                return List.generate(others.length, (i) {
                  return _buildLeaderRow(others[i], isLast: i == others.length - 1);
                });
              }(),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            '10K STEPS SQUAD · ENDS MAY 18',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: WW.textSec,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            decoration: WW.cardDecoration,
            child: Column(
              children: List.generate(_kMiniLeader.length, (i) {
                return _buildMiniLeaderRow(
                  _kMiniLeader[i],
                  isLast: i == _kMiniLeader.length - 1,
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildYourRankCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: WW.chipBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: WW.primary, width: 1),
        boxShadow: WW.shadow,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Center(
              child: Text(
                '#2',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: WW.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: WW.primary,
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Text(
                'M',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'You',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: WW.primaryDark,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Level 7',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: WW.textSec,
                  ),
                ),
              ],
            ),
          ),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '2,840 XP',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: WW.primary,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'This week',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: WW.textSec,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLeaderRow(_LeaderEntry entry, {required bool isLast}) {
    final isFirst = entry.rank == 1;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isFirst ? const Color(0x0FF59E0B) : Colors.transparent,
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: _kDivider, width: 0.5)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Center(
              child: isFirst
                  ? const Text('🥇', style: TextStyle(fontSize: 18))
                  : Text(
                      '#${entry.rank}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: WW.textSec,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: entry.color,
              shape: BoxShape.circle,
              boxShadow: isFirst
                  ? [BoxShadow(color: entry.color.withValues(alpha: 0.4), blurRadius: 8, offset: const Offset(0, 2))]
                  : null,
            ),
            child: Center(
              child: Text(
                entry.initial,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: WW.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  entry.level,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: WW.textSec,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${_fmtXp(entry.xp)} XP',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: isFirst ? WW.gold : WW.text,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniLeaderRow(_MiniEntry entry, {required bool isLast}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: _kDivider, width: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: entry.color,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                entry.initial,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: WW.text,
                  ),
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: entry.pct / 100,
                    minHeight: 5,
                    backgroundColor: WW.elevated,
                    valueColor: AlwaysStoppedAnimation<Color>(entry.color),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${entry.pct}%',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: WW.text,
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // CHALLENGES TAB
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildChallengesTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // MY CHALLENGES header + Create button
          Row(
            children: [
              const Expanded(
                child: Text(
                  'MY CHALLENGES',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: WW.textSec,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => _snack('Create challenge coming soon'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    border: Border.all(color: WW.primary, width: 1.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_rounded, color: WW.primary, size: 14),
                      SizedBox(width: 4),
                      Text(
                        'Create',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: WW.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ..._kActiveChallenges.map(_buildActiveChallengeCard),
          const SizedBox(height: 6),
          const Text(
            'DISCOVER CHALLENGES',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: WW.textSec,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 10),
          ..._kDiscoverChallenges.map(_buildDiscoverCard),
        ],
      ),
    );
  }

  Widget _buildActiveChallengeCard(_Challenge c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: WW.cardDecoration,
        clipBehavior: Clip.hardEdge,
        child: Column(
          children: [
            // Gradient hero strip
            Container(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [c.gradStart, c.gradEnd],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    c.detail,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            // Progress
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Your progress',
                        style: TextStyle(fontSize: 11, color: WW.textSec),
                      ),
                      Text(
                        '${c.pct}% complete',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: WW.text,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: c.pct / 100,
                      minHeight: 6,
                      backgroundColor: WW.elevated,
                      valueColor: AlwaysStoppedAnimation<Color>(c.pctColor),
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

  Widget _buildDiscoverCard(_DiscoverCard c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: WW.cardDecoration,
        clipBehavior: Clip.hardEdge,
        child: Column(
          children: [
            // Gradient hero
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [c.gradStart, c.gradEnd],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // XP pill
                  Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star_rounded, color: Colors.white, size: 11),
                          const SizedBox(width: 3),
                          Text(
                            '+${c.xp} XP',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    c.name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
            ),
            // Stats + Join button
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.people_outline_rounded, size: 14, color: WW.textSec),
                      const SizedBox(width: 4),
                      Text(
                        '${c.participants} joined',
                        style: const TextStyle(fontSize: 12, color: WW.textSec),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () => _snack('Challenge join coming soon'),
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: WW.primary,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Center(
                        child: Text(
                          'Join Challenge',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
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

  // ══════════════════════════════════════════════════════════════════════════
  // FRIENDS TAB
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildFriendsTab() {
    final filtered = _searchQuery.isEmpty
        ? _kFriends
        : _kFriends
            .where((f) =>
                f.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                f.username.toLowerCase().contains(_searchQuery.toLowerCase()))
            .toList();

    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Container(
            height: 42,
            decoration: BoxDecoration(
              color: WW.elevated,
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
              onChanged: (v) => setState(() => _searchQuery = v),
              style: const TextStyle(fontSize: 14, color: WW.text),
              decoration: const InputDecoration(
                hintText: 'Search by username...',
                hintStyle: TextStyle(fontSize: 14, color: WW.textSec),
                prefixIcon: Icon(Icons.search_rounded, color: WW.textSec, size: 20),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ),
        // Friends list
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
            children: [
              Text(
                'FRIENDS (${filtered.length})',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: WW.textSec,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 10),
              if (filtered.isNotEmpty)
                Container(
                  decoration: WW.cardDecoration,
                  child: Column(
                    children: List.generate(filtered.length, (i) {
                      return _buildFriendRow(filtered[i], isLast: i == filtered.length - 1);
                    }),
                  ),
                ),
              const SizedBox(height: 16),
              // Find more friends button
              GestureDetector(
                onTap: () => _snack('Search coming soon'),
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    border: Border.all(color: WW.primary, width: 1.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_rounded, color: WW.primary, size: 18),
                      SizedBox(width: 6),
                      Text(
                        'Find More Friends',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: WW.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFriendRow(_Friend f, {required bool isLast}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: _kDivider, width: 0.5)),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: f.color,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                f.initial,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Name, username, level
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  f.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: WW.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${f.username} · ${f.level}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: WW.textSec,
                  ),
                ),
              ],
            ),
          ),
          // Weekly XP
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _fmtXp(f.weeklyXp),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: WW.primaryDark,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Weekly XP',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: WW.textSec,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
