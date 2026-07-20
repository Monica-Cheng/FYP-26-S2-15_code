// lib/services/barcode_service.dart
// Looks up packaged-food nutrition data by barcode using Open Food Facts —
// a free, public, no-API-key-required food database. More accurate than AI
// photo guessing for packaged products, since it's reading the manufacturer's
// actual declared nutrition label, not estimating from a photo.
//
// NOTE: Open Food Facts nutriment values are reported per 100g, not per
// serving. We surface that honestly in the UI rather than pretending it's
// a single-serving estimate.

import 'dart:convert';

import 'package:http/http.dart' as http;

class BarcodeProduct {
  final String barcode;
  final bool found;
  final String name;
  final int calories; // per 100g
  final int? proteinG; // per 100g
  final int? carbsG; // per 100g
  final int? fatG; // per 100g

  const BarcodeProduct({
    required this.barcode,
    required this.found,
    required this.name,
    required this.calories,
    this.proteinG,
    this.carbsG,
    this.fatG,
  });

  factory BarcodeProduct.notFound(String barcode) => BarcodeProduct(
        barcode: barcode,
        found: false,
        name: 'Unknown product',
        calories: 0,
      );
}

class BarcodeServiceException implements Exception {
  final String message;
  BarcodeServiceException(this.message);
  @override
  String toString() => message;
}

class BarcodeService {
  static const _fields =
      'product_name,nutriments,image_front_small_url,brands';

  Future<BarcodeProduct> lookupBarcode(String barcode) async {
    final uri = Uri.parse(
      'https://world.openfoodfacts.org/api/v2/product/$barcode.json?fields=$_fields',
    );

    late final http.Response response;
    try {
      response = await http.get(uri).timeout(const Duration(seconds: 10));
    } catch (e) {
      throw BarcodeServiceException(
          'Could not reach the food database. Check your connection.');
    }

    if (response.statusCode != 200) {
      throw BarcodeServiceException(
          'Barcode lookup failed (${response.statusCode}).');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final status = data['status'];
    if (status != 1 || data['product'] == null) {
      return BarcodeProduct.notFound(barcode);
    }

    final product = data['product'] as Map<String, dynamic>;
    final nutriments = (product['nutriments'] as Map<String, dynamic>?) ?? {};

    final rawName = (product['product_name'] as String?)?.trim();
    final brand = (product['brands'] as String?)?.split(',').first.trim();
    final name = (rawName != null && rawName.isNotEmpty)
        ? rawName
        : (brand != null && brand.isNotEmpty ? brand : 'Unnamed product');

    int? asInt(dynamic v) => v == null ? null : (v as num).round();

    final calories = asInt(nutriments['energy-kcal_100g']) ?? 0;

    return BarcodeProduct(
      barcode: barcode,
      found: true,
      name: name,
      calories: calories,
      proteinG: asInt(nutriments['proteins_100g']),
      carbsG: asInt(nutriments['carbohydrates_100g']),
      fatG: asInt(nutriments['fat_100g']),
    );
  }
}
