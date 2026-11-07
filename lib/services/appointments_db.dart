import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import 'db.dart';

/// Database calls for appointments and the calendar.
class ApptDb {
  static SupabaseClient get _c => Supabase.instance.client;

  static const _select = '*, patients(id, name, age, gender, patient_code, phone)';

  /// Appointments between two dates (inclusive), cancelled ones excluded.
  static Future<List<DbRow>> between(String fromIso, String toIso) async => await _c
      .from('appointments')
      .select(_select)
      .gte('appt_date', fromIso)
      .lte('appt_date', toIso)
      .neq('status', 'cancelled')
      .order('appt_date')
      .order('start_time');

  static Future<List<DbRow>> forPatient(String patientId) async => await _c
      .from('appointments')
      .select()
      .eq('patient_id', patientId)
      .order('appt_date', ascending: false)
      .order('start_time', ascending: false)
      .limit(30);

  static Future<DbRow> get(String id) async =>
      await _c.from('appointments').select(_select).eq('id', id).single();

  static Future<DbRow> save(DbRow data, {String? id}) async {
    if (id == null) {
      data['branch_id'] = currentBranchId;
      return await _c.from('appointments').insert(data).select().single();
    }
    return await _c.from('appointments').update(data).eq('id', id).select().single();
  }

  static Future<void> setStatus(String id, String status) =>
      _c.from('appointments').update({'status': status}).eq('id', id);

  static Future<void> update(String id, DbRow data) =>
      _c.from('appointments').update(data).eq('id', id);

  /// Initial if the patient has never visited, or their last visit was
  /// more than 3 months ago; otherwise Review.
  static Future<String> suggestedType(String patientId) async {
    final r = await _c
        .from('visits')
        .select('visit_date')
        .eq('patient_id', patientId)
        .neq('status', 'cancelled')
        .order('visit_date', ascending: false)
        .limit(1);
    if (r.isEmpty) return 'initial';
    final last = DateTime.tryParse(r.first['visit_date'].toString());
    if (last == null) return 'initial';
    return DateTime.now().difference(last).inDays > 90 ? 'initial' : 'review';
  }

  /// Clinic sessions from settings, e.g. [{name: Morning, start: 06:30, end: 07:30}].
  static Future<List<Map<String, dynamic>>> sessions() async {
    try {
      final s = await _c.from('clinic_settings').select('sessions').eq('id', 1).maybeSingle();
      final list = (s?['sessions'] as List?) ?? [];
      if (list.isNotEmpty) return list.cast<Map<String, dynamic>>();
    } catch (_) {}
    return [
      {'name': 'Morning', 'start': '06:30', 'end': '07:30'},
      {'name': 'Evening', 'start': '18:30', 'end': '21:00'},
    ];
  }
}
