import 'dart:io';
import 'package:flutter/services.dart'; // For BackgroundIsolateBinaryMessenger
import 'dart:ui'; // for Offset
import 'dart:typed_data';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:image/image.dart' as img; // For compression
import 'package:pdfx/pdfx.dart'
    as pdfx; // For rendering pages to image for compression

/// Arguments for Merge operation
class MergeArguments {
  final List<String> filePaths;
  final String outPath;
  MergeArguments({required this.filePaths, required this.outPath});
}

/// Arguments for Split operation
class SplitArguments {
  final String sourcePath;
  final List<int> pageNumbers; // 1-based
  final String outPath;
  SplitArguments({
    required this.sourcePath,
    required this.pageNumbers,
    required this.outPath,
  });
}

/// Arguments for Encryption
class EncryptArguments {
  final String path;
  final String userPassword;
  final String ownerPassword;
  final String outPath;
  EncryptArguments({
    required this.path,
    required this.userPassword,
    this.ownerPassword = '',
    required this.outPath,
  });
}

/// Arguments for Unlocking
class UnlockArguments {
  final String path;
  final String password;
  final String outPath;
  UnlockArguments({
    required this.path,
    required this.password,
    required this.outPath,
  });
}

/// Arguments for Compression (Raster Mode)
class CompressRasterArguments {
  final String path;
  final double scale;
  final int quality;
  final String outPath;
  final RootIsolateToken token;
  CompressRasterArguments({
    required this.path,
    required this.scale,
    required this.quality,
    required this.outPath,
    required this.token,
  });
}

class PdfService {
  // --- MERGE ---
  static Future<void> mergePdfs(MergeArguments args) async {
    final PdfDocument outputDocument = PdfDocument();

    for (final path in args.filePaths) {
      final File file = File(path);
      final List<int> bytes = await file.readAsBytes();
      final PdfDocument inputDocument = PdfDocument(inputBytes: bytes);

      for (int i = 0; i < inputDocument.pages.count; i++) {
        outputDocument.pages.add().graphics.drawPdfTemplate(
          inputDocument.pages[i].createTemplate(),
          const Offset(0, 0),
        );
      }

      inputDocument.dispose();
    }

    final List<int> bytes = await outputDocument.save();
    outputDocument.dispose();

    await File(args.outPath).writeAsBytes(bytes, flush: true);
  }

  // --- SPLIT ---
  static Future<void> splitPdf(SplitArguments args) async {
    final File file = File(args.sourcePath);
    final List<int> bytes = await file.readAsBytes();
    final PdfDocument inputDocument = PdfDocument(inputBytes: bytes);
    final PdfDocument outputDocument = PdfDocument();

    // Sort pages just in case
    final sortedPages = List<int>.from(args.pageNumbers)..sort();

    for (final pageNumber in sortedPages) {
      if (pageNumber < 1 || pageNumber > inputDocument.pages.count) continue;

      final PdfPage inputPage = inputDocument.pages[pageNumber - 1];
      outputDocument.pages.add().graphics.drawPdfTemplate(
        inputPage.createTemplate(),
        const Offset(0, 0),
      );
    }

    final List<int> outBytes = await outputDocument.save();
    inputDocument.dispose();
    outputDocument.dispose();

    await File(args.outPath).writeAsBytes(outBytes, flush: true);
  }

  // --- ENCRYPT ---
  static Future<void> encryptPdf(EncryptArguments args) async {
    final File file = File(args.path);
    final List<int> bytes = await file.readAsBytes();
    final PdfDocument document = PdfDocument(inputBytes: bytes);

    final PdfSecurity security = document.security;
    security.userPassword = args.userPassword;
    if (args.ownerPassword.isNotEmpty) {
      security.ownerPassword = args.ownerPassword;
    }
    security.algorithm = PdfEncryptionAlgorithm.rc4x128Bit;

    final List<int> outBytes = await document.save();
    document.dispose();

    await File(args.outPath).writeAsBytes(outBytes, flush: true);
  }

  // --- UNLOCK ---
  static Future<void> unlockPdf(UnlockArguments args) async {
    final File file = File(args.path);
    final List<int> bytes = await file.readAsBytes();

    // Load with password
    final PdfDocument document = PdfDocument(
      inputBytes: bytes,
      password: args.password,
    );

    // Remove security
    document.security.userPassword = '';
    document.security.ownerPassword = '';

    final List<int> outBytes = await document.save();
    document.dispose();

    await File(args.outPath).writeAsBytes(outBytes, flush: true);
  }

  // --- COMPRESS (Raster) ---
  static Future<void> compressRaster(CompressRasterArguments args) async {
    // Ensure we can use platform channels (pdfx plugin) in this isolate
    BackgroundIsolateBinaryMessenger.ensureInitialized(args.token);

    final pdfxDoc = await pdfx.PdfDocument.openFile(args.path);
    final outputPdf = PdfDocument();

    outputPdf.fileStructure.incrementalUpdate = false;

    final int pageCount = pdfxDoc.pagesCount;

    for (int i = 1; i <= pageCount; i++) {
      final page = await pdfxDoc.getPage(i);

      final w = page.width;
      final h = page.height;

      final renderW = w * args.scale;
      final renderH = h * args.scale;

      final pdfx.PdfPageImage? image = await page.render(
        width: renderW,
        height: renderH,
        format: pdfx.PdfPageImageFormat.jpeg,
        quality: args.quality,
      );

      await page.close();

      if (image != null) {
        final PdfPage newPage = outputPdf.pages.add();

        final PdfBitmap bitmap = PdfBitmap(image.bytes);

        newPage.graphics.drawImage(
          bitmap,
          Rect.fromLTWH(
            0,
            0,
            newPage.getClientSize().width,
            newPage.getClientSize().height,
          ),
        );
      }
    }

    await pdfxDoc.close();

    final List<int> outBytes = await outputPdf.save();
    outputPdf.dispose();

    await File(args.outPath).writeAsBytes(outBytes, flush: true);
  }
}
