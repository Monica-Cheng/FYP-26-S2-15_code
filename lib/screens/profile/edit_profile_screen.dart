// lib/screens/profile/edit_profile_screen.dart
// Lets the current user edit their display name, username (with live
// uniqueness/format validation), hometown, bio, and profile photo.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../utils/image_encode.dart';
import '../../widgets/quick_add_sheet.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _auth = AuthService();
  final _firestore = FirestoreService();

  String _saveState = 'idle'; // idle / loading / saved
  String? _errorMessage;
  bool _isLoadingProfile = true;

  String _origName = '';
  String _origUsername = '';
  String _origHometown = '';
  String _origBio = '';
  String? _photoBase64;
  bool _isUploadingPhoto = false;

  late final TextEditingController _nameCtrl;
  late final TextEditingController _usernameCtrl;
  late final TextEditingController _hometownCtrl;
  late final TextEditingController _bioCtrl;
  late final FocusNode _usernameFocusNode;

  String? _usernameFieldError;
  bool _usernameChecking = false;
  bool _usernameValid = false;

  bool get _isDirty =>
      _nameCtrl.text != _origName ||
      _usernameCtrl.text != _origUsername ||
      _hometownCtrl.text != _origHometown ||
      _bioCtrl.text != _origBio;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _usernameCtrl = TextEditingController();
    _hometownCtrl = TextEditingController();
    _bioCtrl = TextEditingController();

    _nameCtrl.addListener(_rebuild);
    _usernameCtrl.addListener(_rebuild);
    _hometownCtrl.addListener(_rebuild);
    _bioCtrl.addListener(_rebuild);

    _usernameFocusNode = FocusNode();
    _usernameFocusNode.addListener(_onUsernameFocusChange);

    _loadProfile();
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    _nameCtrl.removeListener(_rebuild);
    _usernameCtrl.removeListener(_rebuild);
    _hometownCtrl.removeListener(_rebuild);
    _bioCtrl.removeListener(_rebuild);
    _usernameFocusNode.removeListener(_onUsernameFocusChange);
    _usernameFocusNode.dispose();
    _nameCtrl.dispose();
    _usernameCtrl.dispose();
    _hometownCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // On-blur username validation — runs format checks, then the async
  // uniqueness check (skipped if unchanged from the loaded username).
  // ---------------------------------------------------------------------------
  void _onUsernameFocusChange() {
    if (_usernameFocusNode.hasFocus) return;
    final username = _usernameCtrl.text.trim();
    if (username.isEmpty) {
      setState(() {
        _usernameFieldError = null;
        _usernameValid = false;
        _usernameChecking = false;
      });
      return;
    }
    _validateUsernameInline(username);
  }

  Future<void> _validateUsernameInline(String username) async {
    if (username.length < 3 || username.length > 20) {
      setState(() {
        _usernameFieldError = 'Username must be between 3 and 20 characters.';
        _usernameValid = false;
        _usernameChecking = false;
      });
      return;
    }
    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(username)) {
      setState(() {
        _usernameFieldError =
            'Username can only contain lowercase letters, numbers, and underscores.';
        _usernameValid = false;
        _usernameChecking = false;
      });
      return;
    }
    if (username == _origUsername) {
      setState(() {
        _usernameFieldError = null;
        _usernameValid = true;
        _usernameChecking = false;
      });
      return;
    }
    setState(() {
      _usernameFieldError = null;
      _usernameChecking = true;
      _usernameValid = false;
    });
    try {
      final isTaken = await _firestore.isUsernameTaken(username);
      if (!mounted) return;
      setState(() {
        _usernameChecking = false;
        if (isTaken) {
          _usernameFieldError = 'That username is already taken.';
          _usernameValid = false;
        } else {
          _usernameFieldError = null;
          _usernameValid = true;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _usernameChecking = false);
    }
  }

  Future<void> _loadProfile() async {
    final uid = _auth.getCurrentUser()?.uid;
    if (uid == null) {
      setState(() => _isLoadingProfile = false);
      return;
    }
    try {
      final profile = await _firestore.getUserProfile(uid);
      if (!mounted) return;
      final name = profile?['displayName'] as String? ?? '';
      final username = profile?['username'] as String? ?? '';
      final hometown = profile?['hometown'] as String? ?? '';
      final bio = profile?['bio'] as String? ?? '';

      _origName = name;
      _origUsername = username;
      _origHometown = hometown;
      _origBio = bio;

      _nameCtrl.text = name;
      _usernameCtrl.text = username;
      _hometownCtrl.text = hometown;
      _bioCtrl.text = bio;

      setState(() {
        _photoBase64 = profile?['photoBase64'] as String?;
        _isLoadingProfile = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingProfile = false);
    }
  }

  // ── Profile photo upload ──────────────────────────────────────────────────
  // Same Take Photo / Choose from Gallery -> encode -> write pattern as
  // profile_screen.dart's _pickAndUploadPhoto() — this screen previously had
  // no working photo picker at all (camera icon/"Change photo" just showed a
  // "coming soon" snackbar).

  Future<void> _promptChangePhoto() async {
    if (_isUploadingPhoto) return;
    await showQuickAddSheet(
      context,
      [
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
      ],
      title: 'Change Profile Photo',
      subtitle: 'Choose how to update your photo',
    );
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

  Future<void> _save() async {
    if (!_isDirty || _saveState != 'idle') return;
    if (_nameCtrl.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Display name cannot be empty.');
      return;
    }

    final username = _usernameCtrl.text.trim();
    if (username.length < 3 || username.length > 20) {
      setState(() => _errorMessage = 'Username must be between 3 and 20 characters.');
      return;
    }
    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(username)) {
      setState(() => _errorMessage =
          'Username can only contain lowercase letters, numbers, and underscores.');
      return;
    }
    if (username != _origUsername) {
      final isTaken = await _firestore.isUsernameTaken(username);
      if (isTaken) {
        setState(() => _errorMessage = 'That username is already taken.');
        return;
      }
    }

    setState(() {
      _saveState = 'loading';
      _errorMessage = null;
    });

    final uid = _auth.getCurrentUser()?.uid;
    if (uid == null) {
      setState(() {
        _saveState = 'idle';
        _errorMessage = 'Not signed in. Please restart the app.';
      });
      return;
    }

    try {
      await _firestore.updateUserProfile(uid, {
        'displayName': _nameCtrl.text.trim(),
        'username': username,
        'hometown': _hometownCtrl.text.trim(),
        'bio': _bioCtrl.text.trim(),
      });
      if (!mounted) return;
      setState(() => _saveState = 'saved');
      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) context.pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _saveState = 'idle';
          _errorMessage = 'Failed to save. Please try again.';
        });
      }
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

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WW.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildTopBar(),
            if (_errorMessage != null) _buildErrorBanner(),
            Expanded(
              child: _isLoadingProfile
                  ? const Center(
                      child: CircularProgressIndicator(color: WW.primary),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 100),
                      child: Column(
                        children: [
                          _buildAvatarSection(),
                          _buildFormCard(),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildStickyButton(),
    );
  }

  // ── Top bar ────────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    final canSave = _isDirty && _saveState == 'idle';
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
          // Back button — pops without saving
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
            'Edit Profile',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: WW.primaryDark,
            ),
          ),
          // Save text button — only active when dirty
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: canSave ? _save : null,
              child: Text(
                'Save',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: canSave ? WW.primary : const Color(0xFFC8C8D8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Error banner ───────────────────────────────────────────────────────────

  Widget _buildErrorBanner() {
    return Container(
      width: double.infinity,
      color: const Color(0xFFFFEEEE),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Text(
        _errorMessage!,
        style: const TextStyle(fontSize: 13, color: Color(0xFFEF4444)),
      ),
    );
  }

  // ── Avatar section ─────────────────────────────────────────────────────────

  Widget _buildAvatarContent() {
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
    final initial = _nameCtrl.text.trim().isNotEmpty
        ? _nameCtrl.text.trim()[0].toUpperCase()
        : '?';
    return Center(
      child: Text(
        initial,
        style: const TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildAvatarSection() {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 16),
      child: Column(
        children: [
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
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: WW.card,
                      shape: BoxShape.circle,
                      border: Border.all(color: WW.primary, width: 1.5),
                    ),
                    child: Center(
                      child: _isUploadingPhoto
                          ? const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                color: WW.primary,
                                strokeWidth: 1.5,
                              ),
                            )
                          : const Icon(
                              Icons.camera_alt_rounded,
                              size: 14,
                              color: WW.primary,
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: _isUploadingPhoto ? null : _promptChangePhoto,
            child: const Text(
              'Change photo',
              style: TextStyle(fontSize: 13, color: WW.primary),
            ),
          ),
        ],
      ),
    );
  }

  // ── Form card ──────────────────────────────────────────────────────────────

  Widget _buildFormCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: WW.cardDecoration,
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fieldName(),
          _divider(),
          _fieldUsername(),
          _divider(),
          _fieldHometown(),
          _divider(),
          _fieldBio(),
        ],
      ),
    );
  }

  Widget _divider() =>
      Container(height: 0.5, color: const Color(0xFFE8EAF8));

  Widget _fieldLabel(String label) => Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: WW.textSec,
          letterSpacing: 0.5,
        ),
      );

  static const _kFieldPadding = EdgeInsets.symmetric(
    horizontal: 16,
    vertical: 12,
  );

  static const _kInputDecoration = InputDecoration(
    border: InputBorder.none,
    isDense: true,
    contentPadding: EdgeInsets.zero,
    hintStyle: TextStyle(fontSize: 15, color: WW.border),
  );

  Widget _fieldName() {
    return Padding(
      padding: _kFieldPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fieldLabel('NAME'),
          const SizedBox(height: 6),
          TextField(
            controller: _nameCtrl,
            style: const TextStyle(fontSize: 15, color: WW.text),
            decoration: _kInputDecoration.copyWith(
              hintText: 'Your display name',
            ),
          ),
        ],
      ),
    );
  }

  Widget _fieldUsername() {
    final slug = _usernameCtrl.text.replaceAll('@', '');
    return Padding(
      padding: _kFieldPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fieldLabel('USERNAME'),
          const SizedBox(height: 6),
          TextField(
            controller: _usernameCtrl,
            focusNode: _usernameFocusNode,
            style: const TextStyle(fontSize: 15, color: WW.text),
            decoration: _kInputDecoration.copyWith(hintText: '@username'),
          ),
          const SizedBox(height: 4),
          Text(
            'wiseworkout.app/u/$slug',
            style: const TextStyle(
              fontSize: 11,
              color: WW.textSec,
              fontStyle: FontStyle.italic,
            ),
          ),
          if (_usernameChecking) ...[
            const SizedBox(height: 4),
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: WW.primary),
            ),
          ] else if (_usernameFieldError != null) ...[
            const SizedBox(height: 4),
            Text(
              _usernameFieldError!,
              style: const TextStyle(fontSize: 12, color: Color(0xFFEF4444)),
            ),
          ] else if (_usernameValid) ...[
            const SizedBox(height: 4),
            const Icon(Icons.check_circle_rounded, size: 16, color: Color(0xFF22C55E)),
          ],
        ],
      ),
    );
  }

  Widget _fieldHometown() {
    return Padding(
      padding: _kFieldPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fieldLabel('HOMETOWN'),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.location_on_rounded, size: 14, color: WW.textSec),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _hometownCtrl,
                  style: const TextStyle(fontSize: 15, color: WW.text),
                  decoration: _kInputDecoration.copyWith(
                    hintText: 'City or country',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _fieldBio() {
    return Padding(
      padding: _kFieldPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fieldLabel('BIO'),
          const SizedBox(height: 6),
          TextField(
            controller: _bioCtrl,
            maxLength: 150,
            maxLines: null,
            minLines: 3,
            style: const TextStyle(fontSize: 15, color: WW.text, height: 1.5),
            decoration: _kInputDecoration.copyWith(
              hintText: 'Write a short bio...',
              counterText: '',
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '${_bioCtrl.text.length} / 150',
              style: const TextStyle(fontSize: 11, color: WW.textSec),
            ),
          ),
        ],
      ),
    );
  }

  // ── Sticky save button ─────────────────────────────────────────────────────

  Widget _buildStickyButton() {
    final canSave = _isDirty && _saveState == 'idle';

    final Color bgColor;
    final Color fgColor;
    if (_saveState == 'saved') {
      bgColor = const Color(0xFF22C55E);
      fgColor = Colors.white;
    } else if (canSave || _saveState == 'loading') {
      bgColor = WW.primary;
      fgColor = Colors.white;
    } else {
      bgColor = const Color(0xFFE8EAF8);
      fgColor = WW.textSec;
    }

    final String label;
    if (_saveState == 'loading') {
      label = 'Saving...';
    } else if (_saveState == 'saved') {
      label = 'Saved!';
    } else {
      label = 'Save Changes';
    }

    Widget? leadingIcon;
    if (_saveState == 'loading') {
      leadingIcon = const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
      );
    } else if (_saveState == 'saved') {
      leadingIcon = const Icon(Icons.check_rounded, size: 16, color: Colors.white);
    }

    return Container(
      decoration: const BoxDecoration(
        color: WW.card,
        border: Border(top: BorderSide(color: Color(0xFFE8EAF8), width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: GestureDetector(
            onTap: canSave ? _save : null,
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (leadingIcon != null) ...[
                    leadingIcon,
                    const SizedBox(width: 8),
                  ],
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: fgColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
