import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'screens/shell.dart';
import 'screens/welcome_screen.dart';
import 'services/api.dart';
import 'theme.dart';
import 'widgets/common.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (isConfigured) {
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  }
  runApp(const MeloriaPatientApp());
}

class MeloriaPatientApp extends StatelessWidget {
  const MeloriaPatientApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: appName,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: isConfigured
            ? const AuthGate()
            : const Scaffold(body: Center(child: Text('Add Supabase keys in lib/config.dart'))),
      );
}

/// Signed out → Welcome. Signed in → load account → app (or finish profile).
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) => StreamBuilder<AuthState>(
        stream: Supabase.instance.client.auth.onAuthStateChange,
        builder: (context, _) {
          final session = Supabase.instance.client.auth.currentSession;
          if (session == null) {
            AppState.me.value = null;
            return const WelcomeScreen();
          }
          return const _Loader();
        },
      );
}

class _Loader extends StatefulWidget {
  const _Loader();
  @override
  State<_Loader> createState() => _LoaderState();
}

class _LoaderState extends State<_Loader> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      await AppState.refresh();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _error = niceError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const BrandMark(size: 48),
              const SizedBox(height: 24),
              Text('Could not connect. Please check your internet.\n$_error', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: _load, child: const Text('Try again')),
              TextButton(onPressed: Api.signOut, child: const Text('Sign out')),
            ]),
          ),
        ),
      );
    }
    return ValueListenableBuilder(
      valueListenable: AppState.me,
      builder: (_, me, __) {
        if (me == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        if (AppState.account == null) return const CompleteProfileScreen();
        return const Shell();
      },
    );
  }
}
