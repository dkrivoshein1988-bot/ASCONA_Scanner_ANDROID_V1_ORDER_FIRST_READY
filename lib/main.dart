import 'package:flutter/material.dart';

import 'screens/returns_home_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AsconaReturnsApp());
}

class AsconaReturnsApp extends StatelessWidget {
  const AsconaReturnsApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seedColor = Color(0xFF1F4E8C);
    return MaterialApp(
      title: 'ASCONA Scanner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          backgroundColor: Color(0xFFF8FAFC),
          surfaceTintColor: Colors.transparent,
          titleTextStyle: TextStyle(
            color: Color(0xFF101828),
            fontSize: 21,
            fontWeight: FontWeight.w800,
          ),
        ),
        cardTheme: const CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
            side: BorderSide(color: Color(0xFFE4E7EC)),
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
      home: const ReturnsHomePage(),
    );
  }
}
