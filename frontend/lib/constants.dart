import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

const String _configuredApiHost = String.fromEnvironment('API_HOST');

String get _apiHost {
  if (_configuredApiHost.isNotEmpty) return _configuredApiHost;
  // Since we reversed port 5000 via adb, we can use 127.0.0.1 directly!
  return '127.0.0.1';
}

String get kBaseUrl => 'http://$_apiHost:5000/api';
String get kSocketUrl => 'http://$_apiHost:5000';

const String kAccessToken = 'access_token';
const String kRefreshToken = 'refresh_token';

const Color kPrimary = Color(0xFF0F6E56);
const Color kPrimaryLight = Color(0xFFE1F5EE);
const Color kSecondary = Color(0xFF378ADD);
const Color kAmber = Color(0xFFBA7517);
const Color kAmberLight = Color(0xFFFAEEDA);
const Color kRed = Color(0xFFE24B4A);
const Color kRedLight = Color(0xFFFCEBEB);
const Color kPurple = Color(0xFF7F77DD);
const Color kGray50  = Color(0xFFFAFAFC);
const Color kGray100 = Color(0xFFF5F5F7);
const Color kGray200 = Color(0xFFEBEBF0);
const Color kGray300 = Color(0xFFD2D2DC);
const Color kGray400 = Color(0xFFA0A0B0);
const Color kGray500 = Color(0xFF858595);
const Color kGray600 = Color(0xFF6B6B80);
const Color kGray700 = Color(0xFF4F4F60);
const Color kGray800 = Color(0xFF333345);
const Color kGray900 = Color(0xFF1A1A2E);

ThemeData buildTheme() => ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: kPrimary),
      fontFamily: 'Inter',
      scaffoldBackgroundColor: kGray100,
      appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: kGray900,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
              fontFamily: 'Inter',
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: kGray900)),
      elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
              backgroundColor: kPrimary,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              textStyle:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 15))),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
              foregroundColor: kPrimary,
              minimumSize: const Size(double.infinity, 52),
              side: const BorderSide(color: kPrimary),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)))),
      inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: kGray200)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: kGray200)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: kPrimary, width: 1.5)),
          hintStyle: const TextStyle(color: kGray400, fontSize: 14)),
      cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: kGray200, width: 0.5)),
          margin: EdgeInsets.zero),
    );
