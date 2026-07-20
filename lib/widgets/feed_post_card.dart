// lib/widgets/feed_post_card.dart
// A single post in the Club "Feed" tab — avatar/name/timestamp header,
// optional food photo, a calorie/macro stat row, and a react + comment bar.
// Reactions and comments are real (Firestore), not mock data.

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../core/app_theme.dart';
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

  @override
  Widget build(BuildContext context) {
    final postId = post['id'] as String;
    final authorName = (post['authorName'] as String?) ?? 'Someone';
    final authorInitial = (post['authorInitial'] as String?) ?? '?';
    final foodName = (post['foodName'] as String?) ?? 'A meal';
    final calories = (post['calories'] as num?)?.toInt() ?? 0;
    final proteinG = (post['proteinG'] as num?)?.toInt();
    final carbsG = (post['carbsG'] as num?)?.toInt();
    final fatG = (post['fatG'] as num?)?.toInt();
    final imageBase64 = post['imageBase64'] as String?;
    final caption = post['caption'] as String?;
    final reactionCount = (post['reactionCount'] as num?)?.toInt() ?? 0;
    final commentCount = (post['commentCount'] as num?)?.toInt() ?? 0;
    final createdAt = post['createdAt'];
    final createdDt = createdAt is Timestamp ? createdAt.toDate() : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: WW.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: WW.primary,
                  child: Text(
                    authorInitial,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
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

          // Caption / food name
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(
              caption?.isNotEmpty == true ? caption! : foodName,
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
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: Image.memory(
                    base64Decode(imageBase64),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(color: WW.elevated),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 12),

          // Stat row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                _StatPill(icon: Icons.local_fire_department_rounded, color: WW.gold, value: '$calories', label: 'Calories'),
                const SizedBox(width: 8),
                _StatPill(icon: Icons.egg_alt_rounded, color: WW.lavender, value: '${proteinG ?? 0}g', label: 'Protein'),
                const SizedBox(width: 8),
                _StatPill(icon: Icons.grain_rounded, color: WW.teal, value: '${carbsG ?? 0}g', label: 'Carbs'),
                const SizedBox(width: 8),
                _StatPill(icon: Icons.water_drop_rounded, color: WW.primary, value: '${fatG ?? 0}g', label: 'Fats'),
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

class _StatPill extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;

  const _StatPill({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(height: 2),
            Text(value, style: WW.caption.copyWith(fontWeight: FontWeight.w800, color: color)),
          ],
        ),
      ),
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
