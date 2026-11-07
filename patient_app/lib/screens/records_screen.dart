import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../services/api.dart';
import '../services/bill_pdf.dart';
import '../theme.dart';
import '../widgets/common.dart';

const _visitTypes = {
  'first': 'Initial consultation',
  'review': 'Review',
  'therapy': 'Therapy',
  'program': 'Program visit',
};

/// Visits, medicines and bills – shown once the clinic has confirmed the account.
class RecordsScreen extends StatefulWidget {
  const RecordsScreen({super.key});

  @override
  State<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends State<RecordsScreen> {
  List<DbRow> _visits = [];
  List<DbRow> _bills = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    AppState.selected.addListener(_load);
    AppState.me.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    AppState.selected.removeListener(_load);
    AppState.me.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final pid = AppState.patientId;
    if (pid == null || !AppState.confirmed) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final v = await Api.visits(pid);
      final b = await Api.bills(pid);
      if (mounted) {
        setState(() {
          _visits = v;
          _bills = b;
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!AppState.confirmed) {
      return Scaffold(
        appBar: AppBar(title: const Text('Records')),
        body: const EmptyState(Icons.lock_clock_outlined,
            'Your visits, medicines and bills will appear here once our team confirms your account.'),
      );
    }
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Records'),
          bottom: const TabBar(
            labelColor: Brand.slate,
            unselectedLabelColor: Brand.muted,
            indicatorColor: Brand.gold,
            tabs: [Tab(text: 'Visits'), Tab(text: 'Medicines'), Tab(text: 'Bills')],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(children: [_visitsTab(), _medicinesTab(), _billsTab()]),
      ),
    );
  }

  // ------------------------------------------------------------ visits
  Widget _visitsTab() {
    if (_visits.isEmpty) return const EmptyState(Icons.event_note_outlined, 'No visits yet.');
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 30),
        itemCount: _visits.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) {
          final v = _visits[i];
          final complaints = ((v['complaints'] as List?) ?? []).map((c) => str(c['complaint'])).where((s) => s.isNotEmpty);
          return SoftCard(
            onTap: () => _visitDetail(v),
            child: Row(children: [
              Column(children: [
                Text(fmtDate(v['visit_date'], 'MMM').toUpperCase(), style: eyebrow(size: 9)),
                Text(fmtDate(v['visit_date'], 'd'), style: serif(28, weight: FontWeight.w700)),
              ]),
              Container(width: 1, height: 40, color: Brand.line, margin: const EdgeInsets.symmetric(horizontal: 14)),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_visitTypes[v['visit_type']] ?? 'Visit', style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(complaints.isNotEmpty ? complaints.join(', ') : str(v['main_complaint']),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Brand.muted, fontSize: 12.5)),
                ]),
              ),
              const Icon(Icons.chevron_right, color: Brand.muted),
            ]),
          );
        },
      ),
    );
  }

  void _visitDetail(DbRow v) {
    final complaints = ((v['complaints'] as List?) ?? []);
    final meds = ((v['medicines'] as List?) ?? []);
    final advice = ((v['advice'] as List?) ?? []);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Brand.ivory,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        builder: (_, sc) => ListView(controller: sc, padding: const EdgeInsets.fromLTRB(22, 20, 22, 30), children: [
          Text(fmtDate(v['visit_date'], 'EEEE, d MMMM yyyy').toUpperCase(), style: eyebrow()),
          const SizedBox(height: 4),
          Text(_visitTypes[v['visit_type']] ?? 'Visit', style: serif(30)),
          const GoldRule(),
          if (complaints.isNotEmpty) ...[
            Text('COMPLAINTS', style: eyebrow()),
            const SizedBox(height: 6),
            ...complaints.map((c) => Text(
                '• ${c['complaint']}${str(c['duration']).isEmpty ? '' : ' – ${c['duration']}'}',
                style: const TextStyle(height: 1.6))),
            const SizedBox(height: 18),
          ],
          if (meds.isNotEmpty) ...[
            Text('MEDICINES', style: eyebrow()),
            const SizedBox(height: 8),
            ...meds.map((m) => Padding(padding: const EdgeInsets.only(bottom: 10), child: _medTile(m, v['visit_date']))),
            const SizedBox(height: 8),
          ],
          if (str(v['diet_plan']).isNotEmpty) ...[
            Text('DIET PLAN', style: eyebrow()),
            const SizedBox(height: 6),
            Text(str(v['diet_plan']), style: const TextStyle(height: 1.55)),
            const SizedBox(height: 18),
          ],
          if (advice.isNotEmpty) ...[
            Text('TREATMENT ADVICE', style: eyebrow()),
            const SizedBox(height: 6),
            ...advice.map((a) => Text(
                '• ${a['name']}${(a['sessions'] ?? 1) > 1 ? ' × ${a['sessions']} sessions' : ''}${str(a['notes']).isEmpty ? '' : ' – ${a['notes']}'}',
                style: const TextStyle(height: 1.6))),
            const SizedBox(height: 18),
          ],
          if (v['next_visit'] != null)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Brand.goldLight, borderRadius: BorderRadius.circular(14)),
              child: Text('Next visit: ${fmtDate(v['next_visit'], 'EEEE, d MMMM')}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
        ]),
      ),
    );
  }

  Widget _medTile(dynamic m, dynamic visitDate) {
    final exp = DateTime.tryParse(str(m['expiry_date']));
    final start = DateTime.tryParse(str(visitDate));
    final days = (m['days'] as num?)?.toInt();
    int? left;
    if (start != null && days != null) {
      left = start.add(Duration(days: days)).difference(DateTime.now()).inDays + 1;
    }
    return SoftCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(str(m['name']), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5))),
          if (left != null && left > 0) Pill('$left days left', color: Brand.sageDark),
        ]),
        const SizedBox(height: 4),
        Text([str(m['dose']), str(m['frequency']), str(m['timing']), if (days != null) '$days days']
            .where((s) => s.isNotEmpty)
            .join(' · ')),
        if (str(m['instructions']).isNotEmpty)
          Text(str(m['instructions']), style: const TextStyle(color: Brand.muted, fontSize: 12.5)),
        if (str(m['batch_no']).isNotEmpty || exp != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
                [if (str(m['batch_no']).isNotEmpty) 'Batch ${m['batch_no']}', if (exp != null) 'Exp ${DateFormat('MM/yyyy').format(exp)}']
                    .join(' · '),
                style: const TextStyle(color: Brand.muted, fontSize: 11.5)),
          ),
      ]),
    );
  }

  // ------------------------------------------------------------ medicines
  Widget _medicinesTab() {
    final withMeds = _visits.where((v) => ((v['medicines'] as List?) ?? []).isNotEmpty).toList();
    if (withMeds.isEmpty) return const EmptyState(Icons.medication_outlined, 'No medicines yet.');
    final latest = withMeds.first;
    return ListView(padding: const EdgeInsets.fromLTRB(22, 16, 22, 30), children: [
      Text('CURRENT · FROM ${fmtDate(latest['visit_date']).toUpperCase()}', style: eyebrow()),
      const SizedBox(height: 10),
      ...((latest['medicines'] as List).map((m) => Padding(padding: const EdgeInsets.only(bottom: 10), child: _medTile(m, latest['visit_date'])))),
      if (withMeds.length > 1) ...[
        const SizedBox(height: 14),
        Text('EARLIER', style: eyebrow()),
        const SizedBox(height: 10),
        ...withMeds.skip(1).map((v) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SoftCard(
                onTap: () => _visitDetail(v),
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  Expanded(
                    child: Text(
                        '${fmtDate(v['visit_date'])} · ${(v['medicines'] as List).map((m) => m['name']).join(', ')}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ),
                  const Icon(Icons.chevron_right, color: Brand.muted),
                ]),
              ),
            )),
      ],
    ]);
  }

  // ------------------------------------------------------------ bills
  Widget _billsTab() {
    if (_bills.isEmpty) return const EmptyState(Icons.receipt_long_outlined, 'No bills yet.');
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 30),
      itemCount: _bills.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final b = _bills[i];
        final due = (b['total'] as num) - (b['paid_amount'] as num);
        return SoftCard(
          onTap: () => _openBill(b['id']),
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            const Icon(Icons.receipt_long_outlined, color: Brand.gold),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(str(b['bill_no']), style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(fmtDate(b['bill_date']), style: const TextStyle(color: Brand.muted, fontSize: 12.5)),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(rupees(b['total'] as num), style: serif(22, weight: FontWeight.w700)),
              due > 0.009 ? Pill('Due ${rupees(due)}', color: Brand.danger) : const Pill('Paid', color: Brand.sageDark),
            ]),
          ]),
        );
      },
    );
  }

  Future<void> _openBill(String id) async {
    try {
      final r = await Api.bill(id);
      final bill = Map<String, dynamic>.from(r['bill'] as Map);
      final items = ((r['items'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final v = r['visit'] as Map?;
      final bytes = await BillPdf.build(
        bill: bill,
        items: items,
        patient: Map<String, dynamic>.from((r['patient'] ?? {}) as Map),
        visitLabel: v == null ? '' : '${_visitTypes[v['visit_type']] ?? ''} · ${v['mode'] == 'online' ? 'Online' : 'In clinic'}',
        doctorName: str(r['doctor']),
        nextVisit: r['next_visit']?.toString(),
      );
      await Printing.sharePdf(bytes: bytes, filename: '${bill['bill_no']}.pdf');
    } catch (e) {
      if (mounted) showMsg(context, niceError(e), error: true);
    }
  }
}
