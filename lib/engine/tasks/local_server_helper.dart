import 'task.dart';

class LocalServerHelper {
  /// Parses task description, comments, streamed content, activity, and message history
  /// for local server URLs (localhost/127.0.0.1/0.0.0.0 with port).
  static Set<String> extractLocalServers(
    KanbanTask task, {
    String? streamedContent,
    String? activity,
    List<String> messageContents = const [],
  }) {
    final servers = <String>{};
    final urlRegExp = RegExp(
      r'\b(?:https?://)?(?:localhost|127\.0\.0\.1|0\.0\.0\.0):\d+\b',
      caseSensitive: false,
    );

    void scan(String text) {
      for (final match in urlRegExp.allMatches(text)) {
        var url = match.group(0)!;
        if (!url.toLowerCase().startsWith('http://') &&
            !url.toLowerCase().startsWith('https://')) {
          url = 'http://$url';
        }
        servers.add(url.toLowerCase());
      }
    }

    scan(task.description);
    for (final comment in task.comments) {
      scan(comment.content);
    }
    if (streamedContent != null) {
      scan(streamedContent);
    }
    if (activity != null) {
      scan(activity);
    }
    for (final msg in messageContents) {
      scan(msg);
    }
    return servers;
  }
}
