// lib/widgets/user_avatar.dart
// Shared avatar circle used everywhere a user's photo can show — post
// headers, comments, leaderboard/friend rows, profile screens. Shows the
// real photoBase64 (users/{uid}.photoBase64, denormalized per-context —
// see each call site) when set, falling back to an initials circle
// otherwise. Callers control size/colors/border so this can match each
// screen's existing avatar styling instead of forcing one universal look.

import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/app_theme.dart';

class UserAvatar extends StatelessWidget {
  final String? photoBase64;
  final String initial;
  final double size;
  final Color backgroundColor;
  final Color initialColor;
  final double? initialFontSize;
  final Border? border;

  const UserAvatar({
    super.key,
    required this.photoBase64,
    required this.initial,
    this.size = 36,
    this.backgroundColor = WW.primary,
    this.initialColor = Colors.white,
    this.initialFontSize,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final photo = photoBase64;
    if (photo != null && photo.isNotEmpty) {
      try {
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: border,
            image: DecorationImage(
              image: MemoryImage(base64Decode(photo)),
              fit: BoxFit.cover,
            ),
          ),
        );
      } catch (_) {
        // Falls through to the initials circle below.
      }
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: BoxShape.circle,
        border: border,
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            color: initialColor,
            fontWeight: FontWeight.w700,
            fontSize: initialFontSize ?? size * 0.38,
          ),
        ),
      ),
    );
  }
}
