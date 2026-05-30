import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:rolekeeper/models/game_tenant_ref.dart';
import 'package:rolekeeper/utils/game_firestore_paths.dart';

/// Seeds instance + event docs for tests.
Future<void> seedGameTenantDocs(
  FirebaseFirestore firestore,
  GameTenantRef tenant, {
  Map<String, dynamic>? eventFields,
}) async {
  final now = FieldValue.serverTimestamp();
  await GameFirestorePaths.instanceDoc(firestore, tenant).set({
    'instanceId': tenant.instanceId,
    'createdAt': now,
    'updatedAt': now,
  });
  await GameFirestorePaths.eventDoc(firestore, tenant).set({
    'tenantKey': tenant.tenantKey,
    'instanceId': tenant.instanceId,
    'eventSlug': tenant.eventSlug,
    'displayName': tenant.eventSlug,
    if (eventFields != null) ...eventFields,
    'createdAt': now,
    'updatedAt': now,
  });
}
