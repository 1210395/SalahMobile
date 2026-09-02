// سكن برو — real PDF report export (#8). Builds an RTL, Cairo-font PDF from the
// same row data used for Excel/CSV, then either opens the system share sheet or
// saves it to the device (#41). The header carries the app logo, the building
// name, and the report title.

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../data/file_save.dart';

/// Share the report through the system sheet (WhatsApp, mail, print…).
Future<void> exportReportPdf(String title, List<List<String>> rows,
    {String? buildingName}) async {
  final bytes = await buildReportPdf(title, rows, buildingName: buildingName);
  await Printing.sharePdf(bytes: bytes, filename: 'sakan-pro-report.pdf');
}

/// #41 — save the report to the device instead; returns the saved path.
Future<String> saveReportPdf(String title, List<List<String>> rows,
    {String? buildingName, String fileName = 'sakan-pro-report.pdf'}) async {
  final bytes = await buildReportPdf(title, rows, buildingName: buildingName);
  return saveToDownloads(fileName, bytes);
}

/// Split the flat row list into tables: a blank row ends the current block, and
/// each block's first row is its own header.
///
/// Reports are built as one flat list of rows with blank separators. Rendering
/// that as a SINGLE table made the very first row the header for everything, so
/// a unit report's five payment columns were squeezed into the two its summary
/// needed — which is what "the report's shape needs fixing" meant.
List<List<List<String>>> reportBlocks(List<List<String>> rows) {
  final blocks = <List<List<String>>>[];
  var current = <List<String>>[];
  for (final r in rows) {
    if (r.isEmpty || r.every((c) => c.trim().isEmpty)) {
      if (current.isNotEmpty) blocks.add(current);
      current = <List<String>>[];
      continue;
    }
    current.add(r);
  }
  if (current.isNotEmpty) blocks.add(current);
  return blocks;
}

String _today() {
  final d = DateTime.now();
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

Future<Uint8List> buildReportPdf(String title, List<List<String>> rows,
    {String? buildingName}) async {
  final base = await PdfGoogleFonts.cairoRegular();
  final bold = await PdfGoogleFonts.cairoBold();

  // Site logo, embedded in the header (optional — skip gracefully if missing).
  Uint8List? logo;
  try {
    logo = (await rootBundle.load('assets/images/logo.png')).buffer.asUint8List();
  } catch (_) {
    logo = null;
  }
  final building = (buildingName ?? '').trim();

  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      textDirection: pw.TextDirection.rtl,
      pageFormat: PdfPageFormat.a4,
      theme: pw.ThemeData.withFont(base: base, bold: bold),
      margin: const pw.EdgeInsets.all(28),
      header: (ctx) => pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 16),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            // The building's name and the report's title, centred and large
            // enough to read across a desk — these are printed and handed to
            // people, not skimmed on a screen.
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (logo != null) ...[
                  pw.Image(pw.MemoryImage(logo), width: 46, height: 46),
                  pw.SizedBox(width: 12),
                ],
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    if (building.isNotEmpty)
                      pw.Text(building,
                          style: pw.TextStyle(
                              font: bold, fontSize: 22, color: PdfColor.fromInt(0xFF6B2F9E))),
                    pw.Text('سكن برو',
                        style: pw.TextStyle(
                            font: base, fontSize: 12, color: PdfColor.fromInt(0xFFA8873A))),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Text(title,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(font: bold, fontSize: 16, color: PdfColors.black)),
            pw.SizedBox(height: 4),
            pw.Text('تاريخ الإصدار: ${_today()}',
                style: pw.TextStyle(font: base, fontSize: 10, color: PdfColors.grey600)),
            pw.SizedBox(height: 8),
            pw.Divider(color: PdfColor.fromInt(0xFFB02324), thickness: 1.4),
          ],
        ),
      ),
      footer: (ctx) => pw.Align(
        alignment: pw.Alignment.centerLeft,
        child: pw.Text('صفحة ${ctx.pageNumber} / ${ctx.pagesCount}',
            style: pw.TextStyle(font: base, fontSize: 9, color: PdfColors.grey500)),
      ),
      build: (ctx) => [
        // Each blank row starts a NEW table, and each table carries its own
        // header row. Everything used to be forced into a single table whose
        // header was the title line, so a unit report's five payment columns
        // were crushed into the two the summary needed.
        for (final block in reportBlocks(rows)) ...[
          pw.TableHelper.fromTextArray(
            headers: block.first,
            data: block.skip(1).toList(),
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            headerStyle: pw.TextStyle(font: bold, fontSize: 12, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF6B2F9E)),
            cellStyle: pw.TextStyle(font: base, fontSize: 11.5),
            cellHeight: 24,
            cellAlignment: pw.Alignment.centerRight,
            headerAlignment: pw.Alignment.centerRight,
            rowDecoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey200, width: 0.5)),
            ),
            oddRowDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF6F3FA)),
          ),
          pw.SizedBox(height: 18),
        ],
      ],
    ),
  );

  return doc.save();
}
