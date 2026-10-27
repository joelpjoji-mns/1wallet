import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' as foundation;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/auth_controller.dart';
import '../capture/capture_pipeline.dart';
import '../capture/message_parser.dart';
import '../features/capture/capture_diagnostics.dart';
import '../features/capture/sms_spooler.dart';
import '../features/capture/notification_spooler.dart';
import '../features/capture/capture_queue.dart';
import '../imports/wallet_csv_parser.dart';
import '../ledger/ledger_selectors.dart';
import '../theme/theme_controller.dart';
import '../utils/recurrence_utils.dart';
import 'ledger_archive.dart';
import 'ledger_codec.dart';
import 'ledger_defaults.dart';
import 'ledger_models.dart';
import 'local_ledger_snapshot.dart';
import 'backup_codec.dart';

const _ledgerStorageKey = 'one_wallet_flutter.ledger.v1';
const _lastActiveUserIdKey = 'last_active_user_id';

@immutable
class LedgerUserIdentity {
  const LedgerUserIdentity({
    required this.userId,
    this.displayName,
    this.email,
  });

  final String userId;
  final String? displayName;
  final String? email;

  bool get isAuthenticated =>
      userId.trim().isNotEmpty && userId.trim() != 'local-user';
}

/// Sanitizes a name, email, or userId segment for safe cross-platform filenames.
String sanitizeBackupFileSegment(String input) {
  return input
      .trim()
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '')
      .replaceAll(RegExp(r'\s+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^[\._-]+|[\._-]+$'), '');
}

/// Builds a human-readable, per-user filename suffix (using full name and/or
/// email address) to place right before the `.onewallet` extension so local
/// backups from different accounts never overwrite or bleed into each other.
String buildUserBackupFileSuffix({
  String? displayName,
  String? email,
  String? userId,
}) {
  final cleanName = displayName != null
      ? sanitizeBackupFileSegment(displayName)
      : '';
  final rawEmail = email?.trim() ?? '';
  final isPlaceholderEmail =
      rawEmail.toLowerCase() == 'google account' || rawEmail.isEmpty;
  final cleanEmail = isPlaceholderEmail
      ? ''
      : sanitizeBackupFileSegment(rawEmail);

  if (cleanName.isNotEmpty && cleanEmail.isNotEmpty) {
    if (cleanName.toLowerCase() == cleanEmail.toLowerCase()) {
      return cleanEmail;
    }
    return '${cleanName}_$cleanEmail';
  }
  if (cleanEmail.isNotEmpty) {
    return cleanEmail;
  }
  if (cleanName.isNotEmpty) {
    return cleanName;
  }
  final cleanId = userId != null && userId.trim() != 'local-user'
      ? sanitizeBackupFileSegment(userId)
      : '';
  return cleanId;
}

/// Returns all valid filename suffixes for a user in priority order so backups
/// remain discoverable even if displayName was later added or updated.
List<String> buildCandidateUserBackupSuffixes({
  String? displayName,
  String? email,
  String? userId,
}) {
  final suffixes = <String>[];
  void addIfNonEmpty(String value) {
    if (value.isNotEmpty && !suffixes.contains(value)) {
      suffixes.add(value);
    }
  }

  final primary = buildUserBackupFileSuffix(
    displayName: displayName,
    email: email,
    userId: userId,
  );
  addIfNonEmpty(primary);

  final rawEmail = email?.trim() ?? '';
  if (rawEmail.isNotEmpty && rawEmail.toLowerCase() != 'google account') {
    addIfNonEmpty(sanitizeBackupFileSegment(rawEmail));
  }
  if (displayName != null && displayName.trim().isNotEmpty) {
    addIfNonEmpty(sanitizeBackupFileSegment(displayName));
  }
  if (userId != null &&
      userId.trim().isNotEmpty &&
      userId.trim() != 'local-user') {
    addIfNonEmpty(sanitizeBackupFileSegment(userId));
  }
  return suffixes;
}

String buildAutoBackupFileName({String? suffix, String variant = ''}) {
  final variantPart = variant.trim().isEmpty ? '' : '_${variant.trim()}';
  final suffixPart = (suffix != null && suffix.trim().isNotEmpty)
      ? '_${suffix.trim()}'
      : '';
  return '1wallet_auto_backup$variantPart$suffixPart.onewallet';
}

String buildManualBackupFileName({
  String? displayName,
  String? email,
  String? userId,
}) {
  final suffix = buildUserBackupFileSuffix(
    displayName: displayName,
    email: email,
    userId: userId,
  );
  if (suffix.isEmpty) {
    return '1wallet_backup.onewallet';
  }
  return '1wallet_backup_$suffix.onewallet';
}

final ledgerRepositoryProvider = Provider<LedgerRepository>((ref) {
  return const LedgerRepository();
});

final ledgerLoadStateProvider = StateProvider<LedgerLoadState>((ref) {
  SharedPreferences? prefs;
  try {
    prefs = ref.watch(sharedPreferencesProvider);
  } catch (_) {}
  if (prefs != null) {
    final payload = prefs.getString(_ledgerStorageKey);
    return LedgerLoadState.ready(
      hasPersistedLedger: payload != null && payload.trim().isNotEmpty,
    );
  }
  return const LedgerLoadState.loading();
});

final ledgerProvider = StateNotifierProvider<LedgerController, LedgerState>((
  ref,
) {
  final initialAuthUser = ref.read(authControllerProvider).user;
  final initialIdentity = initialAuthUser == null
      ? null
      : LedgerUserIdentity(
          userId: initialAuthUser.id,
          displayName: initialAuthUser.displayName,
          email: initialAuthUser.email,
        );
  final repository = ref.watch(ledgerRepositoryProvider);
  SharedPreferences? syncPrefs;
  try {
    syncPrefs = ref.read(sharedPreferencesProvider);
  } catch (_) {}

  LedgerState? syncRestored;
  bool preloadedFromPrefs = false;
  if (syncPrefs != null) {
    final candidate = repository.loadSync(syncPrefs);
    if (candidate != null) {
      final storedOwnerId = syncPrefs.getString(_lastActiveUserIdKey);
      final isForeign =
          initialIdentity != null &&
          initialIdentity.isAuthenticated &&
          ((candidate.userId.isNotEmpty &&
                  candidate.userId != 'local-user' &&
                  candidate.userId != initialIdentity.userId) ||
              (storedOwnerId != null &&
                  storedOwnerId.isNotEmpty &&
                  storedOwnerId != 'local-user' &&
                  storedOwnerId != initialIdentity.userId));
      if (!isForeign) {
        syncRestored =
            (initialIdentity != null &&
                initialIdentity.isAuthenticated &&
                (candidate.userId.isEmpty || candidate.userId == 'local-user'))
            ? candidate.copyWith(userId: initialIdentity.userId)
            : candidate;
        preloadedFromPrefs = true;
      }
    }
  }

  final controller = LedgerController(
    repository,
    setLoadState: (next) =>
        ref.read(ledgerLoadStateProvider.notifier).state = next,
    initialState:
        syncRestored ??
        emptyLedgerState(userId: initialAuthUser?.id ?? 'local-user'),
    initialUser: initialIdentity,
    preloadedFromPrefs: preloadedFromPrefs,
  );
  ref.listen<AuthState>(authControllerProvider, (previous, next) {
    final nextUser = next.user;
    if (nextUser != null) {
      unawaited(
        controller.setActiveUser(
          LedgerUserIdentity(
            userId: nextUser.id,
            displayName: nextUser.displayName,
            email: nextUser.email,
          ),
        ),
      );
    } else if (previous?.user != null) {
      unawaited(controller.clearSessionOnSignOut());
    }
  });
  return controller;
});

class StaleLedgerSessionException implements Exception {
  const StaleLedgerSessionException();

  @override
  String toString() => 'The wallet session changed during this operation.';
}

class LedgerLoadState {
  const LedgerLoadState._({
    required this.isReady,
    this.hasPersistedLedger = false,
    this.errorMessage,
  });

  const LedgerLoadState.loading()
    : this._(isReady: false, hasPersistedLedger: false);

  const LedgerLoadState.ready({required bool hasPersistedLedger})
    : this._(isReady: true, hasPersistedLedger: hasPersistedLedger);

  const LedgerLoadState.failed(String message)
    : this._(isReady: true, errorMessage: message);

  final bool isReady;
  final bool hasPersistedLedger;
  final String? errorMessage;
}

class LedgerRepository {
  const LedgerRepository({this.localFile});
  final Future<File?> Function()? localFile;

  static File? _cachedLocalLedgerFile;

  static Future<File?> _getLocalLedgerFile() async {
    if (foundation.kIsWeb) return null;
    if (_cachedLocalLedgerFile != null) return _cachedLocalLedgerFile;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/1wallet_ledger_state.json');
      _cachedLocalLedgerFile = file;
      return file;
    } catch (_) {
      return null;
    }
  }

  LedgerState? loadSync(SharedPreferences preferences) {
    final payload = preferences.getString(_ledgerStorageKey);
    if (payload != null && payload.trim().isNotEmpty) {
      try {
        return decodeLocalLedgerSnapshot(payload);
      } catch (e) {
        debugPrint('Failed to decode ledger synchronously: $e');
      }
    }
    return null;
  }

  Future<LedgerState?> load() async {
    final preferences = await SharedPreferences.getInstance();
    final payload = preferences.getString(_ledgerStorageKey);
    Object? failure;
    if (payload != null && payload.trim().isNotEmpty) {
      try {
        final decoded = await foundation.compute(
          decodeLocalLedgerSnapshot,
          payload,
        );
        return decoded;
      } catch (e) {
        failure = e;
        debugPrint('Failed to decode ledger from SharedPreferences: $e');
      }
    }

    // Secondary source of truth: atomic file on device storage
    final file = await (localFile?.call() ?? _getLocalLedgerFile());
    if (file != null && await file.exists()) {
      try {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final decoded = await foundation.compute(
            decodeLocalLedgerSnapshot,
            content,
          );
          if (!await preferences.setString(_ledgerStorageKey, content)) {
            throw StateError('Could not recover the local wallet cache.');
          }
          return decoded;
        }
      } catch (e) {
        failure = e;
        debugPrint('Failed to load ledger from local file: $e');
      }
    }
    if (failure != null) {
      throw StateError('The local wallet could not be decoded: $failure');
    }
    return null;
  }

  Future<void> save(LedgerState state) async {
    final preferences = await SharedPreferences.getInstance();
    final payload = await foundation.compute(encodeLocalLedgerSnapshot, state);
    if (!await preferences.setString(_ledgerStorageKey, payload)) {
      throw StateError('Could not persist the local wallet.');
    }

    // Also persist atomically to file
    final file = await (localFile?.call() ?? _getLocalLedgerFile());
    if (file != null) {
      try {
        final tempFile = File('${file.path}.tmp');
        await tempFile.writeAsString(payload, flush: true);
        await tempFile.rename(file.path);
      } catch (e) {
        debugPrint('Failed to write atomic local ledger file: $e');
        rethrow;
      }
    }
  }

  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.remove(_ledgerStorageKey)) {
      throw StateError('Could not clear the local wallet.');
    }
    final file = await (localFile?.call() ?? _getLocalLedgerFile());
    if (file != null && await file.exists()) {
      try {
        await file.delete();
      } catch (error) {
        debugPrint('Could not delete the local wallet file: $error');
        rethrow;
      }
    }
  }
}

LedgerState fixStaleScheduledTransactions(LedgerState ledger) {
  bool changed = false;
  final now = DateTime.now();
  final List<TransactionRecord> newAutoPosted = [];

  // 0. Fix broken zero-amount transfers (where counterAmount was incorrectly saved as 0 due to a bug)
  final updatedTransactions = <TransactionRecord>[];
  for (final t in ledger.transactions) {
    if (t.type == 'transfer' &&
        t.counterAmount != null &&
        t.counterAmount!.amountMinor == 0 &&
        t.amount.amountMinor > 0) {
      if (t.counterAmount!.currency.toUpperCase() ==
          t.amount.currency.toUpperCase()) {
        updatedTransactions.add(t.copyWith(counterAmount: t.amount));
        changed = true;
        continue;
      }
    }
    updatedTransactions.add(t);
  }

  // 1. Build initial history count for auto-posting
  final Map<String, int> initialHistoryCount = {};
  for (final t in updatedTransactions) {
    if (t.originalTransactionId != null &&
        t.status != 'scheduled' &&
        t.status != 'void') {
      initialHistoryCount[t.originalTransactionId!] =
          (initialHistoryCount[t.originalTransactionId!] ?? 0) + 1;
    }
  }

  // 2. Generate auto-posted transactions
  for (final scheduled in updatedTransactions) {
    if (scheduled.status == 'scheduled' && scheduled.postMode == 'auto') {
      if (scheduled.recurrenceFrequency == 'once' ||
          scheduled.recurrenceFrequency == null) {
        if (scheduled.occurredAt.isBefore(now)) {
          final dateStr =
              '${scheduled.occurredAt.year}${scheduled.occurredAt.month.toString().padLeft(2, '0')}${scheduled.occurredAt.day.toString().padLeft(2, '0')}';
          final autoId = '${scheduled.id}-auto-$dateStr';
          final alreadyExists = ledger.transactions.any((t) => t.id == autoId);
          if (!alreadyExists && !newAutoPosted.any((t) => t.id == autoId)) {
            changed = true;
            newAutoPosted.add(
              scheduled.copyWith(
                id: autoId,
                status: 'cleared',
                occurredAt: scheduled.occurredAt,
                originalTransactionId: scheduled.id,
              ),
            );
          }
        }
        continue;
      }

      DateTime nextDate = scheduled.occurredAt;
      int currentCount = initialHistoryCount[scheduled.id] ?? 0;

      while (nextDate.isBefore(now)) {
        if (scheduled.recurrenceLimit != null &&
            currentCount >= scheduled.recurrenceLimit!) {
          break;
        }
        if (scheduled.recurrenceEndDate != null &&
            nextDate.isAfter(scheduled.recurrenceEndDate!)) {
          break;
        }

        final dateStr =
            '${nextDate.year}${nextDate.month.toString().padLeft(2, '0')}${nextDate.day.toString().padLeft(2, '0')}';
        final autoId = '${scheduled.id}-auto-$dateStr';

        final alreadyExists = ledger.transactions.any((t) => t.id == autoId);
        if (!alreadyExists && !newAutoPosted.any((t) => t.id == autoId)) {
          changed = true;
          currentCount++;
          newAutoPosted.add(
            scheduled.copyWith(
              id: autoId,
              status: 'cleared',
              occurredAt: nextDate,
              originalTransactionId: scheduled.id,
            ),
          );
        }
        nextDate = advanceTransactionRecurrence(nextDate, scheduled);
      }
    }
  }

  // Combine original with new
  final combinedTransactions = [...updatedTransactions, ...newAutoPosted];

  // 3. Build history map and final counts
  final Map<String, DateTime> latestHistory = {};
  final Map<String, int> finalHistoryCount = {};
  for (final t in combinedTransactions) {
    if (t.originalTransactionId != null &&
        t.status != 'scheduled' &&
        t.status != 'void') {
      finalHistoryCount[t.originalTransactionId!] =
          (finalHistoryCount[t.originalTransactionId!] ?? 0) + 1;
      final currentLatest = latestHistory[t.originalTransactionId!];
      if (currentLatest == null || t.occurredAt.isAfter(currentLatest)) {
        latestHistory[t.originalTransactionId!] = t.occurredAt;
      }
    }
  }

  // 4. Advance scheduled cursors based on history map and check limits
  final updated = combinedTransactions.map((scheduled) {
    if (scheduled.status != 'scheduled') return scheduled;

    int currentCount = finalHistoryCount[scheduled.id] ?? 0;

    // Check if limit reached
    if (scheduled.recurrenceLimit != null &&
        currentCount >= scheduled.recurrenceLimit!) {
      changed = true;
      return scheduled.copyWith(status: 'finished');
    }

    if (scheduled.recurrenceEndDate != null &&
        scheduled.occurredAt.isAfter(scheduled.recurrenceEndDate!)) {
      changed = true;
      return scheduled.copyWith(status: 'finished');
    }

    final latestOccurredAt = latestHistory[scheduled.id];
    if (latestOccurredAt != null &&
        (scheduled.occurredAt.isBefore(latestOccurredAt) ||
            scheduled.occurredAt.isAtSameMomentAs(latestOccurredAt))) {
      changed = true;
      if (scheduled.recurrenceFrequency == 'once' ||
          scheduled.recurrenceFrequency == null) {
        return scheduled.copyWith(status: 'finished');
      }
      DateTime nextDate = scheduled.occurredAt;
      while (nextDate.isBefore(latestOccurredAt) ||
          nextDate.isAtSameMomentAs(latestOccurredAt)) {
        nextDate = advanceTransactionRecurrence(nextDate, scheduled);
      }

      if (scheduled.recurrenceEndDate != null &&
          nextDate.isAfter(scheduled.recurrenceEndDate!)) {
        return scheduled.copyWith(status: 'finished');
      }
      return scheduled.copyWith(occurredAt: nextDate);
    }

    return scheduled;
  }).toList();

  if (!changed) return ledger;
  return ledger.copyWith(transactions: updated);
}

abstract final class LedgerProvidersConfig {
  static bool disableAutoBackup = false;
}

class LedgerController extends StateNotifier<LedgerState> {
  LedgerController(
    this._repository, {
    void Function(LedgerLoadState)? setLoadState,
    LedgerState? initialState,
    LedgerUserIdentity? initialUser,
    this.preloadedFromPrefs = false,
  }) : _setLoadState = setLoadState ?? _ignoreLoadState,
       _activeUser = initialUser,
       super(
         initialState ??
             emptyLedgerState(userId: initialUser?.userId ?? 'local-user'),
       ) {
    unawaited(_loadPersistedLedger());
  }

  final LedgerRepository _repository;
  final void Function(LedgerLoadState) _setLoadState;
  LedgerUserIdentity? _activeUser;
  final bool preloadedFromPrefs;
  int _sessionEpoch = 0;
  int? _runningEpoch;
  Future<void> _writeTail = Future<void>.value();
  String? _deletingOwner;
  Timer? _spoolPollTimer;

  int get changeVersion => state.localRevision;
  int get sessionGeneration => _sessionEpoch;
  bool get isDeletionPending => _deletingOwner == state.userId;

  void _checkSession() {
    if (!mounted || (_runningEpoch != null && _runningEpoch != _sessionEpoch)) {
      throw const StaleLedgerSessionException();
    }
  }

  Future<T> _runMutation<T>(
    Future<T> Function() action, {
    bool allowDuringDeletion = false,
  }) {
    final epoch = _sessionEpoch;
    final result = _writeTail.then((_) async {
      if (!mounted || epoch != _sessionEpoch) {
        throw const StaleLedgerSessionException();
      }
      if (!allowDuringDeletion && _deletingOwner == state.userId) {
        throw StateError('This wallet is being deleted.');
      }
      _runningEpoch = epoch;
      try {
        return await action();
      } finally {
        _runningEpoch = null;
      }
    });
    _writeTail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        if (error is StaleLedgerSessionException) return;
        debugPrint('Wallet operation failed: $error');
        debugPrintStack(stackTrace: stack);
      },
    );
    return result;
  }

  void invalidatePendingOperations() {
    _sessionEpoch++;
    _spoolPollTimer?.cancel();
    _prefsSaveTimer?.cancel();
    _autoBackupTimer?.cancel();
  }

  Future<void> freezeForDeletion(String owner) async {
    if (state.userId != owner && _activeUser?.userId != owner) return;
    if (_deletingOwner == owner) {
      await CaptureQueue.client.configure(null);
      return;
    }
    invalidatePendingOperations();
    _deletingOwner = owner;
    await CaptureQueue.client.configure(null);
  }

  Future<void> flushPendingWrites() => _runMutation(() async {
    _prefsSaveTimer?.cancel();
    await _repository.save(state);
    _checkSession();
  });

  Future<bool> acknowledgeUploadedVersion(int revision) =>
      _runMutation(() async {
        if (state.localRevision != revision) return false;
        final prefs = await SharedPreferences.getInstance();
        _checkSession();
        if (!await prefs.setBool('has_unsynced_changes', false)) {
          throw StateError('Could not acknowledge the uploaded wallet.');
        }
        _checkSession();
        if (state.accounts.isEmpty &&
            state.transactions.isEmpty &&
            !state.hasAuthoritativeEmptyWallet) {
          state = state.copyWith(hasAuthoritativeEmptyWallet: true);
          await _repository.save(state);
          _checkSession();
        }
        return true;
      });

  Future<void> prepareCloudReplacement(int revision, String owner) =>
      _runMutation(() async {
        if (state.localRevision != revision ||
            state.userId != owner ||
            _activeUser?.userId != owner) {
          throw StateError(
            'The wallet changed after cloud replacement was confirmed.',
          );
        }
        final prefs = await SharedPreferences.getInstance();
        _checkSession();
        if (!await prefs.setBool('has_unsynced_changes', false)) {
          throw StateError('Could not prepare cloud replacement.');
        }
        _checkSession();
      });

  Future<void> markSyncSettingsChanged() => _runMutation(() => _commit(state));

  LedgerUserIdentity? get activeUser => _activeUser;

  bool _capturePreferencesChanged(
    LedgerPreferences before,
    LedgerPreferences after,
  ) =>
      before.smsCaptureEnabled != after.smsCaptureEnabled ||
      before.notificationCaptureEnabled != after.notificationCaptureEnabled ||
      !foundation.listEquals(before.smsTriggerWords, after.smsTriggerWords) ||
      !foundation.listEquals(before.smsIgnoreWords, after.smsIgnoreWords) ||
      !foundation.listEquals(
        before.notificationTriggerWords,
        after.notificationTriggerWords,
      ) ||
      !foundation.listEquals(
        before.notificationIgnoreWords,
        after.notificationIgnoreWords,
      ) ||
      !foundation.listEquals(
        before.notificationTargetPackages,
        after.notificationTargetPackages,
      );

  Future<void> _publishCaptureConfiguration() {
    final active = _activeUser;
    final preferences = state.preferences;
    return CaptureQueue.client.configure(
      active != null &&
              active.isAuthenticated &&
              state.userId == active.userId &&
              _deletingOwner != active.userId
          ? active.userId
          : null,
      settings: {
        'smsCaptureEnabled': preferences.smsCaptureEnabled,
        'smsTriggerWords': preferences.smsTriggerWords,
        'smsIgnoreWords': preferences.smsIgnoreWords,
        'notificationCaptureEnabled': preferences.notificationCaptureEnabled,
        'notificationTriggerWords': preferences.notificationTriggerWords,
        'notificationIgnoreWords': preferences.notificationIgnoreWords,
        'notificationTargetPackages': preferences.notificationTargetPackages,
      },
    );
  }

  Future<void> assignLegacyCaptures() => _runMutation(() async {
    final owner = _activeUser;
    if (owner == null ||
        !owner.isAuthenticated ||
        state.userId != owner.userId) {
      throw StateError('Sign in before assigning legacy captures.');
    }
    await CaptureQueue.client.assignLegacy(owner.userId);
    _checkSession();
  });

  String defaultManualBackupFileName() {
    return buildManualBackupFileName(
      displayName: _activeUser?.displayName,
      email: _activeUser?.email,
      userId: _activeUser?.userId ?? state.userId,
    );
  }

  @override
  void dispose() {
    _sessionEpoch++;
    _spoolPollTimer?.cancel();
    _prefsSaveTimer?.cancel();
    _autoBackupTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadPersistedLedger() => _runMutation(() async {
    final loadEpoch = _sessionEpoch;
    try {
      if (preloadedFromPrefs) {
        _setLoadState(
          LedgerLoadState.ready(hasPersistedLedger: _hasWalletData(state)),
        );
        unawaited(_runBackgroundStartupMaintenance(state, loadEpoch));
        return;
      }

      final restored = await _repository.load();
      if (!mounted || loadEpoch != _sessionEpoch) return;
      if (restored != null) {
        final prefs = await SharedPreferences.getInstance();
        if (!mounted || loadEpoch != _sessionEpoch) return;
        final storedOwnerId = prefs.getString(_lastActiveUserIdKey);
        final active = _activeUser;
        final isForeignLedger =
            active != null &&
            active.isAuthenticated &&
            ((restored.userId.isNotEmpty &&
                    restored.userId != 'local-user' &&
                    restored.userId != active.userId) ||
                (storedOwnerId != null &&
                    storedOwnerId.isNotEmpty &&
                    storedOwnerId != 'local-user' &&
                    storedOwnerId != active.userId));

        if (isForeignLedger) {
          await _repository.clear();
          await prefs.remove('has_unsynced_changes');
          await prefs.remove('last_local_modified_at');
          await prefs.setString(_lastActiveUserIdKey, active.userId);
          if (!mounted || loadEpoch != _sessionEpoch) return;
          state = emptyLedgerState(userId: active.userId);
          _setLoadState(const LedgerLoadState.ready(hasPersistedLedger: false));
        } else {
          final stamped =
              (active != null &&
                  active.isAuthenticated &&
                  (restored.userId.isEmpty || restored.userId == 'local-user'))
              ? restored.copyWith(userId: active.userId)
              : restored;
          state = stamped;
          if (active != null && active.isAuthenticated) {
            unawaited(prefs.setString(_lastActiveUserIdKey, active.userId));
          }
          if (stamped.userId != restored.userId) {
            await _repository.save(stamped);
            _checkSession();
          }
          _setLoadState(
            LedgerLoadState.ready(hasPersistedLedger: _hasWalletData(state)),
          );
          unawaited(_runBackgroundStartupMaintenance(stamped, loadEpoch));
        }
      } else {
        _setLoadState(
          LedgerLoadState.ready(hasPersistedLedger: _hasWalletData(state)),
        );
        unawaited(_runBackgroundStartupMaintenance(state, loadEpoch));
      }
    } catch (error) {
      if (!mounted || loadEpoch != _sessionEpoch) return;
      _setLoadState(
        LedgerLoadState.failed('Unable to restore local wallet: $error'),
      );
    }
  });

  Future<void> _runBackgroundStartupMaintenance(
    LedgerState baseState,
    int loadEpoch,
  ) => _runMutation(() async {
    await null;
    if (!mounted || loadEpoch != _sessionEpoch) return;
    await _publishCaptureConfiguration();
    _checkSession();
    final current = state;
    if (current.transactions.isNotEmpty) {
      final fixed = fixStaleScheduledTransactions(current);
      if (!mounted || loadEpoch != _sessionEpoch) return;
      if (!identical(fixed, current)) {
        await _commit(fixed);
      }
    }

    if (_hasWalletData(state)) {
      unawaited(SmsSpooler.updateTriggerWords(state));
      unawaited(NotificationSpooler.updateTriggerWords(state));
    }
    unawaited(processSpooledSms());
    unawaited(processSpooledNotifications());
    _syncSpoolPolling();
  });

  Future<void> setActiveUser(LedgerUserIdentity user) {
    if (_activeUser?.userId != user.userId) invalidatePendingOperations();
    return _runMutation(() async {
      await _setActiveUser(user);
      _checkSession();
      await _publishCaptureConfiguration();
      _checkSession();
    }, allowDuringDeletion: true);
  }

  Future<void> _setActiveUser(LedgerUserIdentity user) async {
    final prefs = await SharedPreferences.getInstance();
    _checkSession();

    if (_activeUser?.userId == user.userId) {
      _activeUser = user;
      await prefs.setString(_lastActiveUserIdKey, user.userId);
      _checkSession();
      if (user.isAuthenticated &&
          (state.userId.isEmpty || state.userId == 'local-user')) {
        state = state.copyWith(userId: user.userId);
      }
      return;
    }

    final previousOwnerId =
        _activeUser?.userId ?? prefs.getString(_lastActiveUserIdKey);
    final hasForeignLedger =
        user.isAuthenticated &&
        ((state.userId.isNotEmpty &&
                state.userId != 'local-user' &&
                state.userId != user.userId) ||
            (previousOwnerId != null &&
                previousOwnerId.isNotEmpty &&
                previousOwnerId != 'local-user' &&
                previousOwnerId != user.userId));

    if (hasForeignLedger) {
      final prevUser = _activeUser;
      final prevState = state;
      if (prevUser != null &&
          prevUser.isAuthenticated &&
          _hasWalletData(prevState) &&
          prevState.userId == prevUser.userId &&
          !LedgerProvidersConfig.disableAutoBackup) {
        await _performAutoBackup(prevState, userOverride: prevUser);
        _checkSession();
      }
      _spoolPollTimer?.cancel();
      _spoolPollTimer = null;
      _prefsSaveTimer?.cancel();
      _prefsSaveTimer = null;
      _autoBackupTimer?.cancel();
      _autoBackupTimer = null;
      _activeUser = user;
      state = emptyLedgerState(userId: user.userId);
      await _repository.clear();
      _checkSession();
      await prefs.remove('has_unsynced_changes');
      await prefs.remove('last_local_modified_at');
      await prefs.setString(_lastActiveUserIdKey, user.userId);
      _checkSession();
      _setLoadState(const LedgerLoadState.ready(hasPersistedLedger: false));
      return;
    }

    _activeUser = user;
    if (user.isAuthenticated) {
      await prefs.setString(_lastActiveUserIdKey, user.userId);
      _checkSession();
      if (state.userId.isEmpty || state.userId == 'local-user') {
        state = state.copyWith(userId: user.userId);
        await _publishCaptureConfiguration();
        _checkSession();
        if (_hasWalletData(state)) {
          await _repository.save(state);
          _checkSession();
        }
      }
    }
  }

  Future<void> flushAutoBackupBeforeSignOut() async {
    final epoch = _sessionEpoch;
    await flushPendingWrites();
    if (!mounted || epoch != _sessionEpoch) {
      throw const StaleLedgerSessionException();
    }
    _autoBackupTimer?.cancel();
    _autoBackupTimer = null;
    if (!LedgerProvidersConfig.disableAutoBackup && _hasWalletData(state)) {
      await _performAutoBackup(state, userOverride: _activeUser);
    }
  }

  Future<void> clearSessionOnSignOut() {
    invalidatePendingOperations();
    return _runMutation(_clearSessionOnSignOut, allowDuringDeletion: true);
  }

  Future<void> _clearSessionOnSignOut() async {
    await CaptureQueue.client.configure(null);
    _checkSession();
    _spoolPollTimer?.cancel();
    _spoolPollTimer = null;
    _prefsSaveTimer?.cancel();
    _prefsSaveTimer = null;
    final previousUser = _activeUser;
    final previousState = state;
    if (_autoBackupTimer != null &&
        !LedgerProvidersConfig.disableAutoBackup &&
        _hasWalletData(previousState)) {
      _autoBackupTimer?.cancel();
      _autoBackupTimer = null;
      await _performAutoBackup(previousState, userOverride: previousUser);
      _checkSession();
    } else {
      _autoBackupTimer?.cancel();
      _autoBackupTimer = null;
    }
    await _repository.clear();
    _checkSession();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('has_unsynced_changes');
    await prefs.remove('last_local_modified_at');
    await prefs.remove(_lastActiveUserIdKey);
    _checkSession();
    _activeUser = null;
    state = emptyLedgerState();
    _setLoadState(const LedgerLoadState.ready(hasPersistedLedger: false));
  }

  Future<void> clearLocalWallet({String userId = 'local-user'}) {
    invalidatePendingOperations();
    return _runMutation(
      () => _clearLocalWallet(userId),
      allowDuringDeletion: true,
    );
  }

  Future<void> _clearLocalWallet(String userId) async {
    final effectiveUserId =
        userId == 'local-user' && (_activeUser?.isAuthenticated ?? false)
        ? _activeUser!.userId
        : userId;
    final next = emptyLedgerState(userId: effectiveUserId);
    state = next;
    await _repository.clear();
  }

  Future<void> purgeAllLocalData({LedgerUserIdentity? userOverride}) {
    if (userOverride == null ||
        state.userId == userOverride.userId ||
        _activeUser?.userId == userOverride.userId) {
      invalidatePendingOperations();
    }
    return _runMutation(
      () => _purgeAllLocalData(userOverride),
      allowDuringDeletion: true,
    );
  }

  Future<void> _purgeAllLocalData(LedgerUserIdentity? owner) async {
    _spoolPollTimer?.cancel();
    _prefsSaveTimer?.cancel();
    _autoBackupTimer?.cancel();
    await _backupTail;
    _checkSession();
    await deleteAllAutoBackupFiles(userOverride: owner ?? _activeUser);
    final target = owner?.userId ?? _activeUser?.userId ?? state.userId;
    await CaptureQueue.client.purge(target);
    await CaptureDiagnostics.clear(ownerId: target);
    _checkSession();
    if (state.userId != target && _activeUser?.userId != target) return;
    _activeUser = null;
    await _repository.clear();
    state = emptyLedgerState();
    _setLoadState(const LedgerLoadState.ready(hasPersistedLedger: false));
  }

  bool _isSpoolPollingPaused = false;

  void pauseSpoolPolling() {
    _isSpoolPollingPaused = true;
    _spoolPollTimer?.cancel();
    _spoolPollTimer = null;
  }

  void resumeSpoolPolling() {
    _isSpoolPollingPaused = false;
    if (isDeletionPending || !(_activeUser?.isAuthenticated ?? false)) return;
    unawaited(processSpooledSms());
    unawaited(processSpooledNotifications());
    _syncSpoolPolling();
  }

  void _syncSpoolPolling() {
    _spoolPollTimer?.cancel();
    _spoolPollTimer = null;
    if (_isSpoolPollingPaused ||
        !mounted ||
        isDeletionPending ||
        !(_activeUser?.isAuthenticated ?? false)) {
      return;
    }
    if (foundation.kIsWeb ||
        !Platform.isAndroid ||
        Platform.environment.containsKey('FLUTTER_TEST')) {
      return;
    }

    _spoolPollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted ||
          isDeletionPending ||
          !(_activeUser?.isAuthenticated ?? false)) {
        return;
      }
      unawaited(processSpooledSms());
      unawaited(processSpooledNotifications());
    });
  }

  bool _isProcessingSpooledSms = false;
  bool _isProcessingSpooledNotifications = false;

  Account? _applyStatementToAccount({
    required LedgerState currentState,
    required BillStatementNotice notice,
    Account? matchedAccount,
  }) {
    final targetAccount =
        matchedAccount ?? matchAccountForStatement(currentState, notice);
    if (targetAccount == null) return null;

    final details = Map<String, String>.from(
      targetAccount.encryptedDetails ?? const {},
    );
    if (notice.amount != null) {
      details['lastStatementAmountMinor'] = notice.amount!.amountMinor
          .toString();
      details['lastStatementCurrency'] = notice.amount!.currency;
    }
    if (notice.minAmountDue != null) {
      details['lastStatementMinDueMinor'] = notice.minAmountDue!.amountMinor
          .toString();
    }
    if (notice.dueDate != null) {
      details['lastStatementDueDate'] = notice.dueDate!.toIso8601String();
    }
    if (notice.statementDate != null) {
      details['lastStatementDate'] = notice.statementDate!.toIso8601String();
    }
    details['lastStatementUpdated'] = DateTime.now().toIso8601String();

    return targetAccount.copyWith(
      dueDay: notice.dueDay ?? targetAccount.dueDay,
      statementDay: notice.statementDay ?? targetAccount.statementDay,
      notifyDaysBeforeDue: targetAccount.notifyDaysBeforeDue ?? 3,
      encryptedDetails: details,
    );
  }

  Future<void> processSpooledSms() => _runMutation(() async {
    if (_isProcessingSpooledSms) return;
    _isProcessingSpooledSms = true;
    try {
      final owner = state.userId;
      final spooled = await SmsSpooler.popSpooledMessages(owner: owner);
      _checkSession();
      final receivedIds = <String>[];
      final newReceipts = <String>{};
      if (spooled.isEmpty) return;

      final newCandidates = <CaptureCandidate>[];
      final updatedAccounts = <String, Account>{};

      for (final payload in spooled) {
        final id = payload['_queueId'];
        if (id is! String) {
          throw const FormatException('Capture queue ID is missing.');
        }
        if (state.ingressReceipts.contains(id)) {
          receivedIds.add(id);
          continue;
        }
        if (payload['body'] is! String ||
            (payload['body'] as String).trim().isEmpty ||
            (payload['timestamp'] != null && payload['timestamp'] is! String) ||
            (payload['nativeMatchedAmount'] != null &&
                payload['nativeMatchedAmount'] is! String) ||
            (payload['nativeMatchedTriggerWord'] != null &&
                payload['nativeMatchedTriggerWord'] is! String)) {
          await CaptureQueue.client.quarantine(
            owner,
            id,
            'Invalid capture payload types.',
          );
          _checkSession();
          continue;
        }
        receivedIds.add(id);
        newReceipts.add(id);
        final body = payload['body'] as String?;
        final timestampStr = payload['timestamp'] as String?;
        final receivedAt = timestampStr != null
            ? DateTime.tryParse(timestampStr)
            : null;
        if (body != null && body.isNotEmpty) {
          final isStatement =
              payload['isBillStatement'] == true ||
              isBillStatementMessage(body);
          if (isStatement) {
            final notice = parseBillStatementNotice(
              body,
              fallbackCurrency: state.preferences.baseCurrency,
              receivedAt: receivedAt,
            );
            if (notice != null) {
              final updatedAcc = _applyStatementToAccount(
                currentState: state,
                notice: notice,
              );
              if (updatedAcc != null) {
                updatedAccounts[updatedAcc.id] = updatedAcc;
              }
            }
          }

          final nativeAccepted =
              payload['nativeAccepted'] == true ||
              payload['notificationShown'] == true ||
              payload['nativeNotificationShown'] == true ||
              payload['nativeSource'] != null;

          final nativeMatchedAmount = payload['nativeMatchedAmount'] as String?;
          final nativeMatchedTriggerWord =
              payload['nativeMatchedTriggerWord'] as String?;

          final result = _evaluateCaptureMessage(
            rawText: body,
            source: 'sms',
            triggerWords: state.preferences.smsTriggerWords,
            ignoreWords: state.preferences.smsIgnoreWords,
            receivedAt: receivedAt,
            nativeAccepted: nativeAccepted || payload.isNotEmpty,
            notificationShown: true,
            forceQueue: true,
            additionalCandidates: newCandidates,
            nativeMatchedAmount: nativeMatchedAmount,
            nativeMatchedTriggerWord: nativeMatchedTriggerWord,
          );

          if (result.queued && result.candidate != null) {
            newCandidates.add(result.candidate!);
          }
          await CaptureDiagnostics.recordResult(
            ownerId: state.userId,
            stage: 'spool-sms',
            result: result,
          );
        }
      }

      var nextAccounts = state.accounts;
      if (updatedAccounts.isNotEmpty) {
        nextAccounts = state.accounts
            .map((a) => updatedAccounts[a.id] ?? a)
            .toList();
      }

      if (newCandidates.isNotEmpty ||
          updatedAccounts.isNotEmpty ||
          newReceipts.isNotEmpty) {
        await _commit(
          state.copyWith(
            accounts: nextAccounts,
            ingressReceipts: {...state.ingressReceipts, ...newReceipts},
            captureCandidates: [...newCandidates, ...state.captureCandidates],
          ),
        );
      }
      await CaptureQueue.client.acknowledge(owner, receivedIds);
      _checkSession();
      if (receivedIds.isNotEmpty) {
        state = state.copyWith(
          ingressReceipts: state.ingressReceipts.difference(
            receivedIds.toSet(),
          ),
        );
        await _repository.save(state);
        _checkSession();
      }
    } catch (e) {
      debugPrint('Error processing spooled SMS: $e');
      rethrow;
    } finally {
      _isProcessingSpooledSms = false;
    }
  });

  Future<void> processSpooledNotifications() => _runMutation(() async {
    if (_isProcessingSpooledNotifications) return;
    _isProcessingSpooledNotifications = true;
    try {
      final owner = state.userId;
      final spooled = await NotificationSpooler.popSpooledMessages(
        owner: owner,
      );
      _checkSession();
      final receivedIds = <String>[];
      final newReceipts = <String>{};
      if (spooled.isEmpty) return;

      final newCandidates = <CaptureCandidate>[];
      final updatedAccounts = <String, Account>{};

      for (final payload in spooled) {
        final id = payload['_queueId'];
        if (id is! String) {
          throw const FormatException('Capture queue ID is missing.');
        }
        if (state.ingressReceipts.contains(id)) {
          receivedIds.add(id);
          continue;
        }
        if (payload['body'] is! String ||
            (payload['body'] as String).trim().isEmpty ||
            (payload['timestamp'] != null && payload['timestamp'] is! String) ||
            (payload['nativeMatchedAmount'] != null &&
                payload['nativeMatchedAmount'] is! String) ||
            (payload['nativeMatchedTriggerWord'] != null &&
                payload['nativeMatchedTriggerWord'] is! String)) {
          await CaptureQueue.client.quarantine(
            owner,
            id,
            'Invalid capture payload types.',
          );
          _checkSession();
          continue;
        }
        receivedIds.add(id);
        newReceipts.add(id);
        final body = payload['body'] as String?;
        final timestampStr = payload['timestamp'] as String?;
        final receivedAt = timestampStr != null
            ? DateTime.tryParse(timestampStr)
            : null;
        if (body != null && body.isNotEmpty) {
          final isStatement =
              payload['isBillStatement'] == true ||
              isBillStatementMessage(body);
          if (isStatement) {
            final notice = parseBillStatementNotice(
              body,
              fallbackCurrency: state.preferences.baseCurrency,
              receivedAt: receivedAt,
            );
            if (notice != null) {
              final updatedAcc = _applyStatementToAccount(
                currentState: state,
                notice: notice,
              );
              if (updatedAcc != null) {
                updatedAccounts[updatedAcc.id] = updatedAcc;
              }
            }
          }

          final nativeAccepted =
              payload['nativeAccepted'] == true ||
              payload['notificationShown'] == true ||
              payload['nativeNotificationShown'] == true ||
              payload['nativeSource'] != null;

          final nativeMatchedAmount = payload['nativeMatchedAmount'] as String?;
          final nativeMatchedTriggerWord =
              payload['nativeMatchedTriggerWord'] as String?;

          final result = _evaluateCaptureMessage(
            rawText: body,
            source: 'notification',
            triggerWords: state.preferences.notificationTriggerWords,
            ignoreWords: state.preferences.notificationIgnoreWords,
            receivedAt: receivedAt,
            nativeAccepted: nativeAccepted || payload.isNotEmpty,
            notificationShown: true,
            forceQueue: true,
            additionalCandidates: newCandidates,
            nativeMatchedAmount: nativeMatchedAmount,
            nativeMatchedTriggerWord: nativeMatchedTriggerWord,
          );

          if (result.queued && result.candidate != null) {
            newCandidates.add(result.candidate!);
          }
          await CaptureDiagnostics.recordResult(
            ownerId: state.userId,
            stage: 'spool-notification',
            result: result,
          );
        }
      }

      var nextAccounts = state.accounts;
      if (updatedAccounts.isNotEmpty) {
        nextAccounts = state.accounts
            .map((a) => updatedAccounts[a.id] ?? a)
            .toList();
      }

      if (newCandidates.isNotEmpty ||
          updatedAccounts.isNotEmpty ||
          newReceipts.isNotEmpty) {
        await _commit(
          state.copyWith(
            accounts: nextAccounts,
            ingressReceipts: {...state.ingressReceipts, ...newReceipts},
            captureCandidates: [...newCandidates, ...state.captureCandidates],
          ),
        );
      }
      await CaptureQueue.client.acknowledge(owner, receivedIds);
      _checkSession();
      if (receivedIds.isNotEmpty) {
        state = state.copyWith(
          ingressReceipts: state.ingressReceipts.difference(
            receivedIds.toSet(),
          ),
        );
        await _repository.save(state);
        _checkSession();
      }
    } catch (e) {
      debugPrint('Error processing spooled notifications: $e');
      rethrow;
    } finally {
      _isProcessingSpooledNotifications = false;
    }
  });

  Future<void> createStarterWallet({
    required String userId,
    required String accountName,
    required String currency,
    required Color accountColor,
    String accountType = 'bank',
    int openingBalanceMinor = 0,
  }) => _runMutation(() async {
    if (_hasWalletData(state)) {
      return;
    }

    final normalizedCurrency = currency.trim().toUpperCase().isEmpty
        ? kDefaultCurrency
        : currency.trim().toUpperCase();
    final preferences = LedgerPreferences(
      baseCurrency: normalizedCurrency,
      displayCurrency: normalizedCurrency,
      enabledCurrencies: [normalizedCurrency],
      locale: normalizedCurrency == kDefaultCurrency ? kDefaultLocale : 'en_US',
    );
    final starter = emptyLedgerState(userId: userId, preferences: preferences);
    final account = Account(
      id: _newId('acc'),
      name: accountName.trim().isEmpty
          ? '$normalizedCurrency account'
          : accountName.trim(),
      type: accountType,
      currency: normalizedCurrency,
      openingBalance: Money(
        amountMinor: openingBalanceMinor,
        currency: normalizedCurrency,
      ),
      color: accountColor,
      sortOrder: 1,
    );
    await _commit(starter.copyWith(accounts: [account]));
  });

  String exportArchive({String source = 'flutter-local'}) {
    return encodeLedgerArchive(state, source: source);
  }

  Future<String> exportPortableBackup(String passphrase) =>
      encodePortableBackup(state, passphrase);

  Future<void> importArchive(
    String archiveSource, {
    bool force = false,
    String? passphrase,
  }) => _runMutation(() async {
    final incoming = await decodeBackup(
      archiveSource,
      passphrase: passphrase,
      targetUserId: _activeUser?.userId ?? state.userId,
      allowLegacy: true,
      rewrapForImport: true,
    );
    _checkSession();
    final active = _activeUser;
    if (!force &&
        active != null &&
        active.isAuthenticated &&
        incoming.userId.isNotEmpty &&
        incoming.userId != 'local-user' &&
        incoming.userId != active.userId) {
      throw Exception(
        'Restore rejected: This backup belongs to a different account. '
        'Restoring it will replace this account\'s wallet data.',
      );
    }
    if (!force && !LedgerState.isIncomingLedgerSafer(state, incoming)) {
      throw Exception(
        'Restore rejected: Your current local data is newer or has more '
        'transactions than the backup you are trying to restore. '
        'This prevents accidental data loss.',
      );
    }
    final stamped = (active != null && active.isAuthenticated)
        ? incoming.copyWith(userId: active.userId)
        : incoming;
    await _commit(
      stamped.copyWith(
        hasAuthoritativeEmptyWallet:
            stamped.accounts.isEmpty && stamped.transactions.isEmpty,
      ),
    );
    _setLoadState(
      LedgerLoadState.ready(hasPersistedLedger: _hasWalletData(state)),
    );
  });

  bool _isRestoring = false;

  Future<int> restoreLedgerState(
    LedgerState next, {
    String? expectedUserId,
    int? expectedLocalRevision,
  }) => _runMutation(() async {
    if (expectedUserId != null && _activeUser?.userId != expectedUserId) {
      throw const StaleLedgerSessionException();
    }
    if (expectedLocalRevision != null &&
        state.localRevision != expectedLocalRevision) {
      throw StateError('The local wallet changed during cloud restore.');
    }
    final prefs = await SharedPreferences.getInstance();
    _checkSession();
    if (expectedUserId != null &&
        (prefs.getBool('has_unsynced_changes') ?? false)) {
      throw StateError('Local changes are waiting to be uploaded.');
    }
    _isRestoring = true;
    try {
      await _commit(next.copyWith(version: currentLedgerStateVersion));
      _setLoadState(
        LedgerLoadState.ready(hasPersistedLedger: _hasWalletData(state)),
      );
      return state.localRevision;
    } finally {
      _isRestoring = false;
    }
  });

  Future<void> setHomeWidgetPreferences({
    List<String>? order,
    List<String>? hidden,
    Map<String, String>? sizes,
    Map<String, String>? filters,
  }) => _runMutation(() async {
    final preferences = state.preferences;
    await _commit(
      state.copyWith(
        preferences: preferences.copyWith(
          homeWidgetOrder: _normalizeStringList(
            order ?? preferences.homeWidgetOrder,
          ),
          homeWidgetHidden: _normalizeStringList(
            hidden ?? preferences.homeWidgetHidden,
          ),
          homeWidgetSizes: _normalizeStringMap(
            sizes ?? preferences.homeWidgetSizes,
          ),
          homeWidgetFilters: _normalizeStringMap(
            filters ?? preferences.homeWidgetFilters,
          ),
        ),
      ),
    );
  });

  Future<void> setHomeWidgetOrder(List<String> order) async {
    await setHomeWidgetPreferences(order: order);
  }

  Future<void> resetHomeWidgetOrder() => _runMutation(() async {
    const defaults = LedgerPreferences();
    await _commit(
      state.copyWith(
        preferences: state.preferences.copyWith(
          homeWidgetOrder: defaults.homeWidgetOrder,
          homeWidgetHidden: defaults.homeWidgetHidden,
          homeWidgetSizes: defaults.homeWidgetSizes,
          homeWidgetFilters: defaults.homeWidgetFilters,
        ),
      ),
    );
  });

  Future<void> setLocale(String locale) => _runMutation(() async {
    await _commit(
      state.copyWith(preferences: state.preferences.copyWith(locale: locale)),
    );
  });

  Future<void> setStartDayOfMonth(int day) => _runMutation(() async {
    await _commit(
      state.copyWith(
        preferences: state.preferences.copyWith(startDayOfMonth: day),
      ),
    );
  });

  Timer? _prefsSaveTimer;

  /// Replaces a complete snapshot. Field edits should use [updatePreferencesWith].
  Future<void> updatePreferences(LedgerPreferences preferences) =>
      updatePreferencesWith((_) => preferences);

  Future<void> updatePreferencesWith(
    LedgerPreferences Function(LedgerPreferences) update,
  ) => _runMutation(() async {
    final before = state.preferences;
    final preferences = update(before);
    final active = _activeUser;
    final prefs = await SharedPreferences.getInstance();
    _checkSession();
    if (!await prefs.setBool('has_unsynced_changes', true) ||
        !await prefs.setString(
          'last_local_modified_at',
          DateTime.now().toUtc().toIso8601String(),
        )) {
      throw StateError('Could not record the preference edit.');
    }
    _checkSession();
    state = state.copyWith(
      localRevision: state.localRevision + 1,
      userId:
          (active != null &&
              active.isAuthenticated &&
              (state.userId.isEmpty || state.userId == 'local-user'))
          ? active.userId
          : state.userId,
      preferences: preferences,
    );
    if (_capturePreferencesChanged(before, preferences)) {
      await _publishCaptureConfiguration();
      _checkSession();
      await SmsSpooler.updateTriggerWords(state);
      _checkSession();
      await NotificationSpooler.updateTriggerWords(state);
      _checkSession();
      _syncSpoolPolling();
    }

    // Debounce the heavy disk/cloud save to avoid OutOfMemory / extreme jank during slider drags
    _prefsSaveTimer?.cancel();
    final epoch = _sessionEpoch;
    _prefsSaveTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted || epoch != _sessionEpoch) return;
      unawaited(
        _runMutation(() async {
          await _repository.save(state);
          _checkSession();
        }),
      );
    });
  });

  Future<void> setDisplayCurrency(String currency) => _runMutation(() async {
    final normalized = currency.trim().toUpperCase();
    if (normalized.isEmpty) return;
    final enabled = <String>{
      ...state.preferences.enabledCurrencies.map(
        (value) => value.toUpperCase(),
      ),
      state.preferences.baseCurrency.toUpperCase(),
      normalized,
    }.toList()..sort();
    await _commit(
      state.copyWith(
        preferences: state.preferences.copyWith(
          displayCurrency: normalized,
          enabledCurrencies: enabled,
        ),
      ),
    );
  });

  Future<void> addTransaction({
    required String type,
    required String accountId,
    required int amountMinor,
    String status = 'cleared',
    String source = 'manual',
    String? counterAccountId,
    String? categoryId,
    String? paymentMethod,
    String? name,
    String? notes,
    List<String>? tags,
    DateTime? occurredAt,
  }) async {
    await upsertTransaction(
      type: type,
      accountId: accountId,
      amountMinor: amountMinor,
      status: status,
      source: source,
      counterAccountId: counterAccountId,
      categoryId: categoryId,
      paymentMethod: paymentMethod,
      name: name,
      notes: notes,
      occurredAt: occurredAt,
    );
  }

  Future<TransactionRecord> upsertTransaction({
    String? id,
    required String type,
    required String accountId,
    required int amountMinor,
    String status = 'cleared',
    String source = 'manual',
    String? counterAccountId,
    int? counterAmountMinor,
    int? originalAmountMinor,
    String? originalCurrency,
    String? categoryId,
    String? paymentMethod,
    String? locationLabel,
    String? name,
    String? notes,
    List<String>? tags,
    DateTime? occurredAt,
    String? recurrenceFrequency,
    int? recurrenceInterval,
    List<int>? recurrenceDaysOfWeek,
    List<int>? recurrenceDaysOfMonth,
    DateTime? recurrenceEndDate,
    int? recurrenceLimit,
    bool clearRecurrenceEndDate = false,
    bool clearRecurrenceLimit = false,
    bool clearOriginalAmount = false,
    bool? isExcludedFromReports,
    String? originalTransactionId,
    String? postMode,
  }) => _runMutation(
    () => _upsertTransaction(
      id: id,
      type: type,
      accountId: accountId,
      amountMinor: amountMinor,
      status: status,
      source: source,
      counterAccountId: counterAccountId,
      counterAmountMinor: counterAmountMinor,
      originalAmountMinor: originalAmountMinor,
      originalCurrency: originalCurrency,
      categoryId: categoryId,
      paymentMethod: paymentMethod,
      locationLabel: locationLabel,
      name: name,
      notes: notes,
      tags: tags,
      occurredAt: occurredAt,
      recurrenceFrequency: recurrenceFrequency,
      recurrenceInterval: recurrenceInterval,
      recurrenceDaysOfWeek: recurrenceDaysOfWeek,
      recurrenceDaysOfMonth: recurrenceDaysOfMonth,
      recurrenceEndDate: recurrenceEndDate,
      recurrenceLimit: recurrenceLimit,
      clearRecurrenceEndDate: clearRecurrenceEndDate,
      clearRecurrenceLimit: clearRecurrenceLimit,
      clearOriginalAmount: clearOriginalAmount,
      isExcludedFromReports: isExcludedFromReports,
      originalTransactionId: originalTransactionId,
      postMode: postMode,
    ),
  );

  Future<TransactionRecord> _upsertTransaction({
    String? id,
    required String type,
    required String accountId,
    required int amountMinor,
    String status = 'cleared',
    String source = 'manual',
    String? counterAccountId,
    int? counterAmountMinor,
    int? originalAmountMinor,
    String? originalCurrency,
    String? categoryId,
    String? paymentMethod,
    String? locationLabel,
    String? name,
    String? notes,
    List<String>? tags,
    DateTime? occurredAt,
    String? recurrenceFrequency,
    int? recurrenceInterval,
    List<int>? recurrenceDaysOfWeek,
    List<int>? recurrenceDaysOfMonth,
    DateTime? recurrenceEndDate,
    int? recurrenceLimit,
    bool clearRecurrenceEndDate = false,
    bool clearRecurrenceLimit = false,
    bool clearOriginalAmount = false,
    bool? isExcludedFromReports,
    String? originalTransactionId,
    String? postMode,
  }) async {
    final sourceAccount = accountById(state, accountId);
    if (sourceAccount == null) {
      throw StateError('Choose an account before saving.');
    }
    final existing = id == null ? null : _transactionById(state, id);
    final counterAccount = accountById(state, counterAccountId);
    final effectiveAmountMinor = type == 'adjustment'
        ? amountMinor
        : amountMinor.abs();
    final amount = Money(
      amountMinor: effectiveAmountMinor,
      currency: sourceAccount.currency,
    );
    final baseAmount = convertMoneyForDisplay(
      state,
      amount,
      state.preferences.baseCurrency,
    );

    Money? originalAmount;
    if (clearOriginalAmount) {
      originalAmount = null;
    } else if (originalAmountMinor != null &&
        originalCurrency != null &&
        originalCurrency.toUpperCase() !=
            sourceAccount.currency.toUpperCase()) {
      originalAmount = Money(
        amountMinor: originalAmountMinor,
        currency: originalCurrency.toUpperCase(),
      );
    } else if (originalCurrency != null &&
        originalCurrency.toUpperCase() ==
            sourceAccount.currency.toUpperCase()) {
      originalAmount = null;
    } else {
      originalAmount = existing?.originalAmount;
    }

    Money? counterAmount;
    if (counterAccount != null) {
      if (counterAmountMinor != null) {
        counterAmount = Money(
          amountMinor: counterAmountMinor,
          currency: counterAccount.currency,
        );
      } else if (counterAccount.currency.toUpperCase() ==
          sourceAccount.currency.toUpperCase()) {
        counterAmount = amount;
      } else {
        counterAmount = convertMoneyForDisplay(
          state,
          amount,
          counterAccount.currency,
        );
      }
    }

    double? fxRate;
    if (counterAmount != null &&
        counterAmount.currency.toUpperCase() != amount.currency.toUpperCase() &&
        amount.amountMinor != 0) {
      final counterMajor =
          counterAmount.amountMinor /
          math.pow(10, minorUnits(counterAmount.currency));
      final sourceMajor =
          amount.amountMinor / math.pow(10, minorUnits(amount.currency));
      if (sourceMajor != 0) {
        fxRate = counterMajor / sourceMajor;
      }
    }

    double? originalFxRate;
    if (originalAmount != null &&
        originalAmount.currency.toUpperCase() !=
            amount.currency.toUpperCase() &&
        originalAmount.amountMinor != 0) {
      final sourceMajor =
          amount.amountMinor / math.pow(10, minorUnits(amount.currency));
      final originalMajor =
          originalAmount.amountMinor /
          math.pow(10, minorUnits(originalAmount.currency));
      if (originalMajor != 0) {
        originalFxRate = sourceMajor / originalMajor;
      }
    }

    final transaction = TransactionRecord(
      id: existing?.id ?? id ?? _newId('tx'),
      type: type,
      status: status,
      source: source,
      accountId: sourceAccount.id,
      counterAccountId: counterAccount?.id,
      amount: amount,
      baseAmount: baseAmount,
      counterAmount: counterAmount,
      originalAmount: originalAmount,
      fxRate: fxRate,
      originalFxRate: originalFxRate,
      categoryId: type == 'transfer' || type == 'adjustment'
          ? null
          : categoryId,
      locationLabel: _blankToNull(locationLabel) ?? existing?.locationLabel,
      paymentMethod: _blankToNull(paymentMethod) ?? existing?.paymentMethod,
      name: _blankToNull(name) ?? existing?.name,
      notes: _blankToNull(notes),
      importBatchId: existing?.importBatchId,
      occurredAt: occurredAt ?? existing?.occurredAt ?? DateTime.now(),
      recurrenceFrequency: recurrenceFrequency ?? existing?.recurrenceFrequency,
      recurrenceInterval:
          recurrenceInterval ?? existing?.recurrenceInterval ?? 1,
      recurrenceDaysOfWeek:
          recurrenceDaysOfWeek ?? existing?.recurrenceDaysOfWeek,
      recurrenceDaysOfMonth:
          recurrenceDaysOfMonth ?? existing?.recurrenceDaysOfMonth,
      recurrenceEndDate: clearRecurrenceEndDate
          ? null
          : (recurrenceEndDate ?? existing?.recurrenceEndDate),
      recurrenceLimit: clearRecurrenceLimit
          ? null
          : (recurrenceLimit ?? existing?.recurrenceLimit),
      attachments: existing?.attachments ?? const [],
      tags: tags ?? existing?.tags ?? const [],
      isReimbursable: existing?.isReimbursable ?? false,
      isTaxDeductible: existing?.isTaxDeductible ?? false,
      isExcludedFromReports:
          isExcludedFromReports ?? existing?.isExcludedFromReports ?? false,
      sourceConfidence: existing?.sourceConfidence,
      externalRef: existing?.externalRef,
      originalTransactionId:
          originalTransactionId ?? existing?.originalTransactionId,
      postMode: postMode ?? existing?.postMode,
    );
    final transactions = [...state.transactions];
    final index = transactions.indexWhere((item) => item.id == transaction.id);
    if (index == -1) {
      transactions.insert(0, transaction);
    } else {
      transactions[index] = transaction;
    }

    final accounts = [...state.accounts];
    if (transaction.type == 'loan_repayment' &&
        transaction.status == 'scheduled' &&
        transaction.counterAccountId != null) {
      final loanIndex = accounts.indexWhere(
        (a) => a.id == transaction.counterAccountId,
      );
      if (loanIndex != -1) {
        final loan = accounts[loanIndex];
        if (loan.loanDetails != null) {
          final updatedDetails = loan.loanDetails!.copyWith(
            repaymentAmount: transaction.originalAmount ?? transaction.amount,
            recurrenceFrequency: transaction.recurrenceFrequency,
            recurrenceInterval: transaction.recurrenceInterval,
            recurrenceDaysOfWeek: transaction.recurrenceDaysOfWeek,
            recurrenceDaysOfMonth: transaction.recurrenceDaysOfMonth,
            recurrenceEndDate: transaction.recurrenceEndDate,
            recurrenceLimit: transaction.recurrenceLimit,
            repaymentStartsOn: transaction.occurredAt,
          );
          accounts[loanIndex] = loan.copyWith(loanDetails: updatedDetails);
        }
      }
    }

    await _commit(
      state.copyWith(transactions: transactions, accounts: accounts),
    );
    return transaction;
  }

  Future<TransactionRecord> updateTransactionStatus(
    String id,
    String status, {
    DateTime? occurredAt,
  }) => _runMutation(
    () => _updateTransactionStatus(id, status, occurredAt: occurredAt),
  );

  Future<TransactionRecord> _updateTransactionStatus(
    String id,
    String status, {
    DateTime? occurredAt,
  }) async {
    final existing = _transactionById(state, id);
    if (existing == null) throw StateError('Transaction not found.');
    return _upsertTransaction(
      id: existing.id,
      type: existing.type,
      accountId: existing.accountId,
      amountMinor: existing.amount.amountMinor,
      status: status,
      source: existing.source,
      counterAccountId: existing.counterAccountId,
      categoryId: existing.categoryId,
      paymentMethod: existing.paymentMethod,
      name: existing.name,
      notes: existing.notes,
      tags: existing.tags,
      occurredAt: occurredAt ?? existing.occurredAt,
      recurrenceFrequency: existing.recurrenceFrequency,
      isExcludedFromReports: existing.isExcludedFromReports,
      originalAmountMinor: existing.originalAmount?.amountMinor,
      originalCurrency: existing.originalAmount?.currency,
      counterAmountMinor: existing.counterAmount?.amountMinor,
      originalTransactionId: existing.originalTransactionId,
    );
  }

  Future<TransactionRecord> postponeTransaction(String id, DateTime newDate) =>
      _runMutation(() async {
        final existing = _transactionById(state, id);
        if (existing == null) throw StateError('Transaction not found.');
        return _updateTransactionStatus(
          id,
          existing.status,
          occurredAt: newDate,
        );
      });

  Future<void> deleteTransaction(String id) => _runMutation(() async {
    await _commit(
      state.copyWith(
        transactions: state.transactions
            .where((transaction) => transaction.id != id)
            .toList(),
      ),
    );
  });

  Future<void> deleteTransactions(Set<String> ids) => _runMutation(() async {
    await _commit(
      state.copyWith(
        transactions: state.transactions
            .where((transaction) => !ids.contains(transaction.id))
            .toList(),
      ),
    );
  });

  /// Merges multiple transactions from the same account into a single transaction.
  /// The amounts are summed up, notes are merged, and the original transactions
  /// are replaced by the newly created merged transaction.
  Future<TransactionRecord> mergeTransactions({
    required Set<String> transactionIds,
    String? categoryId,
    String? name,
    String? notes,
  }) => _runMutation(() async {
    if (transactionIds.length < 2) {
      throw ArgumentError('At least 2 transactions are required to merge.');
    }

    final targetList = state.transactions
        .where((t) => transactionIds.contains(t.id))
        .toList();

    if (targetList.length != transactionIds.length) {
      throw StateError('Some transactions to merge were not found.');
    }

    if (targetList.any((t) => t.type == 'transfer')) {
      throw ArgumentError('Transfers cannot be merged.');
    }

    // Constraint 1: Must be from the same account
    final firstAccountId = targetList.first.accountId;
    final allSameAccount = targetList.every(
      (t) => t.accountId == firstAccountId,
    );
    if (!allSameAccount) {
      throw ArgumentError(
        'All transactions must belong to the same account to be merged.',
      );
    }

    // Sort by occurredAt (newest first for latest timestamp, or oldest first)
    targetList.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    final latestTx = targetList.first;

    final firstType = targetList.first.type;
    final allSameType = targetList.every((t) => t.type == firstType);

    int netDeltaMinor = 0;
    int netBaseDeltaMinor = 0;
    for (final t in targetList) {
      final delta = sourceDelta(t);
      netDeltaMinor += delta;
      netBaseDeltaMinor += (delta >= 0
          ? t.baseAmount.amountMinor
          : -t.baseAmount.amountMinor);
    }

    final String mergedType;
    if (allSameType) {
      mergedType = firstType;
    } else {
      mergedType = netDeltaMinor >= 0 ? 'income' : 'expense';
    }

    // Sum amount (amountMinor)
    final totalAmountMinor = allSameType
        ? targetList.fold<int>(0, (sum, t) => sum + t.amount.amountMinor)
        : netDeltaMinor.abs();

    // Sum baseAmount
    final totalBaseAmountMinor = allSameType
        ? targetList.fold<int>(0, (sum, t) => sum + t.baseAmount.amountMinor)
        : netBaseDeltaMinor.abs();

    // Determine category: if passed explicitly, use it; else if all have same categoryId, use that
    final effectiveCategoryId =
        categoryId ??
        (targetList.every((t) => t.categoryId == targetList.first.categoryId)
            ? targetList.first.categoryId
            : null);

    // Default name if not provided
    final effectiveName = (name != null && name.trim().isNotEmpty)
        ? name.trim()
        : (targetList
                  .firstWhereOrNull(
                    (t) => t.name != null && t.name!.trim().isNotEmpty,
                  )
                  ?.name ??
              'Merged transaction');

    // Default notes if not provided: include source transactions info
    final effectiveNotes = (notes != null && notes.trim().isNotEmpty)
        ? notes.trim()
        : 'Merged from ${targetList.length} transactions:\n${targetList.map((t) => '• ${t.name ?? "Transaction"}: ${t.amount.amountMinor / 100} (${t.occurredAt.toLocal().toString().split(" ").first})').join('\n')}';

    final mergedTx = TransactionRecord(
      id: _newId('tx'),
      type: mergedType,
      status: targetList.any((t) => t.status == 'cleared')
          ? 'cleared'
          : targetList.first.status,
      source: 'manual',
      accountId: firstAccountId,
      amount: Money(
        amountMinor: totalAmountMinor,
        currency: latestTx.amount.currency,
      ),
      baseAmount: Money(
        amountMinor: totalBaseAmountMinor,
        currency: latestTx.baseAmount.currency,
      ),
      categoryId: effectiveCategoryId,
      occurredAt: latestTx.occurredAt,
      name: effectiveName,
      notes: effectiveNotes,
      attachments: [for (final t in targetList) ...t.attachments],
    );

    // Remove old transactions and prepend merged transaction
    final remainingTransactions = state.transactions
        .where((t) => !transactionIds.contains(t.id))
        .toList();

    await _commit(
      state.copyWith(transactions: [mergedTx, ...remainingTransactions]),
    );

    return mergedTx;
  });

  Future<void> addAttachment(
    String transactionId,
    TransactionAttachment attachment,
  ) => _runMutation(() async {
    final transactions = [...state.transactions];
    final index = transactions.indexWhere((item) => item.id == transactionId);
    if (index == -1) throw StateError('Transaction not found.');
    final existing = transactions[index];
    final updated = TransactionRecord(
      id: existing.id,
      type: existing.type,
      status: existing.status,
      source: existing.source,
      accountId: existing.accountId,
      counterAccountId: existing.counterAccountId,
      amount: existing.amount,
      baseAmount: existing.baseAmount,
      counterAmount: existing.counterAmount,
      originalAmount: existing.originalAmount,
      fxRate: existing.fxRate,
      originalFxRate: existing.originalFxRate,
      categoryId: existing.categoryId,
      locationLabel: existing.locationLabel,
      paymentMethod: existing.paymentMethod,
      name: existing.name,
      notes: existing.notes,
      importBatchId: existing.importBatchId,
      occurredAt: existing.occurredAt,
      recurrenceFrequency: existing.recurrenceFrequency,
      attachments: [...existing.attachments, attachment],
      isReimbursable: existing.isReimbursable,
      isTaxDeductible: existing.isTaxDeductible,
      isExcludedFromReports: existing.isExcludedFromReports,
      sourceConfidence: existing.sourceConfidence,
      externalRef: existing.externalRef,
      originalTransactionId: existing.originalTransactionId,
    );
    transactions[index] = updated;
    await _commit(state.copyWith(transactions: transactions));
  });

  Future<Account> upsertAccount({
    String? id,
    required String name,
    required String type,
    String currency = kDefaultCurrency,
    int? openingBalanceMinor,
    List<Money>? openingBalances,
    Color? color,
    String? institution,
    String? groupName,
    String? cardLast4,
    String? accountLast4,
    AccountLoanDetails? loanDetails,
    Map<String, String>? encryptedDetails,
    Money? creditLimit,
    int? statementDay,
    int? dueDay,
    int? notifyDaysBeforeDue,
    String? lastPaidBillMonth,
    bool includeInTotals = true,
    bool includeInReports = true,
    bool includeInNetWorth = true,
    bool showOnHome = true,
    bool isArchived = false,
  }) => _runMutation(() async {
    final existing = accountById(state, id);
    final isCash = type == 'cash';
    final resolvedOpeningBalances =
        openingBalances ?? existing?.openingBalances ?? const [];
    final effectiveCurrency = isCash
        ? (resolvedOpeningBalances.isNotEmpty
              ? resolvedOpeningBalances.first.currency
              : (currency.isNotEmpty
                    ? currency
                    : existing?.currency ?? state.preferences.baseCurrency))
        : (currency.isNotEmpty
              ? currency
              : existing?.currency ?? state.preferences.baseCurrency);
    final effectiveOpeningBalance = isCash
        ? (resolvedOpeningBalances.isNotEmpty
              ? resolvedOpeningBalances.first
              : (openingBalanceMinor == null
                    ? existing?.openingBalance ??
                          Money(amountMinor: 0, currency: effectiveCurrency)
                    : Money(
                        amountMinor: openingBalanceMinor,
                        currency: effectiveCurrency,
                      )))
        : (openingBalanceMinor == null
              ? existing?.openingBalance ??
                    Money(amountMinor: 0, currency: effectiveCurrency)
              : Money(
                  amountMinor: openingBalanceMinor,
                  currency: effectiveCurrency,
                ));
    final account = Account(
      id: existing?.id ?? id ?? _newId('acc'),
      name: name.trim().isEmpty ? 'New account' : name.trim(),
      type: type,
      currency: effectiveCurrency,
      openingBalance: effectiveOpeningBalance,
      openingBalances: resolvedOpeningBalances,
      color: color ?? existing?.color,
      institution: _blankToNull(institution),
      groupName: _blankToNull(groupName),
      cardLast4: _blankToNull(cardLast4),
      accountLast4: _blankToNull(accountLast4),
      loanDetails: loanDetails ?? existing?.loanDetails,
      encryptedDetails: encryptedDetails ?? existing?.encryptedDetails,
      creditLimit: creditLimit ?? existing?.creditLimit,
      statementDay: statementDay ?? existing?.statementDay,
      dueDay: dueDay ?? existing?.dueDay,
      notifyDaysBeforeDue: notifyDaysBeforeDue ?? existing?.notifyDaysBeforeDue,
      lastPaidBillMonth: lastPaidBillMonth ?? existing?.lastPaidBillMonth,
      includeInTotals: includeInTotals,
      includeInReports: includeInReports,
      includeInNetWorth: includeInNetWorth,
      showOnHome: showOnHome,
      isArchived: isArchived,
      sortOrder: existing?.sortOrder ?? state.accounts.length + 1,
    );

    final accounts = [...state.accounts];
    final index = accounts.indexWhere((item) => item.id == account.id);
    if (index == -1) {
      accounts.add(account);
    } else {
      accounts[index] = account;
    }

    // If the account is newly archived, pause any active scheduled transactions connected to it
    List<TransactionRecord> transactions = state.transactions;
    if (isArchived && existing?.isArchived != true) {
      transactions = state.transactions.map((transaction) {
        if ((transaction.accountId == account.id ||
                transaction.counterAccountId == account.id) &&
            transaction.status == 'scheduled') {
          return transaction.copyWith(status: 'paused');
        }
        return transaction;
      }).toList();
    }

    await _commit(
      state.copyWith(accounts: accounts, transactions: transactions),
    );
    return account;
  });

  Future<void> markCardBillPaid(String accountId, String? cycleMonth) =>
      _runMutation(() async {
        final account = accountById(state, accountId);
        if (account == null) return;
        final updated = account.copyWith(
          lastPaidBillMonth: cycleMonth,
          clearLastPaidBillMonth: cycleMonth == null,
        );
        final accounts = [
          for (final a in state.accounts) a.id == accountId ? updated : a,
        ];
        await _commit(state.copyWith(accounts: accounts));
      });

  Future<void> deleteAccount(String id) => _runMutation(() async {
    final isUsed = state.transactions.any(
      (transaction) =>
          transaction.accountId == id || transaction.counterAccountId == id,
    );

    // Cancel or pause any active scheduled transactions connected to this account
    final transactions = state.transactions.map((transaction) {
      if ((transaction.accountId == id || transaction.counterAccountId == id) &&
          transaction.status == 'scheduled') {
        return transaction.copyWith(status: 'paused');
      }
      return transaction;
    }).toList();

    if (isUsed) {
      // Mark as deleted so it is completely removed from all active and archived
      // account screens, but retain its historical snapshot (isDeleted = true, isArchived = true)
      // so older posted transactions keep their full account context and names.
      final accounts = [
        for (final account in state.accounts)
          account.id == id
              ? account.copyWith(
                  isDeleted: true,
                  isArchived: true,
                  includeInTotals: false,
                  includeInReports: false,
                  includeInNetWorth: false,
                  showOnHome: false,
                )
              : account,
      ];
      await _commit(
        state.copyWith(accounts: accounts, transactions: transactions),
      );
      return;
    }
    await _commit(
      state.copyWith(
        accounts: state.accounts.where((account) => account.id != id).toList(),
        transactions: transactions,
      ),
    );
  });

  Future<void> reorderAccounts(List<String> orderedIds) => _runMutation(
    () async {
      final updated = <Account>[];
      for (final account in state.accounts) {
        final index = orderedIds.indexOf(account.id);
        updated.add(
          account.copyWith(sortOrder: index == -1 ? account.sortOrder : index),
        );
      }
      await _commit(state.copyWith(accounts: updated));
    },
  );

  Future<void> upsertCategory({
    String? id,
    required String name,
    required String kind,
    String? parentId,
    bool isArchived = false,
    Color? color,
  }) => _runMutation(() async {
    final existing = categoryById(state, id);
    final normalizedParentId = _blankToNull(parentId);
    final parent = categoryById(state, normalizedParentId);
    final normalizedKind =
        parent?.kind ??
        existing?.kind ??
        (kind.trim().isEmpty ? 'expense' : kind.trim());
    final category = Category(
      id: existing?.id ?? id ?? _newId('cat'),
      name: name.trim().isEmpty ? 'New category' : name.trim(),
      kind: normalizedKind,
      color: color ?? existing?.color,
      parentId: normalizedParentId,
      isArchived: isArchived,
      sortOrder: existing?.sortOrder ?? state.categories.length + 1,
    );
    final categories = [...state.categories];
    final index = categories.indexWhere((item) => item.id == category.id);
    if (index == -1) {
      categories.add(category);
    } else {
      categories[index] = category;
    }
    await _commit(state.copyWith(categories: categories));
  });

  Future<void> archiveCategory(String id, {required bool archived}) =>
      _runMutation(() async {
        final idsToUpdate = <String>{id};
        if (archived) {
          void collectDescendants(String parentId) {
            for (final c in state.categories) {
              if (c.parentId == parentId && !idsToUpdate.contains(c.id)) {
                idsToUpdate.add(c.id);
                collectDescendants(c.id);
              }
            }
          }

          collectDescendants(id);
        }

        final categories = [
          for (final category in state.categories)
            idsToUpdate.contains(category.id)
                ? category.copyWith(isArchived: archived)
                : category,
        ];
        await _commit(state.copyWith(categories: categories));
      });

  Future<void> deleteCategory(String id) => _runMutation(() async {
    final isUsedInTx = state.transactions.any((t) => t.categoryId == id);
    final isUsedInRules =
        state.preferences.futureGenerationRules?.any(
          (r) => r.categoryId == id,
        ) ??
        false;
    final isUsedInCaptures = state.captureCandidates.any(
      (c) => c.suggestedCategoryId == id,
    );
    final hasChildren = state.categories.any((c) => c.parentId == id);
    final isUsed =
        isUsedInTx || isUsedInRules || isUsedInCaptures || hasChildren;

    if (isUsed) {
      await archiveCategory(id, archived: true);
    } else {
      final categories = state.categories
          .where((category) => category.id != id)
          .toList();
      await _commit(state.copyWith(categories: categories));
    }
  });

  Future<void> resetCategoriesToDefault({bool resetMerchantRules = true}) =>
      _runMutation(() async {
        final defaults = defaultCategories();
        var preferences = state.preferences;
        if (resetMerchantRules) {
          preferences = preferences.copyWith(merchantCategoryRules: const {});
        }
        final normalized = normalizeLedgerState(
          state.copyWith(categories: defaults, preferences: preferences),
          forceFullCategoryReferenceScan: true,
        );
        await _commit(normalized);
      });

  Future<void> updateCaptureCandidateStatus(String id, String status) =>
      _runMutation(() async {
        final candidates = [
          for (final candidate in state.captureCandidates)
            candidate.id == id ? candidate.copyWith(status: status) : candidate,
        ];
        await _commit(state.copyWith(captureCandidates: candidates));
      });

  Future<void> updateCaptureCandidateStatuses(
    Iterable<String> ids,
    String status,
  ) => _runMutation(() async {
    final idSet = ids.toSet();
    final candidates = [
      for (final candidate in state.captureCandidates)
        idSet.contains(candidate.id)
            ? candidate.copyWith(status: status)
            : candidate,
    ];
    await _commit(state.copyWith(captureCandidates: candidates));
  });

  Future<TransactionRecord> approveCaptureCandidate(String id) => _runMutation(
    () async {
      final candidate = _candidateById(state, id);
      if (candidate == null) {
        throw StateError('Capture candidate not found.');
      }
      if (candidate.parsedAmount == null) {
        throw StateError('Candidate has no parsed amount to post.');
      }
      final account =
          accountById(state, candidate.suggestedAccountId) ??
          state.accounts.where((account) => !account.isArchived).firstOrNull ??
          (state.accounts.isEmpty ? null : state.accounts.first);
      if (account == null) {
        throw StateError('Create an account before confirming captures.');
      }
      final type = candidate.transactionType == 'income' ? 'income' : 'expense';
      final category =
          categoryById(state, candidate.suggestedCategoryId) ??
          _matchCategory(state, candidate.merchant, type);
      Money amount;
      Money? originalAmount;
      final parsedCurrency = candidate.parsedAmount!.currency.toUpperCase();
      final accountCurrency = account.currency.toUpperCase();
      if (parsedCurrency != accountCurrency) {
        originalAmount = candidate.parsedAmount!;
        amount = convertMoneyForDisplay(
          state,
          candidate.parsedAmount!,
          account.currency,
        );
      } else {
        amount = candidate.parsedAmount!;
      }
      final baseAmount = convertMoneyForDisplay(
        state,
        amount,
        state.preferences.baseCurrency,
      );
      final transaction = TransactionRecord(
        id: _newId('cap-tx'),
        type: type,
        status: 'cleared',
        source: candidate.source,
        accountId: account.id,
        amount: amount,
        baseAmount: baseAmount,
        originalAmount: originalAmount,
        categoryId: category?.id,
        name: _blankToNull(candidate.merchant),
        occurredAt: candidate.createdAt,
        paymentMethod: candidate.source.toUpperCase(),
        notes: (candidate.rawText?.trim().isNotEmpty == true)
            ? candidate.rawText!.trim()
            : _blankToNull(candidate.merchant),
      );
      final candidates = [
        for (final item in state.captureCandidates)
          item.id == id ? item.copyWith(status: 'approved') : item,
      ];
      final preferences = _preferencesRememberingCategory(
        state,
        candidate.merchant,
        category?.id,
      );
      await _commit(
        state.copyWith(
          preferences: preferences,
          transactions: [transaction, ...state.transactions],
          captureCandidates: candidates,
        ),
      );
      return transaction;
    },
  );

  Future<void> updateCaptureCandidateDetails({
    required String id,
    required Money? parsedAmount,
    required String? merchant,
    required String transactionType,
    required String? suggestedAccountId,
    required String? suggestedCategoryId,
  }) => _runMutation(() async {
    final candidates = [
      for (final candidate in state.captureCandidates)
        candidate.id == id
            ? CaptureCandidate(
                id: candidate.id,
                source: candidate.source,
                status: candidate.status,
                createdAt: candidate.createdAt,
                rawText: candidate.rawText,
                parsedAmount: parsedAmount,
                merchant: _blankToNull(merchant),
                transactionType: transactionType == 'income'
                    ? 'income'
                    : 'expense',
                suggestedAccountId: _blankToNull(suggestedAccountId),
                suggestedCategoryId: _blankToNull(suggestedCategoryId),
                suggestedCategoryConfidence:
                    _blankToNull(suggestedCategoryId) ==
                        candidate.suggestedCategoryId
                    ? candidate.suggestedCategoryConfidence
                    : 1.0,
                suggestedCategoryReason:
                    _blankToNull(suggestedCategoryId) ==
                        candidate.suggestedCategoryId
                    ? candidate.suggestedCategoryReason
                    : 'Chosen during review',
              )
            : candidate,
    ];
    await _commit(state.copyWith(captureCandidates: candidates));
  });

  Future<void> rememberMerchantCategory({
    required String? merchant,
    required String? categoryId,
  }) => _runMutation(() async {
    final preferences = _preferencesRememberingCategory(
      state,
      merchant,
      categoryId,
    );
    if (identical(preferences, state.preferences)) return;
    await _commit(state.copyWith(preferences: preferences));
  });

  ({_CaptureDuplicateKind kind, String? matchedId, String? matchedType})?
  _captureDuplicateKind({
    required LedgerState state,
    required ParsedTransactionMessage parsed,
    required DateTime receivedAt,
    required String? matchedAccountId,
    Iterable<CaptureCandidate> additionalCandidates = const [],
  }) {
    bool sameRawText(CaptureCandidate c) =>
        c.rawText == parsed.rawText &&
        c.createdAt.difference(receivedAt).abs().inHours < 24;

    // 1. Exact raw-text match against pending candidates.
    for (final c in state.captureCandidates) {
      if (c.status == 'pending' && sameRawText(c)) {
        return (
          kind: _CaptureDuplicateKind.pendingText,
          matchedId: c.id,
          matchedType: 'candidate',
        );
      }
    }
    for (final c in additionalCandidates) {
      if (sameRawText(c)) {
        return (
          kind: _CaptureDuplicateKind.batch,
          matchedId: c.id,
          matchedType: 'candidate',
        );
      }
    }

    final amount = parsed.amount;
    if (amount != null) {
      bool isDuplicateCandidate(CaptureCandidate c) {
        if (c.status != 'pending') return false;
        final timeDiff = c.createdAt.difference(receivedAt).abs().inMinutes;
        if (timeDiff > 15) return false;

        if (c.parsedAmount?.amountMinor != amount.amountMinor ||
            c.parsedAmount?.currency.toUpperCase() !=
                amount.currency.toUpperCase()) {
          return false;
        }

        if (matchedAccountId != null &&
            c.suggestedAccountId == matchedAccountId) {
          return true;
        }
        if (parsed.last4 != null) {
          final acc = state.accounts.firstWhereOrNull(
            (a) => a.id == c.suggestedAccountId,
          );
          if (acc != null &&
              (acc.cardLast4 == parsed.last4 ||
                  acc.accountLast4 == parsed.last4)) {
            return true;
          }
          if (c.rawText != null && c.rawText!.contains(parsed.last4!)) {
            return true;
          }
        }

        if (c.merchant != null && parsed.merchant != null) {
          final cMerch = c.merchant!.trim().toLowerCase();
          final pMerch = parsed.merchant!.trim().toLowerCase();
          if (cMerch.isNotEmpty && pMerch.isNotEmpty) {
            final isSimilar =
                cMerch == pMerch ||
                (cMerch.length > 3 && pMerch.contains(cMerch)) ||
                (pMerch.length > 3 && cMerch.contains(pMerch));
            if (isSimilar) {
              return true;
            } else {
              // Known different merchants: not a duplicate
              return false;
            }
          }
        }

        if (matchedAccountId == null ||
            c.suggestedAccountId == null ||
            timeDiff <= 5) {
          return true;
        }
        return false;
      }

      // 2. Amount-based match against pending candidates.
      for (final c in state.captureCandidates) {
        if (isDuplicateCandidate(c)) {
          return (
            kind: _CaptureDuplicateKind.pendingAmount,
            matchedId: c.id,
            matchedType: 'candidate',
          );
        }
      }
      for (final c in additionalCandidates) {
        if (isDuplicateCandidate(c)) {
          return (
            kind: _CaptureDuplicateKind.batch,
            matchedId: c.id,
            matchedType: 'candidate',
          );
        }
      }

      // 3. Check against already-posted transactions.
      final matchedTx = _findDuplicateTransaction(
        state: state,
        parsed: parsed,
        amount: amount,
        receivedAt: receivedAt,
        matchedAccountId: matchedAccountId,
      );
      if (matchedTx != null) {
        return (
          kind: _CaptureDuplicateKind.postedTransaction,
          matchedId: matchedTx.id,
          matchedType: 'transaction',
        );
      }
    }

    return null;
  }

  /// Searches posted transactions for one that matches the parsed SMS.
  /// Looks at amount, account, date proximity, and merchant similarity.
  TransactionRecord? _findDuplicateTransaction({
    required LedgerState state,
    required ParsedTransactionMessage parsed,
    required Money amount,
    required DateTime receivedAt,
    required String? matchedAccountId,
  }) {
    for (final tx in state.transactions) {
      // Only consider live transactions (not void/scheduled).
      if (tx.status == 'void' || tx.status == 'scheduled') continue;

      // Amount must match.
      if (tx.amount.amountMinor != amount.amountMinor ||
          tx.amount.currency.toUpperCase() != amount.currency.toUpperCase()) {
        continue;
      }

      // Must be within 7 days of each other.
      final daysDiff = tx.occurredAt.difference(receivedAt).abs().inDays;
      if (daysDiff > 7) continue;

      // If we know the account, it must match.
      if (matchedAccountId != null && tx.accountId != matchedAccountId) {
        continue;
      }

      // Merchant similarity check (if both have one).
      if (parsed.merchant != null && tx.name != null) {
        final txName = tx.name!.trim().toLowerCase();
        final smsMerchant = parsed.merchant!.trim().toLowerCase();
        if (txName.isNotEmpty && smsMerchant.isNotEmpty) {
          final isSimilar =
              txName == smsMerchant ||
              (txName.length > 3 && smsMerchant.contains(txName)) ||
              (smsMerchant.length > 3 && txName.contains(smsMerchant));
          if (isSimilar) {
            return tx;
          } else {
            // Clearly different merchants: not a duplicate
            continue;
          }
        }
      }

      // Same account + same amount + within 24 hours is a strong signal.
      if (matchedAccountId != null && daysDiff <= 1) {
        return tx;
      }

      // Same amount within 24 hours without account info is still a likely
      // match (e.g. user manually entered it).
      if (daysDiff == 0) {
        return tx;
      }
    }
    return null;
  }

  CaptureImportResult previewSmsMessage(
    String rawText, {
    DateTime? receivedAt,
  }) {
    return _evaluateCaptureMessage(
      rawText: rawText,
      source: 'sms',
      triggerWords: state.preferences.smsTriggerWords,
      ignoreWords: state.preferences.smsIgnoreWords,
      receivedAt: receivedAt,
    );
  }

  CaptureImportResult previewNotificationMessage(
    String rawText, {
    DateTime? receivedAt,
  }) {
    return _evaluateCaptureMessage(
      rawText: rawText,
      source: 'notification',
      triggerWords: state.preferences.notificationTriggerWords,
      ignoreWords: state.preferences.notificationIgnoreWords,
      receivedAt: receivedAt,
    );
  }

  Future<CaptureCandidate?> importSmsMessage(
    String rawText, {
    DateTime? receivedAt,
  }) async {
    final result = await importSmsMessageDetailed(
      rawText,
      receivedAt: receivedAt,
    );
    return result.candidate;
  }

  Future<CaptureImportResult> importSmsMessageDetailed(
    String rawText, {
    DateTime? receivedAt,
    String stage = 'manual-sms',
    bool nativeAccepted = false,
    bool notificationShown = false,
    bool forceQueue = false,
  }) {
    return _importCaptureMessage(
      rawText: rawText,
      source: 'sms',
      stage: stage,
      triggerWords: state.preferences.smsTriggerWords,
      ignoreWords: state.preferences.smsIgnoreWords,
      receivedAt: receivedAt,
      nativeAccepted: nativeAccepted,
      notificationShown: notificationShown,
      forceQueue: forceQueue,
    );
  }

  Future<CaptureImportResult> importNotificationMessageDetailed(
    String rawText, {
    DateTime? receivedAt,
    String stage = 'manual-notification',
    bool nativeAccepted = false,
    bool notificationShown = false,
    bool forceQueue = false,
  }) {
    return _importCaptureMessage(
      rawText: rawText,
      source: 'notification',
      stage: stage,
      triggerWords: state.preferences.notificationTriggerWords,
      ignoreWords: state.preferences.notificationIgnoreWords,
      receivedAt: receivedAt,
      nativeAccepted: nativeAccepted,
      notificationShown: notificationShown,
      forceQueue: forceQueue,
    );
  }

  Future<CaptureImportResult> _importCaptureMessage({
    required String rawText,
    required String source,
    required String stage,
    required List<String> triggerWords,
    required List<String> ignoreWords,
    DateTime? receivedAt,
    bool nativeAccepted = false,
    bool notificationShown = false,
    bool forceQueue = false,
  }) => _runMutation(() async {
    final result = _evaluateCaptureMessage(
      rawText: rawText,
      source: source,
      triggerWords: triggerWords,
      ignoreWords: ignoreWords,
      receivedAt: receivedAt,
      nativeAccepted: nativeAccepted,
      notificationShown: notificationShown,
      forceQueue: forceQueue,
    );

    if (result.queued && result.candidate != null) {
      var nextAccounts = state.accounts;
      if (isBillStatementMessage(rawText)) {
        final notice = parseBillStatementNotice(
          rawText,
          fallbackCurrency: state.preferences.baseCurrency,
          receivedAt: receivedAt,
        );
        if (notice != null) {
          final updatedAcc = _applyStatementToAccount(
            currentState: state,
            notice: notice,
          );
          if (updatedAcc != null) {
            nextAccounts = state.accounts
                .map((a) => a.id == updatedAcc.id ? updatedAcc : a)
                .toList();
          }
        }
      }

      await _commit(
        state.copyWith(
          accounts: nextAccounts,
          captureCandidates: [result.candidate!, ...state.captureCandidates],
        ),
      );
    }

    await CaptureDiagnostics.recordResult(
      stage: stage,
      result: result,
      ownerId: state.userId,
    );
    return result;
  });

  CaptureImportResult _evaluateCaptureMessage({
    required String rawText,
    required String source,
    required List<String> triggerWords,
    required List<String> ignoreWords,
    DateTime? receivedAt,
    bool nativeAccepted = false,
    bool notificationShown = false,
    bool forceQueue = false,
    Iterable<CaptureCandidate> additionalCandidates = const [],
    String? nativeMatchedAmount,
    String? nativeMatchedTriggerWord,
  }) {
    final actualReceivedAt = receivedAt ?? DateTime.now();

    for (final pattern in state.preferences.smsBlockPatterns) {
      if (pattern.trim().isEmpty) continue;
      try {
        final regex = RegExp(pattern, caseSensitive: false);
        if (regex.hasMatch(rawText)) {
          return CaptureImportResult(
            source: source,
            status: CaptureImportStatus.ignored,
            reason: CaptureBlockReason.blockedPattern,
            receivedAt: actualReceivedAt,
            parsed: const ParsedTransactionMessage(rawText: '', ignored: true),
            nativeAccepted: nativeAccepted,
            notificationShown: notificationShown,
          );
        }
      } catch (_) {
        // Ignore invalid regex patterns
      }
    }

    final isStatement = isBillStatementMessage(rawText);
    final statementNotice = isStatement
        ? parseBillStatementNotice(
            rawText,
            fallbackCurrency: state.preferences.baseCurrency,
            receivedAt: actualReceivedAt,
          )
        : null;

    final parsed = parseTransactionMessage(
      rawText,
      fallbackCurrency: state.preferences.baseCurrency,
      triggerWords: triggerWords,
      ignoreWords: ignoreWords,
    );

    final blockReason = blockReasonForParsedMessage(parsed);
    if (parsed.rawText.trim().isEmpty) {
      return CaptureImportResult(
        source: source,
        status: CaptureImportStatus.ignored,
        reason: CaptureBlockReason.empty,
        receivedAt: actualReceivedAt,
        parsed: parsed,
        nativeAccepted: nativeAccepted,
        notificationShown: notificationShown,
      );
    }
    if (parsed.ignored && !forceQueue && statementNotice == null) {
      return CaptureImportResult(
        source: source,
        status: CaptureImportStatus.ignored,
        reason: blockReason,
        receivedAt: actualReceivedAt,
        parsed: parsed,
        nativeAccepted: nativeAccepted,
        notificationShown: notificationShown,
      );
    }

    Money? parsedAmount = statementNotice?.amount ?? parsed.amount;
    if (parsedAmount == null &&
        nativeMatchedAmount != null &&
        nativeMatchedAmount.trim().isNotEmpty) {
      final fallbackParsed = parseTransactionMessage(
        nativeMatchedAmount.trim(),
        fallbackCurrency: state.preferences.baseCurrency,
        triggerWords: triggerWords,
        ignoreWords: ignoreWords,
      );
      parsedAmount = fallbackParsed.amount;
    }

    String? statementMerchant;
    String? matchedAccountId;
    if (statementNotice != null) {
      final matchedAcc = matchAccountForStatement(state, statementNotice);
      matchedAccountId = matchedAcc?.id;
      final inst = statementNotice.institution ?? matchedAcc?.name;
      statementMerchant = inst != null ? '$inst Bill' : 'Credit Card Statement';
    }

    final effectiveParsed = ParsedTransactionMessage(
      rawText: parsed.rawText.isNotEmpty ? parsed.rawText : rawText,
      ignored: statementNotice != null ? false : parsed.ignored,
      hasAmount: parsedAmount != null,
      hasTriggerWord:
          statementNotice != null ||
          parsed.hasTriggerWord ||
          nativeMatchedTriggerWord != null,
      amount: parsedAmount,
      merchant: statementMerchant ?? parsed.merchant,
      transactionType: statementNotice != null
          ? 'expense'
          : parsed.transactionType,
      last4: statementNotice?.last4 ?? parsed.last4,
      institutionName: statementNotice?.institution ?? parsed.institutionName,
      matchedTriggerWord: statementNotice != null
          ? 'bill'
          : (parsed.matchedTriggerWord ?? nativeMatchedTriggerWord),
      matchedIgnoreWord: statementNotice != null
          ? null
          : parsed.matchedIgnoreWord,
    );

    matchedAccountId ??= _matchAccountToSms(state, effectiveParsed);
    final duplicateMatch = _captureDuplicateKind(
      state: state,
      parsed: effectiveParsed,
      receivedAt: actualReceivedAt,
      matchedAccountId: matchedAccountId,
      additionalCandidates: additionalCandidates,
    );
    if (duplicateMatch != null &&
        !(forceQueue &&
            duplicateMatch.kind == _CaptureDuplicateKind.postedTransaction)) {
      return CaptureImportResult(
        source: source,
        status: CaptureImportStatus.duplicate,
        reason: _reasonForDuplicate(duplicateMatch.kind),
        receivedAt: actualReceivedAt,
        parsed: effectiveParsed,
        nativeAccepted: nativeAccepted,
        notificationShown: notificationShown,
        duplicateOfId: duplicateMatch.matchedId,
        duplicateOfType: duplicateMatch.matchedType,
      );
    }

    final type = effectiveParsed.transactionType == 'income'
        ? 'income'
        : 'expense';
    final category = _suggestCategory(
      state,
      effectiveParsed.merchant ?? effectiveParsed.rawText,
      type,
      isMerchant:
          effectiveParsed.merchant != null &&
          effectiveParsed.merchant!.isNotEmpty,
    );
    final candidate = CaptureCandidate(
      id: _newId('cap'),
      source: source,
      status: 'pending',
      createdAt: actualReceivedAt,
      rawText: effectiveParsed.rawText.isNotEmpty
          ? effectiveParsed.rawText
          : rawText,
      parsedAmount: parsedAmount,
      merchant: effectiveParsed.merchant,
      transactionType: type,
      suggestedAccountId: matchedAccountId,
      suggestedCategoryId: category?.category.id,
      suggestedCategoryConfidence: category?.confidence,
      suggestedCategoryReason: category?.reason,
    );
    return CaptureImportResult(
      source: source,
      status: CaptureImportStatus.queued,
      receivedAt: actualReceivedAt,
      parsed: effectiveParsed,
      candidate: candidate,
      nativeAccepted: nativeAccepted,
      notificationShown: notificationShown,
      categoryId: category?.category.id,
      categoryReason: category?.reason,
    );
  }

  Future<List<CaptureImportResult>> importSmsMessagesBatchDetailed(
    List<({String text, DateTime receivedAt})> messages,
  ) => _runMutation(() async {
    final results = <CaptureImportResult>[];
    final newCandidates = <CaptureCandidate>[];
    final updatedAccounts = <String, Account>{};

    for (final message in messages) {
      if (isBillStatementMessage(message.text)) {
        final notice = parseBillStatementNotice(
          message.text,
          fallbackCurrency: state.preferences.baseCurrency,
          receivedAt: message.receivedAt,
        );
        if (notice != null) {
          final updatedAcc = _applyStatementToAccount(
            currentState: state,
            notice: notice,
          );
          if (updatedAcc != null) {
            updatedAccounts[updatedAcc.id] = updatedAcc;
          }
        }
      }

      final result = _evaluateCaptureMessage(
        rawText: message.text,
        source: 'sms',
        triggerWords: state.preferences.smsTriggerWords,
        ignoreWords: state.preferences.smsIgnoreWords,
        receivedAt: message.receivedAt,
        additionalCandidates: newCandidates,
      );
      if (result.queued && result.candidate != null) {
        newCandidates.add(result.candidate!);
      }
      results.add(result);
    }

    var nextAccounts = state.accounts;
    if (updatedAccounts.isNotEmpty) {
      nextAccounts = state.accounts
          .map((a) => updatedAccounts[a.id] ?? a)
          .toList();
    }

    // Single atomic commit for all discovered candidates and account updates from the batch
    if (newCandidates.isNotEmpty || updatedAccounts.isNotEmpty) {
      await _commit(
        state.copyWith(
          accounts: nextAccounts,
          captureCandidates: [...newCandidates, ...state.captureCandidates],
        ),
      );
    }

    return results;
  });

  Future<List<CaptureCandidate>> importSmsMessagesBatch(
    List<({String text, DateTime receivedAt})> messages,
  ) async {
    final results = await importSmsMessagesBatchDetailed(messages);
    return results
        .where((result) => result.queued)
        .map((result) => result.candidate)
        .whereType<CaptureCandidate>()
        .toList();
  }

  Future<List<CaptureImportResult>> importNotificationsBatchDetailed(
    List<({String text, DateTime receivedAt, String? sender})> notifications,
  ) => _runMutation(() async {
    final results = <CaptureImportResult>[];
    final newCandidates = <CaptureCandidate>[];
    final updatedAccounts = <String, Account>{};

    for (final notification in notifications) {
      if (isBillStatementMessage(notification.text)) {
        final notice = parseBillStatementNotice(
          notification.text,
          fallbackCurrency: state.preferences.baseCurrency,
          receivedAt: notification.receivedAt,
        );
        if (notice != null) {
          final updatedAcc = _applyStatementToAccount(
            currentState: state,
            notice: notice,
          );
          if (updatedAcc != null) {
            updatedAccounts[updatedAcc.id] = updatedAcc;
          }
        }
      }

      final result = _evaluateCaptureMessage(
        rawText: notification.text,
        source: 'notification',
        triggerWords: state.preferences.notificationTriggerWords,
        ignoreWords: state.preferences.notificationIgnoreWords,
        receivedAt: notification.receivedAt,
        additionalCandidates: newCandidates,
      );
      if (result.queued && result.candidate != null) {
        newCandidates.add(result.candidate!);
      }
      results.add(result);
      await CaptureDiagnostics.recordResult(
        ownerId: state.userId,
        stage: 'scan-notification',
        result: result,
      );
    }

    var nextAccounts = state.accounts;
    if (updatedAccounts.isNotEmpty) {
      nextAccounts = state.accounts
          .map((a) => updatedAccounts[a.id] ?? a)
          .toList();
    }

    if (newCandidates.isNotEmpty || updatedAccounts.isNotEmpty) {
      await _commit(
        state.copyWith(
          accounts: nextAccounts,
          captureCandidates: [...newCandidates, ...state.captureCandidates],
        ),
      );
    }

    return results;
  });

  Future<List<CaptureCandidate>> importNotificationsBatch(
    List<({String text, DateTime receivedAt, String? sender})> notifications,
  ) async {
    final results = await importNotificationsBatchDetailed(notifications);
    return results
        .where((result) => result.queued)
        .map((result) => result.candidate)
        .whereType<CaptureCandidate>()
        .toList();
  }

  Future<int> importWalletCsvRows(
    List<ParsedWalletCsvRow> rows,
  ) => _runMutation(() async {
    if (rows.isEmpty) return 0;
    if (state.accounts.isEmpty) {
      throw StateError('Create an account before importing CSV rows.');
    }
    final batchId = _newId('import');
    final imported = <TransactionRecord>[];
    var duplicateCount = 0;
    final seenSignatures = {
      for (final transaction in state.transactions)
        _transactionSignature(transaction),
    };
    for (final row in rows) {
      final account =
          _matchAccount(state, row.accountName) ?? state.accounts.first;
      final category = _matchCategory(state, row.categoryName, row.type);
      final amount = row.amount.copyWith(currency: account.currency);
      final signature = _rowSignature(row, account.id, category?.id);
      if (seenSignatures.contains(signature)) {
        duplicateCount++;
        continue;
      }
      seenSignatures.add(signature);
      imported.add(
        TransactionRecord(
          id: _newId('csv'),
          type: row.type,
          status: 'cleared',
          source: 'import',
          accountId: account.id,
          amount: amount,
          baseAmount: amount.copyWith(currency: state.preferences.baseCurrency),
          categoryId: category?.id,
          occurredAt: row.occurredAt ?? DateTime.now(),
          notes: _blankToNull(row.notes) ?? 'Imported CSV row ${row.rowNumber}',
          importBatchId: batchId,
        ),
      );
    }
    final batch = ImportBatch(
      id: batchId,
      source: 'wallet_csv',
      status: 'posted',
      createdAt: DateTime.now(),
      rowCount: rows.length,
      importedCount: imported.length,
      duplicateCount: duplicateCount,
    );
    await _commit(
      state.copyWith(
        transactions: [...imported, ...state.transactions],
        importBatches: [batch, ...state.importBatches],
      ),
    );
    return imported.length;
  });

  Future<int> rollbackImportBatch(String batchId) => _runMutation(() async {
    final batch = _importBatchById(state, batchId);
    if (batch == null) throw StateError('Import batch not found.');
    if (batch.status == 'rolled_back') return 0;
    final beforeCount = state.transactions.length;
    final transactions = state.transactions
        .where((transaction) => transaction.importBatchId != batchId)
        .toList();
    final removed = beforeCount - transactions.length;
    final batches = [
      for (final item in state.importBatches)
        item.id == batchId ? item.copyWith(status: 'rolled_back') : item,
    ];
    await _commit(
      state.copyWith(transactions: transactions, importBatches: batches),
    );
    return removed;
  });

  Future<void> addEnabledCurrency(String currency) => _runMutation(() async {
    final normalized = currency.trim().toUpperCase();
    if (normalized.isEmpty) return;
    if (state.preferences.enabledCurrencies.contains(normalized)) return;
    final enabled = <String>{
      ...state.preferences.enabledCurrencies,
      normalized,
    }.toList()..sort();
    await _commit(
      state.copyWith(
        preferences: state.preferences.copyWith(enabledCurrencies: enabled),
      ),
    );
  });

  Future<void> removeEnabledCurrency(String currency) => _runMutation(() async {
    final normalized = currency.trim().toUpperCase();
    if (normalized == state.preferences.baseCurrency.toUpperCase()) return;
    final enabled = state.preferences.enabledCurrencies
        .where((c) => c.toUpperCase() != normalized)
        .toList();
    final newRates = state.exchangeRates
        .where(
          (r) =>
              r.base.toUpperCase() != normalized &&
              r.quote.toUpperCase() != normalized,
        )
        .toList();
    final isDisplay =
        normalized == state.preferences.displayCurrency.toUpperCase();
    final displayCurrency = isDisplay
        ? state.preferences.baseCurrency
        : state.preferences.displayCurrency;
    await _commit(
      state.copyWith(
        preferences: state.preferences.copyWith(
          enabledCurrencies: enabled,
          displayCurrency: displayCurrency,
        ),
        exchangeRates: newRates,
      ),
    );
  });

  Future<void> setExchangeRate({
    required String base,
    required String quote,
    required double rate,
  }) => _runMutation(() async {
    final normalizedBase = base.trim().toUpperCase();
    final normalizedQuote = quote.trim().toUpperCase();
    if (normalizedBase == normalizedQuote) return;

    final existingIndex = state.exchangeRates.indexWhere(
      (r) =>
          r.base.toUpperCase() == normalizedBase &&
          r.quote.toUpperCase() == normalizedQuote,
    );

    final record = ExchangeRateRecord(
      base: normalizedBase,
      quote: normalizedQuote,
      rate: rate,
      asOfDate: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final rates = [...state.exchangeRates];
    if (existingIndex >= 0) {
      rates[existingIndex] = record;
    } else {
      rates.add(record);
    }
    await _commit(state.copyWith(exchangeRates: rates));
  });

  Future<void> setExchangeRatesDirectly(List<ExchangeRateRecord> rates) =>
      _runMutation(() async {
        await _commit(state.copyWith(exchangeRates: rates));
      });

  Timer? _autoBackupTimer;
  Future<void> _backupTail = Future<void>.value();

  /// Auto-archives loan accounts whose current balance has reached
  /// zero (fully paid off) and pauses their associated scheduled EMIs.
  LedgerState _applyAutoArchiveForPaidOffLoans(LedgerState next) {
    if (!next.accounts.any((a) => !a.isArchived && a.type == 'loan')) {
      return next;
    }
    final accounts = [...next.accounts];
    var transactions = next.transactions;
    bool changed = false;

    for (int i = 0; i < accounts.length; i++) {
      final account = accounts[i];
      if (account.isArchived) continue;
      if (account.type != 'loan') continue;

      // Only auto-archive loans that had a principal or initial negative balance
      final principalMinor =
          account.loanDetails?.principal?.amountMinor.abs() ??
          (account.openingBalance.amountMinor < 0
              ? -account.openingBalance.amountMinor
              : 0);
      if (principalMinor <= 0) continue;

      // Ensure the loan actually has recorded activity or was initialized with debt
      final hasTransactions = next.transactions.any(
        (tx) => tx.accountId == account.id || tx.counterAccountId == account.id,
      );
      if (account.openingBalance.amountMinor >= 0 && !hasTransactions) {
        continue;
      }

      // Balance >= 0 means the loan has been fully paid off
      final remaining = accountBalance(next, account).amountMinor;
      if (remaining < 0) continue;

      // Archive the account
      accounts[i] = account.copyWith(isArchived: true);
      changed = true;

      // Pause any scheduled EMI transactions linked to this loan
      transactions = transactions.map((tx) {
        if ((tx.accountId == account.id || tx.counterAccountId == account.id) &&
            tx.status == 'scheduled') {
          return tx.copyWith(status: 'paused');
        }
        return tx;
      }).toList();
    }

    if (!changed) return next;
    return next.copyWith(accounts: accounts, transactions: transactions);
  }

  Future<void> _commit(LedgerState next) async {
    final active = _activeUser;
    final withOwner =
        (active != null &&
            active.isAuthenticated &&
            (next.userId.isEmpty || next.userId == 'local-user'))
        ? next.copyWith(userId: active.userId)
        : next;

    // Auto-archive any loan accounts that have been fully paid off before
    // normalizing, so the rest of the system sees them as archived immediately.
    final withAutoArchived = _applyAutoArchiveForPaidOffLoans(withOwner);

    // Skip the expensive category taxonomy rebuild once the ledger is
    // already on the current version: every path that can hand us an
    // out-of-date/unnormalized ledger (archive decode, cloud restore
    // parsing) always fully normalizes before we ever see it here, so by the
    // time `next.version == currentLedgerStateVersion` the categories are
    // already taxonomy-normalized. This keeps `_commit` (called on every
    // user edit) cheap while still fully migrating+normalizing genuinely
    // legacy/out-of-date states.
    final normalized = normalizeLedgerState(withAutoArchived).copyWith(
      localRevision: state.localRevision + 1,
      ingressReceipts: Set<String>.unmodifiable({
        ...state.ingressReceipts,
        ...withAutoArchived.ingressReceipts,
      }),
      hasAuthoritativeEmptyWallet:
          withAutoArchived.accounts.isEmpty &&
          withAutoArchived.transactions.isEmpty &&
          (_isRestoring ||
              state.hasAuthoritativeEmptyWallet ||
              withAutoArchived.hasAuthoritativeEmptyWallet ||
              state.accounts.isNotEmpty ||
              state.transactions.isNotEmpty),
    );
    _checkSession();
    if (active != null &&
        active.isAuthenticated &&
        normalized.userId != active.userId) {
      throw StateError('The wallet belongs to a different session.');
    }

    // Mark this edit unsynced *before* mutating `state` (and before the
    // `await _repository.save(...)` below) — not after both, as an earlier
    // version of this method did. `state` is what CloudSyncController reads
    // (via `ledgerProvider`) the instant a remote `users/{uid}` snapshot
    // event fires; `has_unsynced_changes` is the flag it reads to decide
    // whether a pull is safe to apply (`shouldAcceptCloudRestore()`). If
    // `state` were mutated first and this flag flipped only after the
    // `await _repository.save(...)` below, a remote snapshot event landing
    // in that window would find `state` already reflecting this edit but
    // `has_unsynced_changes` still `false` — wrongly treating an overwrite of
    // this just-made, not-yet-recorded-as-unsynced edit as safe. Setting the
    // flag first and awaiting it to complete before `state = normalized`
    // closes that window: since nothing yields control between the two
    // (Dart only switches tasks at `await`/microtask boundaries), any other
    // callback can only ever observe both together, never the flag stale
    // and `state` already updated.
    if (!_isRestoring) {
      final prefs = await SharedPreferences.getInstance();
      _checkSession();
      if (!await prefs.setBool('has_unsynced_changes', true)) {
        throw StateError('Could not mark the wallet unsynced.');
      }
      _checkSession();
      if (!await prefs.setString(
        'last_local_modified_at',
        DateTime.now().toUtc().toIso8601String(),
      )) {
        throw StateError('Could not record the wallet edit.');
      }
      _checkSession();
      if (active != null && active.isAuthenticated) {
        if (!await prefs.setString(_lastActiveUserIdKey, active.userId)) {
          throw StateError('Could not persist wallet ownership.');
        }
        _checkSession();
      }
    }

    _checkSession();
    final prevPrefs = state.preferences;
    final nextPrefs = normalized.preferences;
    final capturePrefsChanged = _capturePreferencesChanged(
      prevPrefs,
      nextPrefs,
    );

    state = normalized;
    await _repository.save(normalized);
    _checkSession();

    if (capturePrefsChanged) {
      await _publishCaptureConfiguration();
      _checkSession();
      await SmsSpooler.updateTriggerWords(normalized);
      _checkSession();
      await NotificationSpooler.updateTriggerWords(normalized);
      _checkSession();
      _syncSpoolPolling();
    }

    if (!_isRestoring) {
      _autoBackupTimer?.cancel();
      if (!LedgerProvidersConfig.disableAutoBackup) {
        final backupUser = _activeUser;
        _autoBackupTimer = Timer(const Duration(seconds: 3), () {
          unawaited(_performAutoBackup(normalized, userOverride: backupUser));
        });
      }
    }
  }

  Future<void> _performAutoBackup(
    LedgerState ledger, {
    LedgerUserIdentity? userOverride,
  }) {
    final epoch = _sessionEpoch;
    final task = _backupTail.then(
      (_) => _writeAutoBackupSnapshot(
        ledger,
        userOverride: userOverride,
        epoch: epoch,
      ),
    );
    _backupTail = task.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        if (error is StaleLedgerSessionException) return;
        debugPrint('Automatic backup failed: $error');
        debugPrintStack(stackTrace: stack);
      },
    );
    return task;
  }

  void _checkBackupSession(int epoch) {
    if (!mounted || epoch != _sessionEpoch) {
      throw const StaleLedgerSessionException();
    }
  }

  Future<void> _writeAutoBackupSnapshot(
    LedgerState ledger, {
    LedgerUserIdentity? userOverride,
    required int epoch,
  }) async {
    if (foundation.kIsWeb) return;
    try {
      _checkBackupSession(epoch);
      final user = userOverride ?? _activeUser;
      final suffix = buildUserBackupFileSuffix(
        displayName: user?.displayName,
        email: user?.email,
        userId: user?.userId ?? ledger.userId,
      );
      final archive = await encodeDeviceBackup(ledger);
      _checkBackupSession(epoch);

      final docsDir = await getApplicationSupportDirectory();
      _checkBackupSession(epoch);
      await _writeAutoBackupToDirectory(
        Directory('${docsDir.path}/1Wallet'),
        archive,
        ledger,
        suffix: suffix,
      );
    } catch (e) {
      debugPrint('Auto backup failed: $e');
      rethrow;
    }
  }

  Future<void> _writeAutoBackupToDirectory(
    Directory dir,
    String archive,
    LedgerState ledger, {
    String? suffix,
  }) async {
    await dir.create(recursive: true);
    final mainName = buildAutoBackupFileName(suffix: suffix);
    final prevName = buildAutoBackupFileName(
      suffix: suffix,
      variant: 'previous',
    );
    final safetyName = buildAutoBackupFileName(
      suffix: suffix,
      variant: 'safety',
    );
    final mainFile = File('${dir.path}/$mainName');
    final prevFile = File('${dir.path}/$prevName');
    final safetyFile = File('${dir.path}/$safetyName');

    if (await mainFile.exists()) {
      try {
        final existingContent = await mainFile.readAsString();
        final existing = await decodeBackup(
          existingContent,
          targetUserId: ledger.userId,
          allowLegacy: true,
        );
        final isSafer = LedgerState.isIncomingLedgerSafer(existing, ledger);
        // If the existing backup has more transactions or newer records than the current ledger,
        // protect it from being lost by saving it as a safety backup!
        if (!isSafer) {
          await mainFile.copy(safetyFile.path);
        } else {
          await mainFile.copy(prevFile.path);
        }
      } catch (_) {
        try {
          await mainFile.copy(prevFile.path);
        } catch (_) {}
      }
    }
    final temporary = File('${mainFile.path}.tmp');
    await temporary.writeAsString(archive, flush: true);
    await temporary.rename(mainFile.path);
  }

  @foundation.visibleForTesting
  Future<void> writeAutoBackupToDirectoryForTesting(
    Directory dir,
    LedgerState ledger, {
    LedgerUserIdentity? userOverride,
  }) async {
    final user = userOverride ?? _activeUser;
    final suffix = buildUserBackupFileSuffix(
      displayName: user?.displayName,
      email: user?.email,
      userId: user?.userId ?? ledger.userId,
    );
    final archive = await encodeDeviceBackup(ledger);
    await _writeAutoBackupToDirectory(dir, archive, ledger, suffix: suffix);
  }

  Future<List<String>> _autoBackupSearchDirectories({Duration? timeout}) async {
    final dirs = <String>[];
    try {
      final support = getApplicationSupportDirectory();
      final directory = timeout == null
          ? await support
          : await support.timeout(timeout);
      dirs.add('${directory.path}/1Wallet');
    } catch (error) {
      debugPrint(
        'Application support backup directory unavailable: ${error.runtimeType}',
      );
    }
    try {
      final docsFuture = getApplicationDocumentsDirectory();
      final docsDir = timeout != null
          ? await docsFuture.timeout(timeout)
          : await docsFuture;
      dirs.add('${docsDir.path}/1Wallet');
      dirs.add(docsDir.path);

      if (Platform.isAndroid) {
        final extFuture = getExternalStorageDirectory();
        final extDir = timeout != null
            ? await extFuture.timeout(timeout)
            : await extFuture;
        if (extDir != null) {
          dirs.add('${extDir.path}/1Wallet');
          dirs.add(extDir.path);
        }
        dirs.addAll(const [
          '/storage/emulated/0/Download/1Wallet',
          '/storage/emulated/0/Download',
          '/storage/emulated/0/Documents/1Wallet',
          '/storage/emulated/0/Documents',
        ]);
      }
    } catch (_) {}
    return dirs;
  }

  Future<File?> getLatestAutoBackupFile({
    LedgerUserIdentity? userOverride,
    List<String>? searchDirectoriesOverride,
  }) async {
    if (foundation.kIsWeb && searchDirectoriesOverride == null) return null;
    final user = userOverride ?? _activeUser;
    final isAuthenticatedUser = user != null && user.isAuthenticated;
    final suffixes = isAuthenticatedUser
        ? buildCandidateUserBackupSuffixes(
            displayName: user.displayName,
            email: user.email,
            userId: user.userId,
          )
        : const <String>[];

    final searchDirs =
        searchDirectoriesOverride ?? await _autoBackupSearchDirectories();

    final candidates = <({File file, bool isLegacyUnsuffixed})>[];
    for (final sub in searchDirs) {
      for (final suffix in suffixes) {
        for (final variant in const ['', 'safety', 'previous']) {
          final fileName = buildAutoBackupFileName(
            suffix: suffix,
            variant: variant,
          );
          candidates.add((
            file: File('$sub/$fileName'),
            isLegacyUnsuffixed: false,
          ));
        }
      }
      // Also check legacy unsuffixed files, which will only be accepted if
      // their internal userId matches the active user (or 'local-user' when
      // unauthenticated).
      for (final variant in const ['', 'safety', 'previous']) {
        final fileName = buildAutoBackupFileName(variant: variant);
        candidates.add((
          file: File('$sub/$fileName'),
          isLegacyUnsuffixed: true,
        ));
      }
    }

    File? bestFile;
    LedgerState? bestState;
    DateTime? newestTime;

    for (final candidate in candidates) {
      final file = candidate.file;
      try {
        if (await file.exists()) {
          final stat = await file.stat();
          final LedgerState decodedState;
          try {
            final content = await file.readAsString();
            decodedState = await decodeBackup(
              content,
              targetUserId: user?.userId ?? state.userId,
              allowLegacy: true,
            );
          } catch (_) {
            continue;
          }

          // Enforce strict per-account ownership so another user's local backup
          // file is never selected or restored into the current account.
          if (isAuthenticatedUser) {
            if (candidate.isLegacyUnsuffixed) {
              // Legacy unsuffixed files must explicitly match this user's UID.
              if (decodedState.userId != user.userId) {
                continue;
              }
            } else {
              // Named files must not belong to a different authenticated UID.
              if (decodedState.userId.isNotEmpty &&
                  decodedState.userId != 'local-user' &&
                  decodedState.userId != user.userId) {
                continue;
              }
            }
          } else {
            // Unauthenticated / local session: ignore files owned by a specific cloud UID.
            if (decodedState.userId.isNotEmpty &&
                decodedState.userId != 'local-user') {
              continue;
            }
          }

          if (bestFile == null) {
            bestFile = file;
            bestState = decodedState;
            newestTime = stat.modified;
          } else if (bestState != null) {
            // Prefer the backup with safer / more transactions and newer records
            if (LedgerState.isIncomingLedgerSafer(bestState, decodedState) &&
                !LedgerState.isIncomingLedgerSafer(decodedState, bestState)) {
              bestFile = file;
              bestState = decodedState;
              newestTime = stat.modified;
            } else if (newestTime == null ||
                stat.modified.isAfter(newestTime)) {
              bestFile = file;
              bestState = decodedState;
              newestTime = stat.modified;
            }
          }
        }
      } catch (_) {}
    }
    return bestFile;
  }

  Future<void> restoreFromAutoBackup(File file, {bool force = false}) async {
    final content = await file.readAsString();
    await importArchive(content, force: force);
  }

  Future<void> deleteAllAutoBackupFiles({
    LedgerUserIdentity? userOverride,
    List<String>? searchDirectoriesOverride,
  }) async {
    if (foundation.kIsWeb && searchDirectoriesOverride == null) return;
    final user = userOverride ?? _activeUser;
    final isAuthenticatedUser = user != null && user.isAuthenticated;
    final suffixes = isAuthenticatedUser
        ? buildCandidateUserBackupSuffixes(
            displayName: user.displayName,
            email: user.email,
            userId: user.userId,
          )
        : const <String>[];

    final searchDirs =
        searchDirectoriesOverride ??
        await _autoBackupSearchDirectories(
          timeout: const Duration(milliseconds: 500),
        );

    final candidates = <({File file, bool isLegacyUnsuffixed})>[];
    for (final sub in searchDirs) {
      for (final suffix in suffixes) {
        for (final variant in const ['', 'safety', 'previous']) {
          final fileName = buildAutoBackupFileName(
            suffix: suffix,
            variant: variant,
          );
          candidates.add((
            file: File('$sub/$fileName'),
            isLegacyUnsuffixed: false,
          ));
        }
      }
      for (final variant in const ['', 'safety', 'previous']) {
        final fileName = buildAutoBackupFileName(variant: variant);
        candidates.add((
          file: File('$sub/$fileName'),
          isLegacyUnsuffixed: true,
        ));
      }
    }

    for (final candidate in candidates) {
      final file = candidate.file;
      try {
        if (await file.exists()) {
          if (isAuthenticatedUser) {
            final content = await file.readAsString();
            final decoded = await decodeBackup(
              content,
              targetUserId: user.userId,
              allowLegacy: true,
            );
            if (decoded.userId.isEmpty || decoded.userId == 'local-user') {
              throw StateError(
                'A legacy backup has no verified owner. '
                'Review it before claiming deletion is complete.',
              );
            }
            if (decoded.userId != user.userId) continue;
          }
          await file.delete();
        }
      } catch (e) {
        debugPrint('Error deleting backup file ${file.path}: $e');
        rethrow;
      }
    }
  }
}

bool _hasWalletData(LedgerState ledger) {
  return ledger.accounts.isNotEmpty ||
      ledger.transactions.isNotEmpty ||
      ledger.captureCandidates.isNotEmpty ||
      ledger.importBatches.isNotEmpty;
}

String _newId(String prefix) {
  return '$prefix-${DateTime.now().microsecondsSinceEpoch}';
}

String? _blankToNull(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

List<String> _normalizeStringList(Iterable<String> values) {
  final seen = <String>{};
  final result = <String>[];
  for (final value in values) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || seen.contains(trimmed)) continue;
    seen.add(trimmed);
    result.add(trimmed);
  }
  return result;
}

Map<String, String> _normalizeStringMap(Map<String, String> values) {
  final result = <String, String>{};
  for (final entry in values.entries) {
    final key = entry.key.trim();
    final value = entry.value.trim();
    if (key.isEmpty || value.isEmpty) continue;
    result[key] = value;
  }
  return result;
}

LedgerPreferences _preferencesRememberingCategory(
  LedgerState state,
  String? merchant,
  String? categoryId,
) {
  final merchantKey = _merchantCategoryRuleKey(merchant);
  final category = categoryById(state, categoryId);
  if (merchantKey == null || category == null || category.isArchived) {
    return state.preferences;
  }

  final rules = {
    for (final entry in state.preferences.merchantCategoryRules.entries)
      if (_merchantCategoryRuleKey(entry.key) != merchantKey)
        entry.key: entry.value,
    merchantKey: category.id,
  };
  return state.preferences.copyWith(merchantCategoryRules: rules);
}

String? _merchantCategoryRuleKey(String? merchant) {
  final key = merchant?.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  return key == null || key.isEmpty ? null : key;
}

TransactionRecord? _transactionById(LedgerState state, String id) {
  for (final transaction in state.transactions) {
    if (transaction.id == id) return transaction;
  }
  return null;
}

CaptureCandidate? _candidateById(LedgerState state, String id) {
  for (final candidate in state.captureCandidates) {
    if (candidate.id == id) return candidate;
  }
  return null;
}

ImportBatch? _importBatchById(LedgerState state, String id) {
  for (final batch in state.importBatches) {
    if (batch.id == id) return batch;
  }
  return null;
}

Account? _matchAccount(LedgerState state, String name) {
  final normalized = name.trim().toLowerCase();
  if (normalized.isEmpty) return null;
  for (final account in state.accounts) {
    if (account.name.toLowerCase() == normalized) return account;
  }
  for (final account in state.accounts) {
    if (account.name.toLowerCase().contains(normalized) ||
        normalized.contains(account.name.toLowerCase())) {
      return account;
    }
  }
  return null;
}

class _CategorySuggestion {
  const _CategorySuggestion({
    required this.category,
    required this.confidence,
    required this.reason,
  });

  final Category category;
  final double confidence;
  final String reason;
}

Category? _matchCategory(LedgerState state, String? name, String kind) {
  return _suggestCategory(state, name, kind)?.category;
}

_CategorySuggestion? _suggestCategory(
  LedgerState state,
  String? name,
  String kind, {
  bool isMerchant = false,
}) {
  final active = state.categories
      .where((category) => !category.isArchived)
      .toList();
  final normalized = name?.trim().toLowerCase();

  if (normalized != null && normalized.isNotEmpty) {
    final merchantKey = isMerchant
        ? _merchantCategoryRuleKey(normalized)
        : null;
    if (merchantKey != null) {
      for (final entry in state.preferences.merchantCategoryRules.entries) {
        if (_merchantCategoryRuleKey(entry.key) != merchantKey) continue;
        final learnedCategory = categoryById(state, entry.value);
        if (learnedCategory != null &&
            !learnedCategory.isArchived &&
            learnedCategory.kind == kind) {
          return _CategorySuggestion(
            category: learnedCategory,
            confidence: 0.95,
            reason: 'Learned merchant category',
          );
        }
      }
    }

    // 2. Check previous transactions for exact or partial name match
    // to find the most recently used category for this merchant.
    for (final tx in state.transactions) {
      final txNotes = tx.notes?.trim().toLowerCase();
      final txName = tx.name?.trim().toLowerCase();

      bool isStrongMatch(String? pastString) {
        if (pastString == null) return false;
        if (pastString == normalized) return true;
        if (pastString.length > 4 && normalized.contains(pastString)) {
          return true;
        }
        if (normalized.length > 4 && pastString.contains(normalized)) {
          return true;
        }
        return false;
      }

      if (isStrongMatch(txNotes) || isStrongMatch(txName)) {
        if (tx.categoryId != null) {
          final cat = categoryById(state, tx.categoryId);
          if (cat != null && !cat.isArchived) {
            return _CategorySuggestion(
              category: cat,
              confidence: 0.9,
              reason: 'Matched past transaction history',
            );
          }
        }
      }
    }

    // 3. Exact match against category names
    for (final category in active) {
      if (category.name.toLowerCase() == normalized) {
        return _CategorySuggestion(
          category: category,
          confidence: 0.85,
          reason: 'Matched category name',
        );
      }
    }

    // 4. Keyword matching against seller names and message content.
    _CategorySuggestion? keywordSuggestion(
      RegExp pattern,
      List<String> preferredCategoryIds,
      List<String> nameNeedles,
      String reason,
    ) {
      if (!pattern.hasMatch(normalized)) return null;
      for (final id in preferredCategoryIds) {
        final category = categoryById(state, id);
        if (category != null && !category.isArchived) {
          return _CategorySuggestion(
            category: category,
            confidence: 0.72,
            reason: reason,
          );
        }
      }
      for (final needle in nameNeedles) {
        for (final category in active) {
          if (category.name.toLowerCase().contains(needle)) {
            return _CategorySuggestion(
              category: category,
              confidence: 0.68,
              reason: reason,
            );
          }
        }
      }
      return null;
    }

    final keyword =
        keywordSuggestion(
          _groceryKeywordRegex,
          const ['cat-grocery', 'cat-food'],
          const ['grocery', 'groceries', 'food'],
          'Grocery/market keyword match',
        ) ??
        keywordSuggestion(
          _diningKeywordRegex,
          const ['cat-dining', 'cat-food'],
          const ['dining', 'food'],
          'Food/dining keyword match',
        ) ??
        keywordSuggestion(
          _transportKeywordRegex,
          const ['cat-transport', 'cat-travel'],
          const ['transport', 'travel'],
          'Transport keyword match',
        ) ??
        keywordSuggestion(
          _shoppingKeywordRegex,
          const ['cat-shopping'],
          const ['shopping'],
          'Shopping keyword match',
        ) ??
        keywordSuggestion(
          _entertainmentKeywordRegex,
          const ['cat-entertainment'],
          const ['entertainment'],
          'Entertainment keyword match',
        ) ??
        keywordSuggestion(
          _healthKeywordRegex,
          const ['cat-health'],
          const ['health', 'medical'],
          'Health keyword match',
        ) ??
        keywordSuggestion(
          _billKeywordRegex,
          const ['cat-bills'],
          const ['bill', 'utility'],
          'Bill/utility keyword match',
        );
    if (keyword != null) return keyword;
  }

  return null;
}

final RegExp _groceryKeywordRegex = RegExp(
  r'\b(market|supermarket|grocery|groceries|bigbasket|blinkit|instamart|jiomart|dmart|tesco|aldi|lidl|walmart|costco|whole\s*foods|trader\s*joe)\b',
);
final RegExp _diningKeywordRegex = RegExp(
  r'\b(zomato|swiggy|food|food\s*delivery|restaurant|cafe|dining|mcdonalds|starbucks|pizza|burger|kfc|dominos|eatery)\b',
);
final RegExp _transportKeywordRegex = RegExp(
  r'\b(uber|ola|rapido|taxi|transit|metro|train|flight)\b',
);
final RegExp _shoppingKeywordRegex = RegExp(
  r'\b(amazon|flipkart|myntra|shopping)\b',
);
final RegExp _entertainmentKeywordRegex = RegExp(
  r'\b(netflix|spotify|prime|hotstar|subscription|movie)\b',
);
final RegExp _healthKeywordRegex = RegExp(
  r'\b(hospital|pharmacy|clinic|medical|health|doctor)\b',
);
final RegExp _billKeywordRegex = RegExp(
  r'\b(jio|airtel|vi|recharge|bill|electricity|water|wifi)\b',
);
final RegExp _smsTokenCleanupRegex = RegExp(r'[^\w\s@]');
final RegExp _smsWhitespaceRegex = RegExp(r'\s+');
final RegExp _nonDigitRegex = RegExp(r'\D');
final RegExp _cardContextRegex = RegExp(
  r'\b(card|credit\s*card|debit\s*card)\b',
  caseSensitive: false,
);
final RegExp _bankContextRegex = RegExp(
  r'\b(a/c|acct|account|savings|checking)\b',
  caseSensitive: false,
);

String? _matchAccountToSms(LedgerState state, ParsedTransactionMessage parsed) {
  final activeAccounts = state.accounts.where((a) => !a.isArchived).toList();
  if (activeAccounts.isEmpty) return null;

  final rawTextLower = parsed.rawText.toLowerCase();

  // Tokenize the raw SMS into lowercase words for word-level matching.
  final smsTokens = rawTextLower
      .replaceAll(_smsTokenCleanupRegex, ' ')
      .split(_smsWhitespaceRegex)
      .where((t) => t.isNotEmpty)
      .toSet();

  // Extract ALL digit fragments from the SMS for exhaustive number matching.
  final allFragments = extractAllNumberFragments(parsed.rawText);
  final hasCardContext = _cardContextRegex.hasMatch(parsed.rawText);
  final hasBankContext = _bankContextRegex.hasMatch(parsed.rawText);

  Account? bestMatch;
  int highestScore = -1;

  for (final account in activeAccounts) {
    int score = 0;

    // ── 1. Primary last4 match (from _extractLast4 result) ──────────
    if (parsed.last4 != null) {
      if (_digitsSuffixMatch(account.cardLast4, parsed.last4!) ||
          _digitsSuffixMatch(account.accountLast4, parsed.last4!)) {
        score += 100;
      }

      // Full account number suffix match from encrypted details
      if (account.encryptedDetails != null) {
        final accNum = account.encryptedDetails!['accountNumber'];
        if (accNum != null) {
          final cleanAccNum = accNum.replaceAll(_nonDigitRegex, '');
          if (cleanAccNum.isNotEmpty && cleanAccNum.endsWith(parsed.last4!)) {
            score += 150;
          }
        }
      }
    }

    // ── 2. Exhaustive fragment matching ──────────────────────────────
    // Try every digit fragment found in the SMS against this account's
    // cardLast4 / accountLast4 / full account number.
    if (score < 100) {
      // Only bother if we haven't already matched via primary last4
      for (final fragment in allFragments) {
        if (_digitsSuffixMatch(account.cardLast4, fragment) ||
            _digitsSuffixMatch(account.accountLast4, fragment)) {
          score += 80;
          break;
        }
      }
    }
    if (account.encryptedDetails != null) {
      final accNum = account.encryptedDetails!['accountNumber'];
      if (accNum != null) {
        final cleanAccNum = accNum.replaceAll(_nonDigitRegex, '');
        if (cleanAccNum.isNotEmpty) {
          for (final fragment in allFragments) {
            if (fragment.length >= 3 && cleanAccNum.endsWith(fragment)) {
              score += 120;
              break;
            }
          }
        }
      }
    }

    // ── 3. Institution match ─────────────────────────────────────────
    if (parsed.institutionName != null && account.institution != null) {
      final instLower = account.institution!.toLowerCase();
      final parsedInstLower = parsed.institutionName!.toLowerCase();
      if (instLower.contains(parsedInstLower) ||
          parsedInstLower.contains(instLower)) {
        score += 50;
      }
    } else if (account.institution != null) {
      final instLower = account.institution!.toLowerCase();
      if (rawTextLower.contains(instLower)) {
        score += 30;
      }
      // Also try word-level institution matching
      final instTokens = instLower
          .split(_smsWhitespaceRegex)
          .where((t) => t.length > 2)
          .toSet();
      if (instTokens.isNotEmpty &&
          instTokens.every((t) => smsTokens.contains(t))) {
        score += 35;
      }
    }

    // ── 4. Account name matching ─────────────────────────────────────
    final nameLower = account.name.toLowerCase();
    // Full name match
    if (rawTextLower.contains(nameLower)) {
      score += 50;
    } else {
      // Word-level name matching: each word of the account name found in
      // the SMS contributes proportionally.
      final nameTokens = nameLower
          .split(_smsWhitespaceRegex)
          .where((t) => t.length > 2)
          .toList();
      if (nameTokens.isNotEmpty) {
        final matched = nameTokens.where((t) => smsTokens.contains(t)).length;
        if (matched > 0) {
          // Scale: 1 of 1 word = 40, 2 of 3 words ≈ 27, etc.
          score += (40 * matched / nameTokens.length).round();
        }
      }
    }

    // ── 5. Group name match ──────────────────────────────────────────
    if (account.groupName != null) {
      final groupLower = account.groupName!.toLowerCase();
      if (rawTextLower.contains(groupLower)) {
        score += 20;
      } else {
        final groupTokens = groupLower
            .split(_smsWhitespaceRegex)
            .where((t) => t.length > 2)
            .toSet();
        if (groupTokens.isNotEmpty &&
            groupTokens.every((t) => smsTokens.contains(t))) {
          score += 15;
        }
      }
    }

    // ── 6. Account type contextual match ─────────────────────────────
    // If the SMS explicitly mentions "card" and the account type is "card",
    // or mentions "a/c" / "account" and the type is "bank", boost slightly.
    if ((account.type == 'card' || account.type == 'credit_card') &&
        hasCardContext) {
      score += 10;
    } else if ((account.type == 'bank' ||
            account.type == 'savings' ||
            account.type == 'checking') &&
        hasBankContext) {
      score += 10;
    }

    // ── 7. Currency tie-breaker ──────────────────────────────────────
    if (parsed.amount != null &&
        parsed.amount!.currency.toUpperCase() ==
            account.currency.toUpperCase()) {
      score += 5;
    }

    // ── Accumulate best ──────────────────────────────────────────────
    if (score > highestScore && score >= 20) {
      highestScore = score;
      bestMatch = account;
    }
  }

  return bestMatch?.id;
}

/// Checks whether [accountDigits] suffix-matches [smsDigits], handling the
/// common case where the SMS has 3 digits and the account stores 4, or vice
/// versa. Both values are compared as pure digit strings (case-insensitive).
bool _digitsSuffixMatch(String? accountDigits, String smsDigits) {
  if (accountDigits == null || accountDigits.isEmpty) return false;
  final a = accountDigits.toLowerCase();
  final s = smsDigits.toLowerCase();
  // Either one is a suffix of the other
  return a.endsWith(s) || s.endsWith(a);
}

String _rowSignature(
  ParsedWalletCsvRow row,
  String accountId,
  String? categoryId,
) {
  final date = row.occurredAt == null ? 'no-date' : _dateKey(row.occurredAt!);
  return [
    accountId,
    row.type,
    row.amount.amountMinor,
    row.amount.currency,
    categoryId ?? '',
    date,
    row.notes?.trim().toLowerCase() ?? '',
  ].join('|');
}

String _transactionSignature(TransactionRecord transaction) {
  return [
    transaction.accountId,
    transaction.type,
    transaction.amount.amountMinor,
    transaction.amount.currency,
    transaction.categoryId ?? '',
    _dateKey(transaction.occurredAt),
    transaction.notes?.trim().toLowerCase() ?? '',
  ].join('|');
}

String _dateKey(DateTime value) {
  return '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }

  T? firstWhereOrNull(bool Function(T element) test) {
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}

void _ignoreLoadState(LedgerLoadState _) {}

enum _CaptureDuplicateKind {
  pendingText,
  pendingAmount,
  postedTransaction,
  batch,
}

CaptureBlockReason _reasonForDuplicate(_CaptureDuplicateKind kind) {
  return switch (kind) {
    _CaptureDuplicateKind.pendingText => CaptureBlockReason.duplicatePending,
    _CaptureDuplicateKind.pendingAmount => CaptureBlockReason.duplicatePending,
    _CaptureDuplicateKind.postedTransaction =>
      CaptureBlockReason.duplicatePosted,
    _CaptureDuplicateKind.batch => CaptureBlockReason.duplicateBatch,
  };
}
