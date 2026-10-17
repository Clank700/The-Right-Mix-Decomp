import 'dart:io';

import 'package:flutter/services.dart';

import 'settings.dart';

/// Where settings live: `%APPDATA%\TheRightMix\settings.json` on Windows, the app's private files directory on
/// Android (asked from MainActivity, since Dart has no portable way to find it without a plugin).
Future<File?> _file() async {
  try {
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      if (appData == null) return null;
      final dir = Directory('$appData/TheRightMix')..createSync(recursive: true);
      return File('${dir.path}/settings.json');
    }
    if (Platform.isAndroid) {
      final dir = await const MethodChannel('org.decomp.therightmix/platform').invokeMethod<String>('filesDir');
      if (dir == null) return null;
      return File('$dir/settings.json');
    }
  } catch (_) {}
  return null;
}

Future<Settings> loadSettingsImpl() async {
  try {
    final f = await _file();
    if (f != null && f.existsSync()) return Settings.decode(f.readAsStringSync());
  } catch (_) {}
  return Settings();
}

Future<void> saveSettingsImpl(Settings s) async {
  try {
    final f = await _file();
    f?.writeAsStringSync(s.encode());
  } catch (_) {}
}
