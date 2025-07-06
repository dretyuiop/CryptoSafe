import 'package:flutter/material.dart';
import 'package:cryptosafe/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cryptosafe/business/crypto/index.dart';
import 'package:cryptosafe/data/cloud/cloud_drive.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class WebDavSetupScreen extends StatefulWidget {
  const WebDavSetupScreen({super.key});

  @override
  State<WebDavSetupScreen> createState() => _WebDavSetupScreenState();
}

class _WebDavSetupScreenState extends State<WebDavSetupScreen> {
  final _formKey = GlobalKey<FormState>();

  final _uriController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isSaving = false;
  bool _connectionSuccessful = false;
  bool _showSuccessIcon = false;
  bool _showErrorIcon = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _loadSavedPreferences();
  }

  Future<void> _loadSavedPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _uriController.text = prefs.getString('webdav_uri') ?? '';
      _usernameController.text = prefs.getString('webdav_username') ?? '';
      _passwordController.text = prefs.getString('webdav_password') ?? '';
    });
  }

  Future<void> _saveAndTestConnection() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
      _connectionSuccessful = false;
      _showSuccessIcon = false;
      _showErrorIcon = false;
    });

    final uri = _uriController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    final prefs = await SharedPreferences.getInstance();
    final storage = FlutterSecureStorage();

    await prefs.setString('cloud_provider', 'webdav');
    await prefs.setString('webdav_uri', uri);
    await prefs.setString('webdav_username', username);
    await prefs.setBool('cloud_connected', false);
    await storage.write(key: 'webdav_password', value: password);

    final webDav = await createCloudInstance();
    final connected = await webDav.checkConnectivity();

    if (connected) {
      await prefs.setBool('cloud_connected', true);
      readIndexCloud();

      setState(() {
        _connectionSuccessful = true;
        _showSuccessIcon = true;
      });
    } else {
      setState(() {
        _showErrorIcon = true;
      });
    }

    setState(() => _isSaving = false);

    await Future.delayed(const Duration(seconds: 3));
    if (mounted) {
      setState(() {
        _showSuccessIcon = false;
        _showErrorIcon = false;
      });
    }
  }

  void _goToHomeScreen() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const MainNavigationScreen()),
      (Route<dynamic> route) => false,
    );
  }

  @override
  void dispose() {
    _uriController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("WebDAV Setup")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _uriController,
                decoration: const InputDecoration(labelText: "WebDAV URI"),
                validator: (value) =>
                    value == null || value.isEmpty ? "Enter URI" : null,
              ),
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(labelText: "Username"),
                validator: (value) =>
                    value == null || value.isEmpty ? "Enter username" : null,
              ),
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: "Password",
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility
                          : Icons.visibility_off,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
                ),
                validator: (value) =>
                    value == null || value.isEmpty ? "Enter password" : null,
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 120,
                    height: 40,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveAndTestConnection,
                      child: _isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : _showSuccessIcon
                              ? const Icon(Icons.check, color: Colors.green)
                              : _showErrorIcon
                                  ? const Icon(Icons.error, color: Colors.red)
                                  : const Text("Test"),
                    ),
                  ),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 120,
                    height: 40,
                    child: ElevatedButton(
                      onPressed: _connectionSuccessful ? _goToHomeScreen : null,
                      child: const Text("Continue"),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
