import 'package:flutter/material.dart';
import 'package:cryptosafe/business/crypto/repository.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  Map<String, dynamic> _results = {};
  bool _searchPerformed = false;
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
  }


  Future<void> _onSearchPressed() async {
    setState(() {
      _isSearching = true;
      _searchPerformed = false;
      _results.clear();
    });


    final query = _searchController.text.trim();
    Map<String, dynamic> result = {};

    if (query.contains('+')) {
      List<String> keywords = query.split('+').map((s) => s.trim()).toList();
      result = await searchFilesFromRepoMultiKey(keywords);
    } else {
      result = await searchFilesFromRepo(query);
    }

    setState(() {
      _results = result;
      _searchPerformed = true;
      _isSearching = false;
    });
  }

  void _handleFileTap(
      String query, String encryptedFileName) async {
    bool isLoadingDialogShowing = false;

    try {
      isLoadingDialogShowing = true;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text("Downloading..."),
            ],
          ),
        ),
      );

      if (query.contains('+')) {
        query = query.split('+').first.trim();
      }

      String savedFilePath = await getFilesFromRepo(
        encryptedFileName,
        query,
      );

      if (isLoadingDialogShowing) {
        Navigator.of(context, rootNavigator: true).pop();
        isLoadingDialogShowing = false;
      }

      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Download Complete'),
          content: Text('File saved to:\n$savedFilePath'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (isLoadingDialogShowing) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      String errorMessage = 'Error saving file: $e';
      if (e.toString().contains(
          'File not found or no locations associated with keyword.')) {
        errorMessage = 'File not found or corrupted. Could not retrieve.';
      }
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Download Failed'),
          content: Text(errorMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildHomeContent() {
    final bool showNoResults = _searchPerformed && _results.isEmpty;
    final String query = _searchController.text.trim();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _onSearchPressed(),
                  decoration: InputDecoration(
                    hintText: 'Search for files using keywords',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_searchController.text.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              setState(() {
                                _searchController.clear();
                                _results.clear();
                                _searchPerformed = false;
                              });
                            },
                          )
                        else
                          Tooltip(
                            message:
                                'Use "+" to search with multiple keywords.\nExample: secret+project',
                            child: const Padding(
                              padding: EdgeInsets.only(right: 8.0),
                              child: Icon(Icons.info_outline),
                            ),
                          ),
                      ],
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12.0),
                    ),
                  ),
                  onChanged: (_) {
                    setState(() {});
                  },
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _isSearching
              ? const Center(child: CircularProgressIndicator())
              : showNoResults
                  ? const Center(
                      child: Text(
                        'No results found.',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                  : _results.isEmpty
                      ? const Center(
                          child: Text(
                            'Welcome to Crypto Safe!',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        )
                      : ListView(
                          children: _results.entries.map((entry) {
                            final filename = entry.key;
                            final description = entry.value[0];
                            final encryptedFileName = entry.value[1];

                            return ListTile(
                              leading: const Icon(Icons.insert_drive_file),
                              title: Text(filename),
                              subtitle: Text(description),
                              onTap: () => _handleFileTap(
                                  query, encryptedFileName),
                              trailing: IconButton(
                                icon:
                                    const Icon(Icons.close, color: Colors.red),
                                tooltip: 'Delete File',
                                onPressed: () async {
                                  bool confirm = await showDialog(
                                    context: context,
                                    builder: (_) => AlertDialog(
                                      title: const Text('Confirm Deletion'),
                                      content: Text(
                                          'Are you sure you want to delete "$filename"?'),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.of(context).pop(false),
                                          child: const Text('Cancel'),
                                        ),
                                        ElevatedButton(
                                          onPressed: () =>
                                              Navigator.of(context).pop(true),
                                          child: const Text('Delete'),
                                        ),
                                      ],
                                    ),
                                  );

                                  if (confirm) {
                                    try {
                                      String processedQuery;
                                      if (query.contains('+')) {
                                        processedQuery =
                                            query.split('+').first.trim();
                                      } else {
                                        processedQuery = query;
                                      }
                                      await deleteFilesFromRepo(
                                          encryptedFileName, processedQuery);
                                      setState(() {
                                        _results.remove(filename);
                                      });
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                            content:
                                                Text('Deleted "$filename"')),
                                      );
                                    } catch (e) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                            content: Text('Delete failed: $e')),
                                      );
                                    }
                                  }
                                },
                              ),
                            );
                          }).toList(),
                        ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Crypto Safe'),
      ),
      body: _buildHomeContent(),
    );
  }
}
