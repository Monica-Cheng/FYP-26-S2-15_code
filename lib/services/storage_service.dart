// lib/services/storage_service.dart
// Handles Firebase Storage uploads — NEVER import firebase_storage
// directly in a screen or widget, same convention as
// firestore_service.dart's own header comment for cloud_firestore.
//
// Currently used only for coach registration credential documents (see
// coach_register_screen.dart). Deliberately separate from
// FirestoreService, which is Firestore-only — this app's other images
// (profile photos, meal photos, share cards) all go through the
// base64-in-Firestore pattern instead (see lib/utils/image_encode.dart),
// which is fine for decorative photos but was judged unsuitable here: a
// credential document's entire value is that an admin can read fine
// print on it (institution, certification title, dates), and the
// compression that pattern needs to fit Firestore's ~1 MiB document cap
// would risk making that text illegible. Firebase Storage has no
// comparable size ceiling, so uploads here stay at their original
// resolution/quality.

import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // Uploads one credential file for [uid]'s coach application and
  // returns its public download URL. Filename is timestamped (not the
  // original picked filename) so re-applying after a rejection, or
  // picking two files with the same name, can never collide/overwrite
  // an earlier upload.
  //
  // Explicit contentType (rather than leaving it to putFile's own
  // inference, which isn't reliable across platforms) so a PDF opens
  // inline/downloads correctly from its URL — e.g. in a browser, on the
  // admin dashboard side — instead of arriving as a generic
  // application/octet-stream blob. Same path/upload mechanism regardless
  // of file type: a PDF is just a different extension through this same
  // method, no separate logic needed.
  Future<String> uploadCredentialFile(String uid, File file) async {
    final ext = file.path.contains('.')
        ? file.path.split('.').last.toLowerCase()
        : 'jpg';
    final contentType = switch (ext) {
      'pdf' => 'application/pdf',
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      _ => 'application/octet-stream',
    };
    final ref = _storage
        .ref()
        .child('businessPartners')
        .child(uid)
        .child('credentials')
        .child('${DateTime.now().millisecondsSinceEpoch}.$ext');
    final task = await ref.putFile(file, SettableMetadata(contentType: contentType));
    return task.ref.getDownloadURL();
  }

  // Uploads every file in [files] for [uid]'s application, in order.
  // Fails fast (throws) on the first failed upload rather than silently
  // submitting a partial credential set — see coach_register_screen
  // .dart's _submit(), which surfaces this as the same submission error
  // as any other registration failure.
  Future<List<String>> uploadCredentialFiles(String uid, List<File> files) async {
    final urls = <String>[];
    for (final file in files) {
      urls.add(await uploadCredentialFile(uid, file));
    }
    return urls;
  }
}
