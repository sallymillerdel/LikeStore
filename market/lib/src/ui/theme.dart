import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// The red of the store icon (`assets/logo.png`). Filled buttons use it as is.
const kBrand = Color(0xFFFF1B43);

/// Neutral roles the Material scheme has no slot for. Surfaces, hairlines and
/// text stay grey; the icon red lives in the color scheme's `primary` and marks
/// the buttons, the new version and the update count.
@immutable
class StoreColors extends ThemeExtension<StoreColors> {
  const StoreColors({
    required this.page,
    required this.card,
    required this.raised,
    required this.hairline,
    required this.muted,
    required this.shadow,
    required this.accent,
    required this.accentTint,
  });

  /// The window background and the top bar.
  final Color page;

  /// Cards, dialogs and sheets.
  final Color card;

  /// One step up from a card: tonal buttons, icon placeholders, tracks.
  final Color raised;

  /// Borders and dividers: primary text at 8%.
  final Color hairline;

  /// Third text role, for meta like versions, sizes and counts.
  final Color muted;

  /// Light theme only; dark depth comes from surface steps.
  final Color shadow;

  /// The icon red as text and outlines: a step darker on light surfaces and a
  /// step lighter on dark ones, so small labels stay readable (4.5:1+).
  final Color accent;

  /// Background of tonal buttons: the icon red at ~10–16% over a card.
  final Color accentTint;

  static const light = StoreColors(
    page: Color(0xFFFAFAFA),
    card: Color(0xFFFFFFFF),
    raised: Color(0xFFF4F4F5),
    hairline: Color(0x14171717),
    muted: Color(0xFF737373),
    shadow: Color(0x0D000000),
    accent: Color(0xFFCF0E37),
    accentTint: Color(0xFFFFE8EC),
  );

  static const dark = StoreColors(
    page: Color(0xFF141415),
    card: Color(0xFF19191B),
    raised: Color(0xFF232325),
    hairline: Color(0x14EDEDED),
    muted: Color(0xFF85858B),
    shadow: Color(0x00000000),
    accent: Color(0xFFFF4D6A),
    accentTint: Color(0xFF3E1921),
  );

  static StoreColors of(BuildContext context) => Theme.of(context).extension<StoreColors>()!;

  @override
  StoreColors copyWith() => this;

  @override
  StoreColors lerp(StoreColors? other, double t) => t < 0.5 || other == null ? this : other;
}

/// The emphasis weight for names and titles. Segoe UI has no 500, so Windows
/// would fall back to Regular; Roboto has a real Medium.
final FontWeight kStrong = defaultTargetPlatform == TargetPlatform.windows ? FontWeight.w600 : FontWeight.w500;

/// Versions, sizes and counts line up digit for digit.
const kTabular = [FontFeature.tabularFigures()];

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final x = dark ? StoreColors.dark : StoreColors.light;
  final text = dark ? const Color(0xFFEDEDED) : const Color(0xFF171717);
  final secondary = dark ? const Color(0xFFA1A1A6) : const Color(0xFF525252);
  final scheme = ColorScheme.fromSeed(seedColor: kBrand, brightness: b).copyWith(
    primary: kBrand,
    onPrimary: Colors.white,
    primaryContainer: x.raised,
    onPrimaryContainer: secondary,
    // Tonal buttons (Open, Change, download progress).
    secondaryContainer: x.accentTint,
    onSecondaryContainer: x.accent,
    surface: x.card,
    surfaceTint: Colors.transparent,
    surfaceContainerLowest: x.card,
    surfaceContainerLow: x.card,
    surfaceContainer: x.card,
    surfaceContainerHigh: x.raised,
    surfaceContainerHighest: x.raised,
    onSurface: text,
    onSurfaceVariant: secondary,
    outline: dark ? const Color(0x29EDEDED) : const Color(0x29171717),
    outlineVariant: x.hairline,
    error: dark ? const Color(0xFFE5484D) : const Color(0xFFDC2626),
    errorContainer: dark ? const Color(0xFF2A1718) : const Color(0xFFFDF0F0),
    onErrorContainer: text,
  );

  final base = ThemeData(colorScheme: scheme, useMaterial3: true, visualDensity: VisualDensity.standard);
  final t = base.textTheme;
  const shape = WidgetStatePropertyAll<OutlinedBorder>(
    RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
  );
  const pad = WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16));
  const size = WidgetStatePropertyAll(Size(64, 40));
  final label = WidgetStatePropertyAll(t.labelLarge?.copyWith(fontSize: 14, fontWeight: kStrong));
  const quick = Duration(milliseconds: 150);

  return base.copyWith(
    scaffoldBackgroundColor: x.page,
    canvasColor: x.card,
    extensions: [x],
    hoverColor: text.withValues(alpha: 0.04),
    highlightColor: text.withValues(alpha: 0.06),
    textTheme: t.copyWith(
      headlineSmall: t.headlineSmall?.copyWith(fontSize: 22, height: 28 / 22, fontWeight: kStrong),
      titleLarge: t.titleLarge?.copyWith(fontSize: 18, height: 24 / 18, fontWeight: kStrong),
      titleMedium: t.titleMedium?.copyWith(fontSize: 16, height: 22 / 16, fontWeight: kStrong),
      bodyLarge: t.bodyLarge?.copyWith(fontSize: 15, height: 22 / 15),
      bodyMedium: t.bodyMedium?.copyWith(fontSize: 14, height: 20 / 14),
      bodySmall: t.bodySmall?.copyWith(fontSize: 13, height: 18 / 13, color: x.muted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(shape: shape, padding: pad, minimumSize: size, textStyle: label, animationDuration: quick),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        shape: shape,
        padding: pad,
        minimumSize: size,
        textStyle: label,
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled) ? x.muted : x.accent,
        ),
        side: WidgetStateProperty.resolveWith(
          (s) => BorderSide(
            color: s.contains(WidgetState.disabled) ? x.hairline : x.accent.withValues(alpha: 0.45),
          ),
        ),
        animationDuration: quick,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        shape: shape,
        padding: pad,
        minimumSize: size,
        textStyle: label,
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled) ? x.muted : x.accent,
        ),
        animationDuration: quick,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        shape: shape,
        iconSize: const WidgetStatePropertyAll(20),
        foregroundColor: WidgetStatePropertyAll(secondary),
      ),
    ),
    iconTheme: IconThemeData(color: secondary, size: 18),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      titleTextStyle: t.bodyLarge?.copyWith(fontSize: 15, height: 22 / 15, color: text),
      subtitleTextStyle: t.bodyMedium?.copyWith(fontSize: 13, height: 18 / 13, color: secondary),
      leadingAndTrailingTextStyle: t.bodyMedium?.copyWith(fontSize: 14, color: secondary, fontFeatures: kTabular),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: x.raised,
      linearMinHeight: 4,
      circularTrackColor: Colors.transparent,
    ),
    dividerTheme: DividerThemeData(color: x.hairline, space: 1, thickness: 1),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: x.card,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: x.muted.withValues(alpha: 0.5),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: x.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: x.hairline),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 500),
      textStyle: t.bodySmall?.copyWith(fontSize: 12, color: dark ? const Color(0xFF171717) : Colors.white),
      decoration: BoxDecoration(color: text, borderRadius: BorderRadius.circular(6)),
    ),
    switchTheme: SwitchThemeData(
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Colors.transparent : scheme.outline,
      ),
    ),
  );
}

/// Bordered surface used by cards, banners and grouped rows.
BoxDecoration panelDecoration(BuildContext context, {Color? color, Color? border, double radius = 16}) {
  final x = StoreColors.of(context);
  return BoxDecoration(
    color: color ?? x.card,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: border ?? x.hairline),
    boxShadow: [if (x.shadow.a > 0) BoxShadow(color: x.shadow, blurRadius: 2, offset: const Offset(0, 1))],
  );
}

/// `2.4.2 → 2.5.0`: the version an app moves from, muted, and the one it moves
/// to, in the accent. The store's one recurring detail, on cards, the updates
/// panel and the app page.
class VersionStep extends StatelessWidget {
  const VersionStep({super.key, required this.from, required this.to, this.style});

  final String from;
  final String to;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final x = StoreColors.of(context);
    final base = (style ?? Theme.of(context).textTheme.bodySmall)?.copyWith(fontFeatures: kTabular);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: from, style: TextStyle(color: x.muted)),
          TextSpan(text: '  →  ', style: TextStyle(color: x.muted)),
          TextSpan(
            text: to,
            style: TextStyle(color: x.accent, fontWeight: kStrong),
          ),
        ],
      ),
      style: base,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
