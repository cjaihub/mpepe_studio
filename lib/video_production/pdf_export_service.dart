import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:signature/signature.dart';
import '../backend/project_repository.dart';

class PdfExportService {
  static Future<File?> generateStoryboardPdf({
    required StudioProject project,
    required List<String> storyboardUrls,
    required List<SignatureController> signatureControllers,
  }) async {
    final pdf = pw.Document();

    // Generate pages for each storyboard scene
    for (int i = 0; i < storyboardUrls.length; i++) {
      final url = storyboardUrls[i];
      final sigController = signatureControllers[i];

      // Download network image to bytes
      pw.MemoryImage? bgImage;
      try {
        final netImage = await networkImage(url);
        bgImage = netImage as pw.MemoryImage; // networkImage returns ImageProvider but printing usually returns MemoryImage
      } catch (e) {
        debugPrint('Failed to load image for PDF: $e');
      }

      // Extract Signature drawing if any
      pw.MemoryImage? drawingImage;
      if (sigController.isNotEmpty) {
        final image = await sigController.toImage();
        if (image != null) {
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          if (data != null) {
            drawingImage = pw.MemoryImage(data.buffer.asUint8List());
          }
        }
      }

      // Add a page to the PDF
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(32),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Header(
                  level: 0,
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(project.title, style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                      pw.Text('Shot ${i + 1} of ${storyboardUrls.length}', style: const pw.TextStyle(fontSize: 16)),
                    ],
                  ),
                ),
                pw.SizedBox(height: 20),
                pw.Expanded(
                  child: pw.Center(
                    child: pw.Stack(
                      alignment: pw.Alignment.center,
                      children: [
                        if (bgImage != null)
                          pw.Image(bgImage, fit: pw.BoxFit.contain),
                        if (drawingImage != null)
                          pw.Image(drawingImage, fit: pw.BoxFit.contain),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      );
    }

    // Save and return the file
    try {
      final bytes = await pdf.save();
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/mpepe_storyboard_${project.id.isNotEmpty ? project.id : "draft"}.pdf');
      await file.writeAsBytes(bytes);
      return file;
    } catch (e) {
      debugPrint('Failed to save PDF: $e');
      return null;
    }
  }
}
