import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:latlong2/latlong.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/services/location_service.dart';

/// The map tiles behind the geo-tag preview and the pin picker.
///
/// OpenStreetMap's standard layer: free, with no API key and no billing
/// account, which the Spark-plan project and the no-secrets rule both
/// need. Its tile policy asks two things of an app, and both are met — it
/// identifies itself (the User-Agent names the app) and it shows
/// attribution on every map ([OsmAttribution]).
///
/// A provider so widget tests can put an empty layer in its place and
/// never reach the network.
final mapTileLayerProvider = Provider<Widget>(
  (ref) => TileLayer(
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    userAgentPackageName: 'com.dorsu.gsuhub',
  ),
);

/// "© OpenStreetMap contributors", as the tile policy requires.
///
/// Drawn here rather than with flutter_map's own attribution widget, which
/// adds a "flutter_map |" prefix at body size — more than a 160px preview
/// has room for.
class OsmAttribution extends StatelessWidget {
  const OsmAttribution({super.key});

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.bottomRight,
    child: Container(
      color: const Color(0xCCFFFFFF),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      child: const Text(
        '© OpenStreetMap contributors',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 10, color: Colors.black87),
      ),
    ),
  );
}

LatLng _latLngOf(GeoCoordinates point) =>
    LatLng(point.latitude, point.longitude);

/// The design's map pin (`169:770`), placed so its tip — not its middle —
/// sits on the point it marks.
class _CenterPin extends StatelessWidget {
  const _CenterPin();

  static const double _height = 30;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Center(
      child: Transform.translate(
        offset: const Offset(0, -_height / 2),
        child: SvgPicture.asset(
          'assets/icons/map_pin.svg',
          width: 24,
          height: _height,
          semanticsLabel: 'Attached location',
        ),
      ),
    ),
  );
}

/// The location card's map (Figma `169:766`): the geo-tag at street
/// level, not interactive — tapping it opens the pin picker instead.
class GeoTagMapPreview extends ConsumerWidget {
  const GeoTagMapPreview({required this.point, super.key, this.onTap});

  final GeoCoordinates point;
  final VoidCallback? onTap;

  static const double height = 160;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
    height: height,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.borderStrong),
      boxShadow: const [
        BoxShadow(
          color: Color(0x1A000000),
          offset: Offset(0, 4),
          blurRadius: 6,
          spreadRadius: -1,
        ),
        BoxShadow(
          color: Color(0x1A000000),
          offset: Offset(0, 2),
          blurRadius: 4,
          spreadRadius: -2,
        ),
      ],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(15),
      child: Stack(
        fit: StackFit.expand,
        children: [
          FlutterMap(
            // Rebuilt at the new point whenever the geo-tag moves; the
            // preview is not the place to pan.
            key: ValueKey(point),
            options: MapOptions(
              initialCenter: _latLngOf(point),
              initialZoom: 17,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.none,
              ),
              onTap: onTap == null ? null : (_, _) => onTap!(),
            ),
            children: [ref.watch(mapTileLayerProvider), const OsmAttribution()],
          ),
          const IgnorePointer(child: ColoredBox(color: AppColors.mapWash)),
          const _CenterPin(),
        ],
      ),
    ),
  );
}

/// The same frame while the device is still finding its position.
class GeoTagLocating extends StatelessWidget {
  const GeoTagLocating({super.key});

  @override
  Widget build(BuildContext context) => Container(
    height: GeoTagMapPreview.height,
    decoration: BoxDecoration(
      color: AppColors.dropZoneFill,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.borderStrong),
    ),
    child: const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          SizedBox(height: 12),
          Text('Getting your location…'),
        ],
      ),
    ),
  );
}

/// Full-screen map for placing the geo-tag by hand — the design's "Tap to
/// adjust location on map" (`169:778`). The design has no frame for this
/// screen, so it is plain Material, and flagged as such: the pin stays in
/// the middle and the map moves under it.
class MapPinPickerScreen extends ConsumerStatefulWidget {
  const MapPinPickerScreen({required this.start, super.key});

  final GeoCoordinates start;

  @override
  ConsumerState<MapPinPickerScreen> createState() => _MapPinPickerScreenState();
}

class _MapPinPickerScreenState extends ConsumerState<MapPinPickerScreen> {
  late LatLng _center = _latLngOf(widget.start);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Adjust location')),
    body: Stack(
      children: [
        FlutterMap(
          options: MapOptions(
            initialCenter: _center,
            initialZoom: 18,
            maxZoom: 19,
            onPositionChanged: (camera, _) => _center = camera.center,
          ),
          children: [ref.watch(mapTileLayerProvider), const OsmAttribution()],
        ),
        const _CenterPin(),
      ],
    ),
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Move the map until the pin sits on the damage.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(
                GeoCoordinates(
                  latitude: _center.latitude,
                  longitude: _center.longitude,
                ),
              ),
              child: const Text('Use this location'),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Opens [MapPinPickerScreen] and returns the chosen point, or null when
/// the requestor backs out. A provider so tests can answer without a map.
typedef MapPinLauncher = Future<GeoCoordinates?> Function(
  BuildContext context,
  GeoCoordinates start,
);

final mapPinLauncherProvider = Provider<MapPinLauncher>(
  (ref) =>
      (context, start) => Navigator.of(context).push<GeoCoordinates>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => MapPinPickerScreen(start: start),
        ),
      ),
);
