import 'package:supabase_flutter/supabase_flutter.dart';

import 'db.dart';

/// Database calls for tracking plans and the tracking chat.
class TrackDb {
  static SupabaseClient get _c => Supabase.instance.client;

  // ------------------------------------------------------------ plan
  static Future<List<DbRow>> trackers(String patientId, {bool activeOnly = true}) async {
    var q = _c.from('patient_trackers').select().eq('patient_id', patientId);
    if (activeOnly) q = q.eq('active', true);
    return await q.order('created_at');
  }

  static Future<void> saveTracker(DbRow data, {String? id}) async {
    if (id == null) {
      await _c.from('patient_trackers').insert(data);
    } else {
      await _c.from('patient_trackers').update(data).eq('id', id);
    }
  }

  static Future<void> stopTracker(String id) =>
      _c.from('patient_trackers').update({'active': false}).eq('id', id);

  // ------------------------------------------------------------ chat
  static Future<List<DbRow>> thread(String patientId, {int limit = 200}) async {
    final r = await _c
        .from('tracking_messages')
        .select()
        .eq('patient_id', patientId)
        .order('created_at', ascending: false)
        .limit(limit);
    return r.reversed.toList();
  }

  static Future<void> post(DbRow data) => _c.from('tracking_messages').insert(data);

  static Future<void> markRead(String patientId) => _c
      .from('tracking_messages')
      .update({'read_by_staff': true})
      .eq('patient_id', patientId)
      .eq('read_by_staff', false);

  /// Inbox: one row per patient with the latest message and unread count.
  /// Includes patients who have an active tracking plan but no messages yet.
  static Future<List<DbRow>> inbox() async {
    final since = DateTime.now().subtract(const Duration(days: 60)).toIso8601String();
    final msgs = await _c
        .from('tracking_messages')
        .select('patient_id, kind, entry_type, body, data, sender_type, read_by_staff, created_at, '
            'patients(id, name, patient_code, age)')
        .gte('created_at', since)
        .order('created_at', ascending: false)
        .limit(1000);
    final plans = await _c
        .from('patient_trackers')
        .select('patient_id, patients(id, name, patient_code, age)')
        .eq('active', true);

    final map = <String, DbRow>{};
    for (final m in msgs) {
      final id = m['patient_id'] as String;
      final row = map.putIfAbsent(id, () => {
            'patient': m['patients'],
            'last': m,
            'unread': 0,
          });
      if (m['sender_type'] == 'patient' && m['read_by_staff'] == false) {
        row['unread'] = (row['unread'] as int) + 1;
      }
    }
    for (final p in plans) {
      map.putIfAbsent(p['patient_id'] as String, () => {'patient': p['patients'], 'last': null, 'unread': 0});
    }
    final list = map.values.toList();
    list.sort((a, b) {
      final ua = a['unread'] as int, ub = b['unread'] as int;
      if ((ua > 0) != (ub > 0)) return ua > 0 ? -1 : 1;
      final ta = (a['last'] as Map?)?['created_at']?.toString() ?? '';
      final tb = (b['last'] as Map?)?['created_at']?.toString() ?? '';
      return tb.compareTo(ta);
    });
    return list;
  }

  static Future<int> unreadTotal() async {
    final r = await _c
        .from('tracking_messages')
        .select('id')
        .eq('sender_type', 'patient')
        .eq('read_by_staff', false);
    return r.length;
  }
}
