import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../../imports/picked_text_file.dart';

Future<PickedTextFile?> pickTextFile({
  required List<String> allowedExtensions,
  bool allowAnyFileType = false,
}) async {
  // On Android and mobile, FileType.custom with custom non-standard MIME
  // extensions like '.onewallet' causes Android's document picker to grey out
  // the files because Android has no registered MIME type for .onewallet.
  // Using FileType.any allows all files to be selectable.
  final hasCustomExtension = allowedExtensions.any(
    (ext) => ext.toLowerCase() == 'onewallet',
  );

  final files = (allowAnyFileType || hasCustomExtension)
      ? await _pickFilesWithFallback(
          primary: FileType.any,
          fallback: FileType.custom,
          allowedExtensions: allowedExtensions,
        )
      : await _pickFilesWithFallback(
          primary: FileType.custom,
          fallback: FileType.any,
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

Future<List<PlatformFile>> _pickFilesWithFallback({
  required FileType primary,
  required FileType fallback,
  required List<String> allowedExtensions,
}) async {
  try {
    return await FilePicker.pickFiles(
      type: primary,
      allowedExtensions: primary == FileType.custom ? allowedExtensions : null,
    );
  } catch (_) {
    return await FilePicker.pickFiles(
      type: fallback,
      allowedExtensions: fallback == FileType.custom ? allowedExtensions : null,
    );
  }
}
