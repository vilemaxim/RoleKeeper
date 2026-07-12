import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/game_tenant_ref.dart';
import '../utils/active_events_utils.dart';
import 'characters_repository.dart';
import 'game_context_service.dart';

/// Writes activity via `createActiveGameEvent` (tenant = `instanceId::eventSlug`).
class ActivityEventsService {
  ActivityEventsService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    GameTenantRef? tenant,
    CharactersRepository? charactersRepository,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _tenant = tenant ?? GameContextService.instance.currentTenant,
        _charactersRepository = charactersRepository;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final GameTenantRef? _tenant;
  final CharactersRepository? _charactersRepository;

  GameTenantRef get _resolvedTenant {
    final t = _tenant;
    if (t == null) throw StateError('No game selected');
    return t;
  }

  String get _tenantKey => _resolvedTenant.tenantKey;

  String? get _userId => _auth.currentUser?.uid;

  CharactersRepository get _chars => _charactersRepository ??
      CharactersRepository(
        firestore: _firestore,
        auth: _auth,
        tenant: _resolvedTenant,
      );

  void _assertActorIsParty(String injuredPlayerId, String medicPlayerId) {
    final uid = _userId;
    if (uid == null) throw StateError('Not authenticated');
    if (uid != injuredPlayerId && uid != medicPlayerId) {
      throw StateError('Caller must be injured or medic for this event');
    }
  }

  Future<String> recordDeathCountStarted({String? characterId}) async {
    final uid = _userId;
    if (uid == null) throw StateError('Not authenticated');
    return ActiveEventsUtils.recordDeathTimerStarted(
      gameId: _tenantKey,
      playerId: uid,
      characterId: characterId,
    );
  }

  Future<void> recordDeathTimerExpired({
    required String activityEventId,
    String? characterId,
  }) async {
    final uid = _userId;
    if (uid == null) return;
    await ActiveEventsUtils.recordDeathTimerExpired(
      gameId: _tenantKey,
      playerId: uid,
      chainActivityEventId: activityEventId,
      characterId: characterId,
    );
  }

  Future<String> recordDeathTimerQrUnavailable({
    String? characterId,
    required String reason,
  }) async {
    final uid = _userId;
    if (uid == null) throw StateError('Not authenticated');
    return ActiveEventsUtils.recordDeathTimerQrUnavailable(
      gameId: _tenantKey,
      playerId: uid,
      characterId: characterId,
      reason: reason,
    );
  }

  Future<void> recordMedicStoppedDeathTimer({
    required String injuredPlayerId,
    required String medicPlayerId,
    required String chainActivityEventId,
    String? injuredCharacterId,
    String? medicCharacterId,
  }) async {
    _assertActorIsParty(injuredPlayerId, medicPlayerId);
    await ActiveEventsUtils.recordMedicStoppedDeathTimer(
      gameId: _tenantKey,
      injuredPlayerId: injuredPlayerId,
      medicPlayerId: medicPlayerId,
      chainActivityEventId: chainActivityEventId,
      injuredCharacterId: injuredCharacterId,
      medicCharacterId: medicCharacterId,
    );
  }

  Future<void> recordMedicRevivedCharacter({
    required String injuredPlayerId,
    String? medicPlayerId,
    String? injuredCharacterId,
    String? medicCharacterId,
    required bool offline,
  }) async {
    if (medicPlayerId != null) {
      _assertActorIsParty(injuredPlayerId, medicPlayerId);
    }
    await ActiveEventsUtils.recordMedicRevivedCharacter(
      gameId: _tenantKey,
      injuredPlayerId: injuredPlayerId,
      medicPlayerId: medicPlayerId,
      injuredCharacterId: injuredCharacterId,
      medicCharacterId: medicCharacterId,
      offline: offline,
    );
  }

  Future<void> recordDeathTimeStopped({
    required String injuredPlayerId,
    required String medicPlayerId,
    required String activityEventId,
    String? injuredCharacterId,
    String? fallenShortId,
    String? medicCharacterId,
  }) async {
    final injuredCharId = injuredCharacterId ??
        ((fallenShortId != null && fallenShortId.isNotEmpty)
            ? await _chars.getCharacterIdForOwnerAndShortId(
                ownerId: injuredPlayerId,
                shortId: fallenShortId,
              )
            : await _chars.getFirstActiveCharacterIdForOwner(injuredPlayerId));
    final medicCharId = medicCharacterId ??
        await _chars.getFirstActiveCharacterIdForOwner(medicPlayerId);
    await recordMedicStoppedDeathTimer(
      injuredPlayerId: injuredPlayerId,
      medicPlayerId: medicPlayerId,
      chainActivityEventId: activityEventId,
      injuredCharacterId: injuredCharId,
      medicCharacterId: medicCharId,
    );
  }

  Future<void> recordDeathInterventionComplete({
    String? helpingPlayerId,
    String? injuredCharacterId,
    String? injuredPlayerId,
    String? fallenShortId,
    required bool offline,
  }) async {
    if (helpingPlayerId == null || helpingPlayerId.isEmpty) return;
    final fallenId = injuredPlayerId ?? _userId;
    if (fallenId == null) throw StateError('Not authenticated');

    var injuredCharId = injuredCharacterId;
    if (injuredCharId == null || injuredCharId.isEmpty) {
      if (fallenShortId != null && fallenShortId.isNotEmpty) {
        injuredCharId = await _chars.getCharacterIdForOwnerAndShortId(
          ownerId: fallenId,
          shortId: fallenShortId,
        );
      } else {
        injuredCharId = await _chars.getFirstActiveCharacterIdForOwner(fallenId);
      }
    }
    final medicCharId =
        await _chars.getFirstActiveCharacterIdForOwner(helpingPlayerId);

    await recordMedicRevivedCharacter(
      injuredPlayerId: fallenId,
      medicPlayerId: helpingPlayerId,
      injuredCharacterId: injuredCharId,
      medicCharacterId: medicCharId,
      offline: offline,
    );
  }
}
