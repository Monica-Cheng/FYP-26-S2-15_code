// lib/screens/business/coach_register_screen.dart
// "Register as Professional" — linked from the pre-auth login screen, so
// this route is public (see router.dart's redirect) and this screen
// itself gates on auth state: unauthenticated visitors see a prompt to
// sign in/create an account first (the actual registration write needs a
// real uid), rather than the form. An already-registered applicant
// (businessPartners/{uid} already exists) skips straight to
// coach_dashboard_screen.dart instead of re-showing the form.

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/app_theme.dart';
import '../../core/router.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../services/storage_service.dart';
import '../../widgets/quick_add_sheet.dart';

// Same 4 categories find_professional_screen.dart already filters by
// (minus its own 'All' chip, which doesn't apply to picking one type
// here) — kept in sync manually since neither file imports the other.
const List<String> _kCoachTypes = [
  'Trainer',
  'Running Coach',
  'Physiotherapist',
  'Nutritionist',
];

class CoachRegisterScreen extends StatefulWidget {
  const CoachRegisterScreen({super.key});

  @override
  State<CoachRegisterScreen> createState() => _CoachRegisterScreenState();
}

class _CoachRegisterScreenState extends State<CoachRegisterScreen> {
  final _authService = AuthService();
  final _firestoreService = FirestoreService();
  final _storageService = StorageService();

  final _nameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _experienceCtrl = TextEditingController();
  String _selectedType = _kCoachTypes.first;

  // Credential documents (certificates, proof of qualification) for
  // admin review — picked here, uploaded to Firebase Storage at submit
  // time (see _submit()), not base64-encoded into the businessPartners
  // doc like this app's other images. See storage_service.dart's own
  // doc comment for why: a certificate's fine print needs to stay
  // readable, which this app's usual compress-to-fit-Firestore pattern
  // would risk destroying.
  final List<File> _credentialFiles = [];

  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _checkExistingApplication();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    _experienceCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkExistingApplication() async {
    final uid = _authService.getCurrentUser()?.uid;
    if (uid == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    try {
      final existing = await _firestoreService.getBusinessPartnerProfile(uid);
      if (!mounted) return;
      if (existing != null) {
        // Already applied (pending or approved) — coach_dashboard_screen
        // itself branches on isApproved, so just forward there instead of
        // letting them resubmit a second application.
        context.pushReplacement(Routes.coachDashboard);
        return;
      }
      setState(() => _isLoading = false);
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool get _canSubmit =>
      _nameCtrl.text.trim().isNotEmpty && _bioCtrl.text.trim().isNotEmpty;

  void _showAddCredentialSheet() {
    showQuickAddSheet(
      context,
      [
        QuickAddOption(
          icon: Icons.camera_alt_rounded,
          iconColor: WW.primary,
          iconBg: WW.chipBg,
          title: 'Take Photo',
          subtitle: 'Photograph a certificate or ID',
          onTap: () => _pickCredentialPhoto(ImageSource.camera),
        ),
        QuickAddOption(
          icon: Icons.photo_library_rounded,
          iconColor: WW.lavender,
          iconBg: WW.lavenderBg,
          title: 'Choose from Gallery',
          subtitle: 'Select one or more existing photos',
          onTap: _pickCredentialsFromGallery,
        ),
        QuickAddOption(
          icon: Icons.picture_as_pdf_rounded,
          iconColor: const Color(0xFFDC2626),
          iconBg: const Color(0xFFFEE2E2),
          title: 'Upload PDF',
          subtitle: 'Select one or more PDF documents',
          onTap: _pickCredentialPdfs,
        ),
      ],
      title: 'Add Credential Document',
      subtitle: 'A certificate, license, or proof of qualification',
    );
  }

  Future<void> _pickCredentialPhoto(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      // No maxWidth/downscaling here — unlike this app's other photo
      // pickers, since these get uploaded full-resolution to Firebase
      // Storage (see storage_service.dart), not compressed into
      // Firestore. imageQuality alone keeps the camera capture's own
      // JPEG re-encode from being needlessly huge without touching
      // legibility at any normal certificate zoom level.
      imageQuality: 92,
    );
    if (picked == null || !mounted) return;
    setState(() => _credentialFiles.add(File(picked.path)));
  }

  Future<void> _pickCredentialsFromGallery() async {
    final picked = await ImagePicker().pickMultiImage(imageQuality: 92);
    if (picked.isEmpty || !mounted) return;
    setState(() {
      _credentialFiles.addAll(picked.map((x) => File(x.path)));
    });
  }

  // Real certificates/licenses are commonly PDFs, not photos —
  // image_picker only handles photos/gallery, so this uses file_picker
  // (a separate package) restricted to just 'pdf' via
  // FileType.custom/allowedExtensions, rather than FileType.any, so a
  // user can't attach an arbitrary/unexpected file type.
  Future<void> _pickCredentialPdfs() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      allowMultiple: true,
    );
    final paths = result?.paths.whereType<String>().toList() ?? [];
    if (paths.isEmpty || !mounted) return;
    setState(() {
      _credentialFiles.addAll(paths.map((p) => File(p)));
    });
  }

  void _removeCredentialFile(int index) {
    setState(() => _credentialFiles.removeAt(index));
  }

  Future<void> _submit() async {
    final uid = _authService.getCurrentUser()?.uid;
    if (uid == null || !_canSubmit || _isSubmitting) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      final credentialUrls = _credentialFiles.isNotEmpty
          ? await _storageService.uploadCredentialFiles(uid, _credentialFiles)
          : null;
      await _firestoreService.registerAsCoach(
        uid: uid,
        name: _nameCtrl.text.trim(),
        type: _selectedType,
        bio: _bioCtrl.text.trim(),
        experience: _experienceCtrl.text.trim(),
        email: _authService.getCurrentUser()?.email,
        credentialUrls: credentialUrls,
      );
      if (!mounted) return;
      context.pushReplacement(Routes.coachDashboard);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorMessage = 'Could not submit application: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSignedIn = _authService.getCurrentUser() != null;

    return Scaffold(
      backgroundColor: WW.bg,
      appBar: AppBar(
        backgroundColor: WW.bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: WW.text, size: 20),
          onPressed: () => context.pop(),
        ),
        title: const Text('Register as Professional', style: WW.titleMed),
        centerTitle: true,
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: WW.primary))
            : !isSignedIn
                ? _buildSignInPrompt()
                : _buildForm(),
      ),
    );
  }

  // ── Sign-in-first prompt (unauthenticated visitors) ──────────────────────

  Widget _buildSignInPrompt() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.badge_outlined, size: 56, color: WW.textSec),
          const SizedBox(height: 16),
          const Text(
            'Create an account first',
            style: WW.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'You need a WiseWorkout account before applying as a coach — '
            'sign in if you already have one, or create a new account.',
            style: WW.labelMed,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: () {
              // Consumed by router.dart's redirect once auth (and, for a
              // brand-new account, onboarding) actually completes — see
              // pendingCoachRegistration's own doc comment there.
              pendingCoachRegistration = true;
              context.push(Routes.register);
            },
            child: Container(
              width: double.infinity,
              height: 52,
              decoration: BoxDecoration(
                color: WW.primary,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Center(
                child: Text(
                  'Create Account',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () {
              pendingCoachRegistration = true;
              context.push(Routes.login);
            },
            child: const Text('I already have an account', style: TextStyle(color: WW.primary)),
          ),
        ],
      ),
    );
  }

  // ── Registration form ─────────────────────────────────────────────────────

  Widget _buildForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Tell us about yourself',
            style: WW.titleLarge,
          ),
          const SizedBox(height: 4),
          const Text(
            'Your application will be reviewed before your profile goes live.',
            style: WW.labelMed,
          ),
          const SizedBox(height: 20),

          _fieldLabel('YOUR NAME'),
          const SizedBox(height: 6),
          _buildTextField(_nameCtrl, hint: 'e.g. Jordan Lee'),
          const SizedBox(height: 18),

          _fieldLabel('COACH TYPE'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _kCoachTypes.map((type) {
              final selected = _selectedType == type;
              return GestureDetector(
                onTap: () => setState(() => _selectedType = type),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: selected ? WW.primary : WW.elevated,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    type,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : WW.textSec,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 18),

          _fieldLabel('EXPERIENCE'),
          const SizedBox(height: 6),
          _buildTextField(_experienceCtrl, hint: 'e.g. 5 years, NASM certified'),
          const SizedBox(height: 18),

          _fieldLabel('BIO'),
          const SizedBox(height: 6),
          _buildTextField(_bioCtrl, hint: 'A short introduction clients will see', maxLines: 4),
          const SizedBox(height: 18),

          _fieldLabel('CREDENTIAL DOCUMENTS'),
          const SizedBox(height: 4),
          const Text(
            'A certificate, license, or proof of qualification helps your '
            'application get reviewed faster. Optional, but recommended.',
            style: WW.labelMed,
          ),
          const SizedBox(height: 8),
          _buildCredentialPicker(),

          if (_errorMessage != null) ...[
            const SizedBox(height: 14),
            Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 13)),
          ],

          const SizedBox(height: 24),
          GestureDetector(
            onTap: _canSubmit && !_isSubmitting ? _submit : null,
            child: Container(
              width: double.infinity,
              height: 52,
              decoration: BoxDecoration(
                color: _canSubmit ? WW.primary : WW.border,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text(
                        'Submit Application',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _fieldLabel(String label) => Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: WW.textSec,
          letterSpacing: 0.5,
        ),
      );

  // Thumbnail grid of picked credential files — an image gets a real
  // Image.file preview (local only, nothing uploaded yet at this point,
  // see _submit()); a PDF can't easily show a thumbnail without extra
  // work, so it gets a generic PDF icon + filename instead, standard
  // practice for this. Plus a trailing "+" tile. Wrap (not Row) so it
  // drops to additional rows on narrow screens instead of overflowing —
  // same reasoning as this app's other Wrap-based pill rows (see
  // build_routine_screen.dart).
  Widget _buildCredentialPicker() {
    const tileSize = 72.0;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (var i = 0; i < _credentialFiles.length; i++)
          Stack(
            clipBehavior: Clip.none,
            children: [
              _buildCredentialTile(_credentialFiles[i], tileSize),
              Positioned(
                top: -6,
                right: -6,
                child: GestureDetector(
                  onTap: () => _removeCredentialFile(i),
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(
                      color: WW.text,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        GestureDetector(
          onTap: _showAddCredentialSheet,
          child: Container(
            width: tileSize,
            height: tileSize,
            decoration: BoxDecoration(
              color: WW.elevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: WW.border, width: 1),
            ),
            child: const Icon(Icons.add_rounded, color: WW.textSec, size: 26),
          ),
        ),
      ],
    );
  }

  Widget _buildCredentialTile(File file, double tileSize) {
    final isPdf = file.path.toLowerCase().endsWith('.pdf');
    if (!isPdf) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(file, width: tileSize, height: tileSize, fit: BoxFit.cover),
      );
    }
    final fileName = file.path.split('/').last;
    return Container(
      width: tileSize,
      height: tileSize,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      decoration: BoxDecoration(
        color: WW.elevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WW.border, width: 1),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.picture_as_pdf_rounded, color: Color(0xFFDC2626), size: 26),
          const SizedBox(height: 4),
          Text(
            fileName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: WW.textSec),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, {required String hint, int maxLines = 1}) {
    return Container(
      decoration: WW.cardDecoration,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        onChanged: (_) => setState(() {}),
        style: const TextStyle(fontSize: 15, color: WW.text),
        decoration: InputDecoration(
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          hintText: hint,
          hintStyle: const TextStyle(fontSize: 14, color: WW.border),
        ),
      ),
    );
  }
}
