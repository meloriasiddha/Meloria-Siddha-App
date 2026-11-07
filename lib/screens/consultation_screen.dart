import 'package:flutter/material.dart';

import 'bill_screen.dart';

import '../services/db.dart';
import '../theme.dart';
import '../widgets/allergies_meds.dart';
import '../widgets/common.dart';

/// Doctor's case sheet for one visit.
class ConsultationScreen extends StatefulWidget {
  const ConsultationScreen({super.key, required this.visitId});
  final String visitId;

  @override
  State<ConsultationScreen> createState() => _ConsultationScreenState();
}

const _familyItems = ['Diabetes', 'BP', 'Heart disease', 'Thyroid', 'Asthma', 'Cancer'];
const _habitOptions = {'never': 'Never', 'current': 'Current', 'past': 'Past'};

class _ConsultationScreenState extends State<ConsultationScreen> {
  DbRow? _visit;
  bool _saving = false;

  // case sheet
  final List<Map<String, TextEditingController>> _complaints = [];
  final _hpi = TextEditingController();
  final Set<String> _family = {};
  final _familyNotes = TextEditingController();
  String _alcohol = '';
  final _alcoholNotes = TextEditingController();
  String _smoking = '';
  final _smokingNotes = TextEditingController();
  String _food = '';
  final _sleep = TextEditingController();
  final _bowel = TextEditingController();
  final _diet = TextEditingController();
  final _notes = TextEditingController();
  DateTime? _nextVisit;

  List<DbRow> _rx = [];
  List<DbRow> _advice = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _addComplaint([String c = '', String d = '']) {
    _complaints.add({
      'complaint': TextEditingController(text: c),
      'duration': TextEditingController(text: d),
    });
  }

  Future<void> _load() async {
    try {
      final v = await Db.getVisit(widget.visitId);
      if (v['status'] == 'waiting') {
        await Db.setVisitStatus(widget.visitId, 'with_doctor');
      }
      var c = await Db.consultation(widget.visitId);
      final isNew = c == null;
      // New consultation: carry forward family & personal history from last visit.
      c ??= await Db.lastConsultation(v['patient_id'], widget.visitId);

      if (c != null) {
        if (!isNew) {
          for (final e in (c['complaints'] as List? ?? [])) {
            _addComplaint(str(e['complaint']), str(e['duration']));
          }
          _hpi.text = str(c['history_present']);
          _diet.text = str(c['diet_plan']);
          _notes.text = str(c['doctor_notes']);
          if (c['next_visit'] != null) _nextVisit = DateTime.tryParse(c['next_visit']);
        }
        final fh = (c['family_history'] as Map?) ?? {};
        for (final k in _familyItems) {
          if (fh[k] == true) _family.add(k);
        }
        _familyNotes.text = str(fh['notes']);
        final ph = (c['personal_history'] as Map?) ?? {};
        _alcohol = str(ph['alcohol']);
        _alcoholNotes.text = str(ph['alcohol_notes']);
        _smoking = str(ph['smoking']);
        _smokingNotes.text = str(ph['smoking_notes']);
        _food = str(ph['food']);
        _sleep.text = str(ph['sleep']);
        _bowel.text = str(ph['bowel']);
      }
      if (_complaints.isEmpty) {
        _addComplaint(str(v['main_complaint']));
      }
      _visit = v;
      await _reloadLists();
    } catch (e) {
      if (mounted) showMsg(context, 'Could not load: $e', error: true);
    }
    if (mounted) setState(() {});
  }

  Future<void> _reloadLists() async {
    final rx = await Db.prescriptions(widget.visitId);
    final adv = await Db.visitAdvice(widget.visitId);
    if (mounted) setState(() {
      _rx = rx;
      _advice = adv;
    });
  }

  Future<void> _save({bool finish = false}) async {
    setState(() => _saving = true);
    final fam = <String, dynamic>{for (final k in _familyItems) k: _family.contains(k)};
    fam['notes'] = _familyNotes.text.trim();
    final data = <String, dynamic>{
      'visit_id': widget.visitId,
      'complaints': _complaints
          .where((m) => m['complaint']!.text.trim().isNotEmpty)
          .map((m) => {
                'complaint': m['complaint']!.text.trim(),
                'duration': m['duration']!.text.trim(),
              })
          .toList(),
      'history_present': _hpi.text.trim(),
      'family_history': fam,
      'personal_history': {
        'alcohol': _alcohol,
        'alcohol_notes': _alcoholNotes.text.trim(),
        'smoking': _smoking,
        'smoking_notes': _smokingNotes.text.trim(),
        'food': _food,
        'sleep': _sleep.text.trim(),
        'bowel': _bowel.text.trim(),
      },
      'diet_plan': _diet.text.trim(),
      'doctor_notes': _notes.text.trim(),
      'next_visit': _nextVisit == null ? null : isoDate(_nextVisit!),
    };
    final ok = await guard(context, () async {
      await Db.saveConsultation(data);
      if (finish) await Db.setVisitStatus(widget.visitId, 'done');
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      showMsg(context, finish ? 'Visit completed – prepare the bill' : 'Saved');
      if (finish) {
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => BillScreen(visitId: widget.visitId)));
      }
    }
  }

  // ------------------------------------------------------------ diet template
  Future<void> _pickDietTemplate() async {
    final t = await Db.dietTemplates();
    if (!mounted) return;
    final picked = await showModalBottomSheet<DbRow>(
      context: context,
      builder: (_) => ListView(
        shrinkWrap: true,
        children: [
          const ListTile(title: Text('Diet templates', style: TextStyle(fontWeight: FontWeight.w600))),
          ...t.map((d) => ListTile(
                title: Text(str(d['name'])),
                subtitle: Text(str(d['body']), maxLines: 2, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.pop(context, d),
              )),
        ],
      ),
    );
    if (picked != null) {
      setState(() => _diet.text =
          _diet.text.trim().isEmpty ? str(picked['body']) : '${_diet.text.trim()}\n${picked['body']}');
    }
  }

  // ------------------------------------------------------------ medicines
  Future<void> _addMedicine() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddMedicineSheet(visitId: widget.visitId),
    );
    if (added == true) _reloadLists();
  }

  // ------------------------------------------------------------ advice
  Future<void> _addAdvice() async {
    final items = await Db.adviceItems();
    if (!mounted) return;
    final picked = await showModalBottomSheet<DbRow>(
      context: context,
      builder: (_) => ListView(
        shrinkWrap: true,
        children: [
          const ListTile(
              title: Text('Treatment advice', style: TextStyle(fontWeight: FontWeight.w600))),
          ...items.map((a) => ListTile(
                title: Text(str(a['name'])),
                subtitle: str(a['description']).isEmpty ? null : Text(str(a['description'])),
                trailing: (a['charge'] ?? 0) > 0 ? Text('₹${a['charge']}') : null,
                onTap: () => Navigator.pop(context, a),
              )),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    final sessions = TextEditingController(text: '1');
    final notes = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(str(picked['name'])),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Field('Sessions', sessions, keyboard: TextInputType.number),
          Field('Notes', notes, maxLines: 2),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await guard(
        context,
        () => Db.addVisitAdvice({
              'visit_id': widget.visitId,
              'advice_id': picked['id'],
              'name': picked['name'],
              'sessions': toInt(sessions.text) ?? 1,
              'notes': notes.text.trim(),
              'charge': picked['charge'] ?? 0,
            }));
    _reloadLists();
  }

  // ------------------------------------------------------------ UI
  Widget _chips(Map<String, String> opts, String value, ValueChanged<String> onChanged) => Wrap(
        spacing: 8,
        children: opts.entries
            .map((e) => ChoiceChip(
                  label: Text(e.value),
                  selected: value == e.key,
                  onSelected: (s) => onChanged(s ? e.key : ''),
                ))
            .toList(),
      );

  @override
  Widget build(BuildContext context) {
    final v = _visit;
    if (v == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }
    final p = v['patients'] as Map;
    final vitals = <String>[
      if (v['bp_systolic'] != null) 'BP ${v['bp_systolic']}/${v['bp_diastolic'] ?? '-'}',
      if (v['pulse'] != null) 'Pulse ${v['pulse']}',
      if (v['spo2'] != null) 'SpO2 ${v['spo2']}%',
      if (v['temperature'] != null) '${v['temperature']}°F',
      if (v['weight'] != null) '${v['weight']} kg',
      if (v['random_sugar'] != null) 'RBS ${v['random_sugar']}',
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Consultation'),
        actions: [
          TextButton(onPressed: _saving ? null : () => _save(), child: const Text('Save')),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: _saving ? null : () => _save(finish: true),
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('FINISH VISIT & BILL'),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Brand.slate,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(str(p['name']),
                      style: const TextStyle(
                          color: Colors.white, fontSize: 19, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    [
                      str(p['patient_code']),
                      if (p['age'] != null) '${p['age']} y',
                      str(p['gender']),
                      str(v['visit_type']),
                      str(v['mode']),
                    ].where((s) => s.isNotEmpty).join(' · '),
                    style: const TextStyle(color: Colors.white70),
                  ),
                  if (vitals.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: vitals
                          .map((t) => Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(20)),
                                child: Text(t,
                                    style: const TextStyle(color: Colors.white, fontSize: 12)),
                              ))
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          AllergiesMedsSection(patientId: p['id']),
          const SizedBox(height: 14),

          // Complaints
          SectionCard(
            title: 'Complaints',
            trailing: IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () => setState(() => _addComplaint()),
            ),
            child: Column(
              children: [
                for (var i = 0; i < _complaints.length; i++)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: Field('Complaint', _complaints[i]['complaint']!)),
                      const SizedBox(width: 8),
                      Expanded(
                          flex: 2,
                          child: Field('Duration', _complaints[i]['duration']!, hint: '3 months')),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20, color: Brand.muted),
                        onPressed: () => setState(() => _complaints.removeAt(i)),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: 'History of present complaints',
            child: Field('Onset, progression, aggravating / relieving factors', _hpi, maxLines: 5),
          ),
          const SizedBox(height: 14),

          // Family history
          SectionCard(
            title: 'Family history',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: _familyItems
                      .map((k) => FilterChip(
                            label: Text(k),
                            selected: _family.contains(k),
                            onSelected: (s) =>
                                setState(() => s ? _family.add(k) : _family.remove(k)),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 12),
                Field('Notes (who, other conditions)', _familyNotes, maxLines: 2),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Personal history
          SectionCard(
            title: 'Personal history',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Alcohol', style: TextStyle(color: Brand.muted)),
                const SizedBox(height: 6),
                _chips(_habitOptions, _alcohol, (v) => setState(() => _alcohol = v)),
                if (_alcohol == 'current' || _alcohol == 'past') ...[
                  const SizedBox(height: 8),
                  Field('How much, how long', _alcoholNotes),
                ],
                const SizedBox(height: 12),
                const Text('Smoking', style: TextStyle(color: Brand.muted)),
                const SizedBox(height: 6),
                _chips(_habitOptions, _smoking, (v) => setState(() => _smoking = v)),
                if (_smoking == 'current' || _smoking == 'past') ...[
                  const SizedBox(height: 8),
                  Field('How much, how long', _smokingNotes),
                ],
                const SizedBox(height: 12),
                const Text('Food habit', style: TextStyle(color: Brand.muted)),
                const SizedBox(height: 6),
                _chips({'veg': 'Vegetarian', 'nonveg': 'Non-veg', 'mixed': 'Mixed'}, _food,
                    (v) => setState(() => _food = v)),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: Field('Sleep', _sleep)),
                  const SizedBox(width: 12),
                  Expanded(child: Field('Bowel', _bowel)),
                ]),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Diet plan
          SectionCard(
            title: 'Diet plan',
            trailing: TextButton.icon(
              onPressed: _pickDietTemplate,
              icon: const Icon(Icons.library_books_outlined, size: 18),
              label: const Text('Template'),
            ),
            child: Field('Diet advice for the patient', _diet, maxLines: 6),
          ),
          const SizedBox(height: 14),

          // Medicines
          SectionCard(
            title: 'Medicines',
            trailing: IconButton(
                onPressed: _addMedicine, icon: const Icon(Icons.add_circle_outline)),
            child: _rx.isEmpty
                ? const Text('No medicines added', style: TextStyle(color: Brand.muted))
                : Column(
                    children: _rx.map((r) {
                      final m = (r['medicines'] ?? {}) as Map;
                      final b = (r['medicine_batches'] ?? {}) as Map;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(str(m['name']),
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text([
                          str(r['dose']),
                          str(r['frequency']),
                          str(r['timing']),
                          if (r['days'] != null) '${r['days']} days',
                          'Qty ${r['quantity']} ${str(m['unit'])}',
                          if (str(b['batch_no']).isNotEmpty) 'Batch ${b['batch_no']}',
                        ].where((s) => s.isNotEmpty).join(' · ')),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: Brand.muted),
                          onPressed: () async {
                            await guard(context, () => Db.deletePrescription(r['id']));
                            _reloadLists();
                          },
                        ),
                      );
                    }).toList(),
                  ),
          ),
          const SizedBox(height: 14),

          // Advice
          SectionCard(
            title: 'Treatment advice',
            trailing:
                IconButton(onPressed: _addAdvice, icon: const Icon(Icons.add_circle_outline)),
            child: _advice.isEmpty
                ? const Text('No treatments advised', style: TextStyle(color: Brand.muted))
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _advice
                        .map((a) => InputChip(
                              label: Text(
                                  '${a['name']}${(a['sessions'] ?? 1) > 1 ? ' × ${a['sessions']}' : ''}'),
                              onDeleted: () async {
                                await guard(context, () => Db.deleteVisitAdvice(a['id']));
                                _reloadLists();
                              },
                            ))
                        .toList(),
                  ),
          ),
          const SizedBox(height: 14),

          // Next visit + notes
          SectionCard(
            title: 'Follow-up',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final d in [7, 15, 30])
                      ActionChip(
                        label: Text('$d days'),
                        onPressed: () => setState(
                            () => _nextVisit = DateTime.now().add(Duration(days: d))),
                      ),
                    ActionChip(
                      avatar: const Icon(Icons.calendar_month_outlined, size: 18),
                      label: Text(_nextVisit == null ? 'Pick date' : fmtDate(_nextVisit)),
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: context,
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                          initialDate: _nextVisit ?? DateTime.now().add(const Duration(days: 7)),
                        );
                        if (d != null) setState(() => _nextVisit = d);
                      },
                    ),
                  ],
                ),
                if (_nextVisit != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Tag('Next visit: ${fmtDate(_nextVisit)}', color: Brand.teal),
                  ),
                const SizedBox(height: 14),
                Field('Doctor notes (private)', _notes, maxLines: 3),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// Bottom sheet: choose a medicine from stock and how to take it.
/// The batch with the earliest expiry (that has stock) is picked automatically.
class _AddMedicineSheet extends StatefulWidget {
  const _AddMedicineSheet({required this.visitId});
  final String visitId;

  @override
  State<_AddMedicineSheet> createState() => _AddMedicineSheetState();
}

class _AddMedicineSheetState extends State<_AddMedicineSheet> {
  List<DbRow> _all = [];
  String _q = '';
  DbRow? _med;
  DbRow? _batch;
  final _dose = TextEditingController();
  String _freq = '1-0-1';
  String _timing = 'After food';
  final _days = TextEditingController(text: '15');
  final _qty = TextEditingController();
  final _instr = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    Db.medicines().then((m) {
      if (mounted) setState(() => _all = m);
    });
  }

  List<DbRow> _usableBatches(DbRow m) {
    final today = DateTime.now();
    final b = ((m['medicine_batches'] as List?) ?? [])
        .cast<DbRow>()
        .where((x) => (x['quantity'] ?? 0) > 0)
        .where((x) {
      final e = DateTime.tryParse(str(x['expiry_date']));
      return e == null || e.isAfter(today);
    }).toList();
    b.sort((a, c) => str(a['expiry_date']).compareTo(str(c['expiry_date'])));
    return b;
  }

  num _stock(DbRow m) =>
      ((m['medicine_batches'] as List?) ?? []).fold<num>(0, (s, x) => s + (x['quantity'] ?? 0));

  void _choose(DbRow m) {
    final b = _usableBatches(m);
    setState(() {
      _med = m;
      _batch = b.isEmpty ? null : b.first;
    });
  }

  Future<void> _save() async {
    if (_med == null) return;
    final qty = toNum(_qty.text) ?? 0;
    if (_batch != null && qty > (_batch!['quantity'] ?? 0)) {
      showMsg(context, 'Only ${_batch!['quantity']} left in this batch', error: true);
      return;
    }
    setState(() => _saving = true);
    final ok = await guard(
        context,
        () => Db.addPrescription({
              'visit_id': widget.visitId,
              'medicine_id': _med!['id'],
              'batch_id': _batch?['id'],
              'dose': _dose.text.trim(),
              'frequency': _freq,
              'timing': _timing,
              'days': toInt(_days.text),
              'quantity': qty,
              'instructions': _instr.text.trim(),
            }));
    if (mounted) {
      setState(() => _saving = false);
      if (ok) Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _all
        .where((m) => str(m['name']).toLowerCase().contains(_q.toLowerCase()))
        .toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: _med == null
            ? Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      autofocus: true,
                      onChanged: (v) => setState(() => _q = v),
                      decoration: const InputDecoration(
                          hintText: 'Search medicine', prefixIcon: Icon(Icons.search)),
                    ),
                  ),
                  Expanded(
                    child: list.isEmpty
                        ? const EmptyState(Icons.medication_outlined,
                            'No medicines in stock.\nAdd them in the Stock tab.')
                        : ListView(
                            children: list.map((m) {
                              final s = _stock(m);
                              return ListTile(
                                title: Text(str(m['name'])),
                                subtitle: Text('${str(m['form'])} · Stock $s ${str(m['unit'])}'),
                                trailing: s <= 0 ? const Tag('Out of stock', color: Brand.danger) : null,
                                onTap: () => _choose(m),
                              );
                            }).toList(),
                          ),
                  ),
                ],
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      IconButton(
                          onPressed: () => setState(() => _med = null),
                          icon: const Icon(Icons.arrow_back)),
                      Expanded(
                        child: Text(str(_med!['name']),
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _batch?['id'],
                    decoration: const InputDecoration(labelText: 'Batch (earliest expiry first)'),
                    items: _usableBatches(_med!)
                        .map((b) => DropdownMenuItem<String>(
                              value: b['id'],
                              child: Text(
                                  '${b['batch_no']} · exp ${fmtDate(b['expiry_date'])} · ${b['quantity']} left'),
                            ))
                        .toList(),
                    onChanged: (id) => setState(() =>
                        _batch = _usableBatches(_med!).firstWhere((b) => b['id'] == id)),
                  ),
                  if (_batch == null)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text('No valid batch in stock – will be added without stock deduction.',
                          style: TextStyle(color: Brand.warning, fontSize: 12)),
                    ),
                  const SizedBox(height: 12),
                  Field('Dose', _dose, hint: '1 tsp, 2 tablets, 5 ml…'),
                  const Text('Frequency', style: TextStyle(color: Brand.muted)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: ['1-0-1', '1-1-1', '1-0-0', '0-0-1', '0-1-0', 'SOS']
                        .map((f) => ChoiceChip(
                              label: Text(f),
                              selected: _freq == f,
                              onSelected: (_) => setState(() => _freq = f),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: ['Before food', 'After food', 'With food']
                        .map((t) => ChoiceChip(
                              label: Text(t),
                              selected: _timing == t,
                              onSelected: (_) => setState(() => _timing = t),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: Field('Days', _days, keyboard: TextInputType.number)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Field('Quantity to give', _qty,
                            keyboard: const TextInputType.numberWithOptions(decimal: true),
                            suffix: str(_med!['unit']))),
                  ]),
                  Field('Special instructions', _instr, hint: 'with honey, in warm water…'),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: const Text('ADD MEDICINE'),
                  ),
                ],
              ),
      ),
    );
  }
}
