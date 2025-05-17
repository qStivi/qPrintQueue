import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:universal_io/io.dart' as io;

import '../models/print_job.dart';
import '../providers/providers.dart';
import '../widgets/progress_dialog.dart';

class JobItem extends ConsumerStatefulWidget {
  final PrintJob job;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const JobItem({
    super.key,
    required this.job,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  ConsumerState<JobItem> createState() => _JobItemState();
}

class _JobItemState extends ConsumerState<JobItem> {
  bool _isDownloading = false;
  late StreamController<double> _downloadProgressController;

  // Create a new StreamController for each download to avoid "Stream already listened to" errors
  void _createNewProgressController() {
    _downloadProgressController = StreamController<double>();
  }

  @override
  void initState() {
    super.initState();
    _createNewProgressController();
  }

  @override
  void dispose() {
    _downloadProgressController.close();
    super.dispose();
  }

  Future<void> _downloadFile() async {
    if (widget.job.id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot download file: Job ID is missing'),
        ),
      );
      return;
    }

    if (widget.job.fileName == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot download file: File name is missing'),
        ),
      );
      return;
    }

    // Create a new progress controller for this download
    _createNewProgressController();

    setState(() {
      _isDownloading = true;
    });

    // Show download progress dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => DownloadProgressDialog(
            fileName: widget.job.fileName!,
            progressStream: _downloadProgressController.stream,
          ),
    );

    try {
      final apiService = ref.read(apiServiceProvider);

      // Download the file data
      final fileData = await apiService.downloadFile(
        widget.job.id!,
        onProgress: (progress) {
          _downloadProgressController.add(progress);
        },
      );

      // Close progress dialog after download completes
      if (mounted) {
        Navigator.of(context).pop();
      }

      // Platform-specific file saving
      if (io.Platform.isAndroid || io.Platform.isIOS) {
        // Use path_provider for mobile platforms
        final directory = await getApplicationDocumentsDirectory();
        final filePath =
            '${directory.path}/${widget.job.fileName ?? "downloaded_file"}';
        final file = File(filePath);
        await file.writeAsBytes(fileData);

        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('File saved to: $filePath')));
        }
      } else if (io.Platform.isMacOS) {
        // Use the system's save dialog on macOS
        try {
          print('Attempting to show save dialog on macOS');

          // Prompt user with a "Save As…" dialog
          final outputFilePath = await FilePicker.platform.saveFile(
            dialogTitle: 'Save ${widget.job.fileName}',
            fileName: widget.job.fileName,
            type:
                FileType
                    .any, // or FileType.custom + allowedExtensions if you need filtering
          );

          if (outputFilePath == null) {
            // user cancelled
            if (mounted) {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('File save cancelled')),
              );
            }
            return;
          }

          final path = outputFilePath;

          print('Save dialog result: Path selected');
          print('Saving file to: $path');

          try {
            // Ensure the path doesn't have a ".*" suffix
            String cleanPath = path;
            if (cleanPath.endsWith(".*")) {
              cleanPath = cleanPath.substring(0, cleanPath.length - 2);
            }
            final file = File(cleanPath);
            await file.writeAsBytes(fileData);
            print('File successfully written to: $cleanPath');

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('File saved to: $cleanPath'),
                  duration: const Duration(seconds: 5),
                ),
              );
            }
          } catch (writeError) {
            print('Error writing file: $writeError');
            throw writeError; // Re-throw to be caught by outer catch block
          }
        } catch (e) {
          print('Error in file save process: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to save file: ${e.toString()}'),
                duration: const Duration(seconds: 5),
              ),
            );
          }
        }
      } else {
        // Fallback for other platforms
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'File download not fully supported on this platform',
              ),
            ),
          );
        }
      }
    } catch (e) {
      print('Download error: $e');
      if (mounted) {
        // Close progress dialog if still showing
        Navigator.of(context).pop();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: ${e.toString()}')),
        );
      }
    } finally {
      setState(() {
        _isDownloading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.job.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _buildPriorityChip(theme),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  _formatDate(widget.job.scheduledAt),
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(width: 16),
                Icon(
                  Icons.attach_file,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    widget.job.fileName ?? widget.job.fileUrl,
                    style: theme.textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (widget.job.fileSize != null)
                  Text(
                    ' (${_formatFileSize(widget.job.fileSize!)})',
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
            if (widget.job.description != null &&
                widget.job.description!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                widget.job.description!,
                style: theme.textTheme.bodyMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Add download button if file is available
                if (widget.job.fileName != null)
                  TextButton.icon(
                    onPressed: _isDownloading ? null : _downloadFile,
                    icon:
                        _isDownloading
                            ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Icon(Icons.download),
                    label: const Text('Download'),
                  ),
                TextButton.icon(
                  onPressed: widget.onEdit,
                  icon: const Icon(Icons.edit),
                  label: const Text('Edit'),
                ),
                TextButton.icon(
                  onPressed: widget.onDelete,
                  icon: const Icon(Icons.delete),
                  label: const Text('Delete'),
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024)
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Widget _buildPriorityChip(ThemeData theme) {
    Color chipColor;
    String label;

    if (widget.job.priority >= 8) {
      chipColor = Colors.red;
      label = 'High';
    } else if (widget.job.priority >= 4) {
      chipColor = Colors.orange;
      label = 'Medium';
    } else {
      chipColor = Colors.green;
      label = 'Low';
    }

    return Chip(
      label: Text(label, style: TextStyle(color: Colors.white, fontSize: 12)),
      backgroundColor: chipColor,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      visualDensity: VisualDensity.compact,
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
