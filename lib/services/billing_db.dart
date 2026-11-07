import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import 'db.dart';

/// Result of the consultation-fee rule check.
class FeeCheck {
  FeeCheck(this.charge, this.note);
  final bool charge;
  final String note;
}

/// Database calls for bills, programs and clinic settings.
class BillDb {
  static SupabaseClient get _c => Supabase.instance.client;

  // ------------------------------------------------------------ settings
  static Future<DbRow> settings() async =>
      (await _c.from('clinic_settings').select().eq('id', 1).maybeSingle()) ??
      {'consultation_fee': 300, 'fee_valid_days': 30, 'fee_valid_visits': 4, 'gst_enabled': false};

  static Future<void> saveSettings(DbRow data) =>
      _c.from('clinic_settings').update(data).eq('id', 1);

  static Future<String> doctorName() async {
    final r = await _c.from('staff_profiles').select('full_name').eq('role', 'doctor').limit(1);
    return r.isEmpty ? '' : r.first['full_name'].toString();
  }

  // ------------------------------------------------------------ programs
  static Future<List<DbRow>> programs() async =>
      await _c.from('programs').select().eq('active', true).order('name');

  static Future<void> saveProgram(DbRow data, {String? id}) async {
    if (id == null) {
      await _c.from('programs').insert(data);
    } else {
      await _c.from('programs').update(data).eq('id', id);
    }
  }

  static Future<List<DbRow>> patientPrograms(String patientId) async => await _c
      .from('patient_programs')
      .select()
      .eq('patient_id', patientId)
      .order('start_date', ascending: false);

  static Future<DbRow?> activeProgram(String patientId) async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final r = await _c
        .from('patient_programs')
        .select()
        .eq('patient_id', patientId)
        .eq('status', 'active')
        .lte('start_date', today)
        .gte('end_date', today)
        .order('end_date', ascending: false)
        .limit(1);
    return r.isEmpty ? null : r.first;
  }

  static Future<DbRow> enroll(DbRow data) async =>
      await _c.from('patient_programs').insert(data).select().single();

  static Future<void> setProgramStatus(String id, String status) =>
      _c.from('patient_programs').update({'status': status}).eq('id', id);

  // ------------------------------------------------------------ fee rule
  /// Consultation fee is charged once and covers [fee_valid_days] days or
  /// [fee_valid_visits] visits, whichever comes first. Therapy visits and
  /// patients on an active program are not charged.
  static Future<FeeCheck> consultationCheck(String patientId, {String? visitType}) async {
    if (visitType == 'therapy') return FeeCheck(false, 'Therapy visit – no consultation fee');
    final prog = await activeProgram(patientId);
    if (prog != null) {
      return FeeCheck(false, 'Included in ${prog['name']} (until ${_d(prog['end_date'])})');
    }
    final s = await settings();
    final validDays = (s['fee_valid_days'] ?? 30) as num;
    final validVisits = (s['fee_valid_visits'] ?? 4) as num;
    final last = await _c
        .from('bills')
        .select('bill_date')
        .eq('patient_id', patientId)
        .eq('consultation_charged', true)
        .neq('status', 'cancelled')
        .order('bill_date', ascending: false)
        .limit(1);
    if (last.isEmpty) return FeeCheck(true, '');
    final paidAt = DateTime.parse(last.first['bill_date'].toString()).toLocal();
    final days = DateTime.now().difference(paidAt).inDays;
    if (days >= validDays) return FeeCheck(true, '');
    final since = paidAt.toIso8601String().substring(0, 10);
    final visits = await _c
        .from('visits')
        .select('id')
        .eq('patient_id', patientId)
        .gte('visit_date', since)
        .neq('status', 'cancelled');
    if (visits.length > validVisits) return FeeCheck(true, '');
    return FeeCheck(false,
        'Covered – fee paid on ${_d(paidAt)} (visit ${visits.length} of ${validVisits.toInt()})');
  }

  static String _d(dynamic v) {
    final d = v is DateTime ? v : DateTime.tryParse(v.toString());
    if (d == null) return '';
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }

  // ------------------------------------------------------------ bills
  static const _billSelect = '*, bill_items(*), patients(*), visits(visit_type, mode, visit_date)';

  static Future<DbRow?> billForVisit(String visitId) async {
    final r = await _c
        .from('bills')
        .select(_billSelect)
        .eq('visit_id', visitId)
        .neq('status', 'cancelled')
        .limit(1);
    return r.isEmpty ? null : r.first;
  }

  static Future<DbRow> getBill(String id) async =>
      await _c.from('bills').select(_billSelect).eq('id', id).single();

  static Future<List<DbRow>> bills({required String fromIso, required String toIso, String? status}) async {
    var q = _c
        .from('bills')
        .select('id, bill_no, bill_date, total, paid_amount, payment_mode, status, patients(name, patient_code)')
        .gte('bill_date', fromIso)
        .lt('bill_date', toIso);
    if (status != null) q = q.eq('status', status);
    return await q.order('bill_date', ascending: false).limit(500);
  }

  static Future<List<DbRow>> pendingBills() async => await _c
      .from('bills')
      .select('id, bill_no, bill_date, total, paid_amount, payment_mode, status, patients(name, patient_code)')
      .inFilter('status', ['pending', 'partial'])
      .order('bill_date', ascending: false)
      .limit(500);

  static Future<List<DbRow>> patientBills(String patientId) async => await _c
      .from('bills')
      .select('id, bill_no, bill_date, total, paid_amount, status')
      .eq('patient_id', patientId)
      .neq('status', 'cancelled')
      .order('bill_date', ascending: false);

  /// Saves the bill and replaces its items. Returns the saved bill id.
  static Future<String> saveBill(DbRow bill, List<DbRow> items, {String? id}) async {
    String billId;
    if (id == null) {
      bill['branch_id'] = currentBranchId;
      final r = await _c.from('bills').insert(bill).select('id').single();
      billId = r['id'];
    } else {
      await _c.from('bills').update(bill).eq('id', id);
      await _c.from('bill_items').delete().eq('bill_id', id);
      billId = id;
    }
    if (items.isNotEmpty) {
      await _c.from('bill_items').insert([
        for (var i = 0; i < items.length; i++)
          {
            'bill_id': billId,
            'sort': i,
            'kind': items[i]['kind'],
            'description': items[i]['description'],
            'detail': items[i]['detail'],
            'qty': items[i]['qty'],
            'rate': items[i]['rate'],
            'amount': items[i]['amount'],
          }
      ]);
    }
    return billId;
  }

  static Future<void> cancelBill(String id) =>
      _c.from('bills').update({'status': 'cancelled'}).eq('id', id);

  static Future<String?> nextVisit(String visitId) async {
    final r = await _c.from('consultations').select('next_visit').eq('visit_id', visitId).maybeSingle();
    return r?['next_visit']?.toString();
  }
}
