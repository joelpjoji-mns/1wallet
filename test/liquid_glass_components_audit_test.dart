import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Comprehensive static audit test to identify all UI components across
/// `lib/src` where liquid glass components (from `package:liquid_glass_widgets`
/// or `app_kit.dart` glass primitives) are NOT being used where a liquid
/// glass equivalent exists.
void main() {
  test('Audit: identify all non-glass UI components across the app', () {
    final baseDir = Directory('lib/src');
    expect(baseDir.existsSync(), isTrue, reason: 'lib/src must exist');

    final dartFiles =
        baseDir
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    final auditResults = <String, List<_AuditFinding>>{
      'Dialogs (AlertDialog vs GlassDialog)': [],
      'Bottom Sheets (AppSheetSurface / ModalSheet vs GlassSheet / GlassModalSheet)':
          [],
      'Text & Form Inputs (TextField / TextFormField vs GlassTextField / AppGlassTextField / GlassFormField)':
          [],
      'Segmented Controls & TabBars (SegmentedButton / TabBar vs GlassSegmentedControl / GlassTabBar)':
          [],
      'Sliders (Slider vs GlassSlider)': [],
      'Dropdowns & Menus (DropdownButtonFormField / PopupMenuButton vs GlassDropdownPill / GlassMenu / GlassPullDownButton)':
          [],
      'Chips (Chip / ActionChip / FilterChip / InputChip vs GlassChip)': [],
      'Badges (Badge.count vs GlassBadge)': [],
      'Progress Indicators (LinearProgressIndicator / CircularProgressIndicator vs GlassProgressIndicator / LiquidProgressIndicator)':
          [],
      'Opaque Panels & Rows (AppSurfaces.panel / glass: false vs GlassCard)':
          [],
    };

    final chipRegex = RegExp(
      r'\b(InputChip|FilterChip|ActionChip|ChoiceChip|Chip)\(',
    );
    final badgeRegex = RegExp(r'\bBadge(\.count)?\(');

    for (final file in dartFiles) {
      final relPath = file.path.replaceAll('\\', '/').split('lib/src/').last;
      final lines = file.readAsLinesSync();

      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        final lineNum = i + 1;
        if (line.startsWith('//') || line.startsWith('/*')) continue;

        // 1. Dialogs
        if (line.contains('AlertDialog(')) {
          auditResults['Dialogs (AlertDialog vs GlassDialog)']!.add(
            _AuditFinding(
              relPath: relPath,
              line: lineNum,
              element: 'AlertDialog',
              replacement: 'GlassDialog / showAppConfirmDialog',
              snippet: line,
            ),
          );
        }

        // 2. Bottom Sheets
        if (relPath.endsWith('app_kit.dart') &&
            line.contains('DecoratedBox(') &&
            i > 1845 &&
            i < 1860) {
          auditResults['Bottom Sheets (AppSheetSurface / ModalSheet vs GlassSheet / GlassModalSheet)']!
              .add(
                _AuditFinding(
                  relPath: relPath,
                  line: lineNum,
                  element: 'AppSheetSurface (opaque scaffoldBackgroundColor)',
                  replacement: 'GlassSheet / GlassModalSheet surface',
                  snippet: line,
                ),
              );
        }

        // 3. Inputs & Form Fields
        if (line.contains('TextFormField(')) {
          auditResults['Text & Form Inputs (TextField / TextFormField vs GlassTextField / AppGlassTextField / GlassFormField)']!
              .add(
                _AuditFinding(
                  relPath: relPath,
                  line: lineNum,
                  element: 'TextFormField',
                  replacement:
                      'AppGlassTextField / GlassFormField / GlassTextField',
                  snippet: line,
                ),
              );
        } else if (RegExp(r'(?<![A-Za-z0-9_])TextField\(').hasMatch(line) &&
            !line.contains('AppGlassTextField') &&
            !line.contains('GlassTextField')) {
          auditResults['Text & Form Inputs (TextField / TextFormField vs GlassTextField / AppGlassTextField / GlassFormField)']!
              .add(
                _AuditFinding(
                  relPath: relPath,
                  line: lineNum,
                  element: 'TextField',
                  replacement: 'AppGlassTextField / GlassTextField',
                  snippet: line,
                ),
              );
        }

        // 4. Segmented Controls & TabBars
        if (line.contains('SegmentedButton') &&
            !line.contains('GlassSegmentedControl')) {
          auditResults['Segmented Controls & TabBars (SegmentedButton / TabBar vs GlassSegmentedControl / GlassTabBar)']!
              .add(
                _AuditFinding(
                  relPath: relPath,
                  line: lineNum,
                  element: 'SegmentedButton',
                  replacement: 'GlassSegmentedControl',
                  snippet: line,
                ),
              );
        }
        if (RegExp(r'(?<![A-Za-z0-9_])TabBar\(').hasMatch(line) &&
            !line.contains('GlassTabBar')) {
          auditResults['Segmented Controls & TabBars (SegmentedButton / TabBar vs GlassSegmentedControl / GlassTabBar)']!
              .add(
                _AuditFinding(
                  relPath: relPath,
                  line: lineNum,
                  element: 'TabBar',
                  replacement: 'GlassTabBar / GlassSegmentedControl',
                  snippet: line,
                ),
              );
        }

        // 5. Sliders
        if (RegExp(r'(?<![A-Za-z0-9_])Slider\(').hasMatch(line) &&
            !line.contains('GlassSlider')) {
          auditResults['Sliders (Slider vs GlassSlider)']!.add(
            _AuditFinding(
              relPath: relPath,
              line: lineNum,
              element: 'Slider',
              replacement: 'GlassSlider',
              snippet: line,
            ),
          );
        }

        // 6. Dropdowns & Menus
        if (line.contains('DropdownButtonFormField') ||
            RegExp(r'\bDropdownButton<').hasMatch(line)) {
          auditResults['Dropdowns & Menus (DropdownButtonFormField / PopupMenuButton vs GlassDropdownPill / GlassMenu / GlassPullDownButton)']!
              .add(
                _AuditFinding(
                  relPath: relPath,
                  line: lineNum,
                  element: 'DropdownButtonFormField / DropdownButton',
                  replacement:
                      'GlassDropdownPill / GlassPicker / GlassPullDownButton',
                  snippet: line,
                ),
              );
        }
        if (line.contains('PopupMenuButton<')) {
          auditResults['Dropdowns & Menus (DropdownButtonFormField / PopupMenuButton vs GlassDropdownPill / GlassMenu / GlassPullDownButton)']!
              .add(
                _AuditFinding(
                  relPath: relPath,
                  line: lineNum,
                  element: 'PopupMenuButton',
                  replacement: 'GlassPullDownButton / GlassMenu',
                  snippet: line,
                ),
              );
        }

        // 7. Chips
        if (chipRegex.hasMatch(line) &&
            !line.contains('GlassChip') &&
            !line.contains('ChipThemeData')) {
          auditResults['Chips (Chip / ActionChip / FilterChip / InputChip vs GlassChip)']!
              .add(
                _AuditFinding(
                  relPath: relPath,
                  line: lineNum,
                  element: 'Chip / FilterChip / ActionChip / InputChip',
                  replacement: 'GlassChip',
                  snippet: line,
                ),
              );
        }

        // 8. Badges
        if (badgeRegex.hasMatch(line) && !line.contains('GlassBadge')) {
          auditResults['Badges (Badge.count vs GlassBadge)']!.add(
            _AuditFinding(
              relPath: relPath,
              line: lineNum,
              element: 'Badge / Badge.count',
              replacement: 'GlassBadge',
              snippet: line,
            ),
          );
        }

        // 9. Progress Indicators
        if (line.contains('LinearProgressIndicator(')) {
          auditResults['Progress Indicators (LinearProgressIndicator / CircularProgressIndicator vs GlassProgressIndicator / LiquidProgressIndicator)']!
              .add(
                _AuditFinding(
                  relPath: relPath,
                  line: lineNum,
                  element: 'LinearProgressIndicator',
                  replacement:
                      'GlassProgressIndicator / LiquidProgressIndicator',
                  snippet: line,
                ),
              );
        }
        if (line.contains('CircularProgressIndicator(') &&
            !relPath.contains('app_kit.dart')) {
          auditResults['Progress Indicators (LinearProgressIndicator / CircularProgressIndicator vs GlassProgressIndicator / LiquidProgressIndicator)']!
              .add(
                _AuditFinding(
                  relPath: relPath,
                  line: lineNum,
                  element: 'CircularProgressIndicator',
                  replacement: 'GlassProgressIndicator / AppInlineSpinner',
                  snippet: line,
                ),
              );
        }

        // 10. Explicit glass: false or AppSurfaces.panel
        if (line.contains('glass: false') ||
            (line.contains('AppSurfaces.panel(') &&
                !relPath.contains('app_kit.dart'))) {
          auditResults['Opaque Panels & Rows (AppSurfaces.panel / glass: false vs GlassCard)']!
              .add(
                _AuditFinding(
                  relPath: relPath,
                  line: lineNum,
                  element: line.contains('glass: false')
                      ? 'glass: false opt-out'
                      : 'AppSurfaces.panel (opaque surface)',
                  replacement: 'GlassCard / glass: true (opt-in)',
                  snippet: line,
                ),
              );
        }
      }
    }

    // Print full human-readable audit report to test logs
    stdout.writeln(
      '================================================================',
    );
    stdout.writeln(
      '           1WALLET LIQUID GLASS COMPONENT AUDIT REPORT          ',
    );
    stdout.writeln(
      '================================================================',
    );

    var totalFindings = 0;
    auditResults.forEach((category, findings) {
      totalFindings += findings.length;
      stdout.writeln('\n### $category: ${findings.length} locations');
      for (final finding in findings) {
        stdout.writeln(
          '  - ${finding.relPath}:${finding.line} [${finding.element}] -> ${finding.replacement}',
        );
      }
    });

    stdout.writeln(
      '\n================================================================',
    );
    stdout.writeln(
      'TOTAL AUDIT FINDINGS: $totalFindings locations across lib/src',
    );
    stdout.writeln(
      '================================================================\n',
    );

    expect(
      totalFindings,
      isPositive,
      reason: 'The audit must discover all candidates',
    );
  });
}

class _AuditFinding {
  const _AuditFinding({
    required this.relPath,
    required this.line,
    required this.element,
    required this.replacement,
    required this.snippet,
  });

  final String relPath;
  final int line;
  final String element;
  final String replacement;
  final String snippet;
}
