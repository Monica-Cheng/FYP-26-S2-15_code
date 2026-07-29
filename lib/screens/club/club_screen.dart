// lib/screens/club/club_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../core/router.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../widgets/feed_post_card.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

String _fmtXp(int xp) {
  if (xp >= 1000) {
    return '${xp ~/ 1000},${(xp % 1000).toString().padLeft(3, '0')}';
  }
  return '$xp';
}

// ── Data types ────────────────────────────────────────────────────────────────

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

// Participants in the 10k Steps Squad challenge
const _kMiniLeader = <_MiniEntry>[
  _MiniEntry(initial: 'M', color: WW.primary,  name: 'You',       pct: 68),
  _MiniEntry(initial: 'A', color: WW.gold,     name: 'Alex Chen', pct: 55),
  _MiniEntry(initial: 'S', color: WW.teal,     name: 'Sarah K',   pct: 42),
  _MiniEntry(initial: 'J', color: WW.lavender, name: 'James L',   pct: 30),
];

// ── Screen ────────────────────────────────────────────────────────────────────

class ClubScreen extends StatefulWidget {
  // Sentinel value for initialSubtab meaning "open the Friends modal on
  // load" (e.g. deep-linking from a friend-request notification in
  // home_screen.dart). Friends is no longer a real subtab index — its
  // content moved into a modal — but this constant stays so callers
  // elsewhere in the app don't need to change.
  static const int kFriendsSubtabIndex = 2;

  final int initialSubtab;
  const ClubScreen({super.key, this.initialSubtab = 0});

  @override
  State<ClubScreen> createState() => _ClubScreenState();
}

class _ClubScreenState extends State<ClubScreen> {
  late int _subtab;

  final _firestoreService = FirestoreService();
  final _authService = AuthService();
  String _myName = 'You';

  // Needed here (not just by FriendsScreen) because the Leaderboard tab
  // scopes its query to friend uids — see _buildLeaderboardTab().
  List<Map<String, dynamic>> _friends = [];
  StreamSubscription<List<Map<String, dynamic>>>? _friendsSub;

  static const _subtabLabels = ['Leaderboard', 'Challenges', 'Feed'];
  static const _kDivider = Color(0xFFE8EAF8);

  // Lighter-weight section-header style for Leaderboard — same role as
  // the old all-caps 11px/w700 label, just less visually loud.
  static const _kSectionHeaderStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: WW.textSec,
    letterSpacing: 0.2,
  );

  @override
  void initState() {
    super.initState();
    final wantsFriends = widget.initialSubtab == ClubScreen.kFriendsSubtabIndex;
    _subtab = wantsFriends ? 0 : widget.initialSubtab;
    _loadMyName();
    _startFriendStreams();
    if (wantsFriends) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.push(Routes.friends, extra: {'expandRequests': true});
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant ClubScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // ClubScreen stays alive inside HomeScreen's IndexedStack, so a new
    // initialSubtab (e.g. deep-linking to Friends from a notification)
    // arrives here rather than through initState() a second time.
    if (widget.initialSubtab != oldWidget.initialSubtab) {
      final wantsFriends = widget.initialSubtab == ClubScreen.kFriendsSubtabIndex;
      if (wantsFriends) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            context.push(Routes.friends, extra: {'expandRequests': true});
          }
        });
      } else {
        setState(() => _subtab = widget.initialSubtab);
      }
    }
  }

  @override
  void dispose() {
    _friendsSub?.cancel();
    super.dispose();
  }

  Future<void> _loadMyName() async {
    final uid = _authService.getCurrentUser()?.uid;
    if (uid == null) return;
    final profile = await _firestoreService.getUserProfile(uid);
    final name = profile?['displayName'] as String?;
    if (mounted) {
      setState(() {
        if (name != null && name.isNotEmpty) _myName = name;
      });
    }
  }

  void _startFriendStreams() {
    final uid = _authService.getCurrentUser()?.uid;
    if (uid == null) return;
    _friendsSub = _firestoreService.getFriendsStream(uid).listen((friends) {
      if (mounted) setState(() => _friends = friends);
    });
  }

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
                  _buildFeedTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Neutral avatar treatment shared by every Leaderboard/Friends row —
  // WW.elevated + WW.text initial for everyone, WW.primary + white for
  // the current signed-in user's own row only.
  Widget _avatar(String initial, {bool isMe = false}) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: isMe ? WW.primary : WW.elevated,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: isMe ? Colors.white : WW.text,
          ),
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
            onTap: () => context.push(Routes.friends),
            child: Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: WW.primary,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person_add_rounded, color: Colors.white, size: 17),
            ),
          ),
        ],
      ),
    );
  }

  // ── Subtabs ───────────────────────────────────────────────────────────────

  // Evenly distributed across the full row width (3 short labels, plenty
  // of room per segment) instead of the old left-aligned, horizontally
  // scrolling Row.
  Widget _buildSubtabs() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Row(
        children: List.generate(_subtabLabels.length, (i) {
          final active = i == _subtab;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i < _subtabLabels.length - 1 ? 8 : 0),
              child: GestureDetector(
                onTap: () => setState(() => _subtab = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 34,
                  decoration: BoxDecoration(
                    color: active ? WW.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(17),
                    border: Border.all(
                      color: active ? WW.primary : WW.border,
                      width: 1,
                    ),
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
    final myUid = _authService.getCurrentUser()?.uid ?? '';
    final friendUids = _friends.map((f) => f['uid'] as String).toList();
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _firestoreService.getFriendsLeaderboardStream(myUid, friendUids),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: WW.primary));
        }
        final entries = snapshot.data ?? [];
        if (entries.length <= 1) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Add friends to see the leaderboard',
                style: TextStyle(fontSize: 13, color: WW.textSec),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Text('THIS WEEK · FRIENDS', style: _kSectionHeaderStyle),
              ),
              Column(
                children: List.generate(entries.length, (i) {
                  final entry = entries[i];
                  return _buildLeaderRow(
                    entry,
                    rank: i + 1,
                    isMe: entry['uid'] == myUid,
                    isLast: i == entries.length - 1,
                  );
                }),
              ),
              const SizedBox(height: 20),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Text(
                  '10K STEPS SQUAD · ENDS MAY 18',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: WW.textSec,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              Column(
                children: List.generate(_kMiniLeader.length, (i) {
                  return _buildMiniLeaderRow(
                    _kMiniLeader[i],
                    isLast: i == _kMiniLeader.length - 1,
                  );
                }),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLeaderRow(
    Map<String, dynamic> entry, {
    required int rank,
    required bool isMe,
    required bool isLast,
  }) {
    final isFirst = rank == 1;
    final name = entry['displayName'] as String? ?? (isMe ? _myName : 'User');
    final level = (entry['level'] as num?)?.toInt();
    final levelLabel = level != null ? 'Level $level' : '—';
    final weeklyXp = (entry['weeklyXp'] as int?) ?? 0;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      decoration: BoxDecoration(
        color: WW.card,
        border: Border(
          left: BorderSide(
            color: isMe ? WW.text : Colors.transparent,
            width: 3,
          ),
          bottom: isLast
              ? BorderSide.none
              : const BorderSide(color: _kDivider, width: 0.5),
        ),
      ),
      padding: EdgeInsets.fromLTRB(isMe ? 17 : 20, 12, 20, 12),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Center(
              child: Text(
                '#$rank',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isFirst ? FontWeight.w800 : FontWeight.w700,
                  color: isFirst ? WW.text : WW.textSec,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _avatar(initial, isMe: isMe),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: WW.rowName.copyWith(
                    fontWeight: isMe ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(levelLabel, style: WW.rowSecondary),
              ],
            ),
          ),
          Text('${_fmtXp(weeklyXp)} XP', style: WW.rowStat),
        ],
      ),
    );
  }

  Widget _buildMiniLeaderRow(_MiniEntry entry, {required bool isLast}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
      decoration: BoxDecoration(
        color: WW.card,
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
  // FEED TAB — real Firestore-backed posts (not mock). App-wide for now,
  // since this app doesn't yet have a real friend-relationship system to
  // scope it to friends only (see note on FirestoreService.getFeedPostsStream).
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildFeedTab() {
    final uid = _authService.getCurrentUser()?.uid ?? '';

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _firestoreService.getFeedPostsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: WW.primary),
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Could not load the feed. ${snapshot.error}',
                style: WW.labelMed,
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        final posts = snapshot.data ?? [];
        if (posts.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.dynamic_feed_rounded,
                      size: 40, color: WW.textSec),
                  const SizedBox(height: 12),
                  const Text('No posts yet', style: WW.titleMed),
                  const SizedBox(height: 6),
                  const Text(
                    'Scan or describe a meal, then tap "Post to Feed" '
                    'to share it here.',
                    style: WW.labelMed,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
          itemCount: posts.length,
          itemBuilder: (context, i) => FeedPostCard(
            post: posts[i],
            currentUid: uid,
            currentUserName: _myName,
            firestoreService: _firestoreService,
          ),
        );
      },
    );
  }
}
