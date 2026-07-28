import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/app_theme.dart';
import '../../services/firestore_service.dart';

class ExerciseDetailScreen extends StatefulWidget {
  final String exerciseName;
  final String muscle;

  const ExerciseDetailScreen({
    super.key,
    required this.exerciseName,
    required this.muscle,
  });

  @override
  State<ExerciseDetailScreen> createState() =>
      _ExerciseDetailScreenState();
}

class _ExerciseDetailScreenState extends State<ExerciseDetailScreen> {
  Map<String, dynamic>? _exercise;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    if (widget.exerciseName.isNotEmpty) {
      _loadExercise(widget.exerciseName);
    }
  }

  Future<void> _loadExercise(String name) async {
    final result = await FirestoreService().getExerciseDetail(name);
    if (mounted) {
      setState(() {
        _exercise = result;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WW.bg,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 260,
            pinned: true,
            backgroundColor: WW.primaryDark,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded,
                  color: Colors.white),
              onPressed: () => context.pop(),
            ),
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                widget.exerciseName,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              background: _buildImageArea(),
            ),
          ),
          SliverToBoxAdapter(
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.only(top: 80),
                    child: Center(
                      child: CircularProgressIndicator(
                          color: WW.primary),
                    ),
                  )
                : _buildBody(),
          ),
        ],
      ),
    );
  }

  Widget _buildImageArea() {
    final imageUrl = _exercise?['imageUrl'] as String? ?? '';
    return Container(
      color: WW.primaryDark,
      child: imageUrl.isNotEmpty
          ? Image.network(
              imageUrl,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => _buildImagePlaceholder(),
            )
          : _buildImagePlaceholder(),
    );
  }

  Widget _buildImagePlaceholder() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.fitness_center_rounded,
              color: Colors.white54,
              size: 40,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Animation coming soon',
            style: TextStyle(
              fontSize: 11,
              color: Colors.white38,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final exercise = _exercise;
    final instructions = exercise?['instructions'] as String? ?? '';
    final equipment = exercise?['equipment'] as String? ?? '';
    final difficulty = exercise?['difficulty'] as String? ?? '';
    final secondaryMuscles =
        (exercise?['secondaryMuscles'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Badges row
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (widget.muscle.isNotEmpty)
                _badge(widget.muscle, WW.primary, WW.chipBg),
              if (equipment.isNotEmpty)
                _badge(equipment, WW.textSec, WW.elevated),
              if (difficulty.isNotEmpty)
                _badge(difficulty, WW.textSec, WW.elevated),
            ],
          ),
          if (secondaryMuscles.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'Secondary Muscles',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: WW.text,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: secondaryMuscles
                  .map((m) => _badge(m, WW.textSec, WW.elevated))
                  .toList(),
            ),
          ],
          const SizedBox(height: 24),
          const Text(
            'How To',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: WW.primaryDark,
            ),
          ),
          const SizedBox(height: 12),
          if (exercise == null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: WW.elevated,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'No instructions available yet. Check back soon.',
                style: TextStyle(
                  fontSize: 13,
                  color: WW.textSec,
                  height: 1.5,
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: WW.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: WW.border, width: 0.5),
              ),
              child: Text(
                instructions.isNotEmpty
                    ? instructions
                    : 'No instructions available yet.',
                style: const TextStyle(
                  fontSize: 14,
                  color: WW.text,
                  height: 1.7,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _badge(String label, Color textColor, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }
}
