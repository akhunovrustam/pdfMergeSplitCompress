import 'dart:io';
import 'package:flutter/foundation.dart'; // for compute
import 'package:flutter_pdf/services/pdf_service.dart';
import 'package:flutter_pdf/utils/ui_utils.dart';
import 'package:open_filex/open_filex.dart';
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

    final String? outPath = await getDirectoryPath();
    if (outPath == null) {
      setState(() {
        _statusMessage = 'Save cancelled.';
      });
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Encrypting...';
    });
    LoadingOverlay.show(context);

    try {
      final File inputHtmlFile = File(_selectedFilePath!);
      final String fileName =
          'encrypted_${inputHtmlFile.uri.pathSegments.last}';
      final String savePath = '$outPath/$fileName';

      final encryptArgs = EncryptArguments(
        path: _selectedFilePath!,
        userPassword: _userPasswordController.text,
        ownerPassword: _ownerPasswordController.text,
        outPath: savePath,
      );

      await compute(PdfService.encryptPdf, encryptArgs);

      if (mounted) {
        setState(() {
          _statusMessage = 'PDF encrypted and saved to:\n$savePath';
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
          _statusMessage = 'Error encrypting PDF: $e';
        });
      }
    } finally {
      if (mounted) {
        LoadingOverlay.hide(context);
        setState(() {
          _isProcessing = false;
        });
      }
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
