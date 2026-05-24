import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
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
  final List<File> _selectedFolderImages = [];
  String? _selectedDirectory;
  bool _loading = true;
  // Candidate folders scanned for images (displayed in the folder scroller)
  final List<String> _candidateDirs = [];
  // Map of folder path -> up to 4 thumbnail files for that folder
  final Map<String, List<File>> _dirThumbnails = {};
  // Loaded files grouped by directory from the database
  final Map<String, List<FileEntry>> _filesByDirectory = {};

  @override
  void initState() {
    super.initState();
    _loadAndDisplayImages();
  }

  Future<void> _loadAndDisplayImages() async {
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

    // Prepare temporary containers then set state once to update UI.
    final candidateList = <String>[];
    final thumbnails = <String, List<File>>{};

    final filesByDirectory = await DatabaseHelper.getFilesByDirectory();

    for (final entry in filesByDirectory.entries) {
      final dir = entry.key;
      final files = entry.value;
      candidateList.add(dir);
      if (files.isNotEmpty) {
        thumbnails[dir] = files.take(4).map((e) => File(e.path)).toList();
      }
    }

    // Start with nothing selected to allow showing all files by default.
    final initialDirectory = null;
    final initialImages = filesByDirectory.values
      .expand((list) => list)
      .map((e) => File(e.path))
      .toList();

    setState(() {
      _candidateDirs.clear();
      _candidateDirs.addAll(candidateList);
      _dirThumbnails.clear();
      _dirThumbnails.addAll(thumbnails);
      _filesByDirectory.clear();
      _filesByDirectory.addAll(filesByDirectory);
      _selectedDirectory = initialDirectory;
      _selectedFolderImages.clear();
      _selectedFolderImages.addAll(initialImages);
      _loading = false;
    });
  }

  void _selectDirectory(String directory) {
    setState(() {
      if (_selectedDirectory == directory) {
        // Toggle off selection — show all files.
        _selectedDirectory = null;
        _selectedFolderImages
          ..clear()
          ..addAll(
            _filesByDirectory.values
                .expand((list) => list)
                .map((e) => File(e.path)),
          );
      } else {
        _selectedDirectory = directory;
        _selectedFolderImages
          ..clear()
          ..addAll(_filesByDirectory[directory]?.map((e) => File(e.path)) ?? []);
      }
    });
  }

  void _selectAll() {
    setState(() {
      _selectedDirectory = null;
      _selectedFolderImages
        ..clear()
        ..addAll(
          _filesByDirectory.values
              .expand((list) => list)
              .map((e) => File(e.path)),
        );
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

    final halfHeight = MediaQuery.of(context).size.height * 0.5;
    final hasImages = _selectedFolderImages.isNotEmpty;

    return Column(
      children: [
        // Main image scroller (top, half height)
        SizedBox(
          height: halfHeight,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            itemCount: hasImages ? _selectedFolderImages.length : 3,
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
                                  _selectedFolderImages[index],
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
                                ? _selectedFolderImages[index]
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
          final baseCandidates = _candidateDirs.isNotEmpty
              ? _candidateDirs
              : [for (var i = 0; i < 3; i++) ''];

          // Prepend a special 'All' card when we have real candidates.
          final displayCandidates = _candidateDirs.isNotEmpty
              ? ['__ALL__', ...baseCandidates]
              : baseCandidates;

          return SizedBox(
            height: folderHeight,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              itemCount: displayCandidates.length,
              itemBuilder: (context, idx) {
                final raw = displayCandidates[idx];
                final isAll = raw == '__ALL__';
                final dir = isAll ? '' : raw;
                final thumbs = isAll
                    ? _filesByDirectory.values
                        .expand((l) => l)
                        .map((e) => File(e.path))
                        .take(4)
                        .toList()
                    : (dir.isNotEmpty ? (_dirThumbnails[dir] ?? []) : []);
                final itemWidth = MediaQuery.of(context).size.width * 0.42;

                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: SizedBox(
                    width: itemWidth,
                    child: GestureDetector(
                      onTap: isAll
                          ? _selectAll
                          : (dir.isNotEmpty ? () => _selectDirectory(dir) : null),
                      child: Card(
                        clipBehavior: Clip.antiAlias,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: (isAll
                                  ? _selectedDirectory == null
                                  : dir == _selectedDirectory)
                              ? BorderSide(
                                  color: Theme.of(context).colorScheme.primary,
                                  width: 2,
                                )
                              : BorderSide.none,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
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
                                isAll
                                    ? 'All'
                                    : (dir.isNotEmpty
                                        ? dir.split(Platform.pathSeparator).last
                                        : 'Unknown'),
                                style: Theme.of(context).textTheme.bodySmall,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
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
