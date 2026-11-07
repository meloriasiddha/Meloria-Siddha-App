import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/api.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'book_screen.dart';

/// Upcoming and past appointments, with cancel / reschedule.
class BookingsScreen extends StatefulWidget {
  const BookingsScreen({super.key});

  @override
  State<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends State<BookingsScreen> {
  List<DbRow> _appts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    AppState.selected.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    AppState.selected.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final pid = AppState.patientId;
    if (pid == null) return;
    try {
      final r = await Api.appointments(pid);
      if (mounted) setState(() => _appts = r);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  DateTime _at(DbRow a) => DateTime.parse('${a['appt_date']} ${a['start_time']}');

  bool _changeable(DbRow a) =>
      ['booked', 'pending_payment'].contains(a['status']) &&
      _at(a).subtract(const Duration(minutes: 30)).isAfter(DateTime.now());

  Future<void> _cancel(DbRow a) async {
    String? refund;
    final paid = a['paid'] == true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text('Cancel appointment?', style: serif(26)),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${DateFormat('EEEE, d MMM').format(_at(a))} · ${fmtClock(a['start_time'])}'),
            if (paid) ...[
              const SizedBox(height: 14),
              const Text('You have paid for this consultation. What would you like?',
                  style: TextStyle(color: Brand.muted)),
              RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: 'credit',
                  groupValue: refund,
                  title: const Text('Keep as credit for my next booking'),
                  onChanged: (v) => set(() => refund = v)),
              RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: 'refund',
                  groupValue: refund,
                  title: const Text('Refund my payment'),
                  onChanged: (v) => set(() => refund = v)),
            ],
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep it')),
            TextButton(
                onPressed: paid && refund == null ? null : () => Navigator.pop(ctx, true),
                child: const Text('Cancel appointment', style: TextStyle(color: Brand.danger))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await Api.cancel(a['id'], refund: refund);
      if (mounted) showMsg(context, 'Appointment cancelled');
    } catch (e) {
      if (mounted) showMsg(context, niceError(e), error: true);
    }
    _load();
  }

  Future<void> _reschedule(DbRow a) async {
    final ok = await Navigator.push(context, MaterialPageRoute(builder: (_) => BookScreen(reschedule: a)));
    if (ok == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final upcoming = _appts
        .where((a) => _at(a).isAfter(now.subtract(const Duration(hours: 1))) &&
            ['booked', 'pending_payment', 'arrived'].contains(a['status']))
        .toList()
      ..sort((a, b) => _at(a).compareTo(_at(b)));
    final past = _appts.where((a) => !upcoming.contains(a)).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Bookings')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Brand.slate,
        foregroundColor: Colors.white,
        onPressed: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const BookScreen()));
          _load();
        },
        icon: const Icon(Icons.add),
        label: const Text('Book'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 4, 22, 100),
                children: [
                  Text('UPCOMING', style: eyebrow()),
                  const SizedBox(height: 10),
                  if (upcoming.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('No upcoming appointments', style: TextStyle(color: Brand.muted)),
                    ),
                  ...upcoming.map((a) => Padding(padding: const EdgeInsets.only(bottom: 12), child: _card(a, true))),
                  if (past.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Text('PAST', style: eyebrow()),
                    const SizedBox(height: 10),
                    ...past.take(30).map((a) => Padding(padding: const EdgeInsets.only(bottom: 10), child: _card(a, false))),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _card(DbRow a, bool upcoming) {
    final d = _at(a);
    final status = str(a['status']);
    final color = switch (status) {
      'pending_payment' => Brand.gold,
      'cancelled' || 'no_show' => Brand.muted,
      'done' => Brand.sageDark,
      _ => Brand.teal,
    };
    return SoftCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Column(children: [
            Text(DateFormat('MMM').format(d).toUpperCase(), style: eyebrow(size: 9)),
            Text('${d.day}', style: serif(30, weight: FontWeight.w700)),
          ]),
          Container(width: 1, height: 44, color: Brand.line, margin: const EdgeInsets.symmetric(horizontal: 14)),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${DateFormat('EEEE').format(d)} · ${fmtClock(a['start_time'])}',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              const SizedBox(height: 2),
              Row(children: [
                Icon(ApptStyle.modeIcon(str(a['mode'])), size: 15, color: Brand.muted),
                const SizedBox(width: 4),
                Flexible(
                  child: Text('${ApptStyle.types[a['appt_type']] ?? ''} · ${ApptStyle.modes[a['mode']] ?? ''}',
                      style: const TextStyle(color: Brand.muted, fontSize: 12.5)),
                ),
              ]),
            ]),
          ),
          Pill(ApptStyle.statuses[status] ?? status, color: color),
        ]),
        if (str(a['program_interest']).isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('For: ${a['program_interest']}', style: const TextStyle(fontSize: 12, color: Brand.gold)),
          ),
        if (status == 'pending_payment' && upcoming)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text('Confirmed once payment is received by the clinic.',
                style: TextStyle(fontSize: 12, color: Brand.muted)),
          ),
        if (str(a['meet_link']).isNotEmpty && upcoming)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: SelectableText('Video link: ${a['meet_link']}', style: const TextStyle(fontSize: 12.5)),
          ),
        if (str(a['refund_choice']).isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(a['refund_choice'] == 'refund' ? 'Refund requested' : 'Kept as credit',
                style: const TextStyle(fontSize: 12, color: Brand.muted)),
          ),
        if (upcoming && _changeable(a)) ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: OutlinedButton(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)),
                    onPressed: () => _reschedule(a),
                    child: const Text('Reschedule'))),
            const SizedBox(width: 10),
            Expanded(
                child: OutlinedButton(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)),
                    onPressed: () => _cancel(a),
                    child: const Text('Cancel', style: TextStyle(color: Brand.danger)))),
          ]),
        ],
      ]),
    );
  }
}
