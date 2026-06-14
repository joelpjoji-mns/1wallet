import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
                      'Sign In',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    const StaggeredFadeIn(
                      child: Text(
                        'Welcome.\n1Wallet.',
                        style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, height: 1.1, letterSpacing: -1),
                      ),
                    ),
                    const SizedBox(height: 16),
                    StaggeredFadeIn(
                      delay: const Duration(milliseconds: 100),
                      child: Text(
                        'A smarter way to track, plan, and grow your money effortlessly.',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                          height: 1.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 64),
                    StaggeredFadeIn(
                      delay: const Duration(milliseconds: 200),
                      child: GlassCard(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              unavailable ? 'Sync unavailable' : 'Get Started',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              unavailable
                                  ? 'Cloud sync is currently offline. Please try again later.'
                                  : 'Connect your Google account to securely sync your data.',
                              style: TextStyle(
                                fontSize: 15,
                                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                              ),
                            ),
                            const SizedBox(height: 24),
                            FilledButton.icon(
                              onPressed: unavailable || auth.isSigningIn
                                  ? null
                                  : () => ref.read(authControllerProvider.notifier).signInWithGoogle(),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(60),
                                backgroundColor: Theme.of(context).colorScheme.primary,
                                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              icon: auth.isSigningIn
                                  ? const SizedBox.square(
                                      dimension: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                                    )
                                  : const Text('G', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
                              label: Text(auth.isSigningIn ? 'Connecting...' : 'Continue with Google'),
                            ),
                            if (auth.errorMessage != null && !unavailable) ...[
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.errorContainer.withOpacity(0.5),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  auth.errorMessage!,
                                  style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer, fontSize: 13),
                                ),
                              ),
                            ],
                          ],
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
