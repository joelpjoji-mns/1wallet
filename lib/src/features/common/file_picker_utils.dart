import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../../imports/picked_text_file.dart';

Future<PickedTextFile?> pickTextFile({
  required List<String> allowedExtensions,
}) async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: allowedExtensions,
    withData: true,
  );
  if (result == null || result.files.isEmpty) return null;
  final file = result.files.single;

  Uint8List? bytes = file.bytes;
  if (bytes == null && file.path != null) {
    try {
      bytes = await File(file.path!).readAsBytes();
    } catch (_) {}
  }

  if (bytes == null) {
    throw FormatException('Could not read ${file.name}.');
  }
  return decodePickedTextFile(
    name: file.name,
    bytes: bytes,
    allowedExtensions: allowedExtensions,
  );
}
