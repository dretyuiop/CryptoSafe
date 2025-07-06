import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cryptosafe/data/cloud/google_drive.dart';
import 'package:cryptosafe/data/cloud/webdav.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract class CloudServer {
  Future<List<int>> downloadFile(String fileName);
  Future<void> uploadFile(List<int> bytes, String fileName);
  Future<void> deleteFile(String fileName);
  Future<void> deleteAllFiles();
  Future<bool> checkFileExists(String fileName);
  Future<bool> checkConnectivity();
}

Future<CloudServer> createCloudInstance() async {
  final prefs = await SharedPreferences.getInstance();
  final storage = FlutterSecureStorage();

  final provider = prefs.getString('cloud_provider');
  final connected = prefs.getBool('cloud_connected') ?? false;

  switch (provider) {
    case 'webdav':
      final uri = prefs.getString('webdav_uri');
      final username = prefs.getString('webdav_username');

      final password = await storage.read(key: 'webdav_password');
      WebDav webdav;

      if (!connected) {
        webdav = WebDav.init(
          uri: uri!,
          username: username!,
          password: password!,
        );
      } else {
        webdav = WebDav.instance!;
      }

      return webdav;

    case 'googledrive':
      final googleDrive = await GoogleDriveProvider.connect();

      return googleDrive!;

    default:
      throw Exception("Unsupported cloud provider: $provider");
  }
}
