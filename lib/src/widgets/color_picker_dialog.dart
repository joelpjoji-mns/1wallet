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
      return AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: HueRingPicker(
            pickerColor: initialColor,
            onColorChanged: (color) {
              selectedColor = color;
            },
            enableAlpha: false,
            displayThumbColor: true,
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
}
