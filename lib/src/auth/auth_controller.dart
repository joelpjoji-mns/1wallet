import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../config/firebase_env.dart';
import 'auth_user.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository();
});

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>(
  (ref) {
    return AuthController(ref.watch(authRepositoryProvider));
  },
);

enum AuthPhase { initializing, signedOut, signedIn, unavailable }

@immutable
class AuthState {
  const AuthState({
    required this.phase,
    required this.googleSignInAvailable,
    this.user,
    this.isSigningIn = false,
    this.errorMessage,
  });

  const AuthState.initializing()
    : phase = AuthPhase.initializing,
      googleSignInAvailable = false,
      user = null,
      isSigningIn = false,
      errorMessage = null;

  final AuthPhase phase;
  final AuthUser? user;
  final bool googleSignInAvailable;
  final bool isSigningIn;
  final String? errorMessage;

  bool get isReady => phase != AuthPhase.initializing;

  bool get isAuthenticated => phase == AuthPhase.signedIn && user != null;

  AuthState copyWith({
    AuthPhase? phase,
    Object? user = _unset,
    bool? googleSignInAvailable,
    bool? isSigningIn,
    Object? errorMessage = _unset,
  }) {
    return AuthState(
      phase: phase ?? this.phase,
      user: identical(user, _unset) ? this.user : user as AuthUser?,
      googleSignInAvailable:
          googleSignInAvailable ?? this.googleSignInAvailable,
      isSigningIn: isSigningIn ?? this.isSigningIn,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
    );
  }
}

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._repository) : super(const AuthState.initializing()) {
    _start();
  }

  final AuthRepository _repository;
  StreamSubscription<AuthUser?>? _subscription;

  void _start() {
    final availability = _repository.availability;
    if (!availability.available) {
      state = AuthState(
        phase: AuthPhase.unavailable,
        googleSignInAvailable: false,
        errorMessage: availability.message,
      );
      return;
    }

    final initialUser = _repository.currentUser;
    if (initialUser != null) {
      state = AuthState(
        phase: AuthPhase.signedIn,
        user: initialUser,
        googleSignInAvailable: true,
      );
    }

    _subscription = _repository.authStateChanges.listen(
      (user) {
        state = state.copyWith(
          phase: user == null ? AuthPhase.signedOut : AuthPhase.signedIn,
          user: user,
          googleSignInAvailable: true,
          isSigningIn: false,
          errorMessage: null,
        );
      },
      onError: (Object error) {
        state = AuthState(
          phase: AuthPhase.signedOut,
          googleSignInAvailable: true,
          errorMessage: _friendlyError(error),
        );
      },
    );
  }

  Future<void> signInWithGoogle() async {
    if (state.isSigningIn) return;
    final availability = _repository.availability;
    if (!availability.available) {
      state = state.copyWith(
        phase: AuthPhase.unavailable,
        googleSignInAvailable: false,
        isSigningIn: false,
        errorMessage: availability.message,
      );
      return;
    }

    state = state.copyWith(isSigningIn: true, errorMessage: null);
    try {
      final user = await _repository.signInWithGoogle();
      if (!mounted) return;
      if (user == null) {
        state = state.copyWith(
          phase: AuthPhase.signedOut,
          user: null,
          isSigningIn: false,
          errorMessage: 'Google sign-in was cancelled.',
        );
        return;
      }
      state = state.copyWith(
        phase: AuthPhase.signedIn,
        user: user,
        isSigningIn: false,
        errorMessage: null,
      );
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(
        isSigningIn: false,
        errorMessage: _friendlyError(error),
      );
    }
  }

  Future<void> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    await _runEmailPasswordAction(
      () =>
          _repository.signInWithEmailPassword(email: email, password: password),
    );
  }

  Future<void> createEmailPasswordAccount({
    required String email,
    required String password,
  }) async {
    await _runEmailPasswordAction(
      () => _repository.createEmailPasswordAccount(
        email: email,
        password: password,
      ),
    );
  }

  Future<void> _runEmailPasswordAction(
    Future<AuthUser?> Function() task,
  ) async {
    if (state.isSigningIn) return;
    if (!FirebaseEnv.emailPasswordAuthEnabled) {
      state = state.copyWith(
        errorMessage: 'Email/password sign-in is available only for QA builds.',
      );
      return;
    }
    final availability = _repository.availability;
    if (!availability.available) {
      state = state.copyWith(
        phase: AuthPhase.unavailable,
        googleSignInAvailable: false,
        isSigningIn: false,
        errorMessage: availability.message,
      );
      return;
    }

    state = state.copyWith(isSigningIn: true, errorMessage: null);
    try {
      final user = await task();
      if (!mounted) return;
      state = state.copyWith(
        phase: user == null ? AuthPhase.signedOut : AuthPhase.signedIn,
        user: user,
        isSigningIn: false,
        errorMessage: null,
      );
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(
        isSigningIn: false,
        errorMessage: _friendlyError(error),
      );
    }
  }

  Future<void> signOut({bool rethrowOnError = false}) async {
    try {
      await _repository.signOut();
      if (!mounted) return;
      state = state.copyWith(
        phase: AuthPhase.signedOut,
        user: null,
        isSigningIn: false,
        errorMessage: null,
      );
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(errorMessage: _friendlyError(error));
      if (rethrowOnError) rethrow;
    }
  }

  Future<String> reauthenticateForDeletion() async {
    final expected = state.user?.id;
    if (expected == null) {
      throw const AuthFailure('Sign in before deleting your account.');
    }
    final token = await _repository.reauthenticateForDeletion();
    if (!mounted || state.user?.id != expected) {
      throw const AuthFailure('The signed-in account changed.');
    }
    return token;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

class AuthRepository {
  Future<String> reauthenticateForDeletion() async {
    final user = firebase_auth.FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw const AuthFailure('Sign in before deleting your account.');
    }
    final google = user.providerData.any(
      (provider) => provider.providerId == 'google.com',
    );
    if (google && !await _reauthenticate(user)) {
      throw const AuthFailure('Re-authentication was cancelled.');
    }
    if (!google) {
      final signedInAt = user.metadata.lastSignInTime;
      if (signedInAt == null ||
          DateTime.now().difference(signedInAt) > const Duration(minutes: 5)) {
        throw const AuthFailure(
          'Sign in again before requesting account deletion.',
        );
      }
    }
    final token = await user.getIdToken(true);
    if (token == null ||
        firebase_auth.FirebaseAuth.instance.currentUser?.uid != user.uid) {
      throw const AuthFailure('Could not verify the account for deletion.');
    }
    return token;
  }

  AuthAvailability get availability {
    if (Firebase.apps.isEmpty) {
      return AuthAvailability.unavailable(FirebaseEnv.configurationSummary());
    }
    if (!FirebaseEnv.googleSignInConfigured) {
      return const AuthAvailability.unavailable(
        'Google sign-in is missing a client ID in `.env`.',
      );
    }
    return const AuthAvailability.available();
  }

  AuthUser? get currentUser {
    try {
      if (Firebase.apps.isEmpty) return null;
      return AuthUser.fromFirebaseUser(
        firebase_auth.FirebaseAuth.instance.currentUser,
      );
    } catch (_) {
      return null;
    }
  }

  Stream<AuthUser?> get authStateChanges => firebase_auth.FirebaseAuth.instance
      .authStateChanges()
      .map(AuthUser.fromFirebaseUser);

  Future<AuthUser?> signInWithGoogle() async {
    final googleSignIn = GoogleSignIn(
      scopes: const ['email', 'profile'],
      clientId: FirebaseEnv.googleClientIdForPlatform,
      serverClientId: kIsWeb ? null : FirebaseEnv.googleWebClientId,
    );

    final googleUser = await googleSignIn.signIn();
    if (googleUser == null) return null;

    final googleAuth = await googleUser.authentication;
    if (googleAuth.idToken == null && googleAuth.accessToken == null) {
      throw const AuthFailure(
        'Google did not return a token. Check the OAuth client IDs in `.env`.',
      );
    }

    final credential = firebase_auth.GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    final result = await firebase_auth.FirebaseAuth.instance
        .signInWithCredential(credential);
    return AuthUser.fromFirebaseUser(result.user);
  }

  Future<AuthUser?> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    final result = await firebase_auth.FirebaseAuth.instance
        .signInWithEmailAndPassword(email: email.trim(), password: password);
    return AuthUser.fromFirebaseUser(result.user);
  }

  Future<AuthUser?> createEmailPasswordAccount({
    required String email,
    required String password,
  }) async {
    final result = await firebase_auth.FirebaseAuth.instance
        .createUserWithEmailAndPassword(
          email: email.trim(),
          password: password,
        );
    return AuthUser.fromFirebaseUser(result.user);
  }

  Future<void> signOut() async {
    await Future.wait([
      firebase_auth.FirebaseAuth.instance.signOut(),
      GoogleSignIn().signOut(),
    ]);
  }

  Future<bool> _reauthenticate(firebase_auth.User user) async {
    final isGoogle = user.providerData.any((p) => p.providerId == 'google.com');
    if (isGoogle) {
      final googleSignIn = GoogleSignIn(
        scopes: const ['email', 'profile'],
        clientId: FirebaseEnv.googleClientIdForPlatform,
        serverClientId: kIsWeb ? null : FirebaseEnv.googleWebClientId,
      );
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) return false;

      final googleAuth = await googleUser.authentication;
      if (googleAuth.idToken == null && googleAuth.accessToken == null) {
        throw const AuthFailure(
          'Google did not return a token. Check the OAuth client IDs in `.env`.',
        );
      }
      final credential = firebase_auth.GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await user.reauthenticateWithCredential(credential);
      return true;
    }
    return false;
  }
}

@immutable
class AuthAvailability {
  const AuthAvailability.available() : available = true, message = null;

  const AuthAvailability.unavailable(this.message) : available = false;

  final bool available;
  final String? message;
}

class AuthFailure implements Exception {
  const AuthFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

const _unset = Object();

String _friendlyError(Object error) {
  if (error is AuthFailure) return error.message;
  if (error is firebase_auth.FirebaseAuthException) {
    return switch (error.code) {
      'requires-recent-login' =>
        'Deleting your account requires recent authentication. Please sign in again.',
      'account-exists-with-different-credential' =>
        'That Google email is already linked to another sign-in method.',
      'invalid-credential' || 'wrong-password' =>
        'Those credentials were not accepted. Please try again.',
      'user-not-found' => 'No account exists for that email.',
      'email-already-in-use' => 'An account already exists for that email.',
      'weak-password' => 'Choose a stronger password for this QA account.',
      'invalid-email' => 'Enter a valid email address.',
      'operation-not-allowed' =>
        'Email/password sign-in is disabled in Firebase for this project.',
      'network-request-failed' =>
        'Network unavailable while contacting Firebase. Check your connection.',
      _ => error.message ?? 'Firebase sign-in failed (${error.code}).',
    };
  }
  if (error is PlatformException) {
    return switch (error.code) {
      'sign_in_canceled' ||
      'SIGN_IN_CANCELLED' => 'Google sign-in was cancelled.',
      'sign_in_failed' =>
        'Google sign-in failed. Check Play Services and OAuth configuration.',
      'network_error' => 'Network unavailable while signing in with Google.',
      _ => error.message ?? 'Google sign-in failed (${error.code}).',
    };
  }
  if (kDebugMode) return error.toString();
  return 'Sign-in failed. Please try again.';
}
