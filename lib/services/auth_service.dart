// lib/services/auth_service.dart
// Handles ALL Firebase Authentication calls for WiseWorkout.
// NEVER import firebase_auth directly in a screen or widget — always go through this service.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  // ---------------------------------------------------------------------------
  // Sign in with email and password.
  // Returns a UserCredential on success.
  // Throws FirebaseAuthException on failure (e.g. wrong password, user not found).
  // ---------------------------------------------------------------------------
  Future<UserCredential> signInWithEmailPassword(
    String email,
    String password,
  ) async {
    return await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  // ---------------------------------------------------------------------------
  // Sign in with Google.
  // Opens the Google account picker. Returns a UserCredential on success.
  // Returns null if the user dismisses the picker without selecting an account.
  // ---------------------------------------------------------------------------
  Future<UserCredential?> signInWithGoogle() async {
    final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

    // User cancelled the sign-in flow.
    if (googleUser == null) return null;

    final GoogleSignInAuthentication googleAuth =
        await googleUser.authentication;

    final AuthCredential credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    return await _auth.signInWithCredential(credential);
  }

  // ---------------------------------------------------------------------------
  // Register a new account with email and password.
  // Returns a UserCredential on success.
  // Throws FirebaseAuthException on failure (e.g. email already in use, weak password).
  // ---------------------------------------------------------------------------
  Future<UserCredential> registerWithEmailPassword(
    String email,
    String password,
  ) async {
    return await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  // ---------------------------------------------------------------------------
  // Sign out of both Firebase Auth and Google Sign-In.
  // Call this from a logout button — it clears all active sessions.
  // ---------------------------------------------------------------------------
  Future<void> signOut() async {
    await Future.wait([
      _auth.signOut(),
      _googleSignIn.signOut(),
    ]);
  }

  // ---------------------------------------------------------------------------
  // Returns the currently signed-in Firebase user, or null if not logged in.
  // Use this for a one-time synchronous check of auth state.
  // ---------------------------------------------------------------------------
  User? getCurrentUser() {
    return _auth.currentUser;
  }

  // ---------------------------------------------------------------------------
  // Sends a password reset email to the given address.
  // Throws FirebaseAuthException if the email is not registered or invalid.
  // ---------------------------------------------------------------------------
  Future<void> sendPasswordReset(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  // ---------------------------------------------------------------------------
  // Whether the current user's sign-in provider is Google (vs email/
  // password) — checked via user.providerData, not the account's email
  // domain (a gmail.com address could still be a password account). This
  // app never links providers together (no linkWithCredential call site
  // exists), so a signed-in user always has exactly one entry here. Used by
  // settings_screen.dart's Change Email flow to pick the correct
  // re-authentication method before a security-sensitive operation.
  // ---------------------------------------------------------------------------
  bool isGoogleSignInUser() {
    final user = _auth.currentUser;
    if (user == null) return false;
    return user.providerData
        .any((p) => p.providerId == GoogleAuthProvider.PROVIDER_ID);
  }

  // ---------------------------------------------------------------------------
  // Re-authenticates an email/password user with their current password —
  // required before a security-sensitive operation (e.g. changeEmail()
  // below). Throws FirebaseAuthException on failure (e.g. wrong-password).
  // ---------------------------------------------------------------------------
  Future<void> reauthenticateWithPassword(String password) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('No signed-in user.');
    final email = user.email;
    if (email == null) throw StateError('Current user has no email.');
    final credential =
        EmailAuthProvider.credential(email: email, password: password);
    await user.reauthenticateWithCredential(credential);
  }

  // ---------------------------------------------------------------------------
  // Re-authenticates a Google user via a fresh Google sign-in — same
  // GoogleSignIn instance/credential-building as signInWithGoogle() above,
  // required before a security-sensitive operation (e.g. changeEmail()
  // below). Returns null if the user cancels the picker without completing
  // it (same convention as signInWithGoogle()'s own cancel case) — callers
  // should treat that as "re-auth not completed," not an error.
  // ---------------------------------------------------------------------------
  Future<UserCredential?> reauthenticateWithGoogle() async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('No signed-in user.');
    final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
    if (googleUser == null) return null;
    final GoogleSignInAuthentication googleAuth =
        await googleUser.authentication;
    final AuthCredential credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    return await user.reauthenticateWithCredential(credential);
  }

  // ---------------------------------------------------------------------------
  // Sends a verification email to [newEmail]. The signed-in user's email is
  // NOT updated immediately — it only changes once they click the
  // verification link in that email (see settings_screen.dart's confirmation
  // copy, which must not claim the change already happened).
  //
  // updateEmail() is deprecated in this Firebase Auth version in favor of
  // this method — deliberately not used.
  //
  // Caller must have re-authenticated the user immediately before calling
  // this (see reauthenticateWithPassword()/reauthenticateWithGoogle()
  // above) — this is a security-sensitive operation and can throw
  // FirebaseAuthException with code 'requires-recent-login' otherwise.
  // ---------------------------------------------------------------------------
  Future<void> changeEmail(String newEmail) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('No signed-in user.');
    await user.verifyBeforeUpdateEmail(newEmail);
  }

  // ---------------------------------------------------------------------------
  // Deletes the signed-in user's Firebase Auth account. Must only be called
  // AFTER FirestoreService.deleteUserAccount() has already succeeded — that
  // Cloud Function deletes this user's Firestore data while request.auth.uid
  // still resolves to a real account; calling this first would strand that
  // cleanup half-done with no way to re-authenticate as the now-deleted uid.
  //
  // Same requires-recent-login gate as changeEmail() above — caller must
  // have re-authenticated via reauthenticateWithPassword()/
  // reauthenticateWithGoogle() immediately before calling this, or it throws
  // FirebaseAuthException with code 'requires-recent-login'.
  // ---------------------------------------------------------------------------
  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('No signed-in user.');
    await user.delete();
  }

  // ---------------------------------------------------------------------------
  // Returns a stream that emits the current user whenever auth state changes
  // (sign-in, sign-out, token refresh). Use this to reactively respond to
  // login/logout events — typically consumed by a Riverpod StreamProvider.
  // ---------------------------------------------------------------------------
  Stream<User?> authStateChanges() {
    return _auth.authStateChanges();
  }
}
