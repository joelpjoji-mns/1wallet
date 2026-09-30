import 'dart:convert';
import 'dart:typed_data';

class PickedTextFile {
  const PickedTextFile({required this.name, required this.text});

  final String name;
  final String text;
}

PickedTextFile decodePickedTextFile({
  required String name,
  required Uint8List bytes,
  required List<String> allowedExtensions,
}) {
  final normalizedName = name.trim().isEmpty ? 'selected file' : name.trim();
  if (bytes.isEmpty) {
    throw FormatException('$normalizedName is empty.');
  }

  String text;
  try {
    text = utf8.decode(bytes, allowMalformed: false);
    if (text.trim().isEmpty) {
      throw FormatException('$normalizedName does not contain readable text.');
    }
  } on FormatException catch (error) {
    if (error.message.contains(normalizedName)) rethrow;
    throw FormatException('$normalizedName is not valid UTF-8 text.');
  }

  final isAllowed = _hasAllowedExtension(normalizedName, allowedExtensions);
  final trimmed = text.trim();
  final isJsonArchive = trimmed.startsWith('{') && trimmed.endsWith('}');

  if (!isAllowed && !isJsonArchive) {
    throw FormatException(
      'Unsupported file type for $normalizedName. Allowed: ${allowedExtensions.join(', ')}.',
    );
  }

  return PickedTextFile(name: normalizedName, text: text);
}

bool _hasAllowedExtension(String name, List<String> allowedExtensions) {
  if (allowedExtensions.isEmpty) return true;
  final lowerName = name.toLowerCase();
  return allowedExtensions
      .map(
        (extension) => extension.toLowerCase().replaceFirst(RegExp(r'^\.'), ''),
      )
      .any((extension) => lowerName.endsWith('.$extension'));
}
