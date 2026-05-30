import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/game_tenant_ref.dart';

/// Firestore paths under `games/{instanceId}/events/{eventSlug}/...`.
abstract final class GameFirestorePaths {
  static DocumentReference<Map<String, dynamic>> instanceDoc(
    FirebaseFirestore db,
    GameTenantRef tenant,
  ) =>
      db.collection('games').doc(tenant.instanceId);

  static DocumentReference<Map<String, dynamic>> eventDoc(
    FirebaseFirestore db,
    GameTenantRef tenant,
  ) =>
      instanceDoc(db, tenant).collection('events').doc(tenant.eventSlug);

  static CollectionReference<Map<String, dynamic>> members(
    FirebaseFirestore db,
    GameTenantRef tenant,
  ) =>
      eventDoc(db, tenant).collection('members');

  static DocumentReference<Map<String, dynamic>> member(
    FirebaseFirestore db,
    GameTenantRef tenant,
    String uid,
  ) =>
      members(db, tenant).doc(uid);

  static CollectionReference<Map<String, dynamic>> characters(
    FirebaseFirestore db,
    GameTenantRef tenant,
  ) =>
      eventDoc(db, tenant).collection('characters');

  static CollectionReference<Map<String, dynamic>> characterShortIdLookup(
    FirebaseFirestore db,
    GameTenantRef tenant,
  ) =>
      eventDoc(db, tenant).collection('characterShortIdLookup');

  static DocumentReference<Map<String, dynamic>> deathRules(
    FirebaseFirestore db,
    GameTenantRef tenant,
  ) =>
      eventDoc(db, tenant).collection('rules').doc('death');

  static CollectionReference<Map<String, dynamic>> deathInterventionClaims(
    FirebaseFirestore db,
    GameTenantRef tenant,
  ) =>
      eventDoc(db, tenant).collection('deathInterventionClaims');

  static CollectionReference<Map<String, dynamic>> activeEvents(
    FirebaseFirestore db,
    GameTenantRef tenant,
  ) =>
      eventDoc(db, tenant).collection('activeEvents');

  static CollectionReference<Map<String, dynamic>> playerActivityEvents(
    FirebaseFirestore db,
    GameTenantRef tenant,
  ) =>
      eventDoc(db, tenant).collection('playerActivityEvents');

  static DocumentReference<Map<String, dynamic>> larpManagerIntegrationConfig(
    FirebaseFirestore db,
    GameTenantRef tenant,
  ) =>
      eventDoc(db, tenant).collection('larpManagerIntegration').doc('config');

  static DocumentReference<Map<String, dynamic>> larpManagerSyncSettingsConfig(
    FirebaseFirestore db,
    GameTenantRef tenant,
  ) =>
      eventDoc(db, tenant).collection('larpManagerSyncSettings').doc('config');

  static DocumentReference<Map<String, dynamic>> larpManagerMirrorSummary(
    FirebaseFirestore db,
    GameTenantRef tenant,
  ) =>
      eventDoc(db, tenant).collection('larpManagerMirrorMeta').doc('summary');

  static CollectionReference<Map<String, dynamic>> larpManagerMirrorChars(
    FirebaseFirestore db,
    GameTenantRef tenant,
  ) =>
      eventDoc(db, tenant).collection('larpManagerMirrorChars');

  static DocumentReference<Map<String, dynamic>> userMembership(
    FirebaseFirestore db,
    String uid,
    GameTenantRef tenant,
  ) =>
      db
          .collection('users')
          .doc(uid)
          .collection('gameMemberships')
          .doc(tenant.tenantKey);

  static DocumentReference<Map<String, dynamic>> larpRegistryEvent(
    FirebaseFirestore db,
    GameTenantRef tenant,
  ) =>
      db
          .collection('larpRegistry')
          .doc(tenant.instanceId)
          .collection('events')
          .doc(tenant.eventSlug);
}
