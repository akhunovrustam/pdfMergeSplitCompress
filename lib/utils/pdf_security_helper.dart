import 'dart:io';
import 'package:flutter/foundation.dart'; // for compute
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:path_provider/path_provider.dart';

class DecryptArguments {
  final List<int> bytes;
  final String password;
  DecryptArguments(this.bytes, this.password);
}

class PdfSecurityHelper {
  /// Ensures the PDF at [path] is readable.
  /// If encrypted, prompts the user for a password via [context].
  /// Returns the path to the readable file (original or decrypted temp file).
  /// Returns null if the user cancels or description fails.
  static Future<String?> ensureReadable(
    BuildContext context,
    String path,
  ) async {
    try {
      final File file = File(path);
      final List<int> bytes = await file.readAsBytes();

      // Run check in background
      final bool isEncrypted = await compute(_checkIfEncrypted, bytes);

      if (!isEncrypted) {
        return path;
      } else {
        return await _handleEncrypted(context, bytes, path);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error reading file: $e')));
      }
      return null;
    }
  }

  // Static method for compute
  static bool _checkIfEncrypted(List<int> bytes) {
    try {
      final PdfDocument doc = PdfDocument(inputBytes: bytes);
      doc.dispose();
      return false; // Readable without password
    } catch (e) {
      // Syncfusion throws if encrypted (or corrupt)
      return true;
    }
  }

  static Future<String?> _handleEncrypted(
    BuildContext context,
    List<int> bytes,
    String originalPath,
  ) async {
    while (true) {
      final String? password = await _showPasswordDialog(context);
      if (password == null) {
        return null; // User cancelled
      }

      // Run decryption in background
      try {
        final List<int>? decryptedBytes = await compute(
          _attemptDecrypt,
          DecryptArguments(bytes, password),
        );

        if (decryptedBytes == null) {
          throw Exception("Decryption failed");
        }

        final Directory tempDir = await getTemporaryDirectory();
        final String fileName = originalPath.split(Platform.pathSeparator).last;
        final String tempPath =
            '${tempDir.path}/unlocked_${DateTime.now().millisecondsSinceEpoch}_$fileName';

        final File tempFile = File(tempPath);
        await tempFile.writeAsBytes(decryptedBytes);

        return tempPath;
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Invalid password or error decrypting.'),
            ),
          );
        }
        // Loop again
      }
    }
  }

  // Static method for compute
  static Future<List<int>?> _attemptDecrypt(DecryptArguments args) async {
    try {
      final PdfDocument document = PdfDocument(
        inputBytes: args.bytes,
        password: args.password,
      );

      // Decrypt to temp file
      document.security.ownerPassword = '';
      document.security.userPassword = '';

      final List<int> decryptedBytes = await document.save();
      document.dispose();
      return decryptedBytes;
    } catch (e) {
      return null;
    }
  }

  static Future<String?> _showPasswordDialog(BuildContext context) async {
    final TextEditingController controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Encrypted PDF'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'This file is password protected. Please enter the password to proceed.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Password',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (val) => Navigator.pop(context, val),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Unlock'),
          ),
        ],
      ),
    );
  }
}
