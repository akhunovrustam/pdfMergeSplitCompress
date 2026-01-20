import 'dart:io';
import 'package:flutter/foundation.dart'; // for compute
import 'package:flutter_pdf/services/pdf_service.dart';
import 'package:flutter_pdf/utils/ui_utils.dart';
import 'package:open_filex/open_filex.dart';
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

    final String? outPath = await getDirectoryPath();
    if (outPath == null) {
      setState(() {
        _statusMessage = 'Save cancelled.';
      });
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Unlocking...';
    });
    LoadingOverlay.show(context);

    try {
      final File inputHtmlFile = File(_selectedFilePath!);
      final String fileName = 'unlocked_${inputHtmlFile.uri.pathSegments.last}';
      final String savePath = '$outPath/$fileName';

      final args = UnlockArguments(
        path: _selectedFilePath!,
        password: _passwordController.text,
        outPath: savePath,
      );

      await compute(PdfService.unlockPdf, args);

      if (mounted) {
        setState(() {
          _statusMessage = 'PDF unlocked and saved to:\n$savePath';
          _isProcessing = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Saved to $savePath')));
        await OpenFilex.open(savePath);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage =
              'Error unlocking PDF: $e\n(Check if password is correct)';
        });
      }
    } finally {
      if (mounted) LoadingOverlay.hide(context);
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
