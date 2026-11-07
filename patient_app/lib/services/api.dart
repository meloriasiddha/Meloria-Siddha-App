import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';

typedef DbRow = Map<String, dynamic>;

/// Everything the patient app reads or writes goes through secure database
/// functions (see supabase/migrations/005_patient_app.sql). They only ever
/// return the signed-in patient's own records.
class Api {
  static SupabaseClient get _c => Supabase.instance.client;

  // ------------------------------------------------------------ auth
  /// Phone number → internal sign-in id (patients never see this).
  static String phoneDigits(String phone) {
    final d = phone.replaceAll(RegExp(r'\D'), '');
    return d.length > 10 ? d.substring(d.length - 10) : d;
  }

  static String _email(String phone) => '${phoneDigits(phone)}@$patientEmailDomain';

  static Future<void> signIn(String phone, String pin) =>
      _c.auth.signInWithPassword(email: _email(phone), password: pin);

  /// Returns true if signed in straight away.
  static Future<bool> signUp(String phone, String pin) async {
    final r = await _c.auth.signUp(email: _email(phone), password: pin);
    return r.session != null;
  }

  static Future<void> signOut() => _c.auth.signOut();

  static String? get currentEmail => _c.auth.currentUser?.email;

  static Future<void> changePin(String pin) => _c.auth.updateUser(UserAttributes(password: pin));

  static Future<void> requestPinReset(String phone) =>
      _c.rpc('app_request_pin_reset', params: {'p_phone': phoneDigits(phone)});

  // ------------------------------------------------------------ calls
  static Future<dynamic> _rpc(String fn, [Map<String, dynamic>? params]) =>
      _c.rpc(fn, params: params ?? {});

  static Future<DbRow> register(String name, String phone, DateTime dob) async =>
      Map<String, dynamic>.from(await _rpc('app_register', {
        'p_name': name,
        'p_phone': phoneDigits(phone),
        'p_dob': dob.toIso8601String().substring(0, 10),
      }));

  static Future<DbRow> me() async => Map<String, dynamic>.from(await _rpc('app_me'));

  static Future<DbRow> doctor() async => Map<String, dynamic>.from(await _rpc('app_doctor'));

  static Future<List<DbRow>> programs() async => _list(await _rpc('app_programs'));

  static Future<DbRow> day(DateTime d) async =>
      Map<String, dynamic>.from(await _rpc('app_day', {'p_date': _iso(d)}));

  static Future<List<DbRow>> appointments(String patientId) async =>
      _list(await _rpc('app_appointments', {'p_patient': patientId}));

  static Future<DbRow> book({
    required String patientId,
    required DateTime date,
    required String time,
    required String mode,
    required String payment,
    String? program,
    String? notes,
  }) async =>
      Map<String, dynamic>.from(await _rpc('app_book', {
        'p_patient': patientId,
        'p_date': _iso(date),
        'p_time': time,
        'p_mode': mode,
        'p_payment': payment,
        'p_program': program,
        'p_notes': notes,
      }));

  static Future<void> cancel(String apptId, {String? refund}) =>
      _rpc('app_cancel', {'p_appt': apptId, 'p_refund': refund});

  static Future<void> reschedule(String apptId, DateTime date, String time) =>
      _rpc('app_reschedule', {'p_appt': apptId, 'p_date': _iso(date), 'p_time': time});

  static Future<List<DbRow>> visits(String patientId) async =>
      _list(await _rpc('app_visits', {'p_patient': patientId}));

  static Future<List<DbRow>> bills(String patientId) async =>
      _list(await _rpc('app_bills', {'p_patient': patientId}));

  static Future<DbRow> bill(String billId) async =>
      Map<String, dynamic>.from(await _rpc('app_bill', {'p_bill': billId}));

  static Future<List<DbRow>> trackers(String patientId) async =>
      _list(await _rpc('app_trackers', {'p_patient': patientId}));

  static Future<List<DbRow>> thread(String patientId) async =>
      _list(await _rpc('app_thread', {'p_patient': patientId}));

  static Future<void> post({
    required String patientId,
    required String kind,
    String? trackerId,
    String? entryType,
    String? slot,
    Map<String, dynamic>? data,
    String? body,
  }) =>
      _rpc('app_post', {
        'p_patient': patientId,
        'p_kind': kind,
        'p_tracker': trackerId,
        'p_entry_type': entryType,
        'p_slot': slot,
        'p_data': data,
        'p_body': body,
      });

  static Future<void> joinProgram(String patientId, String programId, int months) =>
      _rpc('app_join_program', {'p_patient': patientId, 'p_program': programId, 'p_months': months});

  // ------------------------------------------------------------ helpers
  static String _iso(DateTime d) => d.toIso8601String().substring(0, 10);

  static List<DbRow> _list(dynamic v) =>
      v is List ? v.map((e) => Map<String, dynamic>.from(e as Map)).toList() : <DbRow>[];
}

/// Who is signed in and which family member is selected.
class AppState {
  static final me = ValueNotifier<DbRow?>(null);
  static final selected = ValueNotifier<String?>(null);

  static List<DbRow> get patients =>
      ((me.value?['patients'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  static DbRow? get account =>
      me.value?['account'] == null ? null : Map<String, dynamic>.from(me.value!['account'] as Map);

  static DbRow? get patient {
    final list = patients;
    if (list.isEmpty) return null;
    return list.firstWhere((p) => p['id'] == selected.value, orElse: () => list.first);
  }

  static String? get patientId => patient?['id'];

  /// True once the clinic has confirmed / linked the account.
  static bool get confirmed => account?['status'] == 'linked';

  static Future<void> refresh() async {
    final m = await Api.me();
    me.value = m;
    final ids = patients.map((p) => p['id']).toList();
    if (selected.value == null || !ids.contains(selected.value)) {
      selected.value = ids.isEmpty ? null : ids.first as String;
    }
  }
}
