import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cryptosafe/presentation/screens/webdav_setup_screen.dart';
import 'package:cryptosafe/business/crypto/crypt.dart';
import 'package:cryptosafe/business/crypto/index.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cryptosafe/main.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:device_info_plus/device_info_plus.dart';

class FirstSetupScreen extends StatefulWidget {
  const FirstSetupScreen({super.key});

  @override
  State<FirstSetupScreen> createState() => _FirstSetupScreenState();
}

class _FirstSetupScreenState extends State<FirstSetupScreen>
    with WidgetsBindingObserver {
  final _appPasswordController = TextEditingController();
  final _confirmAppPasswordController = TextEditingController();

  bool _showEncryptPassword = false;
  bool _showConfirmPassword = false;
  bool _isSaving = false;
  int _currentStep = 0;
  String? _error;
  String? _selectedServer;
  String? _selectedDirectory;
  bool _openedSettingsForPermission = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _appPasswordController.dispose();
    _confirmAppPasswordController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _openedSettingsForPermission) {
      _openedSettingsForPermission = false;
      _checkPermissionAfterReturning();
    }
  }

  Future<void> _handleNext() async {
    setState(() => _error = null);

    if (_currentStep == 0) {
      setState(() => _currentStep = 1);
    } else if (_currentStep == 1) {
      if (_appPasswordController.text.isEmpty ||
          _confirmAppPasswordController.text.isEmpty) {
        setState(
            () => _error = "Please enter and confirm the encryption password.");
        return;
      }
      if (_appPasswordController.text != _confirmAppPasswordController.text) {
        setState(() => _error = "Passwords do not match.");
        return;
      }
      setState(() => _currentStep = 2);
    } else if (_currentStep == 3) {
      if (_selectedServer == null) {
        setState(() => _error = "Please select a server type.");
        return;
      }
      await _saveCloudContinue();
    }
  }

  Future<void> _grantStorageAccess() async {
    final androidInfo = await DeviceInfoPlugin().androidInfo;
    final sdkInt = androidInfo.version.sdkInt;

    PermissionStatus status;

    if (sdkInt >= 30) {
      status = await Permission.manageExternalStorage.status;

      if (!status.isGranted) {
        status = await Permission.manageExternalStorage.request();
      }
    } else {
      status = await Permission.storage.status;

      if (!status.isGranted) {
        status = await Permission.storage.request();
      }
    }

    if (status.isGranted) {
      setState(() => _error = "Permission granted.");
    } else if (status.isPermanentlyDenied) {
      setState(() {
        _error = "Permission permanently denied. Please enable it in settings.";
        _openedSettingsForPermission = true;
      });

      final intent = AndroidIntent(
        action: 'android.settings.MANAGE_ALL_FILES_ACCESS_PERMISSION',
        flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
      );
      await intent.launch();
    } else {
      setState(() => _error = "Permission not granted.");
    }
  }

  Future<void> _checkPermissionAfterReturning() async {
    final status = await Permission.manageExternalStorage.status;
    if (status.isGranted) {
      setState(() => _error = "Permission granted.");
    } else {
      setState(() => _error = "Permission still not granted.");
    }
  }

  Future<void> _pickDirectory() async {
    final status = await Permission.manageExternalStorage.status;
    if (!status.isGranted) {
      setState(() => _error = "Grant storage permission first.");
      return;
    }

    final selected = await FilePicker.platform.getDirectoryPath();
    if (selected != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('download_directory', selected);

      setState(() {
        _selectedDirectory = selected;
        _error = null;
      });
    }
  }

  Future<void> _saveCloudContinue() async {
    setState(() => _isSaving = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final storage = FlutterSecureStorage();

      final encryptedPassword = await createKey(_appPasswordController.text);

      await storage.write(key: 'encryption_password', value: encryptedPassword);
      await prefs.setBool('first_setup_done', true);
      await prefs.setString('cloud_provider', _selectedServer!);
      await prefs.setString('download_directory', _selectedDirectory!);

      if (!mounted) return;

      if (_selectedServer == 'webdav') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const WebDavSetupScreen()),
        );
      } else if (_selectedServer == 'googledrive') {
        await _handleGoogleDriveSetup();
      }
    } catch (e) {
      setState(() => _error = "Failed to save: $e");
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _handleGoogleDriveSetup() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('cloud_provider', 'googledrive');

    try {
      await prefs.setBool('cloud_connected', true);
      readIndexCloud();
    } catch (_) {}

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const MainNavigationScreen()),
    );
  }

  Widget _buildIntroStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Welcome to CryptoSafe",
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        const Text(
          "CryptoSafe helps you securely store your encrypted files to the cloud."
          "All encryption is done on your device, and only you hold the key.",
          style: TextStyle(fontSize: 16),
        ),
        const SizedBox(height: 30),
        ElevatedButton(
          onPressed: _handleNext,
          child: const Text('Get Started'),
        ),
      ],
    );
  }

  Widget _buildPasswordStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Step 1: Encryption Password",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text(
          "This password will be used for encryption. If you forget it, your files cannot be recovered.",
          style: TextStyle(fontSize: 14),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _appPasswordController,
          obscureText: !_showEncryptPassword,
          decoration: InputDecoration(
            labelText: 'Encryption Password',
            suffixIcon: IconButton(
              icon: Icon(
                _showEncryptPassword ? Icons.visibility : Icons.visibility_off,
              ),
              onPressed: () =>
                  setState(() => _showEncryptPassword = !_showEncryptPassword),
            ),
          ),
        ),
        TextField(
          controller: _confirmAppPasswordController,
          obscureText: !_showConfirmPassword,
          decoration: InputDecoration(
            labelText: 'Confirm Password',
            suffixIcon: IconButton(
              icon: Icon(
                _showConfirmPassword ? Icons.visibility : Icons.visibility_off,
              ),
              onPressed: () =>
                  setState(() => _showConfirmPassword = !_showConfirmPassword),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            OutlinedButton(
              onPressed: () => setState(() => _currentStep = 0),
              child: const Text('Back'),
            ),
            const SizedBox(width: 10),
            ElevatedButton(
              onPressed: _handleNext,
              child: const Text('Next'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDirectoryStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Step 2: Download Storage",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          "Please grant access to storage to download files.",
          style: TextStyle(fontSize: 14),
        ),
        const SizedBox(height: 16),
        FutureBuilder<PermissionStatus>(
          future: Permission.manageExternalStorage.status,
          builder: (context, snapshot) {
            final status = snapshot.data;
            final isGranted = status == PermissionStatus.granted;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ElevatedButton.icon(
                  onPressed: isGranted ? null : _grantStorageAccess,
                  icon: const Icon(Icons.lock),
                  label: Text(isGranted
                      ? "Storage Permission Granted"
                      : "Grant Storage Permission"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isGranted ? Colors.grey : null,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  "Please choose the directory where the downloaded files will be stored.",
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: isGranted ? _pickDirectory : null,
                  icon: const Icon(Icons.folder),
                  label: const Text("Choose Directory"),
                ),
                if (_selectedDirectory != null) ...[
                  const SizedBox(height: 12),
                  const Text(
                    "Selected Directory:",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(_selectedDirectory!),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    OutlinedButton(
                      onPressed: () => setState(() => _currentStep = 1),
                      child: const Text('Back'),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: () {
                        if (_selectedDirectory == null) {
                          setState(() =>
                              _error = "Please select a download directory.");
                        } else {
                          setState(() => _currentStep = 3);
                        }
                      },
                      child: const Text('Next'),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildServerChoiceStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Step 3: Choose Server Type",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text(
          "The server is where the encrypted files are stored.",
          style: TextStyle(fontSize: 14),
        ),
        const SizedBox(height: 16),
        RadioListTile<String>(
          title: const Text("Google Drive"),
          value: "googledrive",
          groupValue: _selectedServer,
          onChanged: (value) => setState(() => _selectedServer = value),
        ),
        RadioListTile<String>(
          title: const Text("WebDAV"),
          value: "webdav",
          groupValue: _selectedServer,
          onChanged: (value) => setState(() => _selectedServer = value),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            OutlinedButton(
              onPressed: () => setState(() => _currentStep = 2),
              child: const Text('Back'),
            ),
            const SizedBox(width: 10),
            ElevatedButton(
              onPressed: _handleNext,
              child: const Text('Finish Setup'),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    switch (_currentStep) {
      case 0:
        body = _buildIntroStep();
        break;
      case 1:
        body = _buildPasswordStep();
        break;
      case 2:
        body = _buildDirectoryStep();
        break;
      case 3:
        body = _buildServerChoiceStep();
        break;
      default:
        body = const Text("Unknown step");
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Initial Setup')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: _isSaving
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  body,
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                ],
              ),
      ),
    );
  }
}
