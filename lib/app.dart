import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

/// Root widget for the ClassRoom app.
///
/// Uses the platform's default text theme rather than `google_fonts` —
/// that package fetches font files over the network at runtime on first
/// use (and caches them), which directly contradicts this project's core
/// "100% offline, no internet required" design. Confirmed as a real issue
/// on-device: a font fetch to fonts.gstatic.com failed and the debug
/// connection dropped right after. Not worth the risk for a cosmetic font
/// choice — if custom typography matters later, bundle a font file as a
/// local asset instead of fetching one at runtime.
class ClassRoomApp extends StatelessWidget {
  const ClassRoomApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ClassRoom',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF1565C0),
        brightness: Brightness.light,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF1565C0),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}
