import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

/// BetterCast brand: warm ember + gold on an inky plum night, or warm paper by day.
abstract final class Brand {
  static const ember = Color(0xFFFF6A3D);
  static const gold = Color(0xFFFFB23F);
  static const lilac = Color(0xFFB9A6FF);

  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [ember, gold],
  );

  static const dark = ColorScheme(
    brightness: Brightness.dark,
    primary: ember,
    onPrimary: Color(0xFF2A0C02),
    primaryContainer: Color(0xFF5A2210),
    onPrimaryContainer: Color(0xFFFFDBCF),
    secondary: gold,
    onSecondary: Color(0xFF2B1A00),
    secondaryContainer: Color(0xFF4A3410),
    onSecondaryContainer: Color(0xFFFFDDB0),
    tertiary: lilac,
    onTertiary: Color(0xFF221447),
    tertiaryContainer: Color(0xFF3A2C66),
    onTertiaryContainer: Color(0xFFE6DEFF),
    error: Color(0xFFFF8A80),
    onError: Color(0xFF3B0907),
    surface: Color(0xFF13111A),
    onSurface: Color(0xFFF5EFEA),
    onSurfaceVariant: Color(0xFFB8AFBF),
    surfaceContainerLowest: Color(0xFF0E0C13),
    surfaceContainerLow: Color(0xFF19161F),
    surfaceContainer: Color(0xFF1E1A26),
    surfaceContainerHigh: Color(0xFF26212F),
    surfaceContainerHighest: Color(0xFF302A3B),
    outline: Color(0xFF6E6578),
    outlineVariant: Color(0xFF3A3345),
    inverseSurface: Color(0xFFF5EFEA),
    onInverseSurface: Color(0xFF13111A),
    inversePrimary: Color(0xFFB83E18),
  );

  static const light = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFFE0502A),
    onPrimary: Colors.white,
    primaryContainer: Color(0xFFFFDBCF),
    onPrimaryContainer: Color(0xFF3A0F02),
    secondary: Color(0xFFB87300),
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFFFFE3BC),
    onSecondaryContainer: Color(0xFF2B1A00),
    tertiary: Color(0xFF6A52D9),
    onTertiary: Colors.white,
    tertiaryContainer: Color(0xFFE6DEFF),
    onTertiaryContainer: Color(0xFF221447),
    error: Color(0xFFC62828),
    onError: Colors.white,
    surface: Color(0xFFFBF7F2),
    onSurface: Color(0xFF1E1A22),
    onSurfaceVariant: Color(0xFF5E5663),
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: Color(0xFFF6F0E9),
    surfaceContainer: Color(0xFFF1EAE2),
    surfaceContainerHigh: Color(0xFFEBE3DA),
    surfaceContainerHighest: Color(0xFFE4DBD1),
    outline: Color(0xFF8E8590),
    outlineVariant: Color(0xFFD8CFC6),
    inverseSurface: Color(0xFF2E2932),
    onInverseSurface: Color(0xFFF7F0EA),
    inversePrimary: ember,
  );
}

/// Builds the full app theme around a color scheme (brand or artwork-derived).
ThemeData buildTheme(ColorScheme s) {
  final body = GoogleFonts.plusJakartaSansTextTheme(
    ThemeData(brightness: s.brightness).textTheme,
  );
  TextStyle? display(TextStyle? t, {FontWeight w = FontWeight.w700, double? ls}) =>
      GoogleFonts.bricolageGrotesque(textStyle: t, fontWeight: w, letterSpacing: ls);
  final text = body
      .copyWith(
        displayLarge: display(body.displayLarge, w: FontWeight.w800, ls: -1.5),
        displayMedium: display(body.displayMedium, w: FontWeight.w800, ls: -1),
        displaySmall: display(body.displaySmall, w: FontWeight.w800, ls: -0.8),
        headlineLarge: display(body.headlineLarge, w: FontWeight.w800, ls: -0.6),
        headlineMedium: display(body.headlineMedium, w: FontWeight.w800, ls: -0.5),
        headlineSmall: display(body.headlineSmall, ls: -0.3),
        titleLarge: display(body.titleLarge, ls: -0.2),
        titleMedium: body.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        titleSmall: body.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        labelLarge: body.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      )
      .apply(bodyColor: s.onSurface, displayColor: s.onSurface);

  final stadium = WidgetStatePropertyAll<OutlinedBorder>(const StadiumBorder());
  const pad = WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 22, vertical: 14));

  return ThemeData(
    useMaterial3: true,
    colorScheme: s,
    scaffoldBackgroundColor: s.surface,
    textTheme: text,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: s.surface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 70,
      backgroundColor: s.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      indicatorColor: s.primary.withValues(alpha: 0.18),
      indicatorShape: const StadiumBorder(),
      labelTextStyle: WidgetStateProperty.resolveWith((st) => text.labelSmall?.copyWith(
            fontWeight: st.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w600,
            color: st.contains(WidgetState.selected) ? s.primary : s.onSurfaceVariant,
          )),
      iconTheme: WidgetStateProperty.resolveWith((st) => IconThemeData(
            color: st.contains(WidgetState.selected) ? s.primary : s.onSurfaceVariant,
          )),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: s.surfaceContainerLow,
      indicatorColor: s.primary.withValues(alpha: 0.18),
      selectedIconTheme: IconThemeData(color: s.primary),
      selectedLabelTextStyle:
          text.labelSmall?.copyWith(color: s.primary, fontWeight: FontWeight.w800),
      unselectedLabelTextStyle: text.labelSmall?.copyWith(color: s.onSurfaceVariant),
    ),
    tabBarTheme: TabBarThemeData(
      dividerColor: Colors.transparent,
      indicatorSize: TabBarIndicatorSize.tab,
      indicator: BoxDecoration(color: s.primary, borderRadius: BorderRadius.circular(99)),
      labelColor: s.onPrimary,
      unselectedLabelColor: s.onSurfaceVariant,
      labelStyle: text.labelLarge,
      unselectedLabelStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      labelPadding: const EdgeInsets.symmetric(horizontal: 16),
      splashBorderRadius: BorderRadius.circular(99),
      tabAlignment: TabAlignment.start,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: s.surfaceContainer,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      clipBehavior: Clip.antiAlias,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(shape: stadium, padding: pad, textStyle: WidgetStatePropertyAll(text.labelLarge)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        shape: stadium,
        padding: pad,
        textStyle: WidgetStatePropertyAll(text.labelLarge),
        side: WidgetStatePropertyAll(BorderSide(color: s.outlineVariant, width: 1.5)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(shape: stadium, textStyle: WidgetStatePropertyAll(text.labelLarge)),
    ),
    chipTheme: ChipThemeData(
      shape: const StadiumBorder(),
      side: BorderSide(color: s.outlineVariant),
      labelStyle: text.labelLarge,
      showCheckmark: false,
      selectedColor: s.primary,
      secondarySelectedColor: s.primary,
      secondaryLabelStyle: text.labelLarge?.copyWith(color: s.onPrimary),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        side: WidgetStatePropertyAll(BorderSide(color: s.outlineVariant)),
        backgroundColor: WidgetStateProperty.resolveWith(
            (st) => st.contains(WidgetState.selected) ? s.primary : null),
        foregroundColor: WidgetStateProperty.resolveWith(
            (st) => st.contains(WidgetState.selected) ? s.onPrimary : s.onSurface),
      ),
    ),
    sliderTheme: SliderThemeData(
      trackHeight: 6,
      activeTrackColor: s.primary,
      inactiveTrackColor: s.onSurface.withValues(alpha: 0.12),
      thumbColor: s.primary,
      overlayColor: s.primary.withValues(alpha: 0.12),
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
      trackShape: const RoundedRectSliderTrackShape(),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: s.primary,
      linearTrackColor: s.onSurface.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(99),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: s.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: s.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: s.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: s.inverseSurface,
      contentTextStyle: text.bodyMedium?.copyWith(color: s.onInverseSurface),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: s.surfaceContainer,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: s.primary, width: 2),
      ),
    ),
    searchBarTheme: SearchBarThemeData(
      elevation: const WidgetStatePropertyAll(0),
      backgroundColor: WidgetStatePropertyAll(s.surfaceContainerHigh),
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16)),
      textStyle: WidgetStatePropertyAll(text.bodyLarge),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: s.onSurfaceVariant,
      titleTextStyle: text.titleSmall?.copyWith(color: s.onSurface),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
          (st) => st.contains(WidgetState.selected) ? s.onPrimary : null),
      trackColor: WidgetStateProperty.resolveWith(
          (st) => st.contains(WidgetState.selected) ? s.primary : null),
    ),
    dividerTheme: DividerThemeData(color: s.outlineVariant.withValues(alpha: 0.5), space: 1),
    badgeTheme: BadgeThemeData(backgroundColor: s.primary, textColor: s.onPrimary),
  );
}

final brandThemeProvider = Provider.family<ThemeData, Brightness>(
    (ref, b) => buildTheme(b == Brightness.dark ? Brand.dark : Brand.light));

/// Color scheme extracted from a cover, so each show tints its own pages.
final artworkSchemeProvider =
    FutureProvider.family<ColorScheme?, (String, Brightness)>((ref, key) async {
  final (url, brightness) = key;
  try {
    return await ColorScheme.fromImageProvider(
      provider: ResizeImage(NetworkImage(url), width: 96, height: 96),
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );
  } catch (_) {
    return null;
  }
});

final _artworkThemeProvider =
    Provider.family<ThemeData?, (String, Brightness)>((ref, key) {
  final scheme = ref.watch(artworkSchemeProvider(key)).value;
  if (scheme == null) return null;
  final base = key.$2 == Brightness.dark ? Brand.dark : Brand.light;
  // Keep brand surfaces' depth but tint them with the cover's hue.
  Color tint(Color c, double a) => Color.alphaBlend(scheme.primary.withValues(alpha: a), c);
  return buildTheme(scheme.copyWith(
    surface: tint(base.surface, 0.06),
    surfaceContainerLowest: tint(base.surfaceContainerLowest, 0.05),
    surfaceContainerLow: tint(base.surfaceContainerLow, 0.08),
    surfaceContainer: tint(base.surfaceContainer, 0.10),
    surfaceContainerHigh: tint(base.surfaceContainerHigh, 0.12),
    surfaceContainerHighest: tint(base.surfaceContainerHighest, 0.14),
    onSurface: base.onSurface,
    onSurfaceVariant: base.onSurfaceVariant,
    outlineVariant: base.outlineVariant,
    inverseSurface: base.inverseSurface,
    onInverseSurface: base.onInverseSurface,
  ));
});

/// Re-themes [child] with the colors of [artworkUrl] (falls back to the brand theme).
class ArtworkTheme extends ConsumerWidget {
  const ArtworkTheme({super.key, required this.artworkUrl, required this.child});
  final String? artworkUrl;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = artworkUrl;
    if (url == null || url.isEmpty) return child;
    final b = Theme.of(context).brightness;
    final theme = ref.watch(_artworkThemeProvider((url, b)));
    if (theme == null) return child;
    return AnimatedTheme(data: theme, duration: const Duration(milliseconds: 400), child: child);
  }
}
