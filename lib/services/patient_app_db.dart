import 'package:supabase_flutter/supabase_flutter.dart';

import 'db.dart';

/// Staff-side calls for everything connected to the patient app:
/// sign-ups, program requests, PIN resets, availability, program pages, doctor profile.
class PatientAppDb {
  static SupabaseClient get _c => Supabase.instance.client;

  // ------------------------------------------------------------ sign-ups
  static Future<List<DbRow>> signups() async {
    final r = await _c.rpc('staff_app_signups');
    return r is List ? r.map((e) => Map<String, dynamic>.from(e as Map)).toList() : [];
  }

  static Future<void> link(String userId, String patientId) =>
      _c.rpc('staff_link_account', params: {'p_user': userId, 'p_patient': patientId});

  static Future<String?> confirmNew(String userId) async =>
      (await _c.rpc('staff_confirm_new', params: {'p_user': userId}))?.toString();

  static Future<void> reject(String userId) => _c.rpc('staff_reject_account', params: {'p_user': userId});

  static Future<void> resetPin(String phone, String pin) =>
      _c.rpc('staff_reset_pin', params: {'p_phone': phone, 'p_pin': pin});

  static Future<List<DbRow>> pinRequests() async => await _c
      .from('pin_reset_requests')
      .select()
      .eq('status', 'new')
      .order('created_at', ascending: false);

  static Future<void> dismissPinRequest(String id) =>
      _c.from('pin_reset_requests').update({'status': 'done'}).eq('id', id);

  /// Number of things waiting for staff (new sign-ups + program requests + PIN resets).
  static Future<int> pendingCount() async {
    try {
      final a = await _c.from('app_accounts').select('user_id').eq('status', 'pending');
      final b = await _c.from('program_requests').select('id').eq('status', 'new');
      final c = await _c.from('pin_reset_requests').select('id').eq('status', 'new');
      return a.length + b.length + c.length;
    } catch (_) {
      return 0;
    }
  }

  // ------------------------------------------------------------ program requests
  static Future<List<DbRow>> programRequests() async => await _c
      .from('program_requests')
      .select('*, patients(id, name, patient_code, phone)')
      .eq('status', 'new')
      .order('created_at', ascending: false);

  static Future<void> setRequestStatus(String id, String status) =>
      _c.from('program_requests').update({'status': status}).eq('id', id);

  // ------------------------------------------------------------ availability
  static Future<List<DbRow>> blocks() async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    return await _c.from('clinic_blocks').select().gte('block_date', today).order('block_date').order('start_time');
  }

  static Future<List<DbRow>> blocksBetween(String from, String to) async =>
      await _c.from('clinic_blocks').select().gte('block_date', from).lte('block_date', to);

  static Future<void> addBlock(DbRow data) => _c.from('clinic_blocks').insert(data);

  static Future<void> deleteBlock(String id) => _c.from('clinic_blocks').delete().eq('id', id);

  // ------------------------------------------------------------ programs
  static Future<List<DbRow>> programsWithPlans() async => await _c
      .from('programs')
      .select('*, program_plans(*)')
      .eq('active', true)
      .order('sort')
      .order('name');

  static Future<void> saveProgram(String id, DbRow data) => _c.from('programs').update(data).eq('id', id);

  static Future<void> savePlan(DbRow data, {String? id}) async {
    if (id == null) {
      await _c.from('program_plans').insert(data);
    } else {
      await _c.from('program_plans').update(data).eq('id', id);
    }
  }

  static Future<void> deletePlan(String id) => _c.from('program_plans').delete().eq('id', id);

  // ------------------------------------------------------------ doctor profile
  static Future<DbRow> settings() async =>
      await _c.from('clinic_settings').select().eq('id', 1).single();

  static Future<void> saveSettings(DbRow data) => _c.from('clinic_settings').update(data).eq('id', 1);
}
