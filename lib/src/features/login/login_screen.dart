import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_controller.dart';
import '../../design/tokens.dart';
import '../../widgets/app_kit.dart';
import '../launch/brand_widgets.dart';
import 'offline_mode_sheet.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  static const offlineButtonKey = Key('login-use-offline');

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    ref.listen<AuthState>(authControllerProvider, (previous, next) {
      if (next.errorMessage == null ||
          next.errorMessage == previous?.errorMessage) {
        return;
      }
      showAppSnackBar(context, next.errorMessage!);
    });

    final unavailable = !auth.googleSignInAvailable;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: LaunchBackdrop(
        child: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Row(
                      children: [
                        const SizedBox(width: 48),
                        const Spacer(),
                        Text(
                          'SIGN IN',
                          style: textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.4),
                          ),
                        ),
                        const Spacer(),
                        const SizedBox(width: 48),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xxl,
                      ),
                      children: [
                        const SizedBox(height: AppSpacing.xxl + AppSpacing.xs),
                        StaggeredFadeIn(
                          child: Text(
                            'Welcome.\n1Wallet.',
                            style: textTheme.displayMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              height: 0.95,
                              letterSpacing: -2.5,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        StaggeredFadeIn(
                          delay: const Duration(milliseconds: 100),
                          child: Text(
                            'A smarter way to track, plan, and grow your money effortlessly.',
                            style: textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w400,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.6),
                              height: 1.5,
                            ),
                          ),
                        ),
                        const SizedBox(
                          height: AppSpacing.xxl * 2 + AppSpacing.md,
                        ),
                        StaggeredFadeIn(
                          delay: const Duration(milliseconds: 200),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 40,
                                  offset: const Offset(0, 20),
                                ),
                              ],
                            ),
                            child: BrandFrostedPanel(
                              padding: const EdgeInsets.all(AppSpacing.xxl),
                              borderRadius: AppRadii.xl,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    unavailable
                                        ? 'Sync offline'
                                        : 'Ready to start?',
                                    style: textTheme.headlineMedium?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.sm),
                                  Text(
                                    unavailable
                                        ? 'Cloud sync is currently unavailable. You can still use the app locally.'
                                        : 'Sign in to sync your data securely across all your devices.',
                                    style: textTheme.bodyLarge?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.6),
                                      height: 1.4,
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.xxl),
                                  // Sign-in is unavailable (offline mode), so
                                  // dim the button — otherwise it looks fully
                                  // interactive even though onTap is null.
                                  AnimatedOpacity(
                                    duration: const Duration(milliseconds: 200),
                                    opacity: unavailable ? 0.5 : 1.0,
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: unavailable || auth.isSigningIn
                                            ? null
                                            : () => ref
                                                  .read(
                                                    authControllerProvider
                                                        .notifier,
                                                  )
                                                  .signInWithGoogle(),
                                        borderRadius: BorderRadius.circular(28),
                                        child: AnimatedContainer(
                                          duration: const Duration(
                                            milliseconds: 200,
                                          ),
                                          height: 64,
                                          decoration: BoxDecoration(
                                            color:
                                                Theme.of(context).brightness ==
                                                    Brightness.dark
                                                ? const Color(0xFF1F1F1F)
                                                : Colors.white,
                                            borderRadius: BorderRadius.circular(
                                              28,
                                            ),
                                            border: Border.all(
                                              color:
                                                  Theme.of(
                                                        context,
                                                      ).brightness ==
                                                      Brightness.dark
                                                  ? Colors.white.withValues(
                                                      alpha: 0.12,
                                                    )
                                                  : Colors.black.withValues(
                                                      alpha: 0.08,
                                                    ),
                                              width: 1.5,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withValues(
                                                  alpha: 0.06,
                                                ),
                                                blurRadius: 12,
                                                offset: const Offset(0, 4),
                                              ),
                                            ],
                                          ),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              if (auth.isSigningIn)
                                                AppInlineSpinner(
                                                  size: 24,
                                                  color: Theme.of(
                                                    context,
                                                  ).colorScheme.primary,
                                                )
                                              else
                                                ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                  child: Image.asset(
                                                    'assets/images/google_logo.png',
                                                    height: 24,
                                                    width: 24,
                                                  ),
                                                ),
                                              const SizedBox(
                                                width: AppSpacing.sm,
                                              ),
                                              Flexible(
                                                child: FittedBox(
                                                  fit: BoxFit.scaleDown,
                                                  child: Text(
                                                    auth.isSigningIn
                                                        ? 'Connecting...'
                                                        : 'Continue with Google',
                                                    maxLines: 1,
                                                    // Google sign-in branding:
                                                    // fixed 17sp Inter label.
                                                    style: TextStyle(
                                                      fontFamily: 'Inter',
                                                      fontSize: 17,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color:
                                                          Theme.of(
                                                                context,
                                                              ).brightness ==
                                                              Brightness.dark
                                                          ? Colors.white
                                                                .withValues(
                                                                  alpha: 0.87,
                                                                )
                                                          : const Color(
                                                              0xFF3C4043,
                                                            ),
                                                      letterSpacing: 0.1,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (auth.errorMessage != null &&
                                      !unavailable) ...[
                                    const SizedBox(height: AppSpacing.lg),
                                    Container(
                                      padding: const EdgeInsets.all(
                                        AppSpacing.md,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .errorContainer
                                            .withValues(alpha: 0.3),
                                        borderRadius: BorderRadius.circular(
                                          AppRadii.md,
                                        ),
                                      ),
                                      child: Text(
                                        auth.errorMessage!,
                                        textAlign: TextAlign.center,
                                        style: textTheme.bodyMedium?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.error,
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
                        const SizedBox(height: AppSpacing.lg),
                        StaggeredFadeIn(
                          delay: const Duration(milliseconds: 260),
                          child: Center(
                            child: TextButton.icon(
                              key: LoginScreen.offlineButtonKey,
                              onPressed: auth.isSigningIn
                                  ? null
                                  : () => showOfflineModeSheet(context),
                              icon: const Icon(Icons.phonelink_lock_outlined),
                              label: const Text(
                                'Use without an account (Offline)',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        Center(
                          child: Text(
                            'Secure • Private • Local First',
                            style: textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.3),
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
        ),
      ),
    );
  }
}
