// عمارتي — real PDF report export (#8). Builds an RTL, Cairo-font PDF from the
// same row data used for Excel/CSV, then opens the system share/print sheet.

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

Future<void> exportReportPdf(String title, List<List<String>> rows) async {
  final base = await PdfGoogleFonts.cairoRegular();
  final bold = await PdfGoogleFonts.cairoBold();

  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      textDirection: pw.TextDirection.rtl,
      pageFormat: PdfPageFormat.a4,
      theme: pw.ThemeData.withFont(base: base, bold: bold),
      margin: const pw.EdgeInsets.all(28),
      header: (ctx) => pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 14),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('عمارتي',
                style: pw.TextStyle(font: bold, fontSize: 22, color: PdfColor.fromInt(0xFF232858))),
            pw.SizedBox(height: 2),
            pw.Text(title, style: pw.TextStyle(font: base, fontSize: 12, color: PdfColors.grey600)),
            pw.Divider(color: PdfColor.fromInt(0xFFC2A24E), thickness: 1.2),
          ],
        ),
      ),
      footer: (ctx) => pw.Align(
        alignment: pw.Alignment.centerLeft,
        child: pw.Text('صفحة ${ctx.pageNumber} / ${ctx.pagesCount}',
            style: pw.TextStyle(font: base, fontSize: 9, color: PdfColors.grey500)),
      ),
      build: (ctx) => [
        if (rows.isNotEmpty)
          pw.TableHelper.fromTextArray(
            headers: rows.first,
            data: rows.skip(1).toList(),
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            headerStyle: pw.TextStyle(font: bold, fontSize: 10, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF232858)),
            cellStyle: pw.TextStyle(font: base, fontSize: 10),
            cellAlignment: pw.Alignment.centerRight,
            headerAlignment: pw.Alignment.centerRight,
            rowDecoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey200, width: 0.5)),
            ),
            oddRowDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFFAFBFD)),
          ),
      ],
    ),
  );

  await Printing.sharePdf(bytes: await doc.save(), filename: 'amarati-report.pdf');
}
