// lib/screens/club/challenge_leaderboard_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';

// Flat rank list for a single challenge — reads getChallengeLeaderboard()
// (progressCache joined with publicProfiles), not raw sessions, matching
// the security/architecture decision made earlier. Full-bleed: the list
// sits directly on WW.bg, no outer bordered/boxed container — each row
// carries its own WW.card background + hairline divider, mirroring
// club_screen.dart's existing friends-leaderboard row style
// (_buildLeaderRow) for visual consistency with the rest of the app.
class ChallengeLeaderboardScreen extends StatefulWidget {
  final String challengeId;
  const ChallengeLeaderboardScreen({super.key, required this.challengeId});

  @override
  State<ChallengeLeaderboardScreen> createState() =>
      _ChallengeLeaderboardScreenState();
}

class _ChallengeLeaderboardScreenState
    extends State<ChallengeLeaderboardScreen> {
  final _firestoreService = FirestoreService();
  final _authService = AuthService();

  Map<String, dynamic>? _challenge;
  List<Map<String, dynamic>> _entries = [];
  bool _isLoading = true;

  static const _kDivider = Color(0xFFE8EAF8);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!_isLoading) setState(() => _isLoading = true);
    final challenge = await _firestoreService.getChallenge(widget.challengeId);
    if (challenge == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    final participantUids =
        (challenge['participantUids'] as List?)?.cast<String>() ?? [];
    final entries = await _firestoreService.getChallengeLeaderboard(
      widget.challengeId,
      participantUids,
    );
    if (mounted) {
      setState(() {
        _challenge = challenge;
        _entries = entries;
        _isLoading = false;
      });
    }
  }

  String _fmtValue(double value) {
    final unit = _challenge?['unit'] as String? ?? '';
    final str = value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(1);
    return '$str $unit';
  }

  @override
  Widget build(BuildContext context) {
    final myUid = _authService.getCurrentUser()?.uid ?? '';
    return Scaffold(
      backgroundColor: WW.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildBody(myUid)),
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
          Text(
            _challenge?['name'] as String? ?? 'Leaderboard',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: WW.primaryDark,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildBody(String myUid) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: WW.primary));
    }
    if (_challenge == null) {
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
    if (_entries.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No participants yet.',
            style: TextStyle(fontSize: 13, color: WW.textSec),
          ),
        ),
      );
    }
    return RefreshIndicator(
      color: WW.primary,
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: _entries.length,
        itemBuilder: (context, i) {
          final entry = _entries[i];
          final isMe = entry['uid'] == myUid;
          final name = entry['displayName'] as String? ?? 'User';
          final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
          final value = entry['value'] as double;
          final isLast = i == _entries.length - 1;
          final rank = i + 1;
          return Container(
            decoration: BoxDecoration(
              color: WW.card,
              border: Border(
                left: BorderSide(
                  color: isMe ? WW.primary : Colors.transparent,
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
                        fontWeight: rank == 1 ? FontWeight.w800 : FontWeight.w700,
                        color: rank == 1 ? WW.text : WW.textSec,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
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
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isMe ? '$name (You)' : name,
                    style: WW.rowName.copyWith(
                      fontWeight: isMe ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                ),
                Text(_fmtValue(value), style: WW.rowStat),
              ],
            ),
          );
        },
      ),
    );
  }
}
