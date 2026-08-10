// lib/screens/plans/explore_screen.dart

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../core/router.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';

// ── Shared category theming ─────────────────────────────────────────────────
// Single source of truth for the Gym/Cardio/Combine icon, reused by the
// inline sport chip icon, the vertical list card's image-fallback tile, and
// the Featured card's image-fallback background — was previously duplicated
// per-widget as _PlanCard._sportIcon.
IconData _categoryIcon(String sport) {
  switch (sport.toLowerCase()) {
    case 'cardio':
      return Icons.directions_run_rounded;
    case 'combine':
      return Icons.merge_type_rounded;
    case 'gym':
      return Icons.fitness_center_rounded;
    default:
      return Icons.sports_rounded;
  }
}

// ── Screen ─────────────────────────────────────────────────────────────────────

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  List<Map<String, dynamic>> _firestorePlans = [];
  List<Map<String, dynamic>> _coachPlans = [];
  bool _isLoading = true;

  final _searchController = TextEditingController();
  String _searchQuery = '';
  String _levelFilter = 'All';
  String _goalFilter = 'All';
  String _sportFilter = 'All';

  final _fs = FirestoreService();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim());
    });
    _loadPlans();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPlans() async {
    try {
      final plans = await _fs.getPlans();
      if (mounted) {
        setState(() {
          _firestorePlans = plans;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
    _loadCoachPlans();
  }

  // Separate from _loadPlans()'s own try/catch — a failure here (or an
  // account with no accepted coach at all, the common case) shouldn't
  // block or delay the main Explore list from showing. Fails soft to an
  // empty list either way, which _buildBrowseMode() already treats as
  // "don't show this section" further down.
  Future<void> _loadCoachPlans() async {
    final uid = AuthService().getCurrentUser()?.uid;
    if (uid == null) return;
    try {
      final plans = await _fs.getCoachPlansForClient(uid);
      if (mounted) setState(() => _coachPlans = plans);
    } catch (_) {}
  }

  // "Coach [Name]'s Plans" when every plan came from the same coach (the
  // common case — one client, one coach); falls back to a generic title
  // if this client happens to have plans from more than one coach,
  // rather than guessing which name to feature.
  String get _coachPlansSectionTitle {
    final names = _coachPlans
        .map((p) => p['coachDisplayName'] as String?)
        .whereType<String>()
        .toSet();
    if (names.length == 1) return "Coach ${names.first}'s Plans";
    return "Your Coaches' Plans";
  }

  // All plans: real non-custom Firestore plans only — the "coming soon"
  // catalog filler (_kCatalogPlans) has been removed. This also acts as
  // the belt-and-suspenders guard for _featuredPlans below: custom/coach
  // plans can never have featured:true written to them server-side (not
  // in their write allowlist), but excluding isCustom docs here too means
  // _featuredPlans never trusts a forged/bad client write either.
  List<Map<String, dynamic>> get _allPlans =>
      _firestorePlans.where((p) => p['isCustom'] != true).toList();

  bool get _hasActiveFilter =>
      _searchQuery.isNotEmpty ||
      _levelFilter != 'All' ||
      _goalFilter != 'All' ||
      _sportFilter != 'All';

  bool _matchesPlan(Map<String, dynamic> plan) {
    if (_searchQuery.isNotEmpty) {
      final name = (plan['name'] as String? ?? '').toLowerCase();
      final goal = (plan['goal'] as String? ?? '').toLowerCase();
      final coach = (plan['coach'] as String? ?? '').toLowerCase();
      final q = _searchQuery.toLowerCase();
      if (!name.contains(q) && !goal.contains(q) && !coach.contains(q)) {
        return false;
      }
    }
    if (_levelFilter != 'All') {
      if ((plan['level'] as String? ?? '') != _levelFilter) return false;
    }
    if (_goalFilter != 'All') {
      if ((plan['goal'] as String? ?? '') != _goalFilter) return false;
    }
    if (_sportFilter != 'All') {
      final sport = (plan['sport'] ?? plan['type'] ?? '').toString();
      if (!sport.toLowerCase().contains(_sportFilter.toLowerCase())) return false;
    }
    return true;
  }

  List<Map<String, dynamic>> get _filteredPlans =>
      _allPlans.where(_matchesPlan).toList();

  List<Map<String, dynamic>> get _gymPlans =>
      _allPlans.where((p) {
        final sport = (p['sport'] ?? p['type'] ?? '').toString().toLowerCase();
        return sport == 'gym';
      }).toList();

  List<Map<String, dynamic>> get _cardioPlans =>
      _allPlans.where((p) {
        final sport = (p['sport'] ?? p['type'] ?? '').toString().toLowerCase();
        return sport == 'cardio';
      }).toList();

  List<Map<String, dynamic>> get _combinePlans =>
      _allPlans.where((p) {
        final sport = (p['sport'] ?? p['type'] ?? '').toString().toLowerCase();
        return sport == 'combine';
      }).toList();

  // Real featured plans, driven by the featured:true flag (Phase 1 backend
  // work) instead of the old client-computed "first 2 gym + 1 running"
  // guess. Deliberately NOT excluded from _gymPlans/_cardioPlans/
  // _combinePlans above — a featured plan is meant to show up twice (once
  // here, once in its normal category section further down).
  List<Map<String, dynamic>> get _featuredPlans =>
      _allPlans.where((p) => p['featured'] == true).toList();

  Color _accentColor(Map<String, dynamic> plan) {
    final sport = (plan['sport'] ?? plan['type'] ?? '').toString().toLowerCase();
    switch (sport) {
      case 'cardio':
        return WW.teal;
      case 'combine':
        return WW.gold;
      case 'gym':
        return WW.primary;
      default:
        return WW.lavender;
    }
  }

  void _onPlanTap(Map<String, dynamic> plan) {
    context.push(Routes.planDetail, extra: {
      ...plan,
      'fromExplore': true,
    });
  }

  void _clearFilters() {
    setState(() {
      _levelFilter = 'All';
      _goalFilter = 'All';
      _sportFilter = 'All';
      _searchController.clear();
    });
  }

  void _showFilterSheet(
    String title,
    List<String> options,
    String current,
    ValueChanged<String> onSelect,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: WW.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _FilterSheet(
        title: title,
        options: options,
        current: current,
        onSelect: (val) {
          Navigator.of(ctx).pop();
          onSelect(val);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WW.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTopBar(),
            _buildSearchBar(),
            _buildFilterChips(),
            if (_isLoading)
              const Expanded(
                child: Center(child: CircularProgressIndicator(color: WW.primary)),
              )
            else
              Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.pop(),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: WW.elevated,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Icon(Icons.chevron_left_rounded, color: WW.textSec, size: 22),
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Explore Plans',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: WW.primaryDark,
                letterSpacing: -0.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: WW.elevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: WW.border, width: 0.5),
        ),
        child: Row(
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 12),
              child: Icon(Icons.search_rounded, color: WW.textSec, size: 18),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchController,
                style: const TextStyle(fontSize: 14, color: WW.text),
                decoration: const InputDecoration(
                  hintText: 'Search plans...',
                  hintStyle: TextStyle(fontSize: 14, color: WW.textSec),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            if (_searchQuery.isNotEmpty)
              GestureDetector(
                onTap: () => _searchController.clear(),
                child: const Padding(
                  padding: EdgeInsets.only(right: 10),
                  child: Icon(Icons.close_rounded, color: WW.textSec, size: 18),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    final chips = [
      _FilterChipData(
        label: _levelFilter == 'All' ? 'Level' : 'Level: $_levelFilter',
        active: _levelFilter != 'All',
        onTap: () => _showFilterSheet(
          'Level',
          ['All', 'Beginner', 'Intermediate', 'Advanced'],
          _levelFilter,
          (v) => setState(() => _levelFilter = v),
        ),
      ),
      _FilterChipData(
        label: _goalFilter == 'All' ? 'Goal' : 'Goal: $_goalFilter',
        active: _goalFilter != 'All',
        onTap: () => _showFilterSheet(
          'Goal',
          ['All', 'Build Muscle', 'Lose Weight', 'Endurance', 'General Fitness', 'Build Strength'],
          _goalFilter,
          (v) => setState(() => _goalFilter = v),
        ),
      ),
      _FilterChipData(
        label: _sportFilter == 'All' ? 'Sport' : 'Sport: $_sportFilter',
        active: _sportFilter != 'All',
        onTap: () => _showFilterSheet(
          'Sport',
          ['All', 'Gym', 'Cardio', 'Combine'],
          _sportFilter,
          (v) => setState(() => _sportFilter = v),
        ),
      ),
    ];

    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          ...chips.map((c) => _buildChip(c)),
          if (_hasActiveFilter)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: GestureDetector(
                onTap: _clearFilters,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFEF4444), width: 1.5),
                  ),
                  child: const Text(
                    'Clear ×',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFEF4444),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildChip(_FilterChipData c) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: c.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: c.active ? WW.chipBg : WW.elevated,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: c.active ? WW.primary : WW.border,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                c.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: c.active ? WW.primary : WW.textSec,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 14,
                color: c.active ? WW.primary : WW.textSec,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_hasActiveFilter) {
      return _buildFilteredResults();
    }
    return _buildBrowseMode();
  }

  Widget _buildFilteredResults() {
    final results = _filteredPlans;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${results.length} plan${results.length != 1 ? 's' : ''} found',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: WW.textSec,
            ),
          ),
          const SizedBox(height: 12),
          if (results.isEmpty)
            _buildEmptyState()
          else
            ...results.map((p) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _PlanCard(plan: p, accentColor: _accentColor(p), onTap: () => _onPlanTap(p)),
                )),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
        child: Column(
          children: [
            const Icon(Icons.search_off_rounded, size: 48, color: WW.textSec),
            const SizedBox(height: 16),
            const Text(
              'No plans match',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: WW.primaryDark,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Try adjusting your filters or search term.',
              style: TextStyle(fontSize: 13, color: WW.textSec),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: _clearFilters,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: WW.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Clear Filters',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBrowseMode() {
    final gym = _gymPlans;
    final cardio = _cardioPlans;
    final combine = _combinePlans;
    final featured = _featuredPlans;

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Coach's Plans (only if this client has an accepted coach
          // relationship with at least one coach who's created plans) —
          // same card style as Featured Plans below, positioned above it.
          // Data source (getCoachPlansForClient via _loadCoachPlans) is
          // unchanged by this phase. Coach plans never carry imageUrl, so
          // imageUrl is intentionally omitted below — the card always
          // falls back to its gradient + workspace_premium icon.
          if (_coachPlans.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: Text(
                _coachPlansSectionTitle,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: WW.primaryDark,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            SizedBox(
              height: 186,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _coachPlans.length,
                separatorBuilder: (ctx, idx) => const SizedBox(width: 12),
                itemBuilder: (ctx, i) => _FeaturedCard(
                  plan: _coachPlans[i],
                  accentColor: _accentColor(_coachPlans[i]),
                  onTap: () => _onPlanTap(_coachPlans[i]),
                  badgeLabel: 'COACH',
                  fallbackIcon: Icons.workspace_premium_rounded,
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],

          // ── Featured — real featured:true official plans (Phase 1
          // backend). No hardcoded count cap; the card row just scrolls
          // further with more of them. Uses each plan's real imageUrl when
          // set, falling back to a gradient + category icon otherwise.
          if (featured.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: Text(
                'Featured Plans',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: WW.primaryDark,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            SizedBox(
              height: 186,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: featured.length,
                separatorBuilder: (ctx2, idx2) => const SizedBox(width: 12),
                itemBuilder: (ctx3, i) {
                  final plan = featured[i];
                  final sport = (plan['sport'] ?? plan['type'] ?? '').toString();
                  return _FeaturedCard(
                    plan: plan,
                    accentColor: _accentColor(plan),
                    onTap: () => _onPlanTap(plan),
                    imageUrl: plan['imageUrl'] as String?,
                    fallbackIcon: _categoryIcon(sport),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
          ],

          // ── Gym Plans ─────────────────────────────────────────────────────
          if (gym.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Row(
                children: [
                  Text(
                    'Gym Plans',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: WW.primaryDark,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: WW.chipBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${gym.length}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: WW.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ...gym.map((p) => Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: _PlanCard(
                    plan: p,
                    accentColor: _accentColor(p),
                    onTap: () => _onPlanTap(p),
                  ),
                )),
            const SizedBox(height: 10),
          ],

          // ── Cardio Plans (replaces the old "Running Plans" section —
          // same widget/layout, just the renamed category) ─────────────────
          if (cardio.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Row(
                children: [
                  const Text(
                    'Cardio Plans',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: WW.primaryDark,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: WW.tealBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${cardio.length}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: WW.teal,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ...cardio.map((p) => Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: _PlanCard(
                    plan: p,
                    accentColor: _accentColor(p),
                    onTap: () => _onPlanTap(p),
                  ),
                )),
            const SizedBox(height: 10),
          ],

          // ── Combine Plans (new category) ─────────────────────────────────
          if (combine.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Row(
                children: [
                  const Text(
                    'Combine Plans',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: WW.primaryDark,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      // No dedicated WW.goldBg token exists — derived at
                      // runtime from WW.gold instead of a new hardcoded
                      // hex, same convention _FeaturedCard's gradient
                      // already uses below for its own tint.
                      color: WW.gold.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${combine.length}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: WW.gold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ...combine.map((p) => Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: _PlanCard(
                    plan: p,
                    accentColor: _accentColor(p),
                    onTap: () => _onPlanTap(p),
                  ),
                )),
          ],
        ],
      ),
    );
  }
}

// ── Featured card (horizontal scroll) ────────────────────────────────────────
// Used for both "Your Coaches' Plans" (badgeLabel:'COACH', no imageUrl —
// coach plans never carry one, so the background is always the gradient +
// fallbackIcon path) and "Featured Plans" (badgeLabel:'FEATURED', real
// imageUrl when the official plan has one).

class _FeaturedCard extends StatelessWidget {
  final Map<String, dynamic> plan;
  final Color accentColor;
  final VoidCallback onTap;
  // Defaults to 'FEATURED' so the existing Featured Plans section is
  // completely unchanged — the Coach's Plans section above passes
  // 'COACH' instead so the two don't read as the same category of card.
  final String badgeLabel;
  // Null/empty for coach cards (coach plans never have this field) and for
  // featured plans that simply haven't had an image set yet.
  final String? imageUrl;
  // Centered over the gradient whenever there's no image (or it fails to
  // load) — the per-category icon for Featured cards, or
  // Icons.workspace_premium_rounded for Coach cards (chosen at the call
  // site in _buildBrowseMode, not computed here).
  final IconData fallbackIcon;

  const _FeaturedCard({
    required this.plan,
    required this.accentColor,
    required this.onTap,
    this.badgeLabel = 'FEATURED',
    this.imageUrl,
    this.fallbackIcon = Icons.sports_rounded,
  });

  bool get _hasImage => (imageUrl ?? '').isNotEmpty;

  Widget _gradientFallback() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accentColor,
            accentColor.withValues(alpha: 0.65),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          fallbackIcon,
          size: 64,
          color: Colors.white.withValues(alpha: 0.35),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = plan['name'] as String? ?? '';
    final level = plan['level'] as String? ?? '';
    final days = (plan['daysPerWeek'] as num?)?.toInt() ?? 0;
    final weeks = (plan['totalWeeks'] as num?)?.toInt() ?? 0;
    final desc = plan['description'] as String? ?? '';
    final coachName = plan['coachDisplayName'] as String?;
    // saveCustomRoutine() in firestore_service.dart writes this exact
    // string as a hardcoded, non-empty description for every custom
    // routine — coach plans included, since build_routine_screen.dart
    // never collects a real description from the coach. So on a COACH
    // card, `desc` is never actually empty/null the way plan['description']
    // is for a genuinely-missing description elsewhere — this literal
    // value IS the "no real description" case for a coach plan. Scoped to
    // badgeLabel == 'COACH' only: a non-coach card's description Text
    // renders exactly as before (unconditionally, even if desc is empty —
    // unchanged from the original behavior, not newly gated here).
    final hideCoachDesc = badgeLabel == 'COACH' &&
        (desc.isEmpty || desc == 'Custom routine created by user');

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 260,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: accentColor.withValues(alpha: 0.3),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background layer: real image when available, else the
            // existing gradient + large centered icon.
            if (_hasImage)
              CachedNetworkImage(
                imageUrl: imageUrl!,
                fit: BoxFit.cover,
                placeholder: (context, url) => _gradientFallback(),
                errorWidget: (context, url, error) => _gradientFallback(),
              )
            else
              _gradientFallback(),
            // Legibility scrim over a photo background only — the plain
            // gradient fallback is already dark enough for white text on
            // its own, matching the original design.
            if (_hasImage)
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.05),
                      Colors.black.withValues(alpha: 0.6),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          badgeLabel,
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.3,
                      height: 1.2,
                    ),
                  ),
                  if (badgeLabel == 'COACH' && coachName != null && coachName.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(Icons.person_rounded,
                            size: 12, color: Colors.white.withValues(alpha: 0.78)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            coachName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.78),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (!hideCoachDesc) ...[
                    const SizedBox(height: 5),
                    Text(
                      desc,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.78),
                        height: 1.4,
                      ),
                    ),
                  ],
                  const Spacer(),
                  Row(
                    children: [
                      if (level.isNotEmpty)
                        _FeaturedChip(level),
                      if (days > 0) ...[
                        const SizedBox(width: 5),
                        _FeaturedChip('$days d/wk'),
                      ],
                      if (weeks > 0) ...[
                        const SizedBox(width: 5),
                        _FeaturedChip('$weeks wks'),
                      ],
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Explore',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(width: 4),
                            Icon(Icons.chevron_right_rounded, color: Colors.white, size: 14),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeaturedChip extends StatelessWidget {
  final String label;
  const _FeaturedChip(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

// ── Plan list card (image-left layout) ───────────────────────────────────────

class _PlanCard extends StatelessWidget {
  final Map<String, dynamic> plan;
  final Color accentColor;
  final VoidCallback onTap;

  static const double _tileSize = 84;

  const _PlanCard({
    required this.plan,
    required this.accentColor,
    required this.onTap,
  });

  // Tinted square tile — soft accentColor background + the category's
  // rounded icon, shown whenever there's no imageUrl (or it fails to
  // load). Reuses the same accentColor already passed down from
  // _ExploreScreenState._accentColor(), same theming source as before,
  // just applied to a tile instead of the old left accent-bar strip.
  Widget _iconTile(String sport) {
    return Container(
      color: accentColor.withValues(alpha: 0.15),
      child: Center(
        child: Icon(_categoryIcon(sport), size: 32, color: accentColor),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = plan['name'] as String? ?? '';
    final level = plan['level'] as String? ?? '';
    final sport = (plan['sport'] ?? plan['type'] ?? '').toString();
    final days = (plan['daysPerWeek'] as num?)?.toInt() ?? 0;
    final desc = plan['description'] as String? ?? '';
    final coach = plan['coach'] as String? ?? 'WiseWorkout';
    final saves = (plan['saves'] as num?)?.toInt() ?? 0;
    final goal = plan['goal'] as String? ?? '';
    final imageUrl = plan['imageUrl'] as String? ?? '';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: WW.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: WW.border, width: 0.5),
          boxShadow: WW.shadow,
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: _tileSize,
                height: _tileSize,
                child: imageUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => _iconTile(sport),
                        errorWidget: (context, url, error) => _iconTile(sport),
                      )
                    : _iconTile(sport),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name row
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: WW.text,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 7),
                  // Chips row
                  Wrap(
                    spacing: 5,
                    runSpacing: 4,
                    children: [
                      if (level.isNotEmpty)
                        _Chip(label: level, bg: WW.chipBg, textColor: WW.primary),
                      if (sport.isNotEmpty)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_categoryIcon(sport),
                                size: 12, color: WW.textSec),
                            const SizedBox(width: 3),
                            _Chip(
                                label: sport,
                                bg: WW.elevated,
                                textColor: WW.textSec),
                          ],
                        ),
                      if (days > 0)
                        _Chip(label: '$days d/wk', bg: WW.elevated, textColor: WW.textSec),
                      if (goal.isNotEmpty)
                        _Chip(label: goal, bg: WW.elevated, textColor: WW.textSec),
                    ],
                  ),
                  if (desc.isNotEmpty) ...[
                    const SizedBox(height: 7),
                    Text(
                      desc,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: WW.textSec,
                        height: 1.4,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  // Bottom row: coach + saves
                  Row(
                    children: [
                      const Icon(Icons.person_outline_rounded,
                          size: 12, color: WW.textSec),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          coach,
                          style: const TextStyle(
                              fontSize: 11, color: WW.textSec),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (saves > 0) ...[
                        const Icon(Icons.bookmark_outline_rounded,
                            size: 12, color: WW.textSec),
                        const SizedBox(width: 3),
                        Text(
                          '$saves saves',
                          style: const TextStyle(
                              fontSize: 11, color: WW.textSec),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color bg;
  final Color textColor;

  const _Chip({required this.label, required this.bg, required this.textColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }
}

// ── Filter bottom sheet ───────────────────────────────────────────────────────

class _FilterSheet extends StatefulWidget {
  final String title;
  final List<String> options;
  final String current;
  final ValueChanged<String> onSelect;

  const _FilterSheet({
    required this.title,
    required this.options,
    required this.current,
    required this.onSelect,
  });

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late String _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.current;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: WW.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: WW.primaryDark,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: const Icon(Icons.close_rounded, color: WW.textSec, size: 22),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1, color: WW.border),
          ...widget.options.map((opt) {
            final selected = _selected == opt;
            return InkWell(
              onTap: () => setState(() => _selected = opt),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        opt,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                          color: selected ? WW.primary : WW.text,
                        ),
                      ),
                    ),
                    if (selected)
                      const Icon(Icons.check_rounded, color: WW.primary, size: 18),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: GestureDetector(
              onTap: () => widget.onSelect(_selected),
              child: Container(
                width: double.infinity,
                height: 48,
                decoration: BoxDecoration(
                  color: WW.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Text(
                    'Apply',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Filter chip data model ────────────────────────────────────────────────────

class _FilterChipData {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _FilterChipData({required this.label, required this.active, required this.onTap});
}
