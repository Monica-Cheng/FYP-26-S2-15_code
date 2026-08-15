// lib/screens/plans/exercise_detail_screen.dart
// Shows instructions/muscle info for a single exercise, looked up by name
// from the exercise library. Reached by tapping an exercise while building
// or viewing a routine.

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

  // Prefers gifUrl (admin-added animated demo) over imageUrl (static
  // photo) when both are present, falling back to the placeholder if
  // neither exists yet — both fields are currently null on every seeded
  // exercise doc, real media sourcing is deferred to a teammate. A GIF is
  // just another image format as far as Image.network is concerned —
  // Flutter's built-in image codec decodes and animates multi-frame GIFs
  // automatically, so this reuses the exact same Image.network call
  // imageUrl already used, no new package or asset-loading logic needed.
  Widget _buildImageArea() {
    final gifUrl = _exercise?['gifUrl'] as String? ?? '';
    final imageUrl = _exercise?['imageUrl'] as String? ?? '';
    final mediaUrl = gifUrl.isNotEmpty ? gifUrl : imageUrl;
    return Container(
      color: WW.primaryDark,
      child: mediaUrl.isNotEmpty
          ? Image.network(
              mediaUrl,
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
    final rawSteps = exercise?['instructionSteps'];
    final instructionSteps = rawSteps is List
        ? rawSteps
            .map((e) => e.toString())
            .where((s) => s.trim().isNotEmpty)
            .toList()
        : <String>[];
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
          if (instructionSteps.isEmpty)
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List.generate(instructionSteps.length, (i) {
                  final isLast = i == instructionSteps.length - 1;
                  return Padding(
                    padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: WW.chipBg,
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Center(
                            child: Text(
                              '${i + 1}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: WW.primary,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              instructionSteps[i],
                              style: const TextStyle(
                                fontSize: 14,
                                color: WW.text,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
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
