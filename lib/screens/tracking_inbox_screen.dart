import 'dart:async';

import 'package:flutter/material.dart';

import '../services/db.dart';
import '../services/trackers.dart';
import '../services/tracking_db.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/patient_picker.dart';
import 'tracking_chat_screen.dart';
import 'tracking_plan_screen.dart';

/// Tracking inbox: patients with new readings / messages at the top.
class TrackingInboxScreen extends StatefulWidget {
  const TrackingInboxScreen({super.key, this.onUnreadChanged});
  final ValueChanged<int>? onUnreadChanged;

  @override
  State<TrackingInboxScreen> createState() => _TrackingInboxScreenState();
}

class _TrackingInboxScreenState extends State<TrackingInboxScreen> {
  List<DbRow> _rows = [];
  bool _loading = true;
  String _q = '';
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final r = await TrackDb.inbox();
      if (mounted) {
        setState(() => _rows = r);
        widget.onUnreadChanged?.call(r.fold<int>(0, (s, x) => s + (x['unread'] as int)));
      }
    } catch (e) {
      if (mounted && !silent) showMsg(context, 'Could not load: $e', error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _open(String patientId) async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => TrackingChatScreen(patientId: patientId)));
    _load(silent: true);
  }

  Future<void> _start() async {
    final p = await pickPatient(context);
    if (p == null || !mounted) return;
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => TrackingPlanScreen(patientId: p['id'])));
    if (mounted) await _open(p['id']);
  }

  String _preview(Map? m) {
    if (m == null) return 'Plan set up · no entries yet';
    final who = m['sender_type'] == 'staff' ? 'You: ' : '';
    switch (m['kind']) {
      case 'entry':
        final def = Trackers.def(str(m['entry_type']));
        return '$who${def.label}: ${Trackers.summary(str(m['entry_type']), (m['data'] ?? {}) as Map)} ${def.unit}'
            .trim();
      case 'request':
        return '${who}Requested ${Trackers.def(str(m['entry_type'])).label.toLowerCase()}';
      default:
        return '$who${str(m['body'])}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows.where((r) {
      if (_q.isEmpty) return true;
      final p = (r['patient'] ?? {}) as Map;
      return '${p['name']} ${p['patient_code']}'.toLowerCase().contains(_q.toLowerCase());
    }).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Tracking')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'track',
        onPressed: _start,
        icon: const Icon(Icons.add),
        label: const Text('Start tracking'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: TextField(
              onChanged: (v) => setState(() => _q = v),
              decoration:
                  const InputDecoration(hintText: 'Search patient', prefixIcon: Icon(Icons.search)),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : rows.isEmpty
                    ? const EmptyState(Icons.forum_outlined,
                        'No patients are being tracked yet.\nTap "Start tracking" to set up a plan.')
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                          itemCount: rows.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            final r = rows[i];
                            final p = (r['patient'] ?? {}) as Map;
                            final last = r['last'] as Map?;
                            final unread = r['unread'] as int;
                            return Card(
                              child: ListTile(
                                contentPadding:
                                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                leading: PatientAvatar(str(p['name'])),
                                title: Text(str(p['name']),
                                    style: TextStyle(
                                        fontWeight: unread > 0 ? FontWeight.w700 : FontWeight.w600)),
                                subtitle: Text(_preview(last),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: unread > 0 ? Brand.slate : Brand.muted)),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    if (last != null)
                                      Text(_when(last['created_at']),
                                          style: const TextStyle(fontSize: 11, color: Brand.muted)),
                                    const SizedBox(height: 4),
                                    if (unread > 0)
                                      Container(
                                        padding:
                                            const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                        decoration: BoxDecoration(
                                            color: Brand.sageDark,
                                            borderRadius: BorderRadius.circular(12)),
                                        child: Text('$unread',
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700)),
                                      ),
                                  ],
                                ),
                                onTap: () => _open(p['id']),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  String _when(dynamic iso) {
    final d = DateTime.tryParse(str(iso))?.toLocal();
    if (d == null) return '';
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) return fmtTime(iso);
    return fmtDate(d).replaceAll(RegExp(r' \d{4}$'), '');
  }
}
