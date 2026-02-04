import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

// 消息模型
class Message {
  final String role; // 'user' 或 'assistant'
  final String content;
  final DateTime timestamp;
  final String? audioPath; // ⭐ 新增：音频文件路径（用于缓存）

  Message({
    required this.role,
    required this.content,
    required this.timestamp,
    this.audioPath, // ⭐ 可选参数
  });

  Map<String, dynamic> toJson() {
    return {
      'role': role,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'audioPath': audioPath, // ⭐ 保存音频路径
    };
  }

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      role: json['role'],
      content: json['content'],
      timestamp: DateTime.parse(json['timestamp']),
      audioPath: json['audioPath'], // ⭐ 读取音频路径
    );
  }

  // ⭐ 新增：创建带音频路径的副本
  Message copyWith({
    String? role,
    String? content,
    DateTime? timestamp,
    String? audioPath,
  }) {
    return Message(
      role: role ?? this.role,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      audioPath: audioPath ?? this.audioPath,
    );
  }
}

// 本地存储服务
class StorageService {
  // 保存对话历史
  static Future<void> saveConversation(
      String characterId, List<Message> messages) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'conversation_$characterId';
    final jsonList = messages.map((m) => m.toJson()).toList();
    await prefs.setString(key, jsonEncode(jsonList));
  }

  // 读取对话历史
  static Future<List<Message>> loadConversation(String characterId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'conversation_$characterId';
    final jsonString = prefs.getString(key);

    if (jsonString == null) {
      return [];
    }

    final jsonList = jsonDecode(jsonString) as List;
    return jsonList.map((json) => Message.fromJson(json)).toList();
  }

  // 清空对话历史
  static Future<void> clearConversation(String characterId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'conversation_$characterId';
    await prefs.remove(key);
  }

  // 获取最近的对话（用于发送给API，限制长度避免超出token限制）
  static List<Message> getRecentMessages(List<Message> messages,
      {int maxMessages = 20}) {
    if (messages.length <= maxMessages) {
      return messages;
    }
    return messages.sublist(messages.length - maxMessages);
  }
}
