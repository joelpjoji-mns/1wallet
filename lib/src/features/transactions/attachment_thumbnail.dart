import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../../data/ledger_models.dart';
import '../../design/tokens.dart';

class AttachmentThumbnail extends StatelessWidget {
  const AttachmentThumbnail({
    required this.attachment,
    this.width = 72,
    this.height = 72,
    this.onDelete,
    this.showDelete = false,
    super.key,
  });

  final TransactionAttachment attachment;
  final double width;
  final double height;
  final VoidCallback? onDelete;
  final bool showDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        GestureDetector(
          onTap: () => showAttachmentPreviewDialog(context, attachment),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.sm),
            child: Container(
              width: width,
              height: height,
              color: scheme.surfaceContainerHighest,
              child: _buildImageOrFallback(context),
            ),
          ),
        ),
        if (showDelete && onDelete != null)
          Positioned(
            top: 2,
            right: 2,
            child: GestureDetector(
              onTap: onDelete,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: scheme.surface.withValues(alpha: 0.86),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.16),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.close_rounded,
                  size: 14,
                  color: scheme.error,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildImageOrFallback(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final uri = attachment.uri;

    if (!kIsWeb && uri.isNotEmpty) {
      try {
        final file = File(uri);
        return Image.file(
          file,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallbackIcon(scheme),
        );
      } catch (_) {
        return _fallbackIcon(scheme);
      }
    }

    if (uri.startsWith('http://') || uri.startsWith('https://')) {
      return Image.network(
        uri,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallbackIcon(scheme),
      );
    }

    return _fallbackIcon(scheme);
  }

  Widget _fallbackIcon(ColorScheme scheme) {
    return Center(
      child: Icon(
        Icons.receipt_outlined,
        color: scheme.onSurfaceVariant,
        size: width * 0.4,
      ),
    );
  }
}

Future<void> showAttachmentPreviewDialog(
  BuildContext context,
  TransactionAttachment attachment,
) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final scheme = Theme.of(dialogContext).colorScheme;
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(AppSpacing.md),
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(AppRadii.lg),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ui-guard: allow modal dialog header
              AppBar(
                title: Text(
                  attachment.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(dialogContext).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                actions: [
                  if (!kIsWeb && attachment.uri.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.open_in_new_rounded),
                      tooltip: 'Open with external viewer',
                      onPressed: () => OpenFilex.open(attachment.uri),
                    ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(dialogContext).pop(),
                  ),
                ],
              ),
              Flexible(
                child: InteractiveViewer(
                  panEnabled: true,
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 500),
                    alignment: Alignment.center,
                    child: _buildFullImage(dialogContext, attachment),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        ),
      );
    },
  );
}

Widget _buildFullImage(BuildContext context, TransactionAttachment attachment) {
  final scheme = Theme.of(context).colorScheme;
  final uri = attachment.uri;

  if (!kIsWeb && uri.isNotEmpty) {
    try {
      final file = File(uri);
      return Image.file(
        file,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _previewFallback(scheme),
      );
    } catch (_) {
      return _previewFallback(scheme);
    }
  }

  if (uri.startsWith('http://') || uri.startsWith('https://')) {
    return Image.network(
      uri,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => _previewFallback(scheme),
    );
  }

  return _previewFallback(scheme);
}

Widget _previewFallback(ColorScheme scheme) {
  return Padding(
    padding: const EdgeInsets.all(AppSpacing.xl),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.broken_image_outlined,
          size: 48,
          color: scheme.onSurfaceVariant,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Image preview unavailable on this device.',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      ],
    ),
  );
}
