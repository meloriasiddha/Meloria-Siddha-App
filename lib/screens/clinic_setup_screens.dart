import 'package:flutter/material.dart';

import '../services/db.dart';
import '../services/patient_app_db.dart';
import '../theme.dart';
import '../widgets/common.dart';

String _hm(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

String _clock(dynamic v) {
  final p = str(v).split(':');
  if (p.length < 2) return '';
  final h = int.parse(p[0]), m = int.parse(p[1]);
  return '${h % 12 == 0 ? 12 : h % 12}:${m.toString().padLeft(2, '0')} ${h >= 12 ? 'PM' : 'AM'}';
}

// =====================================================================
// Clinic closed days and doctor "not available" times
// =====================================================================
class AvailabilityScreen extends StatefulWidget {
  const AvailabilityScreen({super.key});

  @override
  State<AvailabilityScreen> createState() => _AvailabilityScreenState();
}

class _AvailabilityScreenState extends State<AvailabilityScreen> {
  List<DbRow> _blocks = [];
  List<Map<String, dynamic>> _sessions = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final b = await PatientAppDb.blocks();
      final s = await PatientAppDb.settings();
      if (mounted) {
        setState(() {
          _blocks = b;
          _sessions = ((s['sessions'] as List?) ?? []).cast<Map<String, dynamic>>();
        });
      }
    } catch (e) {
      if (mounted) showMsg(context, 'Could not load: $e', error: true);
    }
  }

  Future<void> _add(String kind) async {
    DateTime date = DateTime.now();
    String part = kind == 'closed' ? 'day' : 'custom';
    TimeOfDay start = const TimeOfDay(hour: 18, minute: 30);
    TimeOfDay end = const TimeOfDay(hour: 19, minute: 0);
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(kind == 'closed' ? 'Mark clinic closed' : 'Doctor not available'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_month_outlined),
                label: Text(fmtDate(date)),
                onPressed: () async {
                  final d = await showDatePicker(
                      context: ctx,
                      initialDate: date,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)));
                  if (d != null) set(() => date = d);
                },
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 6, runSpacing: 6, children: [
                if (kind == 'closed')
                  ChoiceChip(label: const Text('Whole day'), selected: part == 'day', onSelected: (_) => set(() => part = 'day')),
                for (final s in _sessions)
                  ChoiceChip(
                      label: Text(str(s['name'])),
                      selected: part == s['name'],
                      onSelected: (_) => set(() => part = s['name'])),
                ChoiceChip(label: const Text('Set times'), selected: part == 'custom', onSelected: (_) => set(() => part = 'custom')),
              ]),
              if (part == 'custom') ...[
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final t = await showTimePicker(context: ctx, initialTime: start);
                        if (t != null) set(() => start = t);
                      },
                      child: Text('From ${start.format(ctx)}'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final t = await showTimePicker(context: ctx, initialTime: end);
                        if (t != null) set(() => end = t);
                      },
                      child: Text('To ${end.format(ctx)}'),
                    ),
                  ),
                ]),
              ],
              const SizedBox(height: 12),
              Field('Reason (optional)', reason),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    String? s, e;
    if (part == 'custom') {
      s = _hm(start);
      e = _hm(end);
    } else if (part != 'day') {
      final sess = _sessions.firstWhere((x) => x['name'] == part);
      s = str(sess['start']);
      e = str(sess['end']);
    }
    await guard(
        context,
        () => PatientAppDb.addBlock({
              'block_date': isoDate(date),
              'start_time': s,
              'end_time': e,
              'kind': kind,
              'reason': reason.text.trim(),
            }));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Clinic availability')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text(
            'The clinic is open every day. Mark closed days or times the doctor is not available; patients cannot book them.',
            style: TextStyle(color: Brand.muted)),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
              child: FilledButton.icon(
                  onPressed: () => _add('closed'),
                  icon: const Icon(Icons.event_busy_outlined),
                  label: const Text('Clinic closed'))),
          const SizedBox(width: 10),
          Expanded(
              child: OutlinedButton.icon(
                  onPressed: () => _add('unavailable'),
                  icon: const Icon(Icons.do_not_disturb_on_outlined),
                  label: const Text('Not available'))),
        ]),
        const SizedBox(height: 18),
        if (_blocks.isEmpty) const EmptyState(Icons.event_available_outlined, 'Nothing marked. The clinic is open as usual.'),
        ..._blocks.map((b) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: ListTile(
                  leading: Icon(b['kind'] == 'closed' ? Icons.event_busy_outlined : Icons.do_not_disturb_on_outlined,
                      color: b['kind'] == 'closed' ? Brand.danger : Brand.warning),
                  title: Text('${fmtDate(b['block_date'])} · ${b['start_time'] == null ? 'Whole day' : '${_clock(b['start_time'])} – ${_clock(b['end_time'])}'}'),
                  subtitle: Text([b['kind'] == 'closed' ? 'Clinic closed' : 'Doctor not available', str(b['reason'])]
                      .where((s) => s.isNotEmpty)
                      .join(' · ')),
                  trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        await guard(context, () => PatientAppDb.deleteBlock(b['id']));
                        _load();
                      }),
                ),
              ),
            )),
      ]),
    );
  }
}

// =====================================================================
// Program pages (text + plans) shown in the patient app
// =====================================================================
class ProgramPagesScreen extends StatefulWidget {
  const ProgramPagesScreen({super.key});
  @override
  State<ProgramPagesScreen> createState() => _ProgramPagesScreenState();
}

class _ProgramPagesScreenState extends State<ProgramPagesScreen> {
  List<DbRow> _list = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await PatientAppDb.programsWithPlans();
    if (mounted) setState(() => _list = r.where((p) => str(p['name']).endsWith('Program')).toList());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Program pages & prices')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          const Text('What patients see in the app. Tap a program to edit its text and plan prices.',
              style: TextStyle(color: Brand.muted)),
          const SizedBox(height: 12),
          ..._list.map((p) {
            final plans = ((p['program_plans'] as List?) ?? []).cast<Map>()
              ..sort((a, b) => (a['months'] as num).compareTo(b['months'] as num));
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: ListTile(
                  title: Text(str(p['name']), style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(plans.map((x) => '${x['months']}m ₹${x['price']}${x['recommended'] == true ? '★' : ''}').join(' · ')),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => ProgramEditScreen(program: p)));
                    _load();
                  },
                ),
              ),
            );
          }),
        ]),
      );
}

class ProgramEditScreen extends StatefulWidget {
  const ProgramEditScreen({super.key, required this.program});
  final DbRow program;
  @override
  State<ProgramEditScreen> createState() => _ProgramEditScreenState();
}

class _ProgramEditScreenState extends State<ProgramEditScreen> {
  late final _name = TextEditingController(text: str(widget.program['name']));
  late final _subtitle = TextEditingController(text: str(widget.program['subtitle']));
  late final _who = TextEditingController(text: str(widget.program['who_for']));
  late final _steps = TextEditingController(
      text: ((widget.program['steps'] as List?) ?? []).map((e) => e.toString()).join('\n'));
  late final _includes = TextEditingController(text: str(widget.program['includes']));
  late List<Map<String, dynamic>> _plans = ((widget.program['program_plans'] as List?) ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList()
    ..sort((a, b) => (a['months'] as num).compareTo(b['months'] as num));
  final List<String> _deleted = [];

  Future<void> _save() async {
    final ok = await guard(context, () async {
      await PatientAppDb.saveProgram(widget.program['id'], {
        'name': _name.text.trim(),
        'subtitle': _subtitle.text.trim(),
        'who_for': _who.text.trim(),
        'steps': _steps.text.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(),
        'includes': _includes.text.trim(),
      });
      for (final id in _deleted) {
        await PatientAppDb.deletePlan(id);
      }
      for (final p in _plans) {
        await PatientAppDb.savePlan({
          'program_id': widget.program['id'],
          'months': p['months'],
          'price': p['price'],
          'recommended': p['recommended'] == true,
          'note': str(p['note']).isEmpty ? null : p['note'],
        }, id: p['id']);
      }
    });
    if (ok && mounted) {
      showMsg(context, 'Saved – patients see it straight away');
      Navigator.pop(context);
    }
  }

  Future<void> _editPlan([int? i]) async {
    final p = i == null ? <String, dynamic>{'months': 1, 'price': 0} : _plans[i];
    final months = TextEditingController(text: str(p['months']));
    final price = TextEditingController(text: str(p['price']));
    final note = TextEditingController(text: str(p['note']));
    var rec = p['recommended'] == true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(i == null ? 'Add plan' : 'Edit plan'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Field('Months', months, keyboard: TextInputType.number),
              Field('Price', price, keyboard: TextInputType.number, suffix: '₹'),
              Field('Note (optional)', note, hint: 'Includes post-treatment follow-up'),
              SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Recommended'),
                  value: rec,
                  onChanged: (v) => set(() => rec = v)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('OK')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final updated = {
      ...p,
      'months': toInt(months.text) ?? 1,
      'price': toNum(price.text) ?? 0,
      'note': note.text.trim(),
      'recommended': rec,
    };
    setState(() {
      if (rec) {
        _plans = _plans.map((x) => {...x, 'recommended': false}).toList();
      }
      i == null ? _plans.add(updated) : _plans[i] = updated;
      _plans.sort((a, b) => (a['months'] as num).compareTo(b['months'] as num));
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Edit program')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          SectionCard(
            title: 'Page text',
            child: Column(children: [
              Field('Program name', _name),
              Field('Short description (under the title)', _subtitle, maxLines: 3),
              Field('Who it is for', _who, maxLines: 3),
              Field('How it works – one step per line', _steps, maxLines: 8),
              Field('What you get', _includes, maxLines: 3),
            ]),
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: 'Plans & prices',
            trailing: IconButton(onPressed: () => _editPlan(), icon: const Icon(Icons.add_circle_outline)),
            child: Column(
              children: [
                for (var i = 0; i < _plans.length; i++)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${_plans[i]['months']} months · ₹${_plans[i]['price']}',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text([
                      if (_plans[i]['recommended'] == true) '★ Recommended',
                      str(_plans[i]['note']),
                    ].where((s) => s.isNotEmpty).join(' · ')),
                    onTap: () => _editPlan(i),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => setState(() {
                        if (_plans[i]['id'] != null) _deleted.add(_plans[i]['id']);
                        _plans.removeAt(i);
                      }),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: const Text('SAVE')),
        ]),
      );
}

// =====================================================================
// Doctor profile shown in the patient app + clinic UPI ID
// =====================================================================
class DoctorProfileScreen extends StatefulWidget {
  const DoctorProfileScreen({super.key});
  @override
  State<DoctorProfileScreen> createState() => _DoctorProfileScreenState();
}

class _DoctorProfileScreenState extends State<DoctorProfileScreen> {
  final _name = TextEditingController();
  final _qual = TextEditingController();
  final _title = TextEditingController();
  final _spec = TextEditingController();
  final _reg = TextEditingController();
  final _area = TextEditingController();
  final _upi = TextEditingController();
  DateTime? _since;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    PatientAppDb.settings().then((s) {
      _name.text = str(s['doctor_name']);
      _qual.text = str(s['doctor_qualification']);
      _title.text = str(s['doctor_title']);
      _spec.text = str(s['doctor_specialty']);
      _reg.text = str(s['doctor_reg_no']);
      _area.text = str(s['doctor_experience_area']);
      _upi.text = str(s['clinic_upi_id']);
      _since = DateTime.tryParse(str(s['doctor_experience_since']));
      if (mounted) setState(() => _loading = false);
    });
  }

  int get _years {
    if (_since == null) return 0;
    final n = DateTime.now();
    var y = n.year - _since!.year;
    if (n.month < _since!.month || (n.month == _since!.month && n.day < _since!.day)) y--;
    return y < 0 ? 0 : y;
  }

  Future<void> _save() async {
    final ok = await guard(
        context,
        () => PatientAppDb.saveSettings({
              'doctor_name': _name.text.trim(),
              'doctor_qualification': _qual.text.trim(),
              'doctor_title': _title.text.trim(),
              'doctor_specialty': _spec.text.trim(),
              'doctor_reg_no': _reg.text.trim(),
              'doctor_experience_area': _area.text.trim(),
              'doctor_experience_since': _since == null ? null : isoDate(_since!),
              'clinic_upi_id': _upi.text.trim().isEmpty ? null : _upi.text.trim(),
            }));
    if (ok && mounted) {
      showMsg(context, 'Saved');
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Doctor profile')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(padding: const EdgeInsets.all(16), children: [
                SectionCard(
                  title: 'Shown on the booking screen',
                  child: Column(children: [
                    Field('Name', _name),
                    Row(children: [
                      Expanded(child: Field('Qualification', _qual)),
                      const SizedBox(width: 10),
                      Expanded(flex: 2, child: Field('Title', _title)),
                    ]),
                    Field('Specialty', _spec),
                    Field('Registration number', _reg),
                    Field('Experience in', _area),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Experience counted from'),
                      subtitle: Text(_since == null ? 'Not set' : '${fmtDate(_since)}  →  $_years years today (updates every year)'),
                      trailing: const Icon(Icons.calendar_month_outlined),
                      onTap: () async {
                        final d = await showDatePicker(
                            context: context,
                            initialDate: _since ?? DateTime(2023, 11, 7),
                            firstDate: DateTime(1980),
                            lastDate: DateTime.now());
                        if (d != null) setState(() => _since = d);
                      },
                    ),
                  ]),
                ),
                const SizedBox(height: 14),
                SectionCard(
                  title: 'Online payments',
                  child: Field('Clinic UPI ID (shown to patients for online consultations)', _upi,
                      hint: 'meloria@okaxis'),
                ),
                const SizedBox(height: 8),
                const Text('The doctor photo is part of the patient app; send a new photo to update it.',
                    style: TextStyle(color: Brand.muted, fontSize: 12)),
                const SizedBox(height: 20),
                FilledButton(onPressed: _save, child: const Text('SAVE')),
              ]),
      );
}
