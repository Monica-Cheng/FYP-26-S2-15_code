// lib/services/nutrition_service.dart
// Handles AI food recognition — both photo scan and manual text description.
// Uses the same OpenAI account/key already configured for WiseCoach
// (see lib/screens/coach/coach_screen.dart and .env: OPENAI_API_KEY).
// NEVER call the OpenAI API directly from a screen — always go through here.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

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
  static const String _endpoint =
      'https://api.openai.com/v1/chat/completions';

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

  String get _apiKey => dotenv.env['OPENAI_API_KEY'] ?? '';

  Future<Map<String, dynamic>> _post(List<Map<String, dynamic>> content) async {
    if (_apiKey.isEmpty) {
      throw NutritionServiceException(
          'AI nutrition scanning is not configured (missing OPENAI_API_KEY).');
    }

    final response = await http.post(
      Uri.parse(_endpoint),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_apiKey',
      },
      body: jsonEncode({
        'model': 'gpt-4o-mini',
        'messages': [
          {
            'role': 'system',
            'content':
                '''You are the nutrition scanner inside the WiseWorkout app. You estimate calories and macros for a single meal or food item from either a photo or a text description. Be a reasonable, practical estimator — assume a typical single-serving portion when portion size is unclear. $_jsonSchemaInstructions''',
          },
          {'role': 'user', 'content': content},
        ],
        'max_tokens': 300,
        'temperature': 0.3,
      }),
    );

    if (response.statusCode != 200) {
      throw NutritionServiceException(
          'AI request failed (${response.statusCode}). Please try again.');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  NutritionResult _parse(Map<String, dynamic> data) {
    final raw = data['choices'][0]['message']['content'] as String;
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
