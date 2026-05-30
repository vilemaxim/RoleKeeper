/// Quick-select entries for common LarpManager instances.
///
/// [baseUrl] is the instance origin, [eventSlug] the first path segment; together
/// they define the same event page as [LarpManagerInstanceTarget.canonicalEventPageUrl]
/// in `lib/utils/larp_manager_instance_parser.dart`.
class PresetLarp {
  const PresetLarp({
    required this.label,
    required this.baseUrl,
    required this.eventSlug,
  });

  final String label;
  final String baseUrl;
  final String eventSlug;
}

const PresetLarp kPresetCrucible = PresetLarp(
  label: 'Crucible',
  baseUrl: 'https://sovereignscrolls.larpmanager.com',
  eventSlug: 'crucible',
);

const PresetLarp kPresetRuinedEarth = PresetLarp(
  label: 'RUIN-Test',
  baseUrl: 'https://sovereignscrolls.larpmanager.com',
  eventSlug: 'ruintest',
);
