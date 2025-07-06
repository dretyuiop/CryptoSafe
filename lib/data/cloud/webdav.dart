import 'package:cryptosafe/data/cloud/cloud_drive.dart';
import 'package:webdav_client/webdav_client.dart';
import 'dart:typed_data';

class WebDav extends CloudServer {
  late Client client;
  String remotePath = "/";

  static WebDav? _instance;
  static WebDav? get instance => _instance;

  WebDav._internal({
    required String uri,
    required String username,
    required String password,
  }) {
    client = newClient(
      uri,
      user: username,
      password: password,
    );
  }

  static WebDav init({
    required String uri,
    required String username,
    required String password,
  }) {
    _instance = WebDav._internal(
      uri: uri,
      username: username,
      password: password,
    );
    return _instance!;
  }

  @override
  Future<List<int>> downloadFile(String fileName) async {
    try {
      final list = await client.readDir(remotePath);
      if (list.any((file) => file.name == fileName)) {
        return await client.read("/$fileName");
      } else {
        throw Exception("File not found: $fileName");
      }
    } catch (e) {
      throw Exception('Download failed for $fileName: $e');
    }
  }

  @override
  Future<void> uploadFile(List<int> bytes, String fileName) async {
    try {
      client.setHeaders({'Content-Type': 'application/octet-stream'});
      await client.write("/$fileName", Uint8List.fromList(bytes));
    } catch (e) {
      throw Exception('Upload failed for $fileName: $e');
    }
  }

  @override
  Future<void> deleteFile(String filePath) async {
    try {
      await client.remove(filePath);
    } catch (e) {
      throw Exception('Failed to delete file $filePath: $e');
    }
  }

  @override
  Future<void> deleteAllFiles() async {
    try {
      final files = await client.readDir(remotePath);
      for (final file in files) {
        try {
          await client.remove("/${file.name}");
        } catch (e) {
          print("Failed to delete ${file.name}: $e");
        }
      }
    } catch (e) {
      throw Exception('Failed to delete all files: $e');
    }
  }

  @override
  Future<bool> checkFileExists(String fileName) async {
    try {
      final files = await client.readDir(remotePath);
      return files.any((file) => file.name == fileName);
    } catch (e) {
      throw Exception('Failed to check existence of $fileName: $e');
    }
  }

  @override
  Future<bool> checkConnectivity() async {
    try {
      await client.ping();
      return true;
    } catch (e) {
      throw Exception('WebDAV connection check failed: $e');
    }
  }
}
