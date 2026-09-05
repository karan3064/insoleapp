import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../models/track_point.dart';
import '../theme/app_colors.dart';

/// Draws a session's GPS path on an OpenStreetMap tile background.
///
/// Uses `flutter_map` + OSM's public tile server instead of Google Maps --
/// no API key, no Google Cloud billing account required. OSM's usage
/// policy (https://operations.osmfoundation.org/policies/tiles/) is meant
/// for exactly this kind of light, non-commercial use; if this app ever
/// sees heavy traffic, switch `urlTemplate` to a paid tile provider
/// (MapTiler, Mapbox, etc.) instead of hammering the free shared server.
class GpsPathMap extends StatelessWidget {
  final List<TrackPoint> path;
  final double height;

  const GpsPathMap({super.key, required this.path, this.height = 220});

  @override
  Widget build(BuildContext context) {
    if (path.isEmpty) return const SizedBox.shrink();

    final points = path.map((pt) => ll.LatLng(pt.latitude, pt.longitude)).toList();

    return SizedBox(
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: FlutterMap(
          options: MapOptions(
            initialCenter: points.first,
            initialZoom: 16,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.solesync.solesync',
            ),
            PolylineLayer(
              polylines: [
                Polyline(points: points, strokeWidth: 4, color: AppColors.primary),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
