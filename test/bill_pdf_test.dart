import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meloria_siddha/services/bill_pdf.dart';

/// Renders a sample bill to build/sample_bill.pdf so the layout can be checked.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('sample bill renders', () async {
    final bytes = await BillPdf.build(
      bill: {
        'bill_no': 'MEL1-B-0001',
        'bill_date': DateTime(2026, 11, 7, 19, 5).toIso8601String(),
        'status': 'paid',
        'subtotal': 1195,
        'discount': 95,
        'gst_rate': 0,
        'gst_amount': 0,
        'total': 1100,
        'paid_amount': 1100,
        'payment_mode': 'upi',
      },
      items: [
        {'kind': 'consultation', 'description': 'Initial consultation', 'detail': 'Valid until 7 Dec 2026 or 4 visits', 'qty': 1, 'rate': 300, 'amount': 300},
        {'kind': 'medicine', 'description': 'Nilavembu Kudineer Choornam 100 g', 'detail': 'Batch NK2611 · Exp 08/2027 · 1 tsp 1-0-1 After food · 15 days', 'qty': 1, 'rate': 120, 'amount': 120},
        {'kind': 'medicine', 'description': 'Amukkara Choornam 50 g', 'detail': 'Batch AM2604 · Exp 03/2028 · 0-0-1 with warm milk · 15 days', 'qty': 1, 'rate': 95, 'amount': 95},
        {'kind': 'medicine', 'description': 'Pinda Thailam 100 ml', 'detail': 'Batch PT2609 · Exp 09/2027 · external application', 'qty': 1, 'rate': 180, 'amount': 180},
        {'kind': 'treatment', 'description': 'Varmam', 'qty': 1, 'rate': 500, 'amount': 500},
      ],
      patient: {'name': 'Anitha Devi', 'patient_code': 'MEL1-0219', 'age': 42, 'gender': 'Female', 'phone': '+91 98765 00021'},
      visitLabel: 'Initial consultation · In clinic',
      doctorName: 'Dr J J Amala Janice Seelan',
      nextVisit: '2026-11-22',
    );
    File('build/sample_bill.pdf').writeAsBytesSync(bytes);
    expect(bytes.length, greaterThan(1000));
  });
}
