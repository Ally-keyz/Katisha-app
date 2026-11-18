import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

/// Outcome of asking the OS for location access.
///
/// The UI never imports geolocator's own permission enum: keeping the mapping
/// here means a plugin upgrade only touches this file.
enum LocationAccess { granted, denied, deniedForever, serviceDisabled }

/// A GPS fix plus the nearest city/country we can infer without a network call.
///
/// Katisha only needs the traveller's country: it decides which currency and
/// mobile-money prices are shown on the payment step. Reverse geocoding over
/// the network would add latency and another permission surface for no benefit,
/// so the nearest city from a small built-in table is enough.
class DeviceLocation {
  final double latitude;
  final double longitude;
  final String? nearestCity;
  final String? countryIso2;
  final String? countryName;

  const DeviceLocation({
    required this.latitude,
    required this.longitude,
    this.nearestCity,
    this.countryIso2,
    this.countryName,
  });
}

class LocationService {
  const LocationService();

  /// Current access state without ever showing the OS permission prompt.
  Future<LocationAccess> checkAccess() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return LocationAccess.serviceDisabled;
      }
      return _mapPermission(await Geolocator.checkPermission());
    } catch (_) {
      return LocationAccess.denied;
    }
  }

  /// Checks the current permission without prompting, then asks the OS once if
  /// the user has not answered yet. Returns [LocationAccess.serviceDisabled]
  /// when GPS/location is switched off system-wide.
  Future<LocationAccess> ensureAccess() async {
    try {
      final current = await checkAccess();
      if (current != LocationAccess.denied) return current;
      return _mapPermission(await Geolocator.requestPermission());
    } catch (_) {
      return LocationAccess.denied;
    }
  }

  static LocationAccess _mapPermission(LocationPermission permission) {
    return switch (permission) {
      LocationPermission.always ||
      LocationPermission.whileInUse => LocationAccess.granted,
      LocationPermission.deniedForever => LocationAccess.deniedForever,
      _ => LocationAccess.denied,
    };
  }

  /// Current position, or null when permission is missing, the fix times out,
  /// or the platform reports an error. Falls back to the last known fix.
  Future<DeviceLocation?> currentLocation() async {
    try {
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.low,
            timeLimit: Duration(seconds: 8),
          ),
        );
      } catch (_) {
        position = await Geolocator.getLastKnownPosition();
      }
      if (position == null) return null;

      final nearest = _nearestCity(position.latitude, position.longitude);
      return DeviceLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        nearestCity: nearest?.city,
        countryIso2: nearest?.countryIso2,
        countryName: nearest?.countryName,
      );
    } catch (_) {
      return null;
    }
  }

  Future<bool> openAppSettings() => Geolocator.openAppSettings();

  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();

  static _CityPoint? _nearestCity(double latitude, double longitude) {
    _CityPoint? best;
    var bestDistance = double.infinity;
    for (final city in _cities) {
      final distance = _distanceKm(
        latitude,
        longitude,
        city.latitude,
        city.longitude,
      );
      if (distance < bestDistance) {
        bestDistance = distance;
        best = city;
      }
    }
    // Outside the region Katisha serves the nearest city is meaningless, so
    // let callers fall back to the device locale instead of guessing.
    return bestDistance <= 350 ? best : null;
  }

  /// Equirectangular approximation — accurate enough for picking the closest
  /// city and much cheaper than a full haversine.
  static double _distanceKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const kmPerDegree = 111.32;
    final meanLat = (lat1 + lat2) * math.pi / 360;
    final dLat = (lat2 - lat1) * kmPerDegree;
    final dLon = (lon2 - lon1) * kmPerDegree * math.cos(meanLat);
    return math.sqrt(dLat * dLat + dLon * dLon);
  }
}

class _CityPoint {
  final String city;
  final String countryIso2;
  final String countryName;
  final double latitude;
  final double longitude;

  const _CityPoint(
    this.city,
    this.countryIso2,
    this.countryName,
    this.latitude,
    this.longitude,
  );
}

/// Coarse city centres for the countries Katisha sells tickets in. The nearest
/// match is only used to pick a country/currency, never to navigate.
const _cities = <_CityPoint>[
  _CityPoint('Kigali', 'RW', 'Rwanda', -1.9441, 30.0619),
  _CityPoint('Huye', 'RW', 'Rwanda', -2.5967, 29.7394),
  _CityPoint('Musanze', 'RW', 'Rwanda', -1.4998, 29.6350),
  _CityPoint('Rubavu', 'RW', 'Rwanda', -1.6779, 29.2564),
  _CityPoint('Rusizi', 'RW', 'Rwanda', -2.4846, 29.0264),
  _CityPoint('Nyagatare', 'RW', 'Rwanda', -1.2939, 30.3271),
  _CityPoint('Kampala', 'UG', 'Uganda', 0.3476, 32.5825),
  _CityPoint('Mbarara', 'UG', 'Uganda', -0.6072, 30.6545),
  _CityPoint('Jinja', 'UG', 'Uganda', 0.4244, 33.2041),
  _CityPoint('Nairobi', 'KE', 'Kenya', -1.2921, 36.8219),
  _CityPoint('Mombasa', 'KE', 'Kenya', -4.0435, 39.6682),
  _CityPoint('Kisumu', 'KE', 'Kenya', -0.0917, 34.7680),
  _CityPoint('Nakuru', 'KE', 'Kenya', -0.3031, 36.0800),
  _CityPoint('Dar es Salaam', 'TZ', 'Tanzania', -6.7924, 39.2083),
  _CityPoint('Arusha', 'TZ', 'Tanzania', -3.3869, 36.6830),
  _CityPoint('Dodoma', 'TZ', 'Tanzania', -6.1630, 35.7516),
  _CityPoint('Mwanza', 'TZ', 'Tanzania', -2.5164, 32.9175),
  _CityPoint('Mbeya', 'TZ', 'Tanzania', -8.9094, 33.4608),
  _CityPoint('Bujumbura', 'BI', 'Burundi', -3.3614, 29.3599),
  _CityPoint('Juba', 'SS', 'South Sudan', 4.8594, 31.5713),
  _CityPoint('Lusaka', 'ZM', 'Zambia', -15.3875, 28.3228),
  _CityPoint('Harare', 'ZW', 'Zimbabwe', -17.8252, 31.0335),
  _CityPoint('Johannesburg', 'ZA', 'South Africa', -26.2041, 28.0473),
  _CityPoint('Lubumbashi', 'CD', 'DR Congo', -11.6876, 27.5026),
];

final locationServiceProvider = Provider<LocationService>(
  (ref) => const LocationService(),
);
