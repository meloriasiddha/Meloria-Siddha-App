import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';

typedef DbRow = Map<String, dynamic>;

/// All database calls in one place. Each method maps to a table in
/// supabase/schema.sql, so it is easy to find and change.
class Db {
  static SupabaseClient get _c => Supabase.instance.client;

  // ------------------------------------------------------------ auth
  static User? get user => _c.auth.currentUser;

  static Future<void> signIn(String email, String password) =>
      _c.auth.signInWithPassword(email: email.trim(), password: password);

  static Future<void> signOut() => _c.auth.signOut();

  /// Returns the staff profile ({full_name, role}) or null if this
  /// login is not registered as doctor/staff.
  static Future<DbRow?> myProfile() async {
    final u = user;
    if (u == null) return null;
    return await _c.from('staff_profiles').select().eq('id', u.id).maybeSingle();
  }

  // ------------------------------------------------------------ patients
  static Future<List<DbRow>> searchPatients(String q) async {
    final query = _c.from('patients').select();
    final t = q.trim().replaceAll(',', ' ');
    if (t.isEmpty) {
      return await query.order('created_at', ascending: false).limit(50);
    }
    return await query
        .or('name.ilike.%$t%,phone.ilike.%$t%,patient_code.ilike.%$t%,referred_by_name.ilike.%$t%')
        .order('name')
        .limit(50);
  }

  static Future<DbRow> getPatient(String id) async =>
      await _c.from('patients').select().eq('id', id).single();

  static Future<DbRow> savePatient(DbRow data, {String? id}) async {
    if (id == null) {
      data['branch_id'] = currentBranchId;
      return await _c.from('patients').insert(data).select().single();
    }
    return await _c.from('patients').update(data).eq('id', id).select().single();
  }

  // ---------------------------------------- allergies & current meds
  static Future<List<DbRow>> allergies(String patientId) async =>
      await _c.from('patient_allergies').select().eq('patient_id', patientId).order('created_at');

  static Future<void> addAllergy(DbRow data) => _c.from('patient_allergies').insert(data);

  static Future<void> deleteAllergy(String id) => _c.from('patient_allergies').delete().eq('id', id);

  static Future<List<DbRow>> currentMeds(String patientId) async => await _c
      .from('current_medications')
      .select()
      .eq('patient_id', patientId)
      .eq('active', true)
      .order('created_at');

  static Future<void> saveCurrentMed(DbRow data, {String? id}) async {
    if (id == null) {
      await _c.from('current_medications').insert(data);
    } else {
      await _c.from('current_medications').update(data).eq('id', id);
    }
  }

  static Future<void> stopCurrentMed(String id) =>
      _c.from('current_medications').update({'active': false}).eq('id', id);

  // ------------------------------------------------------------ visits
  static Future<List<DbRow>> todaysVisits() async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    return await _c
        .from('visits')
        .select('*, patients(id, name, age, gender, patient_code, phone), bills(id, status)')
        .eq('visit_date', today)
        .neq('status', 'cancelled')
        .order('created_at');
  }

  static Future<List<DbRow>> patientVisits(String patientId) async => await _c
      .from('visits')
      .select('*, consultations(*)')
      .eq('patient_id', patientId)
      .order('created_at', ascending: false);

  static Future<DbRow> getVisit(String id) async =>
      await _c.from('visits').select('*, patients(*)').eq('id', id).single();

  static Future<DbRow> saveVisit(DbRow data, {String? id}) async {
    if (id == null) {
      data['branch_id'] = currentBranchId;
      return await _c.from('visits').insert(data).select().single();
    }
    return await _c.from('visits').update(data).eq('id', id).select().single();
  }

  static Future<void> setVisitStatus(String id, String status) =>
      _c.from('visits').update({'status': status}).eq('id', id);

  /// Count of visits for the patient (used to suggest first vs review).
  static Future<int> visitCount(String patientId) async {
    final r = await _c.from('visits').select('id').eq('patient_id', patientId);
    return r.length;
  }

  // ------------------------------------------------------------ consultation
  static Future<DbRow?> consultation(String visitId) async =>
      await _c.from('consultations').select().eq('visit_id', visitId).maybeSingle();

  /// Most recent earlier consultation for this patient (to copy history).
  static Future<DbRow?> lastConsultation(String patientId, String excludeVisitId) async {
    final r = await _c
        .from('visits')
        .select('id, consultations(*)')
        .eq('patient_id', patientId)
        .neq('id', excludeVisitId)
        .order('created_at', ascending: false)
        .limit(5);
    for (final v in r) {
      final c = v['consultations'];
      if (c is List && c.isNotEmpty) return c.first as DbRow;
      if (c is Map<String, dynamic>) return c;
    }
    return null;
  }

  static Future<void> saveConsultation(DbRow data) async {
    data['updated_at'] = DateTime.now().toIso8601String();
    await _c.from('consultations').upsert(data, onConflict: 'visit_id');
  }

  static Future<List<DbRow>> prescriptions(String visitId) async => await _c
      .from('prescriptions')
      .select('*, medicines(name, form, unit, price), medicine_batches(batch_no, expiry_date)')
      .eq('visit_id', visitId)
      .order('created_at');

  static Future<void> addPrescription(DbRow data) => _c.from('prescriptions').insert(data);

  static Future<void> deletePrescription(String id) => _c.from('prescriptions').delete().eq('id', id);

  static Future<List<DbRow>> visitAdvice(String visitId) async =>
      await _c.from('visit_advice').select().eq('visit_id', visitId);

  static Future<void> addVisitAdvice(DbRow data) => _c.from('visit_advice').insert(data);

  static Future<void> deleteVisitAdvice(String id) => _c.from('visit_advice').delete().eq('id', id);

  static Future<List<DbRow>> dietTemplates() async =>
      await _c.from('diet_templates').select().order('name');

  // ------------------------------------------------------------ stock
  static Future<List<DbRow>> medicines({bool activeOnly = true}) async {
    var q = _c.from('medicines').select('*, medicine_batches(*)');
    if (activeOnly) q = q.eq('active', true);
    return await q.order('name');
  }

  static Future<DbRow> saveMedicine(DbRow data, {String? id}) async {
    if (id == null) return await _c.from('medicines').insert(data).select().single();
    return await _c.from('medicines').update(data).eq('id', id).select().single();
  }

  static Future<void> saveBatch(DbRow data, {String? id}) async {
    if (id == null) {
      await _c.from('medicine_batches').insert(data);
    } else {
      await _c.from('medicine_batches').update(data).eq('id', id);
    }
  }

  static Future<void> deleteBatch(String id) => _c.from('medicine_batches').delete().eq('id', id);

  // ------------------------------------------------------------ advice list
  static Future<List<DbRow>> adviceItems() async =>
      await _c.from('advice_items').select().eq('active', true).order('name');

  static Future<void> saveAdviceItem(DbRow data, {String? id}) async {
    if (id == null) {
      await _c.from('advice_items').insert(data);
    } else {
      await _c.from('advice_items').update(data).eq('id', id);
    }
  }

  static Future<void> removeAdviceItem(String id) =>
      _c.from('advice_items').update({'active': false}).eq('id', id);
}
