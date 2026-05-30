/// Parses QR payloads used for online death intervention (medic/healer scans).
///
/// Format: `rolekeeper:death:medic:{shortId}:{fallenPlayerId}:{activityEventId}`
/// Revival confirm: `rolekeeper:death:revival-confirm:{shortId}:{fallenPlayerId}:{activityEventId}`
typedef DeathQrParsed = ({
  String shortId,
  String fallenPlayerId,
  String activityEventId,
});

bool isDeathInterventionMedicQr(String raw) =>
    raw.startsWith('rolekeeper:death:medic:');

bool isDeathInterventionRevivalConfirmQr(String raw) =>
    raw.startsWith('rolekeeper:death:revival-confirm:');

bool isDeathInterventionQr(String raw) =>
    isDeathInterventionMedicQr(raw) || isDeathInterventionRevivalConfirmQr(raw);

/// Returns null if the string is not a valid death intervention QR payload.
DeathQrParsed? parseDeathInterventionQr(String raw) {
  if (!raw.startsWith('rolekeeper:death:')) return null;
  final parts = raw.split(':');
  if (parts.length < 5) return null;
  final shortId = parts[3];
  final fallenPlayerId = parts.length >= 6 ? parts[4] : parts[3];
  final activityEventId = parts.length >= 6 ? parts[5] : parts[4];
  if (shortId.isEmpty) return null;
  if (activityEventId.isEmpty) return null;
  return (
    shortId: shortId,
    fallenPlayerId: fallenPlayerId,
    activityEventId: activityEventId,
  );
}

/// Builds the same string shown in [DeathTimerScreen] for the medic QR.
String buildDeathMedicQrPayload({
  required String shortId,
  required String fallenPlayerId,
  required String activityEventId,
}) =>
    'rolekeeper:death:medic:$shortId:$fallenPlayerId:$activityEventId';

/// Builds the revival-confirmation QR payload.
String buildDeathRevivalConfirmQrPayload({
  required String shortId,
  required String fallenPlayerId,
  required String activityEventId,
}) =>
    'rolekeeper:death:revival-confirm:$shortId:$fallenPlayerId:$activityEventId';
