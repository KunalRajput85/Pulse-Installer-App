import '../models/app_config.dart';
import '../models/models.dart';
import 'location_service.dart';

/// Outcome of a geofence check.
class GeofenceResult {
  final bool allowed;
  final GeoZone? matchedZone; // nearest active zone the point falls inside
  final GeoZone? nearestZone; // nearest active zone overall
  final double? distanceToNearest; // metres to the edge of nearest zone
  final String? blockReason;

  const GeofenceResult({
    required this.allowed,
    this.matchedZone,
    this.nearestZone,
    this.distanceToNearest,
    this.blockReason,
  });
}

/// Evaluates a position against the JSON-defined geofence zones.
///
/// Everything is driven by [GeoConfig]: the global on/off switch, the
/// enforcement mode, and each zone's own radius limit and active flag. When
/// enforcement is "block" and the installer is outside every active zone, the
/// result is not allowed (hard block).
class GeofenceService {
  GeofenceService._();

  static GeofenceResult evaluate(GeoConfig config, GpsReading reading) {
    // Geofencing disabled entirely, or set to a non-enforcing mode.
    if (!config.active || config.enforcement == 'off') {
      return const GeofenceResult(allowed: true);
    }

    final zones = config.activeZones;
    if (zones.isEmpty) {
      // No active zones configured => nothing to enforce against.
      return const GeofenceResult(allowed: true);
    }

    GeoZone? matched;
    GeoZone? nearest;
    double nearestEdgeDistance = double.infinity;

    for (final z in zones) {
      final radius = z.radiusMeters > 0 ? z.radiusMeters : config.defaultRadiusMeters;
      final d = LocationService.distanceBetween(
          reading.latitude, reading.longitude, z.lat, z.lng);
      final edge = d - radius; // negative => inside
      if (edge < nearestEdgeDistance) {
        nearestEdgeDistance = edge;
        nearest = z;
      }
      if (d <= radius && matched == null) {
        matched = z;
      }
    }

    if (matched != null) {
      return GeofenceResult(
        allowed: true,
        matchedZone: matched,
        nearestZone: nearest,
        distanceToNearest: nearestEdgeDistance,
      );
    }

    // Outside all active zones.
    final warnOnly = config.enforcement == 'warn';
    return GeofenceResult(
      allowed: warnOnly, // warn mode allows but flags; block mode denies
      nearestZone: nearest,
      distanceToNearest: nearestEdgeDistance,
      blockReason: nearest == null
          ? 'You are outside the assigned work area.'
          : 'You are ${nearestEdgeDistance.round()} m outside "${nearest.name}". '
              'Move inside the zone to continue.',
    );
  }
}
