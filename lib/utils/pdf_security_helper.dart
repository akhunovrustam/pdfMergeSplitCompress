import 'dart:io';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:path_provider/path_provider.dart';

class PdfSecurityHelper {
  /// Ensures the PDF at [path] is readable.
  /// If encrypted, prompts the user for a password via [context].
  /// Returns the path to the readable file (original or decrypted temp file).
  /// Returns null if the user cancels or description fails.
  static Future<String?> ensureReadable(
    BuildContext context,
    String path,
  ) async {
    // 1. Check if we can open it without password is risky/expensive to try-catch everywhere,
    // but Syncfusion's PdfDocument throws ArgumentError or PdfException if encrypted.

    try {
      final File file = File(path);
      final List<int> bytes = await file.readAsBytes();

      try {
        // Try opening to check security
        final PdfDocument doc = PdfDocument(inputBytes: bytes);
        doc.dispose();
        return path; // It's not encrypted (or at least readable without password)
      } catch (e) {
        // Only catch encryption related errors if possible,
        // but Syncfusion throws generically sometimes.
        // Assuming if it failed to open, it might be encrypted.
        return await _handleEncrypted(context, bytes, path);
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error reading file: $e')));
      return null;
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

      try {
        final PdfDocument document = PdfDocument(
          inputBytes: bytes,
          password: password,
        );

        // Decrypt to temp file
        // To allow other libs (pdfx, etc) to read it, we remove security settings
        document.security.ownerPassword = '';
        document.security.userPassword = '';

        final List<int> decryptedBytes = await document.save();
        document.dispose();

        final Directory tempDir = await getTemporaryDirectory();
        final String fileName = originalPath.split(Platform.pathSeparator).last;
        final String tempPath =
            '${tempDir.path}/unlocked_${DateTime.now().millisecondsSinceEpoch}_$fileName';

        final File tempFile = File(tempPath);
        await tempFile.writeAsBytes(decryptedBytes);

        return tempPath;
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid password or error decrypting.'),
          ),
        );
        // Loop again
      }
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
