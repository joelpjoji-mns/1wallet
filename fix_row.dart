import 'dart:io';

void main() {
  var file = File('lib/src/features/transactions/transaction_row.dart');
  var content = file.readAsStringSync();
  content = content.replaceAll(
    'return RepaintBoundary(\n      child: Container(\n        clipBehavior: Clip.antiAlias,\n        decoration: BoxDecoration(\n          color: scheme.surfaceContainerLow,\n          borderRadius: BorderRadius.circular(AppRadii.md),\n          border: Border.all(color: scheme.outlineVariant.withAlpha(140)),\n        ),\n        child: content,\n      ),\n    );',
    '''    if (glass) return content;
    return RepaintBoundary(
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: scheme.outlineVariant.withAlpha(140)),
        ),
        child: content,
      ),
    );'''
  );
  file.writeAsStringSync(content);
}
