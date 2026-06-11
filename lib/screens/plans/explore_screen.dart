// lib/screens/plans/explore_screen.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../core/router.dart';
import '../../services/firestore_service.dart';

// ── Hardcoded catalog plans (coming soon — not yet in Firestore) ──────────────

const _kCatalogPlans = <Map<String, dynamic>>[
  // ── Gym ──
  {
    'id': 'catalog_fat_loss_circuit',
    'name': 'Fat Loss Circuit',
    'level': 'Beginner',
    'sport': 'Gym',
    'goal': 'Lose Weight',
    'daysPerWeek': 3,
    'totalWeeks': 8,
    'description': 'High-intensity circuits combining strength and cardio.',
    'coach': 'WiseWorkout',
    'saves': 143,
    'isCatalogOnly': true,
  },
  {
    'id': 'catalog_advanced_powerlifting',
    'name': 'Advanced Powerlifting',
    'level': 'Advanced',
    'sport': 'Gym',
    'goal': 'Build Strength',
    'daysPerWeek': 4,
    'totalWeeks': 12,
    'description': 'Periodised strength block for competitive lifters.',
    'coach': 'WiseWorkout',
    'saves': 38,
    'isCatalogOnly': true,
  },
  {
    'id': 'catalog_home_dumbbell',
    'name': 'Home Dumbbell Strength',
    'level': 'Beginner',
    'sport': 'Gym',
    'goal': 'Build Muscle',
    'daysPerWeek': 3,
    'totalWeeks': 8,
    'description': 'Build strength from home with just a set of dumbbells.',
    'coach': 'WiseWorkout',
    'saves': 88,
    'isCatalogOnly': true,
  },
  {
    'id': 'catalog_bodyweight_burn',
    'name': '30-Day Bodyweight Burn',
    'level': 'Intermediate',
    'sport': 'Gym',
    'goal': 'Lose Weight',
    'daysPerWeek': 5,
    'totalWeeks': 5,
    'description': 'No-equipment HIIT that burns fat fast anywhere.',
    'coach': 'WiseWorkout',
    'saves': 199,
    'isCatalogOnly': true,
  },
  {
    'id': 'catalog_hiit_abs',
    'name': 'HIIT & Abs',
    'level': 'Intermediate',
    'sport': 'Gym',
    'goal': 'Lose Weight',
    'daysPerWeek': 4,
    'totalWeeks': 6,
    'description': 'Intense full-body HIIT sessions with core finishers.',
    'coach': 'WiseWorkout',
    'saves': 115,
    'isCatalogOnly': true,
  },
  // ── Running ──
  {
    'id': 'catalog_5k_speed',
    'name': '5K Speed Builder',
    'level': 'Intermediate',
    'sport': 'Running',
    'goal': 'Endurance',
    'daysPerWeek': 4,
    'totalWeeks': 6,
    'description': 'Tempo runs and intervals to break your 5K PB.',
    'coach': 'WiseWorkout',
    'saves': 156,
    'isCatalogOnly': true,
  },
  {
    'id': 'catalog_10k_plan',
    'name': '10K Structured Plan',
    'level': 'Intermediate',
    'sport': 'Running',
    'goal': 'Endurance',
    'daysPerWeek': 5,
    'totalWeeks': 10,
    'description': 'Structured mileage build to complete your first 10K.',
    'coach': 'WiseWorkout',
    'saves': 76,
    'isCatalogOnly': true,
  },
  {
    'id': 'catalog_half_marathon',
    'name': 'Half Marathon Prep',
    'level': 'Intermediate',
    'sport': 'Running',
    'goal': 'Endurance',
    'daysPerWeek': 5,
    'totalWeeks': 16,
    'description': '16-week build to cross your first half marathon finish line.',
    'coach': 'WiseWorkout',
    'saves': 55,
    'isCatalogOnly': true,
  },
  {
    'id': 'catalog_marathon',
    'name': 'Marathon Ready',
    'level': 'Advanced',
    'sport': 'Running',
    'goal': 'Endurance',
    'daysPerWeek': 6,
    'totalWeeks': 20,
    'description': 'Advanced plan for the 42.2 km ultimate challenge.',
    'coach': 'WiseWorkout',
    'saves': 44,
    'isCatalogOnly': true,
  },
  {
    'id': 'catalog_recovery_runs',
    'name': 'Easy Recovery Runs',
    'level': 'Beginner',
    'sport': 'Running',
    'goal': 'General Fitness',
    'daysPerWeek': 3,
    'totalWeeks': 4,
    'description': 'Low-intensity runs to build habit and aerobic base.',
    'coach': 'WiseWorkout',
    'saves': 89,
    'isCatalogOnly': true,
  },
];

// ── Screen ─────────────────────────────────────────────────────────────────────

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  List<Map<String, dynamic>> _firestorePlans = [];
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
  }

  // All plans: Firestore first, then catalog extras (deduped by name).
  List<Map<String, dynamic>> get _allPlans {
    final firestoreNames = _firestorePlans.map((p) => p['name']).toSet();
    final extras = _kCatalogPlans
        .where((p) => !firestoreNames.contains(p['name']))
        .toList();
    return [..._firestorePlans, ...extras];
  }

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

  List<Map<String, dynamic>> get _runningPlans =>
      _allPlans.where((p) {
        final sport = (p['sport'] ?? p['type'] ?? '').toString().toLowerCase();
        return sport == 'running';
      }).toList();

  // Featured: first 3 gym plans from Firestore, then fill with catalog.
  List<Map<String, dynamic>> get _featuredPlans {
    final gym = _gymPlans.take(2).toList();
    final run = _runningPlans.take(1).toList();
    return [...gym, ...run].take(3).toList();
  }

  Color _accentColor(Map<String, dynamic> plan) {
    final sport = (plan['sport'] ?? plan['type'] ?? '').toString().toLowerCase();
    switch (sport) {
      case 'running':
        return WW.teal;
      case 'gym':
        return WW.primary;
      default:
        return WW.lavender;
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: WW.primaryDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _onPlanTap(Map<String, dynamic> plan) {
    if (plan['isCatalogOnly'] == true) {
      _snack('This plan is coming soon to WiseWorkout!');
    } else {
      context.push(Routes.planDetail, extra: plan);
    }
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
          ['All', 'Gym', 'Running'],
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
    final running = _runningPlans;
    final featured = _featuredPlans;

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Featured ──────────────────────────────────────────────────────
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
                itemBuilder: (ctx3, i) => _FeaturedCard(
                  plan: featured[i],
                  accentColor: _accentColor(featured[i]),
                  onTap: () => _onPlanTap(featured[i]),
                ),
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

          // ── Running Plans ─────────────────────────────────────────────────
          if (running.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Row(
                children: [
                  const Text(
                    'Running Plans',
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
                      '${running.length}',
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
            ...running.map((p) => Padding(
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

class _FeaturedCard extends StatelessWidget {
  final Map<String, dynamic> plan;
  final Color accentColor;
  final VoidCallback onTap;

  const _FeaturedCard({
    required this.plan,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final name = plan['name'] as String? ?? '';
    final level = plan['level'] as String? ?? '';
    final days = (plan['daysPerWeek'] as num?)?.toInt() ?? 0;
    final weeks = (plan['totalWeeks'] as num?)?.toInt() ?? 0;
    final desc = plan['description'] as String? ?? '';
    final isCatalog = plan['isCatalogOnly'] == true;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 260,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              accentColor,
              accentColor.withValues(alpha: 0.65),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: accentColor.withValues(alpha: 0.3),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
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
                  child: const Text(
                    'FEATURED',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                if (isCatalog) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'COMING SOON',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
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

// ── Plan list card ─────────────────────────────────────────────────────────────

class _PlanCard extends StatelessWidget {
  final Map<String, dynamic> plan;
  final Color accentColor;
  final VoidCallback onTap;

  const _PlanCard({
    required this.plan,
    required this.accentColor,
    required this.onTap,
  });

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
    final isCatalog = plan['isCatalogOnly'] == true;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: WW.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: WW.border, width: 0.5),
          boxShadow: WW.shadow,
        ),
        clipBehavior: Clip.hardEdge,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left accent bar
              Container(width: 4, color: accentColor),
              // Content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name row
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: WW.text,
                                height: 1.25,
                              ),
                            ),
                          ),
                          if (isCatalog) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: WW.elevated,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'Coming soon',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  color: WW.textSec,
                                ),
                              ),
                            ),
                          ],
                        ],
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
                            _Chip(label: sport, bg: WW.elevated, textColor: WW.textSec),
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
              ),
            ],
          ),
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
