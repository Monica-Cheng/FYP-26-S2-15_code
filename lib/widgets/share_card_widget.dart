import 'package:flutter/material.dart';
import '../core/app_theme.dart';

class ShareCardWidget extends StatelessWidget {
  final String sessionName;
  final bool isCardio;
  final String cardioActivity;
  final int elapsedSeconds;
  final int calories;
  final int totalSets;
  final double volume;
  final int goalMinutes;
  final DateTime date;

  const ShareCardWidget({
    super.key,
    required this.sessionName,
    required this.isCardio,
    required this.cardioActivity,
    required this.elapsedSeconds,
    required this.calories,
    required this.totalSets,
    required this.volume,
    required this.goalMinutes,
    required this.date,
  });

  String _fmtDuration(int secs) {
    final h = secs ~/ 3600;
    final m = (secs % 3600) ~/ 60;
    final s = secs % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m == 0) return '${s}s';
    return '${m}m ${s}s';
  }

  String _fmtDate(DateTime dt) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${days[dt.weekday - 1]}, ${dt.day} '
        '${months[dt.month - 1]} ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final durationStr = _fmtDuration(elapsedSeconds);
    final dateStr = _fmtDate(date);

    return Container(
      width: 360,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [WW.primaryDark, Color(0xFF4a4ea8)],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top header
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // WiseWorkout brand
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.fitness_center_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'WiseWorkout',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
                // Session type badge
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isCardio ? cardioActivity : 'Gym',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Session name
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              sessionName,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: -0.5,
                height: 1.2,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            dateStr,
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withOpacity(0.6),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 24),

          // Stats grid
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: isCardio
                ? _buildCardioStats(durationStr)
                : _buildGymStats(durationStr),
          ),
          const SizedBox(height: 24),

          // Bottom hashtag strip
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.2),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
            ),
            child: const Text(
              '#WiseWorkout  #FitForLife',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white70,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardioStats(String durationStr) {
    final goalStr = goalMinutes > 0
        ? (elapsedSeconds >= goalMinutes * 60
            ? 'Goal reached ✓'
            : '$goalMinutes min')
        : 'Open run';

    return Row(
      children: [
        _StatBox(value: durationStr, label: 'Duration'),
        const SizedBox(width: 10),
        _StatBox(value: '~$calories kcal', label: 'Calories'),
        const SizedBox(width: 10),
        _StatBox(value: goalStr, label: 'Goal'),
      ],
    );
  }

  Widget _buildGymStats(String durationStr) {
    return Row(
      children: [
        _StatBox(value: durationStr, label: 'Duration'),
        const SizedBox(width: 10),
        _StatBox(value: '~$calories kcal', label: 'Calories'),
        const SizedBox(width: 10),
        _StatBox(
            value: '${volume.round()} kg', label: 'Volume'),
      ],
    );
  }
}

class _StatBox extends StatelessWidget {
  final String value;
  final String label;

  const _StatBox({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Text(
              value,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Colors.white.withOpacity(0.65),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
