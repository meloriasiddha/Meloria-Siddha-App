import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme.dart';
import '../widgets/common.dart';

/// Forgot password:
/// 1. Enter email → Supabase emails a reset code.
/// 2. Enter the code + new password → password changed and signed in.
///
/// Needs the Supabase "Reset Password" email template to include {{ .Token }}
/// (see README → "Forgot password email").
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.email = ''});
  final String email;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final _email = TextEditingController(text: widget.email);
  final _code = TextEditingController();
  final _pass1 = TextEditingController();
  final _pass2 = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  bool _hide = true;

  SupabaseClient get _c => Supabase.instance.client;

  Future<void> _sendCode() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      showMsg(context, 'Enter your login email', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await _c.auth.resetPasswordForEmail(email);
      if (mounted) {
        setState(() => _codeSent = true);
        showMsg(context, 'Code sent to $email. Check inbox and spam.');
      }
    } catch (e) {
      if (mounted) showMsg(context, 'Could not send code: $e', error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _reset() async {
    if (_code.text.trim().isEmpty) {
      showMsg(context, 'Enter the code from the email', error: true);
      return;
    }
    if (_pass1.text.length < 6) {
      showMsg(context, 'Password must be at least 6 characters', error: true);
      return;
    }
    if (_pass1.text != _pass2.text) {
      showMsg(context, 'Passwords do not match', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await _c.auth.verifyOTP(
        email: _email.text.trim(),
        token: _code.text.trim(),
        type: OtpType.recovery,
      );
      await _c.auth.updateUser(UserAttributes(password: _pass1.text));
      if (!mounted) return;
      showMsg(context, 'Password changed. You are signed in.');
      Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (mounted) {
        showMsg(context, 'Code is wrong or expired. Request a new one.', error: true);
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reset password')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const BrandMark(size: 56, showText: false),
                  const SizedBox(height: 24),
                  Text(
                    _codeSent
                        ? 'Enter the code we emailed you and choose a new password.'
                        : 'Enter your login email. We will send you a code to reset your password.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Brand.muted),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _email,
                    enabled: !_codeSent,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                        labelText: 'Email', prefixIcon: Icon(Icons.mail_outline)),
                  ),
                  if (_codeSent) ...[
                    const SizedBox(height: 14),
                    TextField(
                      controller: _code,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'Code from email', prefixIcon: Icon(Icons.pin_outlined)),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _pass1,
                      obscureText: _hide,
                      decoration: InputDecoration(
                        labelText: 'New password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                              _hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _hide = !_hide),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _pass2,
                      obscureText: _hide,
                      decoration: const InputDecoration(
                          labelText: 'Confirm new password',
                          prefixIcon: Icon(Icons.lock_outline)),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : (_codeSent ? _reset : _sendCode),
                    child: Text(_busy
                        ? 'Please wait…'
                        : (_codeSent ? 'CHANGE PASSWORD' : 'SEND CODE')),
                  ),
                  if (_codeSent)
                    TextButton(
                      onPressed: _busy ? null : _sendCode,
                      child: const Text('Resend code'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
