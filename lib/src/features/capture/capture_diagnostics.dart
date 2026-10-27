import 'dart:convert';
import 'package:flutter/foundation.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../../capture/capture_pipeline.dart';
import '../../data/ledger_models.dart';

class CaptureDiagnosticEvent {
  const CaptureDiagnosticEvent({
    required this.id,
    required this.timestamp,
    required this.source,
    required this.stage,
    required this.decision,
    this.reason,
    this.rawText,
    this.merchant,
    this.amount,
    this.matchedTriggerWord,
    this.matchedIgnoreWord,
    this.categoryId,
    this.categoryReason,
    this.notificationShown = false,
    this.nativeAccepted = false,
    this.errorMessage,
  });

  final String id;
  final DateTime timestamp;
  final String source;
  final String stage;
  final String decision;
  final String? reason;
  final String? rawText;
  final String? merchant;
  final Money? amount;
  final String? matchedTriggerWord;
  final String? matchedIgnoreWord;
  final String? categoryId;
  final String? categoryReason;
  final bool notificationShown;
  final bool nativeAccepted;
  final String? errorMessage;

  Map<String, Object?> toJson() => {
    'id': id,
    'timestamp': timestamp.toIso8601String(),
    'source': source,
    'stage': stage,
    'decision': decision,
    if (reason != null) 'reason': reason,
    if (rawText != null) 'rawText': rawText,
    if (merchant != null) 'merchant': merchant,
    if (amount != null)
      'amount': {
        'amountMinor': amount!.amountMinor,
        'currency': amount!.currency,
      },
    if (matchedTriggerWord != null) 'matchedTriggerWord': matchedTriggerWord,
    if (matchedIgnoreWord != null) 'matchedIgnoreWord': matchedIgnoreWord,
    if (categoryId != null) 'categoryId': categoryId,
    if (categoryReason != null) 'categoryReason': categoryReason,
    'notificationShown': notificationShown,
    'nativeAccepted': nativeAccepted,
    if (errorMessage != null) 'errorMessage': errorMessage,
  };

  static CaptureDiagnosticEvent? fromJson(Object? value) {
    if (value is String) {
      try {
        return fromJson(jsonDecode(value));
      } catch (_) {
        return null;
      }
    }
    if (value is! Map) return null;
    final json = Map<String, dynamic>.from(value);
    final amountJson = json['amount'];
    Money? amount;
    if (amountJson is Map) {
      final amountMap = Map<String, dynamic>.from(amountJson);
      final rawMinor = amountMap['amountMinor'];
      final currency = amountMap['currency']?.toString();
      if (rawMinor is num && currency != null && currency.isNotEmpty) {
        amount = Money(amountMinor: rawMinor.round(), currency: currency);
      }
    }
    return CaptureDiagnosticEvent(
      id:
          json['id']?.toString() ??
          'diag-${DateTime.now().microsecondsSinceEpoch}',
      timestamp:
          DateTime.tryParse(json['timestamp']?.toString() ?? '') ??
          DateTime.now(),
      source: json['source']?.toString() ?? 'unknown',
      stage: json['stage']?.toString() ?? 'unknown',
      decision: json['decision']?.toString() ?? 'unknown',
      reason: json['reason']?.toString(),
      rawText: json['rawText']?.toString(),
      merchant: json['merchant']?.toString(),
      amount: amount,
      matchedTriggerWord: json['matchedTriggerWord']?.toString(),
      matchedIgnoreWord: json['matchedIgnoreWord']?.toString(),
      categoryId: json['categoryId']?.toString(),
      categoryReason: json['categoryReason']?.toString(),
      notificationShown: json['notificationShown'] == true,
      nativeAccepted: json['nativeAccepted'] == true,
      errorMessage: json['errorMessage']?.toString(),
    );
  }
}

class CaptureDiagnostics {
  static const _key = 'one_wallet_flutter.capture_diagnostics';
  static const _maxEvents = 150;

  static Future<List<CaptureDiagnosticEvent>> recentEvents({
    String ownerId = 'local-user',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.getString('$_key.$ownerId');
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        throw const FormatException('Diagnostic history must be a list.');
      }
      final events = decoded
          .map(CaptureDiagnosticEvent.fromJson)
          .whereType<CaptureDiagnosticEvent>()
          .toList();
      events.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return events;
    } catch (error, stack) {
      debugPrint('Capture diagnostic history is invalid: ${error.runtimeType}');
      debugPrintStack(stackTrace: stack);
      rethrow;
    }
  }

  static Future<void> recordEvent(
    CaptureDiagnosticEvent event, {
    String ownerId = 'local-user',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final events = await recentEvents(ownerId: ownerId);
    final next = [
      event,
      ...events,
    ].take(_maxEvents).map((item) => jsonEncode(item.toJson())).toList();
    if (!await prefs.setString('$_key.$ownerId', jsonEncode(next))) {
      throw StateError('Could not persist capture diagnostics.');
    }
  }

  static Future<void> recordResult({
    required String stage,
    required CaptureImportResult result,
    String ownerId = 'local-user',
  }) {
    return recordEvent(
      CaptureDiagnosticEvent(
        id: 'diag-${DateTime.now().microsecondsSinceEpoch}',
        timestamp: DateTime.now(),
        source: result.source,
        stage: stage,
        decision: result.decisionLabel,
        reason: result.reasonLabel,
        rawText: result.parsed.rawText,
        merchant: result.parsed.merchant,
        amount: result.parsed.amount,
        matchedTriggerWord: result.parsed.matchedTriggerWord,
        matchedIgnoreWord: result.parsed.matchedIgnoreWord,
        categoryId: result.categoryId,
        categoryReason: result.categoryReason,
        notificationShown: result.notificationShown,
        nativeAccepted: result.nativeAccepted,
        errorMessage: result.errorMessage,
      ),
      ownerId: ownerId,
    );
  }

  static Future<void> clear({String ownerId = 'local-user'}) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.remove('$_key.$ownerId')) {
      throw StateError('Could not clear account diagnostics.');
    }
  }

  static Future<void> clearLegacy() async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.remove(_key) || !await prefs.remove('$_key.unassigned')) {
      throw StateError('Could not clear unassigned diagnostic history.');
    }
  }
}
