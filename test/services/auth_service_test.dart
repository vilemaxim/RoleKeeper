import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in_mocks/google_sign_in_mocks.dart';

import 'package:rolekeeper/services/auth_service.dart';

void main() {
  group('AuthService', () {
    group('authStateChanges', () {
      test('emits null when signed out', () async {
        final auth = MockFirebaseAuth(signedIn: false);
        final service = AuthService(auth: auth, isWeb: true);

        final states = <User?>[];
        final sub = service.authStateChanges.listen(states.add);

        await Future<void>.delayed(Duration.zero);
        expect(states, [null]);
        await sub.cancel();
      });

      test('emits user when signed in', () async {
        final user = MockUser(uid: 'uid', email: 'a@b.com', displayName: 'Alice');
        final auth = MockFirebaseAuth(mockUser: user, signedIn: true);
        final service = AuthService(auth: auth, isWeb: true);

        final states = <User?>[];
        final sub = service.authStateChanges.listen(states.add);

        await Future<void>.delayed(Duration.zero);
        expect(states.length, 1);
        expect(states.first?.uid, 'uid');
        expect(states.first?.email, 'a@b.com');
        await sub.cancel();
      });
    });

    group('currentUser', () {
      test('returns null when signed out', () {
        final auth = MockFirebaseAuth(signedIn: false);
        final service = AuthService(auth: auth, isWeb: true);
        expect(service.currentUser, isNull);
      });

      test('returns user when signed in', () {
        final user = MockUser(uid: 'uid', displayName: 'Bob');
        final auth = MockFirebaseAuth(mockUser: user, signedIn: true);
        final service = AuthService(auth: auth, isWeb: true);
        expect(service.currentUser?.uid, 'uid');
        expect(service.currentUser?.displayName, 'Bob');
      });
    });

    group('signInWithGoogle (web)', () {
      test('signs in via popup and returns user', () async {
        final user = MockUser(uid: 'web-uid', email: 'web@test.com');
        final auth = MockFirebaseAuth(mockUser: user, signedIn: false);
        final service = AuthService(auth: auth, isWeb: true);

        final result = await service.signInWithGoogle();

        expect(result.user?.uid, 'web-uid');
        expect(result.user?.email, 'web@test.com');
        expect(auth.currentUser, isNotNull);
      });
    });

    group('signInWithGoogle (native)', () {
      test('signs in via credential and returns user', () async {
        final user = MockUser(uid: 'native-uid', email: 'native@test.com');
        final auth = MockFirebaseAuth(mockUser: user, signedIn: false);
        final googleSignIn = MockGoogleSignIn();
        final service = AuthService(
          auth: auth,
          googleSignIn: googleSignIn,
          isWeb: false,
        );

        final result = await service.signInWithGoogle();

        expect(result.user?.uid, 'native-uid');
        expect(result.user?.email, 'native@test.com');
      });

      test('throws when user cancels sign-in', () async {
        final auth = MockFirebaseAuth(signedIn: false);
        final googleSignIn = MockGoogleSignIn()..setIsCancelled(true);
        final service = AuthService(
          auth: auth,
          googleSignIn: googleSignIn,
          isWeb: false,
        );

        expect(
          service.signInWithGoogle(),
          throwsA(isA<FirebaseAuthException>().having(
            (e) => e.code,
            'code',
            'canceled',
          )),
        );
      });
    });

    group('signOut', () {
      test('clears Firebase currentUser', () async {
        final user = MockUser(uid: 'uid');
        final auth = MockFirebaseAuth(mockUser: user, signedIn: true);
        final service = AuthService(auth: auth, isWeb: true);

        expect(service.currentUser, isNotNull);
        await service.signOut();
        expect(service.currentUser, isNull);
      });

      test('authStateChanges emits null after signOut (web)', () async {
        final user = MockUser(uid: 'uid', email: 'a@b.com');
        final auth = MockFirebaseAuth(mockUser: user, signedIn: true);
        final service = AuthService(auth: auth, isWeb: true);

        final emissions = <User?>[];
        final sub = service.authStateChanges.listen(emissions.add);
        await Future<void>.delayed(Duration.zero);
        emissions.clear();

        await service.signOut();
        await Future<void>.delayed(Duration.zero);

        expect(emissions.isNotEmpty, isTrue);
        expect(emissions.last, isNull);
        await sub.cancel();
      });

      test('native signOut clears Firebase after Google sign-out', () async {
        final user = MockUser(uid: 'native', email: 'n@test.com');
        final auth = MockFirebaseAuth(mockUser: user, signedIn: true);
        final google = MockGoogleSignIn();
        final service = AuthService(
          auth: auth,
          googleSignIn: google,
          isWeb: false,
        );

        await service.signInWithGoogle();
        expect(service.currentUser, isNotNull);

        await service.signOut();
        expect(service.currentUser, isNull);
      });
    });
  });
}
