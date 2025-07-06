import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography_plus/cryptography_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';

final fileAlgo = Xchacha20.poly1305Aead();
final stringAlgo = Xchacha20.poly1305Aead();
final blockSize = 20971520;
final fileNonceSize = 24;
final stringNonceSize = 24;
final keySize = 32;

Future<String> hashSha256(String unhashed) async {
  List<int> unhashedBytes = utf8.encode(unhashed);
  final storage = FlutterSecureStorage();
  final passwordString = await storage.read(key: 'encryption_password');
  final passwordHash = utf8.encode(passwordString!);
  final saltedBytes = <int>[...passwordHash, ...unhashedBytes];

  final sink = Sha256().newHashSink();
  sink.add(saltedBytes);
  sink.close();
  final hash = await sink.hash();
  final hashedBytes = hash.bytes;
  final hashedString = base64Url.encode(hashedBytes);

  return hashedString;
}

Future<List<int>> hashArgon(String unhashed) async {
  List<int> unhashedBytes = utf8.encode(unhashed);
  final salt = 'randomsalt';
  final nonce = utf8.encode(salt);

  final algorithm = Argon2id(
    parallelism: 1,
    memory: 20000,
    iterations: 2,
    hashLength: keySize,
  );

  final secretHash = await algorithm.deriveKey(
    secretKey: SecretKey(unhashedBytes),
    nonce: nonce,
  );

  final hashedBytes = await secretHash.extractBytes();

  return hashedBytes;
}

Future<String> createKey(String password) async {
  final hashedBytes = await hashArgon(password);
  final secretKey = base64.encode(hashedBytes);

  return secretKey;
}

Future<SecretKey> getKey() async {
  final storage = FlutterSecureStorage();
  final passwordString = await storage.read(key: 'encryption_password');
  final passwordHash = utf8.encode(passwordString!);
  final keyHash = passwordHash.sublist(0, keySize);
  final secretKey = SecretKey(keyHash);

  return secretKey;
}

Future<String> encryptString(String clearString) async {
  final secretKey = await getKey();

  final clearBytes = utf8.encode(clearString);

  List<int> nonce = stringAlgo.newNonce();

  final cipherTextBox =
      await stringAlgo.encrypt(clearBytes, secretKey: secretKey, nonce: nonce);

  List<int> cipherTextBytes = [];

  cipherTextBytes = cipherTextBox.concatenation();

  final encryptedString = base64Url.encode(cipherTextBytes);

  return encryptedString;
}

Future<String> decryptString(String encryptedString) async {
  final secretKey = await getKey();

  var encryptStringBytes = base64Url.decode(encryptedString);

  List<int> nonce = encryptStringBytes.sublist(0, fileNonceSize);
  List<int> ciphertext =
      encryptStringBytes.sublist(fileNonceSize, encryptStringBytes.length - 16);
  List<int> mac = encryptStringBytes.sublist(encryptStringBytes.length - 16);

  final decryptBox = SecretBox(ciphertext, nonce: nonce, mac: Mac(mac));

  final decryptedBytes =
      await stringAlgo.decrypt(decryptBox, secretKey: secretKey);

  final decryptedString = utf8.decode(decryptedBytes);

  return (decryptedString);
}

Future<List<int>> encryptFile(List<int> fileBytes) async {
  final secretKey = await getKey();

  final cipherTextBox = await fileAlgo.encrypt(
    fileBytes,
    secretKey: secretKey,
  );

  final concatenatedBytes = cipherTextBox.concatenation();

  return concatenatedBytes;
}

Future<List<int>> decryptFile(
    List<int> enclosedFileBytes, int numBytesStart, int numBytesEnd) async {
  final secretKey = await getKey();

  List<int> fileBytes = enclosedFileBytes.sublist(numBytesStart, numBytesEnd);

  List<int> nonce = fileBytes.sublist(0, fileNonceSize);
  List<int> ciphertext =
      fileBytes.sublist(fileNonceSize, fileBytes.length - 16);
  List<int> mac = fileBytes.sublist(fileBytes.length - 16);

  final secretBox = SecretBox(ciphertext, nonce: nonce, mac: Mac(mac));

  try {
    final clearText = await fileAlgo.decrypt(
      secretBox,
      secretKey: secretKey,
    );

    return clearText;
  } on Exception catch (error) {
    throw Exception('Decryption failed: $error');
  }
}

Future<List<int>> encloseFiles(
  List<int> encryptedFile,
  int numBytesAddBefore,
) async {
  List<int> bytesBefore = randomUint8List(numBytesAddBefore);
  List<int> bytesAfter =
      randomUint8List(blockSize - encryptedFile.length - numBytesAddBefore);

  final enclosedBytes = bytesBefore + encryptedFile + bytesAfter;

  return enclosedBytes;
}

Uint8List randomUint8List(int length) {
  final secureSeed = Random.secure().nextInt(1 << 32);
  final fastRandom = Random(secureSeed);

  final ret = Uint8List(length);
  for (var i = 0; i < length; i++) {
    ret[i] = fastRandom.nextInt(256);
  }
  return ret;
}
