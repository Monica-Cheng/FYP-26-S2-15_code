// lib/screens/profile/profile_screen.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/app_theme.dart';
import '../../core/router.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../utils/image_encode.dart';
import '../../widgets/quick_add_sheet.dart';

// ── Data classes ──────────────────────────────────────────────────────────────

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
  String? _storedUsername;
  String? _hometown;
  String? _bio;
  String? _photoBase64;
  bool _isLoading = true;
  bool _isUploadingPhoto = false;
  int _totalXp = 0;
  int _level = 1;

  int _sessionCount = 0;
  double _totalVolume = 0;
  int _streak = 0;
  bool _statsLoading = true;

  List<Map<String, dynamic>> _allBadges = [];
  Set<String> _earnedBadgeIds = {};
  bool _badgesLoading = true;

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
    _loadStats();
    _loadBadges();
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
          _storedUsername = profile?['username'] as String?;
          _hometown = profile?['hometown'] as String?;
          _bio = profile?['bio'] as String?;
          _photoBase64 = profile?['photoBase64'] as String?;
          _totalXp = (profile?['totalXp'] as num?)?.toInt() ?? 0;
          _level = (profile?['level'] as num?)?.toInt() ?? 1;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadStats() async {
    final uid = _auth.getCurrentUser()?.uid;
    if (uid == null) {
      if (mounted) setState(() => _statsLoading = false);
      return;
    }
    try {
      final stats = await _firestore.getLifetimeStats(uid);
      final streak = await _firestore.calculateStreak(uid);
      if (mounted) {
        setState(() {
          _sessionCount = stats['sessionCount'] as int? ?? 0;
          _totalVolume = (stats['totalVolume'] as num?)?.toDouble() ?? 0;
          _streak = streak;
          _statsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _statsLoading = false);
    }
  }

  Future<void> _loadBadges() async {
    final uid = _auth.getCurrentUser()?.uid;
    if (uid == null) {
      if (mounted) setState(() => _badgesLoading = false);
      return;
    }
    try {
      final badges = await _firestore.getBadgeDefinitions();
      final earnedIds = await _firestore.getEarnedBadgeIds(uid);
      if (mounted) {
        setState(() {
          _allBadges = badges;
          _earnedBadgeIds = earnedIds;
          _badgesLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _badgesLoading = false);
    }
  }

  // ── Profile photo upload ──────────────────────────────────────────────────
  // Take Photo / Choose from Gallery — same showQuickAddSheet chooser
  // pattern already used elsewhere in the app (e.g.
  // post_session_summary_screen.dart's card-flow photo step), just with
  // no "Skip" option here since tapping the avatar is already an
  // explicit "change my photo" action, not an optional attach-during-flow.

  Future<void> _promptChangePhoto() async {
    if (_isUploadingPhoto) return;
    await showQuickAddSheet(context, [
      QuickAddOption(
        icon: Icons.camera_alt_rounded,
        iconColor: WW.primary,
        iconBg: WW.chipBg,
        title: 'Take Photo',
        subtitle: 'Use your camera',
        onTap: () => _pickAndUploadPhoto(ImageSource.camera),
      ),
      QuickAddOption(
        icon: Icons.photo_library_rounded,
        iconColor: WW.teal,
        iconBg: WW.tealBg,
        title: 'Choose from Gallery',
        subtitle: 'Pick an existing photo',
        onTap: () => _pickAndUploadPhoto(ImageSource.gallery),
      ),
    ]);
  }

  Future<void> _pickAndUploadPhoto(ImageSource source) async {
    final uid = _auth.getCurrentUser()?.uid;
    if (uid == null) return;
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1024,
      imageQuality: 80,
    );
    if (picked == null) return;

    setState(() => _isUploadingPhoto = true);
    try {
      // Downscaled well below feed-photo size (480px) — this is read on
      // every avatar render across the app, not a one-off post image, so
      // it's kept as small as still looks sharp in a ~80px circle.
      final encoded = await encodeImageBase64(File(picked.path), targetWidth: 200);
      if (encoded == null) {
        if (mounted) _snack('Could not process that photo. Try another.');
        return;
      }
      await _firestore.updateUserProfile(uid, {'photoBase64': encoded});
      if (!mounted) return;
      setState(() => _photoBase64 = encoded);
    } catch (e) {
      if (mounted) _snack('Could not save photo: $e');
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  Widget _buildAvatarContent() {
    if (_isLoading) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
        ),
      );
    }
    final photo = _photoBase64;
    if (photo != null && photo.isNotEmpty) {
      try {
        return Image.memory(
          base64Decode(photo),
          width: 80,
          height: 80,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildInitialAvatar(),
        );
      } catch (_) {
        return _buildInitialAvatar();
      }
    }
    return _buildInitialAvatar();
  }

  Widget _buildInitialAvatar() {
    return Center(
      child: Text(
        _initial,
        style: const TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
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
  String get _username {
    final stored = _storedUsername;
    if (stored != null && stored.isNotEmpty) {
      return stored.startsWith('@') ? stored : '@$stored';
    }
    return '@${_nameDisplay.toLowerCase().replaceAll(' ', '')}';
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
          // Avatar with camera overlay — shows the real uploaded photo
          // when present, falling back to the initials circle otherwise.
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
                child: ClipOval(child: _buildAvatarContent()),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: GestureDetector(
                  onTap: _isUploadingPhoto ? null : _promptChangePhoto,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: WW.card,
                      shape: BoxShape.circle,
                      border: Border.all(color: WW.primary, width: 1.5),
                    ),
                    child: Center(
                      child: _isUploadingPhoto
                          ? const SizedBox(
                              width: 10,
                              height: 10,
                              child: CircularProgressIndicator(
                                color: WW.primary,
                                strokeWidth: 1.5,
                              ),
                            )
                          : const Icon(
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
    final stats = [
      (Icons.fitness_center_rounded, '$_sessionCount', 'Sessions', WW.primary),
      (Icons.show_chart_rounded, _totalVolume.toStringAsFixed(0), 'kg', WW.teal),
      (Icons.local_fire_department_rounded, '$_streak', 'Day streak', WW.teal),
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
                    _statsLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              color: WW.primary,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
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

  // ── Badges section — real, from getBadgeDefinitions()/
  // getEarnedBadgeIds() (see _loadBadges()). Shows every defined badge in
  // an equal-square grid, earned ones in full color, locked ones dimmed/
  // greyscale with a lock overlay. Tapping any badge — earned or locked —
  // opens a detail sheet with its name/description/conditions. ───────────

  Widget _buildBadgesSection() {
    if (_badgesLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator(color: WW.primary)),
      );
    }
    if (_allBadges.isEmpty) {
      // No badges configured by the admin yet — nothing to show, not an
      // empty card.
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Badges',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: WW.text,
            ),
          ),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 14,
              crossAxisSpacing: 10,
              childAspectRatio: 0.78,
            ),
            itemCount: _allBadges.length,
            itemBuilder: (context, i) {
              final badge = _allBadges[i];
              final earned = _earnedBadgeIds.contains(badge['id'] as String);
              return GestureDetector(
                onTap: () => _showBadgeDetail(badge, earned),
                child: _buildBadgeTile(badge, earned),
              );
            },
          ),
        ],
      ),
    );
  }

  // Locked badges: dimmed (reduced opacity) AND greyscale (a standard
  // luminance-preserving color matrix) together, matching "dimmed/
  // greyscale" — either alone read as too subtle a distinction from an
  // earned badge at this tile size.
  Widget _buildBadgeImage(String imageUrl, double size, bool earned) {
    final image = Image.network(
      imageUrl,
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Icon(
        Icons.emoji_events_rounded,
        size: size * 0.4,
        color: earned ? WW.primary : WW.border,
      ),
    );
    if (earned) return image;
    return Opacity(
      opacity: 0.35,
      child: ColorFiltered(
        colorFilter: const ColorFilter.matrix(<double>[
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0, 0, 0, 1, 0,
        ]),
        child: image,
      ),
    );
  }

  Widget _buildBadgeTile(Map<String, dynamic> badge, bool earned, {double size = 56}) {
    final imageUrl = badge['imageUrl'] as String? ?? '';
    final name = badge['name'] as String? ?? '';
    // TEMPORARY — remove once the real imageUrl value is confirmed (see
    // this session's Phase 2 investigation into badge images not rendering).
    if (imageUrl.isNotEmpty) {
      print('DEBUG_BADGE: badge "${badge['id']}" ($name) imageUrl = $imageUrl');
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: earned ? WW.chipBg : _kLockedBg,
            borderRadius: BorderRadius.circular(size * 0.28),
            border: earned ? null : Border.all(color: WW.border, width: 1.5),
          ),
          clipBehavior: Clip.hardEdge,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (imageUrl.isNotEmpty)
                _buildBadgeImage(imageUrl, size, earned)
              else
                Icon(
                  Icons.emoji_events_rounded,
                  size: size * 0.4,
                  color: earned ? WW.primary : WW.border,
                ),
              if (!earned)
                Container(
                  decoration: const BoxDecoration(
                    color: Colors.black26,
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.lock_rounded, size: size * 0.28, color: Colors.white),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: size,
          child: Text(
            name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              color: earned ? WW.text : WW.border,
              height: 1.2,
            ),
          ),
        ),
      ],
    );
  }

  // Plain-language phrasing for one condition — e.g. {statType: 'level',
  // value: 5} -> "reach level 5". Used by _describeConditions() below,
  // joined into a single readable sentence rather than shown as raw
  // statType/value pairs.
  String _describeCondition(Map<String, dynamic> cond) {
    final statType = cond['statType'] as String? ?? '';
    final rawValue = cond['value'];
    if (rawValue is! num) return 'meet a special condition';
    String fmt(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();
    switch (statType) {
      case 'level':
        return 'reach level ${fmt(rawValue)}';
      case 'totalXp':
        return 'earn ${fmt(rawValue)} total XP';
      case 'sessionCount':
        return 'complete ${fmt(rawValue)} session${rawValue == 1 ? '' : 's'}';
      case 'totalVolume':
        return 'lift ${fmt(rawValue)} kg total volume';
      case 'totalDistance':
        // Badge conditions store distance in the same unit as
        // computeChallengeProgress()'s 'km'-converted output — see
        // checkAndAwardBadges()'s totalDistance stat, which reads
        // getLifetimeStats()'s totalDistanceMeters and is compared
        // directly against this condition's raw value, so this value is
        // already in km, not meters, for a readable admin-facing number.
        return 'cover ${fmt(rawValue)} km total distance';
      case 'streak':
        return 'reach a ${fmt(rawValue)}-day streak';
      default:
        return 'meet a special condition';
    }
  }

  String _describeConditions(List<dynamic> conditions) {
    final parts = conditions
        .whereType<Map>()
        .map((c) => _describeCondition(Map<String, dynamic>.from(c)))
        .toList();
    if (parts.isEmpty) return 'No conditions set';
    final joined = parts.length == 1
        ? parts.first
        : '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';
    return joined[0].toUpperCase() + joined.substring(1);
  }

  void _showBadgeDetail(Map<String, dynamic> badge, bool earned) {
    final name = badge['name'] as String? ?? 'Badge';
    final description = badge['description'] as String? ?? '';
    final conditions = (badge['conditions'] as List?) ?? const [];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: WW.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildBadgeTile(badge, earned, size: 72),
              const SizedBox(height: 16),
              Text(
                name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: WW.primaryDark,
                ),
              ),
              if (description.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  description,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: WW.textSec),
                ),
              ],
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: WW.elevated,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      earned ? Icons.check_circle_rounded : Icons.flag_rounded,
                      color: earned ? WW.teal : WW.textSec,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        earned ? 'Unlocked!' : _describeConditions(conditions),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: WW.text,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
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
