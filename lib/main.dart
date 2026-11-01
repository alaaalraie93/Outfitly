import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/home.dart';
import 'screens/onboarding.dart';
import 'state.dart';
import 'widgets/sky.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState();
  await state.load();
  runApp(OutfitlyApp(state: state));
}

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final base = ColorScheme.fromSeed(seedColor: Sky.blue, brightness: b);
  final scheme = base.copyWith(
    primary: dark ? const Color(0xFF7FD0FF) : Sky.deep,
    tertiary: Sky.coral,
    surface: dark ? const Color(0xFF0E1A2B) : const Color(0xFFF7FBFF),
  );
  const shape = StadiumBorder();
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(shape: shape)),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(shape: shape)),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? const Color(0xFF12223A) : Colors.white,
      indicatorColor: dark ? const Color(0xFF1E4F7D) : Sky.light,
      elevation: 3,
    ),
    chipTheme: ChipThemeData(shape: const StadiumBorder(), side: BorderSide(color: scheme.outlineVariant)),
  );
}

class OutfitlyApp extends StatelessWidget {
  final AppState state;
  const OutfitlyApp({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: Builder(builder: (context) {
        final s = AppScope.of(context);
        return MaterialApp(
          title: 'Outfitly',
          debugShowCheckedModeBanner: false,
          locale: Locale(s.profile.lang),
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          home: s.profile.onboarded ? const HomeShell() : const OnboardingScreen(),
        );
      }),
    );
  }
}
