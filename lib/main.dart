import 'package:flutter/material.dart';
import 'package:flutter_pdf/views/split_view.dart' deferred as split_view;
import 'package:flutter_pdf/views/compress_view.dart' deferred as compress_view;
import 'package:flutter_pdf/views/view_pdf_view.dart' deferred as view_pdf_view;
import 'views/merge_view.dart' deferred as merge_view;
import 'views/encrypt_view.dart' deferred as encrypt_view;
import 'views/unlock_view.dart' deferred as unlock_view;

void main() {
  runApp(PdfToolkitApp());
}

class PdfToolkitApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PDF Toolkit',
      theme: ThemeData(primarySwatch: Colors.red),
      home: HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomePage extends StatefulWidget {
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _isLoading = false;

  Future<void> _navigate(BuildContext context, String key) async {
    setState(() => _isLoading = true);
    try {
      Widget page;
      switch (key) {
        case 'merge':
          await merge_view.loadLibrary();
          page = merge_view.MergeView();
          break;
        case 'split':
          await split_view.loadLibrary();
          page = split_view.SplitView();
          break;
        case 'compress':
          await compress_view.loadLibrary();
          page = compress_view.CompressView();
          break;
        case 'view':
          await view_pdf_view.loadLibrary();
          page = view_pdf_view.ViewPdfPage();
          break;
        case 'encrypt':
          await encrypt_view.loadLibrary();
          page = encrypt_view.EncryptPdfView();
          break;
        case 'unlock':
          await unlock_view.loadLibrary();
          page = unlock_view.UnlockPdfView();
          break;
        default:
          return;
      }

      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error loading module: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  final List<Map<String, dynamic>> operations = [
    {'key': 'merge', 'title': 'Merge PDFs', 'icon': Icons.merge_type},
    {'key': 'split', 'title': 'Split PDF', 'icon': Icons.content_cut},
    {'key': 'compress', 'title': 'Compress PDF', 'icon': Icons.compress},
    {'key': 'view', 'title': 'View PDF', 'icon': Icons.picture_as_pdf},
    {'key': 'encrypt', 'title': 'Encrypt PDF', 'icon': Icons.lock_outline},
    {'key': 'unlock', 'title': 'Unlock PDF', 'icon': Icons.lock_open},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PDF Toolkit')),
      body: Stack(
        children: [
          GridView.count(
            crossAxisCount: 2,
            padding: const EdgeInsets.all(16),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            children: operations
                .map(
                  (op) => OperationCard(
                    title: op['title'],
                    icon: op['icon'],
                    onTap: () => _navigate(context, op['key']),
                  ),
                )
                .toList(),
          ),
          if (_isLoading)
            Container(
              color: Colors.black54,
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

class OperationCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback? onTap;

  OperationCard({required this.title, required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 48, color: Theme.of(context).primaryColor),
              SizedBox(height: 12),
              Text(
                title,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
