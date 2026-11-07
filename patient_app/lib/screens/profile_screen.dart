import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/api.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Profile: patient ID with QR for quick check-in, family members, change PIN.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Future<void> _changePin() async {
    final p1 = TextEditingController();
    final p2 = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Change PIN', style: serif(26)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Field('New 6-digit PIN', p1, keyboard: TextInputType.number, obscure: true),
          Field('Confirm PIN', p2, keyboard: TextInputType.number, obscure: true),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (!RegExp(r'^\d{6}$').hasMatch(p1.text) || p1.text != p2.text) {
      showMsg(context, 'PINs must match and be 6 digits', error: true);
      return;
    }
    try {
      await Api.changePin(p1.text);
      if (mounted) showMsg(context, 'PIN changed');
    } catch (e) {
      if (mounted) showMsg(context, niceError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: AppState.me,
      builder: (_, __, ___) => ValueListenableBuilder(
        valueListenable: AppState.selected,
        builder: (_, __, ___) {
          final acc = AppState.account ?? {};
          final p = AppState.patient ?? {};
          final code = str(p['patient_code']);
          return Scaffold(
            appBar: AppBar(title: const Text('Profile')),
            body: RefreshIndicator(
              onRefresh: AppState.refresh,
              child: ListView(padding: const EdgeInsets.fromLTRB(22, 4, 22, 30), children: [
                SoftCard(
                  padding: const EdgeInsets.all(22),
                  child: Column(children: [
                    Text(str(p['name']).isEmpty ? str(acc['full_name']) : str(p['name']),
                        style: serif(30), textAlign: TextAlign.center),
                    const SizedBox(height: 4),
                    Text(
                        [
                          if (p['age'] != null) '${p['age']} years',
                          if (str(p['phone']).isNotEmpty) str(p['phone']),
                        ].join(' · '),
                        style: const TextStyle(color: Brand.muted)),
                    const GoldRule(),
                    if (code.isNotEmpty) ...[
                      Text('PATIENT ID', style: eyebrow()),
                      const SizedBox(height: 4),
                      Text(code, style: serif(28, weight: FontWeight.w700)),
                      const SizedBox(height: 14),
                      QrImageView(
                        data: code,
                        size: 150,
                        eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Brand.slate),
                        dataModuleStyle:
                            const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Brand.slate),
                      ),
                      const SizedBox(height: 6),
                      const Text('Show this at the clinic desk for quick check-in',
                          style: TextStyle(color: Brand.muted, fontSize: 11.5)),
                    ] else
                      const Text('Your patient ID will appear here once our team confirms your account.',
                          textAlign: TextAlign.center, style: TextStyle(color: Brand.muted, height: 1.5)),
                  ]),
                ),
                if (AppState.patients.length > 1) ...[
                  const SizedBox(height: 22),
                  Text('FAMILY ON THIS ACCOUNT', style: eyebrow()),
                  const SizedBox(height: 10),
                  ...AppState.patients.map((f) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: SoftCard(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          onTap: () => AppState.selected.value = f['id'],
                          child: Row(children: [
                            Icon(f['id'] == p['id'] ? Icons.radio_button_checked : Icons.radio_button_off,
                                color: Brand.slate),
                            const SizedBox(width: 12),
                            Expanded(child: Text(str(f['name']))),
                            Text(str(f['patient_code']), style: const TextStyle(color: Brand.muted)),
                          ]),
                        ),
                      )),
                ],
                const SizedBox(height: 22),
                SoftCard(
                  padding: EdgeInsets.zero,
                  child: Column(children: [
                    ListTile(
                      leading: const Icon(Icons.lock_outline, color: Brand.slate),
                      title: const Text('Change PIN'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _changePin,
                    ),
                    const Divider(),
                    const ListTile(
                      leading: Icon(Icons.call_outlined, color: Brand.slate),
                      title: Text('Call the clinic'),
                      subtitle: Text('+91 93446 98304'),
                    ),
                    const Divider(),
                    const ListTile(
                      leading: Icon(Icons.place_outlined, color: Brand.slate),
                      title: Text('Meloria Siddha and Varma Clinic'),
                      subtitle: Text('18, Thendral Nagar, St Thomas Road, Maharaja Nagar, Tirunelveli – 627011'),
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.logout, color: Brand.danger),
                      title: const Text('Sign out'),
                      onTap: Api.signOut,
                    ),
                  ]),
                ),
                const SizedBox(height: 30),
                const Center(child: BrandMark(size: 38)),
              ]),
            ),
          );
        },
      ),
    );
  }
}
