import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _serverUrlController = TextEditingController();
  bool _isLoading = true;
  List<String> _discoveredServers = [];
  String? _customServerUrl;
  String? _currentServerUrl;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _isLoading = true;
    });

    final discoveryService = ref.read(serverDiscoveryServiceProvider);

    // Get the custom server URL
    final customUrl = await discoveryService.getCustomServerUrl();

    // Get the current server URL from the API service
    final currentUrl = ref.read(apiServiceProvider).baseUrl;

    // Discover servers on the local network
    final discoveredServers = await discoveryService.discoverServers();

    setState(() {
      _customServerUrl = customUrl;
      _currentServerUrl = currentUrl;
      _discoveredServers = discoveredServers;

      if (customUrl != null) {
        _serverUrlController.text = customUrl;
      }

      _isLoading = false;
    });
  }

  Future<void> _saveCustomServerUrl() async {
    if (_formKey.currentState!.validate()) {
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

  Future<void> _refreshServers() async {
    await _loadSettings();

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Server list refreshed')));
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Server Settings'),
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
                      key: _formKey,
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

                    // Discovered servers list
                    const Text(
                      'Discovered Servers',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _discoveredServers.isEmpty
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
                  ],
                ),
              ),
    );
  }
}
