import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../theme.dart';

/// White rounded card with the soft Meloria shadow.
class SoftCard extends StatelessWidget {
  const SoftCard({super.key, required this.child, this.padding = const EdgeInsets.all(18), this.onTap, this.color});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          color: color ?? Colors.white, borderRadius: BorderRadius.circular(22), boxShadow: softShadow),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Logo symbol + MELORIΛ + "Siddha Hospital".
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 58});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Image.asset('assets/images/logo_symbol.png', height: size),
      SizedBox(height: size * 0.24),
      Padding(
        padding: EdgeInsets.only(left: size * 0.17),
        child: Text('MELORIΛ',
            style: GoogleFonts.montserrat(
                fontSize: size * 0.38, fontWeight: FontWeight.w400, letterSpacing: size * 0.17, color: Brand.ink)),
      ),
      Text('Siddha Hospital', style: serif(size * 0.31, color: Brand.teal)),
    ]);
  }
}

/// Thin gold line used as an accent under titles.
class GoldRule extends StatelessWidget {
  const GoldRule({super.key, this.width = 28});
  final double width;
  @override
  Widget build(BuildContext context) =>
      Container(width: width, height: 1.2, color: Brand.gold, margin: const EdgeInsets.symmetric(vertical: 12));
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color = Brand.sageDark, this.filled = false});
  final String text;
  final Color color;
  final bool filled;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: filled ? color : color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Text(text.toUpperCase(),
            style: TextStyle(
                color: filled ? Colors.white : color, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState(this.icon, this.message, {super.key});
  final IconData icon;
  final String message;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(36),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 44, color: Brand.gold),
            const SizedBox(height: 14),
            Text(message,
                textAlign: TextAlign.center, style: const TextStyle(color: Brand.muted, height: 1.5)),
          ]),
        ),
      );
}

/// Simple labelled text field (used by the shared tracker entry form).
class Field extends StatelessWidget {
  const Field(this.label, this.controller,
      {super.key, this.keyboard, this.maxLines = 1, this.hint, this.suffix, this.obscure = false});
  final String label;
  final TextEditingController controller;
  final TextInputType? keyboard;
  final int maxLines;
  final String? hint;
  final String? suffix;
  final bool obscure;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: controller,
          keyboardType: keyboard,
          maxLines: obscure ? 1 : maxLines,
          minLines: 1,
          obscureText: obscure,
          textCapitalization: keyboard == null ? TextCapitalization.sentences : TextCapitalization.none,
          decoration: InputDecoration(labelText: label, hintText: hint, suffixText: suffix),
        ),
      );
}

// ---------------------------------------------------------------- helpers
String str(dynamic v) => v == null ? '' : v.toString();
num? toNum(String s) => s.trim().isEmpty ? null : num.tryParse(s.trim());
int? toInt(String s) => s.trim().isEmpty ? null : int.tryParse(s.trim());
String isoDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

String fmtDate(dynamic v, [String pattern = 'd MMM yyyy']) {
  if (v == null) return '';
  final d = v is DateTime ? v : DateTime.tryParse(v.toString());
  return d == null ? '' : DateFormat(pattern).format(d.toLocal());
}

String fmtTime(dynamic v) {
  final d = DateTime.tryParse(str(v));
  return d == null ? '' : DateFormat('h:mm a').format(d.toLocal());
}

/// "18:30:00" → "6:30 PM"
String fmtClock(dynamic hhmm) {
  final p = str(hhmm).split(':');
  if (p.length < 2) return '';
  final h = int.parse(p[0]), m = int.parse(p[1]);
  final ap = h >= 12 ? 'PM' : 'AM';
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:${m.toString().padLeft(2, '0')} $ap';
}

final _money = NumberFormat('#,##,##0', 'en_IN');
String rupees(num v) => '₹${_money.format(v)}';

void showMsg(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg),
    backgroundColor: error ? Brand.danger : Brand.slate,
    behavior: SnackBarBehavior.floating,
  ));
}

/// Shows the database's own message (e.g. "slot was just taken") when there is one.
String niceError(Object e) {
  final s = e.toString();
  final m = RegExp(r'message: ([^,}]+)').firstMatch(s);
  return m != null ? m.group(1)!.trim() : s.replaceAll('Exception: ', '');
}
