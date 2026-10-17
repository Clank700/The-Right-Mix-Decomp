import 'settings.dart';
import 'settings_store_stub.dart' if (dart.library.io) 'settings_store_io.dart';

/// Loads and saves [Settings]; failures fall back to defaults and never reach the game.
class SettingsStore {
  static Future<Settings> load() => loadSettingsImpl();
  static Future<void> save(Settings s) => saveSettingsImpl(s);
}
