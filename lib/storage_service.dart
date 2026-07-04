import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'character_config.dart';

class ChatSession {
  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isTitlePinned;

  ChatSession({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.isTitlePinned = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'isTitlePinned': isTitlePinned,
    };
  }

  factory ChatSession.fromJson(Map<String, dynamic> json) {
    return ChatSession(
      id: json['id'] as String,
      title: json['title'] as String? ?? '新的对话',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
      isTitlePinned: json['isTitlePinned'] as bool? ?? false,
    );
  }

  ChatSession copyWith({
    String? id,
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isTitlePinned,
  }) {
    return ChatSession(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isTitlePinned: isTitlePinned ?? this.isTitlePinned,
    );
  }
}

// 消息模型
class Message {
  final String role; // 'user' 或 'assistant'
  final String content;
  final DateTime timestamp;
  final String? audioPath; // 单段音频缓存路径（旧版字段，保留兼容性，指向第一段）
  final List<String>? audioPaths; // 情绪化 TTS 的多段音频路径列表（新增）
  // 列表顺序与句子切分顺序一一对应
  // 播放时按顺序逐段播放，实现句子级别的情绪化语音
  final String? imagePath; // 用户发送的图片本地路径（单张，旧版兼容字段）
  final List<String>? imagePaths; // 用户一次性发送的多张图片路径列表（新增）
  final String? imageDescription; // 豆包视觉模型对图片的描述（发给 AI 时用，不显示给用户）

  Message({
    required this.role,
    required this.content,
    required this.timestamp,
    this.audioPath,
    this.audioPaths,
    this.imagePath,
    this.imagePaths,
    this.imageDescription,
  });

  Map<String, dynamic> toJson() {
    return {
      'role': role,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'audioPath': audioPath,
      'audioPaths': audioPaths,
      'imagePath': imagePath,
      'imagePaths': imagePaths,
      'imageDescription': imageDescription,
    };
  }

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      role: json['role'],
      content: json['content'],
      timestamp: DateTime.parse(json['timestamp']),
      audioPath: json['audioPath'],
      audioPaths: (json['audioPaths'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      imagePath: json['imagePath'],
      imagePaths: (json['imagePaths'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      imageDescription: json['imageDescription'],
    );
  }

  Message copyWith({
    String? role,
    String? content,
    DateTime? timestamp,
    String? audioPath,
    List<String>? audioPaths,
    String? imagePath,
    List<String>? imagePaths,
    String? imageDescription,
  }) {
    return Message(
      role: role ?? this.role,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      audioPath: audioPath ?? this.audioPath,
      audioPaths: audioPaths ?? this.audioPaths,
      imagePath: imagePath ?? this.imagePath,
      imagePaths: imagePaths ?? this.imagePaths,
      imageDescription: imageDescription ?? this.imageDescription,
    );
  }
}

// 本地存储服务（无改动，和原来完全一样）
class StorageService {
  static String _sessionsKey(String characterId) =>
      'chat_sessions_$characterId';
  static String _activeSessionKey(String characterId) =>
      'active_chat_session_$characterId';
  static String _legacyConversationKey(String characterId) =>
      'conversation_$characterId';
  static String _sessionConversationKey(String characterId, String sessionId) =>
      'conversation_${characterId}_$sessionId';
  static String scopedSettingKey(
          String baseKey, String characterId, String? sessionId) =>
      sessionId == null || sessionId.isEmpty
          ? '${baseKey}_$characterId'
          : '${baseKey}_${characterId}_$sessionId';

  static Future<List<ChatSession>> loadChatSessions(String characterId) async {
    final prefs = await SharedPreferences.getInstance();
    return _ensureSessions(prefs, characterId);
  }

  static Future<String> getActiveSessionId(String characterId) async {
    final prefs = await SharedPreferences.getInstance();
    final sessions = await _ensureSessions(prefs, characterId);
    final activeId = prefs.getString(_activeSessionKey(characterId));
    if (activeId != null && sessions.any((s) => s.id == activeId)) {
      return activeId;
    }

    final fallback = sessions.first.id;
    await prefs.setString(_activeSessionKey(characterId), fallback);
    return fallback;
  }

  static Future<ChatSession> createChatSession(String characterId,
      {String? title}) async {
    final prefs = await SharedPreferences.getInstance();
    final sessions = await _ensureSessions(prefs, characterId);
    final now = DateTime.now();
    final session = ChatSession(
      id: 'session_${now.microsecondsSinceEpoch}',
      title: title ?? '新的对话',
      createdAt: now,
      updatedAt: now,
    );
    final updated = [session, ...sessions];
    await _saveSessions(prefs, characterId, updated);
    await prefs.setString(_activeSessionKey(characterId), session.id);
    await prefs.setString(
        _sessionConversationKey(characterId, session.id), '[]');
    return session;
  }

  static Future<void> switchActiveChatSession(
      String characterId, String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    final sessions = await _ensureSessions(prefs, characterId);
    if (sessions.any((s) => s.id == sessionId)) {
      await prefs.setString(_activeSessionKey(characterId), sessionId);
    }
  }

  static Future<void> renameChatSession(
      String characterId, String sessionId, String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final sessions = await _ensureSessions(prefs, characterId);
    final updated = sessions.map((session) {
      if (session.id != sessionId) return session;
      return session.copyWith(
        title: trimmed,
        updatedAt: DateTime.now(),
        isTitlePinned: true,
      );
    }).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await _saveSessions(prefs, characterId, updated);
  }

  static Future<String> deleteChatSession(
      String characterId, String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    final sessions = await _ensureSessions(prefs, characterId);

    if (sessions.length <= 1) {
      await clearConversation(characterId, sessionId: sessionId);
      return sessionId;
    }

    final remaining = sessions.where((s) => s.id != sessionId).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (remaining.length == sessions.length) {
      return await getActiveSessionId(characterId);
    }

    await prefs.remove(_sessionConversationKey(characterId, sessionId));
    for (final baseKey in [
      'user_name',
      'user_name_pronunciation',
      'personality_override',
      'tts_speed',
      'emotion_analysis_enabled',
      'show_original',
      'show_translation',
      'proactive_enabled',
      'proactive_interval',
      'proactive_chance',
      'last_proactive',
    ]) {
      await prefs.remove(scopedSettingKey(baseKey, characterId, sessionId));
    }

    await _saveSessions(prefs, characterId, remaining);

    final activeId = prefs.getString(_activeSessionKey(characterId));
    final nextActiveId = activeId == sessionId || activeId == null
        ? remaining.first.id
        : activeId;
    await prefs.setString(_activeSessionKey(characterId), nextActiveId);
    return nextActiveId;
  }

  static Future<void> _saveSessions(SharedPreferences prefs, String characterId,
      List<ChatSession> sessions) async {
    final jsonList = sessions.map((s) => s.toJson()).toList();
    await prefs.setString(_sessionsKey(characterId), jsonEncode(jsonList));
  }

  static Future<List<ChatSession>> _ensureSessions(
      SharedPreferences prefs, String characterId) async {
    final sessionsJson = prefs.getString(_sessionsKey(characterId));
    if (sessionsJson != null) {
      final decoded = jsonDecode(sessionsJson) as List;
      final sessions =
          decoded.map((json) => ChatSession.fromJson(json)).toList();
      if (sessions.isNotEmpty) return sessions;
    }

    final legacyJson = prefs.getString(_legacyConversationKey(characterId));
    List<Message> legacyMessages = [];
    if (legacyJson != null) {
      final decoded = jsonDecode(legacyJson) as List;
      legacyMessages = decoded.map((json) => Message.fromJson(json)).toList();
    }

    final now = DateTime.now();
    final lastTime =
        legacyMessages.isNotEmpty ? legacyMessages.last.timestamp : now;
    final defaultSession = ChatSession(
      id: 'default',
      title: '默认对话',
      createdAt:
          legacyMessages.isNotEmpty ? legacyMessages.first.timestamp : now,
      updatedAt: lastTime,
    );
    await _saveSessions(prefs, characterId, [defaultSession]);
    await prefs.setString(_activeSessionKey(characterId), defaultSession.id);

    final sessionKey = _sessionConversationKey(characterId, defaultSession.id);
    if (legacyJson != null && prefs.getString(sessionKey) == null) {
      await prefs.setString(sessionKey, legacyJson);
    } else if (prefs.getString(sessionKey) == null) {
      await prefs.setString(sessionKey, '[]');
    }

    return [defaultSession];
  }

  static Future<String> _conversationKey(
      SharedPreferences prefs, String characterId, String? sessionId) async {
    final resolvedSessionId =
        sessionId ?? await getActiveSessionId(characterId);
    return _sessionConversationKey(characterId, resolvedSessionId);
  }

  static Future<void> _touchSession(
      SharedPreferences prefs, String characterId, String sessionId,
      {String? title}) async {
    final sessions = await _ensureSessions(prefs, characterId);
    final now = DateTime.now();
    final updated = sessions.map((session) {
      if (session.id != sessionId) return session;
      return session.copyWith(
        title: session.isTitlePinned ? session.title : title ?? session.title,
        updatedAt: now,
      );
    }).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await _saveSessions(prefs, characterId, updated);
  }

  static String _deriveSessionTitle(List<Message> messages) {
    final firstUser = messages.firstWhere(
      (m) => m.role == 'user' && m.content.trim().isNotEmpty,
      orElse: () => messages.isNotEmpty
          ? messages.first
          : Message(role: 'user', content: '新的对话', timestamp: DateTime.now()),
    );
    final normalized = firstUser.content.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) return '新的对话';
    return normalized.length > 18
        ? '${normalized.substring(0, 18)}...'
        : normalized;
  }

  // 保存对话历史
  static Future<void> saveConversation(
      String characterId, List<Message> messages,
      {String? sessionId}) async {
    final prefs = await SharedPreferences.getInstance();
    final resolvedSessionId =
        sessionId ?? await getActiveSessionId(characterId);
    final key = await _conversationKey(prefs, characterId, resolvedSessionId);
    final jsonList = messages.map((m) => m.toJson()).toList();
    await prefs.setString(key, jsonEncode(jsonList));
    await _touchSession(
      prefs,
      characterId,
      resolvedSessionId,
      title: messages.isEmpty ? null : _deriveSessionTitle(messages),
    );
  }

  // 读取对话历史
  static Future<List<Message>> loadConversation(String characterId,
      {String? sessionId}) async {
    final prefs = await SharedPreferences.getInstance();
    await _ensureSessions(prefs, characterId);
    final key = await _conversationKey(prefs, characterId, sessionId);
    final jsonString = prefs.getString(key);

    if (jsonString == null) {
      return [];
    }

    final jsonList = jsonDecode(jsonString) as List;
    return jsonList.map((json) => Message.fromJson(json)).toList();
  }

  // 清空对话历史
  static Future<void> clearConversation(String characterId,
      {String? sessionId}) async {
    final prefs = await SharedPreferences.getInstance();
    final resolvedSessionId =
        sessionId ?? await getActiveSessionId(characterId);
    final key = await _conversationKey(prefs, characterId, resolvedSessionId);
    await prefs.setString(key, '[]');
    await _touchSession(prefs, characterId, resolvedSessionId, title: '新的对话');
  }

  // 获取最近的对话（用于发送给 API，限制长度避免超出 token 限制）
  static List<Message> getRecentMessages(List<Message> messages,
      {int maxMessages = 20}) {
    if (messages.length <= maxMessages) {
      return messages;
    }
    return messages.sublist(messages.length - maxMessages);
  }

  // ----------------------------------------
  // 构建最终生效的角色人设字符串
  // ----------------------------------------
  // 读取 SharedPreferences 中该角色的用户自定义设置，按优先级叠加：
  //   1. 若用户在设置页编辑了人设 → 用覆写版本，否则用 character.personality
  //   2. 若用户在设置页填写了称呼 → 在末尾追加 [用户称呼设置] 指令
  //
  // chat_page.dart 的 _effectivePersonality getter 与此逻辑等价（在本地缓存了设置值）。
  // ProactiveMessageService 在每次触发前调用此方法，确保主动消息也尊重用户的称呼设置。
  static Future<String> buildEffectivePersonality(Character character,
      {String? sessionId}) async {
    final prefs = await SharedPreferences.getInstance();
    final id = character.id;
    final resolvedSessionId = sessionId ?? await getActiveSessionId(id);
    final canUseLegacySettings = resolvedSessionId == 'default';

    final personalityOverride = prefs.getString(
            scopedSettingKey('personality_override', id, resolvedSessionId)) ??
        (canUseLegacySettings
            ? prefs.getString('personality_override_$id')
            : null);
    String base =
        (personalityOverride != null && personalityOverride.isNotEmpty)
            ? personalityOverride
            : character.personality;

    final userName =
        prefs.getString(scopedSettingKey('user_name', id, resolvedSessionId)) ??
            (canUseLegacySettings ? prefs.getString('user_name_$id') : null);
    if (userName != null && userName.isNotEmpty) {
      base += '\n\n[用户称呼设置] 请在对话中用"$userName"称呼用户，'
          '忽略以上提示词中的其他称呼设定。';
    } else {
      base += '\n\n[用户称呼设置] 对方未设置称呼，请不要使用任何固定名字称呼用户，或直接不称呼。';
    }

    return base;
  }
}
