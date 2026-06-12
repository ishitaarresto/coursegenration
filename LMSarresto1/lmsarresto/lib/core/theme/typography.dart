import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'colors.dart';

class AText {
  AText._();
  static TextStyle display({Color? color}) => GoogleFonts.inter(
      fontSize: 32, fontWeight: FontWeight.w800,
      letterSpacing: -0.6, color: color ?? AColors.ink);
  static TextStyle h1({Color? color}) => GoogleFonts.inter(
      fontSize: 26, fontWeight: FontWeight.w800,
      letterSpacing: -0.3, color: color ?? AColors.ink);
  static TextStyle h2({Color? color}) => GoogleFonts.inter(
      fontSize: 21, fontWeight: FontWeight.w800, color: color ?? AColors.ink);
  static TextStyle h3({Color? color}) => GoogleFonts.inter(
      fontSize: 16, fontWeight: FontWeight.w700, color: color ?? AColors.ink);
  static TextStyle body({Color? color}) => GoogleFonts.inter(
      fontSize: 14, fontWeight: FontWeight.w400, color: color ?? AColors.textSecond);
  static TextStyle bodyMd({Color? color}) => GoogleFonts.inter(
      fontSize: 14, fontWeight: FontWeight.w500, color: color ?? AColors.textPrimary);
  static TextStyle bodyBold({Color? color}) => GoogleFonts.inter(
      fontSize: 14, fontWeight: FontWeight.w600, color: color ?? AColors.ink);
  static TextStyle label({Color? color}) => GoogleFonts.inter(
      fontSize: 13, fontWeight: FontWeight.w600, color: color ?? AColors.ink);
  static TextStyle small({Color? color}) => GoogleFonts.inter(
      fontSize: 12, fontWeight: FontWeight.w400, color: color ?? AColors.textMuted);
  static TextStyle smallMd({Color? color}) => GoogleFonts.inter(
      fontSize: 12, fontWeight: FontWeight.w500, color: color ?? AColors.textMuted);
  static TextStyle smallBold({Color? color}) => GoogleFonts.inter(
      fontSize: 12, fontWeight: FontWeight.w600, color: color ?? AColors.textPrimary);
  static TextStyle tiny({Color? color}) => GoogleFonts.inter(
      fontSize: 11, fontWeight: FontWeight.w500, color: color ?? AColors.textMuted);
  static TextStyle eyebrow({Color? color}) => GoogleFonts.inter(
      fontSize: 11, fontWeight: FontWeight.w700,
      letterSpacing: 0.8, color: color ?? AColors.textMuted).copyWith(
      textBaseline: TextBaseline.alphabetic);
  static TextStyle stat({Color? color}) => GoogleFonts.inter(
      fontSize: 28, fontWeight: FontWeight.w800,
      letterSpacing: -0.5, color: color ?? AColors.ink);
  static TextStyle mono({Color? color}) => GoogleFonts.jetBrainsMono(
      fontSize: 11, fontWeight: FontWeight.w400, color: color ?? AColors.textMuted2);
}
