import 'package:cryptosafe/business/crypto/index.dart';
import 'package:flutter/material.dart';
import 'package:cryptosafe/data/cloud/cloud_drive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cryptosafe/data/cloud/google_drive.dart';
import 'webdav_setup_screen.dart';
import 'package:flutter/services.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  void _showServerDialog(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    String? currentProvider = prefs.getString('cloud_provider');

    final Map<String, String> cloudProviders = {
      'webdav': 'WebDAV',
      'googledrive': 'Google Drive',
    };

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        String? selectedProvider = currentProvider;

        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Select Cloud Server'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: cloudProviders.entries.map((entry) {
                  return RadioListTile<String>(
                    title: Text(entry.value),
                    value: entry.key,
                    groupValue: selectedProvider,
                    onChanged: (value) {
                      setState(() {
                        selectedProvider = value;
                      });
                    },
                  );
                }).toList(),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: selectedProvider == null
                      ? null
                      : () {
                          Navigator.of(dialogContext).pop();
                          _handleServerSelection(
                            context,
                            selectedProvider!,
                            cloudProviders[selectedProvider!]!,
                          );
                        },
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _handleServerSelection(
      BuildContext context, String key, String displayName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cloud_provider', key);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$displayName selected as cloud server')),
      );
    }

    if (key == 'webdav') {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const WebDavSetupScreen()),
      );
    } else if (key == 'googledrive') {
      await GoogleDriveProvider.signOut();
      await GoogleDriveProvider.connect(forceInteractive: true);
      readIndexCloud();
    }
  }

  void _showDownloadDirectoryDialog(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final downloadDir = prefs.getString('download_directory') ?? 'Not set';

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Download Directory'),
          content: Text(downloadDir),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'General',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.download),
            title: const Text('Downloads'),
            onTap: () => _showDownloadDirectoryDialog(context),
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Configuration',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.cloud),
            title: const Text('Server'),
            onTap: () => _showServerDialog(context),
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: const Text(
              'Reset App (Clear All Data)',
              style: TextStyle(color: Colors.red),
            ),
            onTap: () {
              showDialog(
                context: context,
                builder: (BuildContext dialogContext) {
                  return AlertDialog(
                    title: const Text('Confirm Reset'),
                    content: const Text(
                        'This will delete all cloud files, local data, and settings. This action cannot be undone.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            vertical: 12.0,
                            horizontal: 16.0,
                          ),
                        ),
                        onPressed: () async {
                          Navigator.of(dialogContext).pop();
                          await resetApp(context);
                        },
                        child: const Text('Delete Everything'),
                      ),
                    ],
                  );
                },
              );
            },
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'About',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.info),
            title: const Text('App Version'),
            subtitle: const Text('1.0.0'),
          ),
        ],
      ),
    );
  }
}

Future<void> resetApp(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  final storage = FlutterSecureStorage();
  final cloud = await createCloudInstance();

  await cloud.deleteAllFiles();

  try {
    await prefs.clear();
    await storage.deleteAll();

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("App data cleared successfully.")),
      );
      await Future.delayed(const Duration(milliseconds: 300));
      SystemNavigator.pop();
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error during reset: $e")),
      );
    }
  }
}
