import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/db.dart';
import '../services/trackers.dart';
import '../services/tracking_db.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/entry_form.dart';
import 'home_screen.dart';
import 'tracking_plan_screen.dart';

/// Chat-style tracking thread for one patient (doctor / staff view).
class TrackingChatScreen extends StatefulWidget {
  const TrackingChatScreen({super.key, required this.patientId});
  final String patientId;

  @override
  State<TrackingChatScreen> createState() => _TrackingChatScreenState();
}

class _TrackingChatScreenState extends State<TrackingChatScreen> {
  DbRow? _patient;
  List<DbRow> _trackers = [];
  List<DbRow> _msgs = [];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  Timer? _timer;
  bool _sending = false;

  String get _me => Session.isDoctor ? Session.name : '${Session.name} (Staff)';

  @override
  void initState() {
    super.initState();
    _load(first: true);
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool first = false}) async {
    try {
      if (first) _patient = await Db.getPatient(widget.patientId);
      final t = await TrackDb.trackers(widget.patientId);
      final m = await TrackDb.thread(widget.patientId);
      final changed = m.length != _msgs.length;
      if (!mounted) return;
      setState(() {
        _trackers = t;
        _msgs = m;
      });
      if (m.any((x) => x['sender_type'] == 'patient' && x['read_by_staff'] == false)) {
        TrackDb.markRead(widget.patientId);
      }
      if (changed) _toBottom();
    } catch (e) {
      if (first && mounted) showMsg(context, 'Could not load: $e', error: true);
    }
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        }
      });

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    final ok = await guard(
        context,
        () => TrackDb.post({
              'patient_id': widget.patientId,
              'kind': 'message',
              'body': text,
              'sender_type': 'staff',
              'sender_name': _me,
              'read_by_staff': true,
            }));
    if (ok) _input.clear();
    if (mounted) setState(() => _sending = false);
    _load();
  }

  Future<DbRow?> _chooseTracker(String title) async {
    if (_trackers.isEmpty) {
      showMsg(context, 'No trackers yet. Set up the plan first.', error: true);
      return null;
    }
    if (_trackers.length == 1) return _trackers.first;
    return showModalBottomSheet<DbRow>(
      context: context,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600))),
            ..._trackers.map((t) {
              final d = Trackers.def(str(t['kind']));
              return ListTile(
                leading: Icon(d.icon, color: d.color),
                title: Text(str(t['label']).isNotEmpty ? str(t['label']) : d.label),
                onTap: () => Navigator.pop(context, t),
              );
            }),
          ],
        ),
      ),
    );
  }

  Future<void> _addReading() async {
    final t = await _chooseTracker('Add reading for patient');
    if (t == null || !mounted) return;
    final r = await showEntryForm(context, t);
    if (r == null || !mounted) return;
    await guard(
        context,
        () => TrackDb.post({
              'patient_id': widget.patientId,
              'tracker_id': t['id'],
              'kind': 'entry',
              'entry_type': t['kind'],
              'slot': r.slot,
              'data': r.data,
              'sender_type': 'staff',
              'sender_name': _me,
              'read_by_staff': true,
            }));
    _load();
  }

  Future<void> _requestTest() async {
    final t = await _chooseTracker('Request from patient');
    if (t == null || !mounted) return;
    final def = Trackers.def(str(t['kind']));
    final slots = ((t['slots'] as List?) ?? []).map((e) => e.toString()).toList();
    final opts = slots.isNotEmpty ? slots : def.slots.keys.toList();
    String? slot = opts.isNotEmpty ? opts.first : null;
    DateTime due = DateTime.now();
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text('Request ${def.label.toLowerCase()}'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (opts.isNotEmpty)
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: opts
                      .map((s) => ChoiceChip(
                            label: Text(def.slots[s] ?? s),
                            selected: slot == s,
                            onSelected: (_) => set(() => slot = s),
                          ))
                      .toList(),
                ),
              const SizedBox(height: 10),
              Wrap(spacing: 6, children: [
                for (final d in [0, 1, 2, 7])
                  ChoiceChip(
                    label: Text(d == 0 ? 'Today' : (d == 1 ? 'Tomorrow' : 'In $d days')),
                    selected: isoDate(due) == isoDate(DateTime.now().add(Duration(days: d))),
                    onSelected: (_) => set(() => due = DateTime.now().add(Duration(days: d))),
                  ),
              ]),
              const SizedBox(height: 10),
              Field('Note (optional)', note),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send request')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    await guard(
        context,
        () => TrackDb.post({
              'patient_id': widget.patientId,
              'tracker_id': t['id'],
              'kind': 'request',
              'entry_type': t['kind'],
              'slot': slot,
              'due_date': isoDate(due),
              'body': note.text.trim(),
              'sender_type': 'staff',
              'sender_name': _me,
              'read_by_staff': true,
            }));
    _load();
  }

  Future<void> _editPlan() async {
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => TrackingPlanScreen(patientId: widget.patientId)));
    _load();
  }

  // ------------------------------------------------------------ helpers
  DbRow? _trackerFor(DbRow m) {
    for (final t in _trackers) {
      if (t['id'] == m['tracker_id']) return t;
    }
    for (final t in _trackers) {
      if (t['kind'] == m['entry_type']) return t;
    }
    return null;
  }

  /// Returns a warning label if the value is outside the patient's target.
  String? _flag(DbRow m) {
    final kind = str(m['entry_type']);
    final d = (m['data'] ?? {}) as Map;
    if (kind == 'bp') {
      final s = d['systolic'] as num?, di = d['diastolic'] as num?;
      if ((s ?? 0) >= 140 || (di ?? 0) >= 90) return 'High';
      if ((s ?? 999) < 90 || (di ?? 999) < 60) return 'Low';
      return null;
    }
    if (kind == 'spo2') {
      final v = d['value'] as num?;
      return v != null && v < 94 ? 'Low' : null;
    }
    final t = _trackerFor(m);
    final v = d['value'] as num?;
    if (t == null || v == null) return null;
    final hi = t['target_high'] as num?;
    final lo = t['target_low'] as num?;
    if (hi != null && v > hi) return 'Above $hi';
    if (lo != null && v < lo) return 'Below $lo';
    return null;
  }

  /// Change since the previous reading of the same kind (weight, waist, hip).
  String? _delta(int index) {
    final m = _msgs[index];
    final kind = str(m['entry_type']);
    if (!['weight', 'waist', 'hip'].contains(kind)) return null;
    final v = ((m['data'] ?? {}) as Map)['value'] as num?;
    if (v == null) return null;
    for (var i = index - 1; i >= 0; i--) {
      final p = _msgs[i];
      if (p['kind'] == 'entry' && p['entry_type'] == kind) {
        final pv = ((p['data'] ?? {}) as Map)['value'] as num?;
        if (pv == null) return null;
        final diff = v - pv;
        if (diff == 0) return 'No change';
        return '${diff > 0 ? '+' : '−'}${diff.abs().toStringAsFixed(1)}';
      }
    }
    return null;
  }

  // ------------------------------------------------------------ UI
  @override
  Widget build(BuildContext context) {
    final p = _patient;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: p == null
            ? const Text('Tracking')
            : Row(children: [
                PatientAvatar(str(p['name']), radius: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(str(p['name']), style: const TextStyle(fontSize: 16)),
                    Text(
                        [str(p['patient_code']), if (p['age'] != null) '${p['age']} y']
                            .join(' · '),
                        style: const TextStyle(fontSize: 11, color: Brand.muted)),
                  ]),
                ),
              ]),
        actions: [
          IconButton(
              onPressed: _editPlan,
              tooltip: 'Tracking plan',
              icon: const Icon(Icons.tune)),
        ],
      ),
      body: Column(
        children: [
          if (_trackers.isNotEmpty)
            Container(
              color: Colors.white,
              height: 46,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                children: _trackers.map((t) {
                  final d = Trackers.def(str(t['kind']));
                  final slots = ((t['slots'] as List?) ?? []).map((s) => d.slots[s] ?? s).join(', ');
                  final name = str(t['label']).isNotEmpty ? str(t['label']) : d.label;
                  return Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                        color: Brand.sage.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(20)),
                    child: Text(slots.isEmpty ? name : '$name · $slots',
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w600, color: Brand.sageDark)),
                  );
                }).toList(),
              ),
            ),
          Expanded(
            child: _msgs.isEmpty
                ? EmptyState(
                    Icons.forum_outlined,
                    _trackers.isEmpty
                        ? 'No tracking plan yet.\nTap the ⚙ icon above to set one up.'
                        : 'No entries yet.\nPatient readings will appear here.')
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    itemCount: _msgs.length,
                    itemBuilder: (_, i) => _item(i),
                  ),
          ),
          _bottomBar(),
        ],
      ),
    );
  }

  Widget _item(int i) {
    final m = _msgs[i];
    final day = DateTime.parse(m['created_at']).toLocal();
    final prevDay = i == 0 ? null : DateTime.parse(_msgs[i - 1]['created_at']).toLocal();
    final showSep = prevDay == null ||
        prevDay.year != day.year ||
        prevDay.month != day.month ||
        prevDay.day != day.day;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showSep) _sep(day),
        switch (str(m['kind'])) {
          'entry' => _entryCard(m, i),
          'request' => _requestCard(m),
          _ => _bubble(m),
        },
      ],
    );
  }

  Widget _sep(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dd = DateTime(d.year, d.month, d.day);
    final label = dd == today
        ? 'Today'
        : (today.difference(dd).inDays == 1 ? 'Yesterday' : DateFormat('EEE, d MMM').format(d));
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Brand.line),
            borderRadius: BorderRadius.circular(20)),
        child: Text(label,
            style: const TextStyle(fontSize: 11, color: Brand.muted, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _entryCard(DbRow m, int i) {
    final kind = str(m['entry_type']);
    final def = Trackers.def(kind);
    final t = _trackerFor(m);
    final d = (m['data'] ?? {}) as Map;
    final label = (t != null && str(t['label']).isNotEmpty) ? str(t['label']) : def.label;
    final slot = def.slots[str(m['slot'])] ?? '';
    final fromStaff = m['sender_type'] == 'staff';
    final flag = _flag(m);
    final delta = _delta(i);
    final big = def.numeric && kind != 'bp';
    final unit = str(d['unit']).isNotEmpty ? str(d['unit']) : def.unit;

    return Align(
      alignment: fromStaff ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: flag != null ? Brand.danger.withValues(alpha: 0.4) : Brand.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              runSpacing: 4,
              children: [
                Icon(def.icon, size: 16, color: def.color),
                Text(
                    [label.toUpperCase(), if (slot.isNotEmpty) slot.toUpperCase()].join(' · '),
                    style: const TextStyle(
                        fontSize: 10.5, letterSpacing: 0.6, color: Brand.muted, fontWeight: FontWeight.w600)),
                if (flag != null) _pill(flag, Brand.danger),
                if (delta != null) _pill(delta + (delta == 'No change' ? '' : ' $unit'), Brand.sageDark),
              ],
            ),
            const SizedBox(height: 4),
            if (big)
              Text.rich(TextSpan(children: [
                TextSpan(
                    text: Trackers.summary(kind, d),
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
                TextSpan(
                    text: '  $unit',
                    style: const TextStyle(fontSize: 12, color: Brand.muted)),
              ]))
            else
              Text(Trackers.summary(kind, d),
                  style: TextStyle(
                      fontSize: kind == 'bp' ? 20 : 13.5,
                      fontWeight: kind == 'bp' ? FontWeight.w600 : FontWeight.w400)),
            const SizedBox(height: 4),
            Text(
              [
                if (fromStaff) 'Entered by ${m['sender_name']}',
                fmtTime(m['created_at']),
              ].join(' · '),
              style: const TextStyle(fontSize: 10, color: Brand.muted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
        child: Text(t, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: c)),
      );

  Widget _bubble(DbRow m) {
    final mine = m['sender_type'] == 'staff';
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        decoration: BoxDecoration(
          color: mine ? Brand.slate : Colors.white,
          border: mine ? null : Border.all(color: Brand.line),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (mine)
              Text(str(m['sender_name']),
                  style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Brand.sage)),
            Text(str(m['body']),
                style: TextStyle(color: mine ? Colors.white : Brand.slate, fontSize: 13.5, height: 1.35)),
            const SizedBox(height: 2),
            Align(
              alignment: Alignment.centerRight,
              child: Text(fmtTime(m['created_at']),
                  style: TextStyle(fontSize: 10, color: mine ? Colors.white60 : Brand.muted)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _requestCard(DbRow m) {
    final def = Trackers.def(str(m['entry_type']));
    final slot = def.slots[str(m['slot'])] ?? '';
    final due = m['due_date'] == null ? '' : ' · due ${fmtDate(m['due_date'])}';
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF2F7480).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF2F7480).withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('🔔 ${m['sender_name']} requested: ${def.label}${slot.isEmpty ? '' : ' ($slot)'}$due',
                style: const TextStyle(
                    color: Color(0xFF2F7480), fontWeight: FontWeight.w600, fontSize: 12.5)),
            if (str(m['body']).isNotEmpty)
              Text(str(m['body']), style: const TextStyle(fontSize: 12.5)),
          ],
        ),
      ),
    );
  }

  Widget _bottomBar() => Container(
        decoration: const BoxDecoration(
            color: Colors.white, border: Border(top: BorderSide(color: Brand.line))),
        padding: EdgeInsets.fromLTRB(10, 8, 10, 8 + MediaQuery.of(context).padding.bottom),
        child: Column(
          children: [
            SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _barBtn('Add reading', Icons.add, _addReading, primary: true),
                  _barBtn('Request test', Icons.notifications_active_outlined, _requestTest),
                  _barBtn('Edit plan', Icons.tune, _editPlan),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'Reply to ${str(_patient?['name']).split(' ').first}…',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: const BorderSide(color: Brand.line)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _sending ? null : _send,
                style: IconButton.styleFrom(backgroundColor: Brand.slate, minimumSize: const Size(46, 46)),
                icon: const Icon(Icons.send_rounded, color: Colors.white),
              ),
            ]),
          ],
        ),
      );

  Widget _barBtn(String t, IconData i, VoidCallback onTap, {bool primary = false}) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: primary
            ? FilledButton.icon(
                style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                onPressed: onTap,
                icon: Icon(i, size: 18),
                label: Text(t, style: const TextStyle(fontSize: 12.5)),
              )
            : OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                onPressed: onTap,
                icon: Icon(i, size: 18),
                label: Text(t, style: const TextStyle(fontSize: 12.5)),
              ),
      );
}
