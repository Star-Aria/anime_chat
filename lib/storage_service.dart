import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

// 消息模型
class Message {
  final String role; // 'user' 或 'assistant'
  final String content;
  final DateTime timestamp;
  final String? audioPath; // 单段音频缓存路径（旧版字段，保留兼容性，指向第一段）
  final List<String>? audioPaths; // 情绪化 TTS 的多段音频路径列表（新增）
  // 列表顺序与句子切分顺序一一对应
  // 播放时按顺序逐段播放，实现句子级别的情绪化语音
  final String? imagePath; // 用户发送的图片本地路径（仅用户消息）
  final String? imageDescription; // 豆包视觉模型对图片的描述（发给 AI 时用，不显示给用户）

  Message({
    required this.role,
    required this.content,
    required this.timestamp,
    this.audioPath,
    this.audioPaths,
    this.imagePath,
    this.imageDescription,
  });

  Map<String, dynamic> toJson() {
    return {
      'role': role,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'audioPath': audioPath,
      'audioPaths': audioPaths, // 序列化多段路径列表
      'imagePath': imagePath,
      'imageDescription': imageDescription,
    };
  }

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      role: json['role'],
      content: json['content'],
      timestamp: DateTime.parse(json['timestamp']),
      audioPath: json['audioPath'],
      // 反序列化时，把 JSON 数组转回 List<String>
      // 旧数据里没有 audioPaths 字段时，这里会是 null，不影响旧消息的播放
      audioPaths: (json['audioPaths'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      imagePath: json['imagePath'],
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
    String? imageDescription,
  }) {
    return Message(
      role: role ?? this.role,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      audioPath: audioPath ?? this.audioPath,
      audioPaths: audioPaths ?? this.audioPaths,
      imagePath: imagePath ?? this.imagePath,
      imageDescription: imageDescription ?? this.imageDescription,
    );
  }
}

// 本地存储服务（无改动，和原来完全一样）
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

  // 获取最近的对话（用于发送给 API，限制长度避免超出 token 限制）
  static List<Message> getRecentMessages(List<Message> messages,
      {int maxMessages = 20}) {
    if (messages.length <= maxMessages) {
      return messages;
    }
    return messages.sublist(messages.length - maxMessages);
  }
}
