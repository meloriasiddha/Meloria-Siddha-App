import 'package:flutter/material.dart';

import '../services/db.dart';
import 'common.dart';

/// Bottom sheet to search and pick a patient. Returns the patient row.
Future<DbRow?> pickPatient(BuildContext context) => showModalBottomSheet<DbRow>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const PatientPickerSheet(),
    );

class PatientPickerSheet extends StatefulWidget {
  const PatientPickerSheet({super.key});

  @override
  State<PatientPickerSheet> createState() => _PatientPickerSheetState();
}

class _PatientPickerSheetState extends State<PatientPickerSheet> {
  List<DbRow> _r = [];

  Future<void> _search(String q) async {
    try {
      final r = await Db.searchPatients(q);
      if (mounted) setState(() => _r = r);
    } catch (_) {}
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
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                autofocus: true,
                onChanged: _search,
                decoration: const InputDecoration(
                    hintText: 'Search name, phone or MEL1-…', prefixIcon: Icon(Icons.search)),
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
