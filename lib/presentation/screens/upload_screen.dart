import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cryptosafe/business/crypto/repository.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  File? _selectedFile;
  bool _isUploading = false;
  bool _filePicked = false;

  final TextEditingController _descriptionController = TextEditingController();
  final List<TextEditingController> _keywordControllers = [
    TextEditingController(),
  ];

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      final fileName = file.path.split('/').last;
      final nameWithoutExtension = fileName.split('.').first;

      final tokens = nameWithoutExtension
          .split(RegExp(r'[^a-zA-Z0-9]+'))
          .where((token) => token.trim().isNotEmpty)
          .toList();

      setState(() {
        _selectedFile = file;
        _filePicked = true;

        for (var controller in _keywordControllers) {
          controller.dispose();
        }
        _keywordControllers.clear();

        if (tokens.isEmpty) {
          _keywordControllers.add(TextEditingController());
        } else {
          _keywordControllers.addAll(
              tokens.map((token) => TextEditingController(text: token)));
        }
      });
    }
  }

  void _addKeywordField() {
    setState(() {
      _keywordControllers.add(TextEditingController());
    });
  }

  void _removeKeywordField(int index) {
    if (_keywordControllers.length > 1) {
      setState(() {
        _keywordControllers[index].dispose();
        _keywordControllers.removeAt(index);
      });
    }
  }

  Future<void> _uploadFile() async {
    if (_selectedFile == null || _isUploading) return;

    final fileName = _selectedFile!.path.split('/').last;
    final filePath = _selectedFile!.path;
    print(filePath);

    final keywords = _keywordControllers
        .map((controller) => controller.text.trim())
        .where((text) => text.isNotEmpty)
        .toList();

    final description = _descriptionController.text.trim();

    if (keywords.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter at least one keyword.')),
      );
      return;
    }

    setState(() {
      _isUploading = true;
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        title: Text('Uploading...'),
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Please wait'),
          ],
        ),
      ),
    );

    try {
      final RootIsolateToken rootIsolateToken = RootIsolateToken.instance!;
      await compute(
        addFileToRepoWrapper,
        [fileName, filePath, keywords, description, rootIsolateToken],
      );

      if (mounted) Navigator.of(context).pop();

      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Upload Complete'),
          content: const Text('File uploaded successfully.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );

      setState(() {
        _selectedFile = null;
        _filePicked = false;
        _descriptionController.clear();
        for (var controller in _keywordControllers) {
          controller.dispose();
        }
        _keywordControllers.clear();
        _keywordControllers.add(TextEditingController());
      });
    } catch (e) {
      if (mounted) Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    for (var controller in _keywordControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Upload File'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: _filePicked && _selectedFile != null
            ? ListView(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.insert_drive_file, size: 40),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _selectedFile!.path.split('/').last,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.red),
                        tooltip: 'Remove file',
                        onPressed: () {
                          setState(() {
                            _selectedFile = null;
                            _filePicked = false;
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Enter Description:',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _descriptionController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: 'Optional file description...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Enter Keywords (Used for Searching):',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ..._keywordControllers.asMap().entries.map((entry) {
                    final index = entry.key;
                    final controller = entry.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: controller,
                              decoration: InputDecoration(
                                labelText: 'Keyword ${index + 1}',
                                border: const OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (_keywordControllers.length > 1)
                            IconButton(
                              icon: const Icon(Icons.remove_circle,
                                  color: Colors.red),
                              onPressed: () => _removeKeywordField(index),
                            ),
                        ],
                      ),
                    );
                  }),
                  SizedBox(
                    width: double.infinity,
                    child: IconButton(
                      onPressed: _addKeywordField,
                      icon: const Icon(Icons.add, size: 28),
                      tooltip: 'Add keyword',
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _isUploading ? null : _uploadFile,
                    child: _isUploading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Upload'),
                  ),
                ],
              )
            : Center(
                child: SizedBox(
                  width: 220,
                  height: 60,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24.0, vertical: 16.0),
                      textStyle: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                    onPressed: _pickFile,
                    icon: const Icon(Icons.cloud_upload, size: 28),
                    label: const Text('Upload File'),
                  ),
                ),
              ),
      ),
    );
  }
}

Future<void> addFileToRepoWrapper(List<dynamic> args) async {
  final String fileName = args[0];
  final String filePath = args[1];
  final List<String> keywords = List<String>.from(args[2]);
  final String description = args[3];
  final RootIsolateToken rootToken = args[4];

  BackgroundIsolateBinaryMessenger.ensureInitialized(rootToken);

  final result = await addFileToRepo(
    fileName,
    filePath,
    keywords,
    description,
  );
  return result;
}
