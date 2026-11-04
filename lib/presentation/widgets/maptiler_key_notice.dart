import 'package:flutter/material.dart';

import '../../core/config/maptiler_config.dart';
import 'error_banner.dart';

/// Explains blank MapTiler tiles over a map. Shows nothing when the key is
/// set.
class MapTilerKeyNotice extends StatelessWidget {
  const MapTilerKeyNotice({super.key});

  @override
  Widget build(BuildContext context) {
    if (MapTilerConfig.isConfigured) return const SizedBox.shrink();
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: const ErrorBanner(
        message: MapTilerConfig.missingKeyMessage,
        margin: EdgeInsets.zero,
      ),
    );
  }
}
