import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../services/bill_pdf.dart';
import '../services/billing_db.dart';
import '../services/db.dart';
import '../theme.dart';
import '../widgets/common.dart';

const _visitTypes = {
  'first': 'Initial consultation',
  'review': 'Review',
  'therapy': 'Therapy',
  'program': 'Program visit',
};
const _payModes = {'cash': 'Cash', 'upi': 'UPI', 'card': 'Card', 'online': 'Online'};
const _kindLabels = {
  'consultation': 'Consultation',
  'program': 'Program',
  'medicine': 'Medicine',
  'treatment': 'Treatment',
  'other': 'Other',
};

/// Create / view / edit a bill. Items are filled automatically from the
/// visit (consultation fee rule, medicines, treatments) and can be edited.
class BillScreen extends StatefulWidget {
  const BillScreen({super.key, this.visitId, this.billId, this.patientId, this.patientProgram});
  final String? visitId;
  final String? billId;
  final String? patientId; // blank bill for a patient
  final DbRow? patientProgram; // bill for a program enrolment

  @override
  State<BillScreen> createState() => _BillScreenState();
}

class _BillScreenState extends State<BillScreen> {
  bool _loading = true;
  bool _saving = false;
  DbRow? _patient;
  DbRow? _visit;
  DbRow _settings = {};
  String? _billId;
  String _billNo = '';
  DateTime _billDate = DateTime.now();
  String _status = 'paid';
  String _feeNote = '';
  final List<DbRow> _items = [];
  final _discount = TextEditingController(text: '0');
  final _paid = TextEditingController();
  final _notes = TextEditingController();
  String _mode = 'cash';
  bool _paidTouched = false;

  @override
  void initState() {
    super.initState();
    _discount.addListener(_recalc);
    _load();
  }

  // ------------------------------------------------------------ totals
  num get _subtotal => _items.fold<num>(0, (s, i) => s + (i['amount'] as num));
  num get _disc => (toNum(_discount.text) ?? 0).clamp(0, _subtotal);
  bool get _gstOn => _settings['gst_enabled'] == true;
  num get _gstRate => _gstOn ? ((_settings['gst_rate'] ?? 0) as num) : 0;
  num get _gst => ((_subtotal - _disc) * _gstRate / 100);
  num get _total => ((_subtotal - _disc + _gst) * 100).round() / 100;

  void _recalc() {
    if (!_paidTouched && _billId == null) _paid.text = _fmt(_total);
    setState(() {});
  }

  String _fmt(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  DbRow _item(String kind, String desc, {String? detail, num qty = 1, num rate = 0}) =>
      {'kind': kind, 'description': desc, 'detail': detail, 'qty': qty, 'rate': rate, 'amount': qty * rate};

  // ------------------------------------------------------------ load
  Future<void> _load() async {
    try {
      _settings = await BillDb.settings();
      DbRow? existing;
      if (widget.billId != null) {
        existing = await BillDb.getBill(widget.billId!);
      } else if (widget.visitId != null) {
        existing = await BillDb.billForVisit(widget.visitId!);
      }

      if (existing != null) {
        _fromBill(existing);
      } else if (widget.visitId != null) {
        await _draftFromVisit(widget.visitId!);
      } else if (widget.patientProgram != null) {
        final pp = widget.patientProgram!;
        _patient = await Db.getPatient(pp['patient_id']);
        _items.add(_item('program', str(pp['name']),
            detail: '${fmtDate(pp['start_date'])} – ${fmtDate(pp['end_date'])} · consultations included',
            rate: (pp['price'] ?? 0) as num));
      } else if (widget.patientId != null) {
        _patient = await Db.getPatient(widget.patientId!);
      }
      if (_billId == null) _paid.text = _fmt(_total);
    } catch (e) {
      if (mounted) showMsg(context, 'Could not load bill: $e', error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  void _fromBill(DbRow b) {
    _billId = b['id'];
    _billNo = str(b['bill_no']);
    _billDate = DateTime.tryParse(str(b['bill_date']))?.toLocal() ?? DateTime.now();
    _status = str(b['status']);
    _patient = b['patients'] as DbRow?;
    _visit = b['visits'] as DbRow?;
    _discount.text = _fmt((b['discount'] ?? 0) as num);
    _paid.text = _fmt((b['paid_amount'] ?? 0) as num);
    _mode = str(b['payment_mode']).isEmpty ? 'cash' : str(b['payment_mode']);
    _notes.text = str(b['notes']);
    _paidTouched = true;
    final items = ((b['bill_items'] as List?) ?? []).cast<DbRow>()
      ..sort((a, c) => ((a['sort'] ?? 0) as num).compareTo((c['sort'] ?? 0) as num));
    _items
      ..clear()
      ..addAll(items.map((i) => {
            'kind': i['kind'],
            'description': i['description'],
            'detail': i['detail'],
            'qty': i['qty'],
            'rate': i['rate'],
            'amount': i['amount'],
          }));
  }

  Future<void> _draftFromVisit(String visitId) async {
    final v = await Db.getVisit(visitId);
    _visit = v;
    _patient = v['patients'] as DbRow?;
    final type = str(v['visit_type']);

    // 1. Consultation fee (1 month / 4 visits rule, programs, therapy)
    final fee = await BillDb.consultationCheck(v['patient_id'], visitType: type);
    _feeNote = fee.note;
    final feeAmt = (_settings['consultation_fee'] ?? 300) as num;
    final validDays = (_settings['fee_valid_days'] ?? 30) as num;
    final validVisits = (_settings['fee_valid_visits'] ?? 4) as num;
    final consultName = type == 'first' ? 'Initial consultation' : 'Consultation';
    if (fee.charge) {
      final until = DateTime.now().add(Duration(days: validDays.toInt()));
      _items.add(_item('consultation', consultName,
          detail: 'Valid until ${fmtDate(until)} or ${validVisits.toInt()} visits', rate: feeAmt));
    } else if (type != 'therapy') {
      _items.add(_item('consultation', consultName, detail: fee.note, rate: 0));
    }

    // 2. Medicines given in this visit
    for (final r in await Db.prescriptions(visitId)) {
      final med = (r['medicines'] ?? {}) as Map;
      final b = (r['medicine_batches'] ?? {}) as Map;
      final exp = DateTime.tryParse(str(b['expiry_date']));
      final qty = ((r['quantity'] ?? 0) as num) > 0 ? r['quantity'] as num : 1;
      _items.add(_item('medicine', str(med['name']),
          detail: [
            if (str(b['batch_no']).isNotEmpty) 'Batch ${b['batch_no']}',
            if (exp != null) 'Exp ${DateFormat('MM/yyyy').format(exp)}',
            [str(r['dose']), str(r['frequency']), str(r['timing'])].where((s) => s.isNotEmpty).join(' '),
            if (r['days'] != null) '${r['days']} days',
          ].where((s) => s.isNotEmpty).join(' · '),
          qty: qty,
          rate: (med['price'] ?? 0) as num));
    }

    // 3. Treatments advised in this visit
    for (final a in await Db.visitAdvice(visitId)) {
      _items.add(_item('treatment', str(a['name']),
          detail: str(a['notes']).isEmpty ? null : str(a['notes']),
          qty: (a['sessions'] ?? 1) as num,
          rate: (a['charge'] ?? 0) as num));
    }
  }

  // ------------------------------------------------------------ edit items
  Future<void> _editItem([int? index]) async {
    final it = index == null ? _item('other', '') : _items[index];
    final desc = TextEditingController(text: str(it['description']));
    final detail = TextEditingController(text: str(it['detail']));
    final qty = TextEditingController(text: _fmt(it['qty'] as num));
    final rate = TextEditingController(text: _fmt(it['rate'] as num));
    String kind = str(it['kind']);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(index == null ? 'Add item' : 'Edit item'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _kindLabels.entries
                    .map((e) => ChoiceChip(
                          label: Text(e.value),
                          selected: kind == e.key,
                          onSelected: (_) => set(() => kind = e.key),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 12),
              Field('Description', desc),
              Field('Detail line (optional)', detail),
              Row(children: [
                Expanded(
                    child: Field('Qty', qty,
                        keyboard: const TextInputType.numberWithOptions(decimal: true))),
                const SizedBox(width: 10),
                Expanded(
                    child: Field('Rate', rate,
                        keyboard: const TextInputType.numberWithOptions(decimal: true), suffix: '₹')),
              ]),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true || desc.text.trim().isEmpty) return;
    final q = toNum(qty.text) ?? 1, r = toNum(rate.text) ?? 0;
    final updated = {
      'kind': kind,
      'description': desc.text.trim(),
      'detail': detail.text.trim().isEmpty ? null : detail.text.trim(),
      'qty': q,
      'rate': r,
      'amount': q * r,
    };
    setState(() => index == null ? _items.add(updated) : _items[index] = updated);
    _recalc();
  }

  // ------------------------------------------------------------ save
  Future<bool> _save() async {
    if (_patient == null) return false;
    if (_items.isEmpty) {
      showMsg(context, 'Add at least one item', error: true);
      return false;
    }
    setState(() => _saving = true);
    final paid = (toNum(_paid.text) ?? 0).clamp(0, double.infinity);
    final status = _status == 'cancelled'
        ? 'cancelled'
        : (paid >= _total - 0.009 ? 'paid' : (paid > 0 ? 'partial' : 'pending'));
    final bill = <String, dynamic>{
      'patient_id': _patient!['id'],
      'visit_id': widget.visitId ?? _visit?['id'],
      if (widget.patientProgram != null) 'patient_program_id': widget.patientProgram!['id'],
      'subtotal': _subtotal,
      'discount': _disc,
      'gst_rate': _gstRate,
      'gst_amount': (_gst * 100).round() / 100,
      'total': _total,
      'paid_amount': paid,
      'payment_mode': paid > 0 ? _mode : null,
      'status': status,
      'consultation_charged':
          _items.any((i) => i['kind'] == 'consultation' && (i['amount'] as num) > 0),
      'notes': _notes.text.trim(),
    };
    bill.removeWhere((k, v) => k == 'visit_id' && v == null);
    var ok = false;
    try {
      final id = await BillDb.saveBill(bill, _items, id: _billId);
      final saved = await BillDb.getBill(id);
      _fromBill(saved);
      ok = true;
      if (mounted) showMsg(context, 'Bill $_billNo saved');
    } catch (e) {
      if (mounted) showMsg(context, 'Could not save bill: $e', error: true);
    }
    if (mounted) setState(() => _saving = false);
    return ok;
  }

  Future<List<int>?> _pdf() async {
    if (_billId == null && !await _save()) return null;
    final saved = await BillDb.getBill(_billId!);
    final items = ((saved['bill_items'] as List?) ?? []).cast<DbRow>()
      ..sort((a, c) => ((a['sort'] ?? 0) as num).compareTo((c['sort'] ?? 0) as num));
    final v = saved['visits'] as Map?;
    final visitLabel = v == null
        ? (items.any((i) => i['kind'] == 'program') ? 'Program enrolment' : '')
        : '${_visitTypes[v['visit_type']] ?? ''} · ${v['mode'] == 'online' ? 'Online' : 'In clinic'}';
    final next = saved['visit_id'] == null ? null : await BillDb.nextVisit(saved['visit_id']);
    return BillPdf.build(
      bill: saved,
      items: items,
      patient: (saved['patients'] ?? {}) as DbRow,
      visitLabel: visitLabel,
      doctorName: await BillDb.doctorName(),
      nextVisit: next,
      gstin: _gstOn ? str(_settings['gstin']) : null,
    );
  }

  Future<void> _share() async {
    try {
      final bytes = await _pdf();
      if (bytes == null) return;
      await Printing.sharePdf(bytes: Uint8ListFrom(bytes).value, filename: '$_billNo.pdf');
    } catch (e) {
      if (mounted) showMsg(context, 'Could not create PDF: $e', error: true);
    }
  }

  Future<void> _print() async {
    try {
      final bytes = await _pdf();
      if (bytes == null) return;
      await Printing.layoutPdf(onLayout: (_) async => Uint8ListFrom(bytes).value, name: _billNo);
    } catch (e) {
      if (mounted) showMsg(context, 'Could not print: $e', error: true);
    }
  }

  Future<void> _cancelBill() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Cancel this bill?'),
        content: const Text('The bill stays in records as Cancelled and stops counting in totals.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('No')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Cancel bill')),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    final ok = await guard(context, () => BillDb.cancelBill(_billId!));
    if (ok && mounted) Navigator.pop(context, true);
  }

  // ------------------------------------------------------------ UI
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(appBar: AppBar(title: const Text('Bill')), body: const Center(child: CircularProgressIndicator()));
    }
    final p = _patient ?? {};
    final cancelled = _status == 'cancelled';
    return Scaffold(
      appBar: AppBar(
        title: Text(_billNo.isEmpty ? 'New bill' : _billNo),
        actions: [
          if (_billId != null && !cancelled)
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'cancel') _cancelBill();
              },
              itemBuilder: (_) => const [PopupMenuItem(value: 'cancel', child: Text('Cancel bill'))],
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _saving ? null : _print,
                icon: const Icon(Icons.print_outlined),
                label: const Text('Print'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _saving ? null : _share,
                icon: const Icon(Icons.share_outlined),
                label: const Text('Share'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                onPressed: _saving || cancelled ? null : _save,
                child: Text(_saving ? '…' : (_billId == null ? 'SAVE' : 'UPDATE')),
              ),
            ),
          ]),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Brand.slate,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(str(p['name']),
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                        [
                          str(p['patient_code']),
                          if (_visit != null) _visitTypes[_visit!['visit_type']] ?? '',
                          DateFormat('d MMM yyyy').format(_billDate),
                        ].where((s) => s.isNotEmpty).join(' · '),
                        style: const TextStyle(color: Colors.white70)),
                  ]),
                ),
                if (_billId != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20)),
                    child: Text(
                        const {
                              'paid': 'PAID',
                              'partial': 'PART PAID',
                              'pending': 'DUE',
                              'cancelled': 'CANCELLED'
                            }[_status] ??
                            _status,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                  ),
              ]),
            ),
          ),
          if (_feeNote.isNotEmpty) ...[
            const SizedBox(height: 10),
            Tag(_feeNote, color: Brand.teal),
          ],
          const SizedBox(height: 14),
          SectionCard(
            title: 'Items',
            trailing: cancelled
                ? null
                : TextButton.icon(
                    onPressed: () => _editItem(), icon: const Icon(Icons.add), label: const Text('Add')),
            child: _items.isEmpty
                ? const Text('No items yet', style: TextStyle(color: Brand.muted))
                : Column(
                    children: [
                      for (var i = 0; i < _items.length; i++)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text(str(_items[i]['description']),
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                          subtitle: Text(
                              [
                                _kindLabels[_items[i]['kind']] ?? '',
                                if (str(_items[i]['detail']).isNotEmpty) str(_items[i]['detail']),
                                '${_fmt(_items[i]['qty'])} × ₹${_fmt(_items[i]['rate'])}',
                              ].join(' · '),
                              style: const TextStyle(fontSize: 12)),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text('₹${BillPdf.m(_items[i]['amount'])}',
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                            if (!cancelled)
                              IconButton(
                                icon: const Icon(Icons.close, size: 18, color: Brand.muted),
                                onPressed: () {
                                  setState(() => _items.removeAt(i));
                                  _recalc();
                                },
                              ),
                          ]),
                          onTap: cancelled ? null : () => _editItem(i),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: 'Total',
            child: Column(children: [
              _row('Subtotal', '₹${BillPdf.m(_subtotal)}'),
              const SizedBox(height: 8),
              Row(children: [
                const Expanded(child: Text('Discount')),
                for (final pc in [5, 10])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ActionChip(
                      label: Text('$pc%'),
                      onPressed: () => _discount.text = _fmt((_subtotal * pc / 100).roundToDouble()),
                    ),
                  ),
                SizedBox(
                  width: 100,
                  child: TextField(
                    controller: _discount,
                    textAlign: TextAlign.right,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(prefixText: '₹ ', isDense: true),
                  ),
                ),
              ]),
              if (_gstOn) ...[
                const SizedBox(height: 8),
                _row('GST ($_gstRate%)', '₹${BillPdf.m(_gst)}'),
              ],
              const Divider(height: 24),
              _row('Total', '₹${BillPdf.m(_total)}', big: true),
            ]),
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: 'Payment',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  children: _payModes.entries
                      .map((e) => ChoiceChip(
                            label: Text(e.value),
                            selected: _mode == e.key,
                            onSelected: cancelled ? null : (_) => setState(() => _mode = e.key),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _paid,
                      onChanged: (_) => setState(() => _paidTouched = true),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Amount paid', prefixText: '₹ '),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                      onPressed: () => setState(() {
                            _paid.text = _fmt(_total);
                            _paidTouched = true;
                          }),
                      child: const Text('Full')),
                  TextButton(
                      onPressed: () => setState(() {
                            _paid.text = '0';
                            _paidTouched = true;
                          }),
                      child: const Text('Not paid')),
                ]),
                if ((toNum(_paid.text) ?? 0) < _total - 0.009)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('Balance due ₹${BillPdf.m(_total - (toNum(_paid.text) ?? 0))}',
                        style: const TextStyle(color: Brand.danger, fontWeight: FontWeight.w600)),
                  ),
                const SizedBox(height: 12),
                Field('Notes (optional)', _notes),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _row(String k, String v, {bool big = false}) => Row(children: [
        Expanded(
            child: Text(k,
                style: TextStyle(fontSize: big ? 18 : 14, fontWeight: big ? FontWeight.w700 : FontWeight.w400))),
        Text(v, style: TextStyle(fontSize: big ? 18 : 14, fontWeight: big ? FontWeight.w700 : FontWeight.w500)),
      ]);
}

/// Small helper so List<int> from the PDF works with printing APIs.
class Uint8ListFrom {
  Uint8ListFrom(List<int> b) : value = b is Uint8List ? b : Uint8List.fromList(b);
  final Uint8List value;
}
