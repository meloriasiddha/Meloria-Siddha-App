import 'package:flutter/material.dart';

import '../services/api.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'book_screen.dart';
import 'home_screen.dart';

/// A reversal program: how it works, plans (1 → 12 months), Join.
class ProgramScreen extends StatefulWidget {
  const ProgramScreen({super.key, required this.program});
  final DbRow program;

  @override
  State<ProgramScreen> createState() => _ProgramScreenState();
}

class _ProgramScreenState extends State<ProgramScreen> {
  late final List<DbRow> _plans = ((widget.program['plans'] as List?) ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList()
    ..sort((a, b) => (a['months'] as num).compareTo(b['months'] as num));
  int? _months;
  bool _busy = false;

  num get _monthlyBase {
    final one = _plans.where((p) => p['months'] == 1);
    return one.isEmpty ? 0 : one.first['price'] as num;
  }

  Future<void> _join() async {
    if (_months == null) {
      showMsg(context, 'Choose a plan first', error: true);
      return;
    }
    final pid = AppState.patientId;
    if (pid == null) return;
    setState(() => _busy = true);
    try {
      final visits = AppState.confirmed ? await Api.visits(pid) : <DbRow>[];
      if (!mounted) return;
      final label = '${widget.program['name']} – $_months month${_months == 1 ? '' : 's'}';
      if (visits.isEmpty) {
        // New patient: first consultation, with the program noted on the booking.
        final go = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Start with a consultation', style: serif(26)),
            content: const Text(
                'Your program begins with a detailed first consultation, so the doctor can plan it for you. '
                'Book your consultation now – your chosen plan will be noted.',
                style: TextStyle(height: 1.5)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Later')),
              FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('BOOK NOW')),
            ],
          ),
        );
        if (go == true && mounted) {
          await Navigator.push(
              context, MaterialPageRoute(builder: (_) => BookScreen(mode: 'offline', program: label)));
        }
      } else {
        await Api.joinProgram(pid, widget.program['id'], _months!);
        if (!mounted) return;
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Request sent', style: serif(26)),
            content: Text('Thank you. The doctor will review your request for $label and the clinic will contact you to begin.',
                style: const TextStyle(height: 1.5)),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
          ),
        );
      }
    } catch (e) {
      if (mounted) showMsg(context, niceError(e), error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.program;
    final c = ProgramCard.colorOf(p);
    final dark = Color.lerp(c, Colors.black, 0.35)!;
    final from = ProgramCard.fromMonthly(p);
    final steps = ((p['steps'] as List?) ?? []).map((e) => e.toString()).toList();
    final nameParts = str(p['name']).replaceAll(' Program', '');

    return Scaffold(
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 14),
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: dark),
            onPressed: _busy ? null : _join,
            child: Text(_busy ? 'PLEASE WAIT…' : 'JOIN PROGRAM'),
          ),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [c, dark])),
            padding: EdgeInsets.fromLTRB(22, MediaQuery.of(context).padding.top + 6, 22, 26),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              IconButton(
                  padding: EdgeInsets.zero,
                  alignment: Alignment.centerLeft,
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20)),
              const SizedBox(height: 10),
              Text('REVERSAL PROGRAM', style: eyebrow(color: Colors.white70)),
              const SizedBox(height: 6),
              Text(nameParts, style: serif(38, color: Colors.white, height: 1.0)),
              const GoldRule(width: 32),
              Text(str(p['subtitle']),
                  style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.55)),
              if (from != null) ...[
                const SizedBox(height: 14),
                Text.rich(TextSpan(style: const TextStyle(color: Colors.white, fontSize: 13.5), children: [
                  const TextSpan(text: 'Starting from  '),
                  TextSpan(text: rupees(from), style: serif(26, color: Colors.white, weight: FontWeight.w700)),
                  const TextSpan(text: ' / month'),
                ])),
              ],
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (str(p['who_for']).isNotEmpty) ...[
                Text('WHO IT IS FOR', style: eyebrow()),
                const SizedBox(height: 8),
                Text(str(p['who_for']), style: const TextStyle(height: 1.55, fontSize: 13.5)),
                const SizedBox(height: 22),
              ],
              Text('HOW IT WORKS', style: eyebrow()),
              const SizedBox(height: 8),
              for (var i = 0; i < steps.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 24, child: Text('${i + 1}', style: serif(18, color: Brand.gold, weight: FontWeight.w700))),
                    Expanded(child: Text(steps[i], style: const TextStyle(fontSize: 13.5, height: 1.45))),
                  ]),
                ),
              if (str(p['includes']).isNotEmpty) ...[
                const SizedBox(height: 18),
                Text('WHAT YOU GET', style: eyebrow()),
                const SizedBox(height: 8),
                Text(str(p['includes']), style: const TextStyle(height: 1.55, fontSize: 13.5)),
              ],
              const SizedBox(height: 26),
              Text('CHOOSE YOUR PLAN', style: eyebrow()),
              const SizedBox(height: 18),
              ..._plans.map(_planCard),
              const SizedBox(height: 6),
              const Text(
                'Please continue any medicines prescribed by your doctor. Changes are made only after review. '
                'Individual results vary.',
                style: TextStyle(color: Brand.muted, fontSize: 11, height: 1.5),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _planCard(DbRow pl) {
    final months = (pl['months'] as num).toInt();
    final price = pl['price'] as num;
    final rec = pl['recommended'] == true;
    final full = _monthlyBase * months;
    final save = full - price;
    final perMonth = (price / months).round();
    final sel = _months == months;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GestureDetector(
        onTap: () => setState(() => _months = months),
        child: Stack(clipBehavior: Clip.none, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
            decoration: BoxDecoration(
              color: rec ? const Color(0xFFFFFDF8) : Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                  color: sel ? Brand.slate : (rec ? Brand.gold : Brand.line), width: sel || rec ? 1.6 : 1),
              boxShadow: sel ? softShadow : null,
            ),
            child: Row(children: [
              Icon(sel ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: sel ? Brand.slate : Brand.line, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('$months month${months == 1 ? '' : 's'}',
                      style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
                  if (months > 1)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                          '${rupees(perMonth)}/month${save > 0 ? ' · save ${rupees(save)}' : ''}',
                          style: TextStyle(
                              fontSize: 11.5, fontWeight: FontWeight.w600, color: rec ? Brand.gold : Brand.sageDark)),
                    ),
                  if (str(pl['note']).isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(str(pl['note']), style: const TextStyle(fontSize: 11, color: Brand.muted)),
                    ),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                if (save > 0)
                  Text(rupees(full),
                      style: const TextStyle(
                          fontSize: 11.5, color: Brand.muted, decoration: TextDecoration.lineThrough)),
                Text(rupees(price), style: serif(26, weight: FontWeight.w700)),
              ]),
            ]),
          ),
          if (rec)
            Positioned(
              top: -11,
              left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(color: Brand.gold, borderRadius: BorderRadius.circular(20)),
                child: const Text('RECOMMENDED',
                    style: TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w700, letterSpacing: 1.6)),
              ),
            ),
        ]),
      ),
    );
  }
}
