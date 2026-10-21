import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StorageService {
  static final StorageService _i = StorageService._();
  factory StorageService() => _i;
  StorageService._();

  final _secure = const FlutterSecureStorage();

  Future<String?> read(String key) => _secure.read(key: key);
  Future<void> write(String key, String value) =>
      _secure.write(key: key, value: value);
  Future<void> delete(String key) => _secure.delete(key: key);
}
