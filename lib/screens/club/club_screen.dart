// lib/screens/club/club_screen.dart
// Club tab: Leaderboard/Challenges/Feed subtabs. Leaderboard ranks users by
// weekly activity, Challenges lists/joins group challenges, and Feed shows
// the real Firestore-backed social feed of workout/nutrition posts.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../core/router.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../widgets/feed_post_card.dart';
import '../../widgets/user_avatar.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

String _fmtXp(int xp) {
  if (xp >= 1000) {
    return '${xp ~/ 1000},${(xp % 1000).toString().padLeft(3, '0')}';
  }
  return '$xp';
}

// ── Challenge display helpers ────────────────────────────────────────────────
// Small pure functions shared by both the "My Challenges" and "Discover"
// cards below — a distinctive color per category (kept to this app's
// existing WW palette, no new colors) and a compact squircle-badge label
// ("5K", "500cal", "60min") derived directly from the challenge's own
// goalValue/unit fields, never hardcoded per-challenge data.

Color _challengeCategoryColor(String metricType) {
  switch (metricType) {
    case 'distance':
      return WW.teal;
    case 'calories':
      return WW.gold;
    case 'duration':
      return WW.lavender;
    default:
      return WW.primary;
  }
}

String _fmtChallengeNum(double value) {
  return value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1);
}

String _challengeBadgeLabel(double goalValue, String unit) {
  final valueStr = _fmtChallengeNum(goalValue);
  switch (unit) {
    case 'km':
      return '${valueStr}K';
    default:
      return '$valueStr$unit';
  }
}

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
  String? _myPhotoBase64;

  // Needed here (not just by FriendsScreen) because the Leaderboard tab
  // scopes its query to friend uids — see _buildLeaderboardTab().
  List<Map<String, dynamic>> _friends = [];
  StreamSubscription<List<Map<String, dynamic>>>? _friendsSub;

  // Bumped by the Challenges tab's error-state Retry buttons — changing
  // the StreamBuilder's key forces a fresh subscription (and therefore a
  // fresh query attempt) instead of relying on the fact that
  // getMyChallengesStream()/getDiscoverableChallengesStream() happen to
  // return a new Stream instance on every rebuild anyway.
  int _myChallengesRetryCount = 0;
  int _discoverChallengesRetryCount = 0;

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

  List<Map<String, dynamic>> _visiblePosts(List<Map<String, dynamic>> posts) {
    return posts.where((post) => post['isHidden'] != true).toList(growable: false);
  }

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
        _myPhotoBase64 = profile?['photoBase64'] as String?;
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
  Widget _avatar(String initial, {String? photoBase64, bool isMe = false}) {
    return UserAvatar(
      photoBase64: photoBase64,
      initial: initial,
      size: 40,
      backgroundColor: isMe ? WW.primary : WW.elevated,
      initialColor: isMe ? Colors.white : WW.text,
      initialFontSize: 15,
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
    final photoBase64 = entry['photoBase64'] as String?;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openLeaderboardProfile(entry, isMe: isMe),
      child: Container(
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
            _avatar(initial, photoBase64: photoBase64, isMe: isMe),
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
      ),
    );
  }

  // Tapping your own row opens the existing own-profile screen
  // (Routes.profile) rather than user_profile_screen.dart, which is
  // built specifically for viewing OTHER people (Follow/Unfollow,
  // someone else's posts) — same navigation FeedPostCard's avatar/name
  // already uses for other users (see its _openProfile()).
  void _openLeaderboardProfile(Map<String, dynamic> entry, {required bool isMe}) {
    if (isMe) {
      context.push(Routes.profile);
      return;
    }
    final uid = entry['uid'] as String?;
    if (uid == null || uid.isEmpty) return;
    context.push(
      Routes.userProfile,
      extra: {
        'uid': uid,
        'authorName': entry['displayName'] as String?,
      },
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // CHALLENGES TAB — real Firestore-backed (getMyChallengesStream()/
  // getDiscoverableChallengesStream()), not mock. Full-bleed: no outer
  // Container/border wraps either list — each challenge is its own
  // WW.cardDecoration card sitting directly on the tab's WW.bg background,
  // matching the per-item (not per-section) elevation convention this app
  // already uses elsewhere (see plan_detail_screen.dart's own cards).
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildChallengesTab() {
    final uid = _authService.getCurrentUser()?.uid ?? '';
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
                onTap: () => context.push(Routes.createChallenge),
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
          StreamBuilder<List<Map<String, dynamic>>>(
            key: ValueKey('myChallenges-$_myChallengesRetryCount'),
            stream: _firestoreService.getMyChallengesStream(uid),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: CircularProgressIndicator(color: WW.primary)),
                );
              }
              if (snapshot.hasError) {
                return _buildChallengesErrorState(
                  "Couldn't load your challenges",
                  onRetry: () => setState(() => _myChallengesRetryCount++),
                );
              }
              final challenges = snapshot.data ?? [];
              if (challenges.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text(
                      "You're not in any challenges yet — create one or join a public challenge below.",
                      style: TextStyle(fontSize: 13, color: WW.textSec),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              return Column(
                children: challenges
                    .map((c) => _buildMyChallengeCard(uid, c))
                    .toList(),
              );
            },
          ),
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
          StreamBuilder<List<Map<String, dynamic>>>(
            key: ValueKey('discoverChallenges-$_discoverChallengesRetryCount'),
            stream: _firestoreService.getDiscoverableChallengesStream(uid),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: CircularProgressIndicator(color: WW.primary)),
                );
              }
              if (snapshot.hasError) {
                return _buildChallengesErrorState(
                  "Couldn't load public challenges",
                  onRetry: () => setState(() => _discoverChallengesRetryCount++),
                );
              }
              final challenges = snapshot.data ?? [];
              if (challenges.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text(
                      'No public challenges available right now.',
                      style: TextStyle(fontSize: 13, color: WW.textSec),
                    ),
                  ),
                );
              }
              return Column(
                children: challenges
                    .map((c) => _buildDiscoverChallengeCard(uid, c))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  // Matches build_routine_screen.dart's exercise-search _buildErrorState()
  // convention exactly (icon + bold message + Retry pill) — shown whenever
  // a challenges stream actually errors (e.g. a missing composite index,
  // a permission-denied from rules), never silently folded into the
  // "genuinely empty" state above.
  Widget _buildChallengesErrorState(String message, {required VoidCallback onRetry}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 40, color: WW.textSec),
            const SizedBox(height: 10),
            Text(
              message,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: WW.text,
              ),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: onRetry,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: WW.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'Retry',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Squircle badge (soft rounded-corner square, not a circle/hexagon)
  // showing the goal value + unit as compact text — e.g. "5K", "500cal",
  // "60min" — colored per category via _challengeCategoryColor().
  Widget _challengeBadge(Map<String, dynamic> challenge) {
    final unit = challenge['unit'] as String? ?? '';
    final metricType = challenge['metricType'] as String? ?? 'distance';
    final goalValue = (challenge['goalValue'] as num?)?.toDouble() ?? 0;
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: _challengeCategoryColor(metricType),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Center(
        child: Text(
          _challengeBadgeLabel(goalValue, unit),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildMyChallengeCard(String uid, Map<String, dynamic> challenge) {
    final challengeId = challenge['id'] as String;
    final name = challenge['name'] as String? ?? 'Challenge';
    final unit = challenge['unit'] as String? ?? '';
    final metricType = challenge['metricType'] as String? ?? 'distance';
    final goalValue = (challenge['goalValue'] as num?)?.toDouble() ?? 0;
    final color = _challengeCategoryColor(metricType);
    final participantCount =
        (challenge['participantUids'] as List?)?.length ?? 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => context.push(
          Routes.challengeDetail,
          extra: {'challengeId': challengeId},
        ),
        child: Container(
          decoration: WW.cardDecoration,
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _challengeBadge(challenge),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: WW.text,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$participantCount participant${participantCount == 1 ? '' : 's'}',
                      style: const TextStyle(fontSize: 11, color: WW.textSec),
                    ),
                    const SizedBox(height: 8),
                    FutureBuilder<double>(
                      future: _firestoreService.computeChallengeProgress(uid, challenge),
                      builder: (context, snap) {
                        final progress = snap.data ?? 0.0;
                        final pct = goalValue > 0
                            ? (progress / goalValue).clamp(0.0, 1.0)
                            : 0.0;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: pct,
                                minHeight: 6,
                                backgroundColor: WW.elevated,
                                valueColor: AlwaysStoppedAnimation<Color>(color),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              snap.connectionState == ConnectionState.waiting
                                  ? 'Loading…'
                                  : '${_fmtChallengeNum(progress)} / ${_fmtChallengeNum(goalValue)} $unit',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: WW.textSec,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDiscoverChallengeCard(String uid, Map<String, dynamic> challenge) {
    final challengeId = challenge['id'] as String;
    final name = challenge['name'] as String? ?? 'Challenge';
    final participantCount =
        (challenge['participantUids'] as List?)?.length ?? 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => context.push(
          Routes.challengeDetail,
          extra: {'challengeId': challengeId},
        ),
        child: Container(
          decoration: WW.cardDecoration,
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              _challengeBadge(challenge),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: WW.text,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$participantCount joined',
                      style: const TextStyle(fontSize: 11, color: WW.textSec),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () async {
                  await _firestoreService.joinChallenge(uid, challengeId);
                  if (mounted) _snack('Joined $name!');
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: WW.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'Join',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
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

        final posts = _visiblePosts(snapshot.data ?? []);
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
            currentUserPhotoBase64: _myPhotoBase64,
            firestoreService: _firestoreService,
          ),
        );
      },
    );
  }
}
