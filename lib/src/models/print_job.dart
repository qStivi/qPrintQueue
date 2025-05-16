class PrintJob {
  final int? id;
  final String fileUrl;
  final String name;
  final int priority;
  final DateTime scheduledAt;
  final String? description;
  final String status;
  final int? orderIndex;

  PrintJob({
    this.id,
    required this.fileUrl,
    required this.name,
    required this.priority,
    required this.scheduledAt,
    this.description,
    this.status = 'pending',
    this.orderIndex,
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
    );
  }
}