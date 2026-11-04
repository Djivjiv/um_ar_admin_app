import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';

/// The floor plan with a dot on the chosen node. Node x/y are image pixels,
/// so the dot needs the image's real size, read once it has loaded.
class EntranceNodePreview extends StatefulWidget {
  final String imageUrl;
  final double? x;
  final double? y;

  const EntranceNodePreview({
    super.key,
    required this.imageUrl,
    required this.x,
    required this.y,
  });

  @override
  State<EntranceNodePreview> createState() => _EntranceNodePreviewState();
}

class _EntranceNodePreviewState extends State<EntranceNodePreview> {
  static const _dot = 12.0;

  Size? _size;
  bool _failed = false;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  ImageProvider get _image => CachedNetworkImageProvider(widget.imageUrl);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(EntranceNodePreview old) {
    super.didUpdateWidget(old);
    if (old.imageUrl != widget.imageUrl) {
      _size = null;
      _failed = false;
      _resolve();
    }
  }

  void _resolve() {
    _stopListening();
    final stream = _image.resolve(createLocalImageConfiguration(context));
    final listener = ImageStreamListener(
      (info, _) {
        if (mounted) {
          setState(() => _size = Size(info.image.width.toDouble(),
              info.image.height.toDouble()));
        }
      },
      onError: (_, _) {
        if (mounted) setState(() => _failed = true);
      },
    );
    stream.addListener(listener);
    _stream = stream;
    _listener = listener;
  }

  void _stopListening() {
    final listener = _listener;
    if (listener != null) _stream?.removeListener(listener);
  }

  @override
  void dispose() {
    _stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return const Text('Floor plan preview unavailable.',
          style: TextStyle(fontSize: 11, color: AppColors.textSecondary));
    }
    final size = _size;
    if (size == null || size.height == 0) {
      return const SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final x = widget.x;
    final y = widget.y;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 180),
      child: AspectRatio(
        aspectRatio: size.width / size.height,
        child: LayoutBuilder(
          builder: (context, c) => Stack(
            children: [
              Positioned.fill(child: Image(image: _image, fit: BoxFit.fill)),
              if (x != null && y != null)
                Positioned(
                  left: x / size.width * c.maxWidth - _dot / 2,
                  top: y / size.height * c.maxHeight - _dot / 2,
                  child: Container(
                    width: _dot,
                    height: _dot,
                    decoration: BoxDecoration(
                      color: AppColors.errorRed,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
