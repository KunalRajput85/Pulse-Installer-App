import 'dart:io';

import 'package:crypto/crypto.dart';

/// SHA-256 hashing for duplicate-image detection (RM Pulse Section 7).
class Hashing {
  Hashing._();

  static Future<String> sha256OfFile(String path) async {
    final bytes = await File(path).readAsBytes();
    return sha256.convert(bytes).toString();
  }
}
