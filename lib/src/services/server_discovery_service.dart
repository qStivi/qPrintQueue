import 'dart:async';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ServerDiscoveryService {
  static const String _customServerKey = 'custom_server_url';
  static const String _serviceType = '_printqueue._tcp';

  // Note: The API server is no longer advertising itself using mDNS due to package limitations.
  // This discovery method will only work if the server is using a different implementation for service advertisement.
  // For now, clients should rely on the custom server URL or the default localhost URL.

  // Discover servers on the local network
  Future<List<String>> discoverServers() async {
    final List<String> servers = [];
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
    } finally {
      client.stop();
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

  // Get the best server URL to use
  // Priority: 1. Custom URL, 2. Default localhost, 3. Discovered server (if any)
  // Note: Discovery is unlikely to work since the server is no longer advertising itself
  Future<String> getBestServerUrl() async {
    // Check for custom server URL
    final customUrl = await getCustomServerUrl();
    if (customUrl != null && customUrl.isNotEmpty) {
      return customUrl;
    }

    // Use localhost as the default
    final defaultUrl = 'http://localhost:8080';

    // Try to discover servers on the local network as a last resort
    // This is unlikely to work since the server is no longer advertising itself
    try {
      final discoveredServers = await discoverServers();
      if (discoveredServers.isNotEmpty) {
        return discoveredServers.first;
      }
    } catch (e) {
      print('Server discovery failed: $e');
    }

    // Fall back to localhost
    return defaultUrl;
  }
}
