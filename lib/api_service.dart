import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'storage_service.dart';

class ApiService {
  // ⚠️ DeepSeek API 配置
  static const String deepseekApiKey =
      'sk-70f5215dc38d48838a52e3f47856679d'; // 请在这里填入你的 DeepSeek API 密钥
  static const String deepseekBaseUrl = 'https://api.deepseek.com/v1';
  static const String deepseekModel = 'deepseek-chat'; // DeepSeek 聊天模型

  // ⚠️ GPT-SoVITS 配置
  static const String gptSovitsBaseUrl =
      'http://127.0.0.1:9880'; // GPT-SoVITS 本地服务地址

  // 生成对话回复（日文+中文翻译）
  static Future<Map<String, String>> generateResponse({
    required String characterPersonality,
    required List<Message> conversationHistory,
    required String userMessage,
  }) async {
    try {
      // 第一步：生成日文回复
      final japaneseMessages = [
        {
          'role': 'system',
          'content': '$characterPersonality\n\n重要：你必须用日语回答所有问题。',
        },
        // 添加历史对话（只保留日文部分）
        ...conversationHistory.map((msg) {
          // 如果是assistant的消息，可能包含中文翻译，需要提取日文部分
          String content = msg.content;
          if (msg.role == 'assistant' && content.contains('\n\n中文：')) {
            content = content.split('\n\n中文：')[0];
          }
          return {
            'role': msg.role,
            'content': content,
          };
        }),
        // 添加当前用户消息
        {
          'role': 'user',
          'content': userMessage,
        },
      ];

      // 调用 DeepSeek API 获取日文回复
      final japaneseResponse = await http.post(
        Uri.parse('$deepseekBaseUrl/chat/completions'),
        headers: {
          'Authorization': 'Bearer $deepseekApiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': deepseekModel,
          'messages': japaneseMessages,
          'max_tokens': 500,
          'temperature': 0.8,
          'stream': false,
        }),
      );

      if (japaneseResponse.statusCode != 200) {
        print('DeepSeek API 错误: ${japaneseResponse.statusCode}');
        print('错误内容: ${japaneseResponse.body}');
        return {'japanese': '申し訳ございません...', 'chinese': '抱歉，我现在无法回答...'};
      }

      final japaneseData = jsonDecode(utf8.decode(japaneseResponse.bodyBytes));
      final japaneseText =
          japaneseData['choices'][0]['message']['content'] as String;

      // 第二步：翻译成中文
      final translationMessages = [
        {
          'role': 'system',
          'content': '你是一个专业的日语翻译。请将用户提供的日语文本翻译成中文。只输出翻译结果，不要有任何额外的解释或说明。',
        },
        {
          'role': 'user',
          'content': '请将以下日语翻译成中文：\n$japaneseText',
        },
      ];

      final translationResponse = await http.post(
        Uri.parse('$deepseekBaseUrl/chat/completions'),
        headers: {
          'Authorization': 'Bearer $deepseekApiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': deepseekModel,
          'messages': translationMessages,
          'max_tokens': 500,
          'temperature': 0.3, // 降低温度以获得更准确的翻译
          'stream': false,
        }),
      );

      String chineseText;
      if (translationResponse.statusCode == 200) {
        final translationData =
            jsonDecode(utf8.decode(translationResponse.bodyBytes));
        chineseText =
            translationData['choices'][0]['message']['content'] as String;
      } else {
        print('翻译 API 错误: ${translationResponse.statusCode}');
        chineseText = '[翻译失败]';
      }

      return {
        'japanese': japaneseText,
        'chinese': chineseText,
      };
    } catch (e) {
      print('请求失败: $e');
      return {'japanese': '申し訳ございません...', 'chinese': '抱歉，连接失败了...'};
    }
  }

  // 生成语音（GPT-SoVITS TTS）- 支持长文本分段
  static Future<List<String>> generateSpeechSegments({
    required String text,
    required String referWavPath,
    required String promptText,
    required String promptLanguage,
  }) async {
    // 将文本按句子分段（以。、！、？为分隔符）
    List<String> segments = _splitTextIntoSegments(text);
    List<String> audioPaths = [];

    for (int i = 0; i < segments.length; i++) {
      final segment = segments[i].trim();
      if (segment.isEmpty) continue;

      try {
        // 调用 GPT-SoVITS API
        final response = await http.post(
          Uri.parse(gptSovitsBaseUrl),
          headers: {
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'refer_wav_path': referWavPath,
            'prompt_text': promptText,
            'prompt_language': promptLanguage,
            'text': segment,
            'text_language': 'ja', // 日语
            'top_k': 15,
            'top_p': 1.0,
            'temperature': 0.4,
            'speed': 1.0,
          }),
        );

        if (response.statusCode == 200) {
          // 保存音频文件到临时目录
          final tempDir = await getTemporaryDirectory();
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final filePath = '${tempDir.path}/audio_${timestamp}_$i.wav';

          final file = File(filePath);
          await file.writeAsBytes(response.bodyBytes);

          audioPaths.add(filePath);
          print('成功生成音频段 $i: $filePath');
        } else {
          print('GPT-SoVITS 错误 (段落$i): ${response.statusCode}');
          print('错误内容: ${response.body}');
        }
      } catch (e) {
        print('GPT-SoVITS 请求失败 (段落$i): $e');
      }
    }

    return audioPaths;
  }

  // 将长文本分段（每段不超过30个字符，适合日语）
  static List<String> _splitTextIntoSegments(String text) {
    const int maxCharsPerSegment = 30; // 适合日语的分段长度
    List<String> segments = [];

    // 先按句子分割
    List<String> sentences = text.split(RegExp(r'[。！？\n]+'));

    String currentSegment = '';

    for (String sentence in sentences) {
      sentence = sentence.trim();
      if (sentence.isEmpty) continue;

      // 如果当前句子本身就很长，需要再拆分
      if (sentence.length > maxCharsPerSegment) {
        // 先保存之前积累的片段
        if (currentSegment.isNotEmpty) {
          segments.add(currentSegment);
          currentSegment = '';
        }

        // 将长句子按逗号、顿号等进一步拆分
        List<String> parts = sentence.split(RegExp(r'[、，]+'));
        String tempSegment = '';

        for (String part in parts) {
          part = part.trim();
          if (part.isEmpty) continue;

          if ((tempSegment + part).length > maxCharsPerSegment &&
              tempSegment.isNotEmpty) {
            segments.add(tempSegment);
            tempSegment = part;
          } else {
            tempSegment += (tempSegment.isEmpty ? '' : '、') + part;
          }
        }

        if (tempSegment.isNotEmpty) {
          // 如果拆分后还是太长，强制按字符截断
          if (tempSegment.length > maxCharsPerSegment) {
            for (int i = 0; i < tempSegment.length; i += maxCharsPerSegment) {
              int end = (i + maxCharsPerSegment < tempSegment.length)
                  ? i + maxCharsPerSegment
                  : tempSegment.length;
              segments.add(tempSegment.substring(i, end));
            }
          } else {
            segments.add(tempSegment);
          }
        }
      } else {
        // 如果加上这个句子会超长，先保存当前片段
        if ((currentSegment + sentence).length > maxCharsPerSegment &&
            currentSegment.isNotEmpty) {
          segments.add(currentSegment);
          currentSegment = sentence;
        } else {
          currentSegment += (currentSegment.isEmpty ? '' : '。') + sentence;
        }
      }
    }

    // 保存最后的片段
    if (currentSegment.isNotEmpty) {
      // 如果最后的片段还是太长，强制拆分
      if (currentSegment.length > maxCharsPerSegment) {
        for (int i = 0; i < currentSegment.length; i += maxCharsPerSegment) {
          int end = (i + maxCharsPerSegment < currentSegment.length)
              ? i + maxCharsPerSegment
              : currentSegment.length;
          segments.add(currentSegment.substring(i, end));
        }
      } else {
        segments.add(currentSegment);
      }
    }

    // 调试输出
    print('文本总长度: ${text.length}');
    print('分成 ${segments.length} 段');
    for (int i = 0; i < segments.length; i++) {
      print('段落 $i (${segments[i].length}字): ${segments[i]}');
    }

    return segments;
  }

  // 单段语音生成（兼容性方法）
  static Future<String?> generateSpeech({
    required String text,
    required String referWavPath,
    required String promptText,
    required String promptLanguage,
  }) async {
    try {
      // 调用 GPT-SoVITS API
      final response = await http.post(
        Uri.parse(gptSovitsBaseUrl),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'refer_wav_path': referWavPath,
          'prompt_text': promptText,
          'prompt_language': promptLanguage,
          'text': text,
          'text_language': 'ja', // 日语
          'top_k': 15,
          'top_p': 1.0,
          'temperature': 1.0,
          'speed': 1.0,
        }),
      );

      if (response.statusCode == 200) {
        // 保存音频文件到临时目录
        final tempDir = await getTemporaryDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final filePath = '${tempDir.path}/audio_$timestamp.wav';

        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);

        return filePath;
      } else {
        print('GPT-SoVITS 错误: ${response.statusCode}');
        print('错误内容: ${response.body}');
        return null;
      }
    } catch (e) {
      print('GPT-SoVITS 请求失败: $e');
      return null;
    }
  }

  // 测试 DeepSeek API 连接
  static Future<bool> testDeepSeekConnection() async {
    try {
      final response = await http.post(
        Uri.parse('$deepseekBaseUrl/chat/completions'),
        headers: {
          'Authorization': 'Bearer $deepseekApiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': deepseekModel,
          'messages': [
            {'role': 'user', 'content': '测试'},
          ],
          'max_tokens': 10,
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('DeepSeek 连接测试失败: $e');
      return false;
    }
  }

  // 测试 GPT-SoVITS API 连接
  static Future<bool> testGptSovitsConnection() async {
    try {
      final response = await http.get(
        Uri.parse(gptSovitsBaseUrl),
      );
      // GPT-SoVITS 通常返回 422 或 400，但服务是运行的
      return response.statusCode == 422 ||
          response.statusCode == 400 ||
          response.statusCode == 200;
    } catch (e) {
      print('GPT-SoVITS 连接测试失败: $e');
      return false;
    }
  }
}
