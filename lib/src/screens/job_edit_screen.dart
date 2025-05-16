import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:universal_io/io.dart';

import '../models/print_job.dart';
import '../providers/providers.dart';

// ignore_for_file: unused_result
class JobEditScreen extends ConsumerStatefulWidget {
  final int? jobId;

  const JobEditScreen({super.key, this.jobId});

  @override
  ConsumerState<JobEditScreen> createState() => _JobEditScreenState();
}

class _JobEditScreenState extends ConsumerState<JobEditScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _fileUrlController = TextEditingController();
  final _descriptionController = TextEditingController();

  DateTime _scheduledDate = DateTime.now();
  int _priority = 0;
  bool _isLoading = false;

  PrintJob? _originalJob;

  @override
  void initState() {
    super.initState();

    // If we're editing an existing job, load its data
    if (widget.jobId != null) {
      _loadJob();
    }
  }

  void _loadJob() {
    final selectedJob = ref.read(selectedJobProvider);
    if (selectedJob != null && selectedJob.id == widget.jobId) {
      _originalJob = selectedJob;
      _nameController.text = selectedJob.name;
      _fileUrlController.text = selectedJob.fileUrl;
      _descriptionController.text = selectedJob.description ?? '';
      _scheduledDate = selectedJob.scheduledAt;
      _priority = selectedJob.priority;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _fileUrlController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _saveJob() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final apiService = ref.read(apiServiceProvider);

      final job = PrintJob(
        id: _originalJob?.id,
        name: _nameController.text,
        fileUrl: _fileUrlController.text,
        priority: _priority,
        scheduledAt: _scheduledDate,
        description:
            _descriptionController.text.isEmpty
                ? null
                : _descriptionController.text,
        status: _originalJob?.status ?? 'pending',
        orderIndex: _originalJob?.orderIndex,
      );

      bool success;
      if (_originalJob == null) {
        // Create new job
        success = await apiService.createJob(job);
      } else {
        // Update existing job
        success = await apiService.updateJob(job);
      }

      if (success && mounted) {
        // Refresh jobs list and navigate back
        ref.refresh(jobsProvider);
        context.go('/');
      } else if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to save job')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _scheduledDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked != null && picked != _scheduledDate) {
      setState(() {
        _scheduledDate = picked;
      });
    }
  }

  Future<void> _pickFile() async {
    try {
      // Platform-specific file picking logic
      if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
        // Use file_picker with platform-specific options
        FilePickerResult? result = await FilePicker.platform.pickFiles(
          type: FileType.any,
          dialogTitle: 'Select Any File',
          // Avoid using deprecated APIs
          withData: false,
          withReadStream: false,
          allowMultiple: false,
        );

        if (result != null) {
          final path = result.files.single.path;
          if (path != null) {
            setState(() {
              _fileUrlController.text = path;
            });
          }
        }
      } else if (kIsWeb) {
        // Web platform has limitations with file paths
        // Use a more compatible approach for web
        FilePickerResult? result = await FilePicker.platform.pickFiles(
          type: FileType.any,
          // For web, we need the bytes or name since paths aren't available
          withData: true,
          allowMultiple: false,
        );

        if (result != null) {
          final fileName = result.files.single.name;
          setState(() {
            _fileUrlController.text = fileName;
          });

          // Show a note about web limitations
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Note: On web, only the filename is stored due to platform limitations',
                ),
                duration: Duration(seconds: 5),
              ),
            );
          }
        }
      } else {
        // Fallback for other platforms
        // Prompt user to enter path manually
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'File picking not fully supported on this platform. Please enter the file path manually.',
              ),
              duration: Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (e) {
      // Improved error handling with more specific messages
      String errorMessage = 'Error picking file: ${e.toString()}';

      if (e.toString().contains('MissingPluginException')) {
        errorMessage =
            'File picker plugin not available on this platform. Please enter the file path manually.';
      } else if (e.toString().contains('Unsupported operation')) {
        errorMessage =
            'File picking is not supported on this platform. Please enter the file path manually.';
      }

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMessage)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNewJob = widget.jobId == null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isNewJob ? 'Add New Job' : 'Edit Job'),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _saveJob,
            child:
                _isLoading
                    ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Text('Save'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Job Name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _fileUrlController,
                        decoration: InputDecoration(
                          labelText: 'File URL',
                          border: const OutlineInputBorder(),
                          hintText: 'Path to any file',
                          helperText:
                              kIsWeb
                                  ? 'On web, only filename will be stored'
                                  : Platform.isAndroid ||
                                      Platform.isIOS ||
                                      Platform.isMacOS
                                  ? 'Select any file type'
                                  : 'Enter file path manually on this platform',
                          helperMaxLines: 2,
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter a file URL';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.file_open),
                      tooltip:
                          kIsWeb
                              ? 'Choose Any File (Web limitations apply)'
                              : Platform.isAndroid ||
                                  Platform.isIOS ||
                                  Platform.isMacOS
                              ? 'Choose Any File'
                              : 'File picking may not work on this platform',
                      onPressed: _pickFile,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Priority',
                          border: OutlineInputBorder(),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int>(
                            value: _priority,
                            onChanged: (int? newValue) {
                              if (newValue != null) {
                                setState(() {
                                  _priority = newValue;
                                });
                              }
                            },
                            items: [
                              for (int i = 0; i <= 10; i++)
                                DropdownMenuItem<int>(
                                  value: i,
                                  child: Text(i.toString()),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: InkWell(
                        onTap: () => _selectDate(context),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Scheduled Date',
                            border: OutlineInputBorder(),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${_scheduledDate.year}-${_scheduledDate.month.toString().padLeft(2, '0')}-${_scheduledDate.day.toString().padLeft(2, '0')}',
                              ),
                              const Icon(Icons.calendar_today),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description (Optional)',
                    border: OutlineInputBorder(),
                    hintText: 'Enter any additional details',
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
