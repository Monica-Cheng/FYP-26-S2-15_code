// lib/screens/club/challenge_detail_screen.dart
// Detail view for a single group challenge: the user's progress toward the
// goal, challenge stats, a link to the leaderboard, and (for private
// challenges) an invite-friends option.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../core/router.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';

// Clean typographic stat block (not a photo-hero) for a single challenge —
// big "X / Goal unit" headline, Total [metric]/Duration/Participants rows,
// a "View Leaderboard" row pushing ChallengeLeaderboardScreen, and (private
// challenges the user participates in only) an "Invite Friends" button.
// Full-bleed: no outer bordered/boxed container around the stat block —
// just the screen's WW.bg background with internal padding; only the
// squircle badge and the invite-friends bottom sheet's row list carry
// their own individual card/row backgrounds, matching this app's existing
// per-item (not per-section) elevation convention.
class ChallengeDetailScreen extends StatefulWidget {
  final String challengeId;
  const ChallengeDetailScreen({super.key, required this.challengeId});

  @override
  State<ChallengeDetailScreen> createState() => _ChallengeDetailScreenState();
}

class _ChallengeDetailScreenState extends State<ChallengeDetailScreen> {
  final _firestoreService = FirestoreService();
  final _authService = AuthService();

  Map<String, dynamic>? _challenge;
  double _myProgress = 0;
  bool _isLoading = true;

  static const _kDivider = Color(0xFFE8EAF8);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = _authService.getCurrentUser()?.uid;
    if (uid == null) {
      setState(() => _isLoading = false);
      return;
    }
    final challenge = await _firestoreService.getChallenge(widget.challengeId);
    if (challenge == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    final progress = await _firestoreService.computeChallengeProgress(uid, challenge);
    if (mounted) {
      setState(() {
        _challenge = challenge;
        _myProgress = progress;
        _isLoading = false;
      });
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

  String _metricLabel(String metricType) {
    switch (metricType) {
      case 'distance':
        return 'Distance';
      case 'calories':
        return 'Calories';
      case 'duration':
        return 'Duration';
      default:
        return 'Progress';
    }
  }

  Color _categoryColor(String metricType) {
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

  // Reads a Firestore Timestamp's .toDate() without importing
  // cloud_firestore in this screen file (AGENT.md rule 3 — Firestore
  // types stay behind lib/services/). Duck-typed via dynamic dispatch:
  // works for any object exposing .toDate(), null on anything else.
  DateTime? _asDateTime(dynamic value) {
    try {
      return (value as dynamic).toDate() as DateTime;
    } catch (_) {
      return null;
    }
  }

  String _fmtNum(double value) {
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(1);
  }

  String _badgeLabel(Map<String, dynamic> challenge) {
    final unit = challenge['unit'] as String? ?? '';
    final goalValue = (challenge['goalValue'] as num?)?.toDouble() ?? 0;
    final valueStr = _fmtNum(goalValue);
    switch (unit) {
      case 'km':
        return '${valueStr}K';
      default:
        return '$valueStr$unit';
    }
  }

  void _showInviteSheet() {
    final challenge = _challenge;
    if (challenge == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: WW.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return _InviteFriendsSheet(
          challengeId: widget.challengeId,
          challengeName: challenge['name'] as String? ?? 'this challenge',
          participantUids:
              (challenge['participantUids'] as List?)?.cast<String>() ?? [],
          invitedUids: (challenge['invitedUids'] as List?)?.cast<String>() ?? [],
          firestoreService: _firestoreService,
          authService: _authService,
          onInvited: () {
            _snack('Invites sent');
            _load();
          },
        );
      },
    );
  }

  // Same AlertDialog shape as plan_detail_screen.dart's own delete
  // confirmation (WW.card background, 16-radius, Cancel/destructive-red
  // TextButton pair) — the established confirm-dialog style in this app.
  Future<void> _confirmDeleteChallenge() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: WW.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete this challenge?',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: WW.text),
        ),
        content: const Text(
          'This removes it for everyone who joined.',
          style: TextStyle(fontSize: 14, color: WW.textSec),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: WW.textSec)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    try {
      await _firestoreService.deleteChallenge(widget.challengeId);
    } catch (_) {
      if (mounted) _snack('Failed to delete challenge. Please try again.');
      return;
    }
    if (!mounted) return;
    _snack('Challenge deleted');
    // Same short delay plan_detail_screen.dart's own delete flow uses
    // between showing a SnackBar and popping — popping immediately tears
    // the route down before the SnackBar has actually rendered, so it
    // would never be visible at all.
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    context.pop();
  }

  Future<void> _confirmLeaveChallenge() async {
    final uid = _authService.getCurrentUser()?.uid;
    if (uid == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: WW.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Leave this challenge?',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: WW.text),
        ),
        content: const Text(
          "You'll be removed from this challenge and its leaderboard.",
          style: TextStyle(fontSize: 14, color: WW.textSec),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: WW.textSec)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Leave',
              style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    try {
      await _firestoreService.leaveChallenge(widget.challengeId, uid);
    } catch (_) {
      if (mounted) _snack('Failed to leave challenge. Please try again.');
      return;
    }
    if (!mounted) return;
    _snack('Left challenge');
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WW.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
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
                  child: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    size: 16,
                    color: WW.textSec,
                  ),
                ),
              ),
            ),
          ),
          const Text(
            'Challenge',
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

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: WW.primary));
    }
    final challenge = _challenge;
    if (challenge == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Challenge not found.',
            style: TextStyle(fontSize: 13, color: WW.textSec),
          ),
        ),
      );
    }

    final uid = _authService.getCurrentUser()?.uid ?? '';
    final name = challenge['name'] as String? ?? 'Challenge';
    final unit = challenge['unit'] as String? ?? '';
    final metricType = challenge['metricType'] as String? ?? 'distance';
    final goalValue = (challenge['goalValue'] as num?)?.toDouble() ?? 0;
    final color = _categoryColor(metricType);
    final participantUids =
        (challenge['participantUids'] as List?)?.cast<String>() ?? [];
    final isParticipant = participantUids.contains(uid);
    final isCreator = challenge['createdBy'] == uid;

    final startDate = _asDateTime(challenge['startDate']);
    final endDate = _asDateTime(challenge['endDate']);
    String durationLabel = '—';
    if (startDate != null && endDate != null) {
      final days = endDate.difference(startDate).inDays;
      durationLabel = '$days day${days == 1 ? '' : 's'}';
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Text(
                    _badgeLabel(challenge),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: WW.primaryDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: _fmtNum(_myProgress),
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    color: WW.text,
                  ),
                ),
                TextSpan(
                  text: ' / ${_fmtNum(goalValue)} $unit',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: WW.textSec,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: goalValue > 0 ? (_myProgress / goalValue).clamp(0, 1) : 0,
              minHeight: 8,
              backgroundColor: WW.elevated,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 24),
          _statRow('Total ${_metricLabel(metricType)}', '${_fmtNum(_myProgress)} $unit'),
          _statRow('Duration', durationLabel),
          _statRow('Participants', '${participantUids.length}'),
          const SizedBox(height: 8),
          _navRow(
            icon: Icons.leaderboard_rounded,
            label: 'View Leaderboard',
            onTap: () => context.push(
              Routes.challengeLeaderboard,
              extra: {'challengeId': widget.challengeId},
            ),
          ),
          // Was `!isGlobal && isParticipant` — Invite Friends only ever
          // makes sense for a private challenge, but that's already
          // guaranteed by `isCreator` below (a regular user is never the
          // creator of an isGlobal:true challenge — those are always
          // createdBy:adminUid), so dropping !isGlobal here doesn't change
          // Invite Friends' visibility. It DOES matter for Leave Challenge
          // below, which — per spec — must be offered for both private and
          // global challenges, not just private ones.
          if (isParticipant) ...[
            const SizedBox(height: 24),
            if (isCreator) ...[
              GestureDetector(
                onTap: _showInviteSheet,
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: WW.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.person_add_rounded, color: Colors.white, size: 18),
                        SizedBox(width: 8),
                        Text(
                          'Invite Friends',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: _confirmDeleteChallenge,
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFEF4444), width: 1),
                  ),
                  child: const Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.delete_outline_rounded,
                            color: Color(0xFFEF4444), size: 18),
                        SizedBox(width: 8),
                        Text(
                          'Delete Challenge',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFEF4444),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ] else
              GestureDetector(
                onTap: _confirmLeaveChallenge,
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFEF4444), width: 1),
                  ),
                  child: const Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.logout_rounded, color: Color(0xFFEF4444), size: 18),
                        SizedBox(width: 8),
                        Text(
                          'Leave Challenge',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFEF4444),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _statRow(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _kDivider, width: 0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 14, color: WW.textSec)),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: WW.text,
            ),
          ),
        ],
      ),
    );
  }

  Widget _navRow({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 18, color: WW.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: WW.text,
                ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 20, color: WW.textSec),
          ],
        ),
      ),
    );
  }
}

// Bottom sheet for inviting more friends to an already-existing challenge —
// visually mirrors create_challenge_screen.dart's friend-invite list
// (avatar + name/username + trailing selector), extended with an
// already-related state (Joined/Invited label instead of a checkbox) since
// unlike a brand-new challenge, this challenge may already have
// participants/pending invites among the current user's friends. Logic is
// fully shared, not duplicated: submission calls the same
// FirestoreService.inviteFriendsToChallenge() that writes through
// _writeChallengeInviteNotifications() — the exact notification shape
// createChallenge() itself uses.
class _InviteFriendsSheet extends StatefulWidget {
  final String challengeId;
  final String challengeName;
  final List<String> participantUids;
  final List<String> invitedUids;
  final FirestoreService firestoreService;
  final AuthService authService;
  final VoidCallback onInvited;

  const _InviteFriendsSheet({
    required this.challengeId,
    required this.challengeName,
    required this.participantUids,
    required this.invitedUids,
    required this.firestoreService,
    required this.authService,
    required this.onInvited,
  });

  @override
  State<_InviteFriendsSheet> createState() => _InviteFriendsSheetState();
}

class _InviteFriendsSheetState extends State<_InviteFriendsSheet> {
  List<Map<String, dynamic>> _friends = [];
  bool _isLoadingFriends = true;
  bool _isSending = false;
  final Set<String> _selectedUids = {};

  static const _kDivider = Color(0xFFE8EAF8);

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    final uid = widget.authService.getCurrentUser()?.uid;
    if (uid == null) {
      setState(() => _isLoadingFriends = false);
      return;
    }
    final friends = await widget.firestoreService.getFriendsStream(uid).first;
    if (mounted) {
      setState(() {
        _friends = friends;
        _isLoadingFriends = false;
      });
    }
  }

  Future<void> _send() async {
    final uid = widget.authService.getCurrentUser()?.uid;
    if (uid == null || _selectedUids.isEmpty || _isSending) return;
    setState(() => _isSending = true);
    try {
      await widget.firestoreService.inviteFriendsToChallenge(
        uid,
        widget.challengeId,
        widget.challengeName,
        _selectedUids.toList(),
      );
      if (mounted) {
        Navigator.pop(context);
        widget.onInvited();
      }
    } catch (_) {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.7,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 14),
              decoration: BoxDecoration(
                color: WW.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 0, 18, 12),
            child: Text(
              'Invite Friends',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: WW.primaryDark,
              ),
            ),
          ),
          Expanded(child: _buildList()),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
            child: GestureDetector(
              onTap: _selectedUids.isEmpty ? null : _send,
              child: Container(
                height: 46,
                decoration: BoxDecoration(
                  color: _selectedUids.isEmpty ? WW.border : WW.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: _isSending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : Text(
                          _selectedUids.isEmpty
                              ? 'Select friends to invite'
                              : 'Send ${_selectedUids.length} Invite${_selectedUids.length == 1 ? '' : 's'}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_isLoadingFriends) {
      return const Center(child: CircularProgressIndicator(color: WW.primary));
    }
    if (_friends.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No friends to invite yet.',
            style: TextStyle(fontSize: 13, color: WW.textSec),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
      itemCount: _friends.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, color: _kDivider),
      itemBuilder: (context, i) {
        final f = _friends[i];
        final uid = f['uid'] as String? ?? f['id'] as String? ?? '';
        final name = f['displayName'] as String? ?? 'Friend';
        final username = f['username'] as String? ?? '';
        final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
        final isParticipant = widget.participantUids.contains(uid);
        final isInvited = widget.invitedUids.contains(uid);
        final selected = _selectedUids.contains(uid);

        Widget trailing;
        if (isParticipant) {
          trailing = const Text(
            'Joined',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: WW.textSec),
          );
        } else if (isInvited) {
          trailing = const Text(
            'Invited',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: WW.textSec),
          );
        } else {
          trailing = Icon(
            selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
            color: selected ? WW.primary : WW.border,
            size: 22,
          );
        }

        return GestureDetector(
          onTap: (isParticipant || isInvited)
              ? null
              : () {
                  setState(() {
                    if (selected) {
                      _selectedUids.remove(uid);
                    } else {
                      _selectedUids.add(uid);
                    }
                  });
                },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(color: WW.elevated, shape: BoxShape.circle),
                  child: Center(
                    child: Text(
                      initial,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: WW.text),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: WW.rowName),
                      const SizedBox(height: 2),
                      Text(username.isNotEmpty ? '@$username' : '—', style: WW.rowSecondary),
                    ],
                  ),
                ),
                trailing,
              ],
            ),
          ),
        );
      },
    );
  }
}
