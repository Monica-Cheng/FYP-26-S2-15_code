// lib/screens/business/coach_dashboard_screen.dart
// Entry point for an approved (or pending) coach — reached after
// submitting coach_register_screen.dart's form, on any later visit via
// profile_screen.dart's persistent link, as the post-login landing tab
// (home_screen.dart's MainShell), or via coach_screen.dart's "My
// Clients" toggle. All four entry points share the exact same
// CoachManagementBody below — this file just decides how much chrome
// (Scaffold/AppBar/title) wraps it for each context, so there is
// exactly one place the actual pending/request/client logic lives.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../core/router.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';

class CoachDashboardScreen extends StatelessWidget {
  // When true, renders as plain tab content (no Scaffold/AppBar/back
  // button) for embedding inside home_screen.dart's MainShell IndexedStack
  // — used for the post-login landing tab, where there's nothing to pop
  // back to (it's a shell tab, not a pushed route) and a back arrow would
  // be either dead or, worse, pop the whole shell. Defaults to false: the
  // normal standalone routed screen (Routes.coachDashboard, reached via
  // context.push() from profile_screen.dart's persistent entry point or
  // coach_register_screen.dart's post-submit redirect), which keeps its
  // full AppBar-with-back-button chrome since those ARE genuinely pushed,
  // poppable screens.
  final bool embedded;

  const CoachDashboardScreen({super.key, this.embedded = false});

  @override
  Widget build(BuildContext context) {
    if (embedded) {
      // Matches progress_screen.dart's own tab-content shape (ColoredBox
      // + SafeArea + a plain title, no AppBar) — this widget is a shell
      // tab here, not a pushed screen, so there's no back button.
      return const ColoredBox(
        color: WW.bg,
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(20, 14, 20, 8),
                child: Text(
                  'Coach Dashboard',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: WW.primaryDark),
                ),
              ),
              Expanded(child: CoachManagementBody()),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: WW.bg,
      appBar: AppBar(
        backgroundColor: WW.bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: WW.text, size: 20),
          onPressed: () => context.pop(),
        ),
        title: const Text('Coach Dashboard', style: WW.titleMed),
        centerTitle: true,
      ),
      body: const SafeArea(child: CoachManagementBody()),
    );
  }
}

// ── Reusable body: no-application / pending / approved (requests +
// clients) — the actual content shared by every entry point above and
// by coach_screen.dart's "My Clients" toggle. ──────────────────────────

class CoachManagementBody extends StatefulWidget {
  const CoachManagementBody({super.key});

  @override
  State<CoachManagementBody> createState() => _CoachManagementBodyState();
}

class _CoachManagementBodyState extends State<CoachManagementBody> {
  final _authService = AuthService();
  final _firestoreService = FirestoreService();

  bool _isLoadingProfile = true;
  Map<String, dynamic>? _partnerProfile;

  List<Map<String, dynamic>> _clients = [];
  bool _isLoadingClients = false;

  // Disables a request's Accept/Decline buttons while that specific
  // request is being processed, without blocking the rest of the list.
  final Set<String> _processingRequestIds = {};

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final uid = _authService.getCurrentUser()?.uid;
    if (uid == null) {
      if (mounted) setState(() => _isLoadingProfile = false);
      return;
    }
    try {
      final profile = await _firestoreService.getBusinessPartnerProfile(uid);
      if (!mounted) return;
      setState(() {
        _partnerProfile = profile;
        _isLoadingProfile = false;
      });
      if (profile?['isApproved'] == true) {
        _loadClients(uid);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingProfile = false);
    }
  }

  Future<void> _loadClients(String coachUid) async {
    setState(() => _isLoadingClients = true);
    try {
      final clients = await _firestoreService.getCoachClients(coachUid);
      if (!mounted) return;
      setState(() {
        _clients = clients;
        _isLoadingClients = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingClients = false);
    }
  }

  bool get _isApproved => _partnerProfile?['isApproved'] == true;

  Future<void> _acceptRequest(Map<String, dynamic> request) async {
    final coachUid = _authService.getCurrentUser()?.uid;
    final requestId = request['id'] as String?;
    final clientUid = request['clientUid'] as String?;
    if (coachUid == null || requestId == null || clientUid == null) return;

    setState(() => _processingRequestIds.add(requestId));
    try {
      final coachProfile = await _firestoreService.getUserProfile(coachUid);
      final rawName = (coachProfile?['displayName'] as String?)?.trim();
      final coachDisplayName = (rawName != null && rawName.isNotEmpty) ? rawName : 'Your coach';

      await _firestoreService.acceptCoachRequest(
        coachUid: coachUid,
        coachDisplayName: coachDisplayName,
        clientUid: clientUid,
        requestId: requestId,
      );
      if (!mounted) return;
      // The request list itself updates on its own (it's a live stream
      // watching this same doc's deletion) — only the client list needs
      // an explicit refresh, since getCoachClients() is a one-time fetch.
      await _loadClients(coachUid);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not accept request: $e')),
      );
    } finally {
      if (mounted) setState(() => _processingRequestIds.remove(requestId));
    }
  }

  Future<void> _declineRequest(String requestId) async {
    setState(() => _processingRequestIds.add(requestId));
    try {
      await _firestoreService.declineCoachRequest(requestId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not decline request: $e')),
      );
    } finally {
      if (mounted) setState(() => _processingRequestIds.remove(requestId));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingProfile) {
      return const Center(child: CircularProgressIndicator(color: WW.primary));
    }
    if (_partnerProfile == null) {
      return _buildNoApplicationState();
    }
    if (!_isApproved) {
      return _buildPendingState();
    }
    return _buildApprovedBody();
  }

  // Shouldn't normally be reachable (every entry point into this widget
  // only shows up once an application exists), but a direct/stale
  // navigation could still land here with none — fails soft with a
  // clear explanation rather than crashing on a null partnerProfile read.
  Widget _buildNoApplicationState() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.info_outline_rounded, size: 48, color: WW.textSec),
          SizedBox(height: 16),
          Text(
            'No application found',
            style: WW.titleLarge,
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 8),
          Text(
            'You haven\'t applied to become a coach yet.',
            style: WW.labelMed,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildPendingState() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: const BoxDecoration(color: WW.chipBg, shape: BoxShape.circle),
            child: const Center(
              child: Icon(Icons.hourglass_top_rounded, size: 40, color: WW.primary),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Your application is pending review',
            style: WW.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Thanks for applying, ${_partnerProfile?['name'] ?? 'there'} — '
            'we\'ll let you know once your profile as a '
            '${_partnerProfile?['type'] ?? 'coach'} has been reviewed.',
            style: WW.labelMed,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildApprovedBody() {
    final coachUid = _authService.getCurrentUser()?.uid;
    if (coachUid == null) return _buildNoApplicationState();

    // Persistent regardless of the request/client list state below —
    // this is about the coach's plan library in general now (any client
    // with an accepted relationship can see it), not tied to a specific
    // client row, so it isn't nested under either section.
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: _buildCreatePlanButton(),
        ),
        Expanded(child: _buildRequestsAndClients(coachUid)),
      ],
    );
  }

  Widget _buildCreatePlanButton() {
    return GestureDetector(
      onTap: () => context.push(Routes.buildRoutine, extra: {'isCoachPlan': true}),
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
              Icon(Icons.add_rounded, color: Colors.white, size: 20),
              SizedBox(width: 6),
              Text(
                'Create a Plan',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRequestsAndClients(String coachUid) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _firestoreService.getCoachRequestsStream(coachUid),
      builder: (context, snapshot) {
        final requests = snapshot.data ?? const [];
        final isLoadingRequests = !snapshot.hasData && snapshot.connectionState == ConnectionState.waiting;
        if (snapshot.hasError) {
          // Kept — a stream error here (e.g. a rules regression) would
          // otherwise silently show as "no pending requests" with no
          // trace of why.
          debugPrint('[CoachRequests] stream error: ${snapshot.error}');
        }

        // The empty state only shows once BOTH lists are known to be
        // genuinely empty — not while either is still loading, and not
        // just because nothing was ever built to display them.
        if (!isLoadingRequests &&
            !_isLoadingClients &&
            requests.isEmpty &&
            _clients.isEmpty) {
          return _buildEmptyState();
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            if (isLoadingRequests || requests.isNotEmpty) ...[
              _sectionHeader('Pending Requests', count: requests.length),
              const SizedBox(height: 10),
              if (isLoadingRequests)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator(color: WW.primary)),
                )
              else
                for (final request in requests) ...[
                  _buildRequestCard(request),
                  const SizedBox(height: 10),
                ],
              const SizedBox(height: 18),
            ],
            _sectionHeader('Your Clients', count: _clients.length),
            const SizedBox(height: 10),
            if (_isLoadingClients)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator(color: WW.primary)),
              )
            else if (_clients.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'No clients yet — accepted requests will show up here.',
                  style: WW.labelMed,
                ),
              )
            else
              for (final client in _clients) ...[
                _buildClientCard(client),
                const SizedBox(height: 10),
              ],
          ],
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.verified_rounded, size: 48, color: Color(0xFF10B981)),
          const SizedBox(height: 16),
          Text(
            'You\'re an approved ${_partnerProfile?['type'] ?? 'coach'}!',
            style: WW.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'Client requests and your client list will show up here once someone finds you via Find a Professional.',
            style: WW.labelMed,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, {required int count}) {
    return Row(
      children: [
        Text(title, style: WW.titleMed),
        if (count > 0) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: WW.chipBg, borderRadius: BorderRadius.circular(10)),
            child: Text(
              '$count',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: WW.primary),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> request) {
    final requestId = request['id'] as String? ?? '';
    final clientName = request['clientDisplayName'] as String? ?? 'Someone';
    final isProcessing = _processingRequestIds.contains(requestId);
    final initial = clientName.isNotEmpty ? clientName[0].toUpperCase() : '?';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: WW.cardDecoration,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(color: WW.primary, shape: BoxShape.circle),
            child: Center(
              child: Text(initial, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              clientName,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: WW.text),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          if (isProcessing)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: WW.primary),
            )
          else ...[
            GestureDetector(
              onTap: () => _declineRequest(requestId),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: WW.elevated,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text('Decline', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: WW.textSec)),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _acceptRequest(request),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: WW.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text('Accept', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildClientCard(Map<String, dynamic> client) {
    final clientName = client['clientDisplayName'] as String? ?? 'Client';
    final initial = clientName.isNotEmpty ? clientName[0].toUpperCase() : '?';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: WW.cardDecoration,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(color: WW.teal, shape: BoxShape.circle),
            child: Center(
              child: Text(initial, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              clientName,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: WW.text),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
