import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Result of [reportAppError]: a safe message for UI plus whether it was mapped.
class AppErrorReport {
  const AppErrorReport({
    required this.userMessage,
    required this.isKnown,
  });

  final String userMessage;
  final bool isKnown;
}

const _unknownErrorUserMessage =
    'Something went wrong. Please try again. If the problem continues, '
    'contact your event administrator.';

const _larpManagerSyncFailedUserMessage =
    'RoleKeeper could not sync with LarpManager. Your organizer should verify '
    'LM Integration (base URL, event slug, and service account), then try '
    'Sync characters again. If this keeps happening, contact your event admin.';

const _lmIntegrationNotConfiguredUserMessage =
    'LarpManager is not connected for this event yet. Ask your organizer to '
    'complete LM Integration in RoleKeeper.';

const _secretManagerPermissionUserMessage =
    'LarpManager credentials could not be saved on the server. Your organizer '
    'must enable Secret Manager and grant the Cloud Functions service account '
    'access (see FIREBASE_SETUP.md in the project).';

/// Logs a success/info line to the `flutter run` terminal.
void logInfoToTerminal(String context, String message) {
  debugPrint('[$context] $message');
}

/// Logs [error] to the debug console (visible in `flutter run` terminal).
@Deprecated('Use reportAppError so terminal and user text stay in sync')
void logErrorToTerminal(String context, Object error, [StackTrace? stackTrace]) {
  _dumpErrorToTerminal(context, error, stackTrace, knownLabel: null);
}

/// Dumps full error detail to the terminal; returns a user-safe [AppErrorReport].
AppErrorReport reportAppError(
  String context,
  Object error, [
  StackTrace? stackTrace,
]) {
  final known = _resolveKnownError(error);
  _dumpErrorToTerminal(
    context,
    error,
    stackTrace,
    knownLabel: known?.label,
  );
  if (known != null) {
    return AppErrorReport(
      userMessage: known.userMessage,
      isKnown: true,
    );
  }
  return const AppErrorReport(
    userMessage: _unknownErrorUserMessage,
    isKnown: false,
  );
}

class _KnownError {
  const _KnownError({required this.label, required this.userMessage});

  final String label;
  final String userMessage;
}

_KnownError? _resolveKnownError(Object error) {
  if (error is FirebaseFunctionsException) {
    return _matchFirebaseFunctions(error);
  }
  if (error is FirebaseException) {
    return _matchFirebaseException(error);
  }
  return null;
}

_KnownError? _matchFirebaseFunctions(FirebaseFunctionsException e) {
  final code = e.code;
  final msg = (e.message ?? '').trim();
  final msgLower = msg.toLowerCase();

  if (code == 'failed-precondition' &&
      msgLower.contains('larpmanager is not connected')) {
    return const _KnownError(
      label: 'lmIntegrationNotConfigured',
      userMessage: _lmIntegrationNotConfiguredUserMessage,
    );
  }

  if (code == 'permission-denied' &&
      (msgLower.contains('secret manager') ||
          msgLower.contains('secretmanager'))) {
    return const _KnownError(
      label: 'secretManagerPermission',
      userMessage: _secretManagerPermissionUserMessage,
    );
  }

  if (code == 'internal') {
    if (msg.isNotEmpty && msgLower != 'internal') {
      return _KnownError(
        label: 'larpManagerSyncFailed',
        userMessage: msg,
      );
    }
    return const _KnownError(
      label: 'larpManagerSyncFailed',
      userMessage: _larpManagerSyncFailedUserMessage,
    );
  }

  if (code == 'unauthenticated') {
    return const _KnownError(
      label: 'unauthenticated',
      userMessage: 'You must be signed in to continue. Sign out and sign in again.',
    );
  }

  if (code == 'permission-denied') {
    return const _KnownError(
      label: 'permissionDenied',
      userMessage:
          'You do not have permission to do that. Contact your event administrator '
          'if you believe this is a mistake.',
    );
  }

  if (code == 'unavailable' || code == 'deadline-exceeded') {
    return const _KnownError(
      label: 'serviceUnavailable',
      userMessage:
          'The server is temporarily unavailable. Check your connection and try again.',
    );
  }

  if (code == 'invalid-argument' && msg.isNotEmpty) {
    return _KnownError(
      label: 'invalidArgument',
      userMessage: msg,
    );
  }

  return null;
}

_KnownError? _matchFirebaseException(FirebaseException e) {
  if (e.code == 'permission-denied') {
    return const _KnownError(
      label: 'firestorePermissionDenied',
      userMessage:
          'You do not have permission to access this data. Contact your event administrator.',
    );
  }
  if (e.code == 'unavailable') {
    return const _KnownError(
      label: 'firestoreUnavailable',
      userMessage:
          'Could not reach the database. Check your connection and try again.',
    );
  }
  return null;
}

void _dumpErrorToTerminal(
  String context,
  Object error,
  StackTrace? stackTrace, {
  required String? knownLabel,
}) {
  debugPrint('=== [$context] ERROR ===');
  debugPrint('knownError: ${knownLabel ?? "(none — showing generic user message)"}');
  debugPrint('runtimeType: ${error.runtimeType}');
  debugPrint('toString: $error');

  if (error is FirebaseFunctionsException) {
    debugPrint('FirebaseFunctionsException.code: ${error.code}');
    debugPrint('FirebaseFunctionsException.message: ${error.message}');
    debugPrint('FirebaseFunctionsException.details: ${error.details}');
  } else if (error is FirebaseException) {
    debugPrint('FirebaseException.plugin: ${error.plugin}');
    debugPrint('FirebaseException.code: ${error.code}');
    debugPrint('FirebaseException.message: ${error.message}');
  }

  final st = stackTrace ?? (error is Error ? error.stackTrace : null);
  if (st != null) {
    debugPrint('stackTrace:\n$st');
  }
  debugPrint('=== end [$context] ===');
}

/// User-facing text only (no terminal log). Prefer [reportAppError] in UI handlers.
@Deprecated('Use reportAppError(context, error).userMessage')
String formatUserFacingError(Object error) {
  return _resolveKnownError(error)?.userMessage ??
      _unknownErrorUserMessage;
}
