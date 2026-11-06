import 'package:flutter/material.dart';

import '../services/db.dart';
import '../theme.dart';
import '../widgets/allergies_meds.dart';
import '../widgets/common.dart';
import 'consultation_screen.dart';
import 'home_screen.dart';
import 'intake_screen.dart';
import 'patient_form_screen.dart';

class PatientDetailScreen extends StatefulWidget {
  const PatientDetailScreen({super.key, required this.patientId});
  final String patientId;

  @override
  State<PatientDetailScreen> createState() => _PatientDetailScreenState();
}

class _PatientDetailScreenState extends State<PatientDetailScreen> {
  DbRow? _p;
  List<DbRow> _visits = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await Db.getPatient(widget.patientId);
      final v = await Db.patientVisits(widget.patientId);
      if (mounted) setState(() {
        _p = p;
        _visits = v;
      });
    } catch (e) {
      if (mounted) showMsg(context, 'Could not load: $e', error: true);
    }
  }

  Future<void> _edit() async {
    final r = await Navigator.push(
        context, MaterialPageRoute(builder: (_) => PatientFormScreen(patient: _p)));
    if (r != null) _load();
  }

  Future<void> _startVisit() async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => IntakeScreen(patientId: widget.patientId)));
    _load();
  }

  Future<void> _openVisit(DbRow v) async {
    final page = Session.isDoctor
        ? ConsultationScreen(visitId: v['id'])
        : IntakeScreen(patientId: widget.patientId, visitId: v['id']);
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Patient'),
        actions: [
          if (p != null) IconButton(onPressed: _edit, icon: const Icon(Icons.edit_outlined)),
        ],
      ),
      floatingActionButton: p == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _startVisit,
              icon: const Icon(Icons.add),
              label: const Text('Start visit'),
            ),
      body: p == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Row(
                        children: [
                          PatientAvatar(str(p['name']), radius: 30),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(str(p['name']),
                                    style: const TextStyle(
                                        fontSize: 19, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 4),
                                Tag(str(p['patient_code']), color: Brand.teal),
                                const SizedBox(height: 8),
                                Text(
                                  [
                                    if (p['age'] != null) '${p['age']} years',
                                    str(p['gender']),
                                    str(p['phone']),
                                  ].where((s) => s.isNotEmpty).join(' · '),
                                  style: const TextStyle(color: Brand.muted),
                                ),
                                if (str(p['address']).isNotEmpty)
                                  Text(str(p['address']),
                                      style: const TextStyle(color: Brand.muted, fontSize: 13)),
                                if (str(p['referred_by_name']).isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(
                                        'Referred by ${p['referred_by_type'] ?? ''}: ${p['referred_by_name']}',
                                        style: const TextStyle(fontSize: 13)),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  AllergiesMedsSection(patientId: widget.patientId),
                  const SizedBox(height: 14),
                  SectionCard(
                    title: 'Visits (${_visits.length})',
                    child: _visits.isEmpty
                        ? const Text('No visits yet', style: TextStyle(color: Brand.muted))
                        : Column(
                            children: _visits.map((v) {
                              final c = v['consultations'];
                              final cons = c is List && c.isNotEmpty
                                  ? c.first as Map
                                  : (c is Map ? c : null);
                              final complaints = (cons?['complaints'] as List?) ?? [];
                              final summary = complaints.isNotEmpty
                                  ? complaints.map((e) => e['complaint']).join(', ')
                                  : str(v['main_complaint']);
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.event_note_outlined, color: Brand.sageDark),
                                title: Text(fmtDate(v['visit_date'])),
                                subtitle: Text(summary.isEmpty ? '—' : summary,
                                    maxLines: 1, overflow: TextOverflow.ellipsis),
                                trailing: Tag(str(v['visit_type'])),
                                onTap: () => _openVisit(v),
                              );
                            }).toList(),
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}
