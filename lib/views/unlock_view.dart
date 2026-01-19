import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class UnlockPdfView extends StatefulWidget {
  @override
  _UnlockPdfViewState createState() => _UnlockPdfViewState();
}

class _UnlockPdfViewState extends State<UnlockPdfView> {
  String? _selectedFilePath;
  final TextEditingController _passwordController = TextEditingController();
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

  Future<void> _unlockPdf() async {
    if (_selectedFilePath == null) {
      setState(() {
        _statusMessage = 'Please select a PDF file first.';
      });
      return;
    }
    if (_passwordController.text.isEmpty) {
      setState(() {
        _statusMessage = 'Password is required to open the locked file.';
      });
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Unlocking...';
    });

    try {
      // 1. Load the existing PDF document with the password.
      final File inputHtmlFile = File(_selectedFilePath!);
      final List<int> bytes = await inputHtmlFile.readAsBytes();

      // Attempt to load with password
      final PdfDocument document = PdfDocument(
        inputBytes: bytes,
        password: _passwordController.text,
      );

      // 2. Remove security settings.
      // Setting these to empty string removes the password protection.
      document.security.userPassword = '';
      document.security.ownerPassword = '';

      // 3. Save the unlocked document.
      final List<int> unlockedBytes = await document.save();
      document.dispose();

      // 4. Prompt user to choose a directory to save the file.
      final String? directoryPath = await getDirectoryPath();

      if (directoryPath != null) {
        final String fileName =
            'unlocked_${inputHtmlFile.uri.pathSegments.last}';
        final String savePath = '$directoryPath/$fileName';
        final File outputFile = File(savePath);
        await outputFile.writeAsBytes(unlockedBytes);
        setState(() {
          _statusMessage = 'PDF unlocked and saved to:\n$savePath';
        });
      } else {
        setState(() {
          _statusMessage = 'Save cancelled.';
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage =
            'Error unlocking PDF: $e\n(Check if password is correct)';
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
      appBar: AppBar(title: const Text('Unlock PDF')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // File Selection
            ElevatedButton.icon(
              onPressed: _pickFile,
              icon: const Icon(Icons.lock_open),
              label: const Text('Select Encrypted PDF'),
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

            // Password Input
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(
                labelText: 'Document Password',
                border: OutlineInputBorder(),
                helperText: 'Enter the password to remove protection',
              ),
              obscureText: true,
            ),
            const SizedBox(height: 32),

            // Action Button
            ElevatedButton(
              onPressed: _isProcessing ? null : _unlockPdf,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green, // Distinct color for unlock
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isProcessing
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Unlock & Save PDF'),
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
