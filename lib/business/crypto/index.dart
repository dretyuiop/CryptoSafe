import 'dart:convert';
import 'package:cryptosafe/data/cloud/cloud_drive.dart';
import "crypt.dart";
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final storage = FlutterSecureStorage();
final emptyIndex = '{"files": {}}';

Future<void> addDocIndex(
    String fileName,
    List<String> keywords,
    List<String> encryptFileLocations,
    List<List> startEndBytes,
    String fileDesc) async {
  String indexContents = await storage.read(key: "index") ?? emptyIndex;
  Map<String, dynamic> index = json.decode(indexContents);
  Map<String, dynamic> fileIndexLocation = {};
  final encryptedFileName = await encryptString(fileName);

  for (int i = 0; i < encryptFileLocations.length; i++) {
    List<String> encryptedStartEndBytes = [];
    encryptedStartEndBytes
        .add(await encryptString(startEndBytes[i][0].toString()));
    encryptedStartEndBytes
        .add(await encryptString(startEndBytes[i][1].toString()));
    fileIndexLocation[encryptFileLocations[i]] = encryptedStartEndBytes;
  }

  fileIndexLocation["Description"] = await encryptString(fileDesc);

  for (int i = 0; i < keywords.length; i++) {
    final encryptedKeyword = await hashSha256(keywords[i]);

    index['files']!.putIfAbsent(encryptedKeyword, () => {});
    index["files"][encryptedKeyword]![encryptedFileName] = fileIndexLocation;
  }

  index["archive"].add(await hashSha256(fileName));

  JsonEncoder encoder = JsonEncoder.withIndent('  ');
  String indexJson = encoder.convert(index);

  await storage.write(key: "index", value: indexJson);
}

Future<Map> searchIndexKeyword(String keyword) async {
  String indexContents = await storage.read(key: "index") ?? emptyIndex;

  Map<String, dynamic> index = json.decode(indexContents);

  final encryptedKeyword = await hashSha256(keyword);

  final fileLocations = index['files'][encryptedKeyword];
  return fileLocations ?? {};
}

Future<void> deleteIndexFile(String encryptedFileName, String keyword) async {
  String indexContents = await storage.read(key: "index") ?? emptyIndex;
  Map<String, dynamic> index = json.decode(indexContents);
  final fileName = await decryptString(encryptedFileName);
  final archiveName = await hashSha256(fileName);
  final encryptedKeyword = await hashSha256(keyword);

  final fileMap = index['files']?[encryptedKeyword];
  fileMap.remove(encryptedFileName);

  if (fileMap.isEmpty) {
    index['files'].remove(encryptedKeyword);
  }

  final archiveMap = index["archive"];
  archiveMap.remove(archiveName);

  String indexJson = json.encode(index);
  await storage.write(key: "index", value: indexJson);

  await writeIndexCloud();
}

Future<void> createIndex() async {
  Map<String, dynamic> index = {"archive": [], "files": {}};

  String indexJson = json.encode(index);

  if (await storage.read(key: "index") == null) {
    await storage.write(key: "index", value: indexJson);
  }

  return;
}

Future<void> writeIndexCloud() async {
  final indexContents = await storage.read(key: "index");
  Map<String, dynamic> index = json.decode(indexContents!);
  JsonEncoder encoder = JsonEncoder.withIndent('  ');
  String indexJson = encoder.convert(index);
  final indexBytes = utf8.encode(indexJson);

  final cloud = await createCloudInstance();
  await cloud.deleteFile("index.json");
  await cloud.uploadFile(indexBytes, "index.json");
}

Future<void> readIndexCloud() async {
  final cloud = await createCloudInstance();

  if (await cloud.checkFileExists("index.json")) {
    final indexBytes = await cloud.downloadFile("index.json");
    final index = utf8.decode(indexBytes);
    await storage.write(key: "index", value: index);
  } else {
    await createIndex();
  }
}

Future<String> checkIndexArchive(String fileName) async {
  String indexContents = await storage.read(key: "index") ?? emptyIndex;
  Map<String, dynamic> index = json.decode(indexContents);
  final archiveFileList = List<String>.from(index['archive']);
  String encryptedFileName = await hashSha256(fileName);
  String newFileName = fileName;

  if (archiveFileList.contains(encryptedFileName)) {
    final RegExp regex = RegExp(r'^(.*?)(\((\d+)\))?(\.\w+)?$');
    final match = regex.firstMatch(fileName);

    String base = match?.group(1) ?? fileName;
    String ext = match?.group(4) ?? '';
    int counter =
        (match?.group(3) != null) ? int.parse(match!.group(3)!) + 1 : 1;

    while (archiveFileList.contains(await hashSha256('$base ($counter)$ext'))) {
      counter++;
    }

    newFileName = '$base ($counter)$ext';
  }

  return newFileName;
}
