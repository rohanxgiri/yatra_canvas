import 'package:geolocator/geolocator.dart';

class DevicePosition {
  const DevicePosition({required this.latitude, required this.longitude});
  final double latitude;
  final double longitude;
}

class DeviceLocationService {
  Future<DevicePosition> getCurrentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const DeviceLocationException(
        'Location services are turned off. Enable them and try again.',
      );
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const DeviceLocationException(
        'Location permission was denied. Choose another start or try again.',
      );
    }
    if (permission == LocationPermission.deniedForever) {
      throw const DeviceLocationException(
        'Location permission is blocked. Enable it in app settings or choose another start.',
      );
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );
    return DevicePosition(
      latitude: position.latitude,
      longitude: position.longitude,
    );
  }
}

class DeviceLocationException implements Exception {
  const DeviceLocationException(this.message);
  final String message;
  @override
  String toString() => message;
}
