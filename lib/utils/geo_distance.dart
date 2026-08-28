import 'dart:math' as math;

import '../models/activity_event.dart';
import '../models/nfc_hunt_tag.dart';

/// Default mismatch threshold per ADR 007.
const double kNfcHuntLocationMismatchThresholdMeters = 50.0;

/// Returns great-circle distance in meters between two WGS84 points.
double haversineDistanceMeters({
  required double lat1,
  required double lon1,
  required double lat2,
  required double lon2,
}) {
  const earthRadiusMeters = 6371000.0;
  final dLat = _toRadians(lat2 - lat1);
  final dLon = _toRadians(lon2 - lon1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_toRadians(lat1)) *
          math.cos(_toRadians(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadiusMeters * c;
}

/// For a fixed tag with placement location and a scan with GPS, returns
/// haversine distance in meters. Returns null when comparison does not apply.
double? fixedTagScanMismatchMeters({
  required NfcHuntPlacement tagPlacement,
  required ActivityEventLocation? tagLocation,
  required ActivityEventLocation? scanLocation,
}) {
  if (tagPlacement != NfcHuntPlacement.fixed) return null;
  if (tagLocation == null || scanLocation == null) return null;

  return haversineDistanceMeters(
    lat1: tagLocation.latitude,
    lon1: tagLocation.longitude,
    lat2: scanLocation.latitude,
    lon2: scanLocation.longitude,
  );
}

/// True when [fixedTagScanMismatchMeters] exceeds [thresholdMeters].
bool isFixedTagScanMismatch({
  required NfcHuntPlacement tagPlacement,
  required ActivityEventLocation? tagLocation,
  required ActivityEventLocation? scanLocation,
  double thresholdMeters = kNfcHuntLocationMismatchThresholdMeters,
}) {
  final meters = fixedTagScanMismatchMeters(
    tagPlacement: tagPlacement,
    tagLocation: tagLocation,
    scanLocation: scanLocation,
  );
  if (meters == null) return false;
  return meters > thresholdMeters;
}

double _toRadians(double degrees) => degrees * (math.pi / 180.0);
