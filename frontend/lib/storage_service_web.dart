import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static final StorageService _i = StorageService._();
  factory StorageService() => _i;
  StorageService._();

  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();

  Future<String?> read(String key) async {
    return _prefs.getString(key);
  }

  Future<void> write(String key, String value) async {
    await _prefs.setString(key, value);
  }

  Future<void> delete(String key) async {
    await _prefs.remove(key);
  }
}
