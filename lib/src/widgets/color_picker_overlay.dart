import 'package:flutter/material.dart';
import '../design/tokens.dart';

/// Shows a color picker dialog for custom theme accent.
///
/// Returns the selected hex color string (e.g. '#FF5722') or `null` if dismissed.
Future<String?> showColorPickerDialog({
  required BuildContext context,
  String initialColor = '#315DA8',
  String title = 'Custom accent',
}) {
  return showDialog<String>(
    context: context,
    builder: (context) =>
        _ColorPickerDialog(initialColor: initialColor, title: title),
  );
}

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({required this.initialColor, required this.title});

  final String initialColor;
  final String title;

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late double _hue;
  late double _saturation;
  late double _lightness;
  late Color _color;

  static const _presetColors = [
    '#315DA8', // 1wallet blue
    '#1976D2', // blue
    '#0097A7', // teal
    '#388E3C', // green
    '#689F38', // lime
    '#F57C00', // orange
    '#E64A19', // deep orange
    '#D32F2F', // red
    '#C2185B', // pink
    '#7B1FA2', // purple
    '#512DA8', // deep purple
    '#303F9F', // indigo
    '#455A64', // blue grey
    '#5D4037', // brown
    '#616161', // grey
  ];

  @override
  void initState() {
    super.initState();
    _color = _parseHex(widget.initialColor);
    final hsl = HSLColor.fromColor(_color);
    _hue = hsl.hue;
    _saturation = hsl.saturation;
    _lightness = hsl.lightness;
  }

  Color _parseHex(String hex) {
    final cleaned = hex.replaceAll('#', '');
    if (cleaned.length != 6) return const Color(0xFFFA233B);
    return Color(int.parse(cleaned, radix: 16) | 0xFF000000);
  }

  String _toHex(Color color) {
    return '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
  }

  void _updateFromHsl() {
    setState(() {
      _color = HSLColor.fromAHSL(1.0, _hue, _saturation, _lightness).toColor();
    });
  }

  void _setPreset(String hex) {
    final color = _parseHex(hex);
    final hsl = HSLColor.fromColor(color);
    setState(() {
      _hue = hsl.hue;
      _saturation = hsl.saturation;
      _lightness = hsl.lightness;
      _color = color;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Color preview
            Container(
              height: 64,
              decoration: BoxDecoration(
                color: _color,
                borderRadius: BorderRadius.circular(AppRadii.lg),
                boxShadow: [
                  BoxShadow(
                    color: _color.withAlpha(80),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                _toHex(_color),
                style: TextStyle(
                  color: _lightness > 0.5 ? Colors.black87 : Colors.white,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'RobotoMono',
                  letterSpacing: 1.2,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // Hue slider
            _SliderRow(
              label: 'Hue',
              value: _hue,
              max: 360,
              activeColor: _color,
              onChanged: (value) {
                _hue = value;
                _updateFromHsl();
              },
            ),
            const SizedBox(height: AppSpacing.sm),

            // Saturation slider
            _SliderRow(
              label: 'Saturation',
              value: _saturation,
              max: 1,
              activeColor: _color,
              onChanged: (value) {
                _saturation = value;
                _updateFromHsl();
              },
            ),
            const SizedBox(height: AppSpacing.sm),

            // Lightness slider
            _SliderRow(
              label: 'Lightness',
              value: _lightness,
              max: 1,
              activeColor: _color,
              onChanged: (value) {
                _lightness = value;
                _updateFromHsl();
              },
            ),
            const SizedBox(height: AppSpacing.lg),

            // Preset grid
            Text(
              'Presets',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final hex in _presetColors)
                  GestureDetector(
                    onTap: () => _setPreset(hex),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: _parseHex(hex),
                        shape: BoxShape.circle,
                        border:
                            _toHex(_color).toUpperCase() == hex.toUpperCase()
                            ? Border.all(
                                color: theme.colorScheme.onSurface,
                                width: 2.5,
                              )
                            : null,
                      ),
                      child: _toHex(_color).toUpperCase() == hex.toUpperCase()
                          ? Icon(
                              Icons.check,
                              size: 16,
                              color:
                                  HSLColor.fromColor(_parseHex(hex)).lightness >
                                      0.5
                                  ? Colors.black87
                                  : Colors.white,
                            )
                          : null,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_toHex(_color)),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.max,
    required this.activeColor,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double max;
  final Color activeColor;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: activeColor,
              thumbColor: activeColor,
              overlayColor: activeColor.withAlpha(30),
              inactiveTrackColor: activeColor.withAlpha(40),
              trackHeight: 4,
            ),
            child: Slider(value: value, min: 0, max: max, onChanged: onChanged),
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            max == 1 ? '${(value * 100).round()}%' : '${value.round()}°',
            textAlign: TextAlign.end,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'RobotoMono',
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
