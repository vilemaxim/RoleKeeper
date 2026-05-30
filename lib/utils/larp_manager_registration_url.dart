import 'larp_manager_instance_parser.dart';

/// LarpManager player signup URL for an event run slug.
///
/// See [LarpManager event routes](https://github.com/LoSkana/larpmanager/blob/main/larpmanager/urls/event.py)
/// (`/{event_slug}/register/`).
String larpManagerRegistrationPageUrl({
  required String baseUrl,
  required String eventSlug,
}) {
  final canonical = canonicalLarpEventPageUrl(baseUrl, eventSlug);
  return '$canonical/register/';
}

/// When an event has multiple runs, LM may route via `/event/register/` first.
String larpManagerEventRegistrationHubUrl({
  required String baseUrl,
  required String eventSlug,
}) {
  final canonical = canonicalLarpEventPageUrl(baseUrl, eventSlug);
  return '$canonical/event/register/';
}
