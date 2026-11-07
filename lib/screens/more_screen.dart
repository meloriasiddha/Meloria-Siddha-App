import 'package:flutter/material.dart';

import '../config.dart';
import '../services/db.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'home_screen.dart';
import 'stock_screen.dart';
import 'bills_screen.dart';

/// More: treatment advice list, account, sign out.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.all(14),
              leading: PatientAvatar(Session.name, radius: 24),
              title: Text(Session.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(Session.isDoctor ? 'Doctor' : 'Staff'),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: Column(children: [
              ListTile(
                leading: const Icon(Icons.receipt_long_outlined, color: Brand.slate),
                title: const Text('Bills & collection'),
                subtitle: const Text('Today, this week, payment due'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const BillsScreen())),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.workspace_premium_outlined, color: Color(0xFF2F7480)),
                title: const Text('Programs & packages'),
                subtitle: const Text('Diabetes, PCOD, weight loss – price and length'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const ProgramsScreen())),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.inventory_2_outlined, color: Brand.teal),
                title: const Text('Medicine stock'),
                subtitle: const Text('Medicines, batches, expiry and low-stock alerts'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const StockScreen())),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.spa_outlined, color: Brand.sageDark),
                title: const Text('Treatment advice list'),
                subtitle: const Text('Varmam, thokkanam and other therapies'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const AdviceListScreen())),
              ),
            ]),
          ),
          if (Session.isDoctor) ...[
            const SizedBox(height: 14),
            Card(
              child: ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text('Billing settings'),
                subtitle: const Text('Consultation fee rule, GST'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const BillingSettingsScreen())),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Card(
            child: ListTile(
              leading: const Icon(Icons.logout, color: Brand.danger),
              title: const Text('Sign out'),
              onTap: Db.signOut,
            ),
          ),
          const SizedBox(height: 40),
          const Center(child: BrandMark(size: 44)),
          const SizedBox(height: 8),
          const Center(
              child: Text('$appName · v1.2',
                  style: TextStyle(color: Brand.muted, fontSize: 12))),
        ],
      ),
    );
  }
}

/// Feedable list of treatments the doctor can advise.
class AdviceListScreen extends StatefulWidget {
  const AdviceListScreen({super.key});

  @override
  State<AdviceListScreen> createState() => _AdviceListScreenState();
}

class _AdviceListScreenState extends State<AdviceListScreen> {
  List<DbRow> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await Db.adviceItems();
    if (mounted) setState(() => _items = r);
  }

  Future<void> _edit([DbRow? a]) async {
    final name = TextEditingController(text: str(a?['name']));
    final desc = TextEditingController(text: str(a?['description']));
    final charge = TextEditingController(text: str(a?['charge']));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(a == null ? 'Add treatment' : 'Edit treatment'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Field('Name', name),
            Field('Description', desc, maxLines: 2),
            Field('Charge per session', charge,
                keyboard: const TextInputType.numberWithOptions(decimal: true), suffix: '₹'),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty || !mounted) return;
    await guard(
        context,
        () => Db.saveAdviceItem({
              'name': name.text.trim(),
              'description': desc.text.trim(),
              'charge': toNum(charge.text) ?? 0,
            }, id: a?['id']));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Treatment advice list')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _edit(),
        child: const Icon(Icons.add),
      ),
      body: _items.isEmpty
          ? const EmptyState(Icons.spa_outlined, 'No treatments yet. Tap + to add.')
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
              itemCount: _items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final a = _items[i];
                return Card(
                  child: ListTile(
                    title: Text(str(a['name']), style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: str(a['description']).isEmpty ? null : Text(str(a['description'])),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('₹${a['charge'] ?? 0}'),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Brand.muted),
                        onPressed: () async {
                          await guard(context, () => Db.removeAdviceItem(a['id']));
                          _load();
                        },
                      ),
                    ]),
                    onTap: () => _edit(a),
                  ),
                );
              },
            ),
    );
  }
}
