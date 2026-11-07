import 'package:flutter/material.dart';

import '../services/appointments_db.dart';
import '../services/db.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/patient_picker.dart';

/// Book a new appointment, or edit / reschedule an existing one.
/// Doctor and staff can overbook (overlapping times are allowed).
class BookAppointmentScreen extends StatefulWidget {
  const BookAppointmentScreen({super.key, this.patient, this.appointment, this.date});
  final DbRow? patient;
  final DbRow? appointment; // edit / reschedule
  final DateTime? date;

  @override
  State<BookAppointmentScreen> createState() => _BookAppointmentScreenState();
}

class _BookAppointmentScreenState extends State<BookAppointmentScreen> {
  DbRow? _patient;
  late DateTime _date;
  TimeOfDay _time = const TimeOfDay(hour: 18, minute: 30);
  String _type = 'review';
  String _mode = 'offline';
  int _minutes = 10;
  bool _paid = false;
  bool _typeTouched = false;
  final _therapy = TextEditingController();
  final _notes = TextEditingController();
  List<DbRow> _advice = [];
  bool _saving = false;

  bool get _editing => widget.appointment != null;

  @override
  void initState() {
    super.initState();
    _date = widget.date ?? DateTime.now();
    final a = widget.appointment;
    if (a != null) {
      _patient = a['patients'] as DbRow?;
      _date = DateTime.parse(a['appt_date']);
      final t = str(a['start_time']).split(':');
      _time = TimeOfDay(hour: int.parse(t[0]), minute: int.parse(t[1]));
      _type = str(a['appt_type']);
      _mode = str(a['mode']);
      _minutes = a['duration_min'] ?? 10;
      _paid = a['paid'] == true;
      _therapy.text = str(a['therapy_name']);
      _notes.text = str(a['notes']);
      _typeTouched = true;
    } else {
      final now = TimeOfDay.now();
      _time = now.hour < 12 ? const TimeOfDay(hour: 6, minute: 30) : const TimeOfDay(hour: 18, minute: 30);
      if (widget.patient != null) _setPatient(widget.patient!);
    }
    Db.adviceItems().then((r) {
      if (mounted) setState(() => _advice = r);
    }).catchError((_) {});
  }

  Future<void> _setPatient(DbRow p) async {
    setState(() => _patient = p);
    final locked = str(p['locked_mode']);
    if (locked.isNotEmpty) setState(() => _mode = locked);
    if (!_typeTouched) {
      try {
        final t = await ApptDb.suggestedType(p['id']);
        if (mounted && !_typeTouched) {
          setState(() {
            _type = t;
            _minutes = ApptStyle.defaultMinutes(t);
          });
        }
      } catch (_) {}
    }
  }

  Future<void> _pickPatient() async {
    final p = await pickPatient(context);
    if (p != null) _setPatient(p);
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: _time);
    if (t != null) setState(() => _time = t);
  }

  Future<void> _save() async {
    if (_patient == null) {
      showMsg(context, 'Choose a patient', error: true);
      return;
    }
    setState(() => _saving = true);
    final online = _mode != 'offline';
    final hh = _time.hour.toString().padLeft(2, '0');
    final mm = _time.minute.toString().padLeft(2, '0');
    final data = <String, dynamic>{
      'patient_id': _patient!['id'],
      'appt_date': isoDate(_date),
      'start_time': '$hh:$mm:00',
      'duration_min': _minutes,
      'appt_type': _type,
      'mode': _mode,
      'therapy_name': _therapy.text.trim().isEmpty ? null : _therapy.text.trim(),
      'notes': _notes.text.trim(),
      'paid': _paid,
      'payment_choice': online ? 'online' : 'clinic',
    };
    final current = str(widget.appointment?['status']);
    if (!_editing || current == 'booked' || current == 'pending_payment') {
      // Online consultations wait for payment before they are confirmed.
      data['status'] = (online && !_paid) ? 'pending_payment' : 'booked';
    }
    final ok = await guard(context, () => ApptDb.save(data, id: widget.appointment?['id']));
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      showMsg(context, _editing ? 'Appointment updated' : 'Appointment booked');
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = str(_patient?['locked_mode']);
    final needsName = _type == 'therapy' || _type == 'procedure' || _type == 'program';
    final color = ApptStyle.background(_type, _mode);

    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Edit appointment' : 'Book appointment')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Preview strip in the booking's colour
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              Icon(ApptStyle.modeIcon(_mode), color: ApptStyle.foreground(_mode)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${ApptStyle.types[_type]} · ${ApptStyle.modes[_mode]} · $_minutes min',
                  style: TextStyle(
                      color: ApptStyle.foreground(_mode), fontWeight: FontWeight.w600),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: 'Patient',
            child: _patient == null
                ? OutlinedButton.icon(
                    onPressed: _pickPatient,
                    icon: const Icon(Icons.person_search_outlined),
                    label: const Text('Choose patient'),
                  )
                : ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: PatientAvatar(str(_patient!['name'])),
                    title: Text(str(_patient!['name']),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${_patient!['patient_code']} · ${str(_patient!['phone'])}'),
                    trailing: _editing
                        ? null
                        : TextButton(onPressed: _pickPatient, child: const Text('Change')),
                  ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: 'Date and time',
            child: Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_month_outlined, size: 18),
                  label: Text(fmtDate(_date)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickTime,
                  icon: const Icon(Icons.schedule, size: 18),
                  label: Text(_time.format(context)),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: 'Type',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ApptStyle.types.entries.map((e) {
                final sel = _type == e.key;
                return ChoiceChip(
                  avatar: CircleAvatar(backgroundColor: ApptStyle.solid(e.key), radius: 6),
                  label: Text(e.value),
                  selected: sel,
                  onSelected: (_) => setState(() {
                    _type = e.key;
                    _typeTouched = true;
                    _minutes = ApptStyle.defaultMinutes(e.key);
                  }),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: 'Mode',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  children: ApptStyle.modes.entries
                      .map((e) => ChoiceChip(
                            avatar: Icon(ApptStyle.modeIcon(e.key), size: 18),
                            label: Text(e.value),
                            selected: _mode == e.key,
                            onSelected: (_) => setState(() => _mode = e.key),
                          ))
                      .toList(),
                ),
                if (locked.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                        'Doctor has set ${ApptStyle.modes[locked]} for this patient. The patient app will not let them change it.',
                        style: const TextStyle(color: Brand.muted, fontSize: 12)),
                  ),
                if (_mode != 'offline') ...[
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _paid,
                    onChanged: (v) => setState(() => _paid = v),
                    title: const Text('Payment received'),
                    subtitle: const Text('Online consultations are confirmed only after payment'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: 'Length',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [10, 15, 20, 30, 45, 60, 90]
                  .map((m) => ChoiceChip(
                        label: Text('$m min'),
                        selected: _minutes == m,
                        onSelected: (_) => setState(() => _minutes = m),
                      ))
                  .toList(),
            ),
          ),
          if (needsName) ...[
            const SizedBox(height: 14),
            SectionCard(
              title: _type == 'program' ? 'Program' : 'Therapy / procedure',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Field('Name', _therapy,
                      hint: _type == 'program' ? 'Diabetes, PCOD, Weight loss…' : 'Varmam, Thokkanam…'),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: (_type == 'program'
                            ? ['Diabetes', 'PCOD', 'Weight loss']
                            : _advice.map((a) => str(a['name'])).toList())
                        .map((n) => ActionChip(
                              label: Text(n),
                              onPressed: () => setState(() => _therapy.text = n),
                            ))
                        .toList(),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          SectionCard(title: 'Notes', child: Field('Notes (optional)', _notes, maxLines: 2)),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Saving…' : (_editing ? 'SAVE CHANGES' : 'BOOK APPOINTMENT')),
          ),
          const SizedBox(height: 8),
          const Text('Overlapping times are allowed.',
              textAlign: TextAlign.center, style: TextStyle(color: Brand.muted, fontSize: 12)),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
