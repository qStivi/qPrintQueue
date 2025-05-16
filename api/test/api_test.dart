import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../bin/api.dart';

void main() {
  final handler = Api().router;

  setUp(() {
    // Clean up the table before each test
    db.execute('DELETE FROM print_jobs');
  });

  test('Login with correct password', () async {
    final request = Request(
      'POST',
      Uri.parse('http://localhost/auth/login'),
      body: jsonEncode({'password': 'changeme'}),
      headers: {'content-type': 'application/json'},
    );
    final response = await handler(request);
    expect(response.statusCode, 200);
    final body = jsonDecode(await response.readAsString());
    expect(body['success'], true);
  });

  test('Login with wrong password', () async {
    final request = Request(
      'POST',
      Uri.parse('http://localhost/auth/login'),
      body: jsonEncode({'password': 'wrong'}),
      headers: {'content-type': 'application/json'},
    );
    final response = await handler(request);
    expect(response.statusCode, 401);
    final body = jsonDecode(await response.readAsString());
    expect(body['success'], false);
  });

  test('Add job', () async {
    final job = {
      'file_url': 'file1.bambu',
      'name': 'Test Job',
      'priority': 1,
      'scheduled_at': '2024-06-01T12:00:00Z',
      'description': 'Test print job',
      'status': 'pending',
      'order_index': 1,
    };
    final request = Request(
      'POST',
      Uri.parse('http://localhost/jobs'),
      body: jsonEncode(job),
      headers: {'content-type': 'application/json'},
    );
    final response = await handler(request);
    expect(response.statusCode, 200);
    final body = jsonDecode(await response.readAsString());
    expect(body['success'], true);
  });

  test('Get jobs', () async {
    // Add a job first
    final job = {
      'file_url': 'file1.bambu',
      'name': 'Test Job',
      'priority': 1,
      'scheduled_at': '2024-06-01T12:00:00Z',
      'description': 'Test print job',
      'status': 'pending',
      'order_index': 1,
    };
    final addRequest = Request(
      'POST',
      Uri.parse('http://localhost/jobs'),
      body: jsonEncode(job),
      headers: {'content-type': 'application/json'},
    );
    await handler(addRequest);

    final request = Request('GET', Uri.parse('http://localhost/jobs'));
    final response = await handler(request);
    expect(response.statusCode, 200);
    final body = jsonDecode(await response.readAsString());
    expect(body, isList);
    expect(body.isNotEmpty, true);
    expect(body.first['name'], 'Test Job');
  });

  test('Edit job', () async {
    // Add a job first
    final job = {
      'file_url': 'file1.bambu',
      'name': 'Test Job',
      'priority': 1,
      'scheduled_at': '2024-06-01T12:00:00Z',
      'description': 'Test print job',
      'status': 'pending',
      'order_index': 1,
    };
    final addRequest = Request(
      'POST',
      Uri.parse('http://localhost/jobs'),
      body: jsonEncode(job),
      headers: {'content-type': 'application/json'},
    );
    await handler(addRequest);

    // Get the first job's id
    final getRequest = Request('GET', Uri.parse('http://localhost/jobs'));
    final getResponse = await handler(getRequest);
    final jobs = jsonDecode(await getResponse.readAsString());
    final id = jobs.first['id'];

    final updatedJob = {
      'file_url': 'file1.bambu',
      'name': 'Updated Job',
      'priority': 2,
      'scheduled_at': '2024-06-02T12:00:00Z',
      'description': 'Updated description',
      'status': 'pending',
      'order_index': 2,
    };
    final request = Request(
      'PUT',
      Uri.parse('http://localhost/jobs/$id'),
      body: jsonEncode(updatedJob),
      headers: {'content-type': 'application/json'},
    );
    final response = await handler(request);
    expect(response.statusCode, 200);
    final body = jsonDecode(await response.readAsString());
    expect(body['success'], true);
  });

  test('Delete job (archive)', () async {
    // Add a job first
    final job = {
      'file_url': 'file1.bambu',
      'name': 'Test Job',
      'priority': 1,
      'scheduled_at': '2024-06-01T12:00:00Z',
      'description': 'Test print job',
      'status': 'pending',
      'order_index': 1,
    };
    final addRequest = Request(
      'POST',
      Uri.parse('http://localhost/jobs'),
      body: jsonEncode(job),
      headers: {'content-type': 'application/json'},
    );
    await handler(addRequest);

    // Get the first job's id
    final getRequest = Request('GET', Uri.parse('http://localhost/jobs'));
    final getResponse = await handler(getRequest);
    final jobs = jsonDecode(await getResponse.readAsString());
    final id = jobs.first['id'];

    final request = Request('DELETE', Uri.parse('http://localhost/jobs/$id'));
    final response = await handler(request);
    expect(response.statusCode, 200);
    final body = jsonDecode(await response.readAsString());
    expect(body['success'], true);

    // Confirm job is not returned in /jobs (status != archived)
    final getRequest2 = Request('GET', Uri.parse('http://localhost/jobs'));
    final getResponse2 = await handler(getRequest2);
    final jobs2 = jsonDecode(await getResponse2.readAsString());
    expect(jobs2.where((j) => j['id'] == id), isEmpty);
  });

  test('Reorder jobs', () async {
    // Add two jobs
    for (var i = 0; i < 2; i++) {
      final job = {
        'file_url': 'file${i + 2}.bambu',
        'name': 'Job $i',
        'priority': i,
        'scheduled_at': '2024-06-0${i + 3}T12:00:00Z',
        'description': 'Job $i',
        'status': 'pending',
        'order_index': i,
      };
      final request = Request(
        'POST',
        Uri.parse('http://localhost/jobs'),
        body: jsonEncode(job),
        headers: {'content-type': 'application/json'},
      );
      await handler(request);
    }

    // Get jobs
    final getRequest = Request('GET', Uri.parse('http://localhost/jobs'));
    final getResponse = await handler(getRequest);
    final jobs = jsonDecode(await getResponse.readAsString());

    // Reverse order_index
    final reorder =
        jobs
            .map(
              (j) => {
                'id': j['id'],
                'order_index': jobs.length - 1 - jobs.indexOf(j),
              },
            )
            .toList();

    final request = Request(
      'PUT',
      Uri.parse('http://localhost/jobs/reorder'),
      body: jsonEncode({'order': reorder}),
      headers: {'content-type': 'application/json'},
    );
    final response = await handler(request);
    expect(response.statusCode, 200);
    final body = jsonDecode(await response.readAsString());
    expect(body['success'], true);
  });
}
