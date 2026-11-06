import 'dart:async';

import 'package:flutter/material.dart';

import '../services/db.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'consultation_screen.dart';
import 'home_screen.dart';
import 'intake_screen.dart';
import 'patients_screen.dart';

/// Today's visits: waiting list for the doctor, done list below.
class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  List<DbRow> _visits = [];
  bool _loading = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    // Refresh every 20 seconds so the doctor sees new patients from staff.
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
      final v = await Db.todaysVisits();
      if (mounted) setState(() => _visits = v);
    } catch (e) {
      if (mounted && !silent) showMsg(context, 'Could not load: $e', error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _open(DbRow visit) async {
    final page = Session.isDoctor
        ? ConsultationScreen(visitId: visit['id'])
        : IntakeScreen(patientId: visit['patient_id'], visitId: visit['id']);
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    _load(silent: true);
  }

  Future<void> _newVisit() async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => const PatientsScreen(pickForVisit: true)));
    _load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    final waiting = _visits.where((v) => v['status'] != 'done').toList();
    final done = _visits.where((v) => v['status'] == 'done').toList();
    final hour = DateTime.now().hour;
    final greet = hour < 12 ? 'Good morning' : (hour < 17 ? 'Good afternoon' : 'Good evening');

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 76,
        title: Row(
          children: [
            Image.asset('assets/images/logo_symbol.png', height: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(greet, style: const TextStyle(fontSize: 13, color: Brand.muted)),
                  Text(Session.name, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newVisit,
        icon: const Icon(Icons.add),
        label: const Text('New visit'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
          children: [
            Row(
              children: [
                _stat('Waiting', waiting.length, Brand.warning),
                const SizedBox(width: 12),
                _stat('Seen today', done.length, Brand.sageDark),
              ],
            ),
            const SizedBox(height: 20),
            if (_loading)
              const Padding(
                  padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
            else if (_visits.isEmpty)
              const EmptyState(Icons.event_available_outlined,
                  'No visits yet today.\nTap "New visit" when a patient arrives.')
            else ...[
              if (waiting.isNotEmpty) _header('Waiting'),
              ...waiting.map(_tile),
              if (done.isNotEmpty) _header('Completed'),
              ...done.map(_tile),
            ],
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, int n, Color c) => Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$n', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600, color: c)),
                Text(label, style: const TextStyle(color: Brand.muted)),
              ],
            ),
          ),
        ),
      );

  Widget _header(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
        child: Text(t.toUpperCase(),
            style: const TextStyle(
                fontSize: 12, letterSpacing: 1.2, color: Brand.muted, fontWeight: FontWeight.w600)),
      );

  Widget _tile(DbRow v) {
    final p = (v['patients'] ?? {}) as Map;
    final status = str(v['status']);
    final color = switch (status) {
      'waiting' => Brand.warning,
      'with_doctor' => Brand.teal,
      _ => Brand.sageDark,
    };
    final label = switch (status) {
      'waiting' => 'Waiting',
      'with_doctor' => 'With doctor',
      _ => 'Done',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: PatientAvatar(str(p['name'])),
          title: Text(str(p['name']), style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
            [
              str(p['patient_code']),
              if (p['age'] != null) '${p['age']} y',
              if (str(v['main_complaint']).isNotEmpty) str(v['main_complaint']),
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Tag(label, color: color),
              const SizedBox(height: 4),
              Text(fmtTime(v['created_at']),
                  style: const TextStyle(fontSize: 11, color: Brand.muted)),
            ],
          ),
          onTap: () => _open(v),
        ),
      ),
    );
  }
}
