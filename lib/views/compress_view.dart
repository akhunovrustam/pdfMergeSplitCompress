import 'dart:io';
import 'dart:math'; // For file size formatting

import 'package:flutter/services.dart'; // For RootIsolateToken
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:flutter/foundation.dart'; // for compute
import 'package:flutter_pdf/services/pdf_service.dart';
import 'package:flutter_pdf/utils/pdf_security_helper.dart';
import 'package:flutter_pdf/utils/ui_utils.dart';

class CompressView extends StatefulWidget {
  const CompressView({Key? key}) : super(key: key);

  @override
  State<CompressView> createState() => _CompressViewState();
}

class _CompressViewState extends State<CompressView> {
  XFile? _selectedFile;
  String? _fileSizeString;
  bool _busy = false;

  // Levels for raster mode
  static const _levels = [
    {'label': 'Low', 'scale': 0.85, 'jpeg': 82},
    {'label': 'Recommended', 'scale': 0.65, 'jpeg': 70},
    {'label': 'Extreme', 'scale': 0.35, 'jpeg': 50},
  ];

  Future<void> _pickFile() async {
    final file = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(label: 'PDF', extensions: ['pdf']),
      ],
    );
    if (file != null) {
      final size = await File(file.path).length();

      final String? readablePath = await PdfSecurityHelper.ensureReadable(
        context,
        file.path,
      );
      if (readablePath == null) return;

      setState(() {
        _selectedFile = XFile(readablePath, name: file.name);
        _fileSizeString = _formatBytes(size);
      });
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(2)} ${suffixes[i]}';
  }

  Future<Directory> _downloadsDir() async {
    final d = await getDownloadsDirectory();
    if (d != null) return d;

    // Android common Downloads fallback
    final androidDownloads = Directory('/storage/emulated/0/Download');
    if (await androidDownloads.exists()) return androidDownloads;

    return await getApplicationDocumentsDirectory();
  }

  // --- SAFE MODE (keep text) ------------------------------------------------

  // Orchestrates compression with auto-fallback if not smaller
  Future<void> _onCompressTap(Map<String, Object> level) async {
    if (_selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a PDF first')),
      );
      return;
    }

    setState(() => _busy = true);
    LoadingOverlay.show(context);

    final inPath = _selectedFile!.path;
    final inFile = File(inPath);
    final inSize = await inFile.length();

    try {
      // Always Rasterize
      final label = level['label'] as String;
      double scale = level['scale'] as double;
      int jpeg = level['jpeg'] as int;

      // Prepare temp output path
      final downloads = await _downloadsDir();
      final base = _selectedFile!.name.replaceAll(
        RegExp(r'\.pdf$', caseSensitive: false),
        '',
      );
      final suffix = '_${label.toLowerCase()}';
      final outPath = '${downloads.path}/${base}_compressed$suffix.pdf';

      // First attempt
      await compute(
        PdfService.compressRaster,
        CompressRasterArguments(
          path: inPath,
          scale: scale,
          quality: jpeg,
          outPath: outPath,
          token: RootIsolateToken.instance!,
        ),
      );

      // Check size
      File outFile = File(outPath);
      int outSize = await outFile.length();

      if (outSize >= (inSize * 0.98)) {
        // Try stronger
        scale = (scale * 0.9).clamp(0.2, 1.0);
        jpeg = (jpeg - 10).clamp(40, 95);

        await compute(
          PdfService.compressRaster,
          CompressRasterArguments(
            path: inPath,
            scale: scale,
            quality: jpeg,
            outPath: outPath,
            token: RootIsolateToken.instance!,
          ),
        );
        outSize = await outFile.length();
      }

      await _showResult(outPath, inSize, outSize);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Compression failed: $e')));
    } finally {
      if (mounted) {
        LoadingOverlay.hide(context);
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _showResult(
    String outPath,
    int originalSize,
    int newSize,
  ) async {
    // If result is bigger/same, keep original (well, we already saved it, but we can warn user)
    if (newSize >= (originalSize * 0.98)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No size improvement.\nOriginal: ${(originalSize / 1024).toStringAsFixed(1)} KB',
          ),
        ),
      );
      // Optional: Delete the larger file? User might want to keep it anyway.
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 5),
        content: Text(
          'Saved to:\n$outPath\n'
          'Size: ${(originalSize / 1024).toStringAsFixed(1)} KB → ${(newSize / 1024).toStringAsFixed(1)} KB',
        ),
      ),
    );
    await OpenFilex.open(outPath);
  }

  @override
  Widget build(BuildContext context) {
    final fileName = _selectedFile?.name;

    return Scaffold(
      appBar: AppBar(title: const Text('Compress PDF')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: _busy
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Select / Change PDF (always visible)
                  ElevatedButton(
                    onPressed: _pickFile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(fileName == null ? 'Select PDF' : 'Change PDF'),
                  ),

                  if (fileName != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Selected: $fileName',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_fileSizeString != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('Size: $_fileSizeString'),
                      ),

                    const SizedBox(height: 16),

                    const SizedBox(height: 20),
                    // Equal-width buttons: Low -> Recommended -> Extreme
                    Row(
                      children: [
                        for (int i = 0; i < _levels.length; i++) ...[
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => _onCompressTap(_levels[i]),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: i == 0
                                    ? Colors.blue
                                    : i == 1
                                    ? Colors.orange
                                    : Colors.red,
                                foregroundColor: Colors.white,
                              ),
                              child: Text(_levels[i]['label'] as String),
                            ),
                          ),
                          if (i != _levels.length - 1)
                            const SizedBox(width: 12),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
