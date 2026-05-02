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

  // ========================================
  // 中译日校验与重试参数（可调）
  // ========================================
  // _maxTranslationRetries：翻译失败时最多重试几次。
  //   网络抖动、API 偶发返回奇怪格式（如返回中文、返回空、返回带 markdown 的内容）时，
  //   会自动再调用一次翻译 API。次数过多会拖慢响应速度，建议 2~4 之间。
  // _japaneseFallbackText：所有重试都失败后兜底用的日语句子。
  //   存在的意义是：宁可让 AI 随便说一句日语兜底，也绝不能把中文塞给 TTS（GPT-SoVITS）
  //   导致语音乱掉、字幕也是中文。如果想换文案，改这里即可，但必须是纯日语。
  static const int _maxTranslationRetries = 3;
  static const String _japaneseFallbackText = 'ごめん、ちょっと言葉が出てこなかった…もう一度話してくれる？';

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
          content = '$textPart【图片内容】${msg.imageDescription}';
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

      // ========================================
      // 中译日的核心校验逻辑（修复后）
      // ========================================
      // 旧版本只判断"是否含中文字符"，但日语本身就有汉字，这个判断本身已经不严谨；
      // 更严重的是翻译失败时静默回退到原中文，导致 TTS 拿到中文文本生成混乱语音。
      //
      // 新版本采用「是否含日语假名（平假名/片假名）」作为「翻译成功」的判定依据：
      //   - 任何一句正常日语都至少会有一个假名（即使是含大量汉字的句子）
      //   - 纯中文不可能含假名，因此假名是中日文最可靠的区分点
      //
      // 流程：
      //   1) 如果原文已含假名，认为本身就是日语，跳过翻译
      //   2) 否则进入翻译循环，最多重试 _maxTranslationRetries 次：
      //      - 调用 _translateToJapanese 翻译
      //      - 翻译结果若含假名 -> 成功，break
      //      - 翻译结果不含假名 -> 视为失败，再来一次
      //   3) 全部重试都失败时，使用 _japaneseFallbackText 兜底，
      //      绝不把中文塞给 TTS（这是出问题最直观的根因）
      if (!_isLikelyJapanese(rawJapaneseText)) {
        print('回复未检测到日语假名，判定为非日语，开始翻译为日文...');
        print('  原始内容: $rawJapaneseText');

        String translated = rawJapaneseText;
        bool success = false;

        for (int attempt = 1; attempt <= _maxTranslationRetries; attempt++) {
          print('  翻译尝试 $attempt / $_maxTranslationRetries ...');
          translated = await _translateToJapanese(rawJapaneseText);

          // 校验翻译结果是否为日语：含假名才算成功
          if (_isLikelyJapanese(translated)) {
            print('  翻译成功（第 $attempt 次）: $translated');
            success = true;
            break;
          } else {
            print('  翻译结果仍未检测到假名，视为失败，准备重试');
            print('  本次返回: $translated');
          }
        }

        if (success) {
          rawJapaneseText = translated;
        } else {
          // 多次重试仍失败，使用兜底日语文本
          // 这样确保 TTS 生成的语音和最终展示的字幕都是日语，
          // 不会出现 GPT-SoVITS 拿中文去合成的情况
          print('  翻译多次失败，使用兜底日语文本: $_japaneseFallbackText');
          rawJapaneseText = _japaneseFallbackText;
        }
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

  // ========================================
  // 中文检测（旧函数，保留以防其他地方引用）
  // ========================================
  // 注意：本函数仅检测「文本是否包含中文字符（即 CJK 统一汉字）」。
  // 由于日语本身也用汉字，单凭这个判断不足以区分中日文，
  // 因此 generateResponse 内部的语种判断已经改为使用 _isLikelyJapanese。
  // 这个函数本身没有删除，方便其他地方（如调试或将来的扩展）继续调用。
  static bool _hasChinese(String text) {
    return RegExp(r'[\u4e00-\u9fff]').hasMatch(text);
  }

  // ========================================
  // 日语判定（新增）
  // ========================================
  // 判断文本是否「像日语」：只要含至少一个平假名（ぁ-ゖ）或片假名（ァ-ヺ），就视为日语。
  // 原因：
  //   - 中文里没有假名，只要出现假名一定不是纯中文
  //   - 任意一句自然日语几乎一定会出现假名（助词、词尾变化、外来语等）
  //   - 偶尔会出现一整句全是汉字的日语（例如「日本語」三个字本身），
  //     但 AI 生成的对话回复几乎不可能全句不含假名，所以这种边缘情况可以接受
  // 这是当前用来判断"翻译是否成功"的最可靠依据，比 _hasChinese 更严谨。
  static bool _isLikelyJapanese(String text) {
    // 平假名范围：U+3040 ~ U+309F
    // 片假名范围：U+30A0 ~ U+30FF
    return RegExp(r'[\u3040-\u309f\u30a0-\u30ff]').hasMatch(text);
  }

  // ========================================
  // 调用 DeepSeek 把中文翻译成日语
  // ========================================
  // 调用方：generateResponse 内部，在判定回复非日语时使用。
  // 改动点：
  //   - 增加了对返回内容的清洗（去掉可能残留的代码块、前缀说明等）
  //   - 把 system prompt 改为更明确的指令，要求只返回日语本体
  //   - 不再在异常时静默返回原中文，而是返回空字符串，
  //     由外层 generateResponse 的 _isLikelyJapanese 校验决定是否重试或兜底，
  //     彻底杜绝把中文继续传给 TTS 的可能
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
              'content': 'あなたはプロの中日翻訳者です。\n'
                  'ユーザーが入力した中国語のテキストを、自然で口語的な日本語に翻訳してください。\n'
                  '\n'
                  '厳守事項:\n'
                  '1. 出力は日本語のみ。中国語の文字、説明、注釈、コードブロック、引用符を一切含めないこと。\n'
                  '2. 「翻訳:」「日本語:」のような前置きを付けない。翻訳本文のみを出力する。\n'
                  '3. 元のテキストに括弧書きの動作描写（例:（笑顔で））がある場合は日本語の括弧で残してよい。\n'
                  '4. 必ず平仮名または片仮名を含む自然な日本語で出力すること。',
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
        String result = data['choices'][0]['message']['content'] as String;
        // 清理模型有时会返回的 markdown 代码块标记和常见前缀
        // 即使 system prompt 已经禁止，仍偶发出现，这里再兜一层
        result = result
            .replaceAll('```japanese', '')
            .replaceAll('```ja', '')
            .replaceAll('```', '')
            .trim();
        // 去掉一些可能的中文前缀（如「翻译：」「日文：」）
        // 只在开头匹配，避免误删正文里的内容
        result = result.replaceFirst(RegExp(r'^(翻訳|翻译|日本語|日文|译文)[:：]\s*'), '');
        return result.trim();
      } else {
        print('日文转换 API 错误: ${response.statusCode}');
        print('错误内容: ${response.body}');
      }
    } catch (e) {
      print('日文转换失败: $e');
    }
    // 失败时返回空字符串而不是原中文。
    // 外层 generateResponse 会用 _isLikelyJapanese 判断这个空串"不是日语"，
    // 进入下一次重试或兜底文案，从而保证最终一定是日语进 TTS。
    return '';
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
