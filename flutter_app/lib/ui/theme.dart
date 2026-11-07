import 'package:flutter/material.dart';

const navy = Color(0xFF14233A);
const navyLight = Color(0xFF24405F);
const orange = Color(0xFFE8631C);
const orangeDark = Color(0xFFC24F14);
const yellow = Color(0xFFF2B705);
const pageBg = Color(0xFFF1F3F7);
const borderColor = Color(0xFFDFE4EB);
const textSecondary = Color(0xFF5F6F84);
const greenOk = Color(0xFF1F8A5F);
const redErr = Color(0xFFC0392B);

const softShadow = [BoxShadow(color: Color(0x14182B45), blurRadius: 16, offset: Offset(0, 4))];

ThemeData buildTheme() => ThemeData(
      useMaterial3: true,
      fontFamily: 'NotoSansSC',
      colorScheme: ColorScheme.fromSeed(seedColor: navy, primary: navy, secondary: orange, surface: Colors.white),
      scaffoldBackgroundColor: pageBg,
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: const Color(0xFFF7F9FB),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: borderColor)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: borderColor)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: orange, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        labelStyle: const TextStyle(fontSize: 12.5, color: textSecondary),
        hintStyle: const TextStyle(fontSize: 12.5, color: Color(0xFF9AA7B8)),
      ),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)))),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(foregroundColor: navy, side: const BorderSide(color: Color(0xFFC9D2DE)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9))),
      ),
      snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
      dialogTheme: DialogThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
      textTheme: const TextTheme(bodyMedium: TextStyle(fontSize: 13), bodyLarge: TextStyle(fontSize: 13), titleMedium: TextStyle(fontSize: 13)),
    );

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, this.hint, this.step, this.icon, this.trailing, required this.child});
  final String title;
  final String? hint;
  final int? step;
  final IconData? icon;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: softShadow),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (step != null || icon != null) ...[
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: const Color(0xFFFFF1E8), borderRadius: BorderRadius.circular(9)),
                child: step != null
                    ? Text('$step', style: const TextStyle(color: orangeDark, fontWeight: FontWeight.w800, fontSize: 15))
                    : Icon(icon, size: 18, color: orangeDark),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: navy)),
                if (hint != null) Padding(padding: const EdgeInsets.only(top: 1), child: Text(hint!, style: const TextStyle(fontSize: 11.5, color: textSecondary))),
              ]),
            ),
            ?trailing,
          ]),
          const SizedBox(height: 14),
          Material(type: MaterialType.transparency, child: child),
        ]),
      );
}
