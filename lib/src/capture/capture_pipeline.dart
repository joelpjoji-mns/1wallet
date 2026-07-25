import '../data/ledger_models.dart';
import 'message_parser.dart';

enum CaptureImportStatus { queued, ignored, duplicate, error }

enum CaptureBlockReason {
  empty,
  captureDisabled,
  ignoreWord,
  missingAmount,
  missingTrigger,
  duplicatePending,
  duplicatePosted,
  duplicateBatch,
  error,
}

class CaptureImportResult {
  const CaptureImportResult({
    required this.source,
    required this.status,
    required this.receivedAt,
    required this.parsed,
    this.reason,
    this.candidate,
    this.errorMessage,
    this.notificationShown = false,
    this.nativeAccepted = false,
    this.categoryId,
    this.categoryReason,
  });

  final String source;
  final CaptureImportStatus status;
  final DateTime receivedAt;
  final ParsedTransactionMessage parsed;
  final CaptureBlockReason? reason;
  final CaptureCandidate? candidate;
  final String? errorMessage;
  final bool notificationShown;
  final bool nativeAccepted;
  final String? categoryId;
  final String? categoryReason;

  bool get queued => status == CaptureImportStatus.queued;
  bool get ignored => status == CaptureImportStatus.ignored;
  bool get duplicate => status == CaptureImportStatus.duplicate;

  String get decisionLabel {
    switch (status) {
      case CaptureImportStatus.queued:
        return 'queued';
      case CaptureImportStatus.ignored:
        return 'ignored';
      case CaptureImportStatus.duplicate:
        return 'duplicate';
      case CaptureImportStatus.error:
        return 'error';
    }
  }

  String get reasonLabel {
    final current = reason;
    if (current == null) return decisionLabel;
    switch (current) {
      case CaptureBlockReason.empty:
        return 'empty message';
      case CaptureBlockReason.captureDisabled:
        return 'capture disabled';
      case CaptureBlockReason.ignoreWord:
        return 'matched ignore word';
      case CaptureBlockReason.missingAmount:
        return 'missing amount';
      case CaptureBlockReason.missingTrigger:
        return 'missing trigger word';
      case CaptureBlockReason.duplicatePending:
        return 'already in review queue';
      case CaptureBlockReason.duplicatePosted:
        return 'already posted';
      case CaptureBlockReason.duplicateBatch:
        return 'duplicate in this scan';
      case CaptureBlockReason.error:
        return 'error';
    }
  }

  String get userMessage {
    switch (status) {
      case CaptureImportStatus.queued:
        return 'Added to the review queue.';
      case CaptureImportStatus.duplicate:
        return reason == CaptureBlockReason.duplicatePosted
            ? 'Looks like this transaction was already posted.'
            : 'Already in the review queue.';
      case CaptureImportStatus.ignored:
        if (reason == CaptureBlockReason.ignoreWord &&
            parsed.matchedIgnoreWord != null) {
          return 'Ignored because it matched "${parsed.matchedIgnoreWord}".';
        }
        if (reason == CaptureBlockReason.missingAmount) {
          return 'Could not find an amount in this message.';
        }
        if (reason == CaptureBlockReason.missingTrigger) {
          return 'No trigger word matched this message.';
        }
        if (reason == CaptureBlockReason.captureDisabled) {
          return 'Capture is disabled.';
        }
        return 'Message ignored.';
      case CaptureImportStatus.error:
        return errorMessage ?? 'Could not add this message.';
    }
  }
}

CaptureBlockReason? blockReasonForParsedMessage(
  ParsedTransactionMessage parsed,
) {
  if (!parsed.ignored) return null;
  if (parsed.rawText.trim().isEmpty) return CaptureBlockReason.empty;
  if (parsed.matchedIgnoreWord != null) return CaptureBlockReason.ignoreWord;
  if (!parsed.hasAmount) return CaptureBlockReason.missingAmount;
  if (!parsed.hasTriggerWord) return CaptureBlockReason.missingTrigger;
  return CaptureBlockReason.error;
}

bool parsedMessageIsQueueable(ParsedTransactionMessage parsed) =>
    !parsed.ignored && parsed.amount != null;
