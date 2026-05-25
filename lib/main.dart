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
  final Set<String> _selectedDirectories = {};
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
      PermissionStatus manageStatus =
          await Permission.manageExternalStorage.status;
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
      _selectedDirectories.clear();
      _selectedFolderImages.clear();
      _selectedFolderImages.addAll(initialImages);
      _loading = false;
    });
  }

  void _selectDirectory(String directory) {
    setState(() {
      if (_selectedDirectories.remove(directory)) {
        if (_selectedDirectories.isEmpty) {
          _selectedFolderImages
            ..clear()
            ..addAll(
              _filesByDirectory.values
                  .expand((list) => list)
                  .map((e) => File(e.path)),
            );
        } else {
          _selectedFolderImages
            ..clear()
            ..addAll(
              _selectedDirectories
                  .expand(
                    (selectedDir) => _filesByDirectory[selectedDir] ?? const [],
                  )
                  .map((e) => File(e.path)),
            );
        }
      } else {
        _selectedDirectories.add(directory);
        _selectedFolderImages
          ..clear()
          ..addAll(
            _selectedDirectories
                .expand(
                  (selectedDir) => _filesByDirectory[selectedDir] ?? const [],
                )
                .map((e) => File(e.path)),
          );
      }
    });
  }

  void _selectAll() {
    setState(() {
      _selectedDirectories.clear();
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
                              ? imageOrFallback(_selectedFolderImages[index])
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
                            vertical: 12,
                            horizontal: 16,
                          ),
                          child: Text(
                            hasImages
                                ? _selectedFolderImages[index].path
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
        Builder(
          builder: (context) {
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
                padding: const EdgeInsets.symmetric(
                  vertical: 8,
                  horizontal: 12,
                ),
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
                            : (dir.isNotEmpty
                                  ? () => _selectDirectory(dir)
                                  : null),
                        child: Card(
                          clipBehavior: Clip.antiAlias,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side:
                                (isAll
                                    ? _selectedDirectories.isEmpty
                                    : _selectedDirectories.contains(dir))
                                ? BorderSide(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    width: 2,
                                  )
                                : BorderSide.none,
                          ),
                          child: Stack(
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                      child: GridView.count(
                                        crossAxisCount: 2,
                                        mainAxisSpacing: 6,
                                        crossAxisSpacing: 6,
                                        physics:
                                            const NeverScrollableScrollPhysics(),
                                        children: List.generate(4, (i) {
                                          if (thumbs.length > i) {
                                            return ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              child: thumbnailOrFallBack(thumbs[i]),
                                            );
                                          }

                                          return Container(
                                            decoration: BoxDecoration(
                                              color: Colors.grey.shade200,
                                              borderRadius:
                                                  BorderRadius.circular(6),
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
                                                ? dir
                                                      .split(
                                                        Platform.pathSeparator,
                                                      )
                                                      .last
                                                : 'Unknown'),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              if (isAll && _selectedDirectories.isNotEmpty)
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      '${_selectedDirectories.length} selected',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                  ),
                                ),
                              if (!isAll && _selectedDirectories.contains(dir))
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.check,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                                  ),
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
          },
        ),

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

  Image imageOrFallback(File input) {
    Center errorBuilder(context, error, stackTrace) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Icon(Icons.broken_image, size: 64, color: Colors.grey),
        ),
      );
    }

    if (input.path.isEmpty) {
      return Image.asset(
        'assets/images/oops.png',
        fit: BoxFit.cover,
        errorBuilder: errorBuilder,
      );
    }

    return Image.file(input, fit: BoxFit.cover, errorBuilder: errorBuilder);
  }

  Image thumbnailOrFallBack(File input) {
    if (input.path.isEmpty) {
      return Image.asset('assets/images/oops.png', fit: BoxFit.cover);
    }

    return Image.file(input, fit: BoxFit.cover);
  }
}
