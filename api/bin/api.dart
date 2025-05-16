import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_cors_headers/shelf_cors_headers.dart';
import 'package:sqlite3/sqlite3.dart';

final db = sqlite3.open('../print_queue.sqlite');
const password = 'changeme'; // Replace with secure storage

void initDb() {
  db.execute('''
    CREATE TABLE IF NOT EXISTS print_jobs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      file_url TEXT NOT NULL,
      name TEXT NOT NULL,
      priority INTEGER NOT NULL DEFAULT 0,
      scheduled_at TEXT NOT NULL,
      description TEXT,
      status TEXT NOT NULL DEFAULT 'pending',
      order_index INTEGER
    );
  ''');
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
      final body = await req.readAsString();
      final data = jsonDecode(body);
      if (data['password'] == password) {
        return _json({'success': true});
      }
      return _json({
        'success': false,
        'error': 'Invalid password',
      }, status: 401);
    });

    // In the /jobs endpoint:
    router.get('/jobs', (Request req) {
      final sort = req.url.queryParameters['sort'] ?? 'priority';
      final orderBy =
          {
            'priority': 'priority DESC',
            'date': 'scheduled_at ASC',
            'name': 'name ASC',
            'custom': 'order_index ASC',
          }[sort] ??
          'priority DESC';
      final result = db.select(
        'SELECT * FROM print_jobs WHERE status != ? ORDER BY $orderBy',
        ['archived'],
      );
      // Use result.columnNames and row as List
      List<Map<String, dynamic>> jobs =
          result
              .map((row) => Map.fromIterables(result.columnNames, row.values))
              .toList();
      return _json(jobs);
    });

    // Add job
    router.post('/jobs', (Request req) async {
      final data = jsonDecode(await req.readAsString());
      final stmt = db.prepare('''
        INSERT INTO print_jobs (file_url, name, priority, scheduled_at, description, status, order_index)
        VALUES (?, ?, ?, ?, ?, ?, ?)
      ''');
      stmt.execute([
        data['file_url'],
        data['name'],
        data['priority'] ?? 0,
        data['scheduled_at'],
        data['description'],
        data['status'] ?? 'pending',
        data['order_index'],
      ]);
      stmt.dispose();
      return _json({'success': true});
    });

    // Edit job
    router.put('/jobs/<id|[0-9]+>', (Request req, String id) async {
      final data = jsonDecode(await req.readAsString());
      final stmt = db.prepare('''
        UPDATE print_jobs SET
          file_url = ?,
          name = ?,
          priority = ?,
          scheduled_at = ?,
          description = ?,
          status = ?,
          order_index = ?
        WHERE id = ?
      ''');
      stmt.execute([
        data['file_url'],
        data['name'],
        data['priority'],
        data['scheduled_at'],
        data['description'],
        data['status'],
        data['order_index'],
        int.parse(id),
      ]);
      stmt.dispose();
      return _json({'success': true});
    });

    // Delete job
    router.delete('/jobs/<id|[0-9]+>', (Request req, String id) {
      db.execute('UPDATE print_jobs SET status = ? WHERE id = ?', [
        'archived',
        int.parse(id),
      ]);
      return _json({'success': true});
    });

    // Reorder jobs
    router.put('/jobs/reorder', (Request req) async {
      final data = jsonDecode(await req.readAsString());
      final batch = db.prepare(
        'UPDATE print_jobs SET order_index = ? WHERE id = ?',
      );
      for (final job in data['order']) {
        batch.execute([job['order_index'], job['id']]);
      }
      batch.dispose();
      return _json({'success': true});
    });

    return router;
  }
}

// Function to log server information
// Note: Service advertisement is not implemented in this version
// Clients will need to use the server discovery feature or manually configure the server URL
Future<void> logServerInfo(int port) async {
  // Get the hostname of the machine
  final String hostName = Platform.localHostname;
  
  // Get all network interfaces
  final interfaces = await NetworkInterface.list(
    includeLinkLocal: false,
    type: InternetAddressType.IPv4,
  );
  
  // Log server information
  print('3D Print Queue Server running on:');
  print('- Hostname: $hostName');
  print('- Port: $port');
  
  // Print all available IP addresses
  for (var interface in interfaces) {
    for (var addr in interface.addresses) {
      print('- Available at: http://${addr.address}:$port');
    }
  }
}

void main() async {
  initDb();
  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(corsHeaders()) // Add CORS middleware
      .addHandler(Api().router);

  final server = await serve(handler, '0.0.0.0', 8080);
  print('API server listening on http://${server.address.host}:${server.port}');

  // Log server information
  await logServerInfo(server.port);
}