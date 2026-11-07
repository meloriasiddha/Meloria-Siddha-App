import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../config.dart';
import '../widgets/common.dart' show str;
import 'db.dart';

/// Builds the A4 bill PDF in the Meloria design.
class BillPdf {
  static const _slate = PdfColor.fromInt(0xFF2C3A45);
  static const _muted = PdfColor.fromInt(0xFF7A8A92);
  static const _sageD = PdfColor.fromInt(0xFF678778);
  static const _sageBg = PdfColor.fromInt(0xFFEEF3F0);
  static const _bg = PdfColor.fromInt(0xFFF7F8F6);
  static const _line = PdfColor.fromInt(0xFFE4E8E5);
  static const _teal = PdfColor.fromInt(0xFF2F7480);

  static final _money = NumberFormat('#,##,##0.00', 'en_IN');
  static String m(num v) => _money.format(v);

  static const clinicAddress =
      '18, Thendral Nagar, St Thomas Road, Maharaja Nagar, Tirunelveli – 627011';
  static const clinicContact = '+91 93446 98304 · meloriasiddha@gmail.com';

  static Future<Uint8List> build({
    required DbRow bill,
    required List<DbRow> items,
    required DbRow patient,
    String visitLabel = '',
    String doctorName = '',
    String? nextVisit,
    String? gstin,
  }) async {
    final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/Montserrat-Regular.ttf'));
    final medium = pw.Font.ttf(await rootBundle.load('assets/fonts/Montserrat-Medium.ttf'));
    final semi = pw.Font.ttf(await rootBundle.load('assets/fonts/Montserrat-SemiBold.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/Montserrat-Bold.ttf'));
    final serif = pw.Font.ttf(await rootBundle.load('assets/fonts/CormorantGaramond-Bold.ttf'));
    final logo = pw.MemoryImage(
        (await rootBundle.load('assets/images/logo_symbol.png')).buffer.asUint8List());

    pw.TextStyle t(double size, {pw.Font? f, PdfColor color = _slate, double spacing = 0}) =>
        pw.TextStyle(font: f ?? regular, fontSize: size, color: color, letterSpacing: spacing);

    final date = DateTime.tryParse(str(bill['bill_date']))?.toLocal() ?? DateTime.now();
    final status = str(bill['status']);
    final statusLabel = switch (status) {
      'paid' => 'PAID',
      'partial' => 'PART PAID',
      'cancelled' => 'CANCELLED',
      _ => 'PAYMENT DUE',
    };
    final statusColor = status == 'paid' ? _sageD : (status == 'cancelled' ? _muted : PdfColor.fromInt(0xFFB4533F));

    // Group items by kind, in a fixed order.
    const groups = {
      'consultation': 'CONSULTATION',
      'program': 'PROGRAM',
      'medicine': 'MEDICINES',
      'treatment': 'TREATMENTS',
      'other': 'OTHER',
    };
    final rows = <pw.TableRow>[];
    var n = 0;
    for (final g in groups.entries) {
      final list = items.where((i) => i['kind'] == g.key).toList();
      if (list.isEmpty) continue;
      rows.add(pw.TableRow(
        decoration: const pw.BoxDecoration(color: _sageBg),
        children: [
          pw.Padding(padding: const pw.EdgeInsets.fromLTRB(8, 5, 8, 5), child: pw.SizedBox()),
          pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(8, 5, 8, 5),
              child: pw.Text(g.value, style: t(8.5, f: semi, color: _sageD, spacing: 0.6))),
          pw.SizedBox(),
          pw.SizedBox(),
          pw.SizedBox(),
        ],
      ));
      for (final i in list) {
        n++;
        rows.add(pw.TableRow(
          decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: _line, width: 0.8))),
          children: [
            _cell(pw.Text('$n', style: t(9.5))),
            _cell(pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(str(i['description']), style: t(9.5)),
              if (str(i['detail']).isNotEmpty)
                pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 2),
                    child: pw.Text(str(i['detail']), style: t(8, color: _muted))),
            ])),
            _cell(pw.Text(_qty(i['qty']), style: t(9.5)), right: true),
            _cell(pw.Text(m(i['rate'] ?? 0), style: t(9.5)), right: true),
            _cell(pw.Text(m(i['amount'] ?? 0), style: t(9.5)), right: true),
          ],
        ));
      }
    }

    pw.Widget info(String k, String v) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
          child: pw.Row(children: [
            pw.SizedBox(width: 70, child: pw.Text(k, style: t(9, color: _muted))),
            pw.Expanded(child: pw.Text(v, style: t(9, f: semi))),
          ]),
        );

    pw.Widget totalRow(String k, String v, {bool big = false, PdfColor color = _slate}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 3),
          child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text(k, style: t(big ? 12.5 : 9.5, f: big ? bold : regular, color: color)),
            pw.Text(v, style: t(big ? 12.5 : 9.5, f: big ? bold : regular, color: color)),
          ]),
        );

    final subtotal = (bill['subtotal'] ?? 0) as num;
    final discount = (bill['discount'] ?? 0) as num;
    final gstAmt = (bill['gst_amount'] ?? 0) as num;
    final total = (bill['total'] ?? 0) as num;
    final paid = (bill['paid_amount'] ?? 0) as num;
    const modes = {'cash': 'Cash', 'upi': 'UPI', 'card': 'Card', 'online': 'Online', 'other': 'Other'};

    final doc = pw.Document(title: str(bill['bill_no']), author: clinicLegalName);
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 34, 40, 30),
      build: (_) => [
          // Header: logo above clinic name
          pw.Center(child: pw.Image(logo, height: 52)),
          pw.SizedBox(height: 6),
          pw.Center(child: pw.Text(clinicLegalName, style: t(22, f: serif))),
          pw.SizedBox(height: 3),
          pw.Center(child: pw.Text(clinicAddress, style: t(8.5, color: _muted))),
          pw.Center(child: pw.Text(clinicContact, style: t(8.5, color: _muted))),
          if ((gstin ?? '').isNotEmpty)
            pw.Center(child: pw.Text('GSTIN: $gstin', style: t(8.5, color: _muted))),
          pw.SizedBox(height: 10),
          pw.Container(height: 1.6, color: _slate),
          pw.SizedBox(height: 12),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text('BILL / RECEIPT', style: t(11, f: semi, spacing: 2.4)),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: statusColor, width: 1.2),
                  borderRadius: pw.BorderRadius.circular(6)),
              child: pw.Text(statusLabel, style: t(8.5, f: bold, color: statusColor, spacing: 0.8)),
            ),
          ]),
          pw.SizedBox(height: 10),
          pw.Container(
            padding: const pw.EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: pw.BoxDecoration(color: _bg, borderRadius: pw.BorderRadius.circular(8)),
            child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Expanded(
                child: pw.Column(children: [
                  info('Bill no.', str(bill['bill_no'])),
                  info('Patient', str(patient['name'])),
                  info('Age / Gender', [
                    if (patient['age'] != null) '${patient['age']} y',
                    str(patient['gender']),
                  ].where((s) => s.isNotEmpty).join(' / ')),
                  if (visitLabel.isNotEmpty) info('Visit', visitLabel),
                ]),
              ),
              pw.SizedBox(width: 20),
              pw.Expanded(
                child: pw.Column(children: [
                  info('Date', DateFormat('d MMM yyyy, h:mm a').format(date)),
                  info('Patient ID', str(patient['patient_code'])),
                  info('Phone', str(patient['phone'])),
                  if (doctorName.isNotEmpty) info('Doctor', doctorName),
                ]),
              ),
            ]),
          ),
          pw.SizedBox(height: 14),
          pw.Table(
            columnWidths: const {
              0: pw.FixedColumnWidth(24),
              1: pw.FlexColumnWidth(),
              2: pw.FixedColumnWidth(40),
              3: pw.FixedColumnWidth(70),
              4: pw.FixedColumnWidth(80),
            },
            children: [
              pw.TableRow(
                decoration: pw.BoxDecoration(color: _slate, borderRadius: pw.BorderRadius.circular(6)),
                children: [
                  _head('#', semi),
                  _head('DESCRIPTION', semi),
                  _head('QTY', semi, right: true),
                  _head('RATE (₹)', semi, right: true),
                  _head('AMOUNT (₹)', semi, right: true),
                ],
              ),
              ...rows,
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.SizedBox(
              width: 220,
              child: pw.Column(children: [
                totalRow('Subtotal', m(subtotal)),
                if (discount > 0) totalRow('Discount', '− ${m(discount)}'),
                if (gstAmt > 0) totalRow('GST (${bill['gst_rate']}%)', m(gstAmt)),
                pw.Container(height: 1.6, color: _slate, margin: const pw.EdgeInsets.symmetric(vertical: 4)),
                totalRow('Total', '₹ ${m(total)}', big: true),
                if (paid > 0)
                  totalRow(
                      'Paid${bill['payment_mode'] == null ? '' : ' by ${modes[bill['payment_mode']] ?? bill['payment_mode']}'}',
                      m(paid),
                      color: _muted),
                if (total - paid > 0.009)
                  totalRow('Balance due', m(total - paid), color: PdfColor.fromInt(0xFFB4533F)),
              ]),
            ),
          ),
          pw.SizedBox(height: 28),
          pw.Container(height: 0.8, color: _line),
          pw.SizedBox(height: 10),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              (nextVisit ?? '').isEmpty
                  ? pw.SizedBox()
                  : pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: pw.BoxDecoration(
                          color: const PdfColor.fromInt(0xFFE8F1F2),
                          borderRadius: pw.BorderRadius.circular(6)),
                      child: pw.Text(
                          'Next visit: ${DateFormat('d MMM yyyy').format(DateTime.parse(nextVisit!))}',
                          style: t(9.5, f: semi, color: _teal)),
                    ),
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
                pw.Text('For $clinicLegalName', style: t(8.5, color: _muted)),
                pw.SizedBox(height: 22),
                if (doctorName.isNotEmpty) pw.Text(doctorName, style: t(9.5, f: medium)),
              ]),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Center(
            child: pw.Text(
                'Computer-generated bill · Medicines once dispensed cannot be returned · Thank you for choosing Meloria',
                style: t(7.5, color: _muted)),
          ),
      ],
    ));
    return doc.save();
  }

  static String _qty(dynamic q) {
    final v = (q ?? 1) as num;
    return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
  }

  static pw.Widget _head(String s, pw.Font f, {bool right = false}) => pw.Padding(
        padding: const pw.EdgeInsets.fromLTRB(8, 7, 8, 7),
        child: pw.Text(s,
            textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
            style: pw.TextStyle(font: f, fontSize: 8, color: PdfColors.white, letterSpacing: 0.6)),
      );

  static pw.Widget _cell(pw.Widget c, {bool right = false}) => pw.Padding(
        padding: const pw.EdgeInsets.fromLTRB(8, 6, 8, 6),
        child: right ? pw.Align(alignment: pw.Alignment.topRight, child: c) : c,
      );
}
