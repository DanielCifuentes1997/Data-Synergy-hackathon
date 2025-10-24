class RecognizedPerson {
  RecognizedPerson({
    required this.id,
    this.name,
    this.document,
    this.cargo,
    this.telefono,
    this.imagePath,
    this.distance,
  });

  final String id;
  final String? name;
  final String? document;
  final String? cargo;
  final String? telefono;
  final String? imagePath;
  final double? distance;
}


