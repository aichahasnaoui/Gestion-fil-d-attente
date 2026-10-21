import 'package:flutter/foundation.dart';

import '../constants.dart';
import '../storage_service.dart';

class AuthProvider extends ChangeNotifier {
  final _storage = StorageService();
  bool _isLoggedIn = false;

  bool get isLoggedIn => _isLoggedIn;

  Future<void> init() async {
    _isLoggedIn = await _storage.read(kAccessToken) != null;
    notifyListeners();
  }
}
