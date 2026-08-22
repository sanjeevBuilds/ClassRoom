import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'screens/home_screen.dart';

/// Root widget for the ClassRoom app.
class ClassRoomApp extends StatelessWidget {
  const ClassRoomApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Primary aesthetic colors derived from UI designs
    const primaryColor = Color(0xFF3629B6);
    const accentColor = Color(0xFFFF4267);
    const darkBgColor = Color(0xFF12202F);
    
    return MaterialApp(
      title: 'ClassRoom',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark, // Default to dark mode per design
      
      darkTheme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: darkBgColor,
        colorScheme: const ColorScheme.dark(
          primary: primaryColor,
          secondary: accentColor,
          surface: Color(0xFF1E2D3D), // Slightly lighter than bg for cards
          error: Color(0xFFFF2936),
        ),
        useMaterial3: true,
        textTheme: GoogleFonts.poppinsTextTheme(
          ThemeData(brightness: Brightness.dark).textTheme,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            elevation: 5,
            shadowColor: primaryColor.withOpacity(0.3),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
