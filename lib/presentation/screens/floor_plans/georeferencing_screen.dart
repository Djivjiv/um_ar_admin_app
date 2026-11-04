import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/config/maptiler_config.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/ui_helpers.dart';
import '../../../data/repositories/floor_plan_repository.dart';
import '../../../domain/models/building_model.dart';
import '../../../domain/models/floor_plan_model.dart';
import '../../widgets/maptiler_key_notice.dart';

const _cMaroon = Color(0xFF7B1C1C);
const _cGold = Color(0xFFC9972C);
const _cCharcoal = Color(0xFF1A1A1A);

const _mtKey = MapTilerConfig.apiKey;
const _streetsUrl =
    'https://api.maptiler.com/maps/streets-v2/{z}/{x}/{y}.png?key=$_mtKey';
const _umOverlayUrl =
    'https://api.maptiler.com/tiles/019fff21-f053-72a0-838d-683bbccd7aa7/'
    '{z}/{x}/{y}.webp?key=$_mtKey';
const _pkg = 'com.um.ar_navigation';
const _campusCenter = LatLng(7.0673125, 125.5951125);
const _nudgeStep = 0.00005; // degrees per nudge-button tap

/// Lets an admin drag/rotate/scale a floor plan image over the real map so it
/// lines up with the building footprint, then saves the four corner GPS
/// coordinates to `building_floors` for indoor↔outdoor navigation.
class GeoreferencingScreen extends StatefulWidget {
  final BuildingModel building;
  final int floorNumber;
  final String floorLabel;

  /// The existing `building_floors` row being georeferenced. Its image is
  /// already in Supabase Storage (uploaded from the Floor Plans screen).
  final FloorPlanModel? existingFloorPlan;

  const GeoreferencingScreen({
    super.key,
    required this.building,
    required this.floorNumber,
    required this.floorLabel,
    this.existingFloorPlan,
  });

  @override
  State<GeoreferencingScreen> createState() => _GeoreferencingScreenState();
}

class _GeoreferencingScreenState extends State<GeoreferencingScreen> {
  final _repo = FloorPlanRepository();
  final _mapController = MapController();

  late LatLng _overlayCenter;
  late double _overlayLatSpan; // degrees
  late double _overlayLngSpan; // degrees
  late double _baseLatSpan; // span at _scaleFactor == 1.0
  late double _baseLngSpan;
  double _rotationAngle = 0.0; // degrees, clockwise
  double _opacity = 0.7;
  double _scaleFactor = 1.0;
  bool _saving = false;

  bool get _hasImage =>
      (widget.existingFloorPlan?.imageUrl ?? '').isNotEmpty;

  @override
  void initState() {
    super.initState();
    final efp = widget.existingFloorPlan;

    if (efp?.centerLat != null && efp?.centerLng != null) {
      _overlayCenter = LatLng(efp!.centerLat!, efp.centerLng!);
    } else if (widget.building.lat != null && widget.building.lng != null) {
      _overlayCenter = LatLng(widget.building.lat!, widget.building.lng!);
    } else {
      _overlayCenter = _campusCenter;
    }

    _scaleFactor = efp?.scaleFactor ?? 1.0;
    _rotationAngle = efp?.rotationAngle ?? 0.0;

    if (efp?.nwLat != null &&
        efp?.swLat != null &&
        efp?.nwLng != null &&
        efp?.neLng != null) {
      // Already georeferenced — the saved spans already encode the correct
      // aspect ratio for this image, so keep them as-is.
      final savedLatSpan = (efp!.nwLat! - efp.swLat!).abs();
      final savedLngSpan = (efp.neLng! - efp.nwLng!).abs();
      final factor = _scaleFactor == 0 ? 1.0 : _scaleFactor;
      _baseLatSpan = savedLatSpan / factor;
      _baseLngSpan = savedLngSpan / factor;
    } else {
      // Brand new plan — start with a placeholder span, then correct it
      // below once the image's real pixel size is known so it isn't
      // stretched to fit an arbitrary box.
      _baseLatSpan = 0.0005;
      _baseLngSpan = 0.0008;
      if (_hasImage) _resolveAspectRatio();
    }
    _overlayLatSpan = _baseLatSpan * _scaleFactor;
    _overlayLngSpan = _baseLngSpan * _scaleFactor;
  }

  /// Reads the floor plan image's real pixel dimensions and recomputes the
  /// base lat/lng spans so the overlay keeps the image's aspect ratio
  /// instead of stretching it to a hardcoded box.
  void _resolveAspectRatio() {
    final stream = _imageProvider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        stream.removeListener(listener);
        final imageWidth = info.image.width.toDouble();
        final imageHeight = info.image.height.toDouble();
        if (imageWidth <= 0 || imageHeight <= 0 || !mounted) return;
        final aspectRatio = imageWidth / imageHeight;

        // Base the width on a reasonable building size, derive height from
        // the image's real aspect ratio (÷1.5 to account for the lat/lng
        // degree ratio at this latitude) so the overlay is never stretched.
        const baseLngSpan = 0.0008;
        final baseLatSpan = baseLngSpan / aspectRatio / 1.5;

        setState(() {
          _baseLngSpan = baseLngSpan;
          _baseLatSpan = baseLatSpan;
          _overlayLngSpan = _baseLngSpan * _scaleFactor;
          _overlayLatSpan = _baseLatSpan * _scaleFactor;
        });
      },
      onError: (error, stack) => stream.removeListener(listener),
    );
    stream.addListener(listener);
  }

  ImageProvider get _imageProvider =>
      CachedNetworkImageProvider(widget.existingFloorPlan!.imageUrl!);

  // --- overlay geometry ----------------------------------------------

  LatLng get _nw => LatLng(_overlayCenter.latitude + _overlayLatSpan / 2,
      _overlayCenter.longitude - _overlayLngSpan / 2);
  LatLng get _sw => LatLng(_overlayCenter.latitude - _overlayLatSpan / 2,
      _overlayCenter.longitude - _overlayLngSpan / 2);
  LatLng get _se => LatLng(_overlayCenter.latitude - _overlayLatSpan / 2,
      _overlayCenter.longitude + _overlayLngSpan / 2);

  LatLngBounds get _overlayBounds => LatLngBounds(_nw, _se);

  /// Rotates [p] clockwise around [_overlayCenter] by [_rotationAngle]
  /// degrees. Longitude is scaled by cos(latitude) so the rotation looks
  /// correct on screen despite degrees-of-longitude shrinking near the poles.
  LatLng _rotated(LatLng p) {
    if (_rotationAngle == 0) return p;
    final rad = _rotationAngle * (math.pi / 180.0);
    final cosLat = math.cos(_overlayCenter.latitude * math.pi / 180.0);
    final safeCosLat = cosLat.abs() < 1e-9 ? 1e-9 : cosLat;
    final dx = (p.longitude - _overlayCenter.longitude) * safeCosLat;
    final dy = p.latitude - _overlayCenter.latitude;
    final cosA = math.cos(rad);
    final sinA = math.sin(rad);
    final rx = dx * cosA + dy * sinA;
    final ry = -dx * sinA + dy * cosA;
    return LatLng(
        _overlayCenter.latitude + ry, _overlayCenter.longitude + rx / safeCosLat);
  }

  // --- tile layers -----------------------------------------------------

  // Fixed UM Campus Map tiles — no layer switching.
  List<Widget> _tileLayers() {
    if (!MapTilerConfig.isConfigured) return const [];
    return [
      TileLayer(
        urlTemplate: _streetsUrl,
        userAgentPackageName: _pkg,
        errorTileCallback: (tile, error, stack) {},
      ),
      TileLayer(
        urlTemplate: _umOverlayUrl,
        userAgentPackageName: _pkg,
        errorTileCallback: (tile, error, stack) {},
      ),
    ];
  }

  // --- save --------------------------------------------------------------

  Future<void> _save() async {
    if (!_hasImage) {
      context.showError('No floor plan image to save.');
      return;
    }
    setState(() => _saving = true);
    try {
      final imageUrl = widget.existingFloorPlan?.imageUrl;
      final bounds = _overlayBounds;
      final model = FloorPlanModel(
        id: widget.existingFloorPlan?.id,
        buildingId: widget.building.id,
        floorNumber: widget.floorNumber,
        floorName: widget.floorLabel,
        imageUrl: imageUrl,
        // Null (not calibrated) is left out of the save, never guessed.
        metersPerPixel: widget.existingFloorPlan?.metersPerPixel,
        nwLat: bounds.north,
        nwLng: bounds.west,
        neLat: bounds.north,
        neLng: bounds.east,
        swLat: bounds.south,
        swLng: bounds.west,
        seLat: bounds.south,
        seLng: bounds.east,
        centerLat: _overlayCenter.latitude,
        centerLng: _overlayCenter.longitude,
        rotationAngle: _rotationAngle,
        scaleFactor: _scaleFactor,
        isGeoreferenced: true,
        isActive: true,
      );

      if (widget.existingFloorPlan?.id != null) {
        await _repo.update(model);
      } else {
        await _repo.create(model);
      }

      if (!mounted) return;
      context.showSuccess('Floor plan saved and georeferenced successfully!');
      context.go('/floor-plans');
    } catch (e) {
      if (mounted) context.showError(e, onRetry: _save);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // --- nudge / reset -------------------------------------------------

  void _move(double lngDelta, double latDelta) {
    setState(() {
      _overlayCenter = LatLng(
        _overlayCenter.latitude + latDelta,
        _overlayCenter.longitude + lngDelta,
      );
    });
  }

  void _resetPosition() {
    setState(() {
      final efp = widget.existingFloorPlan;
      if (efp?.centerLat != null && efp?.centerLng != null) {
        _overlayCenter = LatLng(efp!.centerLat!, efp.centerLng!);
      } else if (widget.building.lat != null && widget.building.lng != null) {
        _overlayCenter = LatLng(widget.building.lat!, widget.building.lng!);
      } else {
        _overlayCenter = _campusCenter;
      }
      _rotationAngle = 0.0;
      _scaleFactor = 1.0;
      _overlayLatSpan = _baseLatSpan;
      _overlayLngSpan = _baseLngSpan;
      _opacity = 0.7;
    });
  }

  // --- build ---------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _topBar(),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: _map()),
                const Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: MapTilerKeyNotice(),
                ),
                if (!_hasImage)
                  Positioned.fill(
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: 0.05),
                      child: const Center(
                        child: Text('No floor plan image available',
                            style: TextStyle(color: AppColors.textSecondary)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          _controlPanel(),
        ],
      ),
    );
  }

  Widget _topBar() {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: _cCharcoal),
            onPressed: () => context.go('/floor-plans'),
          ),
          Expanded(
            child: Text(
              'Georeference — ${widget.building.name} Floor ${widget.floorNumber}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: _cCharcoal),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: (_saving || !_hasImage) ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: _cMaroon,
              foregroundColor: _cGold,
            ),
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: _cGold),
                  )
                : const Text('Save Floor Plan'),
          ),
        ],
      ),
    );
  }

  Widget _map() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _overlayCenter,
        initialZoom: 18.0,
        minZoom: 15.0,
        maxZoom: 20.0,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        ..._tileLayers(),
        if (_hasImage)
          OverlayImageLayer(
            overlayImages: [
              RotatedOverlayImage(
                topLeftCorner: _rotated(_nw),
                bottomLeftCorner: _rotated(_sw),
                bottomRightCorner: _rotated(_se),
                opacity: _opacity,
                imageProvider: _imageProvider,
              ),
            ],
          ),
        MarkerLayer(markers: [
          // Campus-center reference point, for orientation only.
          Marker(
            point: _campusCenter,
            width: 14,
            height: 14,
            alignment: Alignment.center,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.infoBlue.withValues(alpha: 0.5),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
            ),
          ),
          // Overlay-center handle.
          Marker(
            point: _overlayCenter,
            width: 16,
            height: 16,
            alignment: Alignment.center,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _cGold,
                border: Border.all(color: _cMaroon, width: 2),
              ),
            ),
          ),
        ]),
      ],
    );
  }

  // --- control panel ---------------------------------------------------

  Widget _controlPanel() {
    return Container(
      height: 200,
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Color(0x1A000000), blurRadius: 8, offset: Offset(0, -2)),
        ],
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: 40, child: _opacityRow()),
            const SizedBox(height: 4),
            SizedBox(height: 40, child: _rotationRow()),
            const SizedBox(height: 4),
            SizedBox(height: 40, child: _scaleRow()),
            const SizedBox(height: 4),
            SizedBox(height: 36, child: _nudgeRow()),
            const SizedBox(height: 4),
            SizedBox(height: 24, child: _hintText()),
          ],
        ),
      ),
    );
  }

  /// Shrinks the ambient tap-target/track so a Slider fits a compact row.
  Widget _compactSlider({
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Theme(
      data: Theme.of(context).copyWith(
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 3,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          overlayShape: SliderComponentShape.noOverlay,
        ),
        child: Slider(
          value: value,
          min: min,
          max: max,
          activeColor: _cGold,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _opacityRow() {
    return Row(
      children: [
        const Icon(Icons.opacity, size: 18, color: _cMaroon),
        const SizedBox(width: 8),
        const Text('Opacity',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        Expanded(
          child: _compactSlider(
            value: _opacity,
            min: 0.1,
            max: 1.0,
            onChanged: (v) => setState(() => _opacity = v),
          ),
        ),
        SizedBox(
          width: 40,
          child: Text('${(_opacity * 100).round()}%',
              textAlign: TextAlign.right,
              style: const TextStyle(
                  color: _cMaroon, fontWeight: FontWeight.bold, fontSize: 12)),
        ),
      ],
    );
  }

  Widget _rotationRow() {
    return Row(
      children: [
        const Icon(Icons.rotate_right, size: 18, color: _cMaroon),
        const SizedBox(width: 8),
        const Text('Rotation',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        Expanded(
          child: _compactSlider(
            value: _rotationAngle,
            min: -180,
            max: 180,
            onChanged: (v) => setState(() => _rotationAngle = v),
          ),
        ),
        SizedBox(
          width: 48,
          child: Text('${_rotationAngle.toStringAsFixed(1)}°',
              textAlign: TextAlign.right,
              style: const TextStyle(
                  color: _cMaroon, fontWeight: FontWeight.bold, fontSize: 12)),
        ),
      ],
    );
  }

  Widget _scaleRow() {
    return Row(
      children: [
        const Icon(Icons.zoom_out_map, size: 18, color: _cMaroon),
        const SizedBox(width: 8),
        const Text('Scale',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        Expanded(
          child: _compactSlider(
            value: _scaleFactor,
            min: 0.3,
            max: 3.0,
            onChanged: (v) {
              setState(() {
                _scaleFactor = v;
                // Both spans scale by the same factor, so the image's
                // aspect ratio is preserved at every scale.
                _overlayLatSpan = _baseLatSpan * v;
                _overlayLngSpan = _baseLngSpan * v;
              });
            },
          ),
        ),
        SizedBox(
          width: 40,
          child: Text('${_scaleFactor.toStringAsFixed(1)}x',
              textAlign: TextAlign.right,
              style: const TextStyle(
                  color: _cMaroon, fontWeight: FontWeight.bold, fontSize: 12)),
        ),
      ],
    );
  }

  Widget _nudgeRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _nudgeButton(Icons.arrow_back, () => _move(-_nudgeStep, 0)),
        const SizedBox(width: 6),
        _nudgeButton(Icons.arrow_upward, () => _move(0, _nudgeStep)),
        const SizedBox(width: 6),
        _nudgeButton(Icons.arrow_downward, () => _move(0, -_nudgeStep)),
        const SizedBox(width: 6),
        _nudgeButton(Icons.arrow_forward, () => _move(_nudgeStep, 0)),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: _resetPosition,
          icon: const Icon(Icons.refresh, size: 14),
          label: const Text('Reset', style: TextStyle(fontSize: 12)),
          style: OutlinedButton.styleFrom(
            foregroundColor: _cMaroon,
            side: const BorderSide(color: _cMaroon),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ],
    );
  }

  Widget _nudgeButton(IconData icon, VoidCallback onPressed) {
    return SizedBox(
      width: 32,
      height: 32,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: _cMaroon,
          side: const BorderSide(color: _cMaroon),
          padding: EdgeInsets.zero,
          minimumSize: const Size(32, 32),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Icon(icon, size: 14),
      ),
    );
  }

  Widget _hintText() {
    return const Text(
      'Use nudge buttons for fine-tuning against the UM Campus Map.',
      style: TextStyle(
          fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic),
      textAlign: TextAlign.center,
      overflow: TextOverflow.ellipsis,
    );
  }
}

