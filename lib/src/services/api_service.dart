import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:path/path.dart' as path;

import '../models/print_job.dart';

class ApiService {
  String _baseUrl;

  // Getter for baseUrl
  String get baseUrl => _baseUrl;

  ApiService({String baseUrl = 'http://localhost:8080'}) : _baseUrl = baseUrl;

  // Method to update the base URL
  void updateBaseUrl(String newUrl) {
    _baseUrl = newUrl;
  }

  Future<bool> login(String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      body: jsonEncode({'password': password}),
      headers: {'Content-Type': 'application/json'},
    );

    final data = jsonDecode(response.body);
    return data['success'] == true;
  }

  Future<List<PrintJob>> getJobs({String sort = 'priority'}) async {
    final response = await http.get(Uri.parse('$baseUrl/jobs?sort=$sort'));

    final List<dynamic> data = jsonDecode(response.body);
    return data.map((json) => PrintJob.fromJson(json)).toList();
  }

  Future<bool> createJob(PrintJob job) async {
    final response = await http.post(
      Uri.parse('$baseUrl/jobs'),
      body: jsonEncode(job.toJson()),
      headers: {'Content-Type': 'application/json'},
    );

    final data = jsonDecode(response.body);
    return data['success'] == true;
  }

  Future<bool> updateJob(PrintJob job) async {
    final response = await http.put(
      Uri.parse('$baseUrl/jobs/${job.id}'),
      body: jsonEncode(job.toJson()),
      headers: {'Content-Type': 'application/json'},
    );

    final data = jsonDecode(response.body);
    return data['success'] == true;
  }

  Future<bool> deleteJob(int id) async {
    final response = await http.delete(Uri.parse('$baseUrl/jobs/$id'));

    final data = jsonDecode(response.body);
    return data['success'] == true;
  }

  Future<bool> reorderJobs(List<Map<String, dynamic>> order) async {
    final response = await http.put(
      Uri.parse('$baseUrl/jobs/reorder'),
      body: jsonEncode({'order': order}),
      headers: {'Content-Type': 'application/json'},
    );

    final data = jsonDecode(response.body);
    return data['success'] == true;
  }

  /// Uploads a file to the server and returns the file metadata
  Future<Map<String, dynamic>> uploadFile(File file,
      {Function(double)? onProgress}) async {
    try {
      final uri = Uri.parse('$baseUrl/jobs/upload');
      final request = http.MultipartRequest('POST', uri);

      // Get file information
      final fileLength = await file.length();
      final fileName = path.basename(file.path);
      final fileExtension = path.extension(file.path).toLowerCase();

      // Determine MIME type based on extension
      String mimeType = 'application/octet-stream'; // Default
      if (fileExtension == '.stl') {
        mimeType = 'model/stl';
      } else if (fileExtension == '.obj')
        mimeType = 'model/obj';
      else if (fileExtension == '.3mf')
        mimeType = 'model/3mf';
      else if (fileExtension == '.gcode')
        mimeType = 'text/plain';
      else if (fileExtension == '.bambu') mimeType = 'application/octet-stream';

      // Create a stream from the file
      final fileStream = http.ByteStream(file.openRead());

      // Create the multipart file
      final multipartFile = http.MultipartFile(
        'file',
        fileStream,
        fileLength,
        filename: fileName,
        contentType: MediaType.parse(mimeType),
      );

      // Add the file to the request
      request.files.add(multipartFile);

      // Send the request
      final streamedResponse = await request.send();

      // Convert the streamed response to a regular response
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to upload file: ${response.body}');
      }
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Downloads a file from the server
  Future<Uint8List> downloadFile(int jobId,
      {Function(double)? onProgress}) async {
    try {
      final uri = Uri.parse('$baseUrl/jobs/$jobId/file');
      final request = http.Request('GET', uri);
      final streamedResponse = await http.Client().send(request);

      if (streamedResponse.statusCode != 200) {
        throw Exception(
            'Failed to download file: ${streamedResponse.statusCode}');
      }

      final contentLength = streamedResponse.contentLength ?? 0;
      int received = 0;
      final List<int> bytes = [];

      // Listen to the stream and update progress
      await for (final chunk in streamedResponse.stream) {
        bytes.addAll(chunk);
        received += chunk.length;

        if (contentLength > 0 && onProgress != null) {
          onProgress(received / contentLength);
        }
      }

      return Uint8List.fromList(bytes);
    } catch (e) {
      throw Exception('Error downloading file: ${e.toString()}');
    }
  }

  /// Updates the file size limit configuration
  Future<bool> updateFileSizeLimits(int maxFileSize, bool enforceLimit) async {
    final response = await http.post(
      Uri.parse('$baseUrl/settings/file-limits'),
      body: jsonEncode({
        'max_file_size': maxFileSize,
        'enforce_limit': enforceLimit,
      }),
      headers: {'Content-Type': 'application/json'},
    );

    final data = jsonDecode(response.body);
    return data['success'] == true;
  }
}
