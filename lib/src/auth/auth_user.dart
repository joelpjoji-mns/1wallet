import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/foundation.dart';

@immutable
class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    this.displayName,
    this.photoUrl,
    this.provider = 'firebase',
  });

  final String id;
  final String email;
  final String? displayName;
  final String? photoUrl;
  final String provider;

  bool get isGoogleProvider => provider == 'google.com';

  bool get isPasswordProvider => provider == 'password';

  String get providerLabel {
    return switch (provider) {
      'google.com' => 'Google',
      'password' => 'Email/password',
      _ => 'Firebase',
    };
  }

  String get initials {
    final source = (displayName?.trim().isNotEmpty ?? false)
        ? displayName!.trim()
        : email;
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
