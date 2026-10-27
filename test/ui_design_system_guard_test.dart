import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Lint-style guard for the canonical UI primitives documented in
/// `lib/src/design/AGENTS.md` and `lib/src/widgets/AGENTS.md`.
///
/// Feature screens must use the shared tokens/widgets instead of re-creating
/// them. Every exception is listed explicitly with its justification; adding
/// a new raw value to a feature screen fails this test.
class _Rule {
  const _Rule(this.name, this.pattern, this.fix, {this.allow = const {}});

  final String name;
  final RegExp pattern;
  final String fix;

  /// File path suffix -> justification.
  final Map<String, String> allow;
}

const _brand = 'features/launch/brand_widgets.dart';
const _login = 'features/login/login_screen.dart';

final _featureRules = <_Rule>[
  _Rule(
    'raw radius',
    RegExp(r'Radius\.circular\(\s*[0-9]'),
    'use AppRadii.*',
    allow: {_brand: 'launch brand art', _login: 'Google sign-in button'},
  ),
  _Rule(
    'raw font size',
    RegExp(r'fontSize:\s*[0-9]'),
    'use a Theme.textTheme role',
    allow: {_brand: 'launch brand art', _login: 'Google sign-in button'},
  ),
  _Rule(
    'literal font family',
    RegExp(r"fontFamily:\s*'"),
    'the theme applies Inter; use AppFonts.mono for monospace',
    allow: {_login: 'Google sign-in button'},
  ),
  _Rule(
    'hex colour literal',
    RegExp(r'\bColor\(0x'),
    'use a ColorScheme role, scheme.positive or an AppColors token',
    allow: {_brand: 'launch brand art', _login: 'Google sign-in button'},
  ),
  _Rule(
    'named Material colour',
    RegExp(r'\bColors\.(?!transparent\b|white\b|black\b)[a-z]\w*'),
    'use a ColorScheme role or scheme.positive',
  ),
  _Rule(
    'inline SnackBar',
    RegExp(r'(?<![A-Za-z_])SnackBar\('),
    'use showAppSnackBar',
  ),
  _Rule(
    'raw bottom sheet',
    RegExp(r'\bshowModalBottomSheet\b'),
    'use showAppSheet',
  ),
  _Rule(
    'raw grouped list',
    RegExp(r'\b(GlassGroupedSection|GlassListTile)\('),
    'use AppGroupedSection / AppGroupedTile',
  ),
  _Rule(
    'Material list tile',
    RegExp(r'(?<![A-Za-z_])(ListTile|SwitchListTile|CheckboxListTile)\('),
    'use PremiumRow / AppSwitchListTile / AppGroupedTile',
    allow: {
      'features/login/offline_mode_sheet.dart':
          'consent acknowledgement must stay a checkbox',
    },
  ),
  _Rule(
    'Material card',
    RegExp(r'(?<![A-Za-z_])Card\('),
    'use SectionCard or the canonical panel surface',
  ),
  _Rule(
    'Material switch',
    RegExp(r'(?<![A-Za-z_])Switch(\.adaptive)?\('),
    'use AppSwitchListTile / AppGroupedTile.toggle',
  ),
  _Rule(
    'Material app bar',
    RegExp(r'(?<![A-Za-z_])AppBar\('),
    'use RouteScaffold / AppScreen',
  ),
  _Rule(
    'raw page scaffold',
    RegExp(r'(?<![A-Za-z_])Scaffold\('),
    'use RouteScaffold (pushed routes) or AppScreen (shell tabs)',
    allow: {
      'features/main/main_shell.dart': 'owns the drawer and bottom island',
      'features/common/route_scaffold.dart': 'the canonical frame itself',
      _brand: 'launch/login/onboarding brand scaffold',
      _login: 'brand entry screen',
      'features/onboarding/onboarding_screen.dart': 'brand onboarding flow',
    },
  ),
  _Rule(
    'raw glass button',
    RegExp(r'\bGlassButton(\.custom)?\('),
    'use AppActionButton',
  ),
  _Rule(
    'brand panel outside brand screens',
    RegExp(r'\bBrandFrostedPanel\('),
    'BrandFrostedPanel is reserved for launch/login/onboarding',
    allow: {
      _brand: 'definition',
      _login: 'brand entry screen',
      'features/login/offline_mode_sheet.dart': 'shown from the login screen',
      'features/onboarding/onboarding_screen.dart': 'brand onboarding flow',
    },
  ),
];

final _globalRules = <_Rule>[
  _Rule(
    'withAlpha(int)',
    RegExp(r'\.withAlpha\('),
    'use withValues(alpha:) or withAlphaFactor',
    allow: {'design/tokens.dart': 'withAlphaFactor implementation'},
  ),
  _Rule(
    'plain icon glyph',
    RegExp(r'Icons\.(?![a-z_0-9]+_(?:outlined|rounded|sharp)\b)[a-z_0-9]+\b'),
    'use the _rounded (actions/status) or _outlined (content) variant',
  ),
];

List<File> _dartFiles(String dir) =>
    Directory(dir)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

String _rel(File f) => f.path.replaceAll('\\', '/').split('lib/src/').last;

List<String> _violations(List<File> files, List<_Rule> rules) {
  final out = <String>[];
  for (final file in files) {
    final rel = _rel(file);
    final lines = file.readAsLinesSync();
    for (final rule in rules) {
      if (rule.allow.keys.any(rel.endsWith)) continue;
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trimLeft();
        if (line.startsWith('//')) continue;
        // A justified one-off exception is marked in code, on the line or
        // the line above: `// ui-guard: allow <reason>`.
        if (lines[i].contains('ui-guard: allow') ||
            (i > 0 && lines[i - 1].contains('ui-guard: allow'))) {
          continue;
        }
        if (rule.pattern.hasMatch(lines[i])) {
          out.add('$rel:${i + 1} ${rule.name} -> ${rule.fix}');
        }
      }
    }
  }
  return out;
}

void main() {
  test('feature screens use canonical UI tokens and primitives', () {
    final violations = _violations(_dartFiles('lib/src/features'), [
      ..._featureRules,
    ]);
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('lib/src uses one alpha API and rounded/outlined icon variants', () {
    final violations = _violations(_dartFiles('lib/src'), _globalRules);
    expect(violations, isEmpty, reason: violations.join('\n'));
  });
}
