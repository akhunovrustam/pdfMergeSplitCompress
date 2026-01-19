import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class EncryptPdfView extends StatefulWidget {
  @override
  _EncryptPdfViewState createState() => _EncryptPdfViewState();
}

class _EncryptPdfViewState extends State<EncryptPdfView> {
  String? _selectedFilePath;
  final TextEditingController _userPasswordController = TextEditingController();
  final TextEditingController _ownerPasswordController =
      TextEditingController();
  bool _isProcessing = false;
  String? _statusMessage;

  Future<void> _pickFile() async {
    const XTypeGroup typeGroup = XTypeGroup(
      label: 'PDFs',
      extensions: <String>['pdf'],
    );
    final XFile? file = await openFile(
      acceptedTypeGroups: <XTypeGroup>[typeGroup],
    );
    if (file != null) {
      setState(() {
        _selectedFilePath = file.path;
        _statusMessage = null;
      });
    }
  }

  Future<void> _encryptPdf() async {
    if (_selectedFilePath == null) {
      setState(() {
        _statusMessage = 'Please select a PDF file first.';
      });
      return;
    }
    if (_userPasswordController.text.isEmpty) {
      setState(() {
        _statusMessage = 'User password is required.';
      });
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Encrypting...';
    });

    try {
      // 1. Load the existing PDF document.
      final File inputHtmlFile = File(_selectedFilePath!);
      final List<int> bytes = await inputHtmlFile.readAsBytes();
      final PdfDocument document = PdfDocument(inputBytes: bytes);

      // 2. Set the security settings.
      final PdfSecurity security = document.security;
      security.userPassword = _userPasswordController.text;
      if (_ownerPasswordController.text.isNotEmpty) {
        security.ownerPassword = _ownerPasswordController.text;
      }
      // Using RC4 128 bit as a standard compatible encryption. available options in syncfusion generally include rc4x40Bit, rc4x128Bit, aes.
      security.algorithm = PdfEncryptionAlgorithm.rc4x128Bit;

      // 3. Save the encrypted document.
      final List<int> encryptedBytes = await document.save();
      document.dispose();

      // 4. Prompt user to choose a directory to save the file.
      final String? directoryPath = await getDirectoryPath();

      if (directoryPath != null) {
        final String fileName =
            'encrypted_${inputHtmlFile.uri.pathSegments.last}';
        final String savePath = '$directoryPath/$fileName';
        final File outputFile = File(savePath);
        await outputFile.writeAsBytes(encryptedBytes);
        setState(() {
          _statusMessage = 'PDF encrypted and saved to:\n$savePath';
        });
      } else {
        setState(() {
          _statusMessage = 'Save cancelled.';
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Error encrypting PDF: $e';
      });
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Encrypt PDF')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // File Selection
            ElevatedButton.icon(
              onPressed: _pickFile,
              icon: const Icon(Icons.file_open),
              label: const Text('Select PDF File'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            const SizedBox(height: 12),
            if (_selectedFilePath != null)
              Text(
                'Selected: $_selectedFilePath',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            const SizedBox(height: 24),

            // Password Inputs
            TextField(
              controller: _userPasswordController,
              decoration: const InputDecoration(
                labelText: 'User Password (Required)',
                border: OutlineInputBorder(),
                helperText: 'Password needed to open the file',
              ),
              obscureText: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _ownerPasswordController,
              decoration: const InputDecoration(
                labelText: 'Owner Password (Optional)',
                border: OutlineInputBorder(),
                helperText: 'Password needed to change permissions',
              ),
              obscureText: true,
            ),
            const SizedBox(height: 32),

            // Action Button
            ElevatedButton(
              onPressed: _isProcessing ? null : _encryptPdf,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isProcessing
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Encrypt PDF'),
            ),

            // Status Message
            if (_statusMessage != null) ...[
              const SizedBox(height: 24),
              Text(
                _statusMessage!,
                style: TextStyle(
                  color: _statusMessage!.startsWith('Error')
                      ? Colors.red
                      : Colors.green,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
