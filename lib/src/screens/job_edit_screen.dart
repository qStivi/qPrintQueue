import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
        description: _descriptionController.text.isEmpty 
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save job')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
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
  
  @override
  Widget build(BuildContext context) {
    final isNewJob = widget.jobId == null;
    
    return Scaffold(
      appBar: AppBar(
        title: Text(isNewJob ? 'Add New Job' : 'Edit Job'),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _saveJob,
            child: _isLoading
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
                TextFormField(
                  controller: _fileUrlController,
                  decoration: const InputDecoration(
                    labelText: 'File URL',
                    border: OutlineInputBorder(),
                    hintText: 'Path to .bambu or sliced file',
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a file URL';
                    }
                    return null;
                  },
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