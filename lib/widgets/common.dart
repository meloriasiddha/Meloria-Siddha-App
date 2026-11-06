import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../theme.dart';

/// Logo symbol + MELORIA wordmark + "Siddha Hospital" (used inside the app).
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 72, this.showText = true});
  final double size;
  final bool showText;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset('assets/images/logo_symbol.png', height: size),
        if (showText) ...[
          SizedBox(height: size * 0.22),
          Text(
            'MELORI\u039B', // Λ matches the logo's A
            style: GoogleFonts.montserrat(
              fontSize: size * 0.34,
              fontWeight: FontWeight.w500,
              letterSpacing: size * 0.12,
              color: Brand.slate,
            ),
          ),
          Text('Siddha Hospital', style: serifStyle(size: size * 0.24)),
        ],
      ],
    );
  }
}

/// White rounded card with an optional title.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, this.title, this.trailing, required this.child, this.padding});
  final String? title;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: padding ?? const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(title!,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 0.2)),
                    ),
                    if (trailing != null) trailing!,
                  ],
                ),
              ),
            child,
          ],
        ),
      ),
    );
  }
}

/// Small coloured label, e.g. status or allergy tags.
class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.color = Brand.sageDark});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text,
          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

/// Text field with label; keeps forms short to write.
class Field extends StatelessWidget {
  const Field(this.label, this.controller,
      {super.key,
      this.keyboard,
      this.maxLines = 1,
      this.required = false,
      this.hint,
      this.suffix});
  final String label;
  final TextEditingController controller;
  final TextInputType? keyboard;
  final int maxLines;
  final bool required;
  final String? hint;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboard,
        maxLines: maxLines,
        minLines: 1,
        textCapitalization:
            keyboard == null ? TextCapitalization.sentences : TextCapitalization.none,
        decoration: InputDecoration(labelText: label, hintText: hint, suffixText: suffix),
        validator: required
            ? (v) => (v == null || v.trim().isEmpty) ? '$label is required' : null
            : null,
      ),
    );
  }
}

/// Initials avatar in brand colours.
class PatientAvatar extends StatelessWidget {
  const PatientAvatar(this.name, {super.key, this.radius = 22});
  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final parts = name.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    final initials = parts.isEmpty
        ? '?'
        : (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
    return CircleAvatar(
      radius: radius,
      backgroundColor: Brand.sage.withValues(alpha: 0.25),
      child: Text(initials,
          style: TextStyle(
              color: Brand.slate, fontWeight: FontWeight.w600, fontSize: radius * 0.7)),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState(this.icon, this.message, {super.key});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Brand.sage),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Brand.muted)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- helpers
final _date = DateFormat('d MMM yyyy');
final _time = DateFormat('h:mm a');

String fmtDate(dynamic v) {
  if (v == null) return '';
  final d = v is DateTime ? v : DateTime.tryParse(v.toString());
  return d == null ? '' : _date.format(d.toLocal());
}

String fmtTime(dynamic v) {
  if (v == null) return '';
  final d = DateTime.tryParse(v.toString());
  return d == null ? '' : _time.format(d.toLocal());
}

String isoDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

num? toNum(String s) => s.trim().isEmpty ? null : num.tryParse(s.trim());
int? toInt(String s) => s.trim().isEmpty ? null : int.tryParse(s.trim());

String str(dynamic v) => v == null ? '' : v.toString();

void showMsg(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg),
    backgroundColor: error ? Brand.danger : Brand.slate,
    behavior: SnackBarBehavior.floating,
  ));
}

/// Runs an async action and shows a friendly error if it fails.
Future<bool> guard(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
    return true;
  } catch (e) {
    if (context.mounted) showMsg(context, 'Something went wrong: $e', error: true);
    return false;
  }
}
