import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../config/firebase_env.dart';
import 'app_mode.dart';
import 'auth_user.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository();
});

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>(
  (ref) {
    return AuthController(
      ref.watch(authRepositoryProvider),
      appModeStore: ref.watch(appModeStoreProvider),
    );
  },
);

/// The storage mode the current session runs in, derived from [AuthState] so
/// it always agrees with routing and ownership decisions.
final appModeProvider = Provider<AppMode>((ref) {
  final localOnly = ref.watch(
    authControllerProvider.select((state) => state.isLocalOnly),
  );
  return localOnly ? AppMode.offline : AppMode.online;
});

/// [localOnly] is offline mode: the wallet is owned by [localOwnerId], no
/// Firebase user is published, and cloud sync stays disabled.
enum AuthPhase { initializing, signedOut, signedIn, unavailable, localOnly }

@immutable
class AuthState {
  const AuthState({
    required this.phase,
    required this.googleSignInAvailable,
    this.user,
    this.isSigningIn = false,
    this.errorMessage,
    this.localDisplayName,
    this.localOwnershipVerified = false,
  });

  const AuthState.initializing()
    : phase = AuthPhase.initializing,
      googleSignInAvailable = false,
      user = null,
      isSigningIn = false,
      errorMessage = null,
      localDisplayName = null,
      localOwnershipVerified = false;

  final AuthPhase phase;

  /// The Firebase user. Always null in offline mode so no cloud code path
  /// (which all key off this field) can run for a local-only wallet.
  final AuthUser? user;
  final bool googleSignInAvailable;
  final bool isSigningIn;
  final String? errorMessage;
  final String? localDisplayName;

  /// Offline mode only: whether startup confirmed the stored wallet belongs to
  /// [localOwnerId] (and not to a Google account from an interrupted upgrade).
  final bool localOwnershipVerified;

  bool get isReady => phase != AuthPhase.initializing;

  bool get isAuthenticated => phase == AuthPhase.signedIn && user != null;

  bool get isLocalOnly => phase == AuthPhase.localOnly;

  /// The owner of the active wallet: the Firebase uid when signed in, or
  /// [localOwnerId] in offline mode.
  String? get ownerId => user?.id ?? (isLocalOnly ? localOwnerId : null);

  /// Identity to display in profile UI, including the synthetic local owner.
  AuthUser? get profileUser =>
      user ??
      (isLocalOnly ? AuthUser.local(displayName: localDisplayName) : null);

  AuthState copyWith({
    AuthPhase? phase,
    Object? user = _unset,
    bool? googleSignInAvailable,
    bool? isSigningIn,
    Object? errorMessage = _unset,
    Object? localDisplayName = _unset,
    bool? localOwnershipVerified,
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
      localDisplayName: identical(localDisplayName, _unset)
          ? this.localDisplayName
          : localDisplayName as String?,
      localOwnershipVerified:
          localOwnershipVerified ?? this.localOwnershipVerified,
    );
  }
}

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._repository, {AppModeStore? appModeStore})
    : _appModeStore = appModeStore ?? AppModeStore(),
      super(const AuthState.initializing()) {
    _start();
  }

  final AuthRepository _repository;
  final AppModeStore _appModeStore;
  StreamSubscription<AuthUser?>? _subscription;
  bool _verifyingLocalOwner = false;
  bool _upgradeInFlight = false;

  void _start() {
    if (_appModeStore.mode == AppMode.offline) {
      // Offline mode never waits on Firebase: it must open with no network
      // and even when Firebase is not configured at all.
      state = AuthState(
        phase: AuthPhase.localOnly,
        googleSignInAvailable: _googleAvailable,
        localDisplayName: _appModeStore.localDisplayName,
      );
      return;
    }
    _startOnline();
  }

  bool get _googleAvailable {
    try {
      return _repository.availability.available;
    } catch (_) {
      return false;
    }
  }

  void _startOnline() {
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

    _subscribe();
  }

  /// [signedOutNotice] stays visible while no user is signed in (Firebase
  /// re-emits the signed-out state on subscription) and is cleared by the
  /// first sign-in.
  void _subscribe({String? signedOutNotice}) {
    _subscription?.cancel();
    var notice = signedOutNotice;
    _subscription = _repository.authStateChanges.listen(
      (user) {
        if (user != null) notice = null;
        state = state.copyWith(
          phase: user == null ? AuthPhase.signedOut : AuthPhase.signedIn,
          user: user,
          googleSignInAvailable: true,
          isSigningIn: false,
          errorMessage: user == null ? notice : null,
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

  /// Switches this device to offline mode from the signed-out entry screen.
  ///
  /// The caller must first ensure the stored wallet is owned by
  /// [localOwnerId] (see `OfflineModeController.enterOfflineMode`). Firebase
  /// Auth is never touched: no anonymous account is created.
  Future<bool> continueOffline() async {
    if (state.isAuthenticated || state.isSigningIn || state.isLocalOnly) {
      return state.isLocalOnly;
    }
    try {
      await _appModeStore.setMode(AppMode.offline);
    } catch (error) {
      if (!mounted) return false;
      state = state.copyWith(
        errorMessage: 'Could not switch to offline mode. Please try again.',
      );
      return false;
    }
    if (!mounted) return false;
    await _subscription?.cancel();
    _subscription = null;
    if (!mounted) return false;
    state = AuthState(
      phase: AuthPhase.localOnly,
      googleSignInAvailable: _googleAvailable,
      localDisplayName: _appModeStore.localDisplayName,
      localOwnershipVerified: true,
    );
    return true;
  }

  /// Signs in with Google for an offline → Google upgrade WITHOUT publishing
  /// the account: the session stays [AuthPhase.localOnly] until
  /// [completeOfflineUpgrade] so the ledger and cloud sync never observe the
  /// new uid before the local wallet has been migrated to it.
  Future<AuthUser> signInWithGoogleForUpgrade() async {
    if (!state.isLocalOnly) {
      throw const AuthFailure('Offline mode is not active on this device.');
    }
    if (state.isSigningIn) {
      throw const AuthFailure('Google sign-in is already in progress.');
    }
    final availability = _repository.availability;
    if (!availability.available) {
      throw AuthFailure(
        availability.message ?? 'Google sign-in is unavailable right now.',
      );
    }
    state = state.copyWith(isSigningIn: true, errorMessage: null);
    try {
      final user = await _repository.signInWithGoogle();
      if (user == null) {
        throw const AuthFailure('Google sign-in was cancelled.');
      }
      _upgradeInFlight = true;
      return user;
    } catch (error) {
      throw AuthFailure(_friendlyError(error));
    } finally {
      if (mounted) state = state.copyWith(isSigningIn: false);
    }
  }

  /// Publishes [user] after the local wallet was migrated to its uid and
  /// persists [AppMode.online] first, so a restart never reopens offline mode
  /// on a wallet that already belongs to the Google account.
  Future<void> completeOfflineUpgrade(AuthUser user) async {
    await _appModeStore.setMode(AppMode.online);
    _upgradeInFlight = false;
    if (!mounted) return;
    state = AuthState(
      phase: AuthPhase.signedIn,
      user: user,
      googleSignInAvailable: true,
    );
    _subscribe();
  }

  /// Drops a Google session that was opened for an upgrade the user did not
  /// finish. Offline mode and the local wallet are left untouched.
  Future<void> discardUpgradeSession() async {
    _upgradeInFlight = false;
    try {
      await _repository.signOut();
    } catch (error) {
      debugPrint('Could not discard the upgrade session: ${error.runtimeType}');
    }
  }

  /// Startup check for offline mode: offline mode may only open a wallet
  /// owned by [localOwnerId].
  ///
  /// A wallet owned by a Google uid means an upgrade was interrupted after the
  /// wallet was migrated; it is finished when that same Google session still
  /// exists, otherwise the device returns to the sign-in screen so the data
  /// is only ever shown to its owner. Nothing is deleted.
  Future<void> verifyLocalOwnership(String ledgerOwner) async {
    final ownedLocally = ledgerOwner.isEmpty || ledgerOwner == localOwnerId;
    if (!state.isLocalOnly ||
        (state.localOwnershipVerified && ownedLocally) ||
        _verifyingLocalOwner ||
        _upgradeInFlight) {
      return;
    }
    _verifyingLocalOwner = true;
    try {
      final firebaseUser = _repository.currentUser;
      if (ownedLocally) {
        // A Google session left by an abandoned upgrade is never published
        // (nothing offline reads it) and the next upgrade replaces it. It is
        // deliberately not discarded here: this check can run before the
        // persisted wallet finished loading, and that session is exactly what
        // finishes an upgrade that was interrupted after the wallet moved.
        state = state.copyWith(localOwnershipVerified: true);
        return;
      }
      if (firebaseUser != null && firebaseUser.id == ledgerOwner) {
        await completeOfflineUpgrade(firebaseUser);
        return;
      }
      if (firebaseUser != null) await discardUpgradeSession();
      await _appModeStore.setMode(AppMode.online);
      if (!mounted) return;
      final available = _googleAvailable;
      const notice =
          'This device holds a wallet linked to a Google account. '
          'Sign in with that account to open it.';
      state = AuthState(
        phase: available ? AuthPhase.signedOut : AuthPhase.unavailable,
        googleSignInAvailable: available,
        errorMessage: notice,
      );
      if (available) _subscribe(signedOutNotice: notice);
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(
        localOwnershipVerified: false,
        errorMessage: 'Could not verify the offline wallet on this device.',
      );
    } finally {
      _verifyingLocalOwner = false;
    }
  }

  /// Lets startup re-run [verifyLocalOwnership] after it failed.
  void retryLocalOwnershipCheck() {
    if (!state.isLocalOnly || state.localOwnershipVerified) return;
    state = state.copyWith(errorMessage: null);
  }

  Future<void> setLocalDisplayName(String name) async {
    if (!state.isLocalOnly) return;
    await _appModeStore.setLocalDisplayName(name);
    if (!mounted) return;
    final trimmed = name.trim();
    state = state.copyWith(localDisplayName: trimmed.isEmpty ? null : trimmed);
  }

  Future<void> signInWithGoogle() async {
    // Offline mode upgrades go through OfflineModeController so the local
    // wallet is migrated before the Google uid becomes visible.
    if (state.isSigningIn || state.isLocalOnly) return;
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
    if (state.isSigningIn || state.isLocalOnly) return;
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
    // There is no account to leave in offline mode; signing "out" would only
    // strand the device-only wallet behind the sign-in screen.
    if (state.isLocalOnly) return;
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
