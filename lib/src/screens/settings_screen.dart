import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:universal_io/io.dart';

import '../providers/providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _customFormKey = GlobalKey<FormState>();
  final _defaultFormKey = GlobalKey<FormState>();
  final _serverUrlController = TextEditingController();
  final _defaultServerUrlController = TextEditingController();
  bool _isLoading = true;
  bool _isScanning = false;
  bool _verboseLogging = false;
  List<String> _discoveredServers = [];
  String? _customServerUrl;
  String? _currentServerUrl;
  String? _defaultServerUrl;

  // Controllers for quick scan range
  final _startIpController = TextEditingController(text: '1');
  final _endIpController = TextEditingController(text: '254');

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _defaultServerUrlController.dispose();
    _startIpController.dispose();
    _endIpController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _isLoading = true;
      _isScanning = true;
    });

    final discoveryService = ref.read(serverDiscoveryServiceProvider);

    // Ensure default server URL is initialized
    await discoveryService.initializeDefaultServerUrl();

    // Get the custom server URL
    final customUrl = await discoveryService.getCustomServerUrl();

    // Get the default server URL
    final defaultUrl = await discoveryService.getDefaultServerUrl();

    // Get the current server URL from the API service
    final currentUrl = ref.read(apiServiceProvider).baseUrl;

    // Discover servers on the local network using the appropriate method based on platform
    final discoveredServers = await discoveryService.getAllDiscoveredServers();

    // Get the current verbose logging setting
    final verboseLogging = discoveryService.verboseLogging;

    setState(() {
      _customServerUrl = customUrl;
      _defaultServerUrl = defaultUrl;
      _currentServerUrl = currentUrl;
      _discoveredServers = discoveredServers;
      _verboseLogging = verboseLogging;

      if (customUrl != null) {
        _serverUrlController.text = customUrl;
      }

      if (defaultUrl != null) {
        _defaultServerUrlController.text = defaultUrl;
      }

      _isScanning = false;
      _isLoading = false;
    });
  }

  Future<void> _saveCustomServerUrl() async {
    if (_customFormKey.currentState!.validate()) {
      final url = _serverUrlController.text.trim();
      final discoveryService = ref.read(serverDiscoveryServiceProvider);

      await discoveryService.saveCustomServerUrl(url);

      // Update the API service with the new URL
      ref.read(apiServiceProvider).updateBaseUrl(url);

      setState(() {
        _customServerUrl = url;
        _currentServerUrl = url;
      });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Server URL saved')));
      }
    }
  }

  Future<void> _clearCustomServerUrl() async {
    final discoveryService = ref.read(serverDiscoveryServiceProvider);

    await discoveryService.clearCustomServerUrl();

    // Get the best server URL after clearing the custom URL
    final bestUrl = await discoveryService.getBestServerUrl();

    // Update the API service with the best URL
    ref.read(apiServiceProvider).updateBaseUrl(bestUrl);

    setState(() {
      _customServerUrl = null;
      _currentServerUrl = bestUrl;
      _serverUrlController.clear();
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Using automatic server discovery')),
      );
    }
  }

  Future<void> _saveDefaultServerUrl() async {
    if (_defaultFormKey.currentState!.validate()) {
      final url = _defaultServerUrlController.text.trim();
      final discoveryService = ref.read(serverDiscoveryServiceProvider);

      await discoveryService.saveDefaultServerUrl(url);

      // If no custom URL is set, update the API service with the new default URL
      if (_customServerUrl == null || _customServerUrl!.isEmpty) {
        final bestUrl = await discoveryService.getBestServerUrl();
        ref.read(apiServiceProvider).updateBaseUrl(bestUrl);
        setState(() {
          _currentServerUrl = bestUrl;
        });
      }

      setState(() {
        _defaultServerUrl = url;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Default server URL saved')),
        );
      }
    }
  }

  Future<void> _resetDefaultServerUrl() async {
    final discoveryService = ref.read(serverDiscoveryServiceProvider);

    // Clear the default server URL
    await discoveryService.clearDefaultServerUrl();

    // Re-initialize with platform-specific defaults
    await discoveryService.initializeDefaultServerUrl();

    // Get the new default URL
    final defaultUrl = await discoveryService.getDefaultServerUrl();

    // If no custom URL is set, update the API service with the new default URL
    if (_customServerUrl == null || _customServerUrl!.isEmpty) {
      final bestUrl = await discoveryService.getBestServerUrl();
      ref.read(apiServiceProvider).updateBaseUrl(bestUrl);
      setState(() {
        _currentServerUrl = bestUrl;
      });
    }

    setState(() {
      _defaultServerUrl = defaultUrl;
      if (defaultUrl != null) {
        _defaultServerUrlController.text = defaultUrl;
      }
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Default server URL reset to platform default'),
        ),
      );
    }
  }

  Future<void> _refreshServers() async {
    await _loadSettings();

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Server list refreshed')));
    }
  }

  Future<void> _quickScan() async {
    // Validate input
    int? startIp = int.tryParse(_startIpController.text);
    int? endIp = int.tryParse(_endIpController.text);

    if (startIp == null ||
        endIp == null ||
        startIp < 1 ||
        startIp > 254 ||
        endIp < 1 ||
        endIp > 254 ||
        startIp > endIp) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter valid IP range (1-254)')),
      );
      return;
    }

    setState(() {
      _isScanning = true;
      _discoveredServers = [];
    });

    final discoveryService = ref.read(serverDiscoveryServiceProvider);

    // Perform the scan with the specified range
    final discoveredServers = await discoveryService.getAllDiscoveredServers(
      ipRange: [startIp, endIp],
    );

    setState(() {
      _discoveredServers = discoveredServers;
      _isScanning = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            discoveredServers.isEmpty
                ? 'No servers found in the specified range'
                : 'Found ${discoveredServers.length} server(s)',
          ),
        ),
      );
    }
  }

  Future<void> _useDiscoveredServer(String url) async {
    final discoveryService = ref.read(serverDiscoveryServiceProvider);

    // Save the discovered server as the custom server
    await discoveryService.saveCustomServerUrl(url);

    // Update the API service with the new URL
    ref.read(apiServiceProvider).updateBaseUrl(url);

    setState(() {
      _customServerUrl = url;
      _currentServerUrl = url;
      _serverUrlController.text = url;
    });

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Using selected server')));
    }
  }

  // Toggle verbose logging for server discovery
  void _toggleVerboseLogging(bool value) {
    final discoveryService = ref.read(serverDiscoveryServiceProvider);
    discoveryService.setVerboseLogging(value);

    setState(() {
      _verboseLogging = value;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Verbose logging ${value ? 'enabled' : 'disabled'}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _clearAppData() async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Clear App Data'),
            content: const Text(
              'This will clear all app data including login information. '
              'You will need to log in again. Are you sure?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                child: const Text('Clear Data'),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      // Clear all app data
      await ref.read(authServiceProvider).clearAllData();

      // Log out the user
      await ref.read(authStateProvider.notifier).logout();

      if (mounted) {
        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('App data cleared successfully')),
        );

        // Navigate to login screen
        context.go('/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Server Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Servers',
            onPressed: _refreshServers,
          ),
        ],
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Current server info
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Current Server',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(_currentServerUrl ?? 'Not connected'),
                            const SizedBox(height: 8),
                            Text(
                              _customServerUrl != null
                                  ? 'Using custom server'
                                  : 'Using automatic discovery',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.secondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Custom server form
                    Form(
                      key: _customFormKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Custom Server URL',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'This overrides all other server discovery methods',
                            style: TextStyle(
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _serverUrlController,
                            decoration: const InputDecoration(
                              hintText: 'http://example.com:8080',
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter a server URL';
                              }
                              if (!value.startsWith('http://') &&
                                  !value.startsWith('https://')) {
                                return 'URL must start with http:// or https://';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              ElevatedButton(
                                onPressed: _saveCustomServerUrl,
                                child: const Text('Save'),
                              ),
                              const SizedBox(width: 16),
                              OutlinedButton(
                                onPressed: _clearCustomServerUrl,
                                child: const Text('Use Automatic Discovery'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Default server form
                    Form(
                      key: _defaultFormKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Default Server URL',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Used when no custom URL is set and no servers are discovered',
                            style: TextStyle(
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _defaultServerUrlController,
                            decoration: const InputDecoration(
                              hintText: 'http://192.168.1.100:8080',
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter a server URL';
                              }
                              if (!value.startsWith('http://') &&
                                  !value.startsWith('https://')) {
                                return 'URL must start with http:// or https://';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              ElevatedButton(
                                onPressed: _saveDefaultServerUrl,
                                child: const Text('Save Default'),
                              ),
                              const SizedBox(width: 16),
                              OutlinedButton(
                                onPressed: _resetDefaultServerUrl,
                                child: const Text('Reset to Platform Default'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Discovered servers list
                    Row(
                      children: [
                        const Text(
                          'Discovered Servers',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (_isScanning) ...[
                          const SizedBox(width: 16),
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Scanning network...',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.secondary,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0, bottom: 8.0),
                      child: Text(
                        Platform.isAndroid
                            ? 'Using network scanning on Android (may take longer)'
                            : 'Using mDNS discovery',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.secondary,
                          fontSize: 12,
                        ),
                      ),
                    ),

                    // Quick scan UI (only show on Android)
                    if (Platform.isAndroid) ...[
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Quick Scan',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Scan a specific IP range to find servers faster',
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: _startIpController,
                                      decoration: const InputDecoration(
                                        labelText: 'Start IP',
                                        hintText: '1',
                                        border: OutlineInputBorder(),
                                      ),
                                      keyboardType: TextInputType.number,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  const Text('to'),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: TextFormField(
                                      controller: _endIpController,
                                      decoration: const InputDecoration(
                                        labelText: 'End IP',
                                        hintText: '254',
                                        border: OutlineInputBorder(),
                                      ),
                                      keyboardType: TextInputType.number,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: _isScanning ? null : _quickScan,
                                icon: const Icon(Icons.search),
                                label: const Text('Quick Scan'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    const SizedBox(height: 8),
                    _isScanning && _discoveredServers.isEmpty
                        ? const Card(
                          child: Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Text('Scanning the network for servers...'),
                          ),
                        )
                        : _discoveredServers.isEmpty
                        ? const Card(
                          child: Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Text(
                              'No servers discovered on the local network',
                            ),
                          ),
                        )
                        : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _discoveredServers.length,
                          itemBuilder: (context, index) {
                            final server = _discoveredServers[index];
                            return Card(
                              child: ListTile(
                                title: Text(server),
                                trailing: IconButton(
                                  icon: const Icon(Icons.check_circle_outline),
                                  onPressed: () => _useDiscoveredServer(server),
                                  tooltip: 'Use this server',
                                ),
                              ),
                            );
                          },
                        ),

                    const SizedBox(height: 24),

                    // App Data section
                    const Text(
                      'App Data',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Verbose Logging Card
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Debug Settings',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Enable verbose logging to help troubleshoot server discovery issues.',
                            ),
                            SwitchListTile(
                              title: const Text('Verbose Logging'),
                              subtitle: Text(
                                _verboseLogging
                                    ? 'Detailed logs will be shown during server discovery'
                                    : 'Only essential logs will be shown',
                                style: TextStyle(
                                  fontSize: 12,
                                  color:
                                      Theme.of(context).colorScheme.secondary,
                                ),
                              ),
                              value: _verboseLogging,
                              onChanged: _toggleVerboseLogging,
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Clear App Data Card
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Clear all app data including login information and cached settings.',
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: _clearAppData,
                              icon: const Icon(Icons.delete_forever),
                              label: const Text('Clear App Data'),
                              style: ElevatedButton.styleFrom(
                                foregroundColor:
                                    Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
    );
  }
}
