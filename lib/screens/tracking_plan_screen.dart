import 'package:flutter/material.dart';

import '../services/db.dart';
import '../services/trackers.dart';
import '../services/tracking_db.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// What a patient tracks: chosen by doctor / staff. The patient app only
/// shows these trackers, with reminders at the set times.
class TrackingPlanScreen extends StatefulWidget {
  const TrackingPlanScreen({super.key, required this.patientId});
  final String patientId;

  @override
  State<TrackingPlanScreen> createState() => _TrackingPlanScreenState();
}

class _TrackingPlanScreenState extends State<TrackingPlanScreen> {
  DbRow? _patient;
  List<DbRow> _trackers = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      _patient = await Db.getPatient(widget.patientId);
      _trackers = await TrackDb.trackers(widget.patientId);
    } catch (e) {
      if (mounted) showMsg(context, 'Could not load: $e', error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _applyTemplate(String name) async {
    final t = Trackers.templates[name]!;
    final existing = _trackers.map((x) => x['kind']).toSet();
    final ok = await guard(context, () async {
      for (final e in t.entries) {
        if (existing.contains(e.key)) continue;
        final def = Trackers.def(e.key);
        await TrackDb.saveTracker(_newTrackerData(def, e.value));
      }
    });
    if (ok && mounted) showMsg(context, '$name template added. Adjust as needed.');
    _load();
  }

  DbRow _newTrackerData(TrackerDef def, List<String> slots) {
    final reminders = slots.map((s) => Trackers.slotReminder[s]).whereType<String>().toList();
    if (reminders.isEmpty && def.defaultFrequency != 'as_needed') reminders.add('08:00');
    final p = _patient ?? {};
    return {
      'patient_id': widget.patientId,
      'kind': def.kind,
      'slots': slots,
      'frequency': def.defaultFrequency,
      'reminder_times': reminders,
      if (def.kind == 'sugar') 'target_high': p['sugar_fasting_max'] ?? 130,
      if (def.kind == 'sugar') 'target_low': p['sugar_low_min'] ?? 70,
    };
  }

  Future<void> _edit([DbRow? tracker]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
          builder: (_) => TrackerEditScreen(patientId: widget.patientId, tracker: tracker)),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tracking plan')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'addtr',
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('Tracker'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
              children: [
                if (_patient != null)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: PatientAvatar(str(_patient!['name'])),
                    title: Text(str(_patient!['name']),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(str(_patient!['patient_code'])),
                  ),
                const SizedBox(height: 6),
                SectionCard(
                  title: 'Quick templates',
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: Trackers.templates.keys
                        .map((n) => ActionChip(
                              avatar: const Icon(Icons.auto_awesome_outlined, size: 18),
                              label: Text(n),
                              onPressed: () => _applyTemplate(n),
                            ))
                        .toList(),
                  ),
                ),
                const SizedBox(height: 14),
                if (_trackers.isEmpty)
                  const EmptyState(Icons.track_changes_outlined,
                      'No trackers yet.\nUse a template or tap "+ Tracker".')
                else
                  ..._trackers.map(_trackerCard),
              ],
            ),
    );
  }

  Widget _trackerCard(DbRow t) {
    final def = Trackers.def(str(t['kind']));
    final slots = ((t['slots'] as List?) ?? []).map((s) => def.slots[s] ?? s).toList();
    final rem = ((t['reminder_times'] as List?) ?? []).join(', ');
    final label = str(t['label']).isNotEmpty ? str(t['label']) : def.label;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: ListTile(
          contentPadding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
          leading: CircleAvatar(
            backgroundColor: def.color.withValues(alpha: 0.12),
            child: Icon(def.icon, color: def.color),
          ),
          title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text([
            Trackers.frequencies[str(t['frequency'])] ?? '',
            if (slots.isNotEmpty) slots.join(', '),
            if (rem.isNotEmpty) 'Reminders $rem',
            if (t['target_low'] != null || t['target_high'] != null)
              'Target ${t['target_low'] ?? '–'}–${t['target_high'] ?? '–'} ${str(t['unit']).isEmpty ? def.unit : t['unit']}',
            if (t['end_date'] != null) 'Until ${fmtDate(t['end_date'])}',
          ].where((s) => s.isNotEmpty).join('\n')),
          isThreeLine: true,
          trailing: PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'edit') _edit(t);
              if (v == 'stop') {
                await guard(context, () => TrackDb.stopTracker(t['id']));
                _load();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(value: 'stop', child: Text('Stop tracking')),
            ],
          ),
          onTap: () => _edit(t),
        ),
      ),
    );
  }
}

/// Add or edit one tracker.
class TrackerEditScreen extends StatefulWidget {
  const TrackerEditScreen({super.key, required this.patientId, this.tracker});
  final String patientId;
  final DbRow? tracker;

  @override
  State<TrackerEditScreen> createState() => _TrackerEditScreenState();
}

class _TrackerEditScreenState extends State<TrackerEditScreen> {
  late String _kind = str(widget.tracker?['kind']).isEmpty ? 'sugar' : str(widget.tracker!['kind']);
  late final Set<String> _slots =
      ((widget.tracker?['slots'] as List?) ?? []).map((e) => e.toString()).toSet();
  late String _freq = str(widget.tracker?['frequency']).isEmpty
      ? Trackers.def(_kind).defaultFrequency
      : str(widget.tracker!['frequency']);
  late final Set<int> _days =
      ((widget.tracker?['days'] as List?) ?? []).map((e) => int.parse(e.toString())).toSet();
  late final List<String> _reminders =
      ((widget.tracker?['reminder_times'] as List?) ?? []).map((e) => e.toString()).toList();
  late final _label = TextEditingController(text: str(widget.tracker?['label']));
  late final _unit = TextEditingController(text: str(widget.tracker?['unit']));
  late final _low = TextEditingController(text: str(widget.tracker?['target_low']));
  late final _high = TextEditingController(text: str(widget.tracker?['target_high']));
  late DateTime? _end = DateTime.tryParse(str(widget.tracker?['end_date']));

  TrackerDef get _def => Trackers.def(_kind);

  void _toggleSlot(String s, bool on) {
    setState(() {
      on ? _slots.add(s) : _slots.remove(s);
      final r = Trackers.slotReminder[s];
      if (r != null) {
        if (on && !_reminders.contains(r)) _reminders.add(r);
        if (!on) _reminders.remove(r);
      }
      _reminders.sort();
    });
  }

  Future<void> _addReminder() async {
    final t = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 8, minute: 0));
    if (t == null) return;
    final s = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    setState(() {
      if (!_reminders.contains(s)) _reminders.add(s);
      _reminders.sort();
    });
  }

  Future<void> _save() async {
    if (_kind == 'custom' && _label.text.trim().isEmpty) {
      showMsg(context, 'Give the custom tracker a name', error: true);
      return;
    }
    final data = <String, dynamic>{
      'patient_id': widget.patientId,
      'kind': _kind,
      'label': _label.text.trim().isEmpty ? null : _label.text.trim(),
      'unit': _unit.text.trim().isEmpty ? null : _unit.text.trim(),
      'slots': _slots.toList(),
      'frequency': _freq,
      'days': _freq == 'days' ? (_days.toList()..sort()) : [],
      'reminder_times': _reminders,
      'target_low': toNum(_low.text),
      'target_high': toNum(_high.text),
      'end_date': _end == null ? null : isoDate(_end!),
      'active': true,
    };
    final ok = await guard(context, () => TrackDb.saveTracker(data, id: widget.tracker?['id']));
    if (ok && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.tracker != null;
    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Edit tracker' : 'Add tracker')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionCard(
            title: 'What to track',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: Trackers.all.values
                  .map((d) => ChoiceChip(
                        avatar: Icon(d.icon, size: 18, color: d.color),
                        label: Text(d.label),
                        selected: _kind == d.kind,
                        onSelected: editing
                            ? null
                            : (_) => setState(() {
                                  _kind = d.kind;
                                  _slots.clear();
                                  _reminders.clear();
                                  _freq = d.defaultFrequency;
                                }),
                      ))
                  .toList(),
            ),
          ),
          if (_kind == 'custom') ...[
            const SizedBox(height: 14),
            SectionCard(
              title: 'Custom tracker',
              child: Column(children: [
                Field('Name', _label, hint: 'e.g. Steps, Neck pain score'),
                Field('Unit', _unit, hint: 'e.g. steps, /10'),
              ]),
            ),
          ],
          if (_def.slots.isNotEmpty) ...[
            const SizedBox(height: 14),
            SectionCard(
              title: _kind == 'sugar' ? 'When to check' : 'Which times',
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _def.slots.entries
                    .map((e) => FilterChip(
                          label: Text(e.value),
                          selected: _slots.contains(e.key),
                          onSelected: (on) => _toggleSlot(e.key, on),
                        ))
                    .toList(),
              ),
            ),
          ],
          const SizedBox(height: 14),
          SectionCard(
            title: 'How often',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: Trackers.frequencies.entries
                      .map((e) => ChoiceChip(
                            label: Text(e.value),
                            selected: _freq == e.key,
                            onSelected: (_) => setState(() => _freq = e.key),
                          ))
                      .toList(),
                ),
                if (_freq == 'days') ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    children: List.generate(7, (i) {
                      const n = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                      return FilterChip(
                        label: Text(n[i]),
                        selected: _days.contains(i + 1),
                        onSelected: (on) => setState(() => on ? _days.add(i + 1) : _days.remove(i + 1)),
                      );
                    }),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: 'Reminder times',
            trailing: IconButton(onPressed: _addReminder, icon: const Icon(Icons.add_alarm)),
            child: _reminders.isEmpty
                ? const Text('No reminders', style: TextStyle(color: Brand.muted))
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _reminders
                        .map((r) => InputChip(
                              avatar: const Icon(Icons.alarm, size: 18),
                              label: Text(r),
                              onDeleted: () => setState(() => _reminders.remove(r)),
                            ))
                        .toList(),
                  ),
          ),
          if (_def.numeric) ...[
            const SizedBox(height: 14),
            SectionCard(
              title: 'Target range for this patient',
              child: Row(children: [
                Expanded(
                    child: Field('Low', _low,
                        keyboard: const TextInputType.numberWithOptions(decimal: true))),
                const SizedBox(width: 12),
                Expanded(
                    child: Field('High', _high,
                        keyboard: const TextInputType.numberWithOptions(decimal: true),
                        suffix: _kind == 'custom' ? _unit.text : _def.unit)),
              ]),
            ),
          ],
          const SizedBox(height: 14),
          SectionCard(
            title: 'Track until',
            child: Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.event_outlined, size: 18),
                  label: Text(_end == null ? 'No end date' : fmtDate(_end)),
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 730)),
                      initialDate: _end ?? DateTime.now().add(const Duration(days: 30)),
                    );
                    if (d != null) setState(() => _end = d);
                  },
                ),
              ),
              if (_end != null)
                IconButton(onPressed: () => setState(() => _end = null), icon: const Icon(Icons.close)),
            ]),
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: Text(editing ? 'SAVE' : 'ADD TRACKER')),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
