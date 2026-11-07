import 'dart:math';

import 'package:flutter/material.dart';

import '../services/billing_db.dart';
import '../services/db.dart';
import '../services/patient_app_db.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/patient_picker.dart';
import 'bill_screen.dart';

/// Patient app requests: new sign-ups to link/confirm, program join requests, forgotten PINs.
class AppRequestsScreen extends StatefulWidget {
  const AppRequestsScreen({super.key});

  @override
  State<AppRequestsScreen> createState() => _AppRequestsScreenState();
}

class _AppRequestsScreenState extends State<AppRequestsScreen> {
  List<DbRow> _signups = [];
  List<DbRow> _programs = [];
  List<DbRow> _pins = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _signups = await PatientAppDb.signups();
      _programs = await PatientAppDb.programRequests();
      _pins = await PatientAppDb.pinRequests();
    } catch (e) {
      if (mounted) showMsg(context, 'Could not load: $e', error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  // ------------------------------------------------------------ sign-ups
  Future<void> _link(DbRow s, String patientId, String label) async {
    final ok = await _confirm('Link this account?',
        '${s['full_name']} (${s['phone']}) will see the records of $label. Any bookings or messages they made will move to that record.');
    if (!ok || !mounted) return;
    if (await guard(context, () => PatientAppDb.link(s['user_id'], patientId))) {
      if (mounted) showMsg(context, 'Linked to $label');
    }
    _load();
  }

  Future<void> _linkOther(DbRow s) async {
    final p = await pickPatient(context);
    if (p == null) return;
    await _link(s, p['id'], '${p['name']} (${p['patient_code']})');
  }

  Future<void> _confirmNew(DbRow s) async {
    final ok = await _confirm('Confirm as new patient?',
        '${s['full_name']} gets a new patient ID and can see their records as they are added.');
    if (!ok || !mounted) return;
    String? code;
    if (await guard(context, () async => code = await PatientAppDb.confirmNew(s['user_id']))) {
      if (mounted) showMsg(context, 'Confirmed as ${code ?? 'new patient'}');
    }
    _load();
  }

  Future<void> _reject(DbRow s) async {
    final ok = await _confirm('Reject this sign-up?', 'They can still use the app but will not see any clinic records.');
    if (!ok || !mounted) return;
    await guard(context, () => PatientAppDb.reject(s['user_id']));
    _load();
  }

  Future<bool> _confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Yes')),
          ],
        ),
      ) ==
      true;

  // ------------------------------------------------------------ program requests
  Future<void> _enroll(DbRow r) async {
    final months = (r['months'] ?? 1) as int;
    final start = DateTime.now();
    final end = DateTime(start.year, start.month + months, start.day);
    DbRow? enrolled;
    final ok = await guard(context, () async {
      enrolled = await BillDb.enroll({
        'patient_id': r['patient_id'],
        'program_id': r['program_id'],
        'name': '${r['program_name']} – $months month${months == 1 ? '' : 's'}',
        'price': r['price'] ?? 0,
        'start_date': isoDate(start),
        'end_date': isoDate(end),
      });
      await PatientAppDb.setRequestStatus(r['id'], 'enrolled');
    });
    if (ok && enrolled != null && mounted) {
      showMsg(context, 'Enrolled until ${fmtDate(end)}. Prepare the program bill.');
      await Navigator.push(context, MaterialPageRoute(builder: (_) => BillScreen(patientProgram: enrolled)));
    }
    _load();
  }

  // ------------------------------------------------------------ PIN reset
  Future<void> _setPin(DbRow r) async {
    final pin = (100000 + Random().nextInt(900000)).toString();
    final ok = await _confirm('Set temporary PIN',
        'A temporary PIN $pin will be set for ${r['phone']}. Tell the patient this PIN; they can change it in the app (Profile → Change PIN).');
    if (!ok || !mounted) return;
    if (await guard(context, () => PatientAppDb.resetPin(r['phone'], pin))) {
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Temporary PIN set'),
          content: Text('Phone ${r['phone']}\nPIN: $pin', style: const TextStyle(fontSize: 18)),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Done'))],
        ),
      );
    }
    _load();
  }

  // ------------------------------------------------------------ UI
  @override
  Widget build(BuildContext context) {
    final pending = _signups.where((s) => s['status'] == 'pending').toList();
    final others = _signups.where((s) => s['status'] != 'pending').toList();
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Patient app'),
          bottom: TabBar(tabs: [
            Tab(text: 'Sign-ups (${pending.length})'),
            Tab(text: 'Programs (${_programs.length})'),
            Tab(text: 'PIN (${_pins.length})'),
          ]),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(children: [
                RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.all(16), children: [
                    if (pending.isEmpty)
                      const EmptyState(Icons.how_to_reg_outlined, 'No new sign-ups waiting.'),
                    ...pending.map(_signupCard),
                    if (others.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Text('CONFIRMED / OTHER',
                          style: TextStyle(fontSize: 12, letterSpacing: 1.2, color: Brand.muted, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      ...others.map(_signupCard),
                    ],
                  ]),
                ),
                RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.all(16), children: [
                    if (_programs.isEmpty) const EmptyState(Icons.workspace_premium_outlined, 'No program requests.'),
                    ..._programs.map((r) {
                      final p = (r['patients'] ?? {}) as Map;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: SectionCard(
                          title: str(p['name']),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${p['patient_code'] ?? 'Not yet confirmed'} · ${str(p['phone'])}'),
                            const SizedBox(height: 6),
                            Text('${r['program_name']} · ${r['months']} months · ₹${r['price'] ?? '-'}',
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text('Requested ${fmtDate(r['created_at'])}', style: const TextStyle(color: Brand.muted, fontSize: 12)),
                            const SizedBox(height: 10),
                            Row(children: [
                              Expanded(
                                  child: FilledButton(
                                      style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                                      onPressed: p['patient_code'] == null ? null : () => _enroll(r),
                                      child: const Text('Enrol & bill'))),
                              const SizedBox(width: 8),
                              OutlinedButton(
                                  onPressed: () async {
                                    await guard(context, () => PatientAppDb.setRequestStatus(r['id'], 'declined'));
                                    _load();
                                  },
                                  child: const Text('Decline')),
                            ]),
                            if (p['patient_code'] == null)
                              const Padding(
                                padding: EdgeInsets.only(top: 6),
                                child: Text('Confirm the sign-up first.', style: TextStyle(color: Brand.warning, fontSize: 12)),
                              ),
                          ]),
                        ),
                      );
                    }),
                  ]),
                ),
                RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.all(16), children: [
                    if (_pins.isEmpty) const EmptyState(Icons.lock_reset, 'No PIN reset requests.'),
                    ..._pins.map((r) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Card(
                            child: ListTile(
                              leading: const Icon(Icons.lock_reset, color: Brand.teal),
                              title: Text(str(r['phone'])),
                              subtitle: Text('Requested ${fmtDate(r['created_at'])} ${fmtTime(r['created_at'])}'),
                              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                FilledButton(
                                    style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                                    onPressed: () => _setPin(r),
                                    child: const Text('Set PIN')),
                                IconButton(
                                    onPressed: () async {
                                      await guard(context, () => PatientAppDb.dismissPinRequest(r['id']));
                                      _load();
                                    },
                                    icon: const Icon(Icons.close)),
                              ]),
                            ),
                          ),
                        )),
                  ]),
                ),
              ]),
      ),
    );
  }

  Widget _signupCard(DbRow s) {
    final matches = ((s['matches'] as List?) ?? []).cast<Map>();
    final linked = ((s['linked'] as List?) ?? []).cast<Map>();
    final pending = s['status'] == 'pending';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SectionCard(
        title: str(s['full_name']),
        trailing: Tag(str(s['status']), color: pending ? Brand.warning : (s['status'] == 'linked' ? Brand.sageDark : Brand.muted)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${s['phone']} · DOB ${fmtDate(s['dob'])} · signed up ${fmtDate(s['created_at'])}'),
          if (!pending && linked.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Linked to: ${linked.map((l) => '${l['name']} (${l['patient_code'] ?? '-'})').join(', ')}',
                  style: const TextStyle(color: Brand.muted, fontSize: 12.5)),
            ),
          const SizedBox(height: 10),
          if (pending && matches.isNotEmpty) ...[
            const Text('Same phone number in clinic records:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 6),
            ...matches.map((m) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.link),
                    onPressed: () => _link(s, m['id'], '${m['name']} (${m['patient_code']})'),
                    label: Text('Link to ${m['name']} · ${m['patient_code']}${m['age'] == null ? '' : ' · ${m['age']} y'}'),
                  ),
                )),
          ],
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
                onPressed: () => _linkOther(s),
                icon: const Icon(Icons.person_search_outlined),
                label: Text(pending ? 'Link to another patient' : 'Link a family member')),
            if (pending)
              FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 46)),
                  onPressed: () => _confirmNew(s),
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Confirm as new')),
            if (pending)
              TextButton(onPressed: () => _reject(s), child: const Text('Reject', style: TextStyle(color: Brand.danger))),
          ]),
        ]),
      ),
    );
  }
}
