import 'app_log.dart';

class EventTracker {
  static void track(
    String eventName, {
    Map<String, Object?> params = const {},
  }) {
    AppLog.i('event=$eventName params=$params', tag: 'Analytics');
  }
}
