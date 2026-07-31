// lib/widgets/feed_post_card.dart
// A single post in the Club "Feed" tab — avatar/name/timestamp header,
// optional food photo, a calorie/macro stat row, and a react + comment bar.
// Reactions and comments are real (Firestore), not mock data.

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/app_theme.dart';
import '../core/router.dart';
import '../services/firestore_service.dart';

class FeedPostCard extends StatelessWidget {
  final Map<String, dynamic> post;
  final String currentUid;
  final String currentUserName;
  final FirestoreService firestoreService;

  const FeedPostCard({
    super.key,
    required this.post,
    required this.currentUid,
    required this.currentUserName,
    required this.firestoreService,
  });

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  String _fmtDuration(int? secs) {
    if (secs == null) return '--';
    final h = secs ~/ 3600;
    final m = (secs % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    if (m == 0) return '<1m';
    return '${m}m';
  }

  String _fmtVolume(double? v) {
    if (v == null) return '0';
    final n = v.round();
    if (n >= 1000) {
      return '${n ~/ 1000},${(n % 1000).toString().padLeft(3, '0')}';
    }
    return '$n';
  }

  // Real photo when the poster has one (authorPhotoBase64, denormalized
  // onto the post the same way authorName/authorInitial already are —
  // see createFeedPost()), falling back to the initials circle
  // otherwise. Scoped to just this header for now — comment avatars and
  // every other initials-circle elsewhere in the app (leaderboard,
  // friend rows, etc.) still use initials only; updating those is a
  // separate, larger follow-up, not part of this pass.
  Widget _buildAvatar(String? photoBase64, String initial) {
    if (photoBase64 != null && photoBase64.isNotEmpty) {
      try {
        return CircleAvatar(
          radius: 18,
          backgroundColor: WW.primary,
          backgroundImage: MemoryImage(base64Decode(photoBase64)),
        );
      } catch (_) {
        // Falls through to the initials circle below.
      }
    }
    return CircleAvatar(
      radius: 18,
      backgroundColor: WW.primary,
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
      ),
    );
  }

  void _openProfile(BuildContext context) {
    final uid = post['uid'] as String?;
    if (uid == null || uid.isEmpty) return;
    context.push(
      Routes.userProfile,
      extra: {
        'uid': uid,
        'authorName': post['authorName'] as String?,
      },
    );
  }

  void _openComments(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _CommentsSheet(
        postId: post['id'] as String,
        currentUid: currentUid,
        currentUserName: currentUserName,
        firestoreService: firestoreService,
      ),
    );
  }

  void _showPostOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: WW.card,
              borderRadius: BorderRadius.circular(20),
              boxShadow: WW.shadow,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444)),
                  title: const Text(
                    'Delete Post',
                    style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFFEF4444)),
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    _confirmDeletePost(context);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDeletePost(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: WW.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Delete this post?',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: WW.text),
        ),
        content: const Text(
          "This can't be undone.",
          style: TextStyle(fontSize: 14, color: WW.textSec),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel',
                style: TextStyle(fontWeight: FontWeight.w700, color: WW.textSec)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete',
                style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFFEF4444))),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await firestoreService.deletePost(post['id'] as String);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete post: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final postId = post['id'] as String;
    final authorName = (post['authorName'] as String?) ?? 'Someone';
    final authorInitial = (post['authorInitial'] as String?) ?? '?';
    final authorPhotoBase64 = post['authorPhotoBase64'] as String?;
    final isWorkout = (post['type'] as String?) == 'workout';
    final foodName = (post['foodName'] as String?) ?? 'A meal';
    final calories = (post['calories'] as num?)?.toInt() ?? 0;
    final proteinG = (post['proteinG'] as num?)?.toInt();
    final carbsG = (post['carbsG'] as num?)?.toInt();
    final fatG = (post['fatG'] as num?)?.toInt();
    final sessionName = post['sessionName'] as String?;
    final isCardio = post['isCardio'] as bool?;
    final cardioActivity = post['cardioActivity'] as String?;
    final elapsedSeconds = (post['elapsedSeconds'] as num?)?.toInt();
    final totalSets = (post['totalSets'] as num?)?.toInt();
    final volume = (post['volume'] as num?)?.toDouble();
    final imageBase64 = post['imageBase64'] as String?;
    final caption = post['caption'] as String?;
    final reactionCount = (post['reactionCount'] as num?)?.toInt() ?? 0;
    final commentCount = (post['commentCount'] as num?)?.toInt() ?? 0;
    final createdAt = post['createdAt'];
    final createdDt = createdAt is Timestamp ? createdAt.toDate() : null;

    final titleText = caption?.isNotEmpty == true
        ? caption!
        : isWorkout
            ? ((sessionName?.isNotEmpty ?? false) ? sessionName! : 'Workout session')
            : foodName;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: WW.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 6, 10),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _openProfile(context),
                    child: Row(
                      children: [
                        _buildAvatar(authorPhotoBase64, authorInitial),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(authorName, style: WW.titleMed.copyWith(fontSize: 14)),
                              Text(
                                createdDt != null ? _timeAgo(createdDt) : '',
                                style: WW.caption,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (post['uid'] == currentUid)
                  IconButton(
                    onPressed: () => _showPostOptions(context),
                    icon: const Icon(Icons.more_horiz_rounded, color: WW.textSec, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),

          // Caption / food name / session name
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(
              titleText,
              style: WW.bodyMed.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 10),

          // Photo (if present)
          if (imageBase64 != null && imageBase64.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                // No hardcoded AspectRatio — post images come from two
                // sources with genuinely different shapes: share cards
                // are a fixed 9:16 (1080x1920 Story ratio), while a
                // scanned-food photo is whatever ratio the camera/
                // gallery photo actually was (_encodeImageForPost only
                // constrains width, not height, so it's never guaranteed
                // 4:3 either). A single fixed ratio can only ever be
                // right for one of these — sizing to width:infinity with
                // no explicit height lets Image size itself to the
                // decoded image's own natural aspect ratio instead.
                child: Image.memory(
                  base64Decode(imageBase64),
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 200,
                    color: WW.elevated,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 12),

          // Stat row — minimal 2-color treatment (WW.primary icons, WW.text
          // values, no background boxes) shared by meal and workout posts.
          // Wrap (not Row) so a long cardio activity name or a narrow phone
          // never overflows — it just wraps to a second line.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Wrap(
              spacing: 14,
              runSpacing: 6,
              children: isWorkout
                  ? (isCardio == true
                      ? [
                          _StatItem(icon: Icons.timer_outlined, text: _fmtDuration(elapsedSeconds)),
                          _StatItem(icon: Icons.local_fire_department_rounded, text: '$calories cal'),
                          _StatItem(icon: Icons.directions_run_rounded, text: (cardioActivity?.isNotEmpty ?? false) ? cardioActivity! : 'Cardio'),
                        ]
                      : [
                          _StatItem(icon: Icons.timer_outlined, text: _fmtDuration(elapsedSeconds)),
                          _StatItem(icon: Icons.local_fire_department_rounded, text: '$calories cal'),
                          _StatItem(icon: Icons.fitness_center_rounded, text: '${totalSets ?? 0} sets'),
                          _StatItem(icon: Icons.bar_chart_rounded, text: '${_fmtVolume(volume)} kg'),
                        ])
                  : [
                      _StatItem(icon: Icons.local_fire_department_rounded, text: '$calories cal'),
                      _StatItem(icon: Icons.egg_alt_rounded, text: '${proteinG ?? 0}g protein'),
                      _StatItem(icon: Icons.grain_rounded, text: '${carbsG ?? 0}g carbs'),
                      _StatItem(icon: Icons.water_drop_rounded, text: '${fatG ?? 0}g fat'),
                    ],
            ),
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: WW.border),

          // Reaction + comment bar
          StreamBuilder<bool>(
            stream: firestoreService.hasReactedStream(postId, currentUid),
            builder: (context, snapshot) {
              final hasReacted = snapshot.data ?? false;
              return Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () =>
                          firestoreService.toggleReaction(postId, currentUid),
                      icon: Icon(
                        Icons.local_fire_department_rounded,
                        size: 18,
                        color: hasReacted ? WW.gold : WW.textSec,
                      ),
                      label: Text(
                        reactionCount > 0 ? '$reactionCount' : 'React',
                        style: WW.labelMed.copyWith(
                          color: hasReacted ? WW.gold : WW.textSec,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  Container(width: 1, height: 20, color: WW.border),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => _openComments(context),
                      icon: const Icon(Icons.chat_bubble_outline_rounded,
                          size: 17, color: WW.textSec),
                      label: Text(
                        commentCount > 0 ? '$commentCount' : 'Comment',
                        style: WW.labelMed.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// Minimal 2-color stat treatment: WW.primary icon + WW.text value, no
// background box — replaces the old 4-differently-colored _StatPill boxes.
class _StatItem extends StatelessWidget {
  final IconData icon;
  final String text;

  const _StatItem({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: WW.primary),
        const SizedBox(width: 4),
        Text(
          text,
          style: WW.labelMed.copyWith(
            color: WW.text,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

// ── Comments sheet ─────────────────────────────────────────────────────────

class _CommentsSheet extends StatefulWidget {
  final String postId;
  final String currentUid;
  final String currentUserName;
  final FirestoreService firestoreService;

  const _CommentsSheet({
    required this.postId,
    required this.currentUid,
    required this.currentUserName,
    required this.firestoreService,
  });

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.firestoreService.addComment(
        widget.postId,
        uid: widget.currentUid,
        authorName: widget.currentUserName,
        text: text,
      );
      _controller.clear();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _confirmDeleteComment(String commentId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: WW.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Delete this comment?',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: WW.text),
        ),
        content: const Text(
          "This can't be undone.",
          style: TextStyle(fontSize: 14, color: WW.textSec),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel',
                style: TextStyle(fontWeight: FontWeight.w700, color: WW.textSec)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete',
                style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFFEF4444))),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.firestoreService.deleteComment(widget.postId, commentId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete comment: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.65,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: const BoxDecoration(
            color: WW.card,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: WW.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Comments', style: WW.titleLarge),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: widget.firestoreService.getCommentsStream(widget.postId),
                  builder: (context, snapshot) {
                    final comments = snapshot.data ?? [];
                    if (!snapshot.hasData) {
                      return const Center(
                        child: CircularProgressIndicator(color: WW.primary),
                      );
                    }
                    if (comments.isEmpty) {
                      return const Center(
                        child: Text('No comments yet — be the first!',
                            style: WW.labelMed),
                      );
                    }
                    return ListView.builder(
                      itemCount: comments.length,
                      itemBuilder: (context, i) {
                        final c = comments[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                radius: 14,
                                backgroundColor: WW.primary,
                                child: Text(
                                  ((c['authorName'] as String?) ?? '?')
                                      .substring(0, 1)
                                      .toUpperCase(),
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      (c['authorName'] as String?) ?? 'Someone',
                                      style: WW.labelMed.copyWith(
                                          fontWeight: FontWeight.w700,
                                          color: WW.text),
                                    ),
                                    Text(c['text'] as String? ?? '',
                                        style: WW.bodyMed),
                                  ],
                                ),
                              ),
                              if (c['uid'] == widget.currentUid)
                                GestureDetector(
                                  onTap: () => _confirmDeleteComment(c['id'] as String),
                                  child: const Padding(
                                    padding: EdgeInsets.only(left: 6, top: 2),
                                    child: Icon(
                                      Icons.delete_outline_rounded,
                                      size: 17,
                                      color: WW.textSec,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: WW.elevated,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: TextField(
                        controller: _controller,
                        style: WW.bodyMed,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          hintText: 'Add a comment…',
                          hintStyle: WW.labelMed,
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded, color: WW.primary),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
