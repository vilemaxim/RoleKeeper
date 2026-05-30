import 'larp_manager_instance_parser.dart';

/// LarpManager character creation URL for an event run slug.
///
/// See [LarpManager event routes](https://github.com/LoSkana/larpmanager/blob/main/larpmanager/urls/event.py)
/// (`/{event_slug}/character/create/`).
String larpManagerCharacterCreatePageUrl({
  required String baseUrl,
  required String eventSlug,
}) {
  final canonical = canonicalLarpEventPageUrl(baseUrl, eventSlug);
  return '$canonical/character/create/';
}
