// lib/screens/profile/profile_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../core/router.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';

// ── Data classes ──────────────────────────────────────────────────────────────

class _Badge {
  final IconData icon;
  final Color bgColor;
  final String label;
  final bool locked;
  const _Badge({
    required this.icon,
    required this.bgColor,
    required this.label,
    this.locked = false,
  });
}

class _Friend {
  final String initial;
  final Color color;
  final String name;
  final String username;
  final int level;
  final String xp;
  const _Friend({
    required this.initial,
    required this.color,
    required this.name,
    required this.username,
    required this.level,
    required this.xp,
  });
}

// ── Hardcoded data ────────────────────────────────────────────────────────────

// Violet — avatar accent not present in WW palette
const _kPurple = Color(0xFF8B5CF6);
// Off-white — locked-badge background not present in WW palette
const _kLockedBg = Color(0xFFF2F2F7);

const _kBadges = <_Badge>[
  _Badge(icon: Icons.fitness_center_rounded,        bgColor: WW.teal,    label: 'First Workout'),
  _Badge(icon: Icons.local_fire_department_rounded, bgColor: WW.teal,    label: '7-Day Streak'),
  _Badge(icon: Icons.emoji_events_rounded,          bgColor: WW.primary, label: 'Personal Best'),
  _Badge(icon: Icons.people_rounded,                bgColor: WW.gold,    label: 'Squad Win'),
  _Badge(icon: Icons.lock_rounded, bgColor: _kLockedBg, label: 'Locked', locked: true),
  _Badge(icon: Icons.lock_rounded, bgColor: _kLockedBg, label: 'Locked', locked: true),
];

const _kFriends = <_Friend>[
  _Friend(initial: 'A', color: WW.primary, name: 'Aiden Lee',  username: '@aidenlee',  level: 9,  xp: '1,840'),
  _Friend(initial: 'S', color: WW.teal,    name: 'Sarah Lim',  username: '@sarahlim',  level: 6,  xp: '1,240'),
  _Friend(initial: 'Z', color: WW.gold,    name: 'Zaid Malik', username: '@zaidmalik', level: 4,  xp: '860'),
  _Friend(initial: 'A', color: _kPurple,   name: 'Audrey Ng',  username: '@audreyng',  level: 11, xp: '2,340'),
];

// ── Screen ────────────────────────────────────────────────────────────────────

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _auth = AuthService();
  final _firestore = FirestoreService();

  String? _displayName;
  String? _hometown;
  String? _bio;
  bool _isLoading = true;
  int _totalXp = 0;
  int _level = 1;

  static const _kXpThresholds = [0, 500, 1200, 2500, 4500, 7000, 10000, 14000, 19000, 25000, 32000];

  static String _levelName(int level) {
    const names = [
      '', 'Rookie', 'Beginner', 'Apprentice', 'Contender',
      'Challenger', 'Warrior', 'Iron Athlete', 'Steel Athlete',
      'Elite Athlete', 'Champion', 'Legend',
    ];
    if (level < 1 || level >= names.length) return 'Level $level';
    return names[level];
  }

  double _xpProgress() {
    if (_level >= _kXpThresholds.length) return 1.0;
    final start = _kXpThresholds[_level - 1];
    final end = _kXpThresholds[_level];
    return ((_totalXp - start) / (end - start)).clamp(0.0, 1.0);
  }

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final uid = _auth.getCurrentUser()?.uid;
    if (uid == null) {
      setState(() => _isLoading = false);
      return;
    }
    try {
      final profile = await _firestore.getUserProfile(uid);
      if (mounted) {
        setState(() {
          _displayName = profile?['displayName'] as String?;
          _hometown = profile?['hometown'] as String?;
          _bio = profile?['bio'] as String?;
          _totalXp = (profile?['totalXp'] as num?)?.toInt() ?? 0;
          _level = (profile?['level'] as num?)?.toInt() ?? 1;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
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

  String get _nameDisplay => _isLoading ? '' : (_displayName ?? 'Athlete');
  String get _initial => _nameDisplay.isNotEmpty ? _nameDisplay.trim()[0].toUpperCase() : '?';
  String get _username => '@${_nameDisplay.toLowerCase().replaceAll(' ', '')}';

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
                padding: const EdgeInsets.only(bottom: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildProfileCard(),
                    _buildStatsRow(),
                    _buildBadgesSection(),
                    _buildXpCard(),
                    _buildFriendsSection(),
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
        border: Border(
          bottom: BorderSide(color: Color(0xFFE8EAF8), width: 0.5),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Back button
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
                  child: Icon(
                    Icons.chevron_left_rounded,
                    size: 22,
                    color: WW.textSec,
                  ),
                ),
              ),
            ),
          ),
          // Title
          const Text(
            'Profile',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: WW.primaryDark,
            ),
          ),
          // Settings button
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: () => context.push(Routes.settings).then((_) => _loadProfile()),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: WW.elevated,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(
                  child: Icon(
                    Icons.settings_rounded,
                    size: 18,
                    color: WW.text,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Profile header card ───────────────────────────────────────────────────

  Widget _buildProfileCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      padding: const EdgeInsets.all(16),
      decoration: WW.cardDecoration,
      child: Column(
        children: [
          // Avatar with camera overlay
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: const BoxDecoration(
                  color: WW.primary,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: _isLoading
                      ? const SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : Text(
                          _initial,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: GestureDetector(
                  onTap: () => _snack('Photo upload coming soon'),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: WW.card,
                      shape: BoxShape.circle,
                      border: Border.all(color: WW.primary, width: 1.5),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.camera_alt_rounded,
                        size: 12,
                        color: WW.primary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Display name
          _isLoading
              ? const SizedBox(
                  height: 24,
                  width: 120,
                  child: LinearProgressIndicator(
                    color: WW.primary,
                    backgroundColor: WW.elevated,
                  ),
                )
              : Text(
                  _nameDisplay.isNotEmpty ? _nameDisplay : 'Athlete',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: WW.primaryDark,
                  ),
                ),
          const SizedBox(height: 2),
          // Username
          Text(
            _username,
            style: const TextStyle(fontSize: 14, color: WW.textSec),
          ),
          if (_hometown != null && _hometown!.isNotEmpty) ...[
            const SizedBox(height: 4),
            // Location
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.location_on_rounded, size: 12, color: WW.textSec),
                const SizedBox(width: 3),
                Text(
                  _hometown!,
                  style: const TextStyle(fontSize: 13, color: WW.textSec),
                ),
              ],
            ),
          ],
          if (_bio != null && _bio!.isNotEmpty) ...[
            const SizedBox(height: 8),
            // Bio
            Text(
              _bio!,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                color: WW.text,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Stats row ─────────────────────────────────────────────────────────────

  Widget _buildStatsRow() {
    const stats = [
      (Icons.fitness_center_rounded, '47', 'Sessions', WW.primary),
      (Icons.show_chart_rounded, '38.2', 'km', WW.teal),
      (Icons.local_fire_department_rounded, '7', 'Day streak', WW.teal),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        children: List.generate(stats.length, (i) {
          final s = stats[i];
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i < stats.length - 1 ? 8 : 0),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: WW.elevated,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Icon(s.$1, size: 16, color: s.$4),
                    const SizedBox(height: 4),
                    Text(
                      s.$2,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: WW.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      s.$3,
                      style: const TextStyle(fontSize: 11, color: WW.textSec),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ── Badges section ────────────────────────────────────────────────────────

  Widget _buildBadgesSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Badges',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: WW.text,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => _snack('Badges coming soon'),
                child: const Text(
                  'View all',
                  style: TextStyle(fontSize: 13, color: WW.primary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _kBadges.map((b) {
                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Column(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: b.bgColor,
                          shape: BoxShape.circle,
                          border: b.locked
                              ? Border.all(color: WW.border, width: 1.5)
                              : null,
                        ),
                        child: Center(
                          child: Icon(
                            b.icon,
                            size: 22,
                            color: b.locked ? WW.border : Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: 56,
                        child: Text(
                          b.label,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 10,
                            color: b.locked ? WW.border : WW.text,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // ── XP level card ─────────────────────────────────────────────────────────

  Widget _buildXpCard() {
    final progress = _xpProgress();
    final isMaxLevel = _level >= _kXpThresholds.length;
    final nextLevelXp = isMaxLevel ? 0 : _kXpThresholds[_level];
    final xpToNext = isMaxLevel ? 0 : nextLevelXp - _totalXp;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(12),
      decoration: WW.cardDecoration,
      child: Row(
        children: [
          Text(
            'Lv.$_level',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: WW.primaryDark,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _levelName(_level),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: WW.text,
                  ),
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: WW.chipBg,
                    valueColor: const AlwaysStoppedAnimation<Color>(WW.primary),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isMaxLevel
                      ? '$_totalXp XP · Max Level'
                      : '$_totalXp / $nextLevelXp XP · $xpToNext to Level ${_level + 1}',
                  style: const TextStyle(fontSize: 11, color: WW.textSec),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Friends section ───────────────────────────────────────────────────────

  Widget _buildFriendsSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Friends',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: WW.text,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => _snack('Add friends coming soon'),
                child: const Text(
                  'Add friends',
                  style: TextStyle(fontSize: 13, color: WW.primary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Friend count
          Row(
            children: const [
              Icon(Icons.people_rounded, size: 14, color: WW.textSec),
              SizedBox(width: 6),
              Text(
                '8 friends',
                style: TextStyle(fontSize: 13, color: WW.textSec),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Friend rows
          ..._kFriends.map((f) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: WW.cardDecoration,
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: f.color,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          f.initial,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            f.name,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: WW.text,
                            ),
                          ),
                          Text(
                            '${f.username} · Level ${f.level}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: WW.textSec,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${f.xp} XP',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: WW.primary,
                          ),
                        ),
                        const Text(
                          'this week',
                          style: TextStyle(fontSize: 10, color: WW.textSec),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
          // See all link
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => _snack('Friends coming soon'),
            child: const Center(
              child: Text(
                'See all friends →',
                style: TextStyle(fontSize: 13, color: WW.primary),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
