import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:universal_io/io.dart';

import '../models/print_job.dart';
import '../providers/providers.dart';
import '../widgets/progress_dialog.dart';

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

  // File metadata
  String? _fileName;
  String? _fileMimeType;
  int? _fileSize;
  String? _fileData; // Base64 encoded file data
  bool _isUploading = false;
  final _uploadProgressController = StreamController<double>();

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

      // Load file metadata if available
      _fileName = selectedJob.fileName;
      _fileMimeType = selectedJob.fileMimeType;
      _fileSize = selectedJob.fileSize;
      _fileData = selectedJob.fileData;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _fileUrlController.dispose();
    _descriptionController.dispose();
    _uploadProgressController.close();
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
        fileName: _fileName,
        fileMimeType: _fileMimeType,
        fileSize: _fileSize,
        fileData: _fileData,
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
              _isUploading = true;
            });

            final file = File(path);
            final fileName = path
                .split('/')
                .last;

            // Show upload progress dialog
            if (mounted) {
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) =>
                    UploadProgressDialog(
                      fileName: fileName,
                      progressStream: _uploadProgressController.stream,
                    ),
              );
            }

            try {
              // Read file data and encode as base64
              final fileBytes = await file.readAsBytes();
              final base64FileData = base64Encode(fileBytes);

              // Upload file to server
              final apiService = ref.read(apiServiceProvider);
              final uploadResult = await apiService.uploadFile(
                file,
                onProgress: (progress) {
                  _uploadProgressController.add(progress);
                },
              );

              if (uploadResult['success'] == true) {
                setState(() {
                  // Store file metadata
                  _fileName = uploadResult['file_name'];
                  _fileMimeType = uploadResult['file_mime_type'];
                  _fileSize = uploadResult['file_size'];
                  _fileData =
                      base64FileData; // Store the base64 encoded file data

                  // Keep the file path for display purposes
                  _fileUrlController.text = path;
                });

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(
                        'File uploaded successfully: $_fileName')),
                  );
                }
              } else {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(
                        'Upload failed: ${uploadResult['error'] ??
                            "Unknown error"}')),
                  );
                }
              }
            } finally {
              // Close the progress dialog
              if (mounted) {
                Navigator.of(context).pop();
              }
            }
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
          final bytes = result.files.single.bytes;

          if (bytes != null) {
            setState(() {
              _isUploading = true;
            });

            // Show upload progress dialog
            if (mounted) {
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) =>
                    UploadProgressDialog(
                      fileName: fileName,
                      progressStream: _uploadProgressController.stream,
                    ),
              );
            }

            // Simulate progress for web (since we can't track it)
            for (int i = 1; i <= 10; i++) {
              await Future.delayed(const Duration(milliseconds: 100));
              _uploadProgressController.add(i / 10);
            }

            setState(() {
              // Store file metadata
              _fileName = fileName;
              _fileMimeType = 'application/octet-stream'; // Default for web
              _fileSize = bytes.length;
              _fileData =
                  base64Encode(bytes); // Store the base64 encoded file data

              // Keep the file name for display purposes
              _fileUrlController.text = fileName;
            });

            // Close the progress dialog
            if (mounted) {
              Navigator.of(context).pop();

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Note: On web, file data is stored directly due to platform limitations',
                  ),
                  duration: Duration(seconds: 5),
                ),
              );
            }
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
    } finally {
      setState(() {
        _isUploading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNewJob = widget.jobId == null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isNewJob ? 'Add New Job' : 'Edit Job'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
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
