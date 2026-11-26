import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

Future<Color?> showAppColorPicker({
  required BuildContext context,
  required Color initialColor,
  String title = 'Pick a color',
}) async {
  Color selectedColor = initialColor;

  return showDialog<Color>(
    context: context,
    builder: (BuildContext context) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 400;
          final inset = compact ? 16.0 : 40.0;
          final contentInset = compact ? 16.0 : 24.0;
          final availableWidth =
              constraints.maxWidth - 2 * inset - 2 * contentInset;
          // HueRingPicker adds 15 pixels on each side of its ring.
          final pickerWidth = (availableWidth - 30).clamp(0.0, 250.0);
          return AlertDialog(
            insetPadding: EdgeInsets.symmetric(horizontal: inset, vertical: 24),
            contentPadding: EdgeInsets.fromLTRB(
              contentInset,
              16,
              contentInset,
              24,
            ),
            title: Text(title),
            content: SingleChildScrollView(
              child: HueRingPicker(
                pickerColor: selectedColor,
                portraitOnly: availableWidth < 400,
                colorPickerHeight: pickerWidth,
                onColorChanged: (color) {
                  selectedColor = color;
                },
              ),
            ),
            actions: <Widget>[
              TextButton(
                child: const Text('Cancel'),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
              FilledButton(
                child: const Text('Select'),
                onPressed: () {
                  Navigator.of(context).pop(selectedColor);
                },
              ),
            ],
          );
        },
      );
    },
  );
}
