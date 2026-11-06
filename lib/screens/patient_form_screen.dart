import 'package:flutter/material.dart';

import '../services/db.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Register a new patient, or edit an existing one ([patient] != null).
/// Pops with the saved patient row.
class PatientFormScreen extends StatefulWidget {
  const PatientFormScreen({super.key, this.patient});
  final DbRow? patient;

  @override
  State<PatientFormScreen> createState() => _PatientFormScreenState();
}

class _PatientFormScreenState extends State<PatientFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: str(widget.patient?['name']));
  late final _age = TextEditingController(text: str(widget.patient?['age']));
  late final _phone = TextEditingController(text: str(widget.patient?['phone']));
  late final _address = TextEditingController(text: str(widget.patient?['address']));
  late final _refName = TextEditingController(text: str(widget.patient?['referred_by_name']));
  final _oldNumber = TextEditingController(); // for entering old patients (1–218)
  late String _gender = str(widget.patient?['gender']);
  late String _refType = str(widget.patient?['referred_by_type']);
  String? _refPatientId;
  String _refPatientLabel = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _refPatientId = widget.patient?['referred_by_patient'];
    if (_refPatientId != null) {
      Db.getPatient(_refPatientId!).then((p) {
        if (mounted) setState(() => _refPatientLabel = '${p['name']} (${p['patient_code']})');
      });
    }
  }

  Future<void> _pickReferrer() async {
    final picked = await showModalBottomSheet<DbRow>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _PatientPicker(),
    );
    if (picked != null) {
      setState(() {
        _refPatientId = picked['id'];
        _refPatientLabel = '${picked['name']} (${picked['patient_code']})';
      });
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final data = <String, dynamic>{
      'name': _name.text.trim(),
      'age': toInt(_age.text),
      'gender': _gender.isEmpty ? null : _gender,
      'phone': _phone.text.trim(),
      'address': _address.text.trim(),
      'referred_by_type': _refType.isEmpty ? null : _refType,
      'referred_by_patient': _refType == 'patient' ? _refPatientId : null,
      'referred_by_name': _refType == 'patient'
          ? (_refPatientLabel.isEmpty ? null : _refPatientLabel)
          : (_refName.text.trim().isEmpty ? null : _refName.text.trim()),
    };
    final old = toInt(_oldNumber.text);
    if (widget.patient == null && old != null) {
      // Old patient: keep their original number, e.g. 45 → MEL1-0045
      data['patient_code'] = 'MEL1-${old.toString().padLeft(4, '0')}';
    }
    try {
      final saved = await Db.savePatient(data, id: widget.patient?['id']);
      if (!mounted) return;
      if (widget.patient == null) {
        showMsg(context, 'Registered as ${saved['patient_code']}');
      }
      Navigator.pop(context, saved);
    } catch (e) {
      final dup = e.toString().contains('patient_code');
      if (mounted) {
        showMsg(context,
            dup ? 'That patient number is already used.' : 'Could not save: $e',
            error: true);
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.patient != null;
    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Edit patient' : 'New patient')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (editing)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Tag('Patient ID  ${widget.patient!['patient_code']}', color: Brand.teal),
              )
            else
              SectionCard(
                title: 'Patient ID',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('New patients get the next number automatically.',
                        style: TextStyle(color: Brand.muted, fontSize: 13)),
                    const SizedBox(height: 10),
                    Field('Old patient? Enter their existing number', _oldNumber,
                        keyboard: TextInputType.number,
                        hint: 'e.g. 45 → MEL1-0045 (leave empty for new)'),
                  ],
                ),
              ),
            if (!editing) const SizedBox(height: 14),
            SectionCard(
              title: 'Basic details',
              child: Column(
                children: [
                  Field('Full name', _name, required: true),
                  Row(
                    children: [
                      Expanded(child: Field('Age', _age, keyboard: TextInputType.number)),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: Field('Phone number', _phone,
                            keyboard: TextInputType.phone, required: true),
                      ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      children: ['Male', 'Female', 'Other']
                          .map((g) => ChoiceChip(
                                label: Text(g),
                                selected: _gender == g,
                                onSelected: (s) => setState(() => _gender = s ? g : ''),
                              ))
                          .toList(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Field('Address', _address, maxLines: 3),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SectionCard(
              title: 'Referred by',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    children: {'patient': 'Patient', 'doctor': 'Doctor', 'other': 'Other'}
                        .entries
                        .map((e) => ChoiceChip(
                              label: Text(e.value),
                              selected: _refType == e.key,
                              onSelected: (s) => setState(() => _refType = s ? e.key : ''),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                  if (_refType == 'patient')
                    OutlinedButton.icon(
                      onPressed: _pickReferrer,
                      icon: const Icon(Icons.person_search_outlined),
                      label: Text(_refPatientLabel.isEmpty
                          ? 'Choose referring patient'
                          : _refPatientLabel),
                    ),
                  if (_refType == 'doctor')
                    Field('Doctor name', _refName),
                  if (_refType == 'other')
                    Field('Source', _refName, hint: 'Instagram, walk-in, camp…'),
                ],
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : (editing ? 'SAVE CHANGES' : 'REGISTER PATIENT')),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet to search and pick an existing patient.
class _PatientPicker extends StatefulWidget {
  const _PatientPicker();

  @override
  State<_PatientPicker> createState() => _PatientPickerState();
}

class _PatientPickerState extends State<_PatientPicker> {
  List<DbRow> _r = [];

  Future<void> _search(String q) async {
    final r = await Db.searchPatients(q);
    if (mounted) setState(() => _r = r);
  }

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                autofocus: true,
                onChanged: _search,
                decoration: const InputDecoration(
                    hintText: 'Search patient', prefixIcon: Icon(Icons.search)),
              ),
            ),
            Expanded(
              child: ListView(
                children: _r
                    .map((p) => ListTile(
                          leading: PatientAvatar(str(p['name']), radius: 18),
                          title: Text(str(p['name'])),
                          subtitle: Text('${p['patient_code']} · ${str(p['phone'])}'),
                          onTap: () => Navigator.pop(context, p),
                        ))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
