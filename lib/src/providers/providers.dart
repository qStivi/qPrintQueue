import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/print_job.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/server_discovery_service.dart';

// Service providers
final serverDiscoveryServiceProvider = Provider(
  (ref) => ServerDiscoveryService(),
);

// API service provider that uses server discovery
final apiServiceProvider = Provider((ref) {
  // Create a placeholder API service with a temporary URL
  // The actual URL will be updated when server discovery completes
  final apiService = ApiService(baseUrl: 'http://localhost:8080');

  // Get the server discovery service
  final discoveryService = ref.read(serverDiscoveryServiceProvider);

  // Start server discovery and update the API service when it completes
  discoveryService.getBestServerUrl().then((url) {
    apiService.updateBaseUrl(url);
  });

  return apiService;
});

final authServiceProvider = Provider((ref) {
  final apiService = ref.watch(apiServiceProvider);
  return AuthService(apiService: apiService);
});

// Auth state provider
final authStateProvider = StateNotifierProvider<AuthNotifier, bool>((ref) {
  final authService = ref.watch(authServiceProvider);
  return AuthNotifier(authService);
});

class AuthNotifier extends StateNotifier<bool> {
  final AuthService _authService;

  AuthNotifier(this._authService) : super(false) {
    checkAuth();
  }

  Future<void> checkAuth() async {
    state = await _authService.isLoggedIn();
  }

  Future<bool> login(String password) async {
    final success = await _authService.login(password);
    state = success;
    return success;
  }

  Future<void> logout() async {
    await _authService.logout();
    state = false;
  }
}

// Sort mode provider
final sortModeProvider = StateProvider<String>((ref) => 'priority');

// Jobs provider
final jobsProvider = FutureProvider<List<PrintJob>>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  final sortMode = ref.watch(sortModeProvider);
  return apiService.getJobs(sort: sortMode);
});

// Selected job provider for editing
final selectedJobProvider = StateProvider<PrintJob?>((ref) => null);
