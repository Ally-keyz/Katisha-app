import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'print_service.dart';

class PrintServiceImpl implements PrintService {
  @override
  Future<void> printPickupList(PickupListData data) async {
    final pdfBytes = await generatePickupListPdf(data);
    await Printing.layoutPdf(
      onLayout: (format) async => pdfBytes,
      name: 'Katisha Pickup List - ${data.routeName}',
    );
  }

  @override
  Future<Uint8List> generatePickupListPdf(PickupListData data) async {
    final doc = pw.Document();

    final headerStyle = pw.TextStyle(
      fontSize: 20,
      fontWeight: pw.FontWeight.bold,
    );
    final subHeaderStyle = pw.TextStyle(
      fontSize: 12,
      color: PdfColors.grey700,
    );
    final cellStyle = pw.TextStyle(fontSize: 9);
    final boldCellStyle = pw.TextStyle(
      fontSize: 9,
      fontWeight: pw.FontWeight.bold,
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 16),
          child: pw.Text(
            'Katisha - Confidential',
            style: pw.TextStyle(
              fontSize: 8,
              color: PdfColors.grey500,
            ),
          ),
        ),
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Text('Katisha - Pickup Manifest', style: headerStyle),
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Route: ${data.routeName}', style: subHeaderStyle),
                  pw.Text('Date: ${data.date}', style: subHeaderStyle),
                ],
              ),
              pw.Text(
                'Total Seats: ${data.totalSeats}',
                style: subHeaderStyle,
              ),
            ],
          ),
          pw.SizedBox(height: 20),
          _buildPassengerTable(data, cellStyle, boldCellStyle),
          pw.SizedBox(height: 16),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Text(
                'Total Passengers: ${data.passengers.length}  |  '
                'Total Seats: ${_totalBookedSeats(data)}',
                style: boldCellStyle,
              ),
            ],
          ),
        ],
      ),
    );

    return doc.save();
  }

  pw.Table _buildPassengerTable(
    PickupListData data,
    pw.TextStyle cellStyle,
    pw.TextStyle boldCellStyle,
  ) {
    final headers = ['#', 'Reference', 'Passenger', 'Phone', 'Pickup Point', 'Seats', 'Time'];

    final rows = <List<pw.Widget>>[];
    for (var i = 0; i < data.passengers.length; i++) {
      final p = data.passengers[i];
      rows.add([
        _cell((i + 1).toString(), cellStyle),
        _cell(p.referenceCode, cellStyle),
        _cell(p.passengerName, cellStyle),
        _cell(p.phone, cellStyle),
        _cell(p.pickupPoint, cellStyle),
        _cell(p.seats.toString(), cellStyle),
        _cell(p.travelTime, cellStyle),
      ]);
    }

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: rows,
      headerStyle: boldCellStyle,
      headerDecoration: const pw.BoxDecoration(
        color: PdfColors.grey300,
      ),
      cellStyle: cellStyle,
      cellAlignments: {
        0: pw.Alignment.center,
        5: pw.Alignment.center,
        6: pw.Alignment.center,
      },
      headerAlignments: {
        0: pw.Alignment.center,
        5: pw.Alignment.center,
        6: pw.Alignment.center,
      },
      border: pw.TableBorder.all(
        color: PdfColors.grey400,
        width: 0.5,
      ),
      rowDecoration: pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(
            color: PdfColors.grey300,
            width: 0.5,
          ),
        ),
      ),
      oddRowDecoration: const pw.BoxDecoration(
        color: PdfColors.grey50,
      ),
    );
  }

  pw.Widget _cell(String text, pw.TextStyle style) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: pw.Text(text, style: style),
    );
  }

  int _totalBookedSeats(PickupListData data) {
    return data.passengers.fold(0, (sum, p) => sum + p.seats);
  }
}
