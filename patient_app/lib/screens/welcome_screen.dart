import 'package:flutter/material.dart';

import '../services/api.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Sign in (phone + PIN) or create an account (name, phone, date of birth, PIN).
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool _signUp = true;
  bool _busy = false;
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _pin = TextEditingController();
  final _pin2 = TextEditingController();
  DateTime? _dob;

  int? get _age {
    if (_dob == null) return null;
    final now = DateTime.now();
    var a = now.year - _dob!.year;
    if (now.month < _dob!.month || (now.month == _dob!.month && now.day < _dob!.day)) a--;
    return a;
  }

  Future<void> _pickDob() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(1985, 1, 1),
      firstDate: DateTime(1920),
      lastDate: DateTime.now(),
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      helpText: 'Date of birth',
    );
    if (d != null) setState(() => _dob = d);
  }

  bool _validPhone() => Api.phoneDigits(_phone.text).length == 10;
  bool _validPin(String p) => RegExp(r'^\d{6}$').hasMatch(p);

  Future<void> _submit() async {
    if (!_validPhone()) return showMsg(context, 'Enter your 10-digit mobile number', error: true);
    if (!_validPin(_pin.text)) return showMsg(context, 'PIN must be 6 digits', error: true);
    if (_signUp) {
      if (_name.text.trim().length < 2) return showMsg(context, 'Enter your full name', error: true);
      if (_dob == null) return showMsg(context, 'Choose your date of birth', error: true);
      if (_pin.text != _pin2.text) return showMsg(context, 'PINs do not match', error: true);
    }
    setState(() => _busy = true);
    try {
      if (_signUp) {
        final signedIn = await Api.signUp(_phone.text, _pin.text);
        if (!signedIn) await Api.signIn(_phone.text, _pin.text);
        await Api.register(_name.text.trim(), _phone.text, _dob!);
        await AppState.refresh();
      } else {
        await Api.signIn(_phone.text, _pin.text);
      }
    } catch (e) {
      final s = e.toString().toLowerCase();
      final msg = s.contains('already registered') || s.contains('already been registered')
          ? 'This number already has an account. Please sign in.'
          : (s.contains('invalid login') ? 'Wrong mobile number or PIN.' : niceError(e));
      if (mounted) showMsg(context, msg, error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _forgotPin() async {
    final phone = TextEditingController(text: _phone.text);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Forgot PIN', style: serif(24)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Enter your mobile number. The clinic will set a temporary PIN and let you know.',
              style: TextStyle(color: Brand.muted, height: 1.5)),
          const SizedBox(height: 14),
          Field('Mobile number', phone, keyboard: TextInputType.phone),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('SEND')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await Api.requestPinReset(phone.text);
      if (mounted) showMsg(context, 'Request sent. The clinic will contact you shortly.');
    } catch (e) {
      if (mounted) showMsg(context, niceError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 30, 24, 30),
          children: [
            const BrandMark(),
            const SizedBox(height: 34),
            Text(_signUp ? 'Welcome' : 'Welcome back', style: serif(36)),
            const SizedBox(height: 6),
            Text(
              _signUp
                  ? 'Create your account to book consultations and begin your journey to better health.'
                  : 'Sign in with your mobile number and PIN.',
              style: const TextStyle(color: Brand.muted, height: 1.5),
            ),
            const SizedBox(height: 22),
            if (_signUp) ...[
              Field('Full name', _name),
            ],
            Field('Mobile number', _phone, keyboard: TextInputType.phone, hint: '98765 43210'),
            if (_signUp) ...[
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: _pickDob,
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Date of birth',
                    suffixIcon: _age == null
                        ? const Icon(Icons.cake_outlined, color: Brand.muted)
                        : Padding(
                            padding: const EdgeInsets.all(10),
                            child: Pill('Age $_age', color: Brand.gold),
                          ),
                  ),
                  child: Text(_dob == null ? 'Tap to choose' : fmtDate(_dob, 'd MMMM yyyy'),
                      style: TextStyle(color: _dob == null ? Brand.muted : Brand.ink, fontSize: 15)),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Field(_signUp ? 'Create a 6-digit PIN' : 'PIN', _pin,
                keyboard: TextInputType.number, obscure: true),
            if (_signUp) Field('Confirm PIN', _pin2, keyboard: TextInputType.number, obscure: true),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(_signUp ? 'CREATE ACCOUNT' : 'SIGN IN'),
            ),
            const SizedBox(height: 14),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(_signUp ? 'Already registered?' : 'New to Meloria?',
                  style: const TextStyle(color: Brand.muted)),
              TextButton(
                onPressed: () => setState(() => _signUp = !_signUp),
                child: Text(_signUp ? 'Sign in' : 'Create account',
                    style: const TextStyle(fontWeight: FontWeight.w700, color: Brand.slate)),
              ),
            ]),
            if (!_signUp)
              Center(
                  child: TextButton(
                      onPressed: _forgotPin,
                      child: const Text('Forgot PIN?', style: TextStyle(color: Brand.muted)))),
            const SizedBox(height: 18),
            const Text(
              'Visited Meloria before? Your clinic records appear once our team confirms your account.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Brand.muted, fontSize: 11.5, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown if someone signed in but their profile was not saved (e.g. connection dropped).
class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({super.key});
  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _name = TextEditingController();
  DateTime? _dob;
  bool _busy = false;

  Future<void> _save() async {
    if (_name.text.trim().length < 2 || _dob == null) {
      return showMsg(context, 'Enter your name and date of birth', error: true);
    }
    setState(() => _busy = true);
    try {
      final email = str(Api.currentEmail);
      await Api.register(_name.text.trim(), email.split('@').first, _dob!);
      await AppState.refresh();
    } catch (e) {
      if (mounted) showMsg(context, niceError(e), error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(24), children: [
            const SizedBox(height: 20),
            const BrandMark(size: 48),
            const SizedBox(height: 30),
            Text('Almost there', style: serif(34)),
            const SizedBox(height: 18),
            Field('Full name', _name),
            OutlinedButton.icon(
              icon: const Icon(Icons.cake_outlined),
              label: Text(_dob == null ? 'Date of birth' : fmtDate(_dob, 'd MMMM yyyy')),
              onPressed: () async {
                final d = await showDatePicker(
                    context: context,
                    initialDate: DateTime(1985),
                    firstDate: DateTime(1920),
                    lastDate: DateTime.now());
                if (d != null) setState(() => _dob = d);
              },
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: _busy ? null : _save, child: const Text('CONTINUE')),
            TextButton(onPressed: Api.signOut, child: const Text('Sign out')),
          ]),
        ),
      );
}

