// lib/services/nutrition_service.dart
// Handles AI food recognition — both photo scan and manual text description.
// Relays through the analyzeNutrition Cloud Function (functions/index.js)
// instead of calling OpenAI directly — the API key now lives server-side as
// a Cloud Functions secret (shared with callWiseCoachOpenAI), never in the
// app bundle. Same model/params/system-prompt/content-array shape as
// before; only WHERE the OpenAI call happens has changed.
// NEVER call the OpenAI API directly from a screen — always go through here.

import 'dart:convert';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';

// ── Result model ─────────────────────────────────────────────────────────────

class NutritionResult {
  final bool recognized;
  final String foodName;
  final int calories;
  final int? proteinG;
  final int? carbsG;
  final int? fatG;
  final String confidence; // 'high' | 'medium' | 'low'
  final String? message; // shown when recognized == false

  const NutritionResult({
    required this.recognized,
    required this.foodName,
    required this.calories,
    this.proteinG,
    this.carbsG,
    this.fatG,
    this.confidence = 'medium',
    this.message,
  });

  factory NutritionResult.fromJson(Map<String, dynamic> json) {
    return NutritionResult(
      recognized: json['recognized'] == true,
      foodName: (json['foodName'] as String?)?.trim().isNotEmpty == true
          ? json['foodName'] as String
          : 'Unknown food',
      calories: (json['calories'] as num?)?.round() ?? 0,
      proteinG: (json['proteinG'] as num?)?.round(),
      carbsG: (json['carbsG'] as num?)?.round(),
      fatG: (json['fatG'] as num?)?.round(),
      confidence: (json['confidence'] as String?) ?? 'medium',
      message: json['message'] as String?,
    );
  }
}

class NutritionServiceException implements Exception {
  final String message;
  NutritionServiceException(this.message);
  @override
  String toString() => message;
}

// ── Service ──────────────────────────────────────────────────────────────────

class NutritionService {
  static const String _jsonSchemaInstructions = '''
Respond with ONLY a single JSON object — no markdown, no code fences, no extra text.
Schema:
{
  "recognized": boolean,       // false if you cannot identify a food item at all
  "foodName": string,          // best-guess name, e.g. "Fried egg", "Cheeseburger"
  "calories": number,          // estimated total calories (kcal) for the visible/described portion
  "proteinG": number,          // estimated grams of protein
  "carbsG": number,            // estimated grams of carbohydrates
  "fatG": number,              // estimated grams of fat
  "confidence": "high" | "medium" | "low",
  "message": string            // short 1-sentence note, e.g. portion assumption; or, if recognized is false, a brief explanation shown to the user
}
All numeric fields must still be present (use 0) even when recognized is false.''';

  // Relays through the analyzeNutrition Cloud Function instead of calling
  // OpenAI directly — same system prompt/content-array shape as before;
  // only WHERE the call happens has changed. The function itself hardcodes
  // model/max_tokens/temperature server-side (they never varied per-call
  // here), so the client only ever sends `messages`.
  Future<Map<String, dynamic>> _post(List<Map<String, dynamic>> content) async {
    final callable =
        FirebaseFunctions.instance.httpsCallable('analyzeNutrition');
    try {
      final result = await callable.call<Map<String, dynamic>>({
        'messages': [
          {
            'role': 'system',
            'content':
                '''You are the nutrition scanner inside the WiseWorkout app. You estimate calories and macros for a single meal or food item from either a photo or a text description. Be a reasonable, practical estimator — assume a typical single-serving portion when portion size is unclear. $_jsonSchemaInstructions''',
          },
          {'role': 'user', 'content': content},
        ],
      });
      return result.data;
    } catch (_) {
      // Was previously two distinct client-detectable cases (missing key /
      // non-200 OpenAI response) — now a single Cloud-Function-call
      // failure, since the client can no longer distinguish "key missing"
      // from "OpenAI errored" from "network error" once the call moves
      // server-side. Matches coach_screen.dart's own generic fallback
      // wording style from its equivalent migration.
      throw NutritionServiceException(
          'AI nutrition scanning is unavailable right now. Please try again.');
    }
  }

  NutritionResult _parse(Map<String, dynamic> data) {
    final raw = data['content'] as String;
    // Defensive: strip accidental code fences if the model adds them anyway.
    final cleaned = raw.trim().replaceAll(RegExp(r'^```json|^```|```$'), '').trim();
    try {
      final parsed = jsonDecode(cleaned) as Map<String, dynamic>;
      return NutritionResult.fromJson(parsed);
    } catch (_) {
      throw NutritionServiceException(
          'Could not read the AI response. Please try again.');
    }
  }

  // ---------------------------------------------------------------------------
  // Analyzes a food photo. If the AI can't confidently identify any food,
  // the returned result has recognized == false — the caller should fall
  // back to analyzeFoodDescription() with user-entered text.
  // ---------------------------------------------------------------------------
  Future<NutritionResult> analyzeFoodImage(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    final base64Image = base64Encode(bytes);
    final ext = imageFile.path.split('.').last.toLowerCase();
    final mimeType = (ext == 'png') ? 'image/png' : 'image/jpeg';

    final data = await _post([
      {
        'type': 'text',
        'text':
            'Identify the food in this photo and estimate its calories and macros.',
      },
      {
        'type': 'image_url',
        'image_url': {'url': 'data:$mimeType;base64,$base64Image'},
      },
    ]);

    return _parse(data);
  }

  // ---------------------------------------------------------------------------
  // Analyzes a plain-text food description (fallback path when a photo scan
  // fails to recognize the food, or when the user just wants to type it in).
  // ---------------------------------------------------------------------------
  Future<NutritionResult> analyzeFoodDescription(String description) async {
    final data = await _post([
      {
        'type': 'text',
        'text':
            'Estimate calories and macros for this food description: "$description"',
      },
    ]);

    return _parse(data);
  }
}
