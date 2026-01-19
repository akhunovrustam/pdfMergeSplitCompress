import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:image/image.dart' as img;
import 'package:flutter_pdf/utils/pdf_security_helper.dart';

class CompressView extends StatefulWidget {
  const CompressView({Key? key}) : super(key: key);

  @override
  State<CompressView> createState() => _CompressViewState();
}

class _CompressViewState extends State<CompressView> {
  XFile? _selectedFile;
  bool _busy = false;

  // Default to rasterize for visible savings
  bool _rasterize = true;

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
      final String? readablePath = await PdfSecurityHelper.ensureReadable(
        context,
        file.path,
      );
      if (readablePath == null) return;

      setState(() => _selectedFile = XFile(readablePath, name: file.name));
    }
  }

  Future<Directory> _downloadsDir() async {
    final d = await getDownloadsDirectory();
    if (d != null) return d;

    // Android common Downloads fallback
    final androidDownloads = Directory('/storage/emulated/0/Download');
    if (await androidDownloads.exists()) return androidDownloads;

    return await getApplicationDocumentsDirectory();
  }

  // --- Helpers ---------------------------------------------------------------

  Future<File> _writeOut(Uint8List bytes, String outPath) async {
    final f = File(outPath);
    await f.writeAsBytes(bytes, flush: true);
    return f;
  }

  Future<void> _finalizeResult({
    required int inputSize,
    required File tentativeOut,
    required String originalPath,
    required String prettyOutPath,
    required Future<void> Function() onOpen,
    double requireImprovement = 0.98, // must be <= 98% of original (2%+ better)
  }) async {
    final outSize = await tentativeOut.length();

    // If not smaller enough, keep original instead
    if (outSize >= (inputSize * requireImprovement)) {
      final originalBytes = await File(originalPath).readAsBytes();
      await tentativeOut.writeAsBytes(originalBytes, flush: true);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 5),
          content: Text(
            'No size improvement; original kept:\n$prettyOutPath\n'
            'Size: ${(inputSize / 1024).toStringAsFixed(1)} KB',
          ),
        ),
      );
      await onOpen();
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 5),
        content: Text(
          'Saved to:\n$prettyOutPath\n'
          'Size: ${(inputSize / 1024).toStringAsFixed(1)} KB → ${(outSize / 1024).toStringAsFixed(1)} KB',
        ),
      ),
    );
    await onOpen();
  }

  // --- SAFE MODE (keep text) ------------------------------------------------

  Future<File> _compressSafeOnce(String inPath) async {
    final inputBytes = await File(inPath).readAsBytes();
    final doc = sf.PdfDocument(inputBytes: inputBytes);

    // Internal stream compression
    doc.compressionLevel = sf.PdfCompressionLevel.best;
    doc.fileStructure.incrementalUpdate = false;

    final outBytesList = doc.saveSync(); // List<int>
    doc.dispose();

    final outBytes = Uint8List.fromList(outBytesList);
    final downloads = await _downloadsDir();
    final base = _selectedFile!.name.replaceAll(
      RegExp(r'\.pdf$', caseSensitive: false),
      '',
    );
    final outPath = '${downloads.path}/${base}_compressed_safe.pdf';
    return _writeOut(outBytes, outPath);
  }

  // --- RASTER MODE (max shrink) --------------------------------------------

  Future<File> _compressRasterOnce({
    required String inPath,
    required double scale,
    required int jpeg,
    required String suffix,
  }) async {
    final pdfDoc = await pdfx.PdfDocument.openFile(inPath);
    final outDoc = sf.PdfDocument();

    outDoc.fileStructure.incrementalUpdate = false;

    // Process page-by-page to avoid OOM
    for (int i = 1; i <= pdfDoc.pagesCount; i++) {
      final page = await pdfDoc.getPage(i);
      final rendered = await page.render(
        width: page.width * scale,
        height: page.height * scale,
        format: pdfx.PdfPageImageFormat.png, // good input for re-encode
      );
      await page.close();

      if (rendered == null) continue;

      final decoded = img.decodeImage(rendered.bytes);
      if (decoded == null) continue;

      // JPEG re-encode
      final jpgBytes = img.encodeJpg(decoded, quality: jpeg);

      final newPage = outDoc.pages.add();
      newPage.graphics.drawImage(
        sf.PdfBitmap(Uint8List.fromList(jpgBytes)),
        Rect.fromLTWH(0, 0, newPage.size.width, newPage.size.height),
      );
    }

    final outBytesList = outDoc.saveSync(); // List<int>
    outDoc.dispose();
    final outBytes = Uint8List.fromList(outBytesList);

    final downloads = await _downloadsDir();
    final base = _selectedFile!.name.replaceAll(
      RegExp(r'\.pdf$', caseSensitive: false),
      '',
    );
    final outPath =
        '${downloads.path}/${base}_compressed_${suffix.toLowerCase()}.pdf';
    return _writeOut(outBytes, outPath);
  }

  // Orchestrates compression with auto-fallback if not smaller
  Future<void> _onCompressTap(Map<String, Object> level) async {
    if (_selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a PDF first')),
      );
      return;
    }

    setState(() => _busy = true);

    final inPath = _selectedFile!.path;
    final inFile = File(inPath);
    final inSize = await inFile.length();

    try {
      if (_rasterize) {
        final label = level['label'] as String;
        double scale = level['scale'] as double;
        int jpeg = level['jpeg'] as int;

        // First attempt with requested settings
        File outFile = await _compressRasterOnce(
          inPath: inPath,
          scale: scale,
          jpeg: jpeg,
          suffix: label,
        );

        int outSize = await outFile.length();
        // If not reduced at least ~2%, try stronger once
        if (outSize >= (inSize * 0.98)) {
          scale = (scale * 0.9).clamp(0.2, 1.0);
          jpeg = (jpeg - 10).clamp(40, 95);
          outFile = await _compressRasterOnce(
            inPath: inPath,
            scale: scale,
            jpeg: jpeg,
            suffix: '${label}_strong',
          );
        }

        final prettyOutPath = outFile.path;
        await _finalizeResult(
          inputSize: inSize,
          tentativeOut: outFile,
          originalPath: inPath,
          prettyOutPath: prettyOutPath,
          onOpen: () async => OpenFilex.open(outFile.path),
        );
      } else {
        // SAFE MODE
        File outFile = await _compressSafeOnce(inPath);

        // If not smaller, attempt a raster fallback with gentle settings
        int outSize = await outFile.length();
        if (outSize >= (inSize * 0.98)) {
          outFile = await _compressRasterOnce(
            inPath: inPath,
            scale: 0.9,
            jpeg: 85,
            suffix: 'safe_fallback',
          );
        }

        final prettyOutPath = outFile.path;
        await _finalizeResult(
          inputSize: inSize,
          tentativeOut: outFile,
          originalPath: inPath,
          prettyOutPath: prettyOutPath,
          onOpen: () async => OpenFilex.open(outFile.path),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Compression failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
                      style: const TextStyle(fontSize: 16),
                    ),

                    const SizedBox(height: 16),
                    // Mode toggle
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            selected: !_rasterize,
                            label: const Text('Keep text (safe)'),
                            onSelected: (v) => setState(() => _rasterize = !v),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ChoiceChip(
                            selected: _rasterize,
                            label: const Text('Max shrink (rasterize)'),
                            onSelected: (v) => setState(() => _rasterize = v),
                          ),
                        ),
                      ],
                    ),

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
