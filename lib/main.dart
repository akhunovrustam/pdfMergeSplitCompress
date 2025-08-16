import 'package:flutter/material.dart';
import 'package:flutter_pdf/views/split_view.dart';
import 'views/merge_view.dart'; // Import your MergeView file

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

class HomePage extends StatelessWidget {
  final List<Map<String, dynamic>> operations = [
    {'title': 'Merge PDFs', 'icon': Icons.merge_type, 'screen': MergeView()},
    {'title': 'Split PDF', 'icon': Icons.content_cut, 'screen': SplitView()},
    {'title': 'Compress PDF', 'icon': Icons.compress, 'screen': DummyScreen(title: 'Compress PDF')},
    {'title': 'View PDF', 'icon': Icons.picture_as_pdf, 'screen': DummyScreen(title: 'View PDF')},
    {'title': 'Encrypt PDF', 'icon': Icons.lock_outline, 'screen': DummyScreen(title: 'Encrypt PDF')},
    {'title': 'Unlock PDF', 'icon': Icons.lock_open, 'screen': DummyScreen(title: 'Unlock PDF')},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('PDF Toolkit')),
      body: GridView.count(
        crossAxisCount: 2,
        padding: EdgeInsets.all(16),
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        children: operations
            .map(
              (op) => OperationCard(
                title: op['title'],
                icon: op['icon'],
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => op['screen']),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class OperationCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback? onTap;

  OperationCard({
    required this.title,
    required this.icon,
    this.onTap,
  });

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


class DummyScreen extends StatelessWidget {
  final String title;

  DummyScreen({required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(child: Text('Coming soon...')),
    );
  }
}
