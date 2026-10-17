import 'settings.dart';

/// Web / unsupported platforms: nothing is stored.
Future<Settings> loadSettingsImpl() async => Settings();
Future<void> saveSettingsImpl(Settings s) async {}
