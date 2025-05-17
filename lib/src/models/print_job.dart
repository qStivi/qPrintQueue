class PrintJob {
  final int? id;
  final String fileUrl;
  final String name;
  final int priority;
  final DateTime scheduledAt;
  final String? description;
  final String status;
  final int? orderIndex;
  final String? fileName;
  final String? fileMimeType;
  final int? fileSize;
  final String? fileData; // Base64 encoded file data

  PrintJob({
    this.id,
    required this.fileUrl,
    required this.name,
    required this.priority,
    required this.scheduledAt,
    this.description,
    this.status = 'pending',
    this.orderIndex,
    this.fileName,
    this.fileMimeType,
    this.fileSize,
    this.fileData,
  });

  factory PrintJob.fromJson(Map<String, dynamic> json) {
    return PrintJob(
      id: json['id'],
      fileUrl: json['file_url'],
      name: json['name'],
      priority: json['priority'],
      scheduledAt: DateTime.parse(json['scheduled_at']),
      description: json['description'],
      status: json['status'],
      orderIndex: json['order_index'],
      fileName: json['file_name'],
      fileMimeType: json['file_mime_type'],
      fileSize: json['file_size'],
      fileData: json['file_data'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'file_url': fileUrl,
      'name': name,
      'priority': priority,
      'scheduled_at': scheduledAt.toIso8601String(),
      'description': description,
      'status': status,
      'order_index': orderIndex,
      'file_name': fileName,
      'file_mime_type': fileMimeType,
      'file_size': fileSize,
      'file_data': fileData,
    };
  }

  PrintJob copyWith({
    int? id,
    String? fileUrl,
    String? name,
    int? priority,
    DateTime? scheduledAt,
    String? description,
    String? status,
    int? orderIndex,
    String? fileName,
    String? fileMimeType,
    int? fileSize,
    String? fileData,
  }) {
    return PrintJob(
      id: id ?? this.id,
      fileUrl: fileUrl ?? this.fileUrl,
      name: name ?? this.name,
      priority: priority ?? this.priority,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      description: description ?? this.description,
      status: status ?? this.status,
      orderIndex: orderIndex ?? this.orderIndex,
      fileName: fileName ?? this.fileName,
      fileMimeType: fileMimeType ?? this.fileMimeType,
      fileSize: fileSize ?? this.fileSize,
      fileData: fileData ?? this.fileData,
    );
  }
}
