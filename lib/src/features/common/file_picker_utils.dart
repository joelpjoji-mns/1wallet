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
  final bytes = file.bytes;
  if (bytes == null) {
    throw FormatException('Could not read ${file.name}.');
  }
  return decodePickedTextFile(
    name: file.name,
    bytes: bytes,
    allowedExtensions: allowedExtensions,
  );
}
