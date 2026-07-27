// lib/screens/profile/user_profile_screen.dart
// Read-only profile view for a user OTHER than the current one — tapped
// into from a feed post's avatar/name (see feed_post_card.dart). Shows
// their name/avatar, a Follow/Unfollow button, and their recent feed posts.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../widgets/feed_post_card.dart';

class UserProfileScreen extends StatefulWidget {
  final String uid;
  final String? initialName;

  const UserProfileScreen({
    super.key,
    required this.uid,
    this.initialName,
  });

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final _authService = AuthService();
  final _firestoreService = FirestoreService();

  String? _displayName;
  bool _isLoading = true;
  String _myName = 'You';

  int _followerCount = 0;
  int _followingCount = 0;
  bool _countsLoading = true;

  @override
  void initState() {
    super.initState();
    _displayName = widget.initialName;
    _loadProfile();
    _loadMyName();
    _loadCounts();
  }

  Future<void> _loadCounts() async {
    try {
      final results = await Future.wait([
        _firestoreService.getFollowerCount(widget.uid),
        _firestoreService.getFollowingCount(widget.uid),
      ]);
      if (mounted) {
        setState(() {
          _followerCount = results[0];
          _followingCount = results[1];
          _countsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _countsLoading = false);
    }
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await _firestoreService.getUserProfile(widget.uid);
      final name = profile?['displayName'] as String?;
      if (mounted) {
        setState(() {
          if (name != null && name.isNotEmpty) _displayName = name;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMyName() async {
    final uid = _authService.getCurrentUser()?.uid;
    if (uid == null) return;
    final profile = await _firestoreService.getUserProfile(uid);
    final name = profile?['displayName'] as String?;
    if (mounted && name != null && name.isNotEmpty) {
      setState(() => _myName = name);
    }
  }

  String get _nameDisplay =>
      (_displayName != null && _displayName!.isNotEmpty) ? _displayName! : 'Athlete';
  String get _initial =>
      _nameDisplay.trim().isNotEmpty ? _nameDisplay.trim()[0].toUpperCase() : '?';

  @override
  Widget build(BuildContext context) {
    final currentUid = _authService.getCurrentUser()?.uid ?? '';
    final isOwnProfile = currentUid.isNotEmpty && currentUid == widget.uid;

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
                    _buildProfileHeader(isOwnProfile, currentUid),
                    const SizedBox(height: 8),
                    _buildPostsSection(currentUid),
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
          Text(
            _nameDisplay,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: WW.primaryDark,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ── Profile header ───────────────────────────────────────────────────────

  Widget _buildProfileHeader(bool isOwnProfile, String currentUid) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: WW.cardDecoration,
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              color: WW.primary,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: _isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : Text(
                      _initial,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _nameDisplay,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: WW.primaryDark,
            ),
          ),
          const SizedBox(height: 8),
          _buildFollowCounts(),
          if (!isOwnProfile) ...[
            const SizedBox(height: 14),
            _buildFollowButton(currentUid),
          ],
        ],
      ),
    );
  }

  Widget _buildFollowCounts() {
    if (_countsLoading) {
      return const SizedBox(
        height: 18,
        width: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: WW.textSec),
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _followStat(_followerCount, 'Followers'),
        const SizedBox(width: 18),
        _followStat(_followingCount, 'Following'),
      ],
    );
  }

  Widget _followStat(int count, String label) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$count ',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: WW.primaryDark,
            ),
          ),
          TextSpan(
            text: label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: WW.textSec,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFollowButton(String currentUid) {
    if (currentUid.isEmpty) return const SizedBox.shrink();
    return StreamBuilder<bool>(
      stream: _firestoreService.isFollowingStream(currentUid, widget.uid),
      builder: (context, snapshot) {
        final isFollowing = snapshot.data ?? false;
        return GestureDetector(
          onTap: () async {
            if (isFollowing) {
              await _firestoreService.unfollowUser(currentUid, widget.uid);
            } else {
              await _firestoreService.followUser(currentUid, widget.uid);
            }
            if (mounted) _loadCounts();
          },
          child: Container(
            width: double.infinity,
            height: 44,
            decoration: BoxDecoration(
              color: isFollowing ? WW.elevated : WW.primary,
              borderRadius: BorderRadius.circular(12),
              border: isFollowing ? Border.all(color: WW.border, width: 1) : null,
            ),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isFollowing ? Icons.check_rounded : Icons.person_add_rounded,
                    size: 16,
                    color: isFollowing ? WW.text : Colors.white,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isFollowing ? 'Following' : 'Follow',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isFollowing ? WW.text : Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Posts section ────────────────────────────────────────────────────────

  Widget _buildPostsSection(String currentUid) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'POSTS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: WW.textSec,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 10),
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: _firestoreService.getUserPostsStream(widget.uid),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: CircularProgressIndicator(color: WW.primary),
                  ),
                );
              }
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    'Could not load posts. ${snapshot.error}',
                    style: WW.labelMed,
                    textAlign: TextAlign.center,
                  ),
                );
              }

              final posts = snapshot.data ?? [];
              if (posts.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.dynamic_feed_rounded, size: 36, color: WW.textSec),
                        SizedBox(height: 10),
                        Text('No posts yet', style: WW.labelMed),
                      ],
                    ),
                  ),
                );
              }

              return Column(
                children: posts
                    .map((post) => FeedPostCard(
                          post: post,
                          currentUid: currentUid,
                          currentUserName: _myName,
                          firestoreService: _firestoreService,
                        ))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
