import 'package:flutter_test/flutter_test.dart';
import 'package:rolekeeper/models/game_tenant_ref.dart';
import 'package:rolekeeper/services/character_sync_service.dart';

void main() {
  group('CharacterSyncService.buildCallablePayload', () {
    const tenant = GameTenantRef(
      instanceId: 'lm.example.com',
      eventSlug: 'crucible',
    );

    test(
      'posts {gameId, instanceId, eventSlug, characterUuid} to the callable',
      () {
        final payload = CharacterSyncService().buildCallablePayload(
          tenant: tenant,
          characterUuid: 'char00013aaa',
        );

        expect(payload['gameId'], 'lm.example.com::crucible');
        expect(payload['instanceId'], 'lm.example.com');
        expect(payload['eventSlug'], 'crucible');
        expect(payload['characterUuid'], 'char00013aaa');
      },
    );
  });

  group('CharacterSyncService.parseResult', () {
    test('translates {ok: true} to CharacterSyncResult.ok==true, error==null',
        () {
      final result = CharacterSyncService().parseResult(<String, dynamic>{
        'ok': true,
      });
      expect(result.ok, isTrue);
      expect(result.error, isNull);
    });

    test(
      'translates {ok: false, error: "LM said no"} to ok==false, error="LM said no"',
      () {
        final result = CharacterSyncService().parseResult(<String, dynamic>{
          'ok': false,
          'error': 'LM said no',
        });
        expect(result.ok, isFalse);
        expect(result.error, 'LM said no');
      },
    );

    test(
      'translates {ok: false} (no error field) to ok==false, error==null',
      () {
        final result = CharacterSyncService().parseResult(<String, dynamic>{
          'ok': false,
        });
        expect(result.ok, isFalse);
        expect(result.error, isNull);
      },
    );

    test(
      'translates non-Map response to ok==false (defensive against malformed '
      'callable payload)',
      () {
        final result = CharacterSyncService().parseResult('unexpected');
        expect(result.ok, isFalse);
      },
    );
  });
}
