import 'package:flutter/material.dart';

import '../services/api.dart';
import '../services/trackers.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'book_screen.dart';
import 'program_screen.dart';
import 'shell.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<DbRow> _programs = [];
  DbRow? _next;
  List<DbRow> _trackers = [];

  @override
  void initState() {
    super.initState();
    AppState.selected.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    AppState.selected.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final progs = await Api.programs();
      DbRow? next;
      List<DbRow> trackers = [];
      final pid = AppState.patientId;
      if (pid != null) {
        final now = DateTime.now();
        final upcoming = (await Api.appointments(pid)).where((a) {
          final d = DateTime.parse('${a['appt_date']} ${a['start_time']}');
          return d.isAfter(now) && ['booked', 'pending_payment'].contains(a['status']);
        }).toList()
          ..sort((a, b) => '${a['appt_date']}${a['start_time']}'.compareTo('${b['appt_date']}${b['start_time']}'));
        next = upcoming.isEmpty ? null : upcoming.first;
        trackers = await Api.trackers(pid);
      }
      if (mounted) {
        setState(() {
          _programs = progs;
          _next = next;
          _trackers = trackers;
        });
      }
    } catch (_) {}
  }

  Future<void> _book(String mode) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => BookScreen(mode: mode)));
    _load();
  }

  String get _greeting {
    final h = DateTime.now().hour;
    return h < 12 ? 'Good morning' : (h < 17 ? 'Good afternoon' : 'Good evening');
  }

  @override
  Widget build(BuildContext context) {
    final name = str(AppState.account?['full_name']).split(' ').first;
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await AppState.refresh();
            await _load();
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 30),
            children: [
              Row(children: [
                Image.asset('assets/images/logo_symbol.png', height: 34),
                const Spacer(),
                if (AppState.patients.length > 1) _familySwitcher(),
              ]),
              const SizedBox(height: 18),
              Text(_greeting.toUpperCase(), style: eyebrow()),
              const SizedBox(height: 2),
              Text(name, style: serif(36)),
              if (!AppState.confirmed) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Brand.goldLight, borderRadius: BorderRadius.circular(16)),
                  child: const Row(children: [
                    Icon(Icons.hourglass_top_rounded, color: Brand.gold, size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'You can book now. Your clinic records will appear once our team confirms your account.',
                        style: TextStyle(fontSize: 12.5, height: 1.45),
                      ),
                    ),
                  ]),
                ),
              ],
              const SizedBox(height: 22),
              const Text('Book a consultation', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Row(children: [
                _modeCard('offline', 'In clinic', 'Tirunelveli', Brand.slate, Icons.local_hospital_outlined),
                const SizedBox(width: 10),
                _modeCard('video', 'Video', 'Google Meet', Brand.teal, Icons.videocam_outlined),
                const SizedBox(width: 10),
                _modeCard('phone', 'Phone', 'We call you', Brand.sageDark, Icons.call_outlined),
              ]),
              if (_next != null) ...[
                const SizedBox(height: 16),
                SoftCard(
                  onTap: () => Shell.tab.value = 1,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                  child: Row(children: [
                    Column(children: [
                      Text(fmtDate(_next!['appt_date'], 'MMM').toUpperCase(), style: eyebrow(size: 9.5)),
                      Text(fmtDate(_next!['appt_date'], 'd'), style: serif(32, weight: FontWeight.w700)),
                    ]),
                    Container(width: 1, height: 44, color: Brand.line, margin: const EdgeInsets.symmetric(horizontal: 16)),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('NEXT APPOINTMENT', style: eyebrow(size: 9.5)),
                        const SizedBox(height: 3),
                        Text('${fmtDate(_next!['appt_date'], 'EEEE')} · ${fmtClock(_next!['start_time'])}',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15.5)),
                        Text(
                            '${ApptStyle.types[_next!['appt_type']]} · ${ApptStyle.modes[_next!['mode']]}'
                            '${_next!['status'] == 'pending_payment' ? ' · awaiting payment' : ''}',
                            style: const TextStyle(color: Brand.muted, fontSize: 12.5)),
                      ]),
                    ),
                    const Icon(Icons.arrow_forward, color: Brand.muted),
                  ]),
                ),
              ],
              const SizedBox(height: 26),
              const Text('Reversal programs', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              SizedBox(
                height: 158,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  itemCount: _programs.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (_, i) => ProgramCard(program: _programs[i]),
                ),
              ),
              if (_trackers.isNotEmpty) ...[
                const SizedBox(height: 26),
                const Text('Today', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                SoftCard(
                  onTap: () => Shell.tab.value = 2,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  child: Column(children: _todayTasks()),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _todayTasks() {
    final rows = <Widget>[];
    for (final t in _trackers) {
      final def = Trackers.def(str(t['kind']));
      final times = ((t['reminder_times'] as List?) ?? []).map((e) => e.toString()).toList();
      final label = str(t['label']).isNotEmpty ? str(t['label']) : def.label;
      for (final tm in times.isEmpty ? [''] : times) {
        rows.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            Icon(def.icon, size: 20, color: def.color),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
            if (tm.isNotEmpty) Text(fmtClock(tm), style: const TextStyle(color: Brand.muted, fontSize: 12.5)),
          ]),
        ));
      }
    }
    return rows;
  }

  Widget _modeCard(String mode, String title, String sub, Color c, IconData icon) => Expanded(
        child: SoftCard(
          onTap: () => _book(mode),
          padding: const EdgeInsets.fromLTRB(6, 18, 6, 16),
          child: Column(children: [
            CircleAvatar(radius: 25, backgroundColor: c, child: Icon(icon, color: Colors.white, size: 24)),
            const SizedBox(height: 10),
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(sub, style: const TextStyle(fontSize: 11, color: Brand.muted)),
          ]),
        ),
      );

  Widget _familySwitcher() => PopupMenuButton<String>(
        onSelected: (id) => AppState.selected.value = id,
        itemBuilder: (_) => AppState.patients
            .map((p) => PopupMenuItem(value: p['id'] as String, child: Text(str(p['name']))))
            .toList(),
        child: Chip(
          avatar: const Icon(Icons.people_outline, size: 18),
          label: Text(str(AppState.patient?['name']).split(' ').first),
        ),
      );
}

/// Deep-toned program card used on Home and the programs list.
class ProgramCard extends StatelessWidget {
  const ProgramCard({super.key, required this.program, this.width = 210});
  final DbRow program;
  final double width;

  static Color colorOf(DbRow p) {
    final hex = str(p['color']).replaceAll('#', '');
    return hex.length == 6 ? Color(int.parse('FF$hex', radix: 16)) : Brand.deepTeal;
  }

  /// Lowest monthly price across the plans (the 12-month plan).
  static num? fromMonthly(DbRow p) {
    final plans = (p['plans'] as List?) ?? [];
    num? best;
    for (final pl in plans) {
      final m = (pl['price'] as num) / (pl['months'] as num);
      if (best == null || m < best) best = m;
    }
    return best?.round();
  }

  static String shortName(DbRow p) =>
      str(p['name']).replaceAll(' Remission Program', '').replaceAll(' Program', '');

  @override
  Widget build(BuildContext context) {
    final c = colorOf(program);
    final from = fromMonthly(program);
    final isRemission = str(program['name']).contains('Remission');
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProgramScreen(program: program))),
      child: Container(
        width: width,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [c, Color.lerp(c, Colors.black, 0.35)!]),
        ),
        child: Stack(children: [
          Positioned(
            right: -48,
            top: -48,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                  shape: BoxShape.circle, border: Border.all(color: Colors.white.withValues(alpha: 0.16))),
            ),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(isRemission ? 'REMISSION' : 'PROGRAM', style: eyebrow(color: Colors.white70, size: 9)),
            const Spacer(),
            Text(shortName(program), style: serif(25, color: Colors.white, height: 1.0)),
            const GoldRule(width: 24),
            if (from != null)
              Text('From ${rupees(from)} / month',
                  style: const TextStyle(color: Colors.white, fontSize: 11.5, letterSpacing: 0.3)),
          ]),
        ]),
      ),
    );
  }
}
