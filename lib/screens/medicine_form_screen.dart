import 'package:flutter/material.dart';

import '../services/db.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Add / edit a medicine and its batches (batch no, expiry, quantity).
class MedicineFormScreen extends StatefulWidget {
  const MedicineFormScreen({super.key, this.medicineId});
  final String? medicineId;

  @override
  State<MedicineFormScreen> createState() => _MedicineFormScreenState();
}

const _forms = [
  'Choornam', 'Lehyam', 'Thailam', 'Kashayam', 'Tablet', 'Capsule',
  'Syrup', 'Parpam', 'Chendooram', 'Manapagu', 'Ointment', 'Other'
];

class _MedicineFormScreenState extends State<MedicineFormScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _unit = TextEditingController();
  final _price = TextEditingController();
  final _alert = TextEditingController(text: '10');
  String _medForm = '';
  String? _id;
  List<DbRow> _batches = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _id = widget.medicineId;
    if (_id != null) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final all = await Db.medicines(activeOnly: false);
    final m = all.firstWhere((x) => x['id'] == _id);
    _name.text = str(m['name']);
    _unit.text = str(m['unit']);
    _price.text = str(m['price']);
    _alert.text = str(m['low_stock_alert']);
    _medForm = str(m['form']);
    _batches = ((m['medicine_batches'] as List?) ?? []).cast<DbRow>()
      ..sort((a, b) => str(a['expiry_date']).compareTo(str(b['expiry_date'])));
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final ok = await guard(context, () async {
      final saved = await Db.saveMedicine({
        'name': _name.text.trim(),
        'form': _medForm,
        'unit': _unit.text.trim(),
        'price': toNum(_price.text) ?? 0,
        'low_stock_alert': toInt(_alert.text) ?? 10,
      }, id: _id);
      _id = saved['id'];
    });
    if (ok && mounted) {
      showMsg(context, 'Medicine saved');
      setState(() {});
    }
  }

  Future<void> _editBatch([DbRow? b]) async {
    if (_id == null) {
      showMsg(context, 'Save the medicine first', error: true);
      return;
    }
    final no = TextEditingController(text: str(b?['batch_no']));
    final qty = TextEditingController(text: str(b?['quantity']));
    final cost = TextEditingController(text: str(b?['purchase_price']));
    DateTime? mfg = DateTime.tryParse(str(b?['mfg_date']));
    DateTime? exp = DateTime.tryParse(str(b?['expiry_date']));

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        Future<void> pick(bool isExp) async {
          final d = await showDatePicker(
            context: ctx,
            firstDate: DateTime(2018),
            lastDate: DateTime(2040),
            initialDate: (isExp ? exp : mfg) ?? DateTime.now(),
          );
          if (d != null) set(() => isExp ? exp = d : mfg = d);
        }

        return AlertDialog(
          title: Text(b == null ? 'Add batch' : 'Edit batch'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Field('Batch number', no),
              Field('Quantity', qty,
                  keyboard: const TextInputType.numberWithOptions(decimal: true),
                  suffix: _unit.text),
              Field('Purchase price (per unit)', cost,
                  keyboard: const TextInputType.numberWithOptions(decimal: true)),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Manufacture date'),
                subtitle: Text(mfg == null ? 'Not set' : fmtDate(mfg)),
                trailing: const Icon(Icons.calendar_month_outlined),
                onTap: () => pick(false),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Expiry date'),
                subtitle: Text(exp == null ? 'Not set' : fmtDate(exp)),
                trailing: const Icon(Icons.event_busy_outlined),
                onTap: () => pick(true),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        );
      }),
    );
    if (ok != true || no.text.trim().isEmpty || !mounted) return;
    await guard(
        context,
        () => Db.saveBatch({
              'medicine_id': _id,
              'batch_no': no.text.trim(),
              'quantity': toNum(qty.text) ?? 0,
              'purchase_price': toNum(cost.text),
              'mfg_date': mfg == null ? null : isoDate(mfg!),
              'expiry_date': exp == null ? null : isoDate(exp!),
            }, id: b?['id']));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_id == null ? 'New medicine' : 'Medicine')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  SectionCard(
                    title: 'Details',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Field('Medicine name', _name, required: true),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: _forms
                              .map((f) => ChoiceChip(
                                    label: Text(f),
                                    selected: _medForm == f,
                                    onSelected: (s) => setState(() => _medForm = s ? f : ''),
                                  ))
                              .toList(),
                        ),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(child: Field('Unit', _unit, hint: 'g, ml, tablet, bottle')),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Field('Selling price', _price,
                                  keyboard: const TextInputType.numberWithOptions(decimal: true),
                                  suffix: '₹')),
                        ]),
                        Field('Alert when stock below', _alert, keyboard: TextInputType.number),
                        FilledButton(onPressed: _save, child: const Text('SAVE MEDICINE')),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  SectionCard(
                    title: 'Batches',
                    trailing: IconButton(
                        onPressed: () => _editBatch(), icon: const Icon(Icons.add_circle_outline)),
                    child: _batches.isEmpty
                        ? Text(_id == null ? 'Save the medicine, then add batches.' : 'No batches yet.',
                            style: const TextStyle(color: Brand.muted))
                        : Column(
                            children: _batches.map((b) {
                              final e = DateTime.tryParse(str(b['expiry_date']));
                              final expired = e != null && e.isBefore(DateTime.now());
                              final soon = e != null &&
                                  e.isBefore(DateTime.now().add(const Duration(days: 60)));
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text('Batch ${b['batch_no']}',
                                    style: const TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: Text(
                                    'Exp ${e == null ? '-' : fmtDate(e)} · ${b['quantity']} ${_unit.text}'),
                                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                  if (expired)
                                    const Tag('Expired', color: Brand.danger)
                                  else if (soon)
                                    const Tag('Soon', color: Brand.warning),
                                  PopupMenuButton<String>(
                                    onSelected: (v) async {
                                      if (v == 'edit') _editBatch(b);
                                      if (v == 'del') {
                                        await guard(context, () => Db.deleteBatch(b['id']));
                                        _load();
                                      }
                                    },
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(value: 'edit', child: Text('Edit / update qty')),
                                      PopupMenuItem(value: 'del', child: Text('Delete batch')),
                                    ],
                                  ),
                                ]),
                              );
                            }).toList(),
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}
