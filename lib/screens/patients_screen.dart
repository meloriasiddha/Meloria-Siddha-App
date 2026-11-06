import 'dart:async';

import 'package:flutter/material.dart';

import '../services/db.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'intake_screen.dart';
import 'patient_detail_screen.dart';
import 'patient_form_screen.dart';

/// Search patients by name, phone, patient ID or referred-by.
/// With [pickForVisit] = true, tapping a patient starts a new visit.
class PatientsScreen extends StatefulWidget {
  const PatientsScreen({super.key, this.pickForVisit = false});
  final bool pickForVisit;

  @override
  State<PatientsScreen> createState() => _PatientsScreenState();
}

class _PatientsScreenState extends State<PatientsScreen> {
  final _q = TextEditingController();
  List<DbRow> _results = [];
  bool _loading = true;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _search);
  }

  Future<void> _search() async {
    setState(() => _loading = true);
    try {
      final r = await Db.searchPatients(_q.text);
      if (mounted) setState(() => _results = r);
    } catch (e) {
      if (mounted) showMsg(context, 'Search failed: $e', error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _tap(DbRow p) async {
    if (widget.pickForVisit) {
      await Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => IntakeScreen(patientId: p['id'])));
    } else {
      await Navigator.push(
          context, MaterialPageRoute(builder: (_) => PatientDetailScreen(patientId: p['id'])));
      _search();
    }
  }

  Future<void> _register() async {
    final DbRow? created = await Navigator.push(
        context, MaterialPageRoute(builder: (_) => const PatientFormScreen()));
    if (created == null || !mounted) return;
    if (widget.pickForVisit) {
      await Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => IntakeScreen(patientId: created['id'])));
    } else {
      _search();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.pickForVisit ? 'Select patient' : 'Patients')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'reg',
        onPressed: _register,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('New patient'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: TextField(
              controller: _q,
              onChanged: _onChanged,
              decoration: const InputDecoration(
                hintText: 'Search name, phone, MEL1-0001 or referred by',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _results.isEmpty
                    ? EmptyState(
                        Icons.person_search_outlined,
                        _q.text.isEmpty
                            ? 'No patients yet.\nTap "New patient" to register.'
                            : 'No match for "${_q.text}".')
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                        itemCount: _results.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final p = _results[i];
                          return Card(
                            child: ListTile(
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                              leading: PatientAvatar(str(p['name'])),
                              title: Text(str(p['name']),
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text([
                                str(p['patient_code']),
                                if (p['age'] != null) '${p['age']} y',
                                if (str(p['gender']).isNotEmpty) str(p['gender']),
                                str(p['phone']),
                              ].where((s) => s.isNotEmpty).join(' · ')),
                              trailing: Icon(
                                  widget.pickForVisit ? Icons.arrow_forward : Icons.chevron_right,
                                  color: Brand.muted),
                              onTap: () => _tap(p),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
