import 'package:flutter/material.dart';

import '../services/db.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'medicine_form_screen.dart';

/// Medicine stock with low-stock and expiry alerts.
class StockScreen extends StatefulWidget {
  const StockScreen({super.key});

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  List<DbRow> _meds = [];
  bool _loading = true;
  String _filter = 'all';
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final m = await Db.medicines();
      if (mounted) setState(() => _meds = m);
    } catch (e) {
      if (mounted) showMsg(context, 'Could not load stock: $e', error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  static num stockOf(DbRow m) =>
      ((m['medicine_batches'] as List?) ?? []).fold<num>(0, (s, b) => s + (b['quantity'] ?? 0));

  /// True if any batch with stock expires within 60 days (or has expired).
  static bool expiringSoon(DbRow m) {
    final limit = DateTime.now().add(const Duration(days: 60));
    return ((m['medicine_batches'] as List?) ?? []).any((b) {
      final e = DateTime.tryParse(str(b['expiry_date']));
      return e != null && (b['quantity'] ?? 0) > 0 && e.isBefore(limit);
    });
  }

  static bool isLow(DbRow m) => stockOf(m) <= (m['low_stock_alert'] ?? 10);

  Future<void> _open([DbRow? m]) async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => MedicineFormScreen(medicineId: m?['id'])));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final lowCount = _meds.where(isLow).length;
    final expCount = _meds.where(expiringSoon).length;
    final list = _meds.where((m) {
      if (_q.isNotEmpty && !str(m['name']).toLowerCase().contains(_q.toLowerCase())) return false;
      if (_filter == 'low') return isLow(m);
      if (_filter == 'exp') return expiringSoon(m);
      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Medicine stock')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'med',
        onPressed: () => _open(),
        icon: const Icon(Icons.add),
        label: const Text('Medicine'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => _q = v),
              decoration: const InputDecoration(
                  hintText: 'Search medicine', prefixIcon: Icon(Icons.search)),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                ChoiceChip(
                    label: Text('All (${_meds.length})'),
                    selected: _filter == 'all',
                    onSelected: (_) => setState(() => _filter = 'all')),
                const SizedBox(width: 8),
                ChoiceChip(
                    label: Text('Low stock ($lowCount)'),
                    selected: _filter == 'low',
                    onSelected: (_) => setState(() => _filter = 'low')),
                const SizedBox(width: 8),
                ChoiceChip(
                    label: Text('Expiring ($expCount)'),
                    selected: _filter == 'exp',
                    onSelected: (_) => setState(() => _filter = 'exp')),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : list.isEmpty
                    ? const EmptyState(Icons.inventory_2_outlined, 'No medicines here yet.')
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                          itemCount: list.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            final m = list[i];
                            return Card(
                              child: ListTile(
                                contentPadding:
                                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                leading: const CircleAvatar(
                                  backgroundColor: Color(0x3388A99A),
                                  child: Icon(Icons.medication_outlined, color: Brand.slate),
                                ),
                                title: Text(str(m['name']),
                                    style: const TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: Text(
                                    '${str(m['form'])}${str(m['form']).isEmpty ? '' : ' · '}₹${m['price'] ?? 0}/${str(m['unit'])}'),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text('${stockOf(m)} ${str(m['unit'])}',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: isLow(m) ? Brand.danger : Brand.slate)),
                                    if (expiringSoon(m))
                                      const Text('Expiring',
                                          style: TextStyle(fontSize: 11, color: Brand.warning)),
                                  ],
                                ),
                                onTap: () => _open(m),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
