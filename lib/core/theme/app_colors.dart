import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const background = Color(0xFF07070D);
  static const surface = Color(0xFF12121E);
  static const surfaceAlt = Color(0xFF1A1A2B);
  static const border = Color(0xFF262640);
  static const borderSoft = Color(0xFF1E1E33);

  static const textPrimary = Color(0xFFF5F6FA);
  static const textSecondary = Color(0xFF9C9DB8);
  static const textTertiary = Color(0xFF5F607E);

  static const primary = Color(0xFF7C5CFF);
  static const primaryDark = Color(0xFF5B3DF5);
  static const accent = Color(0xFF33C2FF);
  static const pink = Color(0xFFFF4D8D);

  static const success = Color(0xFF34D399);
  static const warning = Color(0xFFFBBF24);
  static const danger = Color(0xFFF87171);

  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF8B5CF6), Color(0xFF3BA7FF)],
  );

  static const gradientSuccess = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF34D399), Color(0xFF22D3EE)],
  );

  static const glowPrimary = Color(0x557C5CFF);
  static const glowGreen = Color(0x5534D399);
}
