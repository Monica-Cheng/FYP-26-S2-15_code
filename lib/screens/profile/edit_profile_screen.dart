// lib/screens/profile/edit_profile_screen.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';

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

  late final TextEditingController _nameCtrl;
  late final TextEditingController _usernameCtrl;
  late final TextEditingController _hometownCtrl;
  late final TextEditingController _bioCtrl;

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

    _loadProfile();
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    _nameCtrl.removeListener(_rebuild);
    _usernameCtrl.removeListener(_rebuild);
    _hometownCtrl.removeListener(_rebuild);
    _bioCtrl.removeListener(_rebuild);
    _nameCtrl.dispose();
    _usernameCtrl.dispose();
    _hometownCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
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

      setState(() => _isLoadingProfile = false);
    } catch (_) {
      if (mounted) setState(() => _isLoadingProfile = false);
    }
  }

  Future<void> _save() async {
    if (!_isDirty || _saveState != 'idle') return;
    if (_nameCtrl.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Display name cannot be empty.');
      return;
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
        'username': _usernameCtrl.text.trim(),
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

  Widget _buildAvatarSection() {
    final initial = _nameCtrl.text.trim().isNotEmpty
        ? _nameCtrl.text.trim()[0].toUpperCase()
        : '?';
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
                child: Center(
                  child: Text(
                    initial,
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
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: WW.card,
                      shape: BoxShape.circle,
                      border: Border.all(color: WW.primary, width: 1.5),
                    ),
                    child: const Center(
                      child: Icon(
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
            onTap: () => _snack('Photo upload coming soon'),
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
