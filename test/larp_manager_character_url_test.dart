import 'package:flutter_test/flutter_test.dart';
import 'package:rolekeeper/utils/larp_manager_character_url.dart';

void main() {
  test('larpManagerCharacterCreatePageUrl', () {
    expect(
      larpManagerCharacterCreatePageUrl(
        baseUrl: 'https://lm.test/',
        eventSlug: 'spring-run',
      ),
      'https://lm.test/spring-run/character/create/',
    );
  });
}
