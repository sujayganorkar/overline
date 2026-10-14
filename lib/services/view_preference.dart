import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ReadingMode { single, doublePage, vertical, horizontalContinuous }

extension ReadingModeX on ReadingMode {
  String get storageValue => name;

  ReadingMode get next => switch (this) {
        ReadingMode.single => ReadingMode.doublePage,
        ReadingMode.doublePage => ReadingMode.vertical,
        ReadingMode.vertical => ReadingMode.horizontalContinuous,
        ReadingMode.horizontalContinuous => ReadingMode.single,
      };

  String get label => switch (this) {
        ReadingMode.single => 'Single page',
        ReadingMode.doublePage => 'Facing pages',
        ReadingMode.vertical => 'Vertical scroll',
        ReadingMode.horizontalContinuous => 'Horizontal scroll',
      };

  IconData get icon => switch (this) {
        ReadingMode.single => Icons.crop_portrait_outlined,
        ReadingMode.doublePage => Icons.menu_book_outlined,
        ReadingMode.vertical => Icons.view_stream_outlined,
        ReadingMode.horizontalContinuous => Icons.view_carousel_outlined,
      };

  static ReadingMode fromStorage(String? value) {
    return ReadingMode.values.cast<ReadingMode?>().firstWhere(
          (mode) => mode?.name == value,
          orElse: () => ReadingMode.single,
        ) ??
        ReadingMode.single;
  }
}

class ReadingPreferenceController extends ChangeNotifier {
  ReadingPreferenceController._(
    this._preferences,
    this._mode, {
    this._invertColors = false,
  });

  final SharedPreferences _preferences;
  static const _storageKey = 'pdfcraft.reading.mode';

  Future<void> setInverted(bool value) async {
    if (_invertColors == value) return;
    _invertColors = value;
    await _preferences.setBool('$_storageKey.invert', value);
    notifyListeners();
  }

  ReadingMode _mode;
  bool _invertColors = false;
  ReadingMode get mode => _mode;
  bool get invertDocumentColors => _invertColors;

  static Future<ReadingPreferenceController> load() async {
    final preferences = await SharedPreferences.getInstance();
    return ReadingPreferenceController._(
      preferences,
      ReadingModeX.fromStorage(preferences.getString(_storageKey)),
      invertColors: preferences.getBool('$_storageKey.invert') ?? false,
    );
  }

  Future<void> setMode(ReadingMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    await _preferences.setString(_storageKey, mode.storageValue);
    notifyListeners();
  }
}