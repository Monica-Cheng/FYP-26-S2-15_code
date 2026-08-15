// lib/screens/club/create_challenge_screen.dart
// Form for creating a new (private) group challenge: name, category, goal
// value, date range, and friends to invite.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../core/constants.dart';
import '../../core/router.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';

// Single-scroll challenge creation flow, reached from club_screen.dart's
// "Create" button on the Challenges tab. User-created challenges are
// always private/invite-only (createChallenge() hardcodes isGlobal:false)
// — the friend-invite step below reuses the same search-by-username +
// list pattern friends_screen.dart already established, just with
// checkboxes instead of an "Add Friend" action.
class CreateChallengeScreen extends StatefulWidget {
  const CreateChallengeScreen({super.key});

  @override
  State<CreateChallengeScreen> createState() => _CreateChallengeScreenState();
}

class _CreateChallengeScreenState extends State<CreateChallengeScreen> {
  final _firestoreService = FirestoreService();
  final _authService = AuthService();

  final _nameCtrl = TextEditingController();
  final _goalCtrl = TextEditingController();

  List<Map<String, dynamic>> _categories = [];
  bool _loadingCategories = true;
  Map<String, dynamic>? _selectedCategory;
  String? _goalError;

  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now().add(const Duration(days: 7));

  List<Map<String, dynamic>> _friends = [];
  bool _loadingFriends = true;
  final Set<String> _selectedFriendUids = {};

  bool _isSaving = false;

  static const _kDivider = Color(0xFFE8EAF8);
  static const _kSectionHeaderStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: WW.textSec,
    letterSpacing: 0.4,
  );

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _loadFriends();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _goalCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    final categories = await _firestoreService.getChallengeCategories();
    if (mounted) {
      setState(() {
        _categories = categories;
        _loadingCategories = false;
      });
    }
  }

  Future<void> _loadFriends() async {
    final uid = _authService.getCurrentUser()?.uid;
    if (uid == null) {
      setState(() => _loadingFriends = false);
      return;
    }
    final friends = await _firestoreService.getFriendsStream(uid).first;
    if (mounted) {
      setState(() {
        _friends = friends;
        _loadingFriends = false;
      });
    }
  }

  bool get _canSave =>
      _nameCtrl.text.trim().isNotEmpty &&
      _selectedCategory != null &&
      _goalError == null &&
      double.tryParse(_goalCtrl.text.trim()) != null &&
      _endDate.isAfter(_startDate);

  void _validateGoal() {
    final value = double.tryParse(_goalCtrl.text.trim());
    final category = _selectedCategory;
    if (value == null || category == null) {
      setState(() => _goalError = null);
      return;
    }
    final min = (category['minGoal'] as num?)?.toDouble();
    final max = (category['maxGoal'] as num?)?.toDouble();
    String? error;
    if (min != null && value < min) error = 'Minimum is $min ${category['unit']}';
    if (max != null && value > max) error = 'Maximum is $max ${category['unit']}';
    setState(() => _goalError = error);
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() {
        _startDate = picked;
        if (!_endDate.isAfter(_startDate)) {
          _endDate = _startDate.add(const Duration(days: 7));
        }
      });
    }
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate,
      firstDate: _startDate.add(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) setState(() => _endDate = picked);
  }

  Future<void> _submit() async {
    if (!_canSave || _isSaving) return;
    final uid = _authService.getCurrentUser()?.uid;
    if (uid == null) return;
    setState(() => _isSaving = true);
    try {
      final profile = await _firestoreService.getUserProfile(uid);
      final isPremium = profile?['isPremium'] as bool? ?? false;
      if (!isPremium) {
        final createdCount =
            await _firestoreService.getCreatedChallengeCount(uid);
        if (createdCount >= AppConstants.freeChallengeLimit) {
          if (mounted) {
            setState(() => _isSaving = false);
            await context.push(Routes.upgrade);
          }
          return;
        }
      }
      await _firestoreService.createChallenge(
        uid,
        name: _nameCtrl.text.trim(),
        categoryId: _selectedCategory!['id'] as String,
        metricType: _selectedCategory!['metricType'] as String,
        unit: _selectedCategory!['unit'] as String,
        goalValue: double.parse(_goalCtrl.text.trim()),
        startDate: _startDate,
        endDate: _endDate,
        invitedUids: _selectedFriendUids.toList(),
      );
      if (mounted) {
        context.pop();
        _snack('Challenge created');
      }
    } catch (e) {
      // Was a bare `catch (_)` — a real failure here (e.g. the
      // PERMISSION_DENIED that used to come from getCreatedChallengeCount()'s
      // old query shape, see that method's own doc comment) was previously
      // indistinguishable from any other failure, both in the console and
      // to the user, making this exact bug much harder to diagnose than it
      // needed to be. Logged here so a future issue like that shows up
      // immediately instead of needing independent investigation from
      // scratch.
      debugPrint('CreateChallengeScreen: _submit failed — $e');
      if (mounted) {
        setState(() => _isSaving = false);
        _snack('Something went wrong. Please try again.');
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

  String _fmtDate(DateTime d) => '${d.day}/${d.month}/${d.year}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WW.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildContent()),
            _buildSubmitBar(),
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
                  child: Icon(Icons.close_rounded, size: 20, color: WW.textSec),
                ),
              ),
            ),
          ),
          const Text(
            'Create Challenge',
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

  Widget _buildContent() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        const Text('NAME', style: _kSectionHeaderStyle),
        const SizedBox(height: 8),
        _inputField(
          controller: _nameCtrl,
          hint: 'e.g. Weekly 5K',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 20),
        const Text('CATEGORY', style: _kSectionHeaderStyle),
        const SizedBox(height: 8),
        _buildCategoryPicker(),
        const SizedBox(height: 20),
        if (_selectedCategory != null) ...[
          Text(
            'GOAL (${_selectedCategory!['unit']})',
            style: _kSectionHeaderStyle,
          ),
          const SizedBox(height: 8),
          _inputField(
            controller: _goalCtrl,
            hint: 'Target ${_selectedCategory!['unit']}',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => _validateGoal(),
          ),
          if (_goalError != null) ...[
            const SizedBox(height: 6),
            Text(
              _goalError!,
              style: const TextStyle(fontSize: 12, color: Colors.redAccent),
            ),
          ],
          const SizedBox(height: 20),
        ],
        const Text('DATES', style: _kSectionHeaderStyle),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _dateField('Start', _startDate, _pickStartDate)),
            const SizedBox(width: 12),
            Expanded(child: _dateField('End', _endDate, _pickEndDate)),
          ],
        ),
        const SizedBox(height: 20),
        Text('INVITE FRIENDS (${_selectedFriendUids.length})',
            style: _kSectionHeaderStyle),
        const SizedBox(height: 8),
        _buildFriendInviteList(),
      ],
    );
  }

  Widget _inputField({
    required TextEditingController controller,
    required String hint,
    TextInputType? keyboardType,
    required ValueChanged<String> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: WW.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WW.border, width: 1),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        onChanged: onChanged,
        style: const TextStyle(fontSize: 14, color: WW.text),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(fontSize: 14, color: WW.textSec),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildCategoryPicker() {
    if (_loadingCategories) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: CircularProgressIndicator(color: WW.primary),
        ),
      );
    }
    if (_categories.isEmpty) {
      return const Text(
        'No challenge categories available yet.',
        style: TextStyle(fontSize: 13, color: WW.textSec),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _categories.map((c) {
        final id = c['id'] as String;
        final selected = _selectedCategory?['id'] == id;
        return GestureDetector(
          onTap: () {
            setState(() {
              _selectedCategory = c;
              _goalError = null;
            });
            _validateGoal();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: selected ? WW.primary : WW.elevated,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              c['name'] as String? ?? 'Category',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : WW.text,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _dateField(String label, DateTime date, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: WW.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: WW.border, width: 1),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_rounded, size: 15, color: WW.textSec),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(fontSize: 10, color: WW.textSec)),
                  Text(_fmtDate(date),
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: WW.text)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFriendInviteList() {
    if (_loadingFriends) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: CircularProgressIndicator(color: WW.primary),
        ),
      );
    }
    if (_friends.isEmpty) {
      return const Text(
        'No friends yet — you can still create the challenge solo.',
        style: TextStyle(fontSize: 13, color: WW.textSec),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: WW.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: List.generate(_friends.length, (i) {
          final f = _friends[i];
          final uid = f['uid'] as String? ?? f['id'] as String? ?? '';
          final name = f['displayName'] as String? ?? 'Friend';
          final username = f['username'] as String? ?? '';
          final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
          final selected = _selectedFriendUids.contains(uid);
          final isLast = i == _friends.length - 1;
          return GestureDetector(
            onTap: () {
              setState(() {
                if (selected) {
                  _selectedFriendUids.remove(uid);
                } else {
                  _selectedFriendUids.add(uid);
                }
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                border: isLast
                    ? null
                    : const Border(bottom: BorderSide(color: _kDivider, width: 0.5)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                      color: WW.elevated,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(initial,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: WW.text)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: WW.rowName),
                        const SizedBox(height: 2),
                        Text(username.isNotEmpty ? '@$username' : '—',
                            style: WW.rowSecondary),
                      ],
                    ),
                  ),
                  Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: selected ? WW.primary : WW.border,
                    size: 22,
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildSubmitBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: const BoxDecoration(
        color: WW.card,
        border: Border(top: BorderSide(color: _kDivider, width: 0.5)),
      ),
      child: GestureDetector(
        onTap: _canSave && !_isSaving ? _submit : null,
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            color: _canSave ? WW.primary : WW.border,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  )
                : const Text(
                    'Create Challenge',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
