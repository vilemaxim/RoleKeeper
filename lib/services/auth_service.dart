import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

import 'game_context_service.dart';

/// Handles authentication with Google Sign-In.
/// Email/password may be added later for LARP Manager integration.
class AuthService {
  AuthService({
    FirebaseAuth? auth,
    GoogleSignIn? googleSignIn,
    bool? isWeb,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _isWeb = isWeb ?? kIsWeb,
        _googleSignIn = ((isWeb ?? kIsWeb) ? null : (googleSignIn ?? GoogleSignIn()));

  final FirebaseAuth _auth;
  final bool _isWeb;
  final GoogleSignIn? _googleSignIn;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  /// Sign in with Google. Returns the UserCredential on success.
  /// Web: uses Firebase signInWithPopup (no client ID needed).
  /// Native: uses google_sign_in + signInWithCredential.
  Future<UserCredential> signInWithGoogle() async {
    if (_isWeb) {
      return _auth.signInWithPopup(GoogleAuthProvider());
    }

    final googleSignIn = _googleSignIn!;
    final googleUser = await googleSignIn.signIn();
    if (googleUser == null) {
      throw FirebaseAuthException(
        code: 'canceled',
        message: 'Sign in was canceled',
      );
    }

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    return _auth.signInWithCredential(credential);
  }

  /// Signs out of Firebase Auth and clears the Google session so the next sign-in
  /// must pick an account again (native: [GoogleSignIn]; web: singleton [GoogleSignIn]).
  Future<void> signOut() async {
    await _auth.signOut();
    GameContextService.instance.clearGameContext();

    final googleSignIn = _googleSignIn;
    if (!_isWeb && googleSignIn != null) {
      try {
        await googleSignIn.signOut();
      } catch (_) {
        // Still treat Firebase sign-out as success.
      }
      try {
        await googleSignIn.disconnect();
      } catch (_) {
        // Optional; may throw if there was no Google session.
      }
      return;
    }

    if (_isWeb) {
      try {
        await GoogleSignIn().signOut();
      } catch (_) {
        // Web may not have a google_sign_in session; ignore.
      }
    }
  }
}
