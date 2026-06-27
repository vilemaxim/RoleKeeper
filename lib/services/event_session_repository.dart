import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/event_session.dart';
import '../models/game_tenant_ref.dart';
import '../utils/game_firestore_paths.dart';
import 'game_context_service.dart';

/// Loads and updates live event session at `eventSession/config`.
class EventSessionRepository {
  EventSessionRepository({
    FirebaseFirestore? firestore,
    GameTenantRef? tenant,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _tenant = tenant ?? GameContextService.instance.currentTenant;

  final FirebaseFirestore _firestore;
  final GameTenantRef? _tenant;

  GameTenantRef get _resolvedTenant {
    final t = _tenant;
    if (t == null) throw StateError('No game selected');
    return t;
  }

  DocumentReference<Map<String, dynamic>> get _configRef =>
      GameFirestorePaths.eventSessionConfig(_firestore, _resolvedTenant);

  Future<EventSession> get() async {
    final doc = await _configRef.get();
    return EventSession.fromMap(doc.data());
  }

  Future<void> startEvent() async {
    await _configRef.set(
      {
        'isLive': true,
        'liveStartedAt': FieldValue.serverTimestamp(),
        'liveEndedAt': FieldValue.delete(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> endEvent() async {
    await _configRef.set(
      {
        'isLive': false,
        'liveEndedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }
}
