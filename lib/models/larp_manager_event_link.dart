import '../utils/larp_manager_character_url.dart';
import '../utils/larp_manager_registration_url.dart';

/// LarpManager instance + event path for the active RoleKeeper game.
class LarpManagerEventLink {
  const LarpManagerEventLink({
    required this.baseUrl,
    required this.eventSlug,
    required this.registrationPageUrl,
    required this.characterCreatePageUrl,
  });

  final String baseUrl;
  final String eventSlug;
  final String registrationPageUrl;
  final String characterCreatePageUrl;

  factory LarpManagerEventLink.fromBaseAndSlug({
    required String baseUrl,
    required String eventSlug,
  }) {
    return LarpManagerEventLink(
      baseUrl: baseUrl,
      eventSlug: eventSlug,
      registrationPageUrl: larpManagerRegistrationPageUrl(
        baseUrl: baseUrl,
        eventSlug: eventSlug,
      ),
      characterCreatePageUrl: larpManagerCharacterCreatePageUrl(
        baseUrl: baseUrl,
        eventSlug: eventSlug,
      ),
    );
  }
}
