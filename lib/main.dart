import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Camera Images',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
      ),
      home: const MyHomePage(title: 'Camera Folder Images'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final List<File> _cameraImages = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCameraImages();
  }

  Future<void> _loadCameraImages() async {
    // Request storage permissions.
    // On modern Android versions prefer MANAGE_EXTERNAL_STORAGE (all-files access),
    // fall back to legacy storage permission where appropriate, and guide the
    // user to app settings if the permission is permanently denied.
    PermissionStatus status;
    if (Platform.isAndroid) {
      // Try MANAGE_EXTERNAL_STORAGE first (Android 11+).
      PermissionStatus manageStatus = await Permission.manageExternalStorage.status;
      if (!manageStatus.isGranted) {
        manageStatus = await Permission.manageExternalStorage.request();
      }

      if (manageStatus.isGranted) {
        status = manageStatus;
      } else {
        // Fallback to legacy storage permission for older devices.
        status = await Permission.storage.request();
      }

      // If permanently denied, prompt user to open app settings.
      if (!status.isGranted && status.isPermanentlyDenied && mounted) {
        final open = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Permission required'),
            content: const Text(
              'Please grant storage permission in app settings to access your photos.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Open settings'),
              ),
            ],
          ),
        );

        if (open == true) {
          await openAppSettings();
        }
      }
    } else {
      status = await Permission.photos.request();
    }

    if (!status.isGranted) {
      setState(() {
        _loading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Storage permission is required to access files'),
          ),
        );
      }
      return;
    }

    final candidateDirs = <String>[
      '/storage/emulated/0/Pictures',
      '/storage/emulated/0/DCIM/Camera',
      '/storage/emulated/0/DCIM/100MEDIA',
      '/sdcard/DCIM/Camera',
      '/storage/emulated/0/DCIM/100ANDRO',
      '/camera',
    ];

    for (final path in candidateDirs) {
      final folder = Directory(path);
      if (await folder.exists()) {
        final entities = await folder.list().toList();

        final files = folder
            .listSync()
            .whereType<File>()
            .where((file) {
              final lower = file.path.toLowerCase();
              return lower.endsWith('.jpg') ||
                  lower.endsWith('.jpeg') ||
                  lower.endsWith('.png') ||
                  lower.endsWith('.webp') ||
                  lower.endsWith('.gif');
            })
            .toList();

        if (files.isNotEmpty) {
          setState(() {
            _cameraImages.addAll(files);
            _loading = false;
          });
          return;
        }
      }
    }

    setState(() {
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_cameraImages.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No images were found in the camera folder. Ensure the app has access to external storage and that the camera folder exists.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      itemCount: _cameraImages.length,
      itemBuilder: (context, index) {
        final imageFile = _cameraImages[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Card(
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Image.file(
                    imageFile,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Icon(
                            Icons.broken_image,
                            size: 64,
                            color: Colors.grey,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  child: Text(
                    imageFile.path.split(Platform.pathSeparator).last,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
