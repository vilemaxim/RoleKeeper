/// Non-web stub for browser geolocation helpers.
Future<bool> webIsWhenInUseGranted() async => false;

Future<bool> webRequestWhenInUse() async => false;

Future<({double latitude, double longitude, double accuracy})?>
    webGetCurrentPosition({
  required Duration timeLimit,
}) async =>
    null;
