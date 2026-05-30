import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/character.dart';
import '../models/game_tenant_ref.dart';
import '../utils/game_firestore_paths.dart';
import '../utils/short_id.dart';
import 'game_context_service.dart';

/// CRUD for characters under `games/{instanceId}/events/{eventSlug}/characters`.
class CharactersRepository {
  CharactersRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    GameTenantRef? tenant,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _tenant = tenant ?? GameContextService.instance.currentTenant;


  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final GameTenantRef? _tenant;

  GameTenantRef get _resolvedTenant {
    final t = _tenant;
    if (t == null) throw StateError('No game selected');
    return t;
  }

  CollectionReference<Map<String, dynamic>> get _charactersCol =>
      GameFirestorePaths.characters(_firestore, _resolvedTenant);

  CollectionReference<Map<String, dynamic>> get _lookupCol =>
      GameFirestorePaths.characterShortIdLookup(_firestore, _resolvedTenant);

  String? get _userId => _auth.currentUser?.uid;

  Stream<List<Character>> watchCharacters() {
    final uid = _userId;
    if (uid == null) return Stream.value([]);
    return _charactersCol
        .where('ownerId', isEqualTo: uid)
        .where('isArchived', isEqualTo: false)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(Character.fromFirestore).toList());
  }

  Future<Character> create(Character character, {bool playtest = false}) async {
    final uid = _userId;
    if (uid == null) throw StateError('Not authenticated');
    final shortId =
        playtest ? playtestShortId : await _generateUniqueShortId();
    final ref = _charactersCol.doc();
    final data = character.toMap()
      ..['ownerId'] = uid
      ..['shortId'] = shortId;
    await ref.set(data);
    if (!playtest) {
      await _lookupCol.doc(shortId).set({
        'ownerId': uid,
      });
    }
    return Character(
      id: ref.id,
      shortId: shortId,
      ownerId: uid,
      name: character.name,
      pronouns: character.pronouns,
      description: character.description,
      gameSystemId: character.gameSystemId,
      gameSystemName: character.gameSystemName,
      isArchived: false,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  Future<String> _generateUniqueShortId() async {
    for (var i = 0; i < 15; i++) {
      final shortId = generateShortId();
      if (shortId == playtestShortId) continue;
      final exists = await _lookupCol.doc(shortId).get();
      if (!exists.exists) return shortId;
    }
    throw StateError('Could not generate unique short ID');
  }

  Future<String?> getOwnerByShortId(String shortId) async {
    if (shortId.isEmpty) return null;
    final doc = await _lookupCol.doc(shortId.toUpperCase()).get();
    return doc.exists ? doc.get('ownerId') as String? : null;
  }

  Future<String?> getCharacterIdForOwnerAndShortId({
    required String ownerId,
    required String shortId,
  }) async {
    if (ownerId.isEmpty || shortId.isEmpty) return null;
    final snap = await _charactersCol
        .where('ownerId', isEqualTo: ownerId)
        .where('shortId', isEqualTo: shortId.toUpperCase())
        .limit(8)
        .get();
    for (final d in snap.docs) {
      final archived = d.data()['isArchived'];
      if (archived != true) return d.id;
    }
    return null;
  }

  Future<String?> getFirstActiveCharacterIdForOwner(String ownerId) async {
    if (ownerId.isEmpty) return null;
    final snap = await _charactersCol
        .where('ownerId', isEqualTo: ownerId)
        .where('isArchived', isEqualTo: false)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return snap.docs.first.id;
  }

  Future<void> update(Character character) async {
    await _charactersCol.doc(character.id).update(character.toMap());
  }

  Future<void> archive(String characterId) async {
    await _charactersCol.doc(characterId).update({
      'isArchived': true,
      'archivedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
