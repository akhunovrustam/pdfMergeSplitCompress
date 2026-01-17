import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:pdfx/pdfx.dart' as pdfx;

class ViewPdfPage extends StatefulWidget {
  const ViewPdfPage({Key? key}) : super(key: key);

  @override
  State<ViewPdfPage> createState() => _ViewPdfPageState();
}

class _ViewPdfPageState extends State<ViewPdfPage> {
  pdfx.PdfControllerPinch? _controller;
  String? _fileName;
  int _pagesCount = 0;
  bool _busy = false;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _openPdf() async {
    final file = await openFile(
      acceptedTypeGroups: [XTypeGroup(label: 'PDF', extensions: ['pdf'])],
    );
    if (file == null) return;

    setState(() => _busy = true);

    try {
      // read page count first for UI
      final tmpDoc = await pdfx.PdfDocument.openFile(file.path);
      final pages = tmpDoc.pagesCount;
      await tmpDoc.close();

      final controller = pdfx.PdfControllerPinch(
        // expects Future<PdfDocument>
        document: pdfx.PdfDocument.openFile(file.path),
      );

      _controller?.dispose();
      setState(() {
        _controller = controller;
        _fileName = file.name;
        _pagesCount = pages;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to open PDF: $e')),
      );
    }
  }

  Future<void> _jumpToPageDialog() async {
    if (_controller == null || _pagesCount == 0) return;

    final current = _controller!.pageListenable.value; // 1-based
    final input = TextEditingController(text: '$current');

    final target = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Go to page'),
        content: TextField(
          controller: input,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: '1 – $_pagesCount',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final val = int.tryParse(input.text.trim());
              if (val != null && val >= 1 && val <= _pagesCount) {
                Navigator.pop(ctx, val);
              } else {
                Navigator.pop(ctx);
              }
            },
            child: const Text('Go'),
          ),
        ],
      ),
    );

    if (target != null) {
      _controller!.animateToPage(
        pageNumber: target,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasDoc = _controller != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('View PDF'),
        actions: [
          IconButton(
            tooltip: hasDoc ? 'Change PDF' : 'Open PDF',
            icon: const Icon(Icons.folder_open),
            onPressed: _openPdf,
          ),
        ],
        bottom: _fileName == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(28),
                child: Container(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Text(
                    _fileName!,
                    style: const TextStyle(fontSize: 13, color: Colors.white70),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
      ),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : hasDoc
              ? Column(
                  children: [
                    Expanded(
                      child: pdfx.PdfViewPinch(
                        controller: _controller!,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
                      child: ValueListenableBuilder<int>(
                        valueListenable: _controller!.pageListenable,
                        builder: (_, current, __) {
                          final page = current.clamp(1, _pagesCount);
                          return Column(
                            children: [
                              Row(
                                children: [
                                  IconButton(
                                    tooltip: 'Previous page',
                                    icon: const Icon(Icons.chevron_left),
                                    onPressed: page > 1
                                        ? () => _controller!.previousPage(
                                              duration: const Duration(milliseconds: 150),
                                              curve: Curves.easeOut,
                                            )
                                        : null,
                                  ),
                                  Text(
                                    'Page $page / $_pagesCount',
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  IconButton(
                                    tooltip: 'Next page',
                                    icon: const Icon(Icons.chevron_right),
                                    onPressed: page < _pagesCount
                                        ? () => _controller!.nextPage(
                                              duration: const Duration(milliseconds: 150),
                                              curve: Curves.easeOut,
                                            )
                                        : null,
                                  ),
                                  const Spacer(),
                                  TextButton.icon(
                                    onPressed: _jumpToPageDialog,
                                    icon: const Icon(Icons.input),
                                    label: const Text('Go to'),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  const Text('1'),
                                  Expanded(
                                    child: Slider(
                                      min: 1,
                                      max: (_pagesCount == 0 ? 1 : _pagesCount).toDouble(),
                                      value: page.toDouble(),
                                      onChanged: (v) => _controller!.animateToPage(
                                        pageNumber: v.round(),
                                        duration: const Duration(milliseconds: 150),
                                        curve: Curves.easeOut,
                                      ),
                                    ),
                                  ),
                                  Text('$_pagesCount'),
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                )
              : Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.picture_as_pdf, size: 72, color: Colors.redAccent),
                      const SizedBox(height: 12),
                      const Text('No PDF selected'),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _openPdf,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Open PDF'),
                      ),
                    ],
                  ),
                ),
    );
  }
}
