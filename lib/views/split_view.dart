// lib/views/split_view.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_pdf/services/pdf_service.dart';

import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:pdfx/pdfx.dart' as pdfx;
// import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:flutter_pdf/utils/pdf_security_helper.dart';
import 'package:flutter_pdf/utils/ui_utils.dart';

class SplitView extends StatefulWidget {
  const SplitView({Key? key}) : super(key: key);

  @override
  State<SplitView> createState() => _SplitViewState();
}

class _SplitViewState extends State<SplitView> {
  XFile? _pdfFile;
  pdfx.PdfDocument? _doc;
  int _pageCount = 0;

  // Thumbnails cache: pageIndex(1-based) -> bytes future
  final Map<int, Future<Uint8List?>> _thumbCache = {};

  // Current selected pages (1-based)
  final Set<int> _selected = {};

  // Selection snapshot taken when pressing "Start range"
  Set<int> _baseSelection = {};

  // For showing "Start range" on last tapped page (when not in range mode)
  int? _lastTappedPage;

  // Range-selection state
  bool _rangeSelecting = false;
  int? _rangeStart;
  int? _rangeEnd;

  // --- Pick a PDF ---
  Future<void> _pickPdf() async {
    final file = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(label: 'PDF', extensions: ['pdf']),
      ],
    );
    if (file == null) return;

    // Check security / decrypt
    final String? readablePath = await PdfSecurityHelper.ensureReadable(
      context,
      file.path,
    );
    if (readablePath == null) return;

    await _doc?.close();
    final doc = await pdfx.PdfDocument.openFile(readablePath);

    setState(() {
      // Use readable file (decrypted or original)
      _pdfFile = XFile(readablePath, name: file.name);
      _doc = doc;
      _pageCount = doc.pagesCount;
      _thumbCache.clear();
      _selected.clear();
      _baseSelection = {};
      _lastTappedPage = null;
      _rangeSelecting = false;
      _rangeStart = null;
      _rangeEnd = null;
    });
  }

  // --- Render a page thumbnail once and cache it ---
  Future<Uint8List?> _renderThumb(int pageNumber) {
    return _thumbCache.putIfAbsent(pageNumber, () async {
      final page = await _doc!.getPage(pageNumber);
      final img = await page.render(
        width: 220,
        height: 300,
        format: pdfx.PdfPageImageFormat.jpeg,
      );
      await page.close();
      return img?.bytes;
    });
  }

  // --- Save selected pages into a single new PDF ---
  // --- Save selected pages into a single new PDF ---
  Future<void> _splitSelected() async {
    if (_pdfFile == null || _selected.isEmpty) return;

    LoadingOverlay.show(context);
    try {
      final pages = _selected.toList()..sort();
      final downloads = await _getDownloadsDir();
      final outPath =
          '${downloads.path}/${_baseName(_pdfFile!.name)}_split.pdf';

      // Run in background
      await compute(
        PdfService.splitPdf,
        SplitArguments(
          sourcePath: _pdfFile!.path,
          pageNumbers: pages,
          outPath: outPath,
        ),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Saved to: $outPath')));
      await OpenFilex.open(outPath);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error splitting PDF: $e')));
    } finally {
      if (mounted) LoadingOverlay.hide(context);
    }
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

  // --- Selection logic ---
  void _toggleSingle(int page) {
    setState(() {
      if (_selected.contains(page)) {
        _selected.remove(page);
      } else {
        _selected.add(page);
      }
      _lastTappedPage = page;
    });
  }

  void _startRangeAt(int page) {
    setState(() {
      _rangeSelecting = true;
      _rangeStart = page;
      _rangeEnd = null;
      // snapshot current selection so ranges accumulate
      _baseSelection = Set<int>.from(_selected);
    });
  }

  void _updateRangeEnd(int page) {
    if (!_rangeSelecting || _rangeStart == null) return;

    final s = _rangeStart!;
    final e = page;
    final from = s < e ? s : e;
    final to = s < e ? e : s;

    // Range pages from 'from'..'to'
    final rangePages = List<int>.generate(to - from + 1, (i) => from + i);

    setState(() {
      _rangeEnd = page;
      // Show base selection UNION live range (doesn't lose existing)
      _selected
        ..clear()
        ..addAll(_baseSelection)
        ..addAll(rangePages);
      _lastTappedPage = page;
    });
  }

  void _endRange() {
    if (!_rangeSelecting) return;
    setState(() {
      _rangeSelecting = false;
      _rangeStart = null;
      _rangeEnd = null;
      _baseSelection = {};
      // keep _selected as-is (base ∪ chosen range)
    });
  }

  void _selectAll() {
    setState(() {
      _selected
        ..clear()
        ..addAll(List<int>.generate(_pageCount, (i) => i + 1));
      _rangeSelecting = false;
      _rangeStart = null;
      _rangeEnd = null;
      _baseSelection = {};
    });
  }

  void _clearSelection() {
    setState(() {
      _selected.clear();
      _rangeSelecting = false;
      _rangeStart = null;
      _rangeEnd = null;
      _baseSelection = {};
      _lastTappedPage = null;
    });
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
                childAspectRatio: 3 / 4,
              ),
              itemCount: _pageCount,
              itemBuilder: (context, i) {
                final page = i + 1;
                final selected = _selected.contains(page);
                final isRangeStart = _rangeSelecting && _rangeStart == page;
                final isRangeEnd = _rangeSelecting && _rangeEnd == page;

                return InkWell(
                  onTap: () {
                    if (_rangeSelecting) {
                      _updateRangeEnd(page);
                    } else {
                      _toggleSingle(page);
                    }
                  },
                  child: Stack(
                    children: [
                      // Card with thumbnail
                      Positioned.fill(
                        child: Card(
                          elevation: (selected || isRangeStart || isRangeEnd)
                              ? 6
                              : 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(
                              color: (selected || isRangeStart || isRangeEnd)
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
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                );
                              }
                              if (!snap.hasData || snap.data == null) {
                                return const Center(
                                  child: Icon(Icons.picture_as_pdf),
                                );
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
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            ' ',
                            style: TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ),
                      ),

                      // Check or endpoints
                      if (selected || isRangeStart || isRangeEnd)
                        Positioned(
                          right: 6,
                          top: 6,
                          child: Icon(
                            isRangeStart
                                ? Icons.playlist_add_check_circle
                                : isRangeEnd
                                ? Icons.task_alt
                                : Icons.check_circle,
                            color: Colors.lightGreenAccent,
                          ),
                        ),

                      // Start range chip (only when not in range mode)
                      if (!_rangeSelecting &&
                          selected &&
                          _lastTappedPage == page)
                        Positioned(
                          left: 8,
                          right: 8,
                          bottom: 8,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange.shade700,
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(32),
                              padding: const EdgeInsets.symmetric(vertical: 6),
                            ),
                            onPressed: () => _startRangeAt(page),
                            child: const Text('Start range'),
                          ),
                        ),

                      // End range chip (only on current end page while in range mode)
                      if (_rangeSelecting && _rangeEnd == page)
                        Positioned(
                          left: 8,
                          right: 8,
                          bottom: 8,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green.shade700,
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(32),
                              padding: const EdgeInsets.symmetric(vertical: 6),
                            ),
                            onPressed: _endRange,
                            child: const Text('End range'),
                          ),
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
              // Left half: Split (only if canSplit)
              Expanded(
                child: (_pdfFile != null && _selected.isNotEmpty)
                    ? ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange.shade600,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _splitSelected,
                        icon: const Icon(Icons.call_split),
                        label: Text('Split (${_selected.length})'),
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(width: 12),
              // Right half: Open/Change PDF
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                    foregroundColor: Colors.white,
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
