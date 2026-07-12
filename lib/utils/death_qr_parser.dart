import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Parses QR payloads used for online death intervention (medic/healer scans).
///
/// v2 medic format (ADR 003):
/// `rolekeeper:death:v2:medic:{shortId}:{fallenPlayerId}:{activityEventId}:{hmacHex}`
typedef DeathQrParsed = ({
  String shortId,
  String fallenPlayerId,
  String activityEventId,
  String? hmacHex,
});

const _v2MedicPrefix = 'rolekeeper:death:v2:medic:';
const _v2RevivalPrefix = 'rolekeeper:death:v2:revival-confirm:';

bool isDeathInterventionMedicQr(String raw) => raw.startsWith(_v2MedicPrefix);

bool isDeathInterventionRevivalConfirmQr(String raw) =>
    raw.startsWith(_v2RevivalPrefix);

bool isDeathInterventionQr(String raw) =>
    isDeathInterventionMedicQr(raw) || isDeathInterventionRevivalConfirmQr(raw);

/// HMAC-SHA256 over `{shortId}:{fallenPlayerId}:{activityEventId}`; first 16 bytes as hex.
String deathQrHmacHex({
  required String signingSecret,
  required String shortId,
  required String fallenPlayerId,
  required String activityEventId,
}) {
  final message = '$shortId:$fallenPlayerId:$activityEventId';
  final digest =
      Hmac(sha256, utf8.encode(signingSecret)).convert(utf8.encode(message));
  return digest.bytes
      .take(16)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
}

bool verifyDeathInterventionQr(
  String raw, {
  required String signingSecret,
}) {
  final parsed = parseDeathInterventionQr(raw, signingSecret: signingSecret);
  return parsed != null;
}

/// Returns null if the string is not a valid death intervention QR payload.
DeathQrParsed? parseDeathInterventionQr(
  String raw, {
  String? signingSecret,
}) {
  final String? prefix;
  if (raw.startsWith(_v2MedicPrefix)) {
    prefix = _v2MedicPrefix;
  } else if (raw.startsWith(_v2RevivalPrefix)) {
    prefix = _v2RevivalPrefix;
  } else {
    return null;
  }

  final rest = raw.substring(prefix.length);
  final lastColon = rest.lastIndexOf(':');
  if (lastColon <= 0) return null;

  final hmacHex = rest.substring(lastColon + 1);
  if (hmacHex.isEmpty || hmacHex.length != 32) return null;

  final body = rest.substring(0, lastColon);
  final bodyParts = body.split(':');
  if (bodyParts.length != 3) return null;

  final shortId = bodyParts[0];
  final fallenPlayerId = bodyParts[1];
  final activityEventId = bodyParts[2];
  if (shortId.isEmpty || fallenPlayerId.isEmpty || activityEventId.isEmpty) {
    return null;
  }

  if (signingSecret != null) {
    final expected = deathQrHmacHex(
      signingSecret: signingSecret,
      shortId: shortId,
      fallenPlayerId: fallenPlayerId,
      activityEventId: activityEventId,
    );
    if (expected != hmacHex) return null;
  }

  return (
    shortId: shortId,
    fallenPlayerId: fallenPlayerId,
    activityEventId: activityEventId,
    hmacHex: hmacHex,
  );
}

/// Builds the v2 HMAC-signed medic QR shown in [DeathTimerScreen].
String buildDeathMedicQrPayload({
  required String shortId,
  required String fallenPlayerId,
  required String activityEventId,
  required String signingSecret,
}) {
  final hmacHex = deathQrHmacHex(
    signingSecret: signingSecret,
    shortId: shortId,
    fallenPlayerId: fallenPlayerId,
    activityEventId: activityEventId,
  );
  return '$_v2MedicPrefix$shortId:$fallenPlayerId:$activityEventId:$hmacHex';
}

/// Returns true when [signingSecret] can produce a verifiable v2 medic QR.
bool canProduceSignedDeathMedicQr({
  required String? signingSecret,
  required String shortId,
  required String fallenPlayerId,
  String activityEventId = 'preflight',
}) {
  if (signingSecret == null || signingSecret.isEmpty) return false;
  try {
    final raw = buildDeathMedicQrPayload(
      shortId: shortId,
      fallenPlayerId: fallenPlayerId,
      activityEventId: activityEventId,
      signingSecret: signingSecret,
    );
    return raw.isNotEmpty &&
        verifyDeathInterventionQr(raw, signingSecret: signingSecret);
  } catch (_) {
    return false;
  }
}

/// Builds the v2 HMAC-signed revival-confirmation QR payload.
String buildDeathRevivalConfirmQrPayload({
  required String shortId,
  required String fallenPlayerId,
  required String activityEventId,
  required String signingSecret,
}) {
  final hmacHex = deathQrHmacHex(
    signingSecret: signingSecret,
    shortId: shortId,
    fallenPlayerId: fallenPlayerId,
    activityEventId: activityEventId,
  );
  return '$_v2RevivalPrefix$shortId:$fallenPlayerId:$activityEventId:$hmacHex';
}
