# 🔬 Comprehensive UI Component Inventory & `g1455` Migration Audit

**Document Version:** 1.0.0  
**Date:** November 2026  
**Target Design System:** `package:g1455/g1455.dart` (PlugFox Liquid Glass)  
**Repository Scope:** `lib/src/features/**` and `lib/src/widgets/**`  

---

## 1. Executive Summary & Architectural Overview

This audit establishes a complete component-level inventory of all user interface elements across the **1Wallet** Flutter mobile and desktop application. The primary mission is achieving native Apple iOS visual fidelity—featuring authentic liquid glass refraction, continuous superellipse curves, sleek floating island navigation, borderless frosted glass styling, and hardware-budgeted shader execution (`GlassLedger` and `GlassHardware`).

### Key Inventory Metrics
- **Total UI Primitives Cataloged:** 487
- **Already Powered by `g1455` / Canonical Glass:** 376 (77.2%)
- **Non-`g1455` Candidate Elements:** 111 (22.8%)

---

## 2. Component Replacement Matrix

| Existing / Legacy Component | Target `g1455` Primitive | Visual Treatment & Configuration |
| :--- | :--- | :--- |
| `liquid_glass_widgets` engine | `package:g1455/g1455.dart` | Initialized via `await GlassHost.precache()` in `main()` |
| Root App Wrapper | `GlassHost` | Configured with `GlassHardware.detect()`, `GlassPress()`, and `GlassThemeData` |
| `GlassAppBar` / `AppBar` | `GlassBar` / `GlassAppBar` | Continuous blur with real-time backdrop refraction |
| `BottomIslandNavBar` + FAB | `GlassTabBar.bottom` + independent FAB | Sleek floating island pill dock with subtle backdrop blur and clean FAB separation |
| `SectionCard` / `Card` | `GlassCard` (`g1455`) | iOS continuous superellipse, subtle luminous edge sheen (`kCalibratedRim`) |
| `BrandFrostedPanel` (Launch/Auth) | `GlassCard` on `LaunchPalette` | Deep refractive glass with brand color aberration |
| `AppGlassTextField` / `TextField` | `GlassTextField` | Inner refraction, smooth focus glow, iOS typography |
| `AppSwitchListTile` / `Switch` | `GlassSwitch` | Native iOS pill geometry with dynamic spring physics |
| `Slider` | `GlassSlider` | Liquid thumb indicator with elastic stretch |
| `SegmentedButton` | `GlassSegmentedControl` | Translucent sliding glass pill indicator |
| `AlertDialog` / `showAppConfirmDialog` | `GlassDialog` | Blurred backdrop with iOS-style divider lines |
| `showAppSheet` / `AppSheetSurface` | `GlassSheet` / `GlassModalSheet` | Native drag capsule, continuous rounded top corners |
| `CreditCardView` | Refractive `GlassCard` | Interactive tilt-responsive sheen and specular edges |

---

## 3. Categorized Domain Inventory (10 Domains)

### 1. Scaffolds & App Bars
**Totals:** 40 g1455 / canonical | 1 candidate replacements

#### Candidate Non-`g1455` Occurrences
| File:Line | Component | Target `g1455` Primitive | Visual Effect Classification | Notes |
| :--- | :--- | :--- | :--- | :--- |
| `features/transactions/attachment_thumbnail.dart:130` | `AppBar` | `GlassAppBar / GlassBar` | **Real-time Refraction** | Attachment thumbnail modal uses standard Material AppBar |

#### Active Canonical `g1455` Implementations
- **RouteScaffold**: 36 occurrences across routes
- **GlassAppBar**: 4 occurrences across routes

### 2. Navigation Chrome
**Totals:** 16 g1455 / canonical | 0 candidate replacements

#### Active Canonical `g1455` Implementations
- **AppMainDrawer**: 5 occurrences across routes
- **IslandFloatingActionButton**: 3 occurrences across routes
- **BottomIslandNavBar**: 2 occurrences across routes
- **GlassBlendGroup**: 2 occurrences across routes
- **GlassTabBar**: 4 occurrences across routes

### 3. Surfaces & Cards
**Totals:** 90 g1455 / canonical | 40 candidate replacements

#### Candidate Non-`g1455` Occurrences
| File:Line | Component | Target `g1455` Primitive | Visual Effect Classification | Notes |
| :--- | :--- | :--- | :--- | :--- |
| `features/calendar/calendar_screen.dart:728` | `AppSurfaces.panel` | `GlassCard / glass: true` | **Static Frosted Panel** | Flat decorated box panel fallback |
| `features/cards/cards_screen.dart:71` | `MetricTile` | `MetricTile (Opaque nested in GlassCard)` | **Static Frosted Panel** | Sub-metric block inside section summaries |
| `features/cards/cards_screen.dart:172` | `AppSurfaces.panel` | `GlassCard / glass: true` | **Static Frosted Panel** | Flat decorated box panel fallback |
| `features/cards/cards_screen.dart:178` | `AppSurfaces.panel` | `GlassCard / glass: true` | **Static Frosted Panel** | Flat decorated box panel fallback |
| `features/categories/categories_screen.dart:69` | `MetricTile` | `MetricTile (Opaque nested in GlassCard)` | **Static Frosted Panel** | Sub-metric block inside section summaries |
| `features/categories/categories_screen.dart:78` | `MetricTile` | `MetricTile (Opaque nested in GlassCard)` | **Static Frosted Panel** | Sub-metric block inside section summaries |
| `features/currencies/currencies_screen.dart:95` | `MetricTile` | `MetricTile (Opaque nested in GlassCard)` | **Static Frosted Panel** | Sub-metric block inside section summaries |
| `features/currencies/currencies_screen.dart:104` | `MetricTile` | `MetricTile (Opaque nested in GlassCard)` | **Static Frosted Panel** | Sub-metric block inside section summaries |
| `features/home/home_widget_card.dart:144` | `AppSurfaces.panel` | `GlassCard / glass: true` | **Static Frosted Panel** | Flat decorated box panel fallback |
| `features/home/home_widget_card.dart:308` | `MetricTile` | `MetricTile (Opaque nested in GlassCard)` | **Static Frosted Panel** | Sub-metric block inside section summaries |
| `features/home/home_widgets.dart:185` | `AppSurfaces.panel` | `GlassCard / glass: true` | **Static Frosted Panel** | Flat decorated box panel fallback |
| `features/home/home_widgets.dart:1939` | `MetricTile` | `MetricTile (Opaque nested in GlassCard)` | **Static Frosted Panel** | Sub-metric block inside section summaries |
| `features/home/home_widgets.dart:1952` | `MetricTile` | `MetricTile (Opaque nested in GlassCard)` | **Static Frosted Panel** | Sub-metric block inside section summaries |
| `features/home/home_widgets.dart:2984` | `AppSurfaces.panel` | `GlassCard / glass: true` | **Static Frosted Panel** | Flat decorated box panel fallback |
| `features/home/home_widgets_new.dart:295` | `MetricTile` | `MetricTile (Opaque nested in GlassCard)` | **Static Frosted Panel** | Sub-metric block inside section summaries |
| `features/home/home_widgets_new.dart:313` | `MetricTile` | `MetricTile (Opaque nested in GlassCard)` | **Static Frosted Panel** | Sub-metric block inside section summaries |
| `features/home/home_widgets_new.dart:804` | `MetricTile` | `MetricTile (Opaque nested in GlassCard)` | **Static Frosted Panel** | Sub-metric block inside section summaries |
| `features/home/home_widgets_new.dart:822` | `MetricTile` | `MetricTile (Opaque nested in GlassCard)` | **Static Frosted Panel** | Sub-metric block inside section summaries |
| `features/home/home_widgets_new.dart:1166` | `MetricTile` | `MetricTile (Opaque nested in GlassCard)` | **Static Frosted Panel** | Sub-metric block inside section summaries |
| `features/home/home_widgets_new.dart:1184` | `MetricTile` | `MetricTile (Opaque nested in GlassCard)` | **Static Frosted Panel** | Sub-metric block inside section summaries |
| `features/imports/import_statement_screen.dart:178` | `MetricTile` | `MetricTile (Opaque nested in GlassCard)` | **Static Frosted Panel** | Sub-metric block inside section summaries |
| `features/imports/import_statement_screen.dart:190` | `MetricTile` | `MetricTile (Opaque nested in GlassCard)` | **Static Frosted Panel** | Sub-metric block inside section summaries |
| `features/imports/import_statement_screen.dart:199` | `MetricTile` | `MetricTile (Opaque nested in GlassCard)` | **Static Frosted Panel** | Sub-metric block inside section summaries |
| `features/imports/import_statement_screen.dart:367` | `AppSurfaces.panel` | `GlassCard / glass: true` | **Static Frosted Panel** | Flat decorated box panel fallback |
| `features/loans/loans_screen.dart:92` | `MetricTile` | `MetricTile (Opaque nested in GlassCard)` | **Static Frosted Panel** | Sub-metric block inside section summaries |
| `features/loans/loans_screen.dart:104` | `MetricTile` | `MetricTile (Opaque nested in GlassCard)` | **Static Frosted Panel** | Sub-metric block inside section summaries |
| `features/loans/loans_screen.dart:992` | `MetricTile` | `MetricTile (Opaque nested in GlassCard)` | **Static Frosted Panel** | Sub-metric block inside section summaries |
| `features/loans/loans_screen.dart:1003` | `MetricTile` | `MetricTile (Opaque nested in GlassCard)` | **Static Frosted Panel** | Sub-metric block inside section summaries |
| `features/loans/loans_screen.dart:1015` | `MetricTile` | `MetricTile (Opaque nested in GlassCard)` | **Static Frosted Panel** | Sub-metric block inside section summaries |
| `features/loans/loans_screen.dart:1025` | `MetricTile` | `MetricTile (Opaque nested in GlassCard)` | **Static Frosted Panel** | Sub-metric block inside section summaries |
| `features/main/main_drawer_components.dart:26` | `AppSurfaces.panel` | `GlassCard / glass: true` | **Static Frosted Panel** | Flat decorated box panel fallback |
| `features/main/main_drawer_components.dart:161` | `AppSurfaces.panel` | `GlassCard / glass: true` | **Static Frosted Panel** | Flat decorated box panel fallback |
| `features/main/main_shell.dart:611` | `AppSurfaces.panel` | `GlassCard / glass: true` | **Static Frosted Panel** | Flat decorated box panel fallback |
| `features/settings/data_backup_screen.dart:150` | `MetricTile` | `MetricTile (Opaque nested in GlassCard)` | **Static Frosted Panel** | Sub-metric block inside section summaries |
| `features/settings/data_backup_screen.dart:159` | `MetricTile` | `MetricTile (Opaque nested in GlassCard)` | **Static Frosted Panel** | Sub-metric block inside section summaries |
| `features/sync/sync_screen.dart:204` | `AppSurfaces.panel` | `GlassCard / glass: true` | **Static Frosted Panel** | Flat decorated box panel fallback |
| `features/sync/sync_screen.dart:212` | `AppSurfaces.panel` | `GlassCard / glass: true` | **Static Frosted Panel** | Flat decorated box panel fallback |
| `features/sync/sync_screen.dart:569` | `MetricTile` | `MetricTile (Opaque nested in GlassCard)` | **Static Frosted Panel** | Sub-metric block inside section summaries |
| `features/sync/sync_screen.dart:581` | `MetricTile` | `MetricTile (Opaque nested in GlassCard)` | **Static Frosted Panel** | Sub-metric block inside section summaries |
| `features/transactions/transaction_row.dart:206` | `AppSurfaces.panel` | `GlassCard / glass: true` | **Static Frosted Panel** | Flat decorated box panel fallback |

#### Active Canonical `g1455` Implementations
- **CreditCardView**: 4 occurrences across routes
- **SectionCard**: 68 occurrences across routes
- **GlassCard**: 10 occurrences across routes
- **BrandFrostedPanel**: 8 occurrences across routes

### 4. List Rows & Tiles
**Totals:** 65 g1455 / canonical | 1 candidate replacements

#### Candidate Non-`g1455` Occurrences
| File:Line | Component | Target `g1455` Primitive | Visual Effect Classification | Notes |
| :--- | :--- | :--- | :--- | :--- |
| `features/login/offline_mode_sheet.dart:130` | `CheckboxListTile` | `GlassSwitch / Custom Glass Checkbox` | **Static Frosted Panel** | Consent acknowledgement checkbox on offline sheet |

#### Active Canonical `g1455` Implementations
- **AppSwitchListTile**: 14 occurrences across routes
- **PremiumRow**: 42 occurrences across routes
- **TransactionRow**: 9 occurrences across routes

### 5. Form Inputs & Search
**Totals:** 36 g1455 / canonical | 21 candidate replacements

#### Candidate Non-`g1455` Occurrences
| File:Line | Component | Target `g1455` Primitive | Visual Effect Classification | Notes |
| :--- | :--- | :--- | :--- | :--- |
| `features/accounts/account_editor_screen.dart:202` | `TextFormField` | `AppGlassTextField / GlassTextField` | **Real-time Refraction** | Form validation text field using standard Material decoration |
| `features/accounts/account_editor_screen.dart:209` | `TextFormField` | `AppGlassTextField / GlassTextField` | **Real-time Refraction** | Form validation text field using standard Material decoration |
| `features/accounts/account_editor_screen.dart:303` | `TextFormField` | `AppGlassTextField / GlassTextField` | **Real-time Refraction** | Form validation text field using standard Material decoration |
| `features/accounts/account_editor_screen.dart:354` | `TextFormField` | `AppGlassTextField / GlassTextField` | **Real-time Refraction** | Form validation text field using standard Material decoration |
| `features/accounts/account_editor_screen.dart:457` | `TextFormField` | `AppGlassTextField / GlassTextField` | **Real-time Refraction** | Form validation text field using standard Material decoration |
| `features/accounts/account_editor_screen.dart:1074` | `TextFormField` | `AppGlassTextField / GlassTextField` | **Real-time Refraction** | Form validation text field using standard Material decoration |
| `features/accounts/secure_account_details_screen.dart:378` | `TextFormField` | `AppGlassTextField / GlassTextField` | **Real-time Refraction** | Form validation text field using standard Material decoration |
| `features/categories/categories_screen.dart:185` | `TextFormField` | `AppGlassTextField / GlassTextField` | **Real-time Refraction** | Form validation text field using standard Material decoration |
| `features/loans/loans_screen.dart:419` | `TextFormField` | `AppGlassTextField / GlassTextField` | **Real-time Refraction** | Form validation text field using standard Material decoration |
| `features/recurring/recurring_screen.dart:842` | `TextFormField` | `AppGlassTextField / GlassTextField` | **Real-time Refraction** | Form validation text field using standard Material decoration |
| `features/recurring/recurring_screen.dart:854` | `TextFormField` | `AppGlassTextField / GlassTextField` | **Real-time Refraction** | Form validation text field using standard Material decoration |
| `features/recurring/recurring_screen.dart:980` | `TextFormField` | `AppGlassTextField / GlassTextField` | **Real-time Refraction** | Form validation text field using standard Material decoration |
| `features/recurring/recurring_screen.dart:1125` | `TextFormField` | `AppGlassTextField / GlassTextField` | **Real-time Refraction** | Form validation text field using standard Material decoration |
| `features/recurring/recurring_screen.dart:1148` | `TextFormField` | `AppGlassTextField / GlassTextField` | **Real-time Refraction** | Form validation text field using standard Material decoration |
| `features/settings/settings_components.dart:209` | `TextField` | `AppGlassTextField / GlassTextField` | **Real-time Refraction** | Unwrapped standard TextField |
| `features/settings/settings_screen.dart:457` | `TextField` | `AppGlassTextField / GlassTextField` | **Real-time Refraction** | Unwrapped standard TextField |
| `features/settings/settings_screen.dart:690` | `TextField` | `AppGlassTextField / GlassTextField` | **Real-time Refraction** | Unwrapped standard TextField |
| `features/transactions/add_record_screen.dart:579` | `TextFormField` | `AppGlassTextField / GlassTextField` | **Real-time Refraction** | Form validation text field using standard Material decoration |
| `features/transactions/add_record_screen.dart:777` | `TextField` | `AppGlassTextField / GlassTextField` | **Real-time Refraction** | Unwrapped standard TextField |
| `features/transactions/add_record_screen.dart:934` | `TextFormField` | `AppGlassTextField / GlassTextField` | **Real-time Refraction** | Form validation text field using standard Material decoration |
| `features/transactions/add_record_screen.dart:945` | `TextFormField` | `AppGlassTextField / GlassTextField` | **Real-time Refraction** | Form validation text field using standard Material decoration |

#### Active Canonical `g1455` Implementations
- **GlassSearchBar**: 1 occurrences across routes
- **AppGlassTextField**: 21 occurrences across routes
- **PremiumSearchInput**: 6 occurrences across routes
- **GlassTextField**: 8 occurrences across routes

### 6. Controls & Toggles
**Totals:** 50 g1455 / canonical | 16 candidate replacements

#### Candidate Non-`g1455` Occurrences
| File:Line | Component | Target `g1455` Primitive | Visual Effect Classification | Notes |
| :--- | :--- | :--- | :--- | :--- |
| `features/accounts/account_editor_screen.dart:1096` | `IconButton` | `GlassButton / GlassIconButton / AppActionButton` | **Real-time Refraction** | Standard Material IconButton |
| `features/accounts/account_editor_screen.dart:1280` | `IconButton` | `GlassButton / GlassIconButton / AppActionButton` | **Real-time Refraction** | Standard Material IconButton |
| `features/accounts/secure_account_details_screen.dart:387` | `IconButton` | `GlassButton / GlassIconButton / AppActionButton` | **Real-time Refraction** | Standard Material IconButton |
| `features/accounts/secure_account_details_screen.dart:528` | `IconButton` | `GlassButton / GlassIconButton / AppActionButton` | **Real-time Refraction** | Standard Material IconButton |
| `features/calendar/calendar_screen.dart:146` | `IconButton` | `GlassButton / GlassIconButton / AppActionButton` | **Real-time Refraction** | Standard Material IconButton |
| `features/calendar/calendar_screen.dart:176` | `IconButton` | `GlassButton / GlassIconButton / AppActionButton` | **Real-time Refraction** | Standard Material IconButton |
| `features/calendar/calendar_screen.dart:625` | `IconButton` | `GlassButton / GlassIconButton / AppActionButton` | **Real-time Refraction** | Standard Material IconButton |
| `features/capture/notification_capture_screen.dart:491` | `IconButton` | `GlassButton / GlassIconButton / AppActionButton` | **Real-time Refraction** | Standard Material IconButton |
| `features/capture/review_queue_screen.dart:750` | `IconButton` | `GlassButton / GlassIconButton / AppActionButton` | **Real-time Refraction** | Standard Material IconButton |
| `features/capture/sms_capture_screen.dart:706` | `IconButton` | `GlassButton / GlassIconButton / AppActionButton` | **Real-time Refraction** | Standard Material IconButton |
| `features/loans/loans_screen.dart:1924` | `IconButton` | `GlassButton / GlassIconButton / AppActionButton` | **Real-time Refraction** | Standard Material IconButton |
| `features/onboarding/onboarding_screen.dart:897` | `IconButton` | `GlassButton / GlassIconButton / AppActionButton` | **Real-time Refraction** | Standard Material IconButton |
| `features/transactions/add_record_screen.dart:297` | `TabBar` | `GlassSegmentedControl / GlassTabBar` | **Real-time Refraction** | Standard Material TabBar in view tab header |
| `features/transactions/attachment_thumbnail.dart:140` | `IconButton` | `GlassButton / GlassIconButton / AppActionButton` | **Real-time Refraction** | Standard Material IconButton |
| `features/transactions/attachment_thumbnail.dart:145` | `IconButton` | `GlassButton / GlassIconButton / AppActionButton` | **Real-time Refraction** | Standard Material IconButton |
| `features/transactions/transactions_screen.dart:1380` | `IconButton` | `GlassButton / GlassIconButton / AppActionButton` | **Real-time Refraction** | Standard Material IconButton |

#### Active Canonical `g1455` Implementations
- **HeaderIconButton**: 45 occurrences across routes
- **GlassIconButton**: 3 occurrences across routes
- **GlassSlider**: 1 occurrences across routes
- **GlassSegmentedControl**: 1 occurrences across routes

### 7. Overlays & Dialogs
**Totals:** 27 g1455 / canonical | 11 candidate replacements

#### Candidate Non-`g1455` Occurrences
| File:Line | Component | Target `g1455` Primitive | Visual Effect Classification | Notes |
| :--- | :--- | :--- | :--- | :--- |
| `features/accounts/account_editor_screen.dart:874` | `AlertDialog` | `GlassDialog / showAppConfirmDialog` | **Real-time Refraction** | Standard Material modal dialog |
| `features/accounts/secure_account_details_screen.dart:151` | `AlertDialog` | `GlassDialog / showAppConfirmDialog` | **Real-time Refraction** | Standard Material modal dialog |
| `features/capture/review_queue_screen.dart:967` | `AlertDialog` | `GlassDialog / showAppConfirmDialog` | **Real-time Refraction** | Standard Material modal dialog |
| `features/categories/categories_screen.dart:173` | `AlertDialog` | `GlassDialog / showAppConfirmDialog` | **Real-time Refraction** | Standard Material modal dialog |
| `features/currencies/currencies_screen.dart:371` | `AlertDialog` | `GlassDialog / showAppConfirmDialog` | **Real-time Refraction** | Standard Material modal dialog |
| `features/imports/import_statement_screen.dart:586` | `AlertDialog` | `GlassDialog / showAppConfirmDialog` | **Real-time Refraction** | Standard Material modal dialog |
| `features/settings/data_backup_screen.dart:517` | `AlertDialog` | `GlassDialog / showAppConfirmDialog` | **Real-time Refraction** | Standard Material modal dialog |
| `features/settings/settings_screen.dart:455` | `AlertDialog` | `GlassDialog / showAppConfirmDialog` | **Real-time Refraction** | Standard Material modal dialog |
| `features/settings/settings_screen.dart:658` | `AlertDialog` | `GlassDialog / showAppConfirmDialog` | **Real-time Refraction** | Standard Material modal dialog |
| `features/transactions/transactions_screen.dart:1066` | `AlertDialog` | `GlassDialog / showAppConfirmDialog` | **Real-time Refraction** | Standard Material modal dialog |
| `widgets/color_picker_dialog.dart:14` | `AlertDialog` | `GlassDialog / showAppConfirmDialog` | **Real-time Refraction** | Standard Material modal dialog |

#### Active Canonical `g1455` Implementations
- **showAppConfirmDialog**: 22 occurrences across routes
- **AppSheetSurface**: 3 occurrences across routes
- **GlassDialog**: 2 occurrences across routes

### 8. Menus & Pickers
**Totals:** 23 g1455 / canonical | 11 candidate replacements

#### Candidate Non-`g1455` Occurrences
| File:Line | Component | Target `g1455` Primitive | Visual Effect Classification | Notes |
| :--- | :--- | :--- | :--- | :--- |
| `features/accounts/account_editor_screen.dart:373` | `DropdownButtonFormField` | `GlassDropdownPill / showFullScreenPicker` | **Real-time Refraction** | Material form dropdown select |
| `features/accounts/account_editor_screen.dart:415` | `DropdownButtonFormField` | `GlassDropdownPill / showFullScreenPicker` | **Real-time Refraction** | Material form dropdown select |
| `features/imports/import_statement_screen.dart:239` | `DropdownButtonFormField` | `GlassDropdownPill / showFullScreenPicker` | **Real-time Refraction** | Material form dropdown select |
| `features/imports/import_statement_screen.dart:262` | `DropdownButtonFormField` | `GlassDropdownPill / showFullScreenPicker` | **Real-time Refraction** | Material form dropdown select |
| `features/loans/loans_screen.dart:392` | `DropdownButtonFormField` | `GlassDropdownPill / showFullScreenPicker` | **Real-time Refraction** | Material form dropdown select |
| `features/loans/loans_screen.dart:2657` | `DropdownButtonFormField` | `GlassDropdownPill / showFullScreenPicker` | **Real-time Refraction** | Material form dropdown select |
| `features/recurring/recurring_screen.dart:927` | `DropdownButtonFormField` | `GlassDropdownPill / showFullScreenPicker` | **Real-time Refraction** | Material form dropdown select |
| `features/recurring/recurring_screen.dart:949` | `DropdownButtonFormField` | `GlassDropdownPill / showFullScreenPicker` | **Real-time Refraction** | Material form dropdown select |
| `features/recurring/recurring_screen.dart:1073` | `DropdownButtonFormField` | `GlassDropdownPill / showFullScreenPicker` | **Real-time Refraction** | Material form dropdown select |
| `features/sync/sync_screen.dart:386` | `DropdownButtonFormField` | `GlassDropdownPill / showFullScreenPicker` | **Real-time Refraction** | Material form dropdown select |
| `features/transactions/add_record_screen.dart:1076` | `PopupMenuButton` | `GlassDropdownPill / GlassMenuAnchor` | **Real-time Refraction** | Material popup menu button |

#### Active Canonical `g1455` Implementations
- **showFullScreenPicker**: 22 occurrences across routes
- **GlassDropdownPill**: 1 occurrences across routes

### 9. Badges & Chips
**Totals:** 13 g1455 / canonical | 6 candidate replacements

#### Candidate Non-`g1455` Occurrences
| File:Line | Component | Target `g1455` Primitive | Visual Effect Classification | Notes |
| :--- | :--- | :--- | :--- | :--- |
| `features/capture/notification_capture_screen.dart:874` | `Material Chip` | `GlassChip / GlassButton pill` | **Real-time Refraction** | Material filter/action chip |
| `features/capture/review_queue_screen.dart:1012` | `Material Chip` | `GlassChip / GlassButton pill` | **Real-time Refraction** | Material filter/action chip |
| `features/capture/sms_capture_screen.dart:380` | `Material Chip` | `GlassChip / GlassButton pill` | **Real-time Refraction** | Material filter/action chip |
| `features/capture/sms_capture_screen.dart:1063` | `Material Chip` | `GlassChip / GlassButton pill` | **Real-time Refraction** | Material filter/action chip |
| `features/home/widgets_manager_screen.dart:237` | `Material Chip` | `GlassChip / GlassButton pill` | **Real-time Refraction** | Material filter/action chip |
| `features/transactions/add_record_screen.dart:742` | `Material Chip` | `GlassChip / GlassButton pill` | **Real-time Refraction** | Material filter/action chip |

#### Active Canonical `g1455` Implementations
- **GlassChip**: 8 occurrences across routes
- **GlassBadge**: 5 occurrences across routes

### 10. Progress & Indicators
**Totals:** 16 g1455 / canonical | 4 candidate replacements

#### Candidate Non-`g1455` Occurrences
| File:Line | Component | Target `g1455` Primitive | Visual Effect Classification | Notes |
| :--- | :--- | :--- | :--- | :--- |
| `features/launch/brand_widgets.dart:638` | `LinearProgressIndicator` | `LiquidProgressIndicator` | **Real-time Refraction** | Material linear progress bar |
| `features/settings/account_deletion_screen.dart:25` | `CircularProgressIndicator` | `AppInlineSpinner / GlassProgressIndicator` | **Real-time Refraction** | Standard Material circular spinner |
| `features/updates/updates_screen.dart:1256` | `CircularProgressIndicator` | `AppInlineSpinner / GlassProgressIndicator` | **Real-time Refraction** | Standard Material circular spinner |
| `features/updates/updates_screen.dart:1266` | `CircularProgressIndicator` | `AppInlineSpinner / GlassProgressIndicator` | **Real-time Refraction** | Standard Material circular spinner |

#### Active Canonical `g1455` Implementations
- **AppInlineSpinner**: 10 occurrences across routes
- **GlassProgressIndicator**: 5 occurrences across routes
- **LiquidProgressIndicator**: 1 occurrences across routes

---

## 4. Visual Effect Classification & Performance Rules

### A. Real-time Refraction
- Applied to: Root headers (`GlassAppBar` / `GlassBar`), modals (`GlassDialog`, `GlassSheet`), interactive hero components (`CreditCardView`), input fields (`GlassTextField`), and segmented selectors (`GlassSegmentedControl`).
- Uses the hardware-accelerated Skia/Impeller shader pass with dynamic background sampling and chromatic aberration.

### B. Static Frosted Panel
- Applied to: Dense scrolling list items (`TransactionRow`, `PremiumRow`), nested tiles (`MetricTile`), and AMOLED dark mode panels.
- **Performance Invariant:** To guarantee consistent 60/120 fps scroll rates, list view rows MUST NOT evaluate real-time backdrops individually. They render lightweight opaque or pre-baked frosted surfaces with subtle borders.

### C. Sleek Floating Island & Independent FAB
- Applied to: Bottom island dock (`BottomIslandNavBar`) + independently floating Action Button (`IslandFloatingActionButton`).
- Rendered as a thin standalone floating pill dock using `GlassTabBar.bottom` with subtle backdrop blur and zero harsh wireframe border. The Quick-Add FAB floats independently with clear separation and zero overlap over the Accounts tab.

---

## 5. Critical Invariants Compliance

1. **Integer Minor Currency Units (`amountMinor`):** Verified. All financial calculations remain discrete integers; no floating-point arithmetic is introduced.
2. **Privacy Masking (`PrivacyText` / `privacyModeProvider`):** Preserved across all balance heroes, transaction rows, and card preview metrics.
3. **Single Source of Truth (`app_kit.dart`):** Upgrading primitives in `app_kit.dart` automatically propagates to all consuming feature screens without fragmenting the design language.

