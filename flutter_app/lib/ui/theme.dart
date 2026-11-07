import 'package:flutter/material.dart';

const navy = Color(0xFF1B2A3A);
const navyLight = Color(0xFF2C4257);
const orange = Color(0xFFE8631C);
const yellow = Color(0xFFF2B705);
const pageBg = Color(0xFFEEF0F3);
const borderColor = Color(0xFFDBDFE6);
const textSecondary = Color(0xFF64748B);
const greenOk = Color(0xFF2E7D5B);
const redErr = Color(0xFFC0392B);

ThemeData buildTheme() => ThemeData(
      useMaterial3: true,
      fontFamily: 'NotoSansSC',
      colorScheme: ColorScheme.fromSeed(seedColor: navy, primary: navy, secondary: orange, surface: Colors.white),
      scaffoldBackgroundColor: pageBg,
      inputDecorationTheme: const InputDecorationTheme(
        isDense: true,
        border: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        labelStyle: TextStyle(fontSize: 12, color: textSecondary),
      ),
      textTheme: const TextTheme(bodyMedium: TextStyle(fontSize: 13), bodyLarge: TextStyle(fontSize: 13), titleMedium: TextStyle(fontSize: 13)),
    );

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, this.hint, required this.child});
  final String title;
  final String? hint;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: borderColor), borderRadius: BorderRadius.circular(6)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: navy)),
            if (hint != null) Text(hint!, style: const TextStyle(fontSize: 11.5, color: textSecondary)),
          ]),
          const SizedBox(height: 12),
          child,
        ]),
      );
}
