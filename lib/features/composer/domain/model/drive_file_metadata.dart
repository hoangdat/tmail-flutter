class DriveFileMetadata {
  final String name;
  final int size;
  final String contentType;
  final String contentUrl;

  const DriveFileMetadata({
    required this.name,
    required this.size,
    required this.contentType,
    required this.contentUrl,
  });

  factory DriveFileMetadata.fromJson(Map<String, dynamic> json) {
    return DriveFileMetadata(
      name: json['name'] as String? ?? '',
      size: json['size'] as int? ?? 0,
      contentType: json['contentType'] as String? ?? '',
      contentUrl: json['contentUrl'] as String? ?? '',
    );
  }

  @override
  String toString() =>
      'DriveFileMetadata{name: $name, size: $size, contentType: $contentType, contentUrl: $contentUrl}';
}
