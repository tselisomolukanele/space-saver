import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path_package;
import 'services/database.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DatabaseHelper.initDB();
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
  // Candidate folders scanned for images (displayed in the folder scroller)
  final List<String> _candidateDirs = [];
  // Map of folder path -> up to 4 thumbnail files for that folder
  final Map<String, List<File>> _dirThumbnails = {};

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

    final candidateDirs = await _loadCandidateDirsFromDatabase();        

    // Prepare temporary containers then set state once to update UI.
    final foundCameraImages = <File>[];
    final candidateList = <String>[];
    final thumbnails = <String, List<File>>{};

    for (final path in candidateDirs) {
      candidateList.add(path);
      final folder = Directory(path);
      if (await folder.exists()) {
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
          // Keep up to 4 thumbnails to show in the folder scroller.
          thumbnails[path] = files.take(4).toList();
          // If we haven't populated the main image list yet, use the first non-empty folder.
          if (foundCameraImages.isEmpty) {
            foundCameraImages.addAll(files);
          }
        }
      }
    }

    setState(() {
      _candidateDirs.clear();
      _candidateDirs.addAll(candidateList);
      _dirThumbnails.clear();
      _dirThumbnails.addAll(thumbnails);
      if (foundCameraImages.isNotEmpty) {
        _cameraImages.addAll(foundCameraImages);
      }
      _loading = false;
    });
  }

  Future<List<String>> _loadCandidateDirsFromDatabase() async {
    try {
      final databasesPath = await getDatabasesPath();
      final dbPath = '$databasesPath${Platform.pathSeparator}albums.db';
      if (!await databaseExists(dbPath)) {
        return const [];
      }

      final db = await openDatabase(dbPath, readOnly: true);
      try {
        final rows = await db.rawQuery(
          'SELECT DISTINCT value FROM album WHERE key = ?',
          ['path'],
        );
        return rows
            .map((row) => row['value'])
            .whereType<String>()
            .map( (value) => path_package.dirname(value))
            .toSet()
            .toList();
      } finally {
        await db.close();
      }
    } catch (_) {
      return const [];
    }
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

    final halfHeight = MediaQuery.of(context).size.height * 0.5;
    final hasImages = _cameraImages.isNotEmpty;

    return Column(
      children: [
        // Main image scroller (top, half height)
        SizedBox(
          height: halfHeight,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            itemCount: hasImages ? _cameraImages.length : 3,
            itemBuilder: (context, index) {
              final cardWidth = MediaQuery.of(context).size.width * 0.8;
              return Padding(
                padding: const EdgeInsets.only(right: 16),
                child: SizedBox(
                  width: cardWidth,
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: hasImages
                              ? Image.file(
                                  _cameraImages[index],
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
                                )
                              : Container(
                                  margin: const EdgeInsets.all(24),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade200,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Center(
                                    child: Icon(
                                      Icons.photo,
                                      size: 64,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 12, horizontal: 16),
                          child: Text(
                            hasImages
                                ? _cameraImages[index]
                                    .path
                                    .split(Platform.pathSeparator)
                                    .last
                                : 'Empty slot',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),

        // Folder scroller (slightly smaller, two-row thumbnails per folder)
        Builder(builder: (context) {
          final folderHeight = halfHeight * 0.5;
          final candidates = _candidateDirs.isNotEmpty ? _candidateDirs : [for (var i = 0; i < 3; i++) ''];
          return SizedBox(
            height: folderHeight,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              itemCount: candidates.length,
              itemBuilder: (context, idx) {
                final dir = candidates[idx];
                final thumbs = dir.isNotEmpty ? (_dirThumbnails[dir] ?? []) : [];
                final itemWidth = MediaQuery.of(context).size.width * 0.42;
                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: SizedBox(
                    width: itemWidth,
                    child: Card(
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // 2x2 small thumbnails
                            Expanded(
                              child: GridView.count(
                                crossAxisCount: 2,
                                mainAxisSpacing: 6,
                                crossAxisSpacing: 6,
                                physics: const NeverScrollableScrollPhysics(),
                                children: List.generate(4, (i) {
                                  if (thumbs.length > i) {
                                    return ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: Image.file(
                                        thumbs[i],
                                        fit: BoxFit.cover,
                                      ),
                                    );
                                  }

                                  return Container(
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade200,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Center(
                                      child: Icon(
                                        Icons.photo_library,
                                        size: 20,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  );
                                }),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              dir.isNotEmpty
                                  ? dir.split(Platform.pathSeparator).last
                                  : 'Unknown',
                              style: Theme.of(context).textTheme.bodySmall,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        }),

        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                hasImages
                    ? 'Swipe left or right to browse your images.'
                    : 'No images were found in the camera folder. Ensure the app has access to external storage and that the camera folder exists.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
