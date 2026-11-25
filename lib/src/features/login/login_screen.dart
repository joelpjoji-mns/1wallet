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
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxHeight < 650;
                  return BrandPageViewport(
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? AppSpacing.md : AppSpacing.xxl,
                      vertical: compact ? AppSpacing.xs : AppSpacing.md,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: AppPanel(
                            glass: true,
                            radius: AppRadii.pill,
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                              vertical: AppSpacing.xs,
                            ),
                            child: Text(
                              'SIGN IN',
                              style: textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: 2,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.6),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          height: compact ? AppSpacing.xs : AppSpacing.md,
                        ),
                        StaggeredFadeIn(
                          child: Text(
                            compact ? '1Wallet.' : 'Welcome.\n1Wallet.',
                            style:
                                (compact
                                        ? textTheme.displaySmall
                                        : textTheme.displayMedium)
                                    ?.copyWith(
                                      fontWeight: FontWeight.w900,
                                      height: 0.95,
                                      letterSpacing: -2.5,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                          ),
                        ),
                        SizedBox(
                          height: compact ? AppSpacing.sm : AppSpacing.md,
                        ),
                        StaggeredFadeIn(
                          delay: const Duration(milliseconds: 100),
                          child: Text(
                            compact
                                ? 'Track, plan, and grow your money effortlessly.'
                                : 'A smarter way to track, plan, and grow your money effortlessly.',
                            style:
                                (compact
                                        ? textTheme.bodyLarge
                                        : textTheme.titleLarge)
                                    ?.copyWith(
                                      fontWeight: FontWeight.w400,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.6),
                                      height: compact ? 1.4 : 1.5,
                                    ),
                          ),
                        ),
                        const Spacer(),
                        const SizedBox(height: AppSpacing.md),
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
                              padding: EdgeInsets.all(
                                compact ? AppSpacing.md : AppSpacing.xl,
                              ),
                              borderRadius: AppRadii.xl,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    unavailable
                                        ? 'Sync offline'
                                        : 'Ready to start?',
                                    style:
                                        (compact
                                                ? textTheme.titleLarge
                                                : textTheme.headlineMedium)
                                            ?.copyWith(
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
                                    style:
                                        (compact
                                                ? textTheme.bodyMedium
                                                : textTheme.bodyLarge)
                                            ?.copyWith(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurface
                                                  .withValues(alpha: 0.6),
                                              height: 1.4,
                                            ),
                                  ),
                                  SizedBox(
                                    height: compact
                                        ? AppSpacing.md
                                        : AppSpacing.xl,
                                  ),
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
                                          height: compact ? 56 : 64,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: AppSpacing.md,
                                          ),
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
                                    SizedBox(
                                      height: compact
                                          ? AppSpacing.sm
                                          : AppSpacing.lg,
                                    ),
                                    AppPanel(
                                      glass: true,
                                      radius: AppRadii.md,
                                      padding: const EdgeInsets.all(
                                        AppSpacing.md,
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.error_outline_rounded,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.error,
                                            size: 20,
                                          ),
                                          const SizedBox(width: AppSpacing.sm),
                                          Expanded(
                                            child: Text(
                                              auth.errorMessage!,
                                              textAlign: TextAlign.start,
                                              style: textTheme.bodyMedium
                                                  ?.copyWith(
                                                    color: Theme.of(
                                                      context,
                                                    ).colorScheme.error,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        StaggeredFadeIn(
                          delay: const Duration(milliseconds: 260),
                          child: Center(
                            child: AppPanel(
                              glass: true,
                              radius: AppRadii.pill,
                              padding: EdgeInsets.zero,
                              child: TextButton.icon(
                                key: LoginScreen.offlineButtonKey,
                                onPressed: auth.isSigningIn
                                    ? null
                                    : () => showOfflineModeSheet(context),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.lg,
                                    vertical: AppSpacing.sm,
                                  ),
                                ),
                                icon: const Icon(Icons.phonelink_lock_outlined),
                                label: const Text(
                                  'Use offline',
                                  semanticsLabel:
                                      'Use without an account (Offline)',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const Spacer(),
                        const SizedBox(height: AppSpacing.xs),
                        Center(
                          child: AppPanel(
                            glass: true,
                            radius: AppRadii.pill,
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                              vertical: AppSpacing.xs,
                            ),
                            child: Text(
                              'Secure • Private • Local First',
                              textAlign: TextAlign.center,
                              style: textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.5),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
