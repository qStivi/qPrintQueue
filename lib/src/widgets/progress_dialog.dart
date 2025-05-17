import 'dart:async';

import 'package:flutter/material.dart';

/// A dialog that shows progress for file uploads and downloads
class ProgressDialog extends StatelessWidget {
  final String title;
  final String message;
  final Stream<double> progressStream;
  final bool isDeterminate;

  const ProgressDialog({
    super.key,
    required this.title,
    required this.message,
    required this.progressStream,
    this.isDeterminate = true,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message),
          const SizedBox(height: 16),
          StreamBuilder<double>(
            stream: progressStream,
            builder: (context, snapshot) {
              final progress = snapshot.data ?? 0.0;
              return Column(
                children: [
                  isDeterminate
                      ? LinearProgressIndicator(value: progress)
                      : const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  if (isDeterminate)
                    Text('${(progress * 100).toStringAsFixed(1)}%'),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// A dialog specifically for file uploads
class UploadProgressDialog extends StatelessWidget {
  final String fileName;
  final Stream<double> progressStream;

  const UploadProgressDialog({
    super.key,
    required this.fileName,
    required this.progressStream,
  });

  @override
  Widget build(BuildContext context) {
    return ProgressDialog(
      title: 'Uploading File',
      message: 'Uploading $fileName',
      progressStream: progressStream,
    );
  }
}

/// A dialog specifically for file downloads
class DownloadProgressDialog extends StatelessWidget {
  final String fileName;
  final Stream<double> progressStream;

  const DownloadProgressDialog({
    super.key,
    required this.fileName,
    required this.progressStream,
  });

  @override
  Widget build(BuildContext context) {
    return ProgressDialog(
      title: 'Downloading File',
      message: 'Downloading $fileName',
      progressStream: progressStream,
    );
  }
}
