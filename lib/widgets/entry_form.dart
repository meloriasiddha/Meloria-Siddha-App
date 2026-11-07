import 'package:flutter/material.dart';

import '../services/db.dart';
import '../services/trackers.dart';
import '../theme.dart';
import 'common.dart';

/// Result of the "add reading" form.
class EntryResult {
  EntryResult(this.slot, this.data);
  final String? slot;
  final Map<String, dynamic> data;
}

/// Bottom-sheet form to record one reading for a tracker.
/// Used by staff now, and by patients in the patient app later.
Future<EntryResult?> showEntryForm(BuildContext context, DbRow tracker) =>
    showModalBottomSheet<EntryResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EntryForm(tracker: tracker),
    );

class _EntryForm extends StatefulWidget {
  const _EntryForm({required this.tracker});
  final DbRow tracker;

  @override
  State<_EntryForm> createState() => _EntryFormState();
}

class _EntryFormState extends State<_EntryForm> {
  late final TrackerDef def = Trackers.def(str(widget.tracker['kind']));
  late final List<String> slotKeys =
      ((widget.tracker['slots'] as List?) ?? []).map((e) => e.toString()).toList();
  String? _slot;
  final _value = TextEditingController();
  final _v2 = TextEditingController();
  final _v3 = TextEditingController();
  final _text = TextEditingController();
  String _event = 'started';
  String _flow = '';
  String _pain = '';
  String _quality = '';
  TimeOfDay? _bed;
  TimeOfDay? _wake;

  @override
  void initState() {
    super.initState();
    final options = slotKeys.isNotEmpty ? slotKeys : def.slots.keys.toList();
    if (options.isNotEmpty) _slot = options.first;
  }

  String _t(TimeOfDay? t) =>
      t == null ? '' : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  void _submit() {
    final d = <String, dynamic>{};
    switch (def.kind) {
      case 'bp':
        if (toNum(_value.text) == null || toNum(_v2.text) == null) return _err('Enter both BP values');
        d['systolic'] = toNum(_value.text);
        d['diastolic'] = toNum(_v2.text);
        if (toNum(_v3.text) != null) d['pulse'] = toNum(_v3.text);
      case 'diet':
      case 'symptoms':
        if (_text.text.trim().isEmpty) return _err('Write what to record');
        d['text'] = _text.text.trim();
      case 'periods':
        d['event'] = _event;
        if (_flow.isNotEmpty) d['flow'] = _flow;
        if (_pain.isNotEmpty) d['pain'] = _pain;
        if (_text.text.trim().isNotEmpty) d['text'] = _text.text.trim();
      case 'sleep':
        d['bed'] = _t(_bed);
        d['wake'] = _t(_wake);
        if (_quality.isNotEmpty) d['quality'] = _quality;
      case 'exercise':
        if (toNum(_value.text) == null) return _err('Enter minutes');
        d['value'] = toNum(_value.text);
        if (_text.text.trim().isNotEmpty) d['text'] = _text.text.trim();
      default:
        if (toNum(_value.text) == null) return _err('Enter a value');
        d['value'] = toNum(_value.text);
        final unit = str(widget.tracker['unit']).isNotEmpty ? str(widget.tracker['unit']) : def.unit;
        if (unit.isNotEmpty) d['unit'] = unit;
    }
    Navigator.pop(context, EntryResult(_slot, d));
  }

  void _err(String m) => showMsg(context, m, error: true);

  Widget _chips(Map<String, String> opts, String value, ValueChanged<String> on) => Wrap(
        spacing: 8,
        runSpacing: 6,
        children: opts.entries
            .map((e) => ChoiceChip(
                label: Text(e.value), selected: value == e.key, onSelected: (_) => on(e.key)))
            .toList(),
      );

  @override
  Widget build(BuildContext context) {
    final label = str(widget.tracker['label']).isNotEmpty ? str(widget.tracker['label']) : def.label;
    final unit = str(widget.tracker['unit']).isNotEmpty ? str(widget.tracker['unit']) : def.unit;
    final slotOpts = {
      for (final k in (slotKeys.isNotEmpty ? slotKeys : def.slots.keys)) k: def.slots[k] ?? k
    };
    const num = TextInputType.numberWithOptions(decimal: true);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              CircleAvatar(
                  backgroundColor: def.color.withValues(alpha: 0.12),
                  child: Icon(def.icon, color: def.color)),
              const SizedBox(width: 12),
              Text('Add $label', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 16),
            if (slotOpts.isNotEmpty) ...[
              _chips(slotOpts, _slot ?? '', (v) => setState(() => _slot = v)),
              const SizedBox(height: 14),
            ],
            ...switch (def.kind) {
              'bp' => [
                  Row(children: [
                    Expanded(child: Field('Systolic', _value, keyboard: num)),
                    const SizedBox(width: 10),
                    Expanded(child: Field('Diastolic', _v2, keyboard: num)),
                    const SizedBox(width: 10),
                    Expanded(child: Field('Pulse', _v3, keyboard: num)),
                  ])
                ],
              'diet' => [Field('What was eaten', _text, maxLines: 3, hint: '2 idli, sambar, tea without sugar')],
              'symptoms' => [Field('How are you feeling?', _text, maxLines: 3)],
              'periods' => [
                  _chips({'started': 'Period started', 'ended': 'Period ended'}, _event,
                      (v) => setState(() => _event = v)),
                  const SizedBox(height: 10),
                  const Text('Flow', style: TextStyle(color: Brand.muted)),
                  const SizedBox(height: 4),
                  _chips({'light': 'Light', 'medium': 'Medium', 'heavy': 'Heavy'}, _flow,
                      (v) => setState(() => _flow = v)),
                  const SizedBox(height: 10),
                  const Text('Pain', style: TextStyle(color: Brand.muted)),
                  const SizedBox(height: 4),
                  _chips({'none': 'None', 'mild': 'Mild', 'severe': 'Severe'}, _pain,
                      (v) => setState(() => _pain = v)),
                  const SizedBox(height: 10),
                  Field('Notes', _text),
                ],
              'sleep' => [
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.bedtime_outlined, size: 18),
                        label: Text(_bed == null ? 'Bed time' : _bed!.format(context)),
                        onPressed: () async {
                          final t = await showTimePicker(
                              context: context, initialTime: const TimeOfDay(hour: 22, minute: 30));
                          if (t != null) setState(() => _bed = t);
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.wb_sunny_outlined, size: 18),
                        label: Text(_wake == null ? 'Wake time' : _wake!.format(context)),
                        onPressed: () async {
                          final t = await showTimePicker(
                              context: context, initialTime: const TimeOfDay(hour: 6, minute: 0));
                          if (t != null) setState(() => _wake = t);
                        },
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  _chips({'good': 'Slept well', 'ok': 'Okay', 'poor': 'Poor'}, _quality,
                      (v) => setState(() => _quality = v)),
                ],
              'exercise' => [
                  Field('Minutes', _value, keyboard: num, suffix: 'min'),
                  Field('What exercise', _text, hint: 'Walking, yoga…'),
                ],
              _ => [Field(label, _value, keyboard: num, suffix: unit)],
            },
            const SizedBox(height: 12),
            FilledButton(onPressed: _submit, child: const Text('SAVE')),
          ],
        ),
      ),
    );
  }
}
