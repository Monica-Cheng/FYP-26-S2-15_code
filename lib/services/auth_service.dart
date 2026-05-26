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
  // Returns a stream that emits the current user whenever auth state changes
  // (sign-in, sign-out, token refresh). Use this to reactively respond to
  // login/logout events — typically consumed by a Riverpod StreamProvider.
  // ---------------------------------------------------------------------------
  Stream<User?> authStateChanges() {
    return _auth.authStateChanges();
  }
}
