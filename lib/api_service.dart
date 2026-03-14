import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'storage_service.dart';

class ApiService {
  static const String doubaoApiKey = 'sk-70f5215dc38d48838a52e3f47856679d';

  static const String doubaoModel = 'deepseek-chat';

  static const String doubaoBaseUrl = 'https://api.deepseek.com/v1';

  // ========================================
  // 豆包视觉模型配置
  // ========================================
  static const String doubaoVisionBaseUrl =
      'https://ark.cn-beijing.volces.com/api/v3';
  static const String doubaoVisionEndpoint = 'ep-20260213104644-59ljp';
  static const String doubaoVisionApiKey =
      'ee7239b4-0334-4062-9819-2e365b6dd49d';

  static const String gptSovitsBaseUrl = 'http://127.0.0.1:9880';

  // 生成对话回复（日文+中文翻译）
  static Future<Map<String, String>> generateResponse({
    required String characterPersonality,
    required List<Message> conversationHistory,
    required String userMessage,
    String? timeContext,
    String? proactiveInstruction,
    String? imagePath,
  }) async {
    try {
      String imageContext = '';
      if (imagePath != null && imagePath.isNotEmpty) {
        print('检测到图片，调用视觉模型中...');
        final description = await _describeImage(imagePath);
        if (description.isNotEmpty) {
          imageContext = '\n\n【图片内容】$description';
          print('视觉模型描述: $description');
        }
      }

      final StringBuffer systemBuffer = StringBuffer();
      systemBuffer.write(characterPersonality);

      if (timeContext != null && timeContext.isNotEmpty) {
        systemBuffer.writeln();
        systemBuffer.write(timeContext);
      }

      if (proactiveInstruction != null && proactiveInstruction.isNotEmpty) {
        systemBuffer.writeln();
        systemBuffer.write(proactiveInstruction);
      }

      systemBuffer.writeln();
      systemBuffer.write('''
【情绪感知回复规则】

当用户的消息中明显出现以下任意一种情况时，进入更深度的「情绪支持模式」：
- 表达情绪低落、难过、哭泣、心情不好
- 表达焦虑、压力大、喘不过气、睡不着
- 表达迷茫、不知道该怎么办、感到无力
- 主动倾诉烦恼、困境或内心困扰
- 希望被安慰、被理解、被倾听
- 寻求建议或解决办法

进入「情绪支持模式」后，必须遵守以下规则：
1. 回复长度要比平时聊天明显更长，充分回应对方的情绪，不要三言两语带过
2. 先共情、后引导：先让对方感到被理解和接纳，再给出温和的建议或鼓励
3. 不要说教，不要急着给解决方案，重点是陪伴和倾听的感觉
4. 如果对方说的烦恼比较具体，可以追问细节，表现出真正在意的样子
5. 全程保持你自己角色的说话方式和性格，不要变成机械助手的语气
6. 可以联系你和对方的关系、你自己的经历来表达共鸣，让安慰更真实有温度

未进入「情绪支持模式」时（即普通日常聊天），完全忽略以上规则，按平时正常方式回复。
''');

      final List<Map<String, String>> japaneseMessages = [
        {
          'role': 'system',
          'content': systemBuffer.toString(),
        },
      ];

      japaneseMessages.addAll(conversationHistory.map((msg) {
        String content = msg.content;
        if (msg.role == 'assistant' && content.contains('\n\n中文：')) {
          content = content.split('\n\n中文：')[0];
        }
        if (msg.role == 'user' &&
            msg.imageDescription != null &&
            msg.imageDescription!.isNotEmpty) {
          final displayText = content.startsWith('[图片] ')
              ? content.substring(5)
              : content == '[图片]'
                  ? ''
                  : content;
          final textPart = displayText.isNotEmpty ? '$displayText\n\n' : '';
          content = '${textPart}【图片内容】${msg.imageDescription}';
        }
        return {
          'role': msg.role,
          'content': content,
        };
      }));

      japaneseMessages.add(
        proactiveInstruction != null
            ? {'role': 'user', 'content': ''}
            : {'role': 'user', 'content': '$userMessage$imageContext'},
      );

      final japaneseResponse = await http.post(
        Uri.parse('$doubaoBaseUrl/chat/completions'),
        headers: {
          'Authorization': 'Bearer $doubaoApiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': doubaoModel,
          'messages': japaneseMessages,
          'max_tokens': 1000,
          'temperature': 0.8,
          'stream': false,
          'top_p': 0.9,
          'presence_penalty': 0.0,
          'frequency_penalty': 0.0,
        }),
      );

      if (japaneseResponse.statusCode != 200) {
        print('DeepSeek API 错误: ${japaneseResponse.statusCode}');
        print('错误内容: ${japaneseResponse.body}');
        return {'japanese': '申し訳ございません...', 'chinese': '抱歉，我现在无法回答...'};
      }

      final japaneseData = jsonDecode(utf8.decode(japaneseResponse.bodyBytes));
      String rawJapaneseText =
          japaneseData['choices'][0]['message']['content'] as String;

      if (_hasChinese(rawJapaneseText)) {
        print('检测到中文回复，正在转换为日文...');
        rawJapaneseText = await _translateToJapanese(rawJapaneseText);
      }

      final japaneseText = _removeChinese(rawJapaneseText);

      final textForTranslation =
          japaneseText.replaceAll(RegExp(r'（[^）]*）'), '').trim();

      String chineseText;
      if (textForTranslation.isEmpty) {
        chineseText = '';
      } else {
        final translationMessages = [
          {
            'role': 'system',
            'content': '你是一个专业的日语翻译。请将用户提供的日语文本翻译成中文。只输出翻译结果，不要有任何额外的解释或说明。',
          },
          {
            'role': 'user',
            'content': '请将以下日语翻译成中文：\n$textForTranslation',
          },
        ];

        final translationResponse = await http.post(
          Uri.parse('$doubaoBaseUrl/chat/completions'),
          headers: {
            'Authorization': 'Bearer $doubaoApiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': doubaoModel,
            'messages': translationMessages,
            'max_tokens': 1000,
            'temperature': 0.3,
            'stream': false,
            'top_p': 0.9,
            'presence_penalty': 0.0,
            'frequency_penalty': 0.0,
          }),
        );

        if (translationResponse.statusCode == 200) {
          final translationData =
              jsonDecode(utf8.decode(translationResponse.bodyBytes));
          chineseText =
              translationData['choices'][0]['message']['content'] as String;
        } else {
          print('翻译 API 错误: ${translationResponse.statusCode}');
          chineseText = '[翻译失败]';
        }
      }

      return {
        'japanese': japaneseText,
        'chinese': chineseText,
        'imageDescription': imageContext.isNotEmpty
            ? imageContext.replaceFirst('\n\n【图片内容】', '')
            : '',
      };
    } catch (e) {
      print('请求失败: $e');
      return {'japanese': '申し訳ございません...', 'chinese': '抱歉，连接失败了...'};
    }
  }

  // 生成语音（GPT-SoVITS api_v2 TTS）- 支持长文本分段
  static Future<List<String>> generateSpeechSegments({
    required String text,
    required String referWavPath,
    required String promptText,
    required String promptLanguage,
    // TTS 播放速度倍率，由角色设置页面配置，默认 1.0（正常速度）
    // 范围 0.5（慢速）~ 2.0（快速），传递给 GPT-SoVITS 的 speed_factor 参数
    double speedFactor = 1.0,
  }) async {
    final cleanedText = _stripActionDescriptions(text);
    List<String> segments = _splitTextIntoSegments(cleanedText);
    List<String> audioPaths = [];

    for (int i = 0; i < segments.length; i++) {
      final segment = segments[i].trim();
      if (segment.isEmpty) continue;

      try {
        final response = await http.post(
          Uri.parse('$gptSovitsBaseUrl/tts'),
          headers: {
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'ref_audio_path': referWavPath,
            'prompt_text': promptText,
            'prompt_lang': promptLanguage,
            'text': segment,
            'text_lang': 'ja',
            'top_k': 5,
            'top_p': 0.8,
            'temperature': 0.8,
            'text_split_method': 'cut5',
            'batch_size': 1,
            'batch_threshold': 0.75,
            'split_bucket': true,
            // 使用传入的语速参数，不再硬编码 1.0
            'speed_factor': speedFactor,
            'fragment_interval': 0.3,
            'seed': -1,
            'media_type': 'wav',
            'streaming_mode': false,
            'parallel_infer': false,
            'repetition_penalty': 1.35,
          }),
        );

        if (response.statusCode == 200) {
          final tempDir = await getTemporaryDirectory();
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final filePath = '${tempDir.path}/audio_${timestamp}_$i.wav';

          final file = File(filePath);
          await file.writeAsBytes(response.bodyBytes);

          audioPaths.add(filePath);
          print('成功生成音频段 $i: $filePath (${response.bodyBytes.length} bytes)');
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

  // 切换角色模型（api_v2 新功能）
  static Future<bool> switchCharacterModel({
    required String gptModelPath,
    required String sovitsModelPath,
  }) async {
    try {
      print('正在切换模型...');
      print('GPT 模型: $gptModelPath');
      print('SoVITS 模型: $sovitsModelPath');

      final gptResponse = await http.get(
        Uri.parse(
            '$gptSovitsBaseUrl/set_gpt_weights?weights_path=$gptModelPath'),
      );

      if (gptResponse.statusCode != 200) {
        print('切换 GPT 模型失败: ${gptResponse.statusCode}');
        print('响应: ${gptResponse.body}');
        return false;
      }

      final sovitsResponse = await http.get(
        Uri.parse(
            '$gptSovitsBaseUrl/set_sovits_weights?weights_path=$sovitsModelPath'),
      );

      if (sovitsResponse.statusCode != 200) {
        print('切换 SoVITS 模型失败: ${sovitsResponse.statusCode}');
        print('响应: ${sovitsResponse.body}');
        return false;
      }

      print('模型切换成功');
      return true;
    } catch (e) {
      print('切换模型失败: $e');
      return false;
    }
  }

  // ========================================
  // 语音文本预处理
  // ========================================

  static String _stripActionDescriptions(String text) {
    String cleaned = text;
    cleaned = cleaned.replaceAll(RegExp(r'（[^）]*）'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\([^)]*\)'), '');
    cleaned = cleaned.replaceAll(RegExp(r'【[^】]*】'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\[[^\]]*\]'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\*[^*]+\*'), '');
    cleaned = cleaned.replaceAll(RegExp(r'  +'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'\n\n+'), '\n');
    cleaned = cleaned.trim();

    if (cleaned != text) {
      print('括号内容已删除');
      print('  原文: $text');
      print('  清理后: $cleaned');
    }

    return cleaned;
  }

  static List<String> _splitTextIntoSegments(String text) {
    const int maxCharsPerSegment = 30;
    List<String> segments = [];
    List<String> sentences = text.split(RegExp(r'[。！？\n]+'));
    String currentSegment = '';

    for (String sentence in sentences) {
      sentence = sentence.trim();
      if (sentence.isEmpty) continue;

      if (sentence.length > maxCharsPerSegment) {
        if (currentSegment.isNotEmpty) {
          segments.add(currentSegment);
          currentSegment = '';
        }

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
        if ((currentSegment + sentence).length > maxCharsPerSegment &&
            currentSegment.isNotEmpty) {
          segments.add(currentSegment);
          currentSegment = sentence;
        } else {
          currentSegment += (currentSegment.isEmpty ? '' : '。') + sentence;
        }
      }
    }

    if (currentSegment.isNotEmpty) {
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

    print('文本总长度: ${text.length}');
    print('分成 ${segments.length} 段');
    for (int i = 0; i < segments.length; i++) {
      print('段落 $i (${segments[i].length}字): ${segments[i]}');
    }

    return segments;
  }

  // ========================================
  // 单段语音生成
  // ========================================
  // 在 chat_page.dart 的 _sendAIMessage 和 _regenerateAudio 里调用。
  // speedFactor 由聊天页从设置中读取后传入，默认 1.0（正常速度）。
  static Future<String?> generateSpeech({
    required String text,
    required String referWavPath,
    required String promptText,
    required String promptLanguage,
    // TTS 播放速度倍率，来自设置页「TTS 语速」滑块，默认 1.0
    double speedFactor = 1.0,
  }) async {
    final cleanedText = _stripActionDescriptions(text);

    try {
      final response = await http.post(
        Uri.parse('$gptSovitsBaseUrl/tts'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'ref_audio_path': referWavPath,
          'prompt_text': promptText,
          'prompt_lang': promptLanguage,
          'text': cleanedText,
          'text_lang': 'ja',
          'top_k': 5,
          'top_p': 1.0,
          'temperature': 1.0,
          // 使用传入的语速参数，不再硬编码 1.0
          'speed_factor': speedFactor,
          'streaming_mode': false,
        }),
      );

      if (response.statusCode == 200) {
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
  static Future<bool> testDoubaoConnection() async {
    try {
      final response = await http.post(
        Uri.parse('$doubaoBaseUrl/chat/completions'),
        headers: {
          'Authorization': 'Bearer $doubaoApiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': doubaoModel,
          'messages': [
            {'role': 'user', 'content': '测试'},
          ],
          'max_tokens': 10,
          'top_p': 0.9,
          'temperature': 0.8,
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('DeepSeek 连接测试失败: $e');
      return false;
    }
  }

  // 测试 GPT-SoVITS API 连接（api_v2）
  static Future<bool> testGptSovitsConnection() async {
    try {
      final response = await http.get(
        Uri.parse('$gptSovitsBaseUrl/tts'),
      );
      return response.statusCode == 422 ||
          response.statusCode == 400 ||
          response.statusCode == 200;
    } catch (e) {
      print('GPT-SoVITS 连接测试失败: $e');
      return false;
    }
  }

  static bool _hasChinese(String text) {
    return RegExp(r'[\u4e00-\u9fff]').hasMatch(text);
  }

  static Future<String> _translateToJapanese(String chineseText) async {
    try {
      final response = await http.post(
        Uri.parse('$doubaoBaseUrl/chat/completions'),
        headers: {
          'Authorization': 'Bearer $doubaoApiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': doubaoModel,
          'messages': [
            {
              'role': 'system',
              'content':
                  'あなたは翻訳者です。中国語のテキストを自然な日本語に翻訳してください。翻訳結果だけを出力し、説明は不要です。',
            },
            {
              'role': 'user',
              'content': chineseText,
            },
          ],
          'max_tokens': 1000,
          'temperature': 0.3,
          'stream': false,
        }),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        return data['choices'][0]['message']['content'] as String;
      }
    } catch (e) {
      print('日文转换失败: $e');
    }
    return chineseText;
  }

  static String _removeChinese(String text) {
    final chineseBracketPattern = RegExp(r'（[^）]*[\u4e00-\u9fff][^）]*）');
    String result = text.replaceAll(chineseBracketPattern, '').trim();
    if (result.isEmpty) return text;
    return result;
  }

  // ========================================
  // 图片理解：调用豆包视觉模型
  // ========================================
  static Future<String> _describeImage(String imagePath) async {
    try {
      final file = File(imagePath);
      if (!await file.exists()) {
        print('图片文件不存在: $imagePath');
        return '';
      }

      final bytes = await file.readAsBytes();
      final String b64 = base64Encode(bytes);

      final ext = imagePath.toLowerCase().split('.').last;
      final String mime = const {
            'jpg': 'image/jpeg',
            'jpeg': 'image/jpeg',
            'png': 'image/png',
            'gif': 'image/gif',
            'webp': 'image/webp',
          }[ext] ??
          'image/jpeg';

      const String visionPrompt = '请用简洁的中文描述这张图片的内容，包括主要对象、场景、活动、氛围等，'
          '100字以内，只描述看到的内容，不分析不评价。';

      final response = await http.post(
        Uri.parse('$doubaoVisionBaseUrl/chat/completions'),
        headers: {
          'Authorization': 'Bearer $doubaoVisionApiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': doubaoVisionEndpoint,
          'messages': [
            {
              'role': 'user',
              'content': [
                {
                  'type': 'image_url',
                  'image_url': {'url': 'data:$mime;base64,$b64'},
                },
                {
                  'type': 'text',
                  'text': visionPrompt,
                },
              ],
            },
          ],
          'max_tokens': 200,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final String desc =
            (data['choices'][0]['message']['content'] as String?) ?? '';
        return desc.trim();
      } else {
        print('豆包视觉模型错误 ${response.statusCode}: ${response.body}');
        return '';
      }
    } catch (e) {
      print('图片理解失败: $e');
      return '';
    }
  }
}
