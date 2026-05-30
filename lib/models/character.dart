import 'package:cloud_firestore/cloud_firestore.dart';

/// Character document from Firestore. MVP fields only.
/// [shortId] is a 3-character alphanumeric display ID (e.g. A1B). Use "000" for playtesting.
class Character {
  const Character({
    required this.id,
    required this.shortId,
    required this.ownerId,
    required this.name,
    this.pronouns,
    this.description,
    this.gameSystemId,
    this.gameSystemName,
    this.isArchived = false,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String shortId;
  final String ownerId;
  final String name;
  final String? pronouns;
  final String? description;
  final String? gameSystemId;
  final String? gameSystemName;
  final bool isArchived;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Map<String, dynamic> toMap() => {
        'shortId': shortId,
        'ownerId': ownerId,
        'name': name,
        if (pronouns != null) 'pronouns': pronouns,
        if (description != null) 'description': description,
        if (gameSystemId != null) 'gameSystemId': gameSystemId,
        if (gameSystemName != null) 'gameSystemName': gameSystemName,
        'isArchived': isArchived,
        'createdAt': createdAt != null
            ? Timestamp.fromDate(createdAt!)
            : FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

  static Character fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final createdAt = data['createdAt'];
    final updatedAt = data['updatedAt'];
    return Character(
      id: doc.id,
      shortId: data['shortId'] as String? ?? '000',
      ownerId: data['ownerId'] as String? ?? '',
      name: data['name'] as String? ?? '',
      pronouns: data['pronouns'] as String?,
      description: data['description'] as String?,
      gameSystemId: data['gameSystemId'] as String?,
      gameSystemName: data['gameSystemName'] as String?,
      isArchived: data['isArchived'] as bool? ?? false,
      createdAt: createdAt is Timestamp
          ? createdAt.toDate()
          : (createdAt is DateTime ? createdAt : null),
      updatedAt: updatedAt is Timestamp
          ? updatedAt.toDate()
          : (updatedAt is DateTime ? updatedAt : null),
    );
  }
}
