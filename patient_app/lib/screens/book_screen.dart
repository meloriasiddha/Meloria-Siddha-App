import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/api.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Book (or reschedule) a consultation. Shows only free slots.
class BookScreen extends StatefulWidget {
  const BookScreen({super.key, this.mode = 'offline', this.program, this.reschedule});
  final String mode;
  final String? program; // program the patient wants to join (noted on the booking)
  final DbRow? reschedule; // existing appointment to move

  @override
  State<BookScreen> createState() => _BookScreenState();
}

class _BookScreenState extends State<BookScreen> {
  DbRow? _doctor;
  late String _mode = widget.reschedule != null ? str(widget.reschedule!['mode']) : widget.mode;
  String _type = 'review';
  int _dur = 10;
  late DateTime _date = _today;
  final Map<String, DbRow> _days = {}; // iso date → availability
  String? _slot; // "18:30"
  String _payment = 'clinic';
  bool _loading = true;
  bool _saving = false;

  static DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  List<DateTime> get _dates => List.generate(21, (i) => _today.add(Duration(days: i)));
  String? get _locked => str(AppState.patient?['locked_mode']).isEmpty ? null : str(AppState.patient?['locked_mode']);

  @override
  void initState() {
    super.initState();
    if (_locked != null) _mode = _locked!;
    _load();
  }

  Future<void> _load() async {
    try {
      _doctor = await Api.doctor();
      if (widget.reschedule != null) {
        _type = str(widget.reschedule!['appt_type']);
        _dur = (widget.reschedule!['duration_min'] as num).toInt();
      } else {
        var type = 'initial';
        final pid = AppState.patientId;
        if (pid != null && AppState.confirmed) {
          final v = await Api.visits(pid);
          if (v.isNotEmpty) {
            final last = DateTime.tryParse(str(v.first['visit_date']));
            if (last != null && DateTime.now().difference(last).inDays <= 90) type = 'review';
          }
        }
        _type = type;
        _dur = ((type == 'initial' ? _doctor!['slot_first_min'] : _doctor!['slot_review_min']) ?? 10) as int;
      }
      final results = await Future.wait(_dates.take(14).map((d) => Api.day(d)));
      for (var i = 0; i < results.length; i++) {
        _days[isoDate(_dates[i])] = results[i];
      }
      // Start on the first day that still has a free time
      _date = _dates.take(14).firstWhere(
          (d) => !_closedAllDay(d) && _sessions.any((s) => s.$2.any((t) => _free(d, t))),
          orElse: () => _today);
    } catch (e) {
      if (mounted) showMsg(context, niceError(e), error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _selectDate(DateTime d) async {
    setState(() {
      _date = d;
      _slot = null;
    });
    if (!_days.containsKey(isoDate(d))) {
      final r = await Api.day(d);
      if (mounted) setState(() => _days[isoDate(d)] = r);
    }
  }

  // ------------------------------------------------------------ availability
  int _m(String hhmm) {
    final p = hhmm.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  bool _closedAllDay(DateTime d) {
    final day = _days[isoDate(d)];
    final blocks = (day?['blocks'] as List?) ?? [];
    return blocks.any((b) => b['start'] == null);
  }

  bool _free(DateTime d, int start) {
    final day = _days[isoDate(d)];
    if (day == null) return false;
    final end = start + _dur;
    final now = DateTime.now();
    if (isoDate(d) == isoDate(now) && start <= now.hour * 60 + now.minute + 15) return false;
    for (final b in (day['blocks'] as List? ?? [])) {
      if (b['start'] == null) return false;
      if (start < _m(b['end']) && end > _m(b['start'])) return false;
    }
    for (final a in (day['busy'] as List? ?? [])) {
      final s = _m(a['start']);
      final e = s + (a['dur'] as num).toInt();
      // when rescheduling, the patient's own current slot does not count
      if (widget.reschedule != null &&
          isoDate(d) == str(widget.reschedule!['appt_date']) &&
          s == _m(str(widget.reschedule!['start_time']))) {
        continue;
      }
      if (start < e && end > s) return false;
    }
    return true;
  }

  List<(String, List<int>)> get _sessions {
    final list = ((_doctor?['sessions'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map));
    return list.map((s) {
      final a = _m(s['start']), b = _m(s['end']);
      final times = <int>[];
      for (var t = a; t + _dur <= b; t += 10) {
        times.add(t);
      }
      return ('${s['name']} · ${fmtClock(s['start'])} – ${fmtClock(s['end'])}', times);
    }).toList();
  }

  String _hhmm(int m) => '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
  String _label(int m) => fmtClock(_hhmm(m)).replaceAll(' AM', '').replaceAll(' PM', '');

  // ------------------------------------------------------------ book
  Future<void> _confirm() async {
    if (_slot == null) return;
    final pid = AppState.patientId;
    if (pid == null) return;
    setState(() => _saving = true);
    try {
      if (widget.reschedule != null) {
        await Api.reschedule(widget.reschedule!['id'], _date, _slot!);
        if (!mounted) return;
        showMsg(context, 'Appointment moved to ${DateFormat('EEE d MMM').format(_date)}, ${fmtClock(_slot)}');
        Navigator.pop(context, true);
        return;
      }
      final r = await Api.book(
        patientId: pid,
        date: _date,
        time: _slot!,
        mode: _mode,
        payment: _mode == 'offline' ? _payment : 'online',
        program: widget.program,
      );
      if (!mounted) return;
      await _success(r);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showMsg(context, niceError(e), error: true);
      // refresh the day so the taken slot disappears
      final r = await Api.day(_date);
      if (mounted) setState(() => _days[isoDate(_date)] = r);
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _success(DbRow appt) async {
    final pending = appt['status'] == 'pending_payment';
    final upi = str(_doctor?['upi_id']);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(pending ? Icons.hourglass_top_rounded : Icons.check_circle_outline,
            color: pending ? Brand.gold : Brand.sageDark, size: 44),
        title: Text(pending ? 'Almost done' : 'Appointment confirmed', style: serif(26), textAlign: TextAlign.center),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${DateFormat('EEEE, d MMMM').format(_date)} · ${fmtClock(_slot)}',
              textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('${ApptStyle.types[appt['appt_type']]} · ${ApptStyle.modes[appt['mode']]}',
              textAlign: TextAlign.center, style: const TextStyle(color: Brand.muted)),
          if (pending) ...[
            const SizedBox(height: 14),
            Text(
              upi.isEmpty
                  ? 'Online consultations are confirmed after payment. The clinic will contact you with payment details.'
                  : 'Online consultations are confirmed after payment. Please pay by UPI to $upi and the clinic will confirm.',
              textAlign: TextAlign.center,
              style: const TextStyle(height: 1.5, fontSize: 13),
            ),
          ],
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('DONE'))],
      ),
    );
  }

  // ------------------------------------------------------------ UI
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.reschedule != null ? 'Reschedule' : 'Book consultation')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 14),
          child: FilledButton(
            onPressed: _slot == null || _saving ? null : _confirm,
            child: Text(_slot == null
                ? 'CHOOSE A TIME'
                : (_saving ? 'PLEASE WAIT…' : 'CONFIRM · ${DateFormat('EEE d MMM').format(_date).toUpperCase()}, ${fmtClock(_slot)}')),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(22, 4, 22, 24),
              children: [
                _doctorCard(),
                if (widget.program != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Brand.goldLight, borderRadius: BorderRadius.circular(14)),
                    child: Text('For: ${widget.program}', style: const TextStyle(fontSize: 12.5)),
                  ),
                ],
                if (widget.reschedule == null) ...[
                  const SizedBox(height: 16),
                  SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: [
                      for (final e in ApptStyle.modes.entries)
                        if (_locked == null || _locked == e.key)
                          ButtonSegment(
                              value: e.key,
                              icon: Icon(ApptStyle.modeIcon(e.key), size: 18),
                              label: Text(e.key == 'offline' ? 'In clinic' : (e.key == 'video' ? 'Video' : 'Phone'))),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (s) => setState(() => _mode = s.first),
                  ),
                  if (_locked != null)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('Your doctor has set this consultation mode for you.',
                          style: TextStyle(color: Brand.muted, fontSize: 12)),
                    ),
                ],
                const SizedBox(height: 10),
                Text('${ApptStyle.types[_type]} · $_dur minutes',
                    style: const TextStyle(color: Brand.muted, fontSize: 12.5)),
                const SizedBox(height: 18),
                Text(DateFormat('MMMM yyyy').format(_date).toUpperCase(), style: eyebrow()),
                const SizedBox(height: 10),
                SizedBox(
                  height: 76,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _dates.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 7),
                    itemBuilder: (_, i) {
                      final d = _dates[i];
                      final sel = isoDate(d) == isoDate(_date);
                      final closed = _closedAllDay(d);
                      return GestureDetector(
                        onTap: closed ? null : () => _selectDate(d),
                        child: Opacity(
                          opacity: closed ? 0.38 : 1,
                          child: Container(
                            width: 56,
                            decoration: BoxDecoration(
                              color: sel ? Brand.slate : Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: sel ? Brand.slate : Brand.line),
                            ),
                            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Text(DateFormat('EEE').format(d).toUpperCase(),
                                  style: eyebrow(size: 9, color: sel ? Colors.white70 : Brand.muted)),
                              Text('${d.day}', style: serif(23, weight: FontWeight.w700, color: sel ? Colors.white : Brand.ink)),
                              if (closed) const Text('Closed', style: TextStyle(fontSize: 8.5, color: Brand.muted)),
                            ]),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (!_days.containsKey(isoDate(_date)))
                  const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))
                else if (_closedAllDay(_date))
                  const EmptyState(Icons.event_busy_outlined, 'The clinic is closed on this day.')
                else
                  for (final (title, times) in _sessions) ...[
                    const SizedBox(height: 18),
                    Text(title.toUpperCase(), style: eyebrow()),
                    const SizedBox(height: 10),
                    _slotGrid(times),
                  ],
                if (widget.reschedule == null && _mode == 'offline') ...[
                  const SizedBox(height: 22),
                  Text('PAYMENT', style: eyebrow()),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, children: [
                    ChoiceChip(
                        label: const Text('Pay at clinic'),
                        selected: _payment == 'clinic',
                        onSelected: (_) => setState(() => _payment = 'clinic')),
                    ChoiceChip(
                        label: const Text('Pay online'),
                        selected: _payment == 'online',
                        onSelected: (_) => setState(() => _payment = 'online')),
                  ]),
                ],
                if (widget.reschedule == null && _mode != 'offline')
                  const Padding(
                    padding: EdgeInsets.only(top: 18),
                    child: Text('Video and phone consultations are confirmed after online payment.',
                        style: TextStyle(color: Brand.muted, fontSize: 12.5, height: 1.5)),
                  ),
              ],
            ),
    );
  }

  Widget _slotGrid(List<int> all) {
    // Times already passed today are hidden, not shown as taken.
    final now = DateTime.now();
    final times = isoDate(_date) == isoDate(now)
        ? all.where((t) => t > now.hour * 60 + now.minute + 15).toList()
        : all;
    final free = times.where((t) => _free(_date, t)).length;
    if (free == 0) {
      return const Text('No free times in this session', style: TextStyle(color: Brand.muted, fontSize: 12.5));
    }
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.9,
      children: times.map((t) {
        final ok = _free(_date, t);
        final sel = _slot == _hhmm(t);
        return GestureDetector(
          onTap: ok ? () => setState(() => _slot = _hhmm(t)) : null,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: sel ? Brand.sageDark : (ok ? Colors.white : Colors.transparent),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: sel ? Brand.sageDark : Brand.line),
            ),
            child: Text(_label(t),
                style: TextStyle(
                    color: sel ? Colors.white : (ok ? Brand.ink : const Color(0xFFC4C7C3)),
                    fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                    decoration: ok ? null : TextDecoration.lineThrough)),
          ),
        );
      }).toList(),
    );
  }

  Widget _doctorCard() {
    final d = _doctor ?? {};
    final years = (d['experience_years'] ?? 0) as num;
    return SoftCard(
      padding: const EdgeInsets.all(16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Brand.gold, width: 1.2)),
          child: const CircleAvatar(radius: 34, backgroundImage: AssetImage('assets/images/doctor.png')),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(str(d['name']), style: serif(21, weight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text('${str(d['qualification'])} · ${str(d['title'])}',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Brand.teal)),
            Text(str(d['specialty']), style: const TextStyle(fontSize: 12, color: Brand.muted)),
            const SizedBox(height: 8),
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Text('$years', style: serif(20, color: Brand.gold, weight: FontWeight.w700, height: 1)),
              const SizedBox(width: 4),
              Flexible(
                child: Text('yrs experience\n${str(d['experience_area'])}',
                    style: const TextStyle(fontSize: 10.5, height: 1.3)),
              ),
            ]),
            const SizedBox(height: 6),
            Text('Reg. No. ${str(d['reg_no'])}', style: const TextStyle(fontSize: 10.5, color: Brand.muted)),
          ]),
        ),
      ]),
    );
  }
}
