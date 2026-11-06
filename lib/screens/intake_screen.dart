import 'package:flutter/material.dart';

import '../services/db.dart';
import '../theme.dart';
import '../widgets/allergies_meds.dart';
import '../widgets/common.dart';

/// Staff intake: visit type, vitals, main complaint, allergies & current meds.
/// Saving a new visit puts the patient in the doctor's waiting list.
class IntakeScreen extends StatefulWidget {
  const IntakeScreen({super.key, required this.patientId, this.visitId});
  final String patientId;
  final String? visitId; // null = new visit

  @override
  State<IntakeScreen> createState() => _IntakeScreenState();
}

class _IntakeScreenState extends State<IntakeScreen> {
  DbRow? _patient;
  String _type = 'review';
  String _mode = 'offline';
  final _bpS = TextEditingController();
  final _bpD = TextEditingController();
  final _pulse = TextEditingController();
  final _temp = TextEditingController();
  final _spo2 = TextEditingController();
  final _weight = TextEditingController();
  final _height = TextEditingController();
  final _sugar = TextEditingController();
  final _complaint = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
    _weight.addListener(() => setState(() {}));
    _height.addListener(() => setState(() {}));
  }

  Future<void> _load() async {
    try {
      _patient = await Db.getPatient(widget.patientId);
      if (widget.visitId != null) {
        final v = await Db.getVisit(widget.visitId!);
        _type = str(v['visit_type']);
        _mode = str(v['mode']);
        _bpS.text = str(v['bp_systolic']);
        _bpD.text = str(v['bp_diastolic']);
        _pulse.text = str(v['pulse']);
        _temp.text = str(v['temperature']);
        _spo2.text = str(v['spo2']);
        _weight.text = str(v['weight']);
        _height.text = str(v['height']);
        _sugar.text = str(v['random_sugar']);
        _complaint.text = str(v['main_complaint']);
      } else {
        final n = await Db.visitCount(widget.patientId);
        _type = n == 0 ? 'first' : 'review';
      }
    } catch (e) {
      if (mounted) showMsg(context, 'Could not load: $e', error: true);
    }
    if (mounted) setState(() {});
  }

  String get _bmi {
    final w = toNum(_weight.text);
    final h = toNum(_height.text);
    if (w == null || h == null || h == 0) return '';
    final m = h / 100;
    return (w / (m * m)).toStringAsFixed(1);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final data = <String, dynamic>{
      'patient_id': widget.patientId,
      'visit_type': _type,
      'mode': _mode,
      'bp_systolic': toInt(_bpS.text),
      'bp_diastolic': toInt(_bpD.text),
      'pulse': toInt(_pulse.text),
      'temperature': toNum(_temp.text),
      'spo2': toInt(_spo2.text),
      'weight': toNum(_weight.text),
      'height': toNum(_height.text),
      'random_sugar': toNum(_sugar.text),
      'main_complaint': _complaint.text.trim(),
    };
    final ok = await guard(context, () => Db.saveVisit(data, id: widget.visitId));
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      showMsg(context, widget.visitId == null ? 'Added to waiting list' : 'Saved');
      Navigator.pop(context, true);
    }
  }

  Widget _num(String label, TextEditingController c, {String? suffix}) => Expanded(
        child: Field(label, c,
            keyboard: const TextInputType.numberWithOptions(decimal: true), suffix: suffix),
      );

  @override
  Widget build(BuildContext context) {
    final p = _patient;
    return Scaffold(
      appBar: AppBar(title: Text(widget.visitId == null ? 'New visit' : 'Visit intake')),
      body: p == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: PatientAvatar(str(p['name'])),
                  title: Text(str(p['name']),
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17)),
                  subtitle: Text([
                    str(p['patient_code']),
                    if (p['age'] != null) '${p['age']} y',
                    str(p['gender'])
                  ].where((s) => s.isNotEmpty).join(' · ')),
                ),
                const SizedBox(height: 8),
                SectionCard(
                  title: 'Visit',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: {
                          'first': 'First consult',
                          'review': 'Review',
                          'therapy': 'Therapy',
                          'program': 'Program'
                        }
                            .entries
                            .map((e) => ChoiceChip(
                                  label: Text(e.value),
                                  selected: _type == e.key,
                                  onSelected: (_) => setState(() => _type = e.key),
                                ))
                            .toList(),
                      ),
                      const SizedBox(height: 10),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                              value: 'offline',
                              label: Text('In clinic'),
                              icon: Icon(Icons.local_hospital_outlined)),
                          ButtonSegment(
                              value: 'online',
                              label: Text('Online'),
                              icon: Icon(Icons.videocam_outlined)),
                        ],
                        selected: {_mode},
                        onSelectionChanged: (s) => setState(() => _mode = s.first),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SectionCard(
                  title: 'Vitals',
                  child: Column(
                    children: [
                      Row(children: [
                        _num('BP systolic', _bpS),
                        const SizedBox(width: 12),
                        _num('BP diastolic', _bpD, suffix: 'mmHg'),
                      ]),
                      Row(children: [
                        _num('Pulse', _pulse, suffix: '/min'),
                        const SizedBox(width: 12),
                        _num('SpO2', _spo2, suffix: '%'),
                      ]),
                      Row(children: [
                        _num('Temperature', _temp, suffix: '°F'),
                        const SizedBox(width: 12),
                        _num('Random sugar', _sugar, suffix: 'mg/dL'),
                      ]),
                      Row(children: [
                        _num('Weight', _weight, suffix: 'kg'),
                        const SizedBox(width: 12),
                        _num('Height', _height, suffix: 'cm'),
                      ]),
                      if (_bmi.isNotEmpty)
                        Align(alignment: Alignment.centerLeft, child: Tag('BMI $_bmi')),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SectionCard(
                  title: 'Main complaint',
                  child: Field('What brings the patient today?', _complaint, maxLines: 3),
                ),
                const SizedBox(height: 14),
                AllergiesMedsSection(patientId: widget.patientId),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.send_outlined),
                  label: Text(widget.visitId == null ? 'SEND TO DOCTOR' : 'SAVE'),
                ),
                const SizedBox(height: 8),
                const Text('Allergies and medicines save instantly when added.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Brand.muted, fontSize: 12)),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}
