import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_controller.dart';
import '../../config/firebase_env.dart';
import '../../design/tokens.dart';
import '../launch/brand_widgets.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    ref.listen<AuthState>(authControllerProvider, (previous, next) {
      if (next.errorMessage == null ||
          next.errorMessage == previous?.errorMessage) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(next.errorMessage!),
            behavior: SnackBarBehavior.floating,
          ),
        );
    });

    final unavailable = !auth.googleSignInAvailable;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: LaunchBackdrop(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.xl,
              AppSpacing.lg,
              AppSpacing.xxl,
            ),
            children: [
              const SizedBox(height: AppSpacing.xl),
              const AnimatedBrandScene(
                compact: true,
                message: 'Continue to your money dashboard',
              ),
              const SizedBox(height: AppSpacing.xxl),
              _LoginPanel(
                unavailable: unavailable,
                isSigningIn: auth.isSigningIn,
                errorMessage: auth.errorMessage,
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: unavailable || auth.isSigningIn
                    ? null
                    : () => ref
                          .read(authControllerProvider.notifier)
                          .signInWithGoogle(),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(62),
                  backgroundColor: scheme.surface,
                  foregroundColor: scheme.onSurface,
                  disabledBackgroundColor: scheme.surfaceContainerHighest
                      .withAlphaFactor(0.5),
                  textStyle: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                icon: auth.isSigningIn
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      )
                    : const Text(
                        'G',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                label: Text(
                  auth.isSigningIn
                      ? 'Connecting Google…'
                      : 'Continue with Google',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ),
        ),
      ),
    );
  }

}

class _LoginPanel extends StatelessWidget {
  const _LoginPanel({
    required this.unavailable,
    required this.isSigningIn,
    required this.errorMessage,
  });

  final bool unavailable;
  final bool isSigningIn;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: scheme.primary.withAlphaFactor(0.10),
        borderRadius: BorderRadius.circular(AppRadii.xl),
        border: Border.all(color: scheme.primary.withAlphaFactor(0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            unavailable ? 'Config needed' : 'Sign in',
            style: const TextStyle(
              color: LaunchPalette.text,
              fontSize: 32,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            unavailable
                ? '${FirebaseEnv.configurationSummary()} Copy `.env.example` to `.env`, fill Firebase/Google client IDs, then restart.'
              : 'Use your Google account to sync and restore your wallet.',
            style: const TextStyle(
              color: LaunchPalette.mutedText,
              fontSize: 16,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (errorMessage != null && !unavailable) ...[
            const SizedBox(height: AppSpacing.md),
            _InlineError(message: errorMessage!),
          ],
        ],
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withAlphaFactor(0.55),
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: scheme.error.withAlphaFactor(0.35)),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: scheme.onErrorContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
