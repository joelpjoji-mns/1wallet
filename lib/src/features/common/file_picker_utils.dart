import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../../imports/picked_text_file.dart';

Future<PickedTextFile?> pickTextFile({
  required List<String> allowedExtensions,
}) async {
  final files = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: allowedExtensions,
  );
  if (files.isEmpty) return null;
  final file = files.single;

  Uint8List bytes;
  try {
    bytes = await file.readAsBytes();
  } catch (_) {
    if (file.path != null) {
      try {
        bytes = await File(file.path!).readAsBytes();
      } catch (_) {
        throw FormatException('Could not read ${file.name}.');
      }
    } else {
      throw FormatException('Could not read ${file.name}.');
    }
  }

  return decodePickedTextFile(
    name: file.name,
    bytes: bytes,
    allowedExtensions: allowedExtensions,
  );
}
