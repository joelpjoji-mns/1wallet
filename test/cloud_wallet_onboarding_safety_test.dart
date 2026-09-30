import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:one_wallet_flutter/src/auth/auth_controller.dart';
import 'package:one_wallet_flutter/src/auth/auth_user.dart';
import 'package:one_wallet_flutter/src/cloud_sync/cloud_sync_controller.dart';
import 'package:one_wallet_flutter/src/data/ledger_defaults.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/features/onboarding/onboarding_controller.dart';
import 'package:one_wallet_flutter/src/features/settings/permission_setup_controller.dart';
import 'package:one_wallet_flutter/src/startup/startup_state.dart';
import 'package:one_wallet_flutter/src/theme/theme_controller.dart';

class _FakeThemeController extends StateNotifier<AppThemeState>
    implements ThemeController {
  _FakeThemeController(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuthController extends StateNotifier<AuthState>
    implements AuthController {
  _FakeAuthController(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLedgerController extends StateNotifier<LedgerState>
    implements LedgerController {
  _FakeLedgerController(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCloudSyncController extends StateNotifier<CloudSyncState>
    implements CloudSyncController {
  _FakeCloudSyncController(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  const testUserId = 'test-user-123';
  final authenticatedState = AuthState(
    phase: AuthPhase.signedIn,
    googleSignInAvailable: true,
    user: const AuthUser(id: testUserId, email: 'user@example.com'),
  );

  test('startupState routes to home when local ledger has wallet data', () {
    final container = ProviderContainer(
      overrides: [
        themeControllerProvider.overrideWith(
          (ref) => _FakeThemeController(const AppThemeState(isLoaded: true)),
        ),
        authControllerProvider.overrideWith(
          (ref) => _FakeAuthController(authenticatedState),
        ),
        ledgerLoadStateProvider.overrideWith(
          (ref) => const LedgerLoadState.ready(hasPersistedLedger: true),
        ),
        ledgerProvider.overrideWith(
          (ref) => _FakeLedgerController(
            emptyLedgerState().copyWith(
              accounts: [
                Account(
                  id: 'acc-1',
                  name: 'Checking',
                  type: 'checking',
                  currency: 'INR',
                  openingBalance: Money(amountMinor: 1000, currency: 'INR'),
                ),
              ],
            ),
          ),
        ),
        permissionSetupControllerProvider.overrideWith(
          (ref) => PermissionSetupController()
            ..state = const PermissionSetupState(
              userId: testUserId,
              completed: true,
            ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final startup = container.read(startupStateProvider);
    expect(startup.destination, StartupDestination.home);
  });

  test('startupState routes to home when onboarding is already completed, even if ledger is empty', () {
    final container = ProviderContainer(
      overrides: [
        themeControllerProvider.overrideWith(
          (ref) => _FakeThemeController(const AppThemeState(isLoaded: true)),
        ),
        authControllerProvider.overrideWith(
          (ref) => _FakeAuthController(authenticatedState),
        ),
        ledgerLoadStateProvider.overrideWith(
          (ref) => const LedgerLoadState.ready(hasPersistedLedger: false),
        ),
        ledgerProvider.overrideWith(
          (ref) => _FakeLedgerController(emptyLedgerState()),
        ),
        permissionSetupControllerProvider.overrideWith(
          (ref) => PermissionSetupController()
            ..state = const PermissionSetupState(
              userId: testUserId,
              completed: true,
            ),
        ),
        cloudSyncControllerProvider.overrideWith(
          (ref) => _FakeCloudSyncController(
            const CloudSyncState(
              phase: CloudSyncPhase.idle,
              bootstrapComplete: true,
              bootstrappedUserId: testUserId,
              hasCloudWallet: false,
            ),
          ),
        ),
        onboardingControllerProvider.overrideWith(
          (ref) => OnboardingController()
            ..state = const OnboardingState(
              userId: testUserId,
              completed: true,
            ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final startup = container.read(startupStateProvider);
    expect(startup.destination, StartupDestination.home);
  });

  test('startupState NEVER routes to onboarding when cloud wallet exists in Firebase', () {
    final container = ProviderContainer(
      overrides: [
        themeControllerProvider.overrideWith(
          (ref) => _FakeThemeController(const AppThemeState(isLoaded: true)),
        ),
        authControllerProvider.overrideWith(
          (ref) => _FakeAuthController(authenticatedState),
        ),
        ledgerLoadStateProvider.overrideWith(
          (ref) => const LedgerLoadState.ready(hasPersistedLedger: false),
        ),
        ledgerProvider.overrideWith(
          (ref) => _FakeLedgerController(emptyLedgerState()),
        ),
        permissionSetupControllerProvider.overrideWith(
          (ref) => PermissionSetupController()
            ..state = const PermissionSetupState(
              userId: testUserId,
              completed: true,
            ),
        ),
        cloudSyncControllerProvider.overrideWith(
          (ref) => _FakeCloudSyncController(
            const CloudSyncState(
              phase: CloudSyncPhase.idle,
              bootstrapComplete: true,
              bootstrappedUserId: testUserId,
              hasCloudWallet: true, // Existing cloud backup detected!
            ),
          ),
        ),
        onboardingControllerProvider.overrideWith(
          (ref) => OnboardingController()
            ..state = const OnboardingState(
              userId: testUserId,
              completed: false,
            ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final startup = container.read(startupStateProvider);
    // Destination must NEVER be onboarding!
    expect(startup.destination, isNot(StartupDestination.onboarding));
    expect(startup.isRecoverableError, isTrue);
    expect(startup.title, contains('Cloud wallet found'));
  });

  test('startupState routes to onboarding only for genuine fresh users without cloud wallet', () {
    final container = ProviderContainer(
      overrides: [
        themeControllerProvider.overrideWith(
          (ref) => _FakeThemeController(const AppThemeState(isLoaded: true)),
        ),
        authControllerProvider.overrideWith(
          (ref) => _FakeAuthController(authenticatedState),
        ),
        ledgerLoadStateProvider.overrideWith(
          (ref) => const LedgerLoadState.ready(hasPersistedLedger: false),
        ),
        ledgerProvider.overrideWith(
          (ref) => _FakeLedgerController(emptyLedgerState()),
        ),
        permissionSetupControllerProvider.overrideWith(
          (ref) => PermissionSetupController()
            ..state = const PermissionSetupState(
              userId: testUserId,
              completed: true,
            ),
        ),
        cloudSyncControllerProvider.overrideWith(
          (ref) => _FakeCloudSyncController(
            const CloudSyncState(
              phase: CloudSyncPhase.idle,
              bootstrapComplete: true,
              bootstrappedUserId: testUserId,
              hasCloudWallet: false, // Truly fresh account
            ),
          ),
        ),
        onboardingControllerProvider.overrideWith(
          (ref) => OnboardingController()
            ..state = const OnboardingState(
              userId: testUserId,
              completed: false,
            ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final startup = container.read(startupStateProvider);
    expect(startup.destination, StartupDestination.onboarding);
  });

  test('startupState routes to home when onboarding is completed even if hasCloudWallet is true', () {
    final container = ProviderContainer(
      overrides: [
        themeControllerProvider.overrideWith(
          (ref) => _FakeThemeController(const AppThemeState(isLoaded: true)),
        ),
        authControllerProvider.overrideWith(
          (ref) => _FakeAuthController(authenticatedState),
        ),
        ledgerLoadStateProvider.overrideWith(
          (ref) => const LedgerLoadState.ready(hasPersistedLedger: false),
        ),
        ledgerProvider.overrideWith(
          (ref) => _FakeLedgerController(emptyLedgerState()),
        ),
        permissionSetupControllerProvider.overrideWith(
          (ref) => PermissionSetupController()
            ..state = const PermissionSetupState(
              userId: testUserId,
              completed: true,
            ),
        ),
        cloudSyncControllerProvider.overrideWith(
          (ref) => _FakeCloudSyncController(
            const CloudSyncState(
              phase: CloudSyncPhase.idle,
              bootstrapComplete: true,
              bootstrappedUserId: testUserId,
              hasCloudWallet: true,
            ),
          ),
        ),
        onboardingControllerProvider.overrideWith(
          (ref) => OnboardingController()
            ..state = const OnboardingState(
              userId: testUserId,
              completed: true,
            ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final startup = container.read(startupStateProvider);
    expect(startup.destination, StartupDestination.home);
    expect(startup.isRecoverableError, isFalse);
  });
}
