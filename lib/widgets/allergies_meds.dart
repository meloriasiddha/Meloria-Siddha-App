import 'package:flutter/material.dart';

import '../services/db.dart';
import '../theme.dart';
import 'common.dart';

/// Allergies + current medications (Siddha / Allopathy) for a patient.
/// Used on patient details, intake and consultation screens.
/// Staff and doctor can both add, edit and remove.
class AllergiesMedsSection extends StatefulWidget {
  const AllergiesMedsSection({super.key, required this.patientId});
  final String patientId;

  @override
  State<AllergiesMedsSection> createState() => _AllergiesMedsSectionState();
}

class _AllergiesMedsSectionState extends State<AllergiesMedsSection> {
  List<DbRow> _allergies = [];
  List<DbRow> _meds = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final a = await Db.allergies(widget.patientId);
      final m = await Db.currentMeds(widget.patientId);
      if (mounted) setState(() {
        _allergies = a;
        _meds = m;
      });
    } catch (_) {}
  }

  // ------------------------------------------------------------ allergies
  Future<void> _addAllergy() async {
    final name = TextEditingController();
    final reaction = TextEditingController();
    String kind = 'drug';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Add allergy'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: 8,
                  children: {'drug': 'Drug', 'food': 'Food', 'other': 'Other'}
                      .entries
                      .map((e) => ChoiceChip(
                            label: Text(e.value),
                            selected: kind == e.key,
                            onSelected: (_) => set(() => kind = e.key),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 12),
                Field('Allergic to', name),
                Field('Reaction (optional)', reaction),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
          ],
        ),
      ),
    );
    if (ok != true || name.text.trim().isEmpty || !mounted) return;
    await guard(context, () => Db.addAllergy({
          'patient_id': widget.patientId,
          'kind': kind,
          'name': name.text.trim(),
          'reaction': reaction.text.trim(),
        }));
    _load();
  }

  // ------------------------------------------------------------ medications
  Future<void> _editMed([DbRow? m]) async {
    final name = TextEditingController(text: str(m?['name']));
    final dose = TextEditingController(text: str(m?['dose']));
    final freq = TextEditingController(text: str(m?['frequency']));
    final since = TextEditingController(text: str(m?['since']));
    final by = TextEditingController(text: str(m?['prescribed_by']));
    String system = str(m?['system']).isEmpty ? 'allopathy' : str(m?['system']);
    String timing = str(m?['timing']);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(m == null ? 'Add current medicine' : 'Edit medicine'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: 8,
                  children: {'siddha': 'Siddha', 'allopathy': 'Allopathy', 'other': 'Other'}
                      .entries
                      .map((e) => ChoiceChip(
                            label: Text(e.value),
                            selected: system == e.key,
                            onSelected: (_) => set(() => system = e.key),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 12),
                Field('Medicine name', name),
                Field('Dose', dose, hint: '500 mg, 1 tsp…'),
                Field('Frequency', freq, hint: '1-0-1, once daily…'),
                Wrap(
                  spacing: 8,
                  children: ['Before food', 'After food']
                      .map((t) => ChoiceChip(
                            label: Text(t),
                            selected: timing == t,
                            onSelected: (s) => set(() => timing = s ? t : ''),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 12),
                Field('Since', since, hint: '2 years'),
                Field('Prescribed by', by),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true || name.text.trim().isEmpty || !mounted) return;
    await guard(
        context,
        () => Db.saveCurrentMed({
              'patient_id': widget.patientId,
              'system': system,
              'name': name.text.trim(),
              'dose': dose.text.trim(),
              'frequency': freq.text.trim(),
              'timing': timing,
              'since': since.text.trim(),
              'prescribed_by': by.text.trim(),
            }, id: m?['id']));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SectionCard(
          title: 'Allergies',
          trailing: IconButton(
              onPressed: _addAllergy, icon: const Icon(Icons.add_circle_outline)),
          child: _allergies.isEmpty
              ? const Text('No known allergies', style: TextStyle(color: Brand.muted))
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _allergies
                      .map((a) => InputChip(
                            avatar: const Icon(Icons.warning_amber_rounded,
                                size: 18, color: Brand.danger),
                            label: Text([
                              str(a['name']),
                              if (str(a['reaction']).isNotEmpty) '(${a['reaction']})'
                            ].join(' ')),
                            backgroundColor: Brand.danger.withValues(alpha: 0.08),
                            onDeleted: () async {
                              await guard(context, () => Db.deleteAllergy(a['id']));
                              _load();
                            },
                          ))
                      .toList(),
                ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: 'Current medications',
          trailing:
              IconButton(onPressed: () => _editMed(), icon: const Icon(Icons.add_circle_outline)),
          child: _meds.isEmpty
              ? const Text('None recorded', style: TextStyle(color: Brand.muted))
              : Column(
                  children: _meds
                      .map((m) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            leading: Tag(
                                str(m['system']) == 'siddha'
                                    ? 'Siddha'
                                    : (str(m['system']) == 'allopathy' ? 'Allo' : 'Other'),
                                color: str(m['system']) == 'siddha' ? Brand.sageDark : Brand.teal),
                            title: Text(str(m['name']),
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text([
                              str(m['dose']),
                              str(m['frequency']),
                              str(m['timing']),
                              if (str(m['since']).isNotEmpty) 'since ${m['since']}',
                            ].where((s) => s.isNotEmpty).join(' · ')),
                            trailing: PopupMenuButton<String>(
                              onSelected: (v) async {
                                if (v == 'edit') _editMed(m);
                                if (v == 'stop') {
                                  await guard(context, () => Db.stopCurrentMed(m['id']));
                                  _load();
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 'edit', child: Text('Edit')),
                                PopupMenuItem(value: 'stop', child: Text('Stopped / remove')),
                              ],
                            ),
                          ))
                      .toList(),
                ),
        ),
      ],
    );
  }
}
