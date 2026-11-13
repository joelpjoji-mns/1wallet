import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/foundation.dart';

import 'app_mode.dart';

@immutable
class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    this.displayName,
    this.photoUrl,
    this.provider = 'firebase',
  });

  /// Synthetic identity for offline mode. It is never published as
  /// `AuthState.user`; it only feeds profile UI.
  factory AuthUser.local({String? displayName}) => AuthUser(
    id: localOwnerId,
    email: 'Stored only on this device',
    displayName: (displayName?.trim().isNotEmpty ?? false)
        ? displayName!.trim()
        : null,
    provider: localProvider,
  );

  static const localProvider = 'local';

  final String id;
  final String email;
  final String? displayName;
  final String? photoUrl;
  final String provider;

  bool get isGoogleProvider => provider == 'google.com';

  bool get isPasswordProvider => provider == 'password';

  bool get isLocalProvider => provider == localProvider;

  String get providerLabel {
    return switch (provider) {
      'google.com' => 'Google',
      'password' => 'Email/password',
      localProvider => 'This device',
      _ => 'Firebase',
    };
  }

  String get initials {
    final name = displayName?.trim();
    if (isLocalProvider) {
      if (name != null && name.isNotEmpty) {
        final letterMatch = RegExp(r'[a-zA-Z0-9]').firstMatch(name);
        return (letterMatch?.group(0) ?? String.fromCharCode(name.runes.first))
            .toUpperCase();
      }
      return '1W';
    }
    final source = (name?.isNotEmpty ?? false) ? name! : email;
    final parts = source
        .split(RegExp(r'\s+|@'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '1W';
    return parts.take(2).map((part) => part[0].toUpperCase()).join();
  }

  static AuthUser? fromFirebaseUser(firebase_auth.User? user) {
    if (user == null) return null;
    return AuthUser(
      id: user.uid,
      email: user.email ?? 'Google account',
      displayName: user.displayName,
      photoUrl: user.photoURL,
      provider: _primaryProvider(user),
    );
  }

  static String _primaryProvider(firebase_auth.User user) {
    for (final provider in user.providerData) {
      if (provider.providerId == 'google.com') return provider.providerId;
    }
    if (user.providerData.isNotEmpty) return user.providerData.first.providerId;
    return 'firebase';
  }
}
