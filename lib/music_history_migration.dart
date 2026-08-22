import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'music_service.dart';
import 'storage_service.dart';

class MusicHistoryMigrationResult {
  final int conversationsUpdated;
  final int attachmentsUpdated;
  final int conversationsSkipped;

  const MusicHistoryMigrationResult({
    required this.conversationsUpdated,
    required this.attachmentsUpdated,
    required this.conversationsSkipped,
  });
}

class MusicHistoryMigration {
  static final RegExp _conversationKeyPattern = RegExp(r'^conversation_');

  /// Updates music attachments already stored in chat history to the current
  /// catalog entry. Message text, timestamps, images and TTS data are retained.
  ///
  /// Lyrics are deliberately not copied into SharedPreferences. The card reads
  /// the current TXT/timed JSON through the migrated paths, so later lyric file
  /// edits also appear in old messages without another migration.
  static Future<MusicHistoryMigrationResult> run() async {
    final catalog = await MusicService.loadCatalog();
    if (catalog.isEmpty) {
      return const MusicHistoryMigrationResult(
        conversationsUpdated: 0,
        attachmentsUpdated: 0,
        conversationsSkipped: 0,
      );
    }

    final prefs = await SharedPreferences.getInstance();
    var conversationsUpdated = 0;
    var attachmentsUpdated = 0;
    var conversationsSkipped = 0;

    for (final key in prefs.getKeys().where(_conversationKeyPattern.hasMatch)) {
      final storedJson = prefs.getString(key);
      if (storedJson == null) continue;

      try {
        final migrated = migrateConversationJson(storedJson, catalog);
        if (migrated.attachmentsUpdated == 0) continue;

        final saved = await prefs.setString(key, migrated.json);
        if (!saved) {
          conversationsSkipped++;
          continue;
        }
        conversationsUpdated++;
        attachmentsUpdated += migrated.attachmentsUpdated;
      } catch (_) {
        // One damaged historical conversation must not block app startup or
        // prevent other valid conversations from being migrated.
        conversationsSkipped++;
      }
    }

    return MusicHistoryMigrationResult(
      conversationsUpdated: conversationsUpdated,
      attachmentsUpdated: attachmentsUpdated,
      conversationsSkipped: conversationsSkipped,
    );
  }

  static ({String json, int attachmentsUpdated}) migrateConversationJson(
    String storedJson,
    List<MusicAttachment> catalog,
  ) {
    final decoded = jsonDecode(storedJson);
    if (decoded is! List) {
      throw const FormatException('Conversation JSON must be a list.');
    }

    final byId = <String, MusicAttachment>{};
    final bySong = <String, MusicAttachment>{};
    for (final song in catalog) {
      final id = song.id.trim().toLowerCase();
      if (id.isNotEmpty) byId[id] = song;
      bySong[_songKey(song.title, song.band)] = song;
      bySong[_songKey(song.title, song.artist)] = song;
    }

    var updated = 0;
    final messages = decoded.map((rawMessage) {
      if (rawMessage is! Map) return rawMessage;
      final message = Map<String, dynamic>.from(rawMessage);
      final rawAttachment = message['musicAttachment'];
      if (rawAttachment is! Map) return message;

      final attachment = Map<String, dynamic>.from(rawAttachment);
      final id = (attachment['id'] as String? ?? '').trim().toLowerCase();
      final title = attachment['title'] as String? ?? '';
      final band = attachment['band'] as String? ?? '';
      final artist = attachment['artist'] as String? ?? '';
      final current = (id.isEmpty ? null : byId[id]) ??
          bySong[_songKey(title, band)] ??
          bySong[_songKey(title, artist)];
      if (current == null) return message;

      final currentJson = current.toJson();
      if (jsonEncode(attachment) == jsonEncode(currentJson)) return message;

      message['musicAttachment'] = currentJson;
      updated++;
      return message;
    }).toList(growable: false);

    return (json: jsonEncode(messages), attachmentsUpdated: updated);
  }

  static String _songKey(String title, String owner) {
    String normalize(String value) => value.toLowerCase().replaceAll(
          RegExp(r'[\s_\-—·・!！?？.,，。:：…「」『』【】（）()]'),
          '',
        );
    return '${normalize(owner)}|${normalize(title)}';
  }
}
