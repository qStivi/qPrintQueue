import 'dart:convert';

import 'package:http/http.dart' as http;

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
}
