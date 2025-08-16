// lib/views/split_view.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

class SplitView extends StatefulWidget {
  const SplitView({Key? key}) : super(key: key);

  @override
  State<SplitView> createState() => _SplitViewState();
}

class _SplitViewState extends State<SplitView> {
  XFile? _pdfFile;
  pdfx.PdfDocument? _doc;
  int _pageCount = 0;

  // Cache thumbnails: pageIndex -> bytes
  final Map<int, Future<Uint8List?>> _thumbCache = {};
  // Selected pages (1-based indices, to be user-friendly)
  final Set<int> _selected = {};

  // --- Pick a PDF ---
  Future<void> _pickPdf() async {
    final file = await openFile(
      acceptedTypeGroups: [XTypeGroup(label: 'PDF', extensions: ['pdf'])],
    );
    if (file == null) return;

    // Close any previous document
    await _doc?.close();

    final doc = await pdfx.PdfDocument.openFile(file.path);
    setState(() {
      _pdfFile = file;
      _doc = doc;
      _pageCount = doc.pagesCount;
      _thumbCache.clear();
      _selected.clear();
    });
  }

  // --- Render a page thumbnail once and cache it ---
  Future<Uint8List?> _renderThumb(int pageNumber) {
    return _thumbCache.putIfAbsent(pageNumber, () async {
      final page = await _doc!.getPage(pageNumber);
      final img = await page.render(
        width: 220,      // render a bit bigger, we’ll fit it down
        height: 300,
        format: pdfx.PdfPageImageFormat.jpeg,
      );
      await page.close();
      return img?.bytes;
    });
  }

  // --- Save selected pages into a single new PDF ---
  Future<void> _splitSelected() async {
    if (_pdfFile == null || _selected.isEmpty) return;

    final bytes = await _pdfFile!.readAsBytes();
    final input = sf.PdfDocument(inputBytes: bytes);
    final output = sf.PdfDocument();

    // Keep selection order
    final pages = _selected.toList()..sort();

    for (final pageNumber in pages) {
      final srcPage = input.pages[pageNumber - 1];
      final template = srcPage.createTemplate();

      // Add page and draw the template at (0,0)
      final newPage = output.pages.add();
      newPage.graphics.drawPdfTemplate(template, const Offset(0, 0));
    }

    final outBytes = output.saveSync();
    input.dispose();
    output.dispose();

    final downloads = await _getDownloadsDir();
    final outPath = '${downloads.path}/${_baseName(_pdfFile!.name)}_split.pdf';
    final f = File(outPath);
    await f.writeAsBytes(outBytes, flush: true);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved to: $outPath')),
    );

    await OpenFilex.open(outPath);
  }

  // --- Helpers ---
  Future<Directory> _getDownloadsDir() async {
    try {
      if (Platform.isAndroid) {
        final d = Directory('/storage/emulated/0/Download');
        if (await d.exists()) return d;
        final ext = await getExternalStorageDirectory();
        return ext ?? await getApplicationDocumentsDirectory();
      } else {
        final d = await getDownloadsDirectory();
        return d ?? await getApplicationDocumentsDirectory();
      }
    } catch (_) {
      return await getApplicationDocumentsDirectory();
    }
  }

  String _baseName(String name) {
    final i = name.lastIndexOf('.');
    return i > 0 ? name.substring(0, i) : name;
  }

  void _toggle(int page) {
    setState(() {
      if (_selected.contains(page)) {
        _selected.remove(page);
      } else {
        _selected.add(page);
      }
    });
  }

  void _selectAll() {
    setState(() {
      _selected
        ..clear()
        ..addAll(List<int>.generate(_pageCount, (i) => i + 1));
    });
  }

  void _clearSelection() {
    setState(() => _selected.clear());
  }

  @override
  void dispose() {
    _doc?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSplit = _pdfFile != null && _selected.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Split PDF'),
        actions: [
          if (_pdfFile != null) ...[
            IconButton(
              tooltip: 'Select all',
              icon: const Icon(Icons.select_all),
              onPressed: _selectAll,
            ),
            IconButton(
              tooltip: 'Clear selection',
              icon: const Icon(Icons.clear_all),
              onPressed: _clearSelection,
            ),
          ],
        ],
      ),
      body: _pdfFile == null
          ? const Center(child: Text('Pick a PDF to start.'))
          : GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 3 / 4, // portrait thumbnail
              ),
              itemCount: _pageCount,
              itemBuilder: (context, i) {
                final page = i + 1;
                final selected = _selected.contains(page);
                return InkWell(
                  onTap: () => _toggle(page),
                  child: Stack(
                    children: [
                      // Card with thumbnail
                      Positioned.fill(
                        child: Card(
                          elevation: selected ? 6 : 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(
                              color: selected
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: FutureBuilder<Uint8List?>(
                            future: _renderThumb(page),
                            builder: (context, snap) {
                              if (snap.connectionState ==
                                  ConnectionState.waiting) {
                                return const Center(
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                );
                              }
                              if (!snap.hasData || snap.data == null) {
                                return const Center(child: Icon(Icons.picture_as_pdf));
                              }
                              return Image.memory(
                                snap.data!,
                                fit: BoxFit.cover,
                              );
                            },
                          ),
                        ),
                      ),
                      // Page number badge
                      Positioned(
                        left: 6,
                        top: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '$page',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12),
                          ),
                        ),
                      ),
                      // Check icon when selected
                      if (selected)
                        const Positioned(
                          right: 6,
                          top: 6,
                          child: Icon(Icons.check_circle,
                              color: Colors.lightGreenAccent),
                        ),
                    ],
                  ),
                );
              },
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Row(
            children: [
              // Left half: Split (only if canSplit), keep slot so Add remains right
              Expanded(
                child: canSplit
                    ? ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange.shade600,
                        ),
                        onPressed: _splitSelected,
                        icon: const Icon(Icons.call_split),
                        label: Text('Split (${_selected.length})'),
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(width: 12),
              // Right half: Add/Open (always visible)
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                  ),
                  onPressed: _pickPdf,
                  icon: const Icon(Icons.folder_open),
                  label: Text(_pdfFile == null ? 'Open PDF' : 'Change PDF'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
