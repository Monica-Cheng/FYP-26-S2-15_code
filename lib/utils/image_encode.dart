// lib/utils/image_encode.dart
// Shared downscale-and-base64-encode helper — same technique as
// nutrition_scan_screen.dart's/post_session_summary_screen.dart's own
// _encodeImageForPost() (dart:ui's instantiateImageCodec, no extra
// image-compression package needed), extracted here rather than adding
// a third hand-copied version for profile photos. Those two screens'
// existing private copies are left untouched — not broken, not in scope
// to refactor — this is only consumed by new code going forward.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

// Returns null (caller should treat this as "no photo") rather than
// throwing if anything in the decode/encode pipeline fails — a bad
// photo shouldn't be able to crash whatever flow is attaching it.
Future<String?> encodeImageBase64(File file, {int targetWidth = 480}) async {
  try {
    final bytes = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: targetWidth);
    final frame = await codec.getNextFrame();
    final byteData = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return null;
    return base64Encode(byteData.buffer.asUint8List());
  } catch (_) {
    return null;
  }
}
