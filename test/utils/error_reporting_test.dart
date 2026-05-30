import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolekeeper/utils/error_reporting.dart';

void main() {
  group('reportAppError', () {
    test('maps bare firebase internal to generic larpManager sync message', () {
      final report = reportAppError(
        'test',
        FirebaseFunctionsException(
          code: 'internal',
          message: 'INTERNAL',
          details: null,
        ),
      );
      expect(report.isKnown, isTrue);
      expect(report.userMessage, contains('could not sync with LarpManager'));
      expect(report.userMessage, isNot(contains('INTERNAL')));
    });

    test('passes through internal code with server message', () {
      const serverMsg =
          'Could not find the Organizer role on LarpManager manage/roles page';
      final report = reportAppError(
        'test',
        FirebaseFunctionsException(
          code: 'internal',
          message: serverMsg,
          details: null,
        ),
      );
      expect(report.isKnown, isTrue);
      expect(report.userMessage, serverMsg);
    });

    test('maps LM not connected failed-precondition', () {
      final report = reportAppError(
        'test',
        FirebaseFunctionsException(
          code: 'failed-precondition',
          message:
              'LarpManager is not connected for this event yet. Ask your organizer.',
          details: null,
        ),
      );
      expect(report.isKnown, isTrue);
      expect(report.userMessage, contains('not connected'));
    });

    test('unknown error uses contact admin message', () {
      final report = reportAppError('test', Exception('something odd'));
      expect(report.isKnown, isFalse);
      expect(report.userMessage, contains('contact your event administrator'));
    });
  });
}
