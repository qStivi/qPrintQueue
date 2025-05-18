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

  String getMimeTypeFromExtension(String? ext) {
    switch (ext?.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'pdf':
        return 'application/pdf';
      case 'doc':
      case 'docx':
        return 'application/msword';
      // Add more as needed
      default:
        return 'application/octet-stream';
    }
  }

  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true, // Always get bytes for web
        allowMultiple: false,
        dialogTitle: 'Select Any File',
      );

      if (result != null) {
        final file = result.files.single;
        final fileName = file.name;
        final filePath = file.path; // will be null on web
        final fileBytes = file.bytes;
        final fileExtension = file.extension;
        final fileMimeType = getMimeTypeFromExtension(fileExtension);

        setState(() {
          _isUploading = true;
        });

        // Show upload progress dialog
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder:
                (context) => UploadProgressDialog(
                  fileName: fileName,
                  progressStream: _uploadProgressController.stream,
                ),
          );
        }

        try {
          String base64FileData;
          int fileSize;

          if (kIsWeb) {
            // --- WEB BRANCH: Never use File ---
            if (fileBytes != null) {
              base64FileData = base64Encode(fileBytes);
              fileSize = fileBytes.length;

              setState(() {
                _fileName = fileName;
                _fileMimeType = fileMimeType;
                _fileSize = fileSize;
                _fileData = base64FileData;
                _fileUrlController.text = fileName;
              });

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'File selected: $fileName. On web, file data is stored in memory.',
                    ),
                  ),
                );
              }
            } else {
              throw Exception('No file data found on web');
            }
          } else {
            // --- IO BRANCH: Use File ---
            if (filePath != null) {
              // Don't even try to import or use File on web.
              final fileObj = File(filePath);
              final bytes = await fileObj.readAsBytes();
              base64FileData = base64Encode(bytes);
              fileSize = bytes.length;

              final apiService = ref.read(apiServiceProvider);
              final uploadResult = await apiService.uploadFile(
                fileObj,
                onProgress: (progress) {
                  _uploadProgressController.add(progress);
                },
              );

              if (uploadResult['success'] == true) {
                setState(() {
                  _fileName = uploadResult['file_name'] ?? fileName;
                  _fileMimeType =
                      uploadResult['file_mime_type'] ?? fileMimeType;
                  _fileSize = uploadResult['file_size'] ?? fileSize;
                  _fileData = base64FileData;
                  _fileUrlController.text = filePath;
                });

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('File uploaded successfully: $_fileName'),
                    ),
                  );
                }
              } else {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Upload failed: ${uploadResult['error'] ?? "Unknown error"}',
                      ),
                    ),
                  );
                }
              }
            } else {
              throw Exception('No file path found');
            }
          }
        } finally {
          if (mounted) {
            Navigator.of(context).pop();
          }
        }
      }
    } catch (e) {
      String errorMessage = 'Error picking file: ${e.toString()}';
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
