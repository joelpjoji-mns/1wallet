import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../auth/auth_controller.dart';
import '../launch/brand_widgets.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    ref.listen<AuthState>(authControllerProvider, (previous, next) {
      if (next.errorMessage == null || next.errorMessage == previous?.errorMessage) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(next.errorMessage!), behavior: SnackBarBehavior.floating));
    });

    final unavailable = !auth.googleSignInAvailable;

    return Scaffold(
      body: LaunchBackdrop(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Row(
                  children: [
                    const SizedBox(width: 48),
                    const Spacer(),
                    Text(
                      'SIGN IN',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        letterSpacing: 2,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  children: [
                    const SizedBox(height: 40),
                    StaggeredFadeIn(
                      child: Text(
                        'Welcome.\n1Wallet.',
                        style: GoogleFonts.outfit(
                          fontSize: 52,
                          fontWeight: FontWeight.w900,
                          height: 0.95,
                          letterSpacing: -2.5,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    StaggeredFadeIn(
                      delay: const Duration(milliseconds: 100),
                      child: Text(
                        'A smarter way to track, plan, and grow your money effortlessly.',
                        style: GoogleFonts.outfit(
                          fontSize: 19,
                          fontWeight: FontWeight.w400,
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                          height: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 80),
                    StaggeredFadeIn(
                      delay: const Duration(milliseconds: 200),
                      child: Container(
                        decoration: BoxDecoration(
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 40,
                              offset: const Offset(0, 20),
                            ),
                          ],
                        ),
                        child: GlassCard(
                          padding: const EdgeInsets.all(32),
                          borderRadius: 32, // More curves
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                unavailable ? 'Sync offline' : 'Ready to start?',
                                style: GoogleFonts.outfit(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                  color: Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                unavailable
                                    ? 'Cloud sync is currently unavailable. You can still use the app locally.'
                                    : 'Sign in to sync your data securely across all your devices.',
                                style: GoogleFonts.outfit(
                                  fontSize: 16,
                                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 32),
                              FilledButton.icon(
                                onPressed: unavailable || auth.isSigningIn
                                    ? null
                                    : () => ref.read(authControllerProvider.notifier).signInWithGoogle(),
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(64),
                                  backgroundColor: Theme.of(context).colorScheme.onSurface,
                                  foregroundColor: Theme.of(context).colorScheme.surface,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20), // Curvy button
                                  ),
                                ),
                                icon: auth.isSigningIn
                                    ? const SizedBox.square(
                                        dimension: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 3,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Text(
                                        'G',
                                        style: GoogleFonts.outfit(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                label: Text(
                                  auth.isSigningIn ? 'Connecting...' : 'Continue with Google',
                                  style: GoogleFonts.outfit(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (auth.errorMessage != null && !unavailable) ...[
                                const SizedBox(height: 20),
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.errorContainer.withOpacity(0.3),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Text(
                                    auth.errorMessage!,
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.outfit(
                                      color: Theme.of(context).colorScheme.error,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 48),
                    Center(
                      child: Text(
                        'Secure • Private • Local First',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1,
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

