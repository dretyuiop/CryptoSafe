import 'package:cryptosafe/data/cloud/cloud_drive.dart';
import 'package:cryptosafe/business/crypto/crypt.dart';
import 'package:cryptosafe/business/crypto/index.dart';
import 'dart:math';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

Future<void> addFileToRepo(String fileName, String filePath,
    List<String> keywords, String description) async {
  final cloud = await createCloudInstance();
  final file = File(filePath);
  if (!await file.exists()) {
    throw FileSystemException("File not found", filePath);
  }

  final fileLength = await file.length() + 40;
  final fileStream = file.openRead();

  List<String> encryptedBlockNames = [];
  List<List<int>> startEndBytes = [];
  int fileNum = 1;

  final newFileName = await checkIndexArchive(fileName);

  int targetblockSize = fileLength;

  if (fileLength > (blockSize * 0.95)) {
    fileNum = (fileLength / (blockSize * 0.95)).ceil() + 1;
    targetblockSize = (fileLength / fileNum).floor();
  }

  final random = Random.secure();
  final uuid = Uuid();
  List<int> buffer = [];


  await for (final List<int> streamblock in fileStream) {
    buffer.addAll(streamblock);

    while (buffer.length >= targetblockSize) {

      final rawblock = buffer.sublist(0, targetblockSize);
      buffer = buffer.sublist(targetblockSize);

      final encryptedblock = await encryptFile(rawblock);

      int emptySpace = blockSize - encryptedblock.length;
      final startByte = (emptySpace > 0) ? random.nextInt(emptySpace) : 0;
      final endByte = startByte + encryptedblock.length;

      final enclosedBytes = await encloseFiles(encryptedblock, startByte);

      startEndBytes.add([startByte, endByte]);

      final blockName = uuid.v4();
      final encryptedBlockName = await encryptString(blockName);
      encryptedBlockNames.add(encryptedBlockName);

      await cloud.uploadFile(enclosedBytes, blockName);
    }
  }

  if (buffer.isNotEmpty) {
    final rawblock = buffer;

    final encryptedblock = await encryptFile(rawblock);

    int emptySpace = blockSize - encryptedblock.length;
    final startByte = random.nextInt(emptySpace);
    final endByte = startByte + encryptedblock.length;

    final enclosedBytes = await encloseFiles(encryptedblock, startByte);

    startEndBytes.add([startByte, endByte]);

    final blockName = uuid.v4();

    final encryptedBlockName = await encryptString(blockName);

    encryptedBlockNames.add(encryptedBlockName);

    await cloud.uploadFile(enclosedBytes, blockName);
  }

  await addDocIndex(
    newFileName,
    keywords,
    encryptedBlockNames,
    startEndBytes,
    description,
  );
  await writeIndexCloud();

}

Future<Map<String, dynamic>> searchFilesFromRepo(String keyword) async {
  final cloud = await createCloudInstance();
  final keywordMap = await searchIndexKeyword(keyword);
  final Map<String, dynamic> resultFiles = {};

  final futures = keywordMap.entries.map((entry) async {
    final encryptedFileName = entry.key;
    final fileInfoMap = entry.value;

    if (fileInfoMap.length <= 1) return null;

    final encryptedFileLocation = fileInfoMap.keys.firstWhere(
      (key) => key != "Description",
      orElse: () => '',
    );

    if (encryptedFileLocation.isEmpty) return null;

    try {
      final blockName = await decryptString(encryptedFileLocation);
      final fileExists = await cloud.checkFileExists(blockName);

      if (!fileExists) {
        await deleteIndexFile(encryptedFileName, keyword);
        return null;
      }

      final decryptedFileName = await decryptString(encryptedFileName);
      final encryptedDescription = fileInfoMap["Description"];
      final decryptedDescription = await decryptString(encryptedDescription);

      return MapEntry(
          decryptedFileName, [decryptedDescription, encryptedFileName]);
    } catch (e) {
      print("Error processing file entry: $e");
      return null;
    }
  });

  final results = await Future.wait(futures);
  for (final entry in results) {
    if (entry != null) {
      resultFiles[entry.key] = entry.value;
    }
  }

  return resultFiles;
}

Future<Map<String, dynamic>> searchFilesFromRepoMultiKey(
    List<String> keywords) async {
  final filesList = await Future.wait(
    keywords.map((keyword) => searchFilesFromRepo(keyword)),
  );

  Set<String> commonKeys = filesList
      .map((map) => map.keys.toSet())
      .reduce((a, b) => a.intersection(b));

  final intersectFiles = Map.fromEntries(
    filesList.first.entries.where((entry) => commonKeys.contains(entry.key)),
  );

  return intersectFiles;
}

Future<String> getFilesFromRepo(
    String encryptedFileName, String keyword) async {
  final cloud = await createCloudInstance();
  final prefs = await SharedPreferences.getInstance();
  final downloadDirectory = prefs.getString('download_directory');
  final fileName = decryptString(encryptedFileName);

  final keywordMap = await searchIndexKeyword(keyword);
  final Map<String, dynamic>? fileLocations = keywordMap[encryptedFileName];

  if (fileLocations == null || fileLocations.isEmpty) {
    throw Exception("File not found or no locations associated with keyword.");
  }

  final String outputPath = '${downloadDirectory!}/$fileName';
  final File outputFile = File(outputPath);
  final IOSink sink = outputFile.openWrite();


  try {
    for (final entry in fileLocations.entries) {
      final encryptedBlockName = entry.key;

      if (encryptedBlockName == "Description") {
        continue;
      }

      final blockName = await decryptString(encryptedBlockName);
      final bounds = entry.value;

      final int startByte = int.parse(await decryptString(bounds[0]));
      final int endByte = int.parse(await decryptString(bounds[1]));

      final enclosedblock = await cloud.downloadFile(blockName);

      final List<int> decryptedblock =
          await decryptFile(enclosedblock, startByte, endByte);

      sink.add(decryptedblock);
    }
  } catch (e) {
    if (await outputFile.exists()) {
      await outputFile.delete();
    }
    rethrow;
  } finally {
    await sink.close();
  }

  return outputPath;
}

Future<void> deleteFilesFromRepo(
    String encryptedFileName, String keyword) async {
  final cloud = await createCloudInstance();

  final keywordMap = await searchIndexKeyword(keyword);
  Map<String, dynamic> fileMap = keywordMap[encryptedFileName];
  String blockName;

  for (var encryptedBlockName in fileMap.keys) {
    if (encryptedBlockName == "Description") {
      continue;
    }
    blockName = await decryptString(encryptedBlockName.toString());
    cloud.deleteFile("/$blockName");
  }
}
