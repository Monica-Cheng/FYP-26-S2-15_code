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
import 'dart:typed_data';
import 'dart:ui' as ui;

// Returns null (caller should treat this as "no photo") rather than
// throwing if anything in the decode/encode pipeline fails — a bad
// photo shouldn't be able to crash whatever flow is attaching it.
Future<String?> encodeImageBase64(File file, {int targetWidth = 480}) async {
  try {
    final bytes = await file.readAsBytes();
    return await encodeImageBytesBase64(bytes, targetWidth: targetWidth);
  } catch (_) {
    return null;
  }
}

// Same downscale-and-base64-encode as encodeImageBase64, but for PNG
// bytes already in memory (e.g. lib/utils/widget_capture.dart's captured
// share-card output) rather than a File — added when a captured share
// card's full-resolution PNG (1080x1920 real pixels, PNG compresses
// photographic/map content poorly) turned out able to exceed Firestore's
// ~1 MiB per-document limit once base64-encoded, which surfaces as an
// invalid-argument error on the write. Default targetWidth is much
// smaller than encodeImageBase64's own 480 default — verified via
// test/capture_size_test.dart that even 480 isn't reliably safe for a
// worst-case (busy/noisy) captured card background; 240 leaves real
// margin under the 1 MiB cap alongside the post's other fields.
Future<String?> encodeImageBytesBase64(Uint8List bytes, {int targetWidth = 240}) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: targetWidth);
    final frame = await codec.getNextFrame();
    final byteData = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return null;
    return base64Encode(byteData.buffer.asUint8List());
  } catch (_) {
    return null;
  }
}
