import 'dart:typed_data';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

class MergeView extends StatefulWidget {
  const MergeView({Key? key}) : super(key: key);

  @override
  State<MergeView> createState() => _MergeViewState();
}

class _MergeViewState extends State<MergeView> {
  final List<XFile> _pdfFiles = [];
  final Map<String, Future<Uint8List?>> _thumbnailCache = {};

  Future<void> _pickFiles() async {
    final files = await openFiles(
      acceptedTypeGroups: [XTypeGroup(label: 'PDFs', extensions: ['pdf'])],
    );
    if (files.isNotEmpty) {
      setState(() {
        for (final f in files) {
          if (_pdfFiles.indexWhere((e) => e.path == f.path) == -1) {
            _pdfFiles.add(f);
            _thumbnailCache[f.path] = _renderFirstPage(f.path);
          }
        }
      });
    }
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final item = _pdfFiles.removeAt(oldIndex);
      _pdfFiles.insert(newIndex, item);
    });
  }

  Future<Uint8List?> _renderFirstPage(String path) async {
    final doc = await pdfx.PdfDocument.openFile(path);
    final page = await doc.getPage(1);
    final img = await page.render(
      width: page.width,
      height: page.height,
      format: pdfx.PdfPageImageFormat.jpeg,
    );
    await page.close();
    return img?.bytes;
  }

  Widget _buildThumbnail(XFile file, {double width = 90, double height = 120}) {
    return FutureBuilder<Uint8List?>(
      future: _thumbnailCache[file.path],
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return SizedBox(
            width: width, height: height,
            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        if (snap.hasError || snap.data == null) {
          return SizedBox(
            width: width, height: height,
            child: const Center(child: Icon(Icons.error)),
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Image.memory(
            snap.data!,
            width: width,
            height: height,
            fit: BoxFit.cover,
          ),
        );
      },
    );
  }

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

  Future<void> _mergePDFs() async {
    if (_pdfFiles.length < 2) return;

    final out = sf.PdfDocument();
    for (final f in _pdfFiles) {
      final bytes = await f.readAsBytes();
      final input = sf.PdfDocument(inputBytes: bytes);
      for (int i = 0; i < input.pages.count; i++) {
        out.pages
            .add()
            .graphics
            .drawPdfTemplate(input.pages[i].createTemplate(), const Offset(0, 0));
      }
      input.dispose();
    }
    final data = out.saveSync();
    out.dispose();

    final dir = await _getDownloadsDir();
    final path = '${dir.path}/merged_output.pdf';
    await File(path).writeAsBytes(data, flush: true);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Merged PDF saved to:\n$path')),
    );

    await OpenFilex.open(path);
  }

  @override
  Widget build(BuildContext context) {
    final canMerge = _pdfFiles.length > 1;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Merge PDFs'),
      ),
      body: _pdfFiles.isEmpty
          ? const Center(child: Text('No PDF files selected.'))
          : ReorderableListView.builder(
              itemCount: _pdfFiles.length,
              onReorder: _onReorder,
              buildDefaultDragHandles: false,
              itemBuilder: (context, index) {
                final file = _pdfFiles[index];
                return Container(
                  key: ValueKey(file.path),
                  height: 120,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  alignment: Alignment.centerLeft,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _buildThumbnail(file, width: 90, height: 120),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          file.name,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        tooltip: 'Remove',
                        onPressed: () {
                          setState(() {
                            _thumbnailCache.remove(file.path);
                            _pdfFiles.removeAt(index);
                          });
                        },
                      ),
                      const SizedBox(width: 12),
                      ReorderableDragStartListener(
                        index: index,
                        child: const Icon(Icons.drag_handle),
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
              // Left half: Merge (only visible when canMerge), but we keep the slot
              Expanded(
                child: canMerge
                    ? ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange.shade600,
                        ),
                        onPressed: _mergePDFs,
                        icon: const Icon(Icons.save),
                        label: const Text('Merge'),
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(width: 12),
              // Right half: Add (always visible)
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                  ),
                  onPressed: _pickFiles,
                  icon: const Icon(Icons.add),
                  label: const Text('Add'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
