import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';

class AuthService {
  final ApiService apiService;
  static const String _authKey = 'auth_token';

  AuthService({required this.apiService});

  Future<bool> login(String password) async {
    final success = await apiService.login(password);
    if (success) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_authKey, password);
    }
    return success;
  }

  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_authKey);
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_authKey);
  }

  /// Clears all app data including login information
  Future<void> clearAllData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
