import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const GeoSnapApp());
}

class GeoSnapApp extends StatelessWidget {
  const GeoSnapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SSW3401 Lab Task 1',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _imagePath;
  double? _latitude;
  double? _longitude;
  String _statusMessage = 'Ready to capture photo and GPS location.';
  bool _isLoading = false;

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    // Automatically load cached photo and GPS data when the app starts
    _loadCachedData();
  }

  // Load saved image path and GPS coordinates from SharedPreferences
  Future<void> _loadCachedData() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPath = prefs.getString('cached_image_path');
    final savedLat = prefs.getDouble('cached_lat');
    final savedLng = prefs.getDouble('cached_lng');

    setState(() {
      if (savedPath != null && File(savedPath).existsSync()) {
        _imagePath = savedPath;
      }
      _latitude = savedLat;
      _longitude = savedLng;
      if (_imagePath != null || _latitude != null) {
        _statusMessage = 'Loaded cached data from SharedPreferences.';
      }
    });
  }

  // Save image path and GPS coordinates locally to SharedPreferences
  Future<void> _saveToCache(String? path, double? lat, double? lng) async {
    final prefs = await SharedPreferences.getInstance();
    if (path != null) await prefs.setString('cached_image_path', path);
    if (lat != null) await prefs.setDouble('cached_lat', lat);
    if (lng != null) await prefs.setDouble('cached_lng', lng);
  }

  // Clear all cached data for testing purposes
  Future<void> _clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    setState(() {
      _imagePath = null;
      _latitude = null;
      _longitude = null;
      _statusMessage = 'Local cache cleared.';
    });
  }

  // Main workflow: Request permissions -> Fetch GPS -> Capture Photo -> Cache locally
  Future<void> _capturePhotoAndLocation() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Requesting permissions...';
    });

    try {
      // Step 1: Request Camera permission
      PermissionStatus cameraStatus = await Permission.camera.request();
      if (!cameraStatus.isGranted) {
        setState(() {
          _statusMessage = 'Camera permission denied. Cannot take photo.';
          _isLoading = false;
        });
        _showPermissionDialog('Camera');
        return;
      }

      // Step 2: Request Location permission
      PermissionStatus locationStatus = await Permission.locationWhenInUse.request();
      double? lat;
      double? lng;

      if (locationStatus.isGranted) {
        setState(() => _statusMessage = 'Fetching GPS coordinates...');
        try {
          // Fetch current GPS with an 8-second timeout to prevent UI freeze
          Position position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 8),
            ),
          );
          lat = position.latitude;
          lng = position.longitude;
        } catch (e) {
          // Fallback to last known position if offline or timed out
          Position? lastPos = await Geolocator.getLastKnownPosition();
          if (lastPos != null) {
            lat = lastPos.latitude;
            lng = lastPos.longitude;
          }
        }
      } else {
        // Gracefully handle denied location permission without crashing
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location permission denied. Photo will be saved without GPS.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }

      // Step 3: Open device camera to take a photo
      setState(() => _statusMessage = 'Opening camera...');
      final XFile? pickedFile = await _picker.pickImage(source: ImageSource.camera);

      if (pickedFile == null) {
        setState(() {
          _statusMessage = 'Photo capture cancelled.';
          _isLoading = false;
        });
        return;
      }

      // Step 4: Copy photo to permanent app directory so it persists after restart
      final appDir = await getApplicationDocumentsDirectory();
      final fileName = 'geo_photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final savedFile = await File(pickedFile.path).copy('${appDir.path}/$fileName');

      // Step 5: Save path and coordinates to SharedPreferences
      await _saveToCache(savedFile.path, lat, lng);

      setState(() {
        _imagePath = savedFile.path;
        _latitude = lat;
        _longitude = lng;
        _statusMessage = lat != null
            ? 'Saved photo & GPS to SharedPreferences!'
            : 'Saved photo (GPS unavailable or denied).';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Error occurred: $e';
        _isLoading = false;
      });
    }
  }

  // Show alert dialog guiding user to App Settings if permission is denied
  void _showPermissionDialog(String permissionName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$permissionName Permission Required'),
        content: Text('Please enable $permissionName permission in App Settings to use this feature.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GeoSnap - Lab Task 1'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        centerTitle: true,
      ),
      // SingleChildScrollView prevents render overflow errors on small screens
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Image display Container
            Container(
              height: 300,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.indigo.shade200, width: 2),
              ),
              clipBehavior: Clip.antiAlias,
              child: _imagePath != null && File(_imagePath!).existsSync()
                  ? Image.file(File(_imagePath!), fit: BoxFit.cover)
                  : const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.camera_alt_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 8),
                  Text('No photo captured yet', style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // GPS Coordinates display card using Container, Column, and Row
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.location_on, color: Colors.indigo),
                      SizedBox(width: 8),
                      Text(
                        'GPS Coordinates (Cached)',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Latitude:', style: TextStyle(fontWeight: FontWeight.w500)),
                      Text(_latitude != null ? _latitude!.toStringAsFixed(6) : 'N/A'),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Longitude:', style: TextStyle(fontWeight: FontWeight.w500)),
                      Text(_longitude != null ? _longitude!.toStringAsFixed(6) : 'N/A'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Status indicator bar
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  if (_isLoading)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    const Icon(Icons.info_outline, size: 18, color: Colors.indigo),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_statusMessage, style: const TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Action buttons Row
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _capturePhotoAndLocation,
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Capture & Tag'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: Colors.indigo,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 1,
                  child: OutlinedButton.icon(
                    onPressed: _isLoading ? null : _clearCache,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Clear'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      foregroundColor: Colors.red,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}