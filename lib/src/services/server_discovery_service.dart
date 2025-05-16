import 'dart:async';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:multicast_dns/multicast_dns.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_io/io.dart';

// A simple semaphore implementation to limit concurrent operations
class Semaphore {
  final int _maxCount;
  int _currentCount = 0;
  final List<Completer<void>> _waiters = [];

  Semaphore(this._maxCount);

  Future<void> acquire() async {
    if (_currentCount < _maxCount) {
      _currentCount++;
      return Future.value();
    }

    final completer = Completer<void>();
    _waiters.add(completer);
    return completer.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      final completer = _waiters.removeAt(0);
      completer.complete();
    } else {
      _currentCount--;
    }
  }
}

class ServerDiscoveryService {
  static const String _customServerKey = 'custom_server_url';
  static const String _defaultServerKey = 'default_server_url';
  static const String _serviceType = '_printqueue._tcp';

  // Flag to control verbose logging during network scanning
  bool verboseLogging = false;

  // Enable or disable verbose logging
  void setVerboseLogging(bool enabled) {
    verboseLogging = enabled;
    print('Verbose logging ${enabled
        ? 'enabled'
        : 'disabled'} for server discovery');
  }

  // Note: The API server is no longer advertising itself using mDNS due to package limitations.
  // This discovery method will only work if the server is using a different implementation for service advertisement.
  // For now, clients should rely on the custom server URL or the default localhost URL.

  // Discover servers on the local network using mDNS (non-Android platforms)
  Future<List<String>> discoverServers() async {
    final List<String> servers = [];

    // Skip mDNS discovery on Android platforms as reusePort is not supported
    if (Platform.isAndroid) {
      print('Skipping mDNS discovery on Android platform');
      return servers;
    }

    final MDnsClient client = MDnsClient();

    try {
      await client.start();

      // Look for print queue servers
      await for (final PtrResourceRecord ptr in client.lookup<PtrResourceRecord>(
        ResourceRecordQuery.serverPointer(_serviceType),
      )) {
        await for (final SrvResourceRecord srv in client.lookup<SrvResourceRecord>(
          ResourceRecordQuery.service(ptr.domainName),
        )) {
          // Get the IP address
          await for (final IPAddressResourceRecord ip in client.lookup<IPAddressResourceRecord>(
            ResourceRecordQuery.addressIPv4(srv.target),
          )) {
            final String serverUrl = 'http://${ip.address.address}:${srv.port}';
            if (!servers.contains(serverUrl)) {
              servers.add(serverUrl);
            }
          }
        }
      }
    } catch (e) {
      print('mDNS discovery error: $e');
      // Continue with empty server list if discovery fails
    } finally {
      client.stop();
    }

    return servers;
  }

  // Get all discovered servers using the appropriate method based on platform
  Future<List<String>> getAllDiscoveredServers({List<int>? ipRange}) async {
    List<String> servers = [];

    if (Platform.isAndroid) {
      print('Using network scanning for discovery on Android');
      servers = await scanNetworkForServer(ipRange: ipRange);
    } else {
      print('Using mDNS for discovery on non-Android platform');
      servers = await discoverServers();
    }

    return servers;
  }

  // Get the custom server URL from SharedPreferences
  Future<String?> getCustomServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_customServerKey);
  }

  // Save a custom server URL to SharedPreferences
  Future<void> saveCustomServerUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_customServerKey, url);
  }

  // Clear the custom server URL from SharedPreferences
  Future<void> clearCustomServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_customServerKey);
  }

  // Get the default server URL from SharedPreferences
  Future<String?> getDefaultServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_defaultServerKey);
  }

  // Save a default server URL to SharedPreferences
  Future<void> saveDefaultServerUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_defaultServerKey, url);
  }

  // Clear the default server URL from SharedPreferences
  Future<void> clearDefaultServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_defaultServerKey);
  }

  // Scan the local network for the server (Android-compatible)
  // If ipRange is provided, only scan that specific range (e.g., [192, 200] to scan .192 to .200)
  Future<List<String>> scanNetworkForServer({List<int>? ipRange}) async {
    final List<String> discoveredServers = [];
    final info = NetworkInfo();

    try {
      // Get the WiFi IP address
      final wifiIP = await info.getWifiIP();
      if (wifiIP == null) {
        print('Could not get WiFi IP address');
        return discoveredServers;
      }

      print('Device IP address: $wifiIP');

      // Parse the IP address to get the subnet
      final ipParts = wifiIP.split('.');
      if (ipParts.length != 4) {
        print('Invalid IP address format: $wifiIP');
        return discoveredServers;
      }

      // Create the subnet prefix (e.g., 192.168.1)
      final subnetPrefix = '${ipParts[0]}.${ipParts[1]}.${ipParts[2]}';

      // Define the port to scan
      const port = 8080;

      // Create a list of futures for parallel scanning
      final futures = <Future<void>>[];

      // Limit the number of concurrent requests to avoid overwhelming the device
      final semaphore = Semaphore(20);

      // Define endpoints to check
      final endpoints = ['/jobs', '/auth/login'];

      // Determine the IP range to scan
      int startIp = 1;
      int endIp = 254;

      if (ipRange != null && ipRange.length == 2) {
        startIp = ipRange[0].clamp(1, 254);
        endIp = ipRange[1].clamp(1, 254);
        if (verboseLogging) {
          print('Scanning limited IP range: $startIp to $endIp');
        }
      }

      // Scan the subnet (using the specified range or default 1-254)
      for (int i = startIp; i <= endIp; i++) {
        futures.add(semaphore.acquire().then((_) async {
          final ipToCheck = '$subnetPrefix.$i';
          final baseUrl = 'http://$ipToCheck:$port';

          // Skip the device's own IP
          if (ipToCheck == wifiIP) {
            return;
          }

          // Try each endpoint
          for (final endpoint in endpoints) {
            try {
              final url = '$baseUrl$endpoint';
              if (verboseLogging) {
                print('Checking: $url');
              }

              // Try to connect with a longer timeout
              final response = await http.get(
                Uri.parse(url),
                headers: {'Accept': 'application/json'},
              ).timeout(const Duration(milliseconds: 1000));

              // Check for various status codes that might indicate our server
              if (response.statusCode == 200 ||
                  response.statusCode == 401 ||
                  response.statusCode == 403 ||
                  response.statusCode == 404) {
                print('Found potential server at: $baseUrl (status: ${response
                    .statusCode})');
                if (!discoveredServers.contains(baseUrl)) {
                  discoveredServers.add(baseUrl);
                }
                // No need to check other endpoints if we found a match
                break;
              }
            } catch (e) {
              // Log connection errors for debugging
              if (verboseLogging) {
                print(
                    'Error checking $baseUrl$endpoint: ${e.toString().substring(
                        0, min(50, e
                        .toString()
                        .length))}...');
              }
            }
          }

          semaphore.release();
        }));
      }

      // Wait for all scans to complete
      await Future.wait(futures);

      print('Network scan complete. Found ${discoveredServers
          .length} potential servers.');
    } catch (e) {
      print('Network scanning error: $e');
    }

    return discoveredServers;
  }

  // Initialize default server URL if not already set
  Future<void> initializeDefaultServerUrl() async {
    final defaultUrl = await getDefaultServerUrl();
    if (defaultUrl == null || defaultUrl.isEmpty) {
      // Set a platform-specific default URL
      if (Platform.isAndroid) {
        // For Android, use the known server IP
        await saveDefaultServerUrl('http://192.168.128.32:8080');
        print(
            'Initialized default server URL for Android: http://192.168.128.32:8080');
      } else {
        // For other platforms, use localhost
        await saveDefaultServerUrl('http://localhost:8080');
        print(
            'Initialized default server URL for non-Android: http://localhost:8080');
      }
    }
  }

  // Get the best server URL to use
  // Priority: 1. Custom URL, 2. Discovered server, 3. Saved default URL, 4. Platform-specific fallback
  Future<String> getBestServerUrl() async {
    // Ensure default server URL is initialized
    await initializeDefaultServerUrl();

    // Check for custom server URL
    final customUrl = await getCustomServerUrl();
    if (customUrl != null && customUrl.isNotEmpty) {
      print('Using custom server URL: $customUrl');
      return customUrl;
    }

    // Use different discovery methods based on platform
    try {
      List<String> discoveredServers = [];

      if (Platform.isAndroid) {
        print('Using network scanning for discovery on Android');
        discoveredServers = await scanNetworkForServer();
      } else {
        print('Using mDNS for discovery on non-Android platform');
        discoveredServers = await discoverServers();
      }

      if (discoveredServers.isNotEmpty) {
        print('Using discovered server: ${discoveredServers.first}');
        return discoveredServers.first;
      }
    } catch (e) {
      print('Server discovery failed: $e');
    }

    // Get the saved default server URL
    final defaultUrl = await getDefaultServerUrl();
    if (defaultUrl != null && defaultUrl.isNotEmpty) {
      print('No servers discovered, using saved default URL: $defaultUrl');
      return defaultUrl;
    }

    // Final fallback (should never reach here due to initialization)
    final fallbackUrl = Platform.isAndroid
        ? 'http://192.168.128.32:8080'
        : 'http://localhost:8080';
    print('No saved default URL found, using fallback: $fallbackUrl');
    return fallbackUrl;
  }
}
