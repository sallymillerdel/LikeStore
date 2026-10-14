import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Colors the Material scheme has no slot for: the page gradient, the
/// "Updates ready" hero card and the tinted cards of apps with updates.
@immutable
class StoreColors extends ThemeExtension<StoreColors> {
  const StoreColors({
    required this.pageTop,
    required this.pageBottom,
    required this.card,
    required this.cardBorder,
    required this.updateCard,
    required this.updateCardBorder,
    required this.heroStart,
    required this.heroEnd,
    required this.heroBorder,
    required this.heroLabel,
    required this.heroText,
    required this.heroButton,
    required this.heroButtonText,
    required this.track,
    required this.shadow,
  });

  final Color pageTop;
  final Color pageBottom;
  final Color card;
  final Color cardBorder;
  final Color updateCard;
  final Color updateCardBorder;
  final Color heroStart;
  final Color heroEnd;
  final Color heroBorder;
  final Color heroLabel;
  final Color heroText;
  final Color heroButton;
  final Color heroButtonText;
  final Color track;
  final Color shadow;

  static const light = StoreColors(
    pageTop: Color(0xFFE4F3EF),
    pageBottom: Color(0xFFF3F7F6),
    card: Color(0xFFF9FCFB),
    cardBorder: Color(0xFFD6E8E3),
    updateCard: Color(0xFFDDF3EE),
    updateCardBorder: Color(0xFFC3E5DD),
    heroStart: Color(0xFF1B7A6F),
    heroEnd: Color(0xFF3AA596),
    heroBorder: Color(0x00000000),
    heroLabel: Color(0xFFD3F5EE),
    heroText: Color(0xFFFFFFFF),
    heroButton: Color(0xFFFFFFFF),
    heroButtonText: Color(0xFF0E5C53),
    track: Color(0xFFBFE0D9),
    shadow: Color(0x0D104A42),
  );

  static const dark = StoreColors(
    pageTop: Color(0xFF0E2220),
    pageBottom: Color(0xFF070B0B),
    card: Color(0xFF111918),
    cardBorder: Color(0xFF243130),
    updateCard: Color(0xFF12201F),
    updateCardBorder: Color(0xFF2A4340),
    heroStart: Color(0xFF1C4A45),
    heroEnd: Color(0xFF0E2826),
    heroBorder: Color(0xFF2E5C56),
    heroLabel: Color(0xFF7FE3D0),
    heroText: Color(0xFFF1F7F6),
    heroButton: Color(0xFFE6F8F4),
    heroButtonText: Color(0xFF0C3D37),
    track: Color(0xFF26302F),
    shadow: Color(0x00000000),
  );

  static StoreColors of(BuildContext context) => Theme.of(context).extension<StoreColors>()!;

  @override
  StoreColors copyWith() => this;

  @override
  StoreColors lerp(StoreColors? other, double t) => t < 0.5 || other == null ? this : other;
}

const _seed = Color(0xFF0F766E);

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final x = dark ? StoreColors.dark : StoreColors.light;
  final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: b).copyWith(
    primary: dark ? const Color(0xFF6EDCC8) : const Color(0xFF12756B),
    onPrimary: dark ? const Color(0xFF00362F) : Colors.white,
    primaryContainer: dark ? const Color(0xFF1B3F3B) : const Color(0xFFD3F0EA),
    onPrimaryContainer: dark ? const Color(0xFFBDF3E8) : const Color(0xFF0B3F39),
    secondaryContainer: dark ? const Color(0xFF1A3532) : const Color(0xFFCBEBE4),
    onSecondaryContainer: dark ? const Color(0xFF9FEBDD) : const Color(0xFF0E5A52),
    surface: dark ? const Color(0xFF0B1211) : const Color(0xFFF3F8F7),
    onSurface: dark ? const Color(0xFFE6EFED) : const Color(0xFF0F1F1C),
    onSurfaceVariant: dark ? const Color(0xFFA3B5B1) : const Color(0xFF4A5E5A),
    surfaceContainerLow: x.card,
    outlineVariant: x.cardBorder,
    error: dark ? const Color(0xFFF2A097) : const Color(0xFFB3261E),
  );

  final pill = WidgetStatePropertyAll<OutlinedBorder>(const StadiumBorder());
  const pad = WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 22, vertical: 12));
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, visualDensity: VisualDensity.standard);
  final label = WidgetStatePropertyAll(base.textTheme.labelLarge?.copyWith(fontSize: 15, fontWeight: FontWeight.w600));

  return base.copyWith(
    scaffoldBackgroundColor: x.pageBottom,
    extensions: [x],
    textTheme: base.textTheme.copyWith(
      headlineSmall: base.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
      titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(shape: pill, padding: pad, textStyle: label),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        shape: pill,
        padding: pad,
        textStyle: label,
        side: WidgetStatePropertyAll(BorderSide(color: dark ? const Color(0xFF34423F) : const Color(0xFFB8D3CD))),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        shape: pill,
        textStyle: WidgetStatePropertyAll(
          base.textTheme.labelLarge?.copyWith(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: x.track,
      linearMinHeight: 8,
    ),
    dividerTheme: DividerThemeData(color: x.cardBorder, space: 1, thickness: 1),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: dark ? const Color(0xFF0F1817) : const Color(0xFFF5FAF9),
      surfaceTintColor: Colors.transparent,
      dragHandleColor: scheme.onSurfaceVariant.withValues(alpha: 0.4),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: dark ? const Color(0xFF131D1C) : const Color(0xFFF5FAF9),
      surfaceTintColor: Colors.transparent,
    ),
    switchTheme: SwitchThemeData(
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Colors.transparent : scheme.outline,
      ),
    ),
  );
}

/// Rounded, bordered surface used by cards, banners and the top bar.
BoxDecoration panelDecoration(BuildContext context, {Color? color, Color? border, double radius = 24}) {
  final x = StoreColors.of(context);
  return BoxDecoration(
    color: color ?? x.card,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: border ?? x.cardBorder),
    boxShadow: [if (x.shadow.a > 0) BoxShadow(color: x.shadow, blurRadius: 24, offset: const Offset(0, 2))],
  );
}

/// The page background: a soft teal glow at the top fading out.
///
/// The gradient is long and dark, so plain 8-bit rendering shows it as wide
/// bands. It is drawn with a dithering shader ([load] it before `runApp`);
/// without one it falls back to a plain [LinearGradient].
class PageBackground extends StatelessWidget {
  const PageBackground({super.key, required this.child});

  final Widget child;

  static ui.FragmentProgram? _program;

  static Future<void> load() async {
    try {
      _program = await ui.FragmentProgram.fromAsset('shaders/page_gradient.frag');
    } catch (e) {
      debugPrint('Page gradient shader unavailable: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final x = StoreColors.of(context);
    return CustomPaint(painter: _GradientPainter(x.pageTop, x.pageBottom, _program), child: child);
  }
}

class _GradientPainter extends CustomPainter {
  _GradientPainter(this.from, this.to, this.program);

  final Color from;
  final Color to;
  final ui.FragmentProgram? program;

  // From the top-left corner to Alignment(0.4, 0.6).
  static const _end = Offset(0.7, 0.8);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final end = Offset(size.width * _end.dx, size.height * _end.dy);
    final paint = Paint();
    final program = this.program;
    if (program == null) {
      paint.shader = ui.Gradient.linear(Offset.zero, end, [from, to]);
    } else {
      final s = program.fragmentShader();
      var i = 0;
      for (final v in [0.0, 0.0, end.dx, end.dy, from.r, from.g, from.b, from.a, to.r, to.g, to.b, to.a]) {
        s.setFloat(i++, v);
      }
      paint.shader = s;
    }
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(_GradientPainter old) => old.from != from || old.to != to || old.program != program;
}
