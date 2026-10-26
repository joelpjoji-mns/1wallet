import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:firebase_core/firebase_core.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/notification_service.dart';

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
}

enum UpdateStatus { idle, checking, downloading, downloaded, installing, error }

final List<AppUpdateRelease> kBuiltInReleaseHistory = [
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
      notes: const [
        'Added over 380 unit and widget integration tests',
      ],
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
      notes: const [
        'Fluid glass card animations on selection',
      ],
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
      bugFixes: const [
        'Fixed filter state persistence across tab switches',
      ],
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
      notes: const [
        'Zero background battery drain from update checker loop',
      ],
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
      notes: const [
        'Smooth splash screen fade into selected theme',
      ],
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
      bugFixes: const [
        'Resolved settings screen overflow on narrow screens',
      ],
      notes: const [
        'Standardized app bar heights and touch target padding',
      ],
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
      notes: const [
        'Optimized background alarm manager triggers',
      ],
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
      notes: const [
        'Hardened cloud authentication session validation',
      ],
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
      notes: const [
        'Automated migration for existing category assignments',
      ],
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
      bugFixes: const [
        'Resolved drawer duplicate navigation history bug',
      ],
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
      notes: const [
        'Introduced progressive web app companion shell',
      ],
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
      notes: const [
        'Foundational mobile update release pipeline',
      ],
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
    String? downloadedApkPath,
    bool clearLatestRelease = false,
    bool clearCurrentRelease = false,
    bool clearErrorMessage = false,
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

  AppUpdateProvider() : super(AppUpdateState()) {
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
    state = state.copyWith(allReleases: kBuiltInReleaseHistory);
    try {
      if (Firebase.apps.isEmpty) return;
    } catch (_) {
      return; // If Firebase is not linked
    }
    await checkForUpdates();
  }

  Future<void> checkForUpdates({bool force = false}) async {
    try {
      if (Firebase.apps.isEmpty) {
        state = state.copyWith(status: UpdateStatus.idle);
        return;
      }
    } catch (_) {
      state = state.copyWith(status: UpdateStatus.idle);
      return;
    }

    if (!force &&
        _lastCheckedAt != null &&
        DateTime.now().difference(_lastCheckedAt!) < const Duration(hours: 6)) {
      return;
    }
    _lastCheckedAt = DateTime.now();

    state = state.copyWith(
      status: UpdateStatus.checking,
      clearErrorMessage: true,
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

      final currentRelease = await _releaseForVersionCode(currentVersionCode);

      List<AppUpdateRelease> fetchedReleases = [];
      try {
        final res = await _dio.get(
          'https://api.github.com/repos/joelpjoji-mns/1wallet/releases?per_page=30',
          options: Options(
            headers: {'User-Agent': '1Wallet-App'},
            sendTimeout: const Duration(seconds: 8),
            receiveTimeout: const Duration(seconds: 8),
          ),
        );
        if (res.statusCode == 200 && res.data is List) {
          for (final item in res.data) {
            if (item is Map) {
              final r = _parseGitHubRelease(Map<String, dynamic>.from(item));
              if (r != null) fetchedReleases.add(r);
            }
          }
        }
      } catch (_) {}

      try {
        final querySnap = await _firestore
            .collection('appUpdates/android/releases')
            .orderBy('versionCode', descending: true)
            .limit(200)
            .get();
        if (querySnap.docs.isNotEmpty) {
          final firestoreReleases = querySnap.docs
              .map((doc) => AppUpdateRelease.fromFirestore(doc))
              .toList();
          fetchedReleases = _mergeReleases(fetchedReleases, firestoreReleases);
        }
      } catch (_) {}

      final allReleases = _mergeReleases(fetchedReleases, kBuiltInReleaseHistory);

      DocumentSnapshot? channelDoc;
      try {
        channelDoc = await _firestore
            .collection('appUpdates/android/channels')
            .doc('stable')
            .get();
      } catch (_) {
        channelDoc = null;
      }

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

      // If Firestore channel document was unavailable, permission denied,
      // or unpopulated, seamlessly fallback to the newest release discovered
      // from GitHub Releases API:
      if (candidateRelease == null && allReleases.isNotEmpty) {
        final newestFromApi = allReleases.first;
        candidateRelease = newestFromApi;
        latestVersionCode = newestFromApi.versionCode;
        latestReleaseId = newestFromApi.id;
        rawVersionName = newestFromApi.versionName;
      }

      if (latestVersionCode == null) {
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
        final release = candidateRelease ??
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

        state = state.copyWith(
          status: UpdateStatus.idle,
          latestRelease: release,
          currentRelease: currentRelease,
          allReleases: allReleases,
          clearCurrentRelease: currentRelease == null,
        );

        final prefs = await SharedPreferences.getInstance();
        const notificationKey = 'lastNotifiedVersionCode.stable';
        final lastNotifiedVersionCode = prefs.getInt(notificationKey) ?? 0;
        if (latestVersionCode > lastNotifiedVersionCode) {
          await NotificationService.showUpdateNotification(
            release.versionName,
          );
          await prefs.setInt(notificationKey, latestVersionCode);
        }
        return;
      }

      state = state.copyWith(
        status: UpdateStatus.idle,
        currentRelease: currentRelease ?? candidateRelease,
        allReleases: allReleases,
        clearCurrentRelease: currentRelease == null && candidateRelease == null,
        clearLatestRelease: true,
      );
    } catch (e) {
      final message = e is FirebaseException && e.code == 'permission-denied'
          ? 'Update metadata is not available yet. Please try again later.'
          : 'Failed to check for updates: $e';
      state = state.copyWith(
        status: UpdateStatus.error,
        errorMessage: message,
        allReleases: state.allReleases.isNotEmpty
            ? state.allReleases
            : kBuiltInReleaseHistory,
      );
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
    final maxLength =
        parts1.length > parts2.length ? parts1.length : parts2.length;
    for (int i = 0; i < maxLength; i++) {
      final p1 = i < parts1.length ? parts1[i] : 0;
      final p2 = i < parts2.length ? parts2[i] : 0;
      if (p1 > p2) return 1;
      if (p1 < p2) return -1;
    }
    return 0;
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

  static List<AppUpdateRelease> _mergeReleases(
    List<AppUpdateRelease> primary,
    List<AppUpdateRelease> secondary,
  ) {
    final seen = <String>{};
    final result = <AppUpdateRelease>[];
    for (final r in primary) {
      if (seen.add(r.versionName)) result.add(r);
    }
    for (final r in secondary) {
      if (seen.add(r.versionName)) result.add(r);
    }
    result.sort((a, b) {
      final dateA = DateTime.tryParse(a.publishedAt) ?? DateTime(1970);
      final dateB = DateTime.tryParse(b.publishedAt) ?? DateTime(1970);
      final cmp = dateB.compareTo(dateA);
      if (cmp != 0) return cmp;
      return b.versionCode.compareTo(a.versionCode);
    });
    return result;
  }

  static AppUpdateRelease? _parseGitHubRelease(Map<String, dynamic> json) {
    final tagName = _stringValue(json['tag_name']);
    if (!tagName.startsWith('android-')) return null;

    final versionName = tagName.replaceFirst('android-', '');
    final publishedAt = _stringValue(json['published_at']);
    final body = _stringValue(json['body']);

    ApkMetadata? apk;
    final assets = json['assets'];
    if (assets is List) {
      for (final a in assets) {
        if (a is Map) {
          final aMap = Map<String, dynamic>.from(a);
          final name = _stringValue(aMap['name']);
          if (name.endsWith('.apk')) {
            apk = ApkMetadata(
              downloadUrl: _stringValue(aMap['browser_download_url']),
              fileName: name,
              sizeBytes: _intValue(aMap['size']),
              sha256: '',
              architecture: name.contains('arm64') ? 'arm64-v8a' : 'universal',
            );
            break;
          }
        }
      }
    }

    final changelog = _parseMarkdownChangelog(body);
    final versionCode = _deriveVersionCode(versionName);

    return AppUpdateRelease(
      id: tagName,
      platform: 'android',
      channel: 'stable',
      status: 'published',
      versionName: versionName,
      versionCode: versionCode,
      runtimeVersion: versionName,
      releaseType: 'full',
      requirement: 'optional',
      mandatory: false,
      minimumSupportedVersionCode: 0,
      publishedAt: publishedAt,
      changelog: changelog,
      apk: apk,
    );
  }

  static Changelog _parseMarkdownChangelog(String body) {
    final features = <String>[];
    final fixes = <String>[];
    final notes = <String>[];

    final lines = body.split('\n');
    String currentSection = '';

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.startsWith('#')) {
        final heading = line.toLowerCase();
        if (heading.contains('feature')) {
          currentSection = 'features';
        } else if (heading.contains('fix') || heading.contains('bug')) {
          currentSection = 'fixes';
        } else if (heading.contains('improvement') ||
            heading.contains('note') ||
            heading.contains('enhancement')) {
          currentSection = 'notes';
        } else {
          currentSection = '';
        }
        continue;
      }

      if (line.startsWith('-') || line.startsWith('*')) {
        final clean = line.replaceFirst(RegExp(r'^[-*]\s*'), '').trim();
        if (clean.isEmpty) continue;
        if (currentSection == 'features') {
          features.add(clean);
        } else if (currentSection == 'fixes') {
          fixes.add(clean);
        } else {
          notes.add(clean);
        }
      }
    }

    return Changelog(
      newFeatures: features,
      bugFixes: fixes,
      notes: notes,
    );
  }

  static int _deriveVersionCode(String versionName) {
    final clean = versionName.trim().replaceFirst(RegExp(r'^[vV]'), '');
    final parts = clean.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    if (parts.length >= 3) {
      final major = parts[0];
      final minor = parts[1];
      final patch = parts[2];
      return major * 1000000 + minor * 100000 + patch;
    }
    return 0;
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
      state = state.copyWith(
        progress: 1.0,
      );

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
    final apkPath = state.downloadedApkPath;
    if (apkPath == null) return;

    state = state.copyWith(status: UpdateStatus.installing);
    try {
      if (!await File(apkPath).exists()) {
        throw Exception(
          'Downloaded APK was not found. Please download it again.',
        );
      }
      final result = await OpenFilex.open(
        apkPath,
        type: 'application/vnd.android.package-archive',
      );
      if (result.type != ResultType.done) {
        throw Exception(result.message);
      }
      state = state.copyWith(
        status: UpdateStatus.downloaded,
        errorMessage:
            'Installer opened. If Android blocks it, allow installs from 1wallet or uninstall the debug build first.',
      );
    } catch (e) {
      state = state.copyWith(
        status: UpdateStatus.error,
        errorMessage: 'Failed to install update: $e',
      );
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
