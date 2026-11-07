import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/appointments_db.dart';
import '../services/db.dart';
import '../services/patient_app_db.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'book_appointment_screen.dart';
import 'intake_screen.dart';
import 'patient_detail_screen.dart';

/// Colour-coded appointment calendar: Day / Week / Month.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

DateTime _d(DateTime x) => DateTime(x.year, x.month, x.day);
int _mins(String hhmm) {
  final p = hhmm.split(':');
  return int.parse(p[0]) * 60 + int.parse(p[1]);
}

String _fmtMins(int m) {
  final h = m ~/ 60, mm = m % 60;
  final ap = h >= 12 ? 'PM' : 'AM';
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:${mm.toString().padLeft(2, '0')} $ap';
}

class _CalendarScreenState extends State<CalendarScreen> {
  String _view = 'day';
  DateTime _sel = _d(DateTime.now());
  List<DbRow> _appts = [];
  List<DbRow> _blocks = [];
  List<Map<String, dynamic>> _sessions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    ApptDb.sessions().then((s) {
      if (mounted) setState(() => _sessions = s);
    });
    _load();
  }

  DateTime get _weekStart => _sel.subtract(Duration(days: _sel.weekday - 1));

  (DateTime, DateTime) get _range {
    if (_view == 'month') {
      final first = DateTime(_sel.year, _sel.month, 1);
      final start = first.subtract(Duration(days: first.weekday - 1));
      return (start, start.add(const Duration(days: 41)));
    }
    return (_weekStart, _weekStart.add(const Duration(days: 6)));
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final (a, b) = _range;
    try {
      final r = await ApptDb.between(isoDate(a), isoDate(b));
      List<DbRow> bl = [];
      try {
        bl = await PatientAppDb.blocksBetween(isoDate(a), isoDate(b));
      } catch (_) {}
      if (mounted) {
        setState(() {
          _appts = r;
          _blocks = bl;
        });
      }
    } catch (e) {
      if (mounted) showMsg(context, 'Could not load appointments: $e', error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  List<DbRow> _on(DateTime day) =>
      _appts.where((a) => a['appt_date'] == isoDate(day)).toList();

  void _go(int dir) {
    setState(() {
      _sel = switch (_view) {
        'month' => DateTime(_sel.year, _sel.month + dir, 1),
        'week' => _sel.add(Duration(days: 7 * dir)),
        _ => _sel.add(Duration(days: dir)),
      };
    });
    _load();
  }

  Future<void> _book() async {
    final ok = await Navigator.push(
        context, MaterialPageRoute(builder: (_) => BookAppointmentScreen(date: _sel)));
    if (ok == true) _load();
  }

  // ------------------------------------------------------------ actions
  Future<void> _openAppt(DbRow a) async {
    final p = (a['patients'] ?? {}) as Map;
    final status = str(a['status']);
    final type = str(a['appt_type']);
    final mode = str(a['mode']);
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: ApptStyle.background(type, mode), borderRadius: BorderRadius.circular(16)),
              child: DefaultTextStyle(
                style: TextStyle(color: ApptStyle.foreground(mode)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(str(p['name']),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text('${p['patient_code']} · ${str(p['phone'])}'),
                    const SizedBox(height: 8),
                    Text(
                        '${fmtDate(a['appt_date'])} · ${_fmtMins(_mins(str(a['start_time'])))} · ${a['duration_min']} min'),
                    Text([
                      ApptStyle.types[type] ?? type,
                      ApptStyle.modes[mode] ?? mode,
                      if (str(a['therapy_name']).isNotEmpty) str(a['therapy_name']),
                    ].join(' · ')),
                    const SizedBox(height: 6),
                    Text('Status: ${ApptStyle.statuses[status] ?? status}',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (a['booked_by'] == 'patient') const Text('Booked by patient in the app'),
                    if (str(a['program_interest']).isNotEmpty) Text('Interested in: ${a['program_interest']}'),
                    if (str(a['refund_choice']).isNotEmpty)
                      Text(a['refund_choice'] == 'refund' ? 'Patient asked for a refund' : 'Patient kept payment as credit'),
                    if (str(a['notes']).isNotEmpty) Text(str(a['notes'])),
                  ],
                ),
              ),
            ),
            if (status == 'pending_payment')
              ListTile(
                  leading: const Icon(Icons.verified_outlined, color: Brand.sageDark),
                  title: const Text('Payment received – confirm'),
                  onTap: () => Navigator.pop(ctx, 'paid')),
            if (status == 'booked' || status == 'pending_payment')
              ListTile(
                  leading: const Icon(Icons.how_to_reg_outlined, color: Brand.teal),
                  title: const Text('Arrived – start visit'),
                  onTap: () => Navigator.pop(ctx, 'arrived')),
            if (status != 'done')
              ListTile(
                  leading: const Icon(Icons.check_circle_outline, color: Brand.sageDark),
                  title: const Text('Mark done'),
                  onTap: () => Navigator.pop(ctx, 'done')),
            if (status == 'booked' || status == 'pending_payment')
              ListTile(
                  leading: const Icon(Icons.person_off_outlined, color: Brand.warning),
                  title: const Text('No-show'),
                  onTap: () => Navigator.pop(ctx, 'no_show')),
            ListTile(
                leading: const Icon(Icons.edit_calendar_outlined),
                title: const Text('Reschedule / edit'),
                onTap: () => Navigator.pop(ctx, 'edit')),
            ListTile(
                leading: const Icon(Icons.person_outline),
                title: const Text('Open patient'),
                onTap: () => Navigator.pop(ctx, 'patient')),
            if (status != 'cancelled' && status != 'done')
              ListTile(
                  leading: const Icon(Icons.cancel_outlined, color: Brand.danger),
                  title: const Text('Cancel appointment'),
                  onTap: () => Navigator.pop(ctx, 'cancel')),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;

    switch (action) {
      case 'paid':
        await guard(context, () => ApptDb.update(a['id'], {'paid': true, 'status': 'booked'}));
      case 'arrived':
        await _arrived(a);
      case 'done':
      case 'no_show':
        await guard(context, () => ApptDb.setStatus(a['id'], action));
      case 'edit':
        await Navigator.push(
            context, MaterialPageRoute(builder: (_) => BookAppointmentScreen(appointment: a)));
      case 'patient':
        await Navigator.push(context,
            MaterialPageRoute(builder: (_) => PatientDetailScreen(patientId: a['patient_id'])));
      case 'cancel':
        final sure = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Cancel this appointment?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('No')),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Yes, cancel')),
            ],
          ),
        );
        if (sure == true && mounted) {
          await guard(context, () => ApptDb.setStatus(a['id'], 'cancelled'));
        }
    }
    _load();
  }

  /// Creates the visit (waiting list) and opens intake for vitals.
  Future<void> _arrived(DbRow a) async {
    const visitType = {
      'initial': 'first',
      'review': 'review',
      'therapy': 'therapy',
      'procedure': 'therapy',
      'program': 'program',
    };
    String? visitId;
    final ok = await guard(context, () async {
      final v = await Db.saveVisit({
        'patient_id': a['patient_id'],
        'visit_type': visitType[a['appt_type']] ?? 'review',
        'mode': a['mode'] == 'offline' ? 'offline' : 'online',
        'main_complaint': str(a['therapy_name']).isEmpty ? null : str(a['therapy_name']),
      });
      visitId = v['id'];
      await ApptDb.update(a['id'], {'status': 'arrived', 'visit_id': visitId});
    });
    if (ok && mounted && visitId != null) {
      await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => IntakeScreen(patientId: a['patient_id'], visitId: visitId)));
    }
  }

  // ------------------------------------------------------------ UI
  @override
  Widget build(BuildContext context) {
    final title = _view == 'month'
        ? DateFormat('MMMM yyyy').format(_sel)
        : DateFormat('MMMM yyyy').format(_view == 'week' ? _weekStart : _sel);
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(onPressed: () => _go(-1), icon: const Icon(Icons.chevron_left)),
          IconButton(onPressed: () => _go(1), icon: const Icon(Icons.chevron_right)),
          TextButton(
            onPressed: () {
              setState(() => _sel = _d(DateTime.now()));
              _load();
            },
            child: const Text('Today'),
          ),
          const SizedBox(width: 6),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'book',
        onPressed: _book,
        icon: const Icon(Icons.add),
        label: const Text('Book'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'day', label: Text('Day')),
                ButtonSegment(value: 'week', label: Text('Week')),
                ButtonSegment(value: 'month', label: Text('Month')),
              ],
              selected: {_view},
              onSelectionChanged: (s) {
                setState(() => _view = s.first);
                _load();
              },
            ),
          ),
          if (_view != 'month') _weekStrip(),
          _legend(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: switch (_view) {
                      'week' => _weekView(),
                      'month' => _monthView(),
                      _ => _dayView(),
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _dots(List<DbRow> list, {Color? override}) {
    final types = list.map((a) => str(a['appt_type'])).toSet().take(3);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: types
          .map((t) => Container(
                width: 5,
                height: 5,
                margin: const EdgeInsets.symmetric(horizontal: 1),
                decoration: BoxDecoration(
                    color: override ?? ApptStyle.solid(t), shape: BoxShape.circle),
              ))
          .toList(),
    );
  }

  Widget _weekStrip() {
    final days = List.generate(7, (i) => _weekStart.add(Duration(days: i)));
    final today = _d(DateTime.now());
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: days.map((d) {
          final sel = d == _sel;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() {
                _sel = d;
                _view = 'day';
              }),
              child: Container(
                margin: const EdgeInsets.all(3),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: sel ? Brand.slate : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: d == today && !sel ? Brand.sageDark : Brand.line),
                ),
                child: Column(children: [
                  Text(DateFormat('EEE').format(d).toUpperCase(),
                      style: TextStyle(
                          fontSize: 10, color: sel ? Colors.white70 : Brand.muted)),
                  Text('${d.day}',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: sel ? Colors.white : Brand.slate)),
                  const SizedBox(height: 4),
                  SizedBox(height: 5, child: _dots(_on(d), override: sel ? Colors.white : null)),
                ]),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _legend() => SizedBox(
        height: 40,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          children: [
            ...ApptStyle.shortTypes.entries.map((e) => _legendChip(ApptStyle.solid(e.key), e.value)),
            _legendChip(Colors.white, 'Light = Online', border: true),
          ],
        ),
      );

  Widget _legendChip(Color c, String t, {bool border = false}) => Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Brand.line)),
        child: Row(children: [
          Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                  color: c,
                  borderRadius: BorderRadius.circular(3),
                  border: border ? Border.all(color: Brand.slate, width: 1.4) : null)),
          const SizedBox(width: 4),
          Text(t, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        ]),
      );

  // ---------------- Day view: one timeline per clinic session
  Widget _dayView() {
    final list = _on(_sel);
    final used = <String>{};
    final children = <Widget>[];
    final dayBlocks = _blocks.where((b) => b['block_date'] == isoDate(_sel)).toList();
    for (final b in dayBlocks.where((b) => b['start_time'] == null)) {
      children.add(Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Brand.danger.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
        child: Text('Clinic closed all day${str(b['reason']).isEmpty ? '' : ' – ${b['reason']}'}',
            style: const TextStyle(color: Brand.danger, fontWeight: FontWeight.w600)),
      ));
    }
    for (final s in _sessions) {
      final start = _mins(str(s['start']));
      final end = _mins(str(s['end']));
      final inSession = list.where((a) {
        final m = _mins(str(a['start_time']));
        return m >= start && m < end;
      }).toList();
      used.addAll(inSession.map((a) => a['id'] as String));
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
        child: Row(children: [
          Expanded(
            child: Text(
                '${str(s['name']).toUpperCase()} · ${_fmtMins(start)} – ${_fmtMins(end)}',
                style: const TextStyle(
                    fontSize: 11, letterSpacing: 1.1, color: Brand.muted, fontWeight: FontWeight.w600)),
          ),
          Text('${inSession.length} booked',
              style: const TextStyle(fontSize: 11, color: Brand.sageDark, fontWeight: FontWeight.w600)),
        ]),
      ));
      children.add(_timeline(start, end, inSession,
          blocks: dayBlocks.where((b) => b['start_time'] != null).toList()));
    }
    final others = list.where((a) => !used.contains(a['id'])).toList();
    if (others.isNotEmpty) {
      children.add(const Padding(
        padding: EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Text('OUTSIDE SESSION HOURS',
            style: TextStyle(
                fontSize: 11, letterSpacing: 1.1, color: Brand.muted, fontWeight: FontWeight.w600)),
      ));
      children.addAll(others.map(_apptTile));
    }
    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 100), children: children);
  }

  Widget _timeline(int start, int end, List<DbRow> appts, {List<DbRow> blocks = const []}) {
    const px = 3.0; // pixels per minute
    const labelW = 46.0;
    final height = (end - start) * px + 8;

    // Lay out overlapping appointments in columns.
    final items = appts.map((a) {
      final s = _mins(str(a['start_time']));
      final dur = (a['duration_min'] ?? 10) as int;
      return (a: a, s: s, e: s + dur);
    }).toList()
      ..sort((x, y) => x.s.compareTo(y.s));
    final n = items.length;
    final col = List<int>.filled(n, 0);
    final cols = List<int>.filled(n, 1);
    var colEnds = <int>[];
    var cs = 0, cEnd = -1;
    for (var i = 0; i < n; i++) {
      if (i > 0 && items[i].s >= cEnd) {
        for (var k = cs; k < i; k++) {
          cols[k] = colEnds.length;
        }
        cs = i;
        colEnds = <int>[];
        cEnd = -1;
      }
      var c = colEnds.indexWhere((x) => x <= items[i].s);
      if (c == -1) {
        colEnds.add(items[i].e);
        c = colEnds.length - 1;
      } else {
        colEnds[c] = items[i].e;
      }
      col[i] = c;
      if (items[i].e > cEnd) cEnd = items[i].e;
    }
    for (var k = cs; k < n; k++) {
      cols[k] = colEnds.isEmpty ? 1 : colEnds.length;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 10, 10),
        child: LayoutBuilder(builder: (context, box) {
          final w = box.maxWidth - labelW;
          return SizedBox(
            height: height,
            child: Stack(children: [
              for (var m = start; m < end; m += 15)
                Positioned(
                  top: (m - start) * px,
                  left: 0,
                  right: 0,
                  child: Row(children: [
                    SizedBox(
                        width: labelW - 6,
                        child: Text(_fmtMins(m).replaceAll(' AM', '').replaceAll(' PM', ''),
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontSize: 10, color: Brand.muted))),
                    const SizedBox(width: 6),
                    Expanded(child: Container(height: 1, color: Brand.line)),
                  ]),
                ),
              for (final b in blocks)
                if (_mins(str(b['end_time'])) > start && _mins(str(b['start_time'])) < end)
                  Positioned(
                    top: (_mins(str(b['start_time'])).clamp(start, end) - start) * px,
                    left: labelW,
                    right: 0,
                    height: ((_mins(str(b['end_time'])).clamp(start, end) - _mins(str(b['start_time'])).clamp(start, end)) * px)
                        .toDouble(),
                    child: Container(
                      decoration: BoxDecoration(
                          color: Brand.muted.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8)),
                      alignment: Alignment.center,
                      child: Text(
                          b['kind'] == 'closed' ? 'Closed' : 'Doctor not available',
                          style: const TextStyle(color: Brand.muted, fontSize: 11, fontWeight: FontWeight.w600)),
                    ),
                  ),
              for (var i = 0; i < items.length; i++)
                Positioned(
                  top: (items[i].s - start) * px + 2,
                  left: labelW + w * col[i] / cols[i],
                  width: w / cols[i] - 4,
                  height: ((items[i].e - items[i].s) * px - 4).clamp(30.0, 2000.0),
                  child: _block(items[i].a,
                      compact: (items[i].e - items[i].s) * px - 4 < 50),
                ),
            ]),
          );
        }),
      ),
    );
  }

  Widget _block(DbRow a, {bool compact = false}) {
    final p = (a['patients'] ?? {}) as Map;
    final type = str(a['appt_type']);
    final mode = str(a['mode']);
    final status = str(a['status']);
    final fg = ApptStyle.foreground(mode);
    final faded = status == 'done' || status == 'no_show';
    return GestureDetector(
      onTap: () => _openAppt(a),
      child: Opacity(
        opacity: faded ? 0.55 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: ApptStyle.background(type, mode),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: compact ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(
                          text: str(p['name']),
                          style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 12)),
                      if (compact)
                        TextSpan(
                            text: '  ${ApptStyle.shortTypes[type] ?? type}',
                            style: TextStyle(color: fg.withValues(alpha: 0.85), fontSize: 10.5)),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (a['booked_by'] == 'patient') Icon(Icons.phone_android, size: 13, color: fg),
                if (mode != 'offline') Icon(ApptStyle.modeIcon(mode), size: 14, color: fg),
                if (status != 'booked')
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(ApptStyle.statuses[status] ?? status,
                        style: TextStyle(color: fg, fontSize: 10)),
                  ),
              ]),
              if (!compact)
              Flexible(
                child: Text(
                  [
                    ApptStyle.shortTypes[type] ?? type,
                    if (str(a['therapy_name']).isNotEmpty) str(a['therapy_name']),
                    '${a['duration_min']} min',
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: fg.withValues(alpha: 0.85), fontSize: 10.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _apptTile(DbRow a) {
    final p = (a['patients'] ?? {}) as Map;
    final type = str(a['appt_type']);
    final mode = str(a['mode']);
    final fg = ApptStyle.foreground(mode);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: ApptStyle.background(type, mode),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _openAppt(a),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              SizedBox(
                width: 64,
                child: Text(_fmtMins(_mins(str(a['start_time']))),
                    style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 12)),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(str(p['name']),
                        style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
                    Text(
                        '${ApptStyle.shortTypes[type]} · ${ApptStyle.modes[mode]} · ${a['duration_min']} min',
                        style: TextStyle(color: fg.withValues(alpha: 0.85), fontSize: 11)),
                  ],
                ),
              ),
              if (str(a['status']) != 'booked')
                Text(ApptStyle.statuses[str(a['status'])] ?? '',
                    style: TextStyle(color: fg, fontSize: 11)),
            ]),
          ),
        ),
      ),
    );
  }

  // ---------------- Week view: a card per day
  Widget _weekView() {
    final days = List.generate(7, (i) => _weekStart.add(Duration(days: i)));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
      children: days.map((d) {
        final list = _on(d);
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SectionCard(
            title: DateFormat('EEEE, d MMM').format(d),
            trailing: Text('${list.length}', style: const TextStyle(color: Brand.muted)),
            child: list.isEmpty
                ? const Text('No bookings', style: TextStyle(color: Brand.muted))
                : Column(children: list.map(_apptTile).toList()),
          ),
        );
      }).toList(),
    );
  }

  // ---------------- Month view: grid with coloured dots
  Widget _monthView() {
    final (start, _) = _range;
    final today = _d(DateTime.now());
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 100),
      children: [
        Row(
          children: ['M', 'T', 'W', 'T', 'F', 'S', 'S']
              .map((d) => Expanded(
                  child: Center(
                      child: Text(d,
                          style: const TextStyle(
                              color: Brand.muted, fontSize: 12, fontWeight: FontWeight.w600)))))
              .toList(),
        ),
        const SizedBox(height: 6),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 0.8,
          children: List.generate(42, (i) {
            final d = start.add(Duration(days: i));
            final inMonth = d.month == _sel.month;
            final list = _on(d);
            return GestureDetector(
              onTap: () {
                setState(() {
                  _sel = d;
                  _view = 'day';
                });
                _load();
              },
              child: Container(
                margin: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: inMonth ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: d == today ? Brand.sageDark : Brand.line, width: d == today ? 1.6 : 1),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('${d.day}',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: inMonth ? Brand.slate : Brand.muted.withValues(alpha: 0.5))),
                    const SizedBox(height: 4),
                    SizedBox(height: 5, child: _dots(list)),
                    if (list.isNotEmpty)
                      Text('${list.length}', style: const TextStyle(fontSize: 10, color: Brand.muted)),
                  ],
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}
