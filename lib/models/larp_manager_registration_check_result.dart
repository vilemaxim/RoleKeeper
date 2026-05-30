/// Result of [LarpManagerRegistrationService.verifyRegistration].
class LarpManagerRegistrationCheckResult {
  const LarpManagerRegistrationCheckResult({
    required this.registered,
    this.isOrganizer = false,
    this.role = 'player',
    this.registrationPageUrl,
    this.registrationCount = 0,
    this.organizerCount = 0,
    this.syncedAt,
    this.message,
    this.hasCharacter = false,
    this.characterCount = 0,
    this.characterCreatePageUrl,
    this.characterMessage,
  });

  final bool registered;
  final bool isOrganizer;
  final String role;
  final String? registrationPageUrl;
  final int registrationCount;
  final int organizerCount;
  final String? syncedAt;
  final String? message;
  final bool hasCharacter;
  final int characterCount;
  final String? characterCreatePageUrl;
  final String? characterMessage;

  factory LarpManagerRegistrationCheckResult.fromCallable(
    Map<String, dynamic> data,
  ) {
    return LarpManagerRegistrationCheckResult(
      registered: data['registered'] == true,
      isOrganizer: data['isOrganizer'] == true,
      role: data['role'] as String? ?? 'player',
      registrationPageUrl: data['registrationPageUrl'] as String?,
      registrationCount: (data['registrationCount'] as num?)?.toInt() ?? 0,
      organizerCount: (data['organizerCount'] as num?)?.toInt() ?? 0,
      syncedAt: data['syncedAt'] as String?,
      message: data['message'] as String?,
      hasCharacter: data['hasCharacter'] == true,
      characterCount: (data['characterCount'] as num?)?.toInt() ?? 0,
      characterCreatePageUrl: data['characterCreatePageUrl'] as String?,
      characterMessage: data['characterMessage'] as String?,
    );
  }
}
