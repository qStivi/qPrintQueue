import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:mime/mime.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_cors_headers/shelf_cors_headers.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:sqlite3/sqlite3.dart';

final db = sqlite3.open('../print_queue.sqlite');
const password = 'changeme'; // Replace with secure storage

// Configurable file size limit (default 50MB)
int maxFileSize = 50 * 1024 * 1024; // 50MB in bytes
bool enforceFileSizeLimit = true;

void initDb() {
  print('[DB] Initializing database...');
  db.execute('''
    CREATE TABLE IF NOT EXISTS print_jobs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      file_url TEXT NOT NULL,
      name TEXT NOT NULL,
      priority INTEGER NOT NULL DEFAULT 0,
      scheduled_at TEXT NOT NULL,
      description TEXT,
      status TEXT NOT NULL DEFAULT 'pending',
      order_index INTEGER,
      file_data BLOB,
      file_mime_type TEXT,
      file_name TEXT,
      file_size INTEGER
    );
  ''');
  print('[DB] Database initialized successfully');
}

Response _json(data, {int status = 200}) => Response(
  status,
  body: jsonEncode(data),
  headers: {'content-type': 'application/json'},
);

class Api {
  Router get router {
    final router = Router();

    // Auth
    router.post('/auth/login', (Request req) async {
      print(
        '[Auth] Login attempt from ${req.headers['user-agent']} at ${req.headers['host']}',
      );
      final body = await req.readAsString();
      final data = jsonDecode(body);
      if (data['password'] == password) {
        print('[Auth] Successful login');
        return _json({'success': true});
      }
      print('[Auth] Failed login attempt - Invalid password');
      return _json({
        'success': false,
        'error': 'Invalid password',
      }, status: 401);
    });

    // In the /jobs endpoint:
    router.get('/jobs', (Request req) {
      print(
        '[Jobs] Getting jobs list with sort: ${req.url.queryParameters['sort']}',
      );
      final sort = req.url.queryParameters['sort'] ?? 'priority';
      final orderBy =
          {
            'priority': 'priority DESC',
            'date': 'scheduled_at ASC',
            'name': 'name ASC',
            'custom': 'order_index ASC',
          }[sort] ??
          'priority DESC';

      // Select all fields except file_data to avoid sending large binary data
      final result = db.select(
        '''
        SELECT 
          id, file_url, name, priority, scheduled_at, description, 
          status, order_index, file_name, file_mime_type, file_size,
          (file_data IS NOT NULL) as has_file_data
        FROM print_jobs 
        WHERE status != ? 
        ORDER BY $orderBy
        ''',
        ['archived'],
      );

      List<Map<String, dynamic>> jobs =
          result
              .map((row) => Map.fromIterables(result.columnNames, row.values))
              .toList();

      print('[Jobs] Returning ${jobs.length} jobs');
      return _json(jobs);
    });

    // Add job
    router.post('/jobs', (Request req) async {
      print('[Jobs] Adding new job');
      final data = jsonDecode(await req.readAsString());

      // Check file size if file data is provided
      if (data['file_data'] != null) {
        final fileData = base64Decode(data['file_data']);
        final fileSize = fileData.length;

        if (fileSize > maxFileSize && enforceFileSizeLimit) {
          print('[Jobs] File exceeds size limit: $fileSize bytes');
          return _json({
            'success': false,
            'error': 'File exceeds size limit'
          }, status: 413);
        }
      }

      final stmt = db.prepare('''
        INSERT INTO print_jobs (
          file_url, name, priority, scheduled_at, description, status, order_index,
          file_data, file_mime_type, file_name, file_size
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''');

      Uint8List? fileData;
      if (data['file_data'] != null) {
        fileData = base64Decode(data['file_data']);
      }

      stmt.execute([
        data['file_url'],
        data['name'],
        data['priority'] ?? 0,
        data['scheduled_at'],
        data['description'],
        data['status'] ?? 'pending',
        data['order_index'],
        fileData,
        data['file_mime_type'],
        data['file_name'],
        data['file_size'],
      ]);
      stmt.dispose();
      print('[Jobs] Successfully added job: ${data['name']}');
      return _json({'success': true});
    });

    // Edit job
    router.put('/jobs/<id|[0-9]+>', (Request req, String id) async {
      print('[Jobs] Editing job ID: $id');
      final data = jsonDecode(await req.readAsString());

      // Check file size if file data is provided
      if (data['file_data'] != null) {
        final fileData = base64Decode(data['file_data']);
        final fileSize = fileData.length;

        if (fileSize > maxFileSize && enforceFileSizeLimit) {
          print('[Jobs] File exceeds size limit: $fileSize bytes');
          return _json({
            'success': false,
            'error': 'File exceeds size limit'
          }, status: 413);
        }
      }

      final stmt = db.prepare('''
        UPDATE print_jobs SET
          file_url = ?,
          name = ?,
          priority = ?,
          scheduled_at = ?,
          description = ?,
          status = ?,
          order_index = ?,
          file_data = CASE WHEN ? IS NULL THEN file_data ELSE ? END,
          file_mime_type = ?,
          file_name = ?,
          file_size = ?
        WHERE id = ?
      ''');

      Uint8List? fileData;
      if (data['file_data'] != null) {
        fileData = base64Decode(data['file_data']);
      }

      stmt.execute([
        data['file_url'],
        data['name'],
        data['priority'],
        data['scheduled_at'],
        data['description'],
        data['status'],
        data['order_index'],
        fileData, // For the CASE WHEN check
        fileData, // For the actual update
        data['file_mime_type'],
        data['file_name'],
        data['file_size'],
        int.parse(id),
      ]);
      stmt.dispose();
      print('[Jobs] Successfully updated job ID: $id');
      return _json({'success': true});
    });

    // Delete job
    router.delete('/jobs/<id|[0-9]+>', (Request req, String id) {
      print('[Jobs] Archiving job ID: $id');
      db.execute('UPDATE print_jobs SET status = ? WHERE id = ?', [
        'archived',
        int.parse(id),
      ]);
      print('[Jobs] Successfully archived job ID: $id');
      return _json({'success': true});
    });

    // Reorder jobs
    router.put('/jobs/reorder', (Request req) async {
      print('[Jobs] Reordering jobs');
      final data = jsonDecode(await req.readAsString());
      final batch = db.prepare(
        'UPDATE print_jobs SET order_index = ? WHERE id = ?',
      );
      for (final job in data['order']) {
        batch.execute([job['order_index'], job['id']]);
      }
      batch.dispose();
      print('[Jobs] Successfully reordered ${data['order'].length} jobs');
      return _json({'success': true});
    });

    // File upload endpoint
    router.post('/jobs/upload', (Request req) async {
      print('[Files] Handling file upload');
      try {
        // Check if this is a multipart request by examining the Content-Type header
        final contentType = req.headers['content-type'];
        if (contentType == null ||
            !contentType.startsWith('multipart/form-data')) {
          return _json({
            'success': false,
            'error': 'Not a multipart request'
          }, status: 400);
        }

        // Parse the boundary from the Content-Type header
        final boundaryMatch = RegExp(r'boundary=(.*)$').firstMatch(contentType);
        if (boundaryMatch == null) {
          return _json({
            'success': false,
            'error': 'Invalid multipart request: no boundary found'
          }, status: 400);
        }
        final boundary = boundaryMatch.group(1)!;

        // Use MimeMultipartTransformer to parse the request body
        final transformer = MimeMultipartTransformer(boundary);
        final bodyBytes = await req
            .read()
            .expand((element) => element)
            .toList();
        final bodyStream = Stream.fromIterable([Uint8List.fromList(bodyBytes)]);
        final parts = await transformer.bind(bodyStream).toList();

        if (parts.isEmpty) {
          return _json({
            'success': false,
            'error': 'No parts found in multipart request'
          }, status: 400);
        }

        // Find the file part
        MimeMultipart? filePart;
        for (final part in parts) {
          final contentDisposition = part.headers['content-disposition'];
          if (contentDisposition != null &&
              contentDisposition.contains('filename=')) {
            filePart = part;
            break;
          }
        }

        if (filePart == null) {
          return _json({
            'success': false,
            'error': 'No file found in request'
          }, status: 400);
        }

        // Extract filename from content-disposition header
        final contentDisposition = filePart.headers['content-disposition'] ??
            '';
        final filenameMatch = RegExp(r'filename="([^"]*)"').firstMatch(
            contentDisposition);
        final fileName = filenameMatch?.group(1) ?? 'unknown_file';

        // Get content type
        final partContentType = filePart.headers['content-type'];
        final mimeType = partContentType ?? 'application/octet-stream';

        // Read file bytes
        final bytes = await filePart.fold<List<int>>(
          <int>[],
              (previous, element) => previous..addAll(element),
        );
        final fileSize = bytes.length;

        // Check size limit
        if (fileSize > maxFileSize && enforceFileSizeLimit) {
          print('[Files] File exceeds size limit: $fileSize bytes');
          return _json({
            'success': false,
            'error': 'File exceeds size limit'
          }, status: 413);
        }

        print(
            '[Files] Uploaded file: $fileName, size: $fileSize bytes, type: $mimeType');

        // Return file metadata for client to use in job creation
        return _json({
          'success': true,
          'file_name': fileName,
          'file_size': fileSize,
          'file_mime_type': mimeType,
          'file_data_length': bytes.length
        });
      } catch (e) {
        print('[Files] Error handling file upload: $e');
        return _json({
          'success': false,
          'error': 'Error processing file upload: ${e.toString()}'
        }, status: 500);
      }
    });

    // File download endpoint
    router.get('/jobs/<id|[0-9]+>/file', (Request req, String id) {
      print('[Files] Handling file download for job ID: $id');
      try {
        final result = db.select(
            'SELECT file_data, file_name, file_mime_type FROM print_jobs WHERE id = ?',
            [int.parse(id)]
        );

        if (result.isEmpty) {
          print('[Files] File not found for job ID: $id');
          return Response.notFound('File not found');
        }

        final fileData = result.first['file_data'] as Uint8List?;
        final fileName = result.first['file_name'] as String?;
        final mimeType = result.first['file_mime_type'] as String?;

        if (fileData == null) {
          print('[Files] No file data found for job ID: $id');
          return Response.notFound('No file data found');
        }

        print('[Files] Sending file: ${fileName ?? "unknown"}, size: ${fileData
            .length} bytes');

        return Response.ok(
            fileData,
            headers: {
              'Content-Type': mimeType ?? 'application/octet-stream',
              'Content-Disposition': 'attachment; filename="${fileName ??
                  "file"}"',
            }
        );
      } catch (e) {
        print('[Files] Error handling file download: $e');
        return Response.internalServerError(
            body: 'Error processing file download');
      }
    });

    // File size limit configuration endpoint
    router.post('/settings/file-limits', (Request req) async {
      print('[Settings] Updating file size limits');
      try {
        final data = jsonDecode(await req.readAsString());
        if (data['max_file_size'] != null) {
          maxFileSize = data['max_file_size'];
        }
        if (data['enforce_limit'] != null) {
          enforceFileSizeLimit = data['enforce_limit'];
        }
        print(
            '[Settings] Updated file size limit: $maxFileSize bytes, enforce: $enforceFileSizeLimit');
        return _json({'success': true});
      } catch (e) {
        print('[Settings] Error updating file size limits: $e');
        return _json({
          'success': false,
          'error': 'Error updating file size limits: ${e.toString()}'
        }, status: 500);
      }
    });

    return router;
  }
}

Future<void> logServerInfo(int port) async {
  final String hostName = Platform.localHostname;

  final interfaces = await NetworkInterface.list(
    includeLinkLocal: false,
    type: InternetAddressType.IPv4,
  );

  print('[Server] 3D Print Queue Server running on:');
  print('[Server] - Hostname: $hostName');
  print('[Server] - Port: $port');

  for (var interface in interfaces) {
    for (var addr in interface.addresses) {
      print('[Server] - Available at: http://${addr.address}:$port');
    }
  }
}

void main() async {
  print('[Server] Starting server...');
  initDb();
  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(corsHeaders())
      .addHandler(Api().router);

  final server = await serve(handler, '0.0.0.0', 8080);
  print(
    '[Server] API server listening on http://${server.address.host}:${server.port}',
  );

  await logServerInfo(server.port);
}
