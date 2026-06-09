// lib/screens/home/manual_activity_log_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';

// Activity-specific accent colors not present in WW palette
const _kBlue   = Color(0xFF3B82F6); // swimming
const _kGreen  = Color(0xFF22C55E); // hiking, football
const _kRed    = Color(0xFFEF4444); // table tennis, martial arts
const _kOrange = Color(0xFFF97316); // HIIT
const _kYellow = Color(0xFFEAB308); // tennis
const _kBrown  = Color(0xFF92400E); // rock climbing
const _kPink   = Color(0xFFEC4899); // dance

// MET values per activity key and intensity
const Map<String, Map<String, double>> _kMet = {
  'running':    {'easy': 6.0,  'moderate': 8.0,  'hard': 11.5},
  'walking':    {'easy': 2.8,  'moderate': 3.5,  'hard': 5.0},
  'cycling':    {'easy': 4.0,  'moderate': 6.8,  'hard': 10.0},
  'swimming':   {'easy': 5.0,  'moderate': 7.0,  'hard': 9.8},
  'hiking':     {'easy': 5.0,  'moderate': 6.0,  'hard': 7.8},
  'basketball': {'easy': 4.5,  'moderate': 6.5,  'hard': 8.0},
  'gym':        {'easy': 3.0,  'moderate': 3.5,  'hard': 5.0},
  'hiit':       {'easy': 5.0,  'moderate': 8.0,  'hard': 12.0},
  'yoga':       {'easy': 2.0,  'moderate': 2.5,  'hard': 4.0},
};

double _metFor(String key, String intensity) {
  const fallback = {'easy': 3.5, 'moderate': 5.0, 'hard': 7.0};
  final row = _kMet[key] ?? fallback;
  return (row[intensity] ?? row['moderate'])!;
}

// ── Activity catalogue ────────────────────────────────────────────────────────

class _Activity {
  final String key;
  final String label;
  final String desc;
  final Color color;
  final IconData icon;
  final bool hasDistance;
  const _Activity({
    required this.key,
    required this.label,
    required this.desc,
    required this.color,
    required this.icon,
    this.hasDistance = false,
  });
}

class _Category {
  final String title;
  final List<_Activity> activities;
  const _Category(this.title, this.activities);
}

const List<_Category> _kCatalogue = [
  _Category('Cardio & Sport', [
    _Activity(key:'running',     label:'Running',           desc:'Road, track or trail',     color:WW.teal,    icon:Icons.directions_run_rounded,    hasDistance:true),
    _Activity(key:'walking',     label:'Walking',           desc:'Casual or brisk walk',     color:WW.teal,    icon:Icons.directions_walk_rounded,   hasDistance:true),
    _Activity(key:'cycling',     label:'Cycling',           desc:'Outdoor or stationary',    color:WW.teal,    icon:Icons.directions_bike_rounded,   hasDistance:true),
    _Activity(key:'swimming',    label:'Swimming',          desc:'Pool or open water',       color:_kBlue,     icon:Icons.pool_rounded,              hasDistance:true),
    _Activity(key:'hiking',      label:'Hiking',            desc:'Trail or nature walk',     color:_kGreen,    icon:Icons.terrain_rounded,           hasDistance:true),
    _Activity(key:'basketball',  label:'Basketball',        desc:'Casual or competitive',    color:WW.gold,    icon:Icons.sports_basketball_rounded),
    _Activity(key:'football',    label:'Football / Soccer', desc:'Casual or competitive',    color:_kGreen,    icon:Icons.sports_soccer_rounded),
    _Activity(key:'tennis',      label:'Tennis',            desc:'Singles or doubles',       color:_kYellow,   icon:Icons.sports_tennis_rounded),
    _Activity(key:'badminton',   label:'Badminton',         desc:'Singles or doubles',       color:WW.teal,    icon:Icons.sports_tennis_rounded),
    _Activity(key:'volleyball',  label:'Volleyball',        desc:'Beach or indoor',          color:WW.gold,    icon:Icons.sports_volleyball_rounded),
    _Activity(key:'tableTennis', label:'Table Tennis',      desc:'Casual or competitive',    color:_kRed,      icon:Icons.sports_tennis_rounded),
  ]),
  _Category('Gym & Fitness', [
    _Activity(key:'gym',          label:'Gym Training',     desc:'Free weights, machines',   color:WW.primary, icon:Icons.fitness_center_rounded),
    _Activity(key:'hiit',         label:'HIIT',             desc:'High intensity intervals', color:_kOrange,   icon:Icons.bolt_rounded),
    _Activity(key:'yoga',         label:'Yoga',             desc:'Any style',                color:WW.lavender,icon:Icons.self_improvement_rounded),
    _Activity(key:'pilates',      label:'Pilates',          desc:'Mat or reformer',          color:WW.lavender,icon:Icons.self_improvement_rounded),
    _Activity(key:'martialArts',  label:'Martial Arts',     desc:'Boxing, karate, judo',     color:_kRed,      icon:Icons.sports_martial_arts_rounded),
    _Activity(key:'rockClimbing', label:'Rock Climbing',    desc:'Indoor or outdoor',        color:_kBrown,    icon:Icons.landscape_rounded),
    _Activity(key:'dance',        label:'Dance',            desc:'Any style',                color:_kPink,     icon:Icons.music_note_rounded),
  ]),
  _Category('Other', [
    _Activity(key:'otherCardio',  label:'Other Cardio',     desc:'Jump rope, rowing, etc.',  color:WW.teal,    icon:Icons.favorite_rounded),
    _Activity(key:'other',        label:'Other Activity',   desc:'Any activity not listed',  color:WW.textSec, icon:Icons.more_horiz_rounded),
  ]),
];

final List<_Activity> _kAllActivities = [
  for (final cat in _kCatalogue) ...cat.activities,
];

// ── Screen ────────────────────────────────────────────────────────────────────

class ManualActivityLogScreen extends StatefulWidget {
  const ManualActivityLogScreen({super.key});

  @override
  State<ManualActivityLogScreen> createState() => _ManualActivityLogScreenState();
}

class _ManualActivityLogScreenState extends State<ManualActivityLogScreen> {
  final _auth      = AuthService();
  final _firestore = FirestoreService();

  final _searchCtrl   = TextEditingController();
  final _notesCtrl    = TextEditingController();
  final _distanceCtrl = TextEditingController();
  late final TextEditingController _durationCtrl;

  _Activity? _selected;
  String   _intensity     = 'moderate';
  DateTime _activityDate  = DateTime.now();
  TimeOfDay _activityTime = TimeOfDay.now();
  String   _saveState     = 'idle'; // idle | loading | saved
  double   _userWeightKg  = 70.0;
  int      _durationMin   = 0;
  bool     _durationError = false;

  bool get _canSave =>
      _selected != null && _durationMin > 0 && _saveState == 'idle';

  int get _estimatedCals {
    if (_selected == null || _durationMin <= 0) return 0;
    return (_metFor(_selected!.key, _intensity) * _userWeightKg * _durationMin / 60)
        .round();
  }

  List<_Activity>? get _searchResults {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return null;
    return _kAllActivities
        .where((a) =>
            a.label.toLowerCase().contains(q) ||
            a.key.toLowerCase().contains(q))
        .toList();
  }

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _durationCtrl = TextEditingController();
    _durationCtrl.addListener(_onDurationChanged);
    _searchCtrl.addListener(() => setState(() {}));
    _loadUserWeight();
  }

  void _onDurationChanged() {
    final v = (int.tryParse(_durationCtrl.text) ?? 0).clamp(0, 480);
    if (v != _durationMin || (v > 0 && _durationError)) {
      setState(() {
        _durationMin = v;
        if (v > 0) _durationError = false;
      });
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _notesCtrl.dispose();
    _distanceCtrl.dispose();
    _durationCtrl
      ..removeListener(_onDurationChanged)
      ..dispose();
    super.dispose();
  }

  Future<void> _loadUserWeight() async {
    final uid = _auth.getCurrentUser()?.uid;
    if (uid == null) return;
    try {
      final profile = await _firestore.getUserProfile(uid);
      if (!mounted) return;
      final w = double.tryParse(profile?['weight']?.toString() ?? '') ?? 70.0;
      setState(() => _userWeightKg = w);
    } catch (_) {}
  }

  // ── Actions ─────────────────────────────────────────────────────────────────

  void _selectActivity(_Activity act) {
    setState(() {
      _selected = act;
      _searchCtrl.clear();
    });
  }

  void _clearSelection() {
    setState(() {
      _selected = null;
      _durationMin = 0;
      _durationCtrl.clear();
      _distanceCtrl.clear();
      _notesCtrl.clear();
      _durationError = false;
    });
  }

  void _adjustDuration(int delta) {
    final v = (_durationMin + delta).clamp(0, 480);
    final text = v == 0 ? '' : '$v';
    _durationCtrl.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _activityDate,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now,
    );
    if (picked != null && mounted) setState(() => _activityDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _activityTime,
    );
    if (picked != null && mounted) setState(() => _activityTime = picked);
  }

  Future<void> _save() async {
    if (!_canSave) return;
    if (_durationMin <= 0) {
      setState(() => _durationError = true);
      return;
    }
    setState(() => _saveState = 'loading');

    final uid = _auth.getCurrentUser()?.uid;
    if (uid == null) {
      setState(() => _saveState = 'idle');
      return;
    }

    final dt = DateTime(
      _activityDate.year, _activityDate.month, _activityDate.day,
      _activityTime.hour, _activityTime.minute,
    );

    try {
      await _firestore.saveManualActivity(
        uid,
        activityKey:    _selected!.key,
        activityName:   _selected!.label,
        intensity:      _intensity,
        durationMinutes: _durationMin,
        distance: _selected!.hasDistance && _distanceCtrl.text.isNotEmpty
            ? double.tryParse(_distanceCtrl.text)
            : null,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        caloriesBurned: _estimatedCals,
        activityDate:   dt,
      );
      if (!mounted) return;
      setState(() => _saveState = 'saved');
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) context.pop();
    } catch (_) {
      if (mounted) setState(() => _saveState = 'idle');
    }
  }

  // ── Formatting helpers ───────────────────────────────────────────────────────

  String _formatDate(DateTime d) {
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return 'Today';
    }
    const months = ['Jan','Feb','Mar','Apr','May','Jun',
                    'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day} ${months[d.month - 1]}';
  }

  String _formatTime(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.period == DayPeriod.am ? 'AM' : 'PM'}';
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WW.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHelperTip(),
                    const SizedBox(height: 12),
                    _buildSearchBar(),
                    const SizedBox(height: 10),
                    if (_selected != null) ...[
                      _buildSelectedPill(),
                      const SizedBox(height: 16),
                      _buildIntensitySection(),
                      const SizedBox(height: 20),
                      _buildForm(),
                      if (_estimatedCals > 0) ...[
                        const SizedBox(height: 12),
                        _buildCalCard(),
                      ],
                    ] else
                      _buildActivityList(),
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

  // ── Top bar ──────────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Container(
      height: 56,
      decoration: const BoxDecoration(
        color: WW.card,
        border: Border(bottom: BorderSide(color: Color(0xFFE8EAF8), width: 0.5)),
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
                  child: Icon(Icons.close_rounded, size: 18, color: WW.textSec),
                ),
              ),
            ),
          ),
          const Text(
            'Log Activity',
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

  // ── Helper tip ───────────────────────────────────────────────────────────────

  Widget _buildHelperTip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: WW.elevated,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Icon(Icons.info_outline_rounded, size: 14, color: WW.primary),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Log a past activity to track your calorie burn for the day.',
              style: TextStyle(fontSize: 13, color: WW.text, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  // ── Search bar ───────────────────────────────────────────────────────────────

  Widget _buildSearchBar() {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: WW.elevated,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, size: 18, color: WW.textSec),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(fontSize: 14, color: WW.text),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                hintText: 'Search activities...',
                hintStyle: TextStyle(fontSize: 14, color: WW.textSec),
              ),
            ),
          ),
          if (_searchCtrl.text.isNotEmpty)
            GestureDetector(
              onTap: () => _searchCtrl.clear(),
              child: const Icon(Icons.close_rounded, size: 16, color: WW.textSec),
            ),
        ],
      ),
    );
  }

  // ── Selected activity pill ────────────────────────────────────────────────────

  Widget _buildSelectedPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: WW.chipBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: WW.primary, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_rounded, size: 14, color: WW.primary),
          const SizedBox(width: 6),
          Text(
            _selected!.label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: WW.primary,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _clearSelection,
            child: const Icon(Icons.close_rounded, size: 14, color: WW.textSec),
          ),
        ],
      ),
    );
  }

  // ── Intensity section ─────────────────────────────────────────────────────────

  Widget _buildIntensitySection() {
    const segs = [('easy', 'Easy'), ('moderate', 'Moderate'), ('hard', 'Hard')];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('Intensity'),
        const SizedBox(height: 8),
        Row(
          children: List.generate(segs.length, (i) {
            final (key, label) = segs[i];
            final active = _intensity == key;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  left: i == 0 ? 0 : 5,
                  right: i == segs.length - 1 ? 0 : 5,
                ),
                child: GestureDetector(
                  onTap: () => setState(() => _intensity = key),
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: active ? WW.primary : WW.elevated,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: active ? Colors.white : WW.textSec,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  // ── Details form ──────────────────────────────────────────────────────────────

  Widget _buildForm() {
    return Container(
      decoration: WW.cardDecoration,
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date + Time side by side
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _dateTile()),
              Container(width: 0.5, height: 80, color: const Color(0xFFE8EAF8)),
              Expanded(child: _timeTile()),
            ],
          ),
          const _Divider(),
          _durationField(),
          if (_selected?.hasDistance == true) ...[
            const _Divider(),
            _distanceField(),
          ],
          const _Divider(),
          _notesField(),
        ],
      ),
    );
  }

  Widget _dateTile() {
    return GestureDetector(
      onTap: _pickDate,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _FieldLabel('DATE'),
            const SizedBox(height: 6),
            Text(
              _formatDate(_activityDate),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: WW.text,
              ),
            ),
            const SizedBox(height: 2),
            const Text('Tap to change',
                style: TextStyle(fontSize: 11, color: WW.textSec)),
          ],
        ),
      ),
    );
  }

  Widget _timeTile() {
    return GestureDetector(
      onTap: _pickTime,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _FieldLabel('TIME'),
            const SizedBox(height: 6),
            Text(
              _formatTime(_activityTime),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: WW.text,
              ),
            ),
            const SizedBox(height: 2),
            const Text('Tap to change',
                style: TextStyle(fontSize: 11, color: WW.textSec)),
          ],
        ),
      ),
    );
  }

  Widget _durationField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _FieldLabel('DURATION'),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.timer_rounded, size: 18, color: WW.primary),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _adjustDuration(-5),
                child: const Icon(Icons.remove_circle_outline_rounded,
                    size: 26, color: WW.primary),
              ),
              Expanded(
                child: TextField(
                  controller: _durationCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: _durationError ? const Color(0xFFEF4444) : WW.text,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    hintText: '0',
                    hintStyle: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: WW.border,
                    ),
                  ),
                ),
              ),
              const Text('min',
                  style: TextStyle(fontSize: 15, color: WW.textSec)),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _adjustDuration(5),
                child: const Icon(Icons.add_circle_outline_rounded,
                    size: 26, color: WW.primary),
              ),
            ],
          ),
          if (_durationError) ...[
            const SizedBox(height: 4),
            const Row(
              children: [
                Icon(Icons.error_outline_rounded,
                    size: 12, color: Color(0xFFEF4444)),
                SizedBox(width: 4),
                Text('Please enter a duration.',
                    style: TextStyle(fontSize: 12, color: Color(0xFFEF4444))),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _distanceField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              _FieldLabel('DISTANCE'),
              SizedBox(width: 4),
              Text('(optional)',
                  style: TextStyle(fontSize: 11, color: WW.textSec)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.route_rounded, size: 18, color: WW.teal),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _distanceCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: WW.text),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    hintText: '0.0',
                    hintStyle: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: WW.border),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Text('km',
                  style: TextStyle(fontSize: 14, color: WW.textSec)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _notesField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              _FieldLabel('NOTES'),
              SizedBox(width: 4),
              Text('(optional)',
                  style: TextStyle(fontSize: 11, color: WW.textSec)),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _notesCtrl,
            maxLines: null,
            minLines: 3,
            style:
                const TextStyle(fontSize: 14, color: WW.text, height: 1.5),
            decoration: const InputDecoration(
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
              hintText: 'Optional notes...',
              hintStyle: TextStyle(fontSize: 14, color: WW.border),
            ),
          ),
        ],
      ),
    );
  }

  // ── Calorie estimate card ─────────────────────────────────────────────────────

  Widget _buildCalCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: WW.tealBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.local_fire_department_rounded,
              size: 20, color: WW.teal),
          const SizedBox(width: 10),
          Text(
            '~$_estimatedCals kcal estimated',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: WW.teal,
            ),
          ),
        ],
      ),
    );
  }

  // ── Activity list (no activity selected) ─────────────────────────────────────

  Widget _buildActivityList() {
    final results = _searchResults;

    if (results != null) {
      return results.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('No activities found',
                    style: TextStyle(fontSize: 13, color: WW.textSec)),
              ),
            )
          : Container(
              decoration: WW.cardDecoration,
              clipBehavior: Clip.hardEdge,
              child: Column(
                children: List.generate(
                  results.length,
                  (i) => _ActivityRow(
                    activity: results[i],
                    onTap: () => _selectActivity(results[i]),
                    showBorder: i > 0,
                  ),
                ),
              ),
            );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _kCatalogue.map((cat) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionLabel(cat.title),
              const SizedBox(height: 6),
              Container(
                decoration: WW.cardDecoration,
                clipBehavior: Clip.hardEdge,
                child: Column(
                  children: List.generate(cat.activities.length, (i) {
                    final act = cat.activities[i];
                    return _ActivityRow(
                      activity: act,
                      onTap: () => _selectActivity(act),
                      showBorder: i > 0,
                    );
                  }),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ── Sticky save button ────────────────────────────────────────────────────────

  Widget _buildStickyButton() {
    final Color bg;
    final Color fg;
    final String label;
    Widget? leading;

    if (_saveState == 'saved') {
      bg = const Color(0xFF22C55E);
      fg = Colors.white;
      label = 'Saved!';
      leading = const Icon(Icons.check_rounded, size: 16, color: Colors.white);
    } else if (_canSave || _saveState == 'loading') {
      bg = WW.primary;
      fg = Colors.white;
      label = _saveState == 'loading' ? 'Saving...' : 'Log Activity';
      if (_saveState == 'loading') {
        leading = const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
        );
      }
    } else {
      bg = const Color(0xFFE8EAF8);
      fg = WW.textSec;
      label = 'Log Activity';
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
            onTap: _canSave ? _save : null,
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (leading != null) ...[leading, const SizedBox(width: 8)],
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: fg,
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

// ── Shared helper widgets ──────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: WW.textSec,
          letterSpacing: 0.5,
        ),
      );
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: WW.textSec,
          letterSpacing: 0.5,
        ),
      );
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) =>
      Container(height: 0.5, color: const Color(0xFFE8EAF8));
}

class _ActivityRow extends StatelessWidget {
  final _Activity activity;
  final VoidCallback onTap;
  final bool showBorder;

  const _ActivityRow({
    required this.activity,
    required this.onTap,
    required this.showBorder,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 60,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: showBorder
            ? const BoxDecoration(
                border: Border(
                  top: BorderSide(color: Color(0xFFE8EAF8), width: 0.5),
                ),
              )
            : null,
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: activity.color,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Icon(activity.icon, size: 18, color: Colors.white),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    activity.label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: WW.text,
                    ),
                  ),
                  Text(
                    activity.desc,
                    style:
                        const TextStyle(fontSize: 12, color: WW.textSec),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                size: 16, color: WW.border),
          ],
        ),
      ),
    );
  }
}
