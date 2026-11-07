import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/api.dart';
import '../services/trackers.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/entry_form.dart';

/// Health tracker chat: buttons for the trackers the clinic assigned,
/// readings as cards, free messages, replies from the clinic.
class TrackerScreen extends StatefulWidget {
  const TrackerScreen({super.key});

  @override
  State<TrackerScreen> createState() => _TrackerScreenState();
}

const _short = {
  'sugar': 'Sugar',
  'bp': 'BP',
  'waist': 'Waist',
  'hip': 'Hip',
  'spo2': 'SpO2',
};

class _TrackerScreenState extends State<TrackerScreen> {
  List<DbRow> _trackers = [];
  List<DbRow> _msgs = [];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  Timer? _timer;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    AppState.selected.addListener(_load);
    _load();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    AppState.selected.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final pid = AppState.patientId;
    if (pid == null) return;
    try {
      final t = await Api.trackers(pid);
      final m = await Api.thread(pid);
      final changed = m.length != _msgs.length;
      if (!mounted) return;
      setState(() {
        _trackers = t;
        _msgs = m;
      });
      if (changed) _toBottom();
    } catch (_) {}
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        }
      });

  Future<void> _add(DbRow t) async {
    final r = await showEntryForm(context, t);
    if (r == null || !mounted) return;
    try {
      await Api.post(
          patientId: AppState.patientId!,
          kind: 'entry',
          trackerId: t['id'],
          entryType: t['kind'],
          slot: r.slot,
          data: r.data);
    } catch (e) {
      if (mounted) showMsg(context, niceError(e), error: true);
    }
    _load();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await Api.post(patientId: AppState.patientId!, kind: 'message', body: text);
      _input.clear();
    } catch (e) {
      if (mounted) showMsg(context, niceError(e), error: true);
    }
    if (mounted) setState(() => _sending = false);
    _load();
  }

  DbRow? _trackerFor(String? id, String? kind) {
    for (final t in _trackers) {
      if (t['id'] == id) return t;
    }
    for (final t in _trackers) {
      if (t['kind'] == kind) return t;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Row(children: [
          Image.asset('assets/images/logo_symbol.png', height: 30),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Health tracker', style: serif(22)),
            const Text('Meloria Siddha', style: TextStyle(fontSize: 11, color: Brand.muted)),
          ]),
        ]),
      ),
      body: Column(children: [
        Expanded(
          child: _msgs.isEmpty
              ? EmptyState(
                  Icons.forum_outlined,
                  _trackers.isEmpty
                      ? 'Your doctor will set up what to track for you.\nYou can message the clinic below.'
                      : 'Tap a button below to add your first reading.')
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  itemCount: _msgs.length,
                  itemBuilder: (_, i) => _item(i),
                ),
        ),
        Container(
          decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Brand.line))),
          padding: EdgeInsets.fromLTRB(12, 10, 12, 10 + MediaQuery.of(context).padding.bottom),
          child: Column(children: [
            if (_trackers.isNotEmpty)
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: _trackers.map((t) {
                    final d = Trackers.def(str(t['kind']));
                    final label = str(t['label']).isNotEmpty ? str(t['label']) : d.label;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 38),
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                        onPressed: () => _add(t),
                        icon: Icon(d.icon, size: 18),
                        label: Text(str(t['label']).isNotEmpty ? label : (_short[t['kind']] ?? label.split(' ').first)),
                      ),
                    );
                  }).toList(),
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
                    hintText: 'Message the clinic…',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(26)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(26), borderSide: const BorderSide(color: Brand.line)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _sending ? null : _send,
                style: IconButton.styleFrom(backgroundColor: Brand.slate, minimumSize: const Size(48, 48)),
                icon: const Icon(Icons.send_rounded, color: Colors.white),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _item(int i) {
    final m = _msgs[i];
    final day = DateTime.parse(m['created_at']).toLocal();
    final prev = i == 0 ? null : DateTime.parse(_msgs[i - 1]['created_at']).toLocal();
    final sep = prev == null || prev.day != day.day || prev.month != day.month || prev.year != day.year;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (sep)
        Center(
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
            child: Text(_dayLabel(day), style: eyebrow(size: 9.5)),
          ),
        ),
      switch (str(m['kind'])) {
        'entry' => _entry(m),
        'request' => _request(m),
        _ => _bubble(m),
      },
    ]);
  }

  String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final t = DateTime(now.year, now.month, now.day);
    final dd = DateTime(d.year, d.month, d.day);
    if (dd == t) return 'TODAY';
    if (t.difference(dd).inDays == 1) return 'YESTERDAY';
    return DateFormat('EEE, d MMM').format(d).toUpperCase();
  }

  Widget _entry(DbRow m) {
    final kind = str(m['entry_type']);
    final def = Trackers.def(kind);
    final t = _trackerFor(m['tracker_id'], kind);
    final d = Map<String, dynamic>.from((m['data'] ?? {}) as Map);
    final label = (t != null && str(t['label']).isNotEmpty) ? str(t['label']) : def.label;
    final slot = def.slots[str(m['slot'])] ?? '';
    final mine = m['sender_type'] == 'patient';
    final unit = str(d['unit']).isNotEmpty ? str(d['unit']) : def.unit;
    final big = def.numeric && kind != 'bp';
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 290),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: softShadow),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(def.icon, size: 16, color: def.color),
            const SizedBox(width: 6),
            Flexible(
              child: Text([label.toUpperCase(), if (slot.isNotEmpty) slot.toUpperCase()].join(' · '),
                  style: eyebrow(size: 9.5)),
            ),
          ]),
          const SizedBox(height: 4),
          big
              ? Text.rich(TextSpan(children: [
                  TextSpan(text: Trackers.summary(kind, d), style: serif(28, weight: FontWeight.w700)),
                  TextSpan(text: '  $unit', style: const TextStyle(fontSize: 12, color: Brand.muted)),
                ]))
              : Text(Trackers.summary(kind, d),
                  style: TextStyle(fontSize: kind == 'bp' ? 20 : 14, fontWeight: kind == 'bp' ? FontWeight.w600 : FontWeight.w400)),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
                [if (!mine) 'Added by ${m['sender_name']}', fmtTime(m['created_at'])].join(' · '),
                style: const TextStyle(fontSize: 10, color: Brand.muted)),
          ),
        ]),
      ),
    );
  }

  Widget _bubble(DbRow m) {
    final mine = m['sender_type'] == 'patient';
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 290),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
        decoration: BoxDecoration(
          color: mine ? Brand.slate : Colors.white,
          boxShadow: mine ? null : softShadow,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(mine ? 18 : 4),
            bottomRight: Radius.circular(mine ? 4 : 18),
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (!mine)
            Text(str(m['sender_name']),
                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Brand.sageDark)),
          Text(str(m['body']), style: TextStyle(color: mine ? Colors.white : Brand.ink, height: 1.4)),
          Align(
            alignment: Alignment.centerRight,
            child: Text(fmtTime(m['created_at']),
                style: TextStyle(fontSize: 10, color: mine ? Colors.white60 : Brand.muted)),
          ),
        ]),
      ),
    );
  }

  Widget _request(DbRow m) {
    final def = Trackers.def(str(m['entry_type']));
    final slot = def.slots[str(m['slot'])] ?? '';
    final t = _trackerFor(m['tracker_id'], m['entry_type']);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Brand.goldLight,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Brand.gold.withValues(alpha: 0.5)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${m['sender_name']} requested', style: eyebrow(size: 9.5, color: Brand.gold)),
          const SizedBox(height: 4),
          Text('${def.label}${slot.isEmpty ? '' : ' – $slot'}', style: const TextStyle(fontWeight: FontWeight.w600)),
          if (m['due_date'] != null)
            Text('By ${fmtDate(m['due_date'], 'EEE, d MMM')}', style: const TextStyle(fontSize: 12, color: Brand.muted)),
          if (str(m['body']).isNotEmpty) Text(str(m['body']), style: const TextStyle(fontSize: 12.5)),
          if (t != null) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 38)),
              onPressed: () => _add(t),
              child: const Text('Add now'),
            ),
          ],
        ]),
      ),
    );
  }
}
