import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';

/// Result of a file pick from [ImageUpload].
class PickedImage {
  final String fileName;
  final Uint8List bytes;
  const PickedImage(this.fileName, this.bytes);
}

class ImageUpload extends StatefulWidget {
  final String label;
  final String? currentUrl;
  final ValueChanged<PickedImage> onPicked;
  final VoidCallback? onCleared;

  const ImageUpload({
    super.key,
    this.label = 'Image',
    this.currentUrl,
    required this.onPicked,
    this.onCleared,
  });

  @override
  State<ImageUpload> createState() => _ImageUploadState();
}

class _ImageUploadState extends State<ImageUpload> {
  PickedImage? _picked;
  bool _picking = false;

  Future<void> _pick() async {
    setState(() => _picking = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) return;
      final picked = PickedImage(file.name, bytes);
      setState(() => _picked = picked);
      widget.onPicked(picked);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasPreview = _picked != null ||
        (widget.currentUrl != null && widget.currentUrl!.isNotEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            widget.label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        InkWell(
          onTap: _picking ? null : _pick,
          borderRadius: BorderRadius.circular(10),
          child: DottedBorderBox(
            child: SizedBox(
              height: 160,
              width: double.infinity,
              child: _picking
                  ? const Center(child: CircularProgressIndicator())
                  : hasPreview
                      ? _preview()
                      : const _EmptyPrompt(),
            ),
          ),
        ),
        if (hasPreview)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () {
                setState(() => _picked = null);
                widget.onCleared?.call();
              },
              icon: const Icon(Icons.close, size: 16),
              label: const Text('Remove'),
            ),
          ),
      ],
    );
  }

  Widget _preview() {
    if (_picked != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(_picked!.bytes, fit: BoxFit.cover),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CachedNetworkImage(
        imageUrl: widget.currentUrl!,
        fit: BoxFit.cover,
        errorWidget: (_, _, _) => const _EmptyPrompt(),
      ),
    );
  }
}

class _EmptyPrompt extends StatelessWidget {
  const _EmptyPrompt();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_upload_outlined,
              color: AppColors.accentGold, size: 32),
          SizedBox(height: 8),
          Text(
            'Click to choose an image',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// A simple dashed-looking border box (painted as a gold rounded rect).
class DottedBorderBox extends StatelessWidget {
  final Widget child;
  const DottedBorderBox({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.accentGold.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.accentGold.withValues(alpha: 0.6),
          width: 1.5,
        ),
      ),
      child: child,
    );
  }
}
