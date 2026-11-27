import 'dart:convert';
import 'dart:io';
import 'dart:developer' as developer;
import 'package:crypto/crypto.dart';
import 'package:firebase_core/firebase_core.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class Changelog {
  final List<String> newFeatures;
  final List<String> bugFixes;
  final List<String> notes;

  Changelog({
    required this.newFeatures,
    required this.bugFixes,
    required this.notes,
  });

  factory Changelog.fromJson(Map<String, dynamic> json) {
    final nested = _mapValue(json['changelog']);
    return Changelog(
      newFeatures: _stringList(
        json['newFeatures'] ??
            json['features'] ??
            nested['newFeatures'] ??
            nested['features'],
      ),
      bugFixes: _stringList(
        json['bugFixes'] ??
            json['fixes'] ??
            nested['bugFixes'] ??
            nested['fixes'],
      ),
      notes: _stringList(json['notes'] ?? nested['notes']),
    );
  }

  bool get isEmpty => newFeatures.isEmpty && bugFixes.isEmpty && notes.isEmpty;

  Map<String, dynamic> toJson() => {
    'newFeatures': newFeatures,
    'bugFixes': bugFixes,
    'notes': notes,
  };
}

class ApkMetadata {
  final String downloadUrl;
  final String fileName;
  final int sizeBytes;
  final String sha256;
  final String architecture;
  final int? minSdk;
  final int? estimatedDownloadSeconds;

  ApkMetadata({
    required this.downloadUrl,
    required this.fileName,
    required this.sizeBytes,
    required this.sha256,
    required this.architecture,
    this.minSdk,
    this.estimatedDownloadSeconds,
  });

  factory ApkMetadata.fromJson(Map<String, dynamic> json) {
    return ApkMetadata(
      downloadUrl: _stringValue(json['downloadUrl'] ?? json['url']),
      fileName: _stringValue(json['fileName'], fallback: 'update.apk'),
      sizeBytes: _intValue(json['sizeBytes']),
      sha256: _stringValue(json['sha256']),
      architecture: _stringValue(json['architecture']),
      minSdk: _nullableIntValue(json['minSdk']),
      estimatedDownloadSeconds: _nullableIntValue(
        json['estimatedDownloadSeconds'],
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'downloadUrl': downloadUrl,
    'fileName': fileName,
    'sizeBytes': sizeBytes,
    'sha256': sha256,
    'architecture': architecture,
    if (minSdk != null) 'minSdk': minSdk,
    if (estimatedDownloadSeconds != null)
      'estimatedDownloadSeconds': estimatedDownloadSeconds,
  };
}

class AppUpdateRelease {
  final String id;
  final String platform;
  final String channel;
  final String status;
  final String versionName;
  final int versionCode;
  final String runtimeVersion;
  final String releaseType;
  final String requirement;
  final bool mandatory;
  final int minimumSupportedVersionCode;
  final String publishedAt;
  final Changelog changelog;
  final ApkMetadata? apk;

  AppUpdateRelease({
    required this.id,
    required this.platform,
    required this.channel,
    required this.status,
    required this.versionName,
    required this.versionCode,
    required this.runtimeVersion,
    required this.releaseType,
    required this.requirement,
    required this.mandatory,
    required this.minimumSupportedVersionCode,
    required this.publishedAt,
    required this.changelog,
    this.apk,
  });

  factory AppUpdateRelease.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AppUpdateRelease.fromJson(doc.id, data);
  }

  factory AppUpdateRelease.fromJson(String id, Map<String, dynamic> data) {
    return AppUpdateRelease(
      id: id,
      platform: _stringValue(data['platform'], fallback: 'android'),
      channel: _stringValue(data['channel'], fallback: 'stable'),
      status: _stringValue(data['status'], fallback: 'published'),
      versionName: _stringValue(data['versionName'] ?? data['version']),
      versionCode: _intValue(data['versionCode']),
      runtimeVersion: _stringValue(data['runtimeVersion']),
      releaseType: _stringValue(data['releaseType']),
      requirement: _stringValue(data['requirement'], fallback: 'optional'),
      mandatory: data['mandatory'] == true,
      minimumSupportedVersionCode: _intValue(
        data['minimumSupportedVersionCode'],
      ),
      publishedAt: _dateString(data['publishedAt'] ?? data['generatedAt']),
      changelog: Changelog.fromJson(data['changelog'] ?? {}),
      apk: data['apk'] != null
          ? ApkMetadata.fromJson(_mapValue(data['apk']))
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'platform': platform,
    'channel': channel,
    'status': status,
    'versionName': versionName,
    'versionCode': versionCode,
    'runtimeVersion': runtimeVersion,
    'releaseType': releaseType,
    'requirement': requirement,
    'mandatory': mandatory,
    'minimumSupportedVersionCode': minimumSupportedVersionCode,
    'publishedAt': publishedAt,
    'changelog': changelog.toJson(),
    if (apk != null) 'apk': apk!.toJson(),
  };
}

enum UpdateStatus { idle, checking, downloading, downloaded, installing, error }

final List<AppUpdateRelease> kBuiltInReleaseHistory = [
  AppUpdateRelease(
    id: '1.0.23',
    platform: 'android',
    channel: 'stable',
    status: 'published',
    versionName: '1.0.23',
    versionCode: 23,
    runtimeVersion: '1.0.23',
    releaseType: 'full',
    requirement: 'optional',
    mandatory: false,
    minimumSupportedVersionCode: 1,
    publishedAt: '2026-11-27T18:00:00.000Z',
    changelog: Changelog(
      newFeatures: const [
        'Credit utilization shows total credit used across all cards',
      ],
      bugFixes: const [
        'Account groups widget redesigned with clearer spacing and icons',
        'Account deletion screen redesigned with step-by-step progress',
      ],
      notes: const [],
    ),
  ),  AppUpdateRelease(
    id: '1.0.22',
    platform: 'android',
    channel: 'stable',
    status: 'published',
    versionName: '1.0.22',
    versionCode: 22,
    runtimeVersion: '1.0.22',
    releaseType: 'full',
    requirement: 'optional',
    mandatory: false,
    minimumSupportedVersionCode: 1,
    publishedAt: '2026-11-27T16:00:00.000Z',
    changelog: Changelog(
      newFeatures: const [
        'New update screen with a live download progress bar',
        'Updates install and restart automatically once downloaded',
        'Planned payment cards show schedule and account on one line, with notes below',
      ],
      bugFixes: const [
        'Update check runs only once a day, even after days away',
        'Skip next can no longer skip the same payment twice',
        'Loan history no longer counts skipped EMIs as repayments',
        'One-time plans read "One-time" instead of "Every 1 once"',
      ],
      notes: const ['Google Play still asks you to confirm an update once'],
    ),
  ),
  AppUpdateRelease(
    id: '1.0.21',
    platform: 'android',
    channel: 'stable',
    status: 'published',
    versionName: '1.0.21',
    versionCode: 21,
    runtimeVersion: '1.0.21',
    releaseType: 'full',
    requirement: 'optional',
    mandatory: false,
    minimumSupportedVersionCode: 1,
    publishedAt: '2026-11-27T14:00:00.000Z',
    changelog: Changelog(
      newFeatures: const [
        'Pull down in Review to scan the last day of SMS and notifications',
      ],
      bugFixes: const [
        'Confirmed or dismissed messages never return to Review on rescan',
      ],
      notes: const ['Only scans capture sources you have switched on'],
    ),
  ),
  AppUpdateRelease(
    id: '1.0.20',
    platform: 'android',
    channel: 'stable',
    status: 'published',
    versionName: '1.0.20',
    versionCode: 20,
    runtimeVersion: '1.0.20',
    releaseType: 'full',
    requirement: 'optional',
    mandatory: false,
    minimumSupportedVersionCode: 1,
    publishedAt: '2026-11-27T14:00:00.000Z',
    changelog: Changelog(
      newFeatures: const [],
      bugFixes: const [
        'No more repeated "Tour progress ... Cloud sync is unavailable" messages',
        'Tour progress syncs quietly in the background and waits for slow networks',
      ],
      notes: const ['Tour progress is always saved on your device first'],
    ),
  ),
  AppUpdateRelease(
    id: '1.0.19',
    platform: 'android',
    channel: 'stable',
    status: 'published',
    versionName: '1.0.19',
    versionCode: 19,
    runtimeVersion: '1.0.19',
    releaseType: 'full',
    requirement: 'optional',
    mandatory: false,
    minimumSupportedVersionCode: 1,
    publishedAt: '2026-11-27T13:00:00.000Z',
    changelog: Changelog(
      newFeatures: const [
        'Hide an account from the All accounts tile with a tick box',
        'More compact Review inbox cards with side-by-side chips',
      ],
      bugFixes: const [
        'Button labels always stay on one line',
        'Close and Delete account buttons sit side by side',
        'Balance tile date range and currency sit on the right',
      ],
      notes: const ['Confirm no longer wraps on narrow phones'],
    ),
  ),
  AppUpdateRelease(
    id: '1.0.18',
    platform: 'android',
    channel: 'stable',
    status: 'published',
    versionName: '1.0.18',
    versionCode: 18,
    runtimeVersion: '1.0.18',
    releaseType: 'full',
    requirement: 'optional',
    mandatory: false,
    minimumSupportedVersionCode: 1,
    publishedAt: '2026-11-27T12:00:00.000Z',
    changelog: Changelog(
      newFeatures: const [
        'Payday countdown, Next card bill and Unusual spending home widgets',
        'Compact calendar popup for custom date ranges',
        'Glass-styled buttons across the app',
      ],
      bugFixes: const [
        'Deleted accounts no longer reappear or get blocked by hidden plans',
        'Cleaner, aligned planned payment lists, details and summary',
        'Review and inbox notification card layout fixes',
      ],
      notes: const ['New widgets appear at the bottom of the dashboard'],
    ),
  ),
  AppUpdateRelease(
    id: '1.0.17',
    platform: 'android',
    channel: 'stable',
    status: 'published',
    versionName: '1.0.17',
    versionCode: 17,
    runtimeVersion: '1.0.17',
    releaseType: 'full',
    requirement: 'optional',
    mandatory: false,
    minimumSupportedVersionCode: 1,
    publishedAt: '2026-11-26T01:30:00.000Z',
    changelog: Changelog(
      newFeatures: const [
        'Unified interactive story tour with illuminated spotlight beacons',
        'Interactive Calendar forecast with next month preview and day sheet inspection',
        'Compact glass coach marks with inline live sample previews',
      ],
      bugFixes: const [
        'Non-optional guided onboarding flow cleanly advances across all core tabs',
        'Smooth bottom sheet presentation and day transaction breakdown in tour',
      ],
      notes: const ['Sample tour workflows are isolated and non-destructive'],
    ),
  ),
  AppUpdateRelease(
    id: '1.0.16',
    platform: 'android',
    channel: 'stable',
    status: 'published',
    versionName: '1.0.16',
    versionCode: 16,
    runtimeVersion: '1.0.16',
    releaseType: 'full',
    requirement: 'optional',
    mandatory: false,
    minimumSupportedVersionCode: 1,
    publishedAt: '2026-11-26T00:30:00.000Z',
    changelog: Changelog(
      newFeatures: const [
        'Compact interactive tours with real-screen spotlights and arrows',
        'Guides for plans, loans, forecasts, credentials and alert matching',
        'Safe sample workflows and replay controls in Settings',
      ],
      bugFixes: const [
        'Fresh offline wallets finish account setup before discovery',
        'Existing wallets stay free of unsolicited tour popups',
        'Improved small-screen, large-text and navigation layouts',
      ],
      notes: const ['Samples never save transactions or credentials'],
    ),
  ),
  AppUpdateRelease(
    id: '1.0.15',
    platform: 'android',
    channel: 'stable',
    status: 'published',
    versionName: '1.0.15',
    versionCode: 15,
    runtimeVersion: '1.0.15',
    releaseType: 'full',
    requirement: 'optional',
    mandatory: false,
    minimumSupportedVersionCode: 1,
    publishedAt: '2026-11-25T20:30:00.000Z',
    changelog: Changelog(
      newFeatures: const [
        'Planned payments show how much was spent or paid so far',
        'Offline wallets can sign out from Settings',
      ],
      bugFixes: const [
        'Compact planned and loan detail headers and summaries',
        'History filters in three columns; cleaner search bar',
        'Fixed login, onboarding and layouts at large text sizes',
      ],
      notes: const ['Clear glass is now the default finish'],
    ),
    apk: ApkMetadata(
      downloadUrl: '',
      fileName: 'app-release.apk',
      sizeBytes: 52 * 1024 * 1024,
      sha256: '',
      architecture: 'universal',
    ),
  ),
  AppUpdateRelease(
    id: '1.0.14',
    platform: 'android',
    channel: 'stable',
    status: 'published',
    versionName: '1.0.14',
    versionCode: 14,
    runtimeVersion: '1.0.14',
    releaseType: 'full',
    requirement: 'optional',
    mandatory: false,
    minimumSupportedVersionCode: 1,
    publishedAt: '2026-11-23T21:00:00.000Z',
    changelog: Changelog(
      newFeatures: const [
        'Google Play in-app updates: check and update inline directly inside the app',
        'Loan management: dedicated Pay EMI and custom repayment actions in Loan details',
      ],
      bugFixes: const [
        'Fixed loan repayment account selector to display loan accounts and balances',
        'Resolved double-counting of finished scheduled plan templates in ledger',
        'Fixed EMI plan recurrence limit loop and repayment history tracking',
      ],
      notes: const [
        'Reinforced double-entry ledger integrity for all loan operations',
      ],
    ),
    apk: ApkMetadata(
      downloadUrl: '',
      fileName: 'app-release.apk',
      sizeBytes: 52 * 1024 * 1024,
      sha256: '',
      architecture: 'universal',
    ),
  ),
  AppUpdateRelease(
    id: '1.0.13',
    platform: 'android',
    channel: 'stable',
    status: 'published',
    versionName: '1.0.13',
    versionCode: 13,
    runtimeVersion: '1.0.13',
    releaseType: 'full',
    requirement: 'optional',
    mandatory: false,
    minimumSupportedVersionCode: 1,
    publishedAt: '2026-11-23T15:00:00.000Z',
    changelog: Changelog(
      newFeatures: const [
        'Dynamic currency icons in selectors and account setup matching active currencies',
      ],
      bugFixes: const [
        'Fixed missing search bar and action glyphs by bundling Cupertino icons',
        'Fixed currency picker to display currency-specific symbols and icons instead of generic placeholders',
      ],
      notes: const [
        'Streamlined settings and navigation chrome for enhanced Google Play compliance',
      ],
    ),
    apk: ApkMetadata(
      downloadUrl: '',
      fileName: 'app-release.apk',
      sizeBytes: 52 * 1024 * 1024,
      sha256: '',
      architecture: 'universal',
    ),
  ),
  AppUpdateRelease(
    id: '1.0.12',
    platform: 'android',
    channel: 'stable',
    status: 'published',
    versionName: '1.0.12',
    versionCode: 12,
    runtimeVersion: '1.0.12',
    releaseType: 'full',
    requirement: 'optional',
    mandatory: false,
    minimumSupportedVersionCode: 1,
    publishedAt: '2026-11-22T19:15:00.000Z',
    changelog: Changelog(
      newFeatures: const [
        'Continuous multi-period date range navigation with responsive swipe and arrow controls',
      ],
      bugFixes: const [
        'Clean Review & Inbox statement cards: single-row action layout with Confirm Paid and Dismiss',
        'Fixed date range navigation getting stuck or resetting when swiping or clicking consecutively',
        'Enabled date filter navigation when transitioning from All Time filter in Transactions',
      ],
      notes: const [
        'Improved touch target accessibility and tactile haptic feedback for timeframe controls',
      ],
    ),
    apk: ApkMetadata(
      downloadUrl: '',
      fileName: 'app-release.apk',
      sizeBytes: 52 * 1024 * 1024,
      sha256: '',
      architecture: 'universal',
    ),
  ),
  AppUpdateRelease(
    id: '1.0.11',
    platform: 'android',
    channel: 'stable',
    status: 'published',
    versionName: '1.0.11',
    versionCode: 11,
    runtimeVersion: '1.0.11',
    releaseType: 'full',
    requirement: 'optional',
    mandatory: false,
    minimumSupportedVersionCode: 1,
    publishedAt: '2026-11-22T16:20:00.000Z',
    changelog: Changelog(
      newFeatures: const [
        'Streamlined repository architecture with optimized APK build and bundle footprint',
        'Performance enhancements across home dashboard and ledger selectors',
      ],
      bugFixes: const [
        'Removed redundant prototype dependencies and unreferenced legacy components',
        'Cleaned up unbundled font binaries and unused platform reload utilities',
      ],
      notes: const [
        'Over 100 MB of legacy clutter and obsolete scripts pruned from source repository',
      ],
    ),
    apk: ApkMetadata(
      downloadUrl: '',
      fileName: 'app-release.apk',
      sizeBytes: 52 * 1024 * 1024,
      sha256: '',
      architecture: 'universal',
    ),
  ),
  AppUpdateRelease(
    id: '1.0.10',
    platform: 'android',
    channel: 'stable',
    status: 'published',
    versionName: '1.0.10',
    versionCode: 10,
    runtimeVersion: '1.0.10',
    releaseType: 'full',
    requirement: 'optional',
    mandatory: false,
    minimumSupportedVersionCode: 1,
    publishedAt: '2026-11-22T13:00:00.000Z',
    changelog: Changelog(
      newFeatures: const [
        'Added Today date filter option across transactions and home widgets',
        'Interactive left/right arrow navigation (< Period >) on date range dropdown pill',
        'Horizontal swipe gesture support on date filter to seamlessly step between time periods',
      ],
      bugFixes: const [
        'Resolved sign out failure and session teardown across multiple user profiles',
        'Fixed Confirm Paid button right alignment in Statement Ready notification cards',
        'Removed update checker, update banners, and install buttons from Changelog window',
      ],
      notes: const [
        'Streamlined Review & Inbox notification cards and button responsiveness',
      ],
    ),
    apk: ApkMetadata(
      downloadUrl: '',
      fileName: 'app-release.apk',
      sizeBytes: 58 * 1024 * 1024,
      sha256: '',
      architecture: 'arm64-v8a',
    ),
  ),
  AppUpdateRelease(
    id: '1.0.9',
    platform: 'android',
    channel: 'stable',
    status: 'published',
    versionName: '1.0.9',
    versionCode: 9,
    runtimeVersion: '1.0.9',
    releaseType: 'full',
    requirement: 'optional',
    mandatory: false,
    minimumSupportedVersionCode: 1,
    publishedAt: '2026-11-19T22:00:00.000Z',
    changelog: Changelog(
      newFeatures: const [
        'Dedicated in-app Changelog screen accessible via Settings',
        'Direct quick-action controls for SMS, notifications, and diagnostics in Review queue',
        'Optimized clear glass optics with 0.5px blur and high-contrast readability',
      ],
      bugFixes: const [
        'Stabilized recent records animation container and eliminated height jumping',
        'Eliminated see-through dropdown transparency across menus and popups',
        'Refined promotional card alignment and mathematically centered pill badges',
      ],
      notes: const [
        'Automated release changelog packaging for Google Play Store deployments',
      ],
    ),
    apk: ApkMetadata(
      downloadUrl: '',
      fileName: 'app-release.apk',
      sizeBytes: 58 * 1024 * 1024,
      sha256: '',
      architecture: 'arm64-v8a',
    ),
  ),
  AppUpdateRelease(
    id: '1.0.8',
    platform: 'android',
    channel: 'stable',
    status: 'published',
    versionName: '1.0.8',
    versionCode: 8,
    runtimeVersion: '1.0.8',
    releaseType: 'full',
    requirement: 'optional',
    mandatory: false,
    minimumSupportedVersionCode: 1,
    publishedAt: '2026-11-19T21:00:00.000Z',
    changelog: Changelog(
      newFeatures: const [
        'Enhanced Google Play release pipeline and deployment configurations',
        'Refined privacy controls and high-fidelity glass design enhancements',
        'Offline-first personal finance with double-entry ledger accuracy',
      ],
      bugFixes: const [
        'Fixed background sync lifecycle handlers and token management',
        'Resolved layout overflows and polished typography alignment',
      ],
      notes: const [
        'Production release for Google Play Store with end-to-end ledger encryption',
      ],
    ),
    apk: ApkMetadata(
      downloadUrl: '',
      fileName: 'app-release.apk',
      sizeBytes: 58 * 1024 * 1024,
      sha256: '',
      architecture: 'arm64-v8a',
    ),
  ),
  AppUpdateRelease(
    id: '1.0.0',
    platform: 'android',
    channel: 'stable',
    status: 'published',
    versionName: '1.0.0',
    versionCode: 1,
    runtimeVersion: '1.0.0',
    releaseType: 'full',
    requirement: 'optional',
    mandatory: false,
    minimumSupportedVersionCode: 1,
    publishedAt: '2026-11-01T00:00:00.000Z',
    changelog: Changelog(
      newFeatures: const [
        'Initial public release of 1Wallet on Google Play',
        'Offline-first personal finance with double-entry ledger accuracy',
        'Biometric authentication and AES-256 local encryption',
      ],
      bugFixes: const [],
      notes: const ['Welcome to 1Wallet!'],
    ),
    apk: ApkMetadata(
      downloadUrl: '',
      fileName: 'app-release.apk',
      sizeBytes: 58 * 1024 * 1024,
      sha256: '',
      architecture: 'arm64-v8a',
    ),
  ),
  AppUpdateRelease(
    id: '2.1.106',
    platform: 'android',
    channel: 'stable',
    status: 'published',
    versionName: '2.1.106',
    versionCode: 201106,
    runtimeVersion: '2.1.0',
    releaseType: 'full',
    requirement: 'optional',
    mandatory: false,
    minimumSupportedVersionCode: 200000,
    publishedAt: '2026-10-25T12:00:00.000Z',
    changelog: Changelog(
      newFeatures: const [
        'Standardized date filters across home screen tiles: `This week`, `This month`, `30 days`, `6 months`, `1 year`',
        'Top-left tile icons are now interactive shortcuts to respective management and history screens',
        'Multi-tag filtering support and unified search in transaction history',
      ],
      bugFixes: const [
        'Fixed card statement confirm-paid payment cycles and notifications',
        'Suppressed floating snackbar and notification overlay popups',
        'Fixed transaction account selector to avoid unintended default selection',
      ],
      notes: const [
        'Morphe Manager-inspired update screen with full timeline changelog, version transition, and progress ring',
        'Full-width action buttons and pull-to-refresh changelog timeline',
      ],
    ),
    apk: ApkMetadata(
      downloadUrl: '',
      fileName: 'app-release.apk',
      sizeBytes: 58 * 1024 * 1024,
      sha256: '',
      architecture: 'arm64-v8a',
    ),
  ),
  AppUpdateRelease(
    id: '2.1.105',
    platform: 'android',
    channel: 'stable',
    status: 'published',
    versionName: '2.1.105',
    versionCode: 201105,
    runtimeVersion: '2.1.0',
    releaseType: 'full',
    requirement: 'optional',
    mandatory: false,
    minimumSupportedVersionCode: 200000,
    publishedAt: '2026-10-20T10:00:00.000Z',
    changelog: Changelog(
      newFeatures: const [
        'Multi-currency cash account opening balances support',
        'Smooth number transitions and animated home net balance counter',
      ],
      bugFixes: const [
        'Fixed balance display glitch during rapid currency switching',
        'Added missing Android drawable imports and resolved crash on cold launch',
      ],
      notes: const [
        'Safety guard blocking account deletion when linked to active recurring plans',
        'Preserved historical transactions upon cash account deletion',
      ],
    ),
  ),
  AppUpdateRelease(
    id: '2.1.102',
    platform: 'android',
    channel: 'stable',
    status: 'published',
    versionName: '2.1.102',
    versionCode: 201102,
    runtimeVersion: '2.1.0',
    releaseType: 'full',
    requirement: 'optional',
    mandatory: false,
    minimumSupportedVersionCode: 200000,
    publishedAt: '2026-10-14T08:00:00.000Z',
    changelog: Changelog(
      newFeatures: const [
        'Universal bank-agnostic PDF statement parser with auto-recovery and password detection',
        'Value Date and opening balance delta tracking for PDF imports',
      ],
      bugFixes: const [
        'Fixed calendar day selection and modal sheet clipping on AMOLED and desktop layouts',
        'Aligned transaction card horizontal width with accounts cards across compact layouts',
      ],
      notes: const [
        'Isolated user backup sessions and instant startup performance enhancements',
      ],
    ),
  ),
  AppUpdateRelease(
    id: '2.1.101',
    platform: 'android',
    channel: 'stable',
    status: 'published',
    versionName: '2.1.101',
    versionCode: 201101,
    runtimeVersion: '2.1.0',
    releaseType: 'full',
    requirement: 'optional',
    mandatory: false,
    minimumSupportedVersionCode: 200000,
    publishedAt: '2026-10-08T18:00:00.000Z',
    changelog: Changelog(
      newFeatures: const [
        'Optimized SMS parser cache to avoid re-reading past statements',
      ],
      bugFixes: const [
        'Resolved data loss on force stop and phone lag caused by inbox scan disk thrashing',
      ],
      notes: const [
        'Memory footprint reduced by 30% during background batch scans',
      ],
    ),
  ),
  AppUpdateRelease(
    id: '2.1.100',
    platform: 'android',
    channel: 'stable',
    status: 'published',
    versionName: '2.1.100',
    versionCode: 201100,
    runtimeVersion: '2.1.0',
    releaseType: 'full',
    requirement: 'optional',
    mandatory: false,
    minimumSupportedVersionCode: 200000,
    publishedAt: '2026-10-08T12:00:00.000Z',
    changelog: Changelog(
      newFeatures: const [
        'Liquid Glass UI framework with minimal, standard, and crystal refractive modes',
        'Comprehensive multi-account grid with live balances and quick transfers',
        'Multi-transaction merge in history and SMS duplicate inspection',
      ],
      bugFixes: const [
        'Optimized regular expressions and memoized selectors to eliminate UI thread lag',
      ],
      notes: const ['Added over 380 unit and widget integration tests'],
    ),
  ),
  AppUpdateRelease(
    id: '2.1.99',
    platform: 'android',
    channel: 'stable',
    status: 'published',
    versionName: '2.1.99',
    versionCode: 201099,
    runtimeVersion: '2.1.0',
    releaseType: 'full',
    requirement: 'optional',
    mandatory: false,
    minimumSupportedVersionCode: 200000,
    publishedAt: '2026-10-07T14:00:00.000Z',
    changelog: Changelog(
      newFeatures: const [
        'Delete account option with comprehensive cloud and local data wipe in settings',
      ],
      bugFixes: const [
        'Prevented orphaned recurring transaction plans when deleting user accounts',
      ],
      notes: const [
        'Immediate biometric confirmation required for account termination',
      ],
    ),
  ),
  AppUpdateRelease(
    id: '2.1.96',
    platform: 'android',
    channel: 'stable',
    status: 'published',
    versionName: '2.1.96',
    versionCode: 201096,
    runtimeVersion: '2.1.0',
    releaseType: 'full',
    requirement: 'optional',
    mandatory: false,
    minimumSupportedVersionCode: 200000,
    publishedAt: '2026-09-30T22:00:00.000Z',
    changelog: Changelog(
      newFeatures: const [
        'Enhanced credit card bill and due date notifications with review inbox quick actions',
      ],
      bugFixes: const [
        'Fixed notification background action intents and tap navigation',
      ],
      notes: const [
        'Smart reminder threshold calculation based on user billing history',
      ],
    ),
  ),
  AppUpdateRelease(
    id: '2.1.95',
    platform: 'android',
    channel: 'stable',
    status: 'published',
    versionName: '2.1.95',
    versionCode: 201095,
    runtimeVersion: '2.1.0',
    releaseType: 'full',
    requirement: 'optional',
    mandatory: false,
    minimumSupportedVersionCode: 200000,
    publishedAt: '2026-09-30T19:00:00.000Z',
    changelog: Changelog(
      newFeatures: const [
        'Redesigned credit card billing section with dedicated card and GlassCard day picker',
      ],
      bugFixes: const [
        'Fixed statement cycle end dates for months with fewer than 31 days',
      ],
      notes: const ['Fluid glass card animations on selection'],
    ),
  ),
  AppUpdateRelease(
    id: '2.1.93',
    platform: 'android',
    channel: 'stable',
    status: 'published',
    versionName: '2.1.93',
    versionCode: 201093,
    runtimeVersion: '2.1.0',
    releaseType: 'full',
    requirement: 'optional',
    mandatory: false,
    minimumSupportedVersionCode: 200000,
    publishedAt: '2026-09-30T16:00:00.000Z',
    changelog: Changelog(
      newFeatures: const [
        'True linear scroll fade mask across all screens for seamless liquid top bars',
        'Calendar day-of-month picker for card billing cycles and due dates',
      ],
      bugFixes: const [
        'Tightened top scroll fade height to 12px across all views',
      ],
      notes: const [
        'Optimized shader mask evaluation for low-end GPU performance',
      ],
    ),
  ),
  AppUpdateRelease(
    id: '2.1.92',
    platform: 'android',
    channel: 'stable',
    status: 'published',
    versionName: '2.1.92',
    versionCode: 201092,
    runtimeVersion: '2.1.0',
    releaseType: 'full',
    requirement: 'optional',
    mandatory: false,
    minimumSupportedVersionCode: 200000,
    publishedAt: '2026-09-30T13:00:00.000Z',
    changelog: Changelog(
      newFeatures: const [
        'Header scroll gradient dynamic tinting',
        'Card urgency stripe for overdue and near-due payments',
        'Categories drill-down breakdown in monthly reports',
      ],
      bugFixes: const ['Fixed filter state persistence across tab switches'],
      notes: const [
        'Color-coded urgency stripes: green, amber, and alert crimson',
      ],
    ),
  ),
  AppUpdateRelease(
    id: '2.1.91',
    platform: 'android',
    channel: 'stable',
    status: 'published',
    versionName: '2.1.91',
    versionCode: 201091,
    runtimeVersion: '2.1.0',
    releaseType: 'full',
    requirement: 'optional',
    mandatory: false,
    minimumSupportedVersionCode: 200000,
    publishedAt: '2026-09-30T09:00:00.000Z',
    changelog: Changelog(
      newFeatures: const [
        'Live Firebase cloud verification before syncing ledger mutations',
      ],
      bugFixes: const [
        'Fixed notification routing to review inbox on cold start',
        'Eliminated repeated update alerts when on latest build',
        'Added download cancel guard and concurrency protection',
      ],
      notes: const ['Zero background battery drain from update checker loop'],
    ),
  ),
  AppUpdateRelease(
    id: '2.1.86',
    platform: 'android',
    channel: 'stable',
    status: 'published',
    versionName: '2.1.86',
    versionCode: 201086,
    runtimeVersion: '2.1.0',
    releaseType: 'full',
    requirement: 'optional',
    mandatory: false,
    minimumSupportedVersionCode: 200000,
    publishedAt: '2026-09-27T18:00:00.000Z',
    changelog: Changelog(
      newFeatures: const [
        'Dynamic island bar transitions with tight 200ms spring animations',
      ],
      bugFixes: const [
        'Resolved page swiping friction and applied clamping physics to horizontal pagers',
      ],
      notes: const [
        'Snappy navigation responsiveness across all mobile form factors',
      ],
    ),
  ),
  AppUpdateRelease(
    id: '2.1.85',
    platform: 'android',
    channel: 'stable',
    status: 'published',
    versionName: '2.1.85',
    versionCode: 201085,
    runtimeVersion: '2.1.0',
    releaseType: 'full',
    requirement: 'optional',
    mandatory: false,
    minimumSupportedVersionCode: 200000,
    publishedAt: '2026-09-27T14:00:00.000Z',
    changelog: Changelog(
      newFeatures: const [
        'Pure black AMOLED mode for cards and bottom navigation bar',
      ],
      bugFixes: const [
        'Fixed dark tint glass color consistency on OLED panels',
        'Centered floating action button within island bar',
      ],
      notes: const [
        'Saves up to 15% battery on OLED devices in true black mode',
      ],
    ),
  ),
  AppUpdateRelease(
    id: '2.1.84',
    platform: 'android',
    channel: 'stable',
    status: 'published',
    versionName: '2.1.84',
    versionCode: 201084,
    runtimeVersion: '2.1.0',
    releaseType: 'full',
    requirement: 'optional',
    mandatory: false,
    minimumSupportedVersionCode: 200000,
    publishedAt: '2026-09-27T10:00:00.000Z',
    changelog: Changelog(
      newFeatures: const [
        'Liquid Glass dropdown menus across add-record and transaction history',
      ],
      bugFixes: const [
        'Optimized shader compilation during dropdown open animation',
      ],
      notes: const [
        'Eliminated dropped frames during account and category selection',
      ],
    ),
  ),
  AppUpdateRelease(
    id: '2.1.82',
    platform: 'android',
    channel: 'stable',
    status: 'published',
    versionName: '2.1.82',
    versionCode: 201082,
    runtimeVersion: '2.1.0',
    releaseType: 'full',
    requirement: 'optional',
    mandatory: false,
    minimumSupportedVersionCode: 200000,
    publishedAt: '2026-09-26T21:00:00.000Z',
    changelog: Changelog(
      newFeatures: const [
        'Glass configuration settings: refractive index, blur radius, tint opacity',
        'AMOLED card outlines for crisp contrast in dark environments',
      ],
      bugFixes: const [
        'Resolved calendar island FAB collision on narrow viewports',
      ],
      notes: const [
        'Custom glass shader adjustments saved locally in user preferences',
      ],
    ),
  ),
  AppUpdateRelease(
    id: '2.1.79',
    platform: 'android',
    channel: 'stable',
    status: 'published',
    versionName: '2.1.79',
    versionCode: 201079,
    runtimeVersion: '2.1.0',
    releaseType: 'full',
    requirement: 'optional',
    mandatory: false,
    minimumSupportedVersionCode: 200000,
    publishedAt: '2026-09-26T17:00:00.000Z',
    changelog: Changelog(
      newFeatures: const [
        'Adopted shared Liquid Glass UI widgets library across entire application',
      ],
      bugFixes: const [
        'Fixed cloud overwrite conflicts during simultaneous multi-device sync',
        'Standardized button actions and back handlers',
      ],
      notes: const [
        'Streamlined widget architecture reducing code duplication by 25%',
      ],
    ),
  ),
  AppUpdateRelease(
    id: '2.1.76',
    platform: 'android',
    channel: 'stable',
    status: 'published',
    versionName: '2.1.76',
    versionCode: 201076,
    runtimeVersion: '2.1.0',
    releaseType: 'full',
    requirement: 'optional',
    mandatory: false,
    minimumSupportedVersionCode: 200000,
    publishedAt: '2026-09-26T14:00:00.000Z',
    changelog: Changelog(
      newFeatures: const [
        'Early theme mode boot sequence preventing bright white flash on startup',
      ],
      bugFixes: const [
        'Enforced dark transparent glass default for app island & home avatar circle',
        'Cleaned accent color logic for dynamic Material You palettes',
      ],
      notes: const ['Smooth splash screen fade into selected theme'],
    ),
  ),
  AppUpdateRelease(
    id: '2.1.72',
    platform: 'android',
    channel: 'stable',
    status: 'published',
    versionName: '2.1.72',
    versionCode: 201072,
    runtimeVersion: '2.1.0',
    releaseType: 'full',
    requirement: 'optional',
    mandatory: false,
    minimumSupportedVersionCode: 200000,
    publishedAt: '2026-09-26T11:00:00.000Z',
    changelog: Changelog(
      newFeatures: const [
        'Complete liquid glass rewrite of the history page and transaction rows',
      ],
      bugFixes: const [
        'Fixed date separator alignment and sticky month header rendering',
      ],
      notes: const [
        'Smooth list physics with zero jitter during fast scrolling',
      ],
    ),
  ),
  AppUpdateRelease(
    id: '2.1.66',
    platform: 'android',
    channel: 'stable',
    status: 'published',
    versionName: '2.1.66',
    versionCode: 201066,
    runtimeVersion: '2.1.0',
    releaseType: 'full',
    requirement: 'optional',
    mandatory: false,
    minimumSupportedVersionCode: 200000,
    publishedAt: '2026-09-26T08:00:00.000Z',
    changelog: Changelog(
      newFeatures: const [
        'Unified navigation chrome with GlassAppBar and integrated back navigation',
      ],
      bugFixes: const ['Resolved settings screen overflow on narrow screens'],
      notes: const ['Standardized app bar heights and touch target padding'],
    ),
  ),
  AppUpdateRelease(
    id: '2.1.60',
    platform: 'android',
    channel: 'stable',
    status: 'published',
    versionName: '2.1.60',
    versionCode: 201060,
    runtimeVersion: '2.1.0',
    releaseType: 'full',
    requirement: 'optional',
    mandatory: false,
    minimumSupportedVersionCode: 200000,
    publishedAt: '2026-09-22T16:00:00.000Z',
    changelog: Changelog(
      newFeatures: const [
        'Endless scrolling on balance trend chart with zoom levels: 1W, 1M, 3M, 6M, 1Y, ALL',
        'Virtual viewport panning for smooth historical balance inspection',
      ],
      bugFixes: const [
        'Fixed balance calculation to accurately match projected calendar balances',
      ],
      notes: const [
        'Interactive scrub line showing exact historical net worth',
      ],
    ),
  ),
  AppUpdateRelease(
    id: '2.1.0',
    platform: 'android',
    channel: 'stable',
    status: 'published',
    versionName: '2.1.0',
    versionCode: 201000,
    runtimeVersion: '2.1.0',
    releaseType: 'full',
    requirement: 'optional',
    mandatory: false,
    minimumSupportedVersionCode: 200000,
    publishedAt: '2026-09-15T12:00:00.000Z',
    changelog: Changelog(
      newFeatures: const [
        'Universal bank-agnostic PDF statement parser with password auto-detection',
        'Value Date and opening balance delta tracking for PDF statement imports',
        'Automatic recurring payment schedule detection from transaction history',
      ],
      bugFixes: const [
        'Fixed multi-currency exchange rate rounding errors',
        'Resolved transaction list duplicate entries on rapid sync',
      ],
      notes: const [
        'Major milestone release introducing bank PDF ingestion and recurring scheduler v2',
      ],
    ),
  ),
  AppUpdateRelease(
    id: '2.0.0',
    platform: 'android',
    channel: 'stable',
    status: 'published',
    versionName: '2.0.0',
    versionCode: 200000,
    runtimeVersion: '2.0.0',
    releaseType: 'major',
    requirement: 'optional',
    mandatory: false,
    minimumSupportedVersionCode: 100000,
    publishedAt: '2026-09-01T12:00:00.000Z',
    changelog: Changelog(
      newFeatures: const [
        'Complete Flutter 3 architecture rewrite with Material You and Riverpod',
        'Automated SMS and notification transaction capture engine',
        'Credit cards and Loan EMI tracking modules',
        'Biometric authentication (Fingerprint & Face Unlock) with AES-256 local encryption',
      ],
      bugFixes: const [
        'Fixed background notification sync and system permission handling',
      ],
      notes: const [
        'Initial 2.0 release marking complete transition to modern native Flutter stack',
      ],
    ),
  ),
  AppUpdateRelease(
    id: '1.6.12',
    platform: 'android',
    channel: 'stable',
    status: 'published',
    versionName: '1.6.12',
    versionCode: 1061200,
    runtimeVersion: '1.6.0',
    releaseType: 'full',
    requirement: 'optional',
    mandatory: false,
    minimumSupportedVersionCode: 100000,
    publishedAt: '2026-06-16T15:00:00.000Z',
    changelog: Changelog(
      newFeatures: const [
        'Ultimate scheduling engine: custom recurrence intervals and weekend posting rules',
      ],
      bugFixes: const [
        'Fixed recurring payment reminder notifications upon device reboot',
      ],
      notes: const ['Optimized background alarm manager triggers'],
    ),
  ),
  AppUpdateRelease(
    id: '1.6.10',
    platform: 'android',
    channel: 'stable',
    status: 'published',
    versionName: '1.6.10',
    versionCode: 1061000,
    runtimeVersion: '1.6.0',
    releaseType: 'full',
    requirement: 'optional',
    mandatory: false,
    minimumSupportedVersionCode: 100000,
    publishedAt: '2026-06-14T18:00:00.000Z',
    changelog: Changelog(
      newFeatures: const [
        'Real-time auto-sync engine with multi-client delta hashing',
      ],
      bugFixes: const [
        'Fixed skipped recurring payments calculation in cashflow forecasts',
      ],
      notes: const [
        'Conflict-free replicated data types for offline ledger editing',
      ],
    ),
  ),
  AppUpdateRelease(
    id: '1.6.8',
    platform: 'android',
    channel: 'stable',
    status: 'published',
    versionName: '1.6.8',
    versionCode: 1060800,
    runtimeVersion: '1.6.0',
    releaseType: 'full',
    requirement: 'optional',
    mandatory: false,
    minimumSupportedVersionCode: 100000,
    publishedAt: '2026-06-14T14:00:00.000Z',
    changelog: Changelog(
      newFeatures: const [],
      bugFixes: const [
        'Updated Firestore collection security rules for seamless multi-tier backups',
      ],
      notes: const ['Hardened cloud authentication session validation'],
    ),
  ),
  AppUpdateRelease(
    id: '1.6.6',
    platform: 'android',
    channel: 'stable',
    status: 'published',
    versionName: '1.6.6',
    versionCode: 1060600,
    runtimeVersion: '1.6.0',
    releaseType: 'full',
    requirement: 'optional',
    mandatory: false,
    minimumSupportedVersionCode: 100000,
    publishedAt: '2026-06-14T10:00:00.000Z',
    changelog: Changelog(
      newFeatures: const [
        'Hierarchical category taxonomy with nested subcategories and custom icon picker',
      ],
      bugFixes: const [
        'Fixed category search matching across deeply nested child items',
      ],
      notes: const ['Automated migration for existing category assignments'],
    ),
  ),
  AppUpdateRelease(
    id: '1.6.4',
    platform: 'android',
    channel: 'stable',
    status: 'published',
    versionName: '1.6.4',
    versionCode: 1060400,
    runtimeVersion: '1.6.0',
    releaseType: 'full',
    requirement: 'optional',
    mandatory: false,
    minimumSupportedVersionCode: 100000,
    publishedAt: '2026-06-13T16:00:00.000Z',
    changelog: Changelog(
      newFeatures: const [
        'Background application update notification dispatch on device startup',
      ],
      bugFixes: const [
        'Fixed startup freeze on Android 14 devices caused by synchronous shared preferences',
      ],
      notes: const [
        'Hardened Android release pipeline and Proguard obfuscation rules',
      ],
    ),
  ),
  AppUpdateRelease(
    id: '1.6.0',
    platform: 'android',
    channel: 'stable',
    status: 'published',
    versionName: '1.6.0',
    versionCode: 1060000,
    runtimeVersion: '1.6.0',
    releaseType: 'major',
    requirement: 'optional',
    mandatory: false,
    minimumSupportedVersionCode: 100000,
    publishedAt: '2026-06-03T12:00:00.000Z',
    changelog: Changelog(
      newFeatures: const [
        'Comprehensive multi-account net summaries and aggregated balance overview',
        'Swipe-to-navigate drawer menu with instant route switching',
      ],
      bugFixes: const ['Resolved drawer duplicate navigation history bug'],
      notes: const [
        'Stable 1.6.0 release introducing full accounts management suite',
      ],
    ),
  ),
  AppUpdateRelease(
    id: '1.5.0',
    platform: 'android',
    channel: 'stable',
    status: 'published',
    versionName: '1.5.0',
    versionCode: 1050000,
    runtimeVersion: '1.5.0',
    releaseType: 'full',
    requirement: 'optional',
    mandatory: false,
    minimumSupportedVersionCode: 100000,
    publishedAt: '2026-06-02T12:00:00.000Z',
    changelog: Changelog(
      newFeatures: const [
        'Interactive loan manager with amortization table calculations and EMI reminders',
        'Real-time multi-currency exchange rate conversions',
      ],
      bugFixes: const [],
      notes: const ['Introduced progressive web app companion shell'],
    ),
  ),
  AppUpdateRelease(
    id: '1.4.0',
    platform: 'android',
    channel: 'stable',
    status: 'published',
    versionName: '1.4.0',
    versionCode: 1040000,
    runtimeVersion: '1.4.0',
    releaseType: 'full',
    requirement: 'optional',
    mandatory: false,
    minimumSupportedVersionCode: 100000,
    publishedAt: '2026-06-01T18:00:00.000Z',
    changelog: Changelog(
      newFeatures: const [
        'Android update channel recovery and automated OTA self-healing',
        'Swipe gesture sensitivity calibration for tab navigation',
      ],
      bugFixes: const [
        'Fixed update download stalled connections on unstable Wi-Fi',
      ],
      notes: const [],
    ),
  ),
  AppUpdateRelease(
    id: '1.3.0',
    platform: 'android',
    channel: 'stable',
    status: 'published',
    versionName: '1.3.0',
    versionCode: 1030000,
    runtimeVersion: '1.3.0',
    releaseType: 'full',
    requirement: 'optional',
    mandatory: false,
    minimumSupportedVersionCode: 100000,
    publishedAt: '2026-06-01T14:00:00.000Z',
    changelog: Changelog(
      newFeatures: const [
        'Beta update channel subscription support in settings',
        'Patch train release distribution system',
      ],
      bugFixes: const [],
      notes: const [],
    ),
  ),
  AppUpdateRelease(
    id: '1.2.2',
    platform: 'android',
    channel: 'stable',
    status: 'published',
    versionName: '1.2.2',
    versionCode: 1020200,
    runtimeVersion: '1.2.0',
    releaseType: 'full',
    requirement: 'optional',
    mandatory: false,
    minimumSupportedVersionCode: 100000,
    publishedAt: '2026-06-01T10:00:00.000Z',
    changelog: Changelog(
      newFeatures: const [
        'Native OTA update manager with SHA-256 package verification',
        'Integrated CMake codegen pipeline for high-performance cryptographic operations',
      ],
      bugFixes: const [],
      notes: const ['Foundational mobile update release pipeline'],
    ),
  ),
];

class AppUpdateState {
  final UpdateStatus status;
  final AppUpdateRelease? latestRelease;
  final AppUpdateRelease? currentRelease;
  final List<AppUpdateRelease> allReleases;
  final String currentVersionName;
  final int currentVersionCode;
  final double progress;
  final int bytesWritten;
  final int bytesExpected;
  final String? errorMessage;
  final String? notificationWarning;
  final String? downloadedApkPath;

  AppUpdateState({
    this.status = UpdateStatus.idle,
    this.latestRelease,
    this.currentRelease,
    this.allReleases = const [],
    this.currentVersionName = '',
    this.currentVersionCode = 0,
    this.progress = 0.0,
    this.bytesWritten = 0,
    this.bytesExpected = 0,
    this.errorMessage,
    this.notificationWarning,
    this.downloadedApkPath,
  });

  AppUpdateState copyWith({
    UpdateStatus? status,
    AppUpdateRelease? latestRelease,
    AppUpdateRelease? currentRelease,
    List<AppUpdateRelease>? allReleases,
    String? currentVersionName,
    int? currentVersionCode,
    double? progress,
    int? bytesWritten,
    int? bytesExpected,
    String? errorMessage,
    String? notificationWarning,
    String? downloadedApkPath,
    bool clearLatestRelease = false,
    bool clearCurrentRelease = false,
    bool clearErrorMessage = false,
    bool clearNotificationWarning = false,
    bool clearDownloadedApkPath = false,
  }) {
    return AppUpdateState(
      status: status ?? this.status,
      latestRelease: clearLatestRelease
          ? null
          : latestRelease ?? this.latestRelease,
      currentRelease: clearCurrentRelease
          ? null
          : currentRelease ?? this.currentRelease,
      allReleases: allReleases ?? this.allReleases,
      currentVersionName: currentVersionName ?? this.currentVersionName,
      currentVersionCode: currentVersionCode ?? this.currentVersionCode,
      progress: progress ?? this.progress,
      bytesWritten: bytesWritten ?? this.bytesWritten,
      bytesExpected: bytesExpected ?? this.bytesExpected,
      errorMessage: clearErrorMessage
          ? null
          : errorMessage ?? this.errorMessage,
      notificationWarning: clearNotificationWarning
          ? null
          : notificationWarning ?? this.notificationWarning,
      downloadedApkPath: clearDownloadedApkPath
          ? null
          : downloadedApkPath ?? this.downloadedApkPath,
    );
  }
}

class AppUpdateProvider extends StateNotifier<AppUpdateState> {
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 5),
    ),
  );
  CancelToken? _downloadCancelToken;
  DateTime? _lastCheckedAt;
  final Future<void> Function(String)? _notifyUpdate;

  AppUpdateProvider({Future<void> Function(String)? notifyUpdate})
    // ignore: prefer_initializing_formals
    : _notifyUpdate = notifyUpdate,
      super(AppUpdateState()) {
    _init();
  }

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  Future<void> _clearOldUpdates() async {
    try {
      final dir = await getTemporaryDirectory();
      if (await dir.exists()) {
        final files = dir.listSync();
        for (final file in files) {
          if (file is File && file.path.toLowerCase().endsWith('.apk')) {
            await file.delete();
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _init() async {
    await _clearOldUpdates();
    if (!mounted) return;
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentCode = int.tryParse(packageInfo.buildNumber) ?? 0;
      final currentName = packageInfo.version;
      if (mounted) {
        state = state.copyWith(
          currentVersionName: currentName,
          currentVersionCode: currentCode,
          allReleases: kBuiltInReleaseHistory,
          status: UpdateStatus.idle,
        );
      }
    } catch (_) {
      if (mounted) {
        state = state.copyWith(
          allReleases: kBuiltInReleaseHistory,
          status: UpdateStatus.idle,
        );
      }
    }
  }

  Future<void> checkForUpdates({bool force = false}) async {
    try {
      if (Firebase.apps.isEmpty) {
        state = state.copyWith(
          status: UpdateStatus.idle,
          allReleases: kBuiltInReleaseHistory,
        );
        return;
      }
    } catch (_) {
      state = state.copyWith(
        status: UpdateStatus.idle,
        allReleases: kBuiltInReleaseHistory,
      );
      return;
    }

    if (!force &&
        _lastCheckedAt != null &&
        DateTime.now().difference(_lastCheckedAt!) < const Duration(hours: 6)) {
      return;
    }

    state = state.copyWith(
      status: UpdateStatus.checking,
      clearErrorMessage: true,
      clearNotificationWarning: true,
      clearDownloadedApkPath: true,
    );

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersionCode = int.tryParse(packageInfo.buildNumber) ?? 0;
      final currentVersionName = packageInfo.version;
      state = state.copyWith(
        currentVersionName: currentVersionName,
        currentVersionCode: currentVersionCode,
      );

      final currentReleaseFuture = _releaseForVersionCode(currentVersionCode);

      final channelDocFuture = () async {
        try {
          return await _firestore
              .collection('appUpdates/android/channels')
              .doc('stable')
              .get()
              .timeout(const Duration(seconds: 4));
        } catch (_) {
          return null;
        }
      }();

      final results = await Future.wait([
        currentReleaseFuture,
        channelDocFuture,
      ]);
      final currentRelease = results[0] as AppUpdateRelease?;
      final channelDoc = results[1] as DocumentSnapshot?;

      final allReleases = kBuiltInReleaseHistory;

      int? latestVersionCode;
      String latestReleaseId = '';
      String rawVersionName = '';
      AppUpdateRelease? candidateRelease;

      if (channelDoc != null && channelDoc.exists) {
        final data = channelDoc.data() as Map<String, dynamic>?;
        if (data != null) {
          latestVersionCode = _nullableIntValue(data['latestVersionCode']);
          latestReleaseId = _stringValue(data['latestReleaseId']);
          rawVersionName = _stringValue(
            data['latestVersionName'] ?? data['versionName'],
          );
          if (latestVersionCode != null) {
            try {
              candidateRelease = await _releaseForVersionCode(
                latestVersionCode,
                releaseId: latestReleaseId,
              );
            } catch (_) {}
          }
        }
      }

      if (latestVersionCode == null) {
        _lastCheckedAt = DateTime.now();
        state = state.copyWith(
          status: UpdateStatus.idle,
          currentRelease: currentRelease,
          allReleases: allReleases,
          clearCurrentRelease: currentRelease == null,
          clearLatestRelease: true,
        );
        return;
      }
      final latestName = candidateRelease?.versionName.isNotEmpty == true
          ? candidateRelease!.versionName
          : rawVersionName;

      final isNewer = isReleaseNewer(
        latestVersionCode: latestVersionCode,
        latestVersionName: latestName,
        currentVersionCode: currentVersionCode,
        currentVersionName: currentVersionName,
      );

      if (isNewer) {
        final release =
            candidateRelease ??
            AppUpdateRelease.fromJson(
              latestReleaseId.isNotEmpty
                  ? latestReleaseId
                  : 'stable-$latestVersionCode',
              {
                'versionName': rawVersionName.isNotEmpty
                    ? rawVersionName
                    : 'v$latestVersionCode',
                'versionCode': latestVersionCode,
                'platform': 'android',
                'channel': 'stable',
                'status': 'published',
                'publishedAt': DateTime.now().toIso8601String(),
                'changelog': {
                  'newFeatures': ['New update is available to install.'],
                  'bugFixes': <String>[],
                  'notes': <String>[],
                },
              },
            );

        _lastCheckedAt = DateTime.now();
        await publishAvailableRelease(
          release,
          currentRelease: currentRelease,
          allReleases: allReleases,
        );
        return;
      }

      _lastCheckedAt = DateTime.now();
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('cached_latest_release_json');
      } catch (_) {}
      state = state.copyWith(
        status: UpdateStatus.idle,
        currentRelease: currentRelease ?? candidateRelease,
        allReleases: allReleases,
        clearCurrentRelease: currentRelease == null && candidateRelease == null,
        clearLatestRelease: true,
      );
    } catch (_) {
      _lastCheckedAt = null;
      state = state.copyWith(
        status: UpdateStatus.idle,
        clearErrorMessage: true,
        allReleases: state.allReleases.isNotEmpty
            ? state.allReleases
            : kBuiltInReleaseHistory,
      );
    }
  }

  @protected
  Future<void> publishAvailableRelease(
    AppUpdateRelease release, {
    AppUpdateRelease? currentRelease,
    required List<AppUpdateRelease> allReleases,
  }) async {
    if (!mounted) return;
    state = state.copyWith(
      status: UpdateStatus.idle,
      latestRelease: release,
      currentRelease: currentRelease,
      allReleases: allReleases,
      clearCurrentRelease: currentRelease == null,
      clearErrorMessage: true,
      clearNotificationWarning: true,
    );
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'cached_latest_release_json',
        jsonEncode(release.toJson()),
      );
    } catch (_) {}
    // Notification delivery is optional; only deliver if custom handler was supplied.
    if (_notifyUpdate != null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (!mounted) return;
        await prefs.reload();
        if (!mounted) return;
        const notificationKey = 'lastNotifiedVersionCode.stable';
        final lastNotifiedVersionCode = prefs.getInt(notificationKey) ?? 0;
        if (release.versionCode > lastNotifiedVersionCode) {
          await _notifyUpdate(release.versionName);
          if (!mounted) return;
          if (!await prefs.setInt(notificationKey, release.versionCode)) {
            throw StateError('Could not record update notification delivery.');
          }
        }
      } catch (error, stack) {
        developer.log(
          'Could not deliver the update notification',
          name: 'AppUpdateProvider',
          error: error,
          stackTrace: stack,
        );
        if (!mounted) return;
        state = state.copyWith(
          notificationWarning:
              'The update notification could not be shown. You can still download and install the update here.',
        );
      }
    }
  }

  static bool isReleaseNewer({
    required int latestVersionCode,
    required String latestVersionName,
    required int currentVersionCode,
    required String currentVersionName,
  }) {
    final cleanLatest = _cleanVersion(latestVersionName);
    final cleanCurrent = _cleanVersion(currentVersionName);

    // 1. If semantic versions match, it's definitely the current version (no update)
    if (cleanLatest.isNotEmpty &&
        cleanCurrent.isNotEmpty &&
        cleanLatest == cleanCurrent) {
      return false;
    }

    // 2. Transition guard: moving from legacy 200xxxx series (e.g. 2.1.146) to 210xxxx series (e.g. 2.1.51)
    if (latestVersionCode >= 2100000 &&
        currentVersionCode > 0 &&
        currentVersionCode < 2100000) {
      return true;
    }

    // 3. Semantic version comparison (e.g. 2.1.52 > 2.1.51, 2.2.00 > 2.1.99, 3.0.00 > 2.9.99, 10.0.00 > 9.9.99)
    final semverCmp = _compareSemanticVersions(cleanLatest, cleanCurrent);
    if (semverCmp != null) {
      return semverCmp > 0;
    }

    // 4. Normalized versionCode fallback (handles ABI split offset: arm64 adds 2000, armv7 adds 1000, etc.)
    final normCurrent = _normalizeVersionCode(currentVersionCode);
    final normLatest = _normalizeVersionCode(latestVersionCode);
    return normLatest > normCurrent;
  }

  static String _cleanVersion(String v) {
    return v.trim().replaceFirst(RegExp(r'^[vV]'), '');
  }

  static int? _compareSemanticVersions(String v1, String v2) {
    if (v1.isEmpty || v2.isEmpty) return null;
    final parts1 = v1.split('.').map((p) => int.tryParse(p) ?? -1).toList();
    final parts2 = v2.split('.').map((p) => int.tryParse(p) ?? -1).toList();
    if (parts1.any((p) => p == -1) || parts2.any((p) => p == -1)) {
      return null;
    }
    final maxLength = parts1.length > parts2.length
        ? parts1.length
        : parts2.length;
    for (int i = 0; i < maxLength; i++) {
      final p1 = i < parts1.length ? parts1[i] : 0;
      final p2 = i < parts2.length ? parts2[i] : 0;
      if (p1 > p2) return 1;
      if (p1 < p2) return -1;
    }
    return 0;
  }

  static String formatDisplayBuild(String versionName, int fallbackCode) {
    final clean = _cleanVersion(versionName);
    final parts = clean.split('.');
    if (parts.length >= 3) {
      final major = int.tryParse(parts[0]);
      final minor = int.tryParse(parts[1]);
      final patch = int.tryParse(parts[2]);
      if (major != null && minor != null && patch != null) {
        return '${major * 1000 + minor * 100 + patch}';
      }
    }
    if (fallbackCode > 0) {
      if (fallbackCode >= 2100000) {
        final codeWithoutOffset = fallbackCode - 2100000;
        final normalized = codeWithoutOffset >= 2000
            ? codeWithoutOffset - 2000
            : codeWithoutOffset;
        if (normalized > 0) return '$normalized';
      }
      return '$fallbackCode';
    }
    return 'Unknown';
  }

  static int _normalizeVersionCode(int code) {
    if (code >= 2000000) {
      final offset = code - 2000000;
      return 2000000 + (offset % 1000);
    }
    if (code >= 1000000) {
      final offset = code - 1000000;
      return 1000000 + (offset % 1000);
    }
    return code;
  }

  Future<AppUpdateRelease?> _releaseForVersionCode(
    int versionCode, {
    String? releaseId,
  }) async {
    if (versionCode <= 0) return null;
    final ids = <String>[
      if (releaseId != null && releaseId.trim().isNotEmpty) releaseId.trim(),
      'stable-$versionCode',
      versionCode.toString(),
    ];

    try {
      for (final id in ids.toSet()) {
        final releaseDoc = await _firestore
            .collection('appUpdates/android/releases')
            .doc(id)
            .get();
        if (!releaseDoc.exists) continue;
        return AppUpdateRelease.fromFirestore(releaseDoc);
      }
      return null;
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') return null;
      rethrow;
    }
  }

  Future<void> downloadUpdate() async {
    if (state.status == UpdateStatus.downloading) return;
    if (state.latestRelease?.apk == null) return;

    _downloadCancelToken?.cancel();
    _downloadCancelToken = CancelToken();

    state = state.copyWith(
      status: UpdateStatus.downloading,
      progress: 0.0,
      bytesWritten: 0,
      bytesExpected: state.latestRelease!.apk!.sizeBytes,
      clearErrorMessage: true,
      clearDownloadedApkPath: true,
    );

    final apk = state.latestRelease!.apk!;

    try {
      final dir = await getTemporaryDirectory();
      final savePath = '${dir.path}/${apk.fileName}';

      await _dio.download(
        apk.downloadUrl,
        savePath,
        cancelToken: _downloadCancelToken,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            state = state.copyWith(
              progress: received / total,
              bytesWritten: received,
              bytesExpected: total,
            );
          }
        },
      );

      // -----------------------------------------------------------------------
      // SHA-256 integrity check — verify the downloaded file matches the hash
      // stored in Firestore before allowing installation.
      // -----------------------------------------------------------------------
      state = state.copyWith(progress: 1.0);

      final downloadedFile = File(savePath);
      final fileBytes = await downloadedFile.readAsBytes();
      final computedHash = sha256.convert(fileBytes).toString();

      // Normalise: Firestore value may include a 'sha256:' prefix.
      final expectedHash = apk.sha256.startsWith('sha256:')
          ? apk.sha256.substring('sha256:'.length)
          : apk.sha256;

      if (computedHash != expectedHash) {
        // Delete the corrupted / tampered file immediately.
        await downloadedFile.delete();
        state = state.copyWith(
          status: UpdateStatus.error,
          clearDownloadedApkPath: true,
          errorMessage:
              'Download integrity check failed. The file may be corrupted or '
              'tampered with. Please try again.',
        );
        return;
      }

      state = state.copyWith(
        status: UpdateStatus.downloaded,
        downloadedApkPath: savePath,
      );
      await installUpdate();
    } catch (e) {
      if (e is DioException && CancelToken.isCancel(e)) {
        state = state.copyWith(
          status: UpdateStatus.idle,
          progress: 0.0,
          bytesWritten: 0,
          clearErrorMessage: true,
        );
        return;
      }
      state = state.copyWith(
        status: UpdateStatus.error,
        errorMessage: 'Failed to download update: $e',
      );
    } finally {
      _downloadCancelToken = null;
    }
  }

  void cancelDownload() {
    if (_downloadCancelToken != null && !_downloadCancelToken!.isCancelled) {
      _downloadCancelToken!.cancel('User cancelled download');
    }
    state = state.copyWith(
      status: UpdateStatus.idle,
      progress: 0.0,
      bytesWritten: 0,
      clearErrorMessage: true,
    );
  }

  Future<void> installUpdate() async {
    await openStoreListing();
  }

  Future<void> openStoreListing() async {
    final marketUri = Uri.parse('market://details?id=com.joelpjoji.one.wallet');
    final webUri = Uri.parse(
      'https://play.google.com/store/apps/details?id=com.joelpjoji.one.wallet',
    );
    try {
      if (await canLaunchUrl(marketUri)) {
        await launchUrl(marketUri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      try {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
  }
}

final appUpdateProvider =
    StateNotifierProvider<AppUpdateProvider, AppUpdateState>((ref) {
      return AppUpdateProvider();
    });

Map<String, dynamic> _mapValue(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return <String, dynamic>{};
}

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return value
      .map((item) => item.toString())
      .where((item) => item.trim().isNotEmpty)
      .toList();
}

String _stringValue(Object? value, {String fallback = ''}) {
  if (value == null) return fallback;
  final string = value.toString().trim();
  return string.isEmpty ? fallback : string;
}

int _intValue(Object? value) => _nullableIntValue(value) ?? 0;

int? _nullableIntValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value);
  return null;
}

String _dateString(Object? value) {
  if (value is Timestamp) return value.toDate().toIso8601String();
  return _stringValue(value);
}
