import 'package:flutter/material.dart';

import '../services/bill_pdf.dart';
import '../services/billing_db.dart';
import '../services/db.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'bill_screen.dart';

/// All bills with daily / weekly / monthly collection and pending payments.
class BillsScreen extends StatefulWidget {
  const BillsScreen({super.key});

  @override
  State<BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends State<BillsScreen> {
  String _range = 'today';
  List<DbRow> _bills = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      if (_range == 'pending') {
        _bills = await BillDb.pendingBills();
      } else {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final from = switch (_range) {
          'week' => today.subtract(Duration(days: today.weekday - 1)),
          'month' => DateTime(now.year, now.month, 1),
          _ => today,
        };
        final to = today.add(const Duration(days: 1));
        _bills = await BillDb.bills(
            fromIso: from.toUtc().toIso8601String(), toIso: to.toUtc().toIso8601String());
      }
    } catch (e) {
      if (mounted) showMsg(context, 'Could not load bills: $e', error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final active = _bills.where((b) => b['status'] != 'cancelled').toList();
    final billed = active.fold<num>(0, (s, b) => s + (b['total'] as num));
    final collected = active.fold<num>(0, (s, b) => s + (b['paid_amount'] as num));
    final byMode = <String, num>{};
    for (final b in active) {
      final m = str(b['payment_mode']);
      if (m.isNotEmpty) byMode[m] = (byMode[m] ?? 0) + (b['paid_amount'] as num);
    }
    const modeNames = {'cash': 'Cash', 'upi': 'UPI', 'card': 'Card', 'online': 'Online', 'other': 'Other'};

    return Scaffold(
      appBar: AppBar(title: const Text('Bills')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: {
                  'today': 'Today',
                  'week': 'This week',
                  'month': 'This month',
                  'pending': 'Payment due',
                }
                    .entries
                    .map((e) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(e.value),
                            selected: _range == e.key,
                            onSelected: (_) {
                              setState(() => _range = e.key);
                              _load();
                            },
                          ),
                        ))
                    .toList(),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              color: Brand.slate,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_range == 'pending' ? 'Balance due' : 'Collected',
                      style: const TextStyle(color: Colors.white70)),
                  Text(
                      '₹${BillPdf.m(_range == 'pending' ? billed - collected : collected)}',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 28, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text(
                      '${active.length} bills · billed ₹${BillPdf.m(billed)}'
                      '${_range == 'pending' ? '' : ' · due ₹${BillPdf.m(billed - collected)}'}',
                      style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  if (byMode.isNotEmpty && _range != 'pending') ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: byMode.entries
                          .map((e) => Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(20)),
                                child: Text('${modeNames[e.key] ?? e.key} ₹${BillPdf.m(e.value)}',
                                    style: const TextStyle(color: Colors.white, fontSize: 12)),
                              ))
                          .toList(),
                    ),
                  ],
                ]),
              ),
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Padding(
                  padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
            else if (_bills.isEmpty)
              const EmptyState(Icons.receipt_long_outlined, 'No bills here.')
            else
              ..._bills.map((b) {
                final p = (b['patients'] ?? {}) as Map;
                final status = str(b['status']);
                final (label, color) = switch (status) {
                  'paid' => ('Paid', Brand.sageDark),
                  'partial' => ('Part paid', Brand.warning),
                  'cancelled' => ('Cancelled', Brand.muted),
                  _ => ('Due', Brand.danger),
                };
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      title: Text(str(p['name']), style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('${b['bill_no']} · ${fmtDate(b['bill_date'])} ${fmtTime(b['bill_date'])}'),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('₹${BillPdf.m(b['total'])}',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  decoration: status == 'cancelled' ? TextDecoration.lineThrough : null)),
                          const SizedBox(height: 4),
                          Tag(label, color: color),
                        ],
                      ),
                      onTap: () async {
                        await Navigator.push(context,
                            MaterialPageRoute(builder: (_) => BillScreen(billId: b['id'])));
                        _load();
                      },
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

/// Programs / packages (Diabetes, PCOD, Weight loss…) with price and length.
class ProgramsScreen extends StatefulWidget {
  const ProgramsScreen({super.key});

  @override
  State<ProgramsScreen> createState() => _ProgramsScreenState();
}

class _ProgramsScreenState extends State<ProgramsScreen> {
  List<DbRow> _list = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await BillDb.programs();
    if (mounted) setState(() => _list = r);
  }

  Future<void> _edit([DbRow? p]) async {
    final name = TextEditingController(text: str(p?['name']));
    final price = TextEditingController(text: str(p?['price']));
    final days = TextEditingController(text: str(p?['duration_days'] ?? 90));
    final desc = TextEditingController(text: str(p?['description']));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(p == null ? 'Add program' : 'Edit program'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Field('Name', name),
            Field('Package price', price,
                keyboard: const TextInputType.numberWithOptions(decimal: true), suffix: '₹'),
            Field('Length', days, keyboard: TextInputType.number, suffix: 'days'),
            Field('Description', desc, maxLines: 2),
          ]),
        ),
        actions: [
          if (p != null)
            TextButton(
              onPressed: () async {
                await BillDb.saveProgram({'active': false}, id: p['id']);
                if (ctx.mounted) Navigator.pop(ctx, true);
              },
              child: const Text('Remove', style: TextStyle(color: Brand.danger)),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (name.text.trim().isEmpty) return;
              await BillDb.saveProgram({
                'name': name.text.trim(),
                'price': toNum(price.text) ?? 0,
                'duration_days': toInt(days.text) ?? 90,
                'description': desc.text.trim(),
              }, id: p?['id']);
              if (ctx.mounted) Navigator.pop(ctx, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Programs & packages')),
      floatingActionButton:
          FloatingActionButton(onPressed: () => _edit(), child: const Icon(Icons.add)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
        children: [
          const Text('Consultations are free while a patient is on an active program.',
              style: TextStyle(color: Brand.muted, fontSize: 13)),
          const SizedBox(height: 12),
          ..._list.map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  child: ListTile(
                    title: Text(str(p['name']), style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${p['duration_days']} days${str(p['description']).isEmpty ? '' : ' · ${p['description']}'}'),
                    trailing: Text('₹${BillPdf.m(p['price'] ?? 0)}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    onTap: () => _edit(p),
                  ),
                ),
              )),
        ],
      ),
    );
  }
}

/// Clinic billing settings: consultation fee rule and GST.
class BillingSettingsScreen extends StatefulWidget {
  const BillingSettingsScreen({super.key});

  @override
  State<BillingSettingsScreen> createState() => _BillingSettingsScreenState();
}

class _BillingSettingsScreenState extends State<BillingSettingsScreen> {
  final _fee = TextEditingController();
  final _days = TextEditingController();
  final _visits = TextEditingController();
  final _gstin = TextEditingController();
  final _gstRate = TextEditingController();
  bool _gst = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    BillDb.settings().then((s) {
      _fee.text = str(s['consultation_fee']);
      _days.text = str(s['fee_valid_days']);
      _visits.text = str(s['fee_valid_visits']);
      _gst = s['gst_enabled'] == true;
      _gstin.text = str(s['gstin']);
      _gstRate.text = str(s['gst_rate'] ?? 0);
      if (mounted) setState(() => _loading = false);
    });
  }

  Future<void> _save() async {
    final ok = await guard(
        context,
        () => BillDb.saveSettings({
              'consultation_fee': toNum(_fee.text) ?? 300,
              'fee_valid_days': toInt(_days.text) ?? 30,
              'fee_valid_visits': toInt(_visits.text) ?? 4,
              'gst_enabled': _gst,
              'gstin': _gstin.text.trim(),
              'gst_rate': toNum(_gstRate.text) ?? 0,
            }));
    if (ok && mounted) {
      showMsg(context, 'Settings saved');
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    const num = TextInputType.numberWithOptions(decimal: true);
    return Scaffold(
      appBar: AppBar(title: const Text('Billing settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SectionCard(
                  title: 'Consultation fee',
                  child: Column(children: [
                    Field('Fee', _fee, keyboard: num, suffix: '₹'),
                    Row(children: [
                      Expanded(child: Field('Valid for', _days, keyboard: TextInputType.number, suffix: 'days')),
                      const SizedBox(width: 12),
                      Expanded(child: Field('or', _visits, keyboard: TextInputType.number, suffix: 'visits')),
                    ]),
                    const Text(
                        'Charged once, then free until the days or visits run out (whichever first). '
                        'Therapy visits and active programs are never charged.',
                        style: TextStyle(color: Brand.muted, fontSize: 12)),
                  ]),
                ),
                const SizedBox(height: 14),
                SectionCard(
                  title: 'GST',
                  child: Column(children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Add GST to bills'),
                      value: _gst,
                      onChanged: (v) => setState(() => _gst = v),
                    ),
                    if (_gst) ...[
                      Field('GSTIN', _gstin),
                      Field('GST rate', _gstRate, keyboard: num, suffix: '%'),
                    ],
                  ]),
                ),
                const SizedBox(height: 24),
                FilledButton(onPressed: _save, child: const Text('SAVE')),
              ],
            ),
    );
  }
}
