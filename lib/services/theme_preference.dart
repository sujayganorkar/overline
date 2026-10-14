import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persisted user preference for application color mode.
enum PdfCraftThemeChoice { system, light, dark }

extension PdfCraftThemeChoiceX on PdfCraftThemeChoice {
  ThemeMode get themeMode => switch (this) {
        PdfCraftThemeChoice.system => ThemeMode.system,
        PdfCraftThemeChoice.light => ThemeMode.light,
        PdfCraftThemeChoice.dark => ThemeMode.dark,
      };

  String get storageValue => name;

  IconData get icon => switch (this) {
        PdfCraftThemeChoice.system => Icons.brightness_auto,
        PdfCraftThemeChoice.light => Icons.light_mode,
        PdfCraftThemeChoice.dark => Icons.dark_mode,
      };

  String get label => switch (this) {
        PdfCraftThemeChoice.system => 'System',
        PdfCraftThemeChoice.light => 'Light',
        PdfCraftThemeChoice.dark => 'Dark',
      };

  static PdfCraftThemeChoice fromStorage(String? value) {
    return PdfCraftThemeChoice.values.firstWhere(
      (choice) => choice.name == value,
      orElse: () => PdfCraftThemeChoice.system,
    );
  }
}

/// Small controller around the user’s theme preference.
///
/// It is intentionally dependency-light so widget tests can use it without
/// standing up platform plugins beyond SharedPreferences.
class ThemePreferenceController extends ChangeNotifier {
  ThemePreferenceController._(this._preferences, this._choice);

  final SharedPreferences _preferences;

  PdfCraftThemeChoice _choice;
  PdfCraftThemeChoice get choice => _choice;
  ThemeMode get mode => _choice.themeMode;

  static const _storageKey = 'pdfcraft.theme.choice';

  static Future<ThemePreferenceController> load() async {
    final preferences = await SharedPreferences.getInstance();
    final storedChoice = PdfCraftThemeChoiceX.fromStorage(
      preferences.getString(_storageKey),
    );
    return ThemePreferenceController._(preferences, storedChoice);
  }

  Future<void> setChoice(PdfCraftThemeChoice choice) async {
    if (_choice == choice) return;
    _choice = choice;
    await _preferences.setString(_storageKey, choice.storageValue);
    notifyListeners();
  }
}
