import 'dart:io';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:path/path.dart';
import 'package:googleapis_auth/googleapis_auth.dart';
import 'cloud_drive.dart';

// This is code obtained from https://github.com/chris-wolf/multi_cloud_storage, with modifications made
// This is done according to the MIT license of the original source code
// All credit goes to the original developer

class GoogleDriveProvider extends CloudServer {
  late drive.DriveApi driveApi;
  bool _isAuthenticated = false;
  String remotePath = "CryptoSafe";

  // Static instance for GoogleSignIn to manage it globally for this provider
  static GoogleSignIn? _googleSignIn;

  // Static instance of the provider to make it a singleton
  static GoogleDriveProvider? _instance;

  GoogleDriveProvider._create(); // Private constructor

  // Public accessor for the singleton instance
  static GoogleDriveProvider? get instance => _instance;

  // Get an authenticated instance of GoogleDriveProvider
  // Tries silent sign-in first, then interactive if needed.
  static Future<GoogleDriveProvider?> connect(
      {bool forceInteractive = false}) async {
    // If already connected and not forcing interactive, return existing instance
    if (_instance != null && _instance!._isAuthenticated && !forceInteractive) {
      print("GoogleDriveProvider: Already connected.");
      return _instance;
    }

    _googleSignIn ??= GoogleSignIn(
      scopes: [
        // MultiCloudStorage.cloudAccess == CloudAccessType.appStorage?
        // drive.DriveApi
        //     .driveAppdataScope // Use driveAppdataScope for appDataFolder
        //     :
        // drive.DriveApi.driveScope, // Full drive access
        drive.DriveApi.driveFileScope
        // You might need PeopleServiceApi.contactsReadonlyScope or other scopes
        // if GSI complains about missing them, but for Drive, these should be enough.
      ],
      // If you use serverClientId for offline access (refresh tokens which are longer-lived)
      // This is highly recommended for "don't re-auth as long as possible"
      // You need to create this OAuth 2.0 Client ID of type "Web application" in Google Cloud Console
      // serverClientId: 'YOUR_SERVER_CLIENT_ID_FROM_GOOGLE_CLOUD_CONSOLE',
    );

    GoogleSignInAccount? account;
    AuthClient? client;

    try {
      if (!forceInteractive) {
        print("GoogleDriveProvider: Attempting silent sign-in...");
        account = await _googleSignIn!.signInSilently();
      }

      if (account == null) {
        print(
            "GoogleDriveProvider: Silent sign-in failed or interactive forced. Attempting interactive sign-in...");
        account = await _googleSignIn!.signIn();
        if (account == null) {
          print("GoogleDriveProvider: Interactive sign-in cancelled by user.");
          _instance?._isAuthenticated =
              false; // Ensure state is false if it was previously true
          return null; // User cancelled
        }
      }
      print("GoogleDriveProvider: Sign-in successful for ${account.email}.");

      // Get the AuthClient from the extension
      client = await _googleSignIn!.authenticatedClient();

      if (client == null) {
        print(
            "GoogleDriveProvider: Failed to get authenticated client. User might not be signed in or credentials issue.");
        await signOut(); // Sign out to clear any problematic state
        _instance?._isAuthenticated = false;
        return null;
      }

      print("GoogleDriveProvider: Authenticated client obtained.");
      final provider = _instance ?? GoogleDriveProvider._create();
      provider.driveApi = drive.DriveApi(client);
      provider._isAuthenticated = true;
      _instance = provider;
      return _instance;
    } catch (error, stackTrace) {
      print(
          'GoogleDriveProvider: Error during sign-in or client retrieval: $error');
      print(stackTrace);
      _instance?._isAuthenticated = false;
      // Optionally sign out if a severe error occurs
      // await signOut();
      return null;
    }
  }

  @override
  Future<bool> checkConnectivity() async {
    _checkAuth();

    return true;
  }

  @override
  Future<List<int>> downloadFile(
    String fileName,
  ) async {
    _checkAuth();

    final filePath = "$remotePath/$fileName";
    final file = await _getFileByPath(filePath);
    if (file == null || file.id == null) {
      throw Exception('GoogleDriveProvider: File not found at $filePath');
    }

    try {
      final media = await driveApi.files.get(
        file.id!,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media; // Cast is important here

      final bytes = <int>[];
      await for (final chunk in media.stream) {
        bytes.addAll(chunk);
      }

      return bytes;
    } catch (e) {
      if (e is drive.DetailedApiRequestError &&
          (e.status == 401 || e.status == 403)) {
        _isAuthenticated = false;
      }
      rethrow;
    }
  }

  @override
  Future<void> uploadFile(
    List<int> fileBytes,
    String fileName,
  ) async {
    _checkAuth();

    final remoteFile = "$remotePath/$fileName";
    Stream<List<int>> stream = Stream.value(fileBytes);
    // Ensure the remote path is relative to the root (or appDataFolder)
    final remoteDir = dirname(remoteFile) == '.' ? '' : dirname(remoteFile);
    final folder = await _getOrCreateFolder(remoteDir);

    final driveFile = drive.File()
      ..name = fileName
      ..parents = [folder.id!];

    final media = drive.Media(stream, fileBytes.length);
    // drive.File uploadedFile;
    try {
      // uploadedFile =
      await driveApi.files.create(driveFile, uploadMedia: media, $fields: 'id');
    } catch (e) {
      print("Error uploading file: $e");
      // Check for auth-related errors here if needed, though the client should refresh
      if (e is drive.DetailedApiRequestError &&
          (e.status == 401 || e.status == 403)) {
        print("Authentication error during upload. Attempting to reconnect...");
        _isAuthenticated = false; // Mark as unauthenticated
        // Optionally try to reconnect or notify user
        // await connect(forceInteractive: true);
        // _checkAuth(); // Re-check auth
        // Retry logic could be added here
      }
      rethrow;
    }
  }

  @override
  Future<void> deleteFile(String fileName) async {
    _checkAuth();

    final remoteFile = "$remotePath/$fileName";

    final file = await _getFileByPath(remoteFile);
    if (file != null && file.id != null) {
      try {
        await driveApi.files.delete(file.id!);
      } catch (e) {
        print("Error deleting file: $e");
        rethrow;
      }
    } else {
      print(
          "GoogleDriveProvider: File/Folder to delete not found at $remoteFile");
      // Optionally throw an exception if not found behavior is critical
      // throw Exception('File not found for deletion: $path');
    }
  }

  @override
  Future<void> deleteAllFiles() async {
    _checkAuth();
    await deleteFile('');
  }

  @override
  Future<bool> checkFileExists(String fileName) async {
    _checkAuth();

    String path = "$remotePath/$fileName";
    final folder = await _getFileByPath(path);
    if (folder == null || folder.id == null) {
      print("GoogleDriveProvider: Folder not found at $path");
      return false;
    }
    return true;
  }

  // Method to sign out
  static Future<void> signOut() async {
    try {
      await _googleSignIn?.disconnect(); // Revoke token
      await _googleSignIn?.signOut(); // Sign out locally
    } catch (e) {
      print("GoogleDriveProvider: Sign out error - $e");
    }

    _googleSignIn = null; // Clear scopes & cached state
    _instance?._isAuthenticated = false;
    _instance = null; // Reset the singleton
    print("GoogleDriveProvider: User signed out and GoogleSignIn reset.");
  }

  void _checkAuth() async {
    if (!_isAuthenticated || _instance == null) {
      try {
        await connect(forceInteractive: true);
      } catch (e) {
        throw Exception(
          'GoogleDriveProvider: Not authenticated or not properly initialized. Call connect() first.\nOriginal error: $e',
        );
      }
    }
  }

  // Helper to get the root folder ID based on access type
  Future<String> _getRootFolderId() async {
    // if (MultiCloudStorage.cloudAccess == CloudAccessType.appStorage) {
    // return 'appDataFolder';
    // }
    return 'root';
  }

  Future<drive.File?> _getFileByPath(String filePath) async {
    _checkAuth();
    if (filePath.isEmpty || filePath == '.' || filePath == '/') {
      // Cannot get a "file" that is the root itself this way,
      // root has special handling or use _getFolderByPath for root folder metadata.
      // This method expects a file or folder *within* another folder.
      if (filePath == '/' || filePath == '.') {
        // Requesting root metadata
        return _getRootFolder();
      }
      return null;
    }

    // Normalize path: remove leading/trailing slashes for consistent splitting
    final normalizedPath =
        filePath.replaceAll(RegExp(r'^/+'), '').replaceAll(RegExp(r'/+$'), '');
    if (normalizedPath.isEmpty)
      return _getRootFolder(); // If path was only slashes

    final parts = split(normalizedPath);
    drive.File currentFolder = await _getRootFolder();

    for (var i = 0; i < parts.length - 1; i++) {
      final folderName = parts[i];
      if (folderName.isEmpty) continue; // Should not happen with normalizedPath
      final folder = await _getFolderByName(currentFolder.id!, folderName);
      if (folder == null) {
        print(
            "GoogleDriveProvider: Intermediate folder '$folderName' not found in path '$filePath'");
        return null;
      }
      currentFolder = folder;
    }

    final fileName = parts.last;
    if (fileName.isEmpty) {
      // Path ended with a slash, meaning it's a directory request
      return currentFolder; // This is the directory itself
    }

    final query =
        "'${currentFolder.id}' in parents and name = '${_sanitizeQueryString(fileName)}' and trashed = false";
    final fileList = await driveApi.files.list(
      spaces: 'drive',
      q: query,
      $fields: 'files(id, name, size, modifiedTime, mimeType, parents)',
      // spaces: MultiCloudStorage.cloudAccess == CloudAccessType.appStorage ? 'appDataFolder' : 'drive',
    );

    return fileList.files?.isNotEmpty == true ? fileList.files!.first : null;
  }

  Future<drive.File> _getOrCreateFolder(String folderPath) async {
    _checkAuth();
    if (folderPath.isEmpty || folderPath == '.' || folderPath == '/') {
      return _getRootFolder();
    }

    // Remove leading/trailing slashes for consistent splitting
    final normalizedPath = folderPath
        .replaceAll(RegExp(r'^/+'), '')
        .replaceAll(RegExp(r'/+$'), '');
    if (normalizedPath.isEmpty) return _getRootFolder();

    final parts = split(normalizedPath);
    drive.File currentFolder = await _getRootFolder();

    for (final part in parts) {
      if (part.isEmpty) continue; // Should not happen with normalizedPath

      var folder = await _getFolderByName(currentFolder.id!, part);
      if (folder == null) {
        folder = await _createFolder(currentFolder.id!, part);
      }
      currentFolder = folder;
    }
    return currentFolder;
  }

  Future<drive.File> _getRootFolder() async {
    // In Drive API, the root folder ID is 'root' or 'appDataFolder'
    String rootFolderId = await _getRootFolderId();
    // We generally don't fetch 'root' or 'appDataFolder' details, just use its ID.
    // If you need its metadata, you'd call files.get(rootFolderId).

    if (_instance == null || !_instance!._isAuthenticated) _checkAuth();

    // To get metadata of the root folder if actually needed:
    // return await driveApi.files.get(rootFolderId, $fields: 'id, name, mimeType, parents');

    // For path traversal, just its ID is sufficient:
    return drive.File()..id = rootFolderId;
  }

  Future<drive.File?> _getFolderByName(String parentId, String name) async {
    _checkAuth();
    final query =
        "'$parentId' in parents and name = '${_sanitizeQueryString(name)}' and mimeType = 'application/vnd.google-apps.folder' and trashed = false";
    final fileList = await driveApi.files.list(
      spaces: 'drive',
      q: query,
      $fields:
          'files(id, name, mimeType, parents)', // Add mimeType and parents for consistency
      // spaces: MultiCloudStorage.cloudAccess == CloudAccessType.appStorage ? 'appDataFolder' : 'drive',
    );
    return fileList.files?.isNotEmpty == true ? fileList.files!.first : null;
  }

  Future<drive.File> _createFolder(String parentId, String name) async {
    _checkAuth();
    final folder = drive.File()
      ..name = name
      ..mimeType = 'application/vnd.google-apps.folder'
      ..parents = [parentId];

    return await driveApi.files
        .create(folder, $fields: 'id, name, mimeType, parents');
  }

  // Helper to sanitize strings for Drive API queries (names with single quotes)
  String _sanitizeQueryString(String value) {
    return value.replaceAll("'", "\\'");
  }

  Future<String> getSharedFileById({
    required String fileId,
    required String localPath,
  }) async {
    _checkAuth();

    final output = File(localPath);
    final sink = output.openWrite();

    try {
      final media = await driveApi.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media; // Cast is important here

      await media.stream.pipe(sink);
      await sink.close();
    } catch (e) {
      await sink.close(); // Ensure sink is closed on error
      // Delete partially downloaded file if an error occurs

      if (await output.exists()) {
        await output.delete();
      }

      print("Error downloading shared file by ID: $e");
      if (e is drive.DetailedApiRequestError &&
          (e.status == 401 || e.status == 403)) {
        print(
            "Authentication error during download. Attempting to reconnect...");
        _isAuthenticated = false;
      }
      rethrow;
    }

    return localPath;
  }
}
