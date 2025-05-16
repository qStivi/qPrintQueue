import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/print_job.dart';
import '../providers/providers.dart';
import '../services/api_service.dart';
import '../widgets/job_item.dart';

// ignore_for_file: unused_result
class JobListScreen extends ConsumerWidget {
  const JobListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sortMode = ref.watch(sortModeProvider);
    final jobsAsync = ref.watch(jobsProvider);
    final apiService = ref.watch(apiServiceProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('3D Print Queue'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () {
              ref.refresh(jobsProvider);
            },
          ),
          _buildSortButton(context, ref, sortMode),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () {
              context.go('/settings');
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () {
              ref.read(authStateProvider.notifier).logout();
            },
          ),
        ],
      ),
      body: jobsAsync.when(
        data: (jobs) => _buildJobList(context, ref, jobs, sortMode, apiService),
        loading: () => const Center(child: CircularProgressIndicator()),
        error:
            (error, stackTrace) => Center(
              child: Text(
                'Error loading jobs: ${error.toString()}',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          ref.read(selectedJobProvider.notifier).state = null;
          context.go('/job');
        },
        tooltip: 'Add Job',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildSortButton(
    BuildContext context,
    WidgetRef ref,
    String currentSort,
  ) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.sort),
      tooltip: 'Sort by',
      onSelected: (String sort) {
        ref.read(sortModeProvider.notifier).state = sort;
      },
      itemBuilder:
          (BuildContext context) => <PopupMenuEntry<String>>[
            const PopupMenuItem<String>(
              value: 'priority',
              child: Text('Sort by Priority'),
            ),
            const PopupMenuItem<String>(
              value: 'date',
              child: Text('Sort by Date'),
            ),
            const PopupMenuItem<String>(
              value: 'name',
              child: Text('Sort by Name'),
            ),
            const PopupMenuItem<String>(
              value: 'custom',
              child: Text('Custom Order'),
            ),
          ],
    );
  }

  Widget _buildJobList(
    BuildContext context,
    WidgetRef ref,
    List<PrintJob> jobs,
    String sortMode,
    ApiService apiService,
  ) {
    if (jobs.isEmpty) {
      return const Center(
        child: Text('No print jobs found. Add your first job!'),
      );
    }

    // Function to refresh jobs
    Future<void> refreshJobs() async {
      ref.refresh(jobsProvider);
    }

    if (sortMode == 'custom') {
      return RefreshIndicator(
        onRefresh: refreshJobs,
        child: ReorderableListView.builder(
          itemCount: jobs.length,
          itemBuilder: (context, index) {
            final job = jobs[index];
            return _buildJobItem(
              context,
              ref,
              job,
              apiService,
              key: ValueKey(job.id),
            );
          },
          onReorder: (oldIndex, newIndex) async {
            if (oldIndex < newIndex) {
              newIndex -= 1;
            }

            final List<Map<String, dynamic>> updates = [];

            for (int i = 0; i < jobs.length; i++) {
              int newOrderIndex;

              if (i == oldIndex) {
                newOrderIndex = newIndex;
              } else if (i < oldIndex && i < newIndex) {
                newOrderIndex = i;
              } else if (i > oldIndex && i > newIndex) {
                newOrderIndex = i;
              } else if (i < oldIndex && i >= newIndex) {
                newOrderIndex = i + 1;
              } else {
                newOrderIndex = i - 1;
              }

              updates.add({'id': jobs[i].id, 'order_index': newOrderIndex});
            }

            await apiService.reorderJobs(updates);
            ref.refresh(jobsProvider);
          },
        ),
      );
    } else {
      return RefreshIndicator(
        onRefresh: refreshJobs,
        child: ListView.builder(
          itemCount: jobs.length,
          itemBuilder: (context, index) {
            final job = jobs[index];
            return _buildJobItem(context, ref, job, apiService);
          },
        ),
      );
    }
  }

  Widget _buildJobItem(
    BuildContext context,
    WidgetRef ref,
    PrintJob job,
    ApiService apiService, {
    Key? key,
  }) {
    return JobItem(
      key: key ?? ValueKey(job.id),
      job: job,
      onEdit: () {
        ref.read(selectedJobProvider.notifier).state = job;
        context.go('/job/${job.id}');
      },
      onDelete: () async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder:
              (context) => AlertDialog(
                title: const Text('Delete Job'),
                content: Text('Are you sure you want to delete "${job.name}"?'),
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
                    child: const Text('Delete'),
                  ),
                ],
              ),
        );

        if (confirmed == true) {
          await apiService.deleteJob(job.id!);
          ref.refresh(jobsProvider);
        }
      },
    );
  }
}
