// lib/utils/image_encode.dart
// Shared downscale-and-base64-encode helper — same technique as
// nutrition_scan_screen.dart's/post_session_summary_screen.dart's own
// _encodeImageForPost() (dart:ui's instantiateImageCodec, no extra
// image-compression package needed), extracted here rather than adding
// a third hand-copied version for profile photos. Those two screens'
// existing private copies are left untouched — not broken, not in scope
// to refactor — this is only consumed by new code going forward.
//
// encodeCapturedCardBase64() (bottom of this file) is a separate helper
// specifically for the Post-to-Feed share-card path — it uses
// package:image (already a project dependency — see
// outdoor_cardio_screen.dart's own map-snapshot JPEG encoding) rather
// than dart:ui's PNG-only encoder, since that path's content is always
// photographic/map imagery. Deliberately NOT folded into
// encodeImageBytesBase64 below, which stays exactly as-is for its
// existing callers (profile/meal photos, the Share-flow's photo picker)
// — this task was scoped to share-card quality only.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;

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

// Highest safe base64 length for a share-card image field inside a
// Firestore document, comfortably under the ~1 MiB (1,048,576 byte) hard
// document cap — leaves generous headroom for the rest of a post's other
// fields (caption, session stats, timestamps — all trivially small next
// to the image) rather than targeting the ceiling exactly.
const int _kMaxCardImageBase64Length = 900 * 1024;

// Encodes a captured share-card PNG (see widget_capture.dart's
// captureWidgetAsPngBytes(), called at 1080x1920 real pixels for the
// Post-to-Feed path) for a Firestore write, trading resolution/quality
// down only as far as needed to fit under the budget above — same
// compress-until-under-threshold approach outdoor_cardio_screen.dart's
// _captureMapSnapshot() already uses for its own map thumbnails, just
// with a much larger budget since a share card is the actual shared
// content, not a small supporting thumbnail.
//
// JPEG instead of PNG: this always receives photographic/map card
// content (a real photo background, or map tiles), and PNG's lossless
// compression is dramatically less byte-efficient than JPEG's for that
// kind of content — switching formats alone lets a much higher
// resolution/quality survive the same byte budget that previously forced
// a blurry 240px PNG (encodeImageBytesBase64's old default for this same
// call site). Uses package:image (already a dependency, not a new one —
// see outdoor_cardio_screen.dart's own JPEG map-snapshot encoding) since
// dart:ui's ImageByteFormat has no JPEG option.
//
// Share (native OS share sheet, see post_session_summary_screen.dart's
// _shareCard()/activity_detail_screen.dart's _shareCard()) has no
// Firestore size constraint and stays full-resolution PNG — this is only
// used on the Post-to-Feed path.
Future<String?> encodeCapturedCardBase64(Uint8List pngBytes) async {
  try {
    final decoded = img.decodeImage(pngBytes);
    if (decoded == null) return null;

    const attempts = [
      (width: 1080, quality: 90),
      (width: 1080, quality: 80),
      (width: 900, quality: 80),
      (width: 720, quality: 78),
      (width: 540, quality: 75),
      (width: 360, quality: 70),
      (width: 240, quality: 60),
    ];
    for (final attempt in attempts) {
      final resized = attempt.width < decoded.width
          ? img.copyResize(decoded, width: attempt.width)
          : decoded;
      final jpegBytes = img.encodeJpg(resized, quality: attempt.quality);
      final encoded = base64Encode(jpegBytes);
      if (encoded.length <= _kMaxCardImageBase64Length) return encoded;
    }
    // Every attempt, down to the smallest/lowest-quality one, still
    // exceeded the budget — drop the image rather than risk the
    // [cloud_firestore/invalid-argument] oversized-document error (see
    // this project's own prior bug history with exactly that failure
    // mode on this same posting path).
    return null;
  } catch (_) {
    return null;
  }
}
