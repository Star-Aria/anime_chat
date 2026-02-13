import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'storage_service.dart';

class ApiService {
  static const String doubaoApiKey = 'sk-70f5215dc38d48838a52e3f47856679d';

  static const String doubaoModel = 'deepseek-chat';

  static const String doubaoBaseUrl = 'https://api.deepseek.com/v1';

  // ⚠️ GPT-SoVITS 配置（使用 api_v2）
  static const String gptSovitsBaseUrl = 'http://127.0.0.1:9880';

  // 生成对话回复（日文+中文翻译）
  static Future<Map<String, String>> generateResponse({
    required String characterPersonality,
    required List<Message> conversationHistory,
    required String userMessage,
    String? timeContext,
    String? proactiveInstruction, // 主动消息专用：直接注入system层，不作为user消息
  }) async {
    try {
      // 第一步：生成日文回复
      // 把所有内容合并成一条 system 消息，日语强制指令放在最前面
      // DeepSeek 不支持多条 role=system，多余的会被忽略
      final StringBuffer systemBuffer = StringBuffer();

      // ① 日语指令永远第一行，用日文写，避免中文环境干扰
      systemBuffer.writeln(
          'あなたは日本語キャラクターです。ユーザーが何語で話しかけても、必ず日本語のみで返答してください。中国語・英語での返答は絶対に禁止です。');
      systemBuffer.writeln();

      // ② 角色人设
      systemBuffer.write(characterPersonality);

      // ③ 时间上下文（仅追加，不放在 system 开头）
      if (timeContext != null && timeContext.isNotEmpty) {
        systemBuffer.writeln();
        systemBuffer.write(timeContext);
      }

      // ④ 主动消息指令
      if (proactiveInstruction != null && proactiveInstruction.isNotEmpty) {
        systemBuffer.writeln();
        systemBuffer.write(proactiveInstruction);
      }

      final List<Map<String, String>> japaneseMessages = [
        {
          'role': 'system',
          'content': systemBuffer.toString(),
        },
      ];

      // 调试：打印system prompt前150字，确认日语指令在最前面
      final systemContent = systemBuffer.toString();
      print(
          '📤 System prompt前150字: ${systemContent.substring(0, systemContent.length > 150 ? 150 : systemContent.length)}');
      print(
          '📤 userMessage: $userMessage | proactiveInstruction: ${proactiveInstruction != null ? "有" : "无"}');

      // 添加历史对话（只保留日文部分）
      japaneseMessages.addAll(conversationHistory.map((msg) {
        String content = msg.content;
        if (msg.role == 'assistant' && content.contains('\n\n中文：')) {
          content = content.split('\n\n中文：')[0];
        }
        return {
          'role': msg.role,
          'content': content,
        };
      }));

      // 主动消息用日文触发词，普通消息直接传用户文字
      japaneseMessages.add(
        proactiveInstruction != null
            ? {'role': 'user', 'content': '（システムトリガー）'}
            : {'role': 'user', 'content': userMessage},
      );

      // 调用 DeepSeek API
      final japaneseResponse = await http.post(
        Uri.parse('$doubaoBaseUrl/chat/completions'),
        headers: {
          'Authorization': 'Bearer $doubaoApiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': doubaoModel,
          'messages': japaneseMessages,
          'max_tokens': 500,
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

      // 语言检测兜底：含任意中文字符就强制转日文
      if (_hasChinese(rawJapaneseText)) {
        print('⚠️ 检测到中文回复，正在转换为日文...');
        rawJapaneseText = await _translateToJapanese(rawJapaneseText);
      }

      // 过滤掉AI回复中混入的中文括号动作描写
      final japaneseText = _removeChinese(rawJapaneseText);

      // 第二步：翻译成中文
      // 翻译前先去掉日文括号里的动作描写，避免翻译器把动作当成对话内容
      final textForTranslation =
          japaneseText.replaceAll(RegExp(r'（[^）]*）'), '').trim();

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

      // 调用翻译API
      final translationResponse = await http.post(
        Uri.parse('$doubaoBaseUrl/chat/completions'),
        headers: {
          'Authorization': 'Bearer $doubaoApiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': doubaoModel,
          'messages': translationMessages,
          'max_tokens': 500,
          'temperature': 0.3,
          'stream': false,
          'top_p': 0.9,
          'presence_penalty': 0.0,
          'frequency_penalty': 0.0,
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

  // 生成语音（GPT-SoVITS api_v2 TTS）- 支持长文本分段
  static Future<List<String>> generateSpeechSegments({
    required String text,
    required String referWavPath,
    required String promptText,
    required String promptLanguage,
  }) async {
    // 在分段之前先清理括号内的动作、神态描述，
    // 确保 GPT-SoVITS 只朗读真正的台词部分
    final cleanedText = _stripActionDescriptions(text);

    // 将清理后的文本按句子分段
    List<String> segments = _splitTextIntoSegments(cleanedText);
    List<String> audioPaths = [];

    for (int i = 0; i < segments.length; i++) {
      final segment = segments[i].trim();
      if (segment.isEmpty) continue;

      try {
        // 调用 GPT-SoVITS api_v2（端点是 /tts）
        final response = await http.post(
          Uri.parse('$gptSovitsBaseUrl/tts'),
          headers: {
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            // ⚠️ 注意：api_v2 的参数名和 api.py 不同
            'ref_audio_path': referWavPath,
            'prompt_text': promptText,
            'prompt_lang': promptLanguage,
            'text': segment,
            'text_lang': 'ja',

            // ⚠️ 以下是 api_v2 的参数
            'top_k': 5, // 默认值，可调整范围 3-20
            'top_p': 0.8, // 默认值，可调整范围 0.8-1.0
            'temperature': 0.8, // 默认值，可调整范围 0.6-1.5
            'text_split_method': 'cut5', // 默认值，选项：cut0-cut5
            'batch_size': 1, // 默认值，根据显存调整 1-8
            'batch_threshold': 0.75, // 默认值
            'split_bucket': true, // 默认值
            'speed_factor': 1.0, // 默认值，可调整范围 0.8-1.5
            'fragment_interval': 0.3, // 默认值，可调整范围 0.1-1.0
            'seed': -1, // 默认值，-1 表示随机
            'media_type': 'wav', // 音频格式
            'streaming_mode': false, // ⭐ 启用流式模式（推荐）
            'parallel_infer': false, // 并行推理
            'repetition_penalty': 1.35, // 默认值，可调整范围 1.0-2.0
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

      // 切换 GPT 模型
      final gptResponse = await http.get(
        Uri.parse(
            '$gptSovitsBaseUrl/set_gpt_weights?weights_path=$gptModelPath'),
      );

      if (gptResponse.statusCode != 200) {
        print('切换 GPT 模型失败: ${gptResponse.statusCode}');
        print('响应: ${gptResponse.body}');
        return false;
      }

      // 切换 SoVITS 模型
      final sovitsResponse = await http.get(
        Uri.parse(
            '$gptSovitsBaseUrl/set_sovits_weights?weights_path=$sovitsModelPath'),
      );

      if (sovitsResponse.statusCode != 200) {
        print('切换 SoVITS 模型失败: ${sovitsResponse.statusCode}');
        print('响应: ${sovitsResponse.body}');
        return false;
      }

      print('✅ 模型切换成功！');
      return true;
    } catch (e) {
      print('切换模型失败: $e');
      return false;
    }
  }

  // ========================================
  // 语音文本预处理
  // ========================================

  // 删除文本中括号内的动作、神态描述，只保留台词部分
  //
  // AI 生成的回复里经常带有括号注释，例如：
  //   （恥ずかしそうに目を逸らす）そ、そんなことはない...
  //   *頬を赤らめながら* ねえ、聞いてる？
  // 这些描述文字不应该被朗读出来，需要在发送给 GPT-SoVITS 之前删除。
  //
  // 支持删除的括号类型：
  //   （ ）  全角圆括号（最常见，AI 最常用这种）
  //   ( )   半角圆括号
  //   【 】  全角方括号
  //   [ ]   半角方括号
  //   * *   星号包裹（部分 AI 用于表示动作）
  //
  // 不删除的括号类型：
  //   「 」  日语引号（正常台词对话，不是动作描述）
  //   『 』  日语书名号/强调引号（同上）
  //
  // 如果你发现有其他需要删除的括号格式，在 RegExp 里添加对应的模式即可。
  static String _stripActionDescriptions(String text) {
    String cleaned = text;

    // 删除全角圆括号及其内容，例如：（照れながら）
    cleaned = cleaned.replaceAll(RegExp(r'（[^）]*）'), '');

    // 删除半角圆括号及其内容，例如：(blushing)
    cleaned = cleaned.replaceAll(RegExp(r'\([^)]*\)'), '');

    // 删除全角方括号及其内容，例如：【小声地】
    cleaned = cleaned.replaceAll(RegExp(r'【[^】]*】'), '');

    // 删除半角方括号及其内容，例如：[laughs]
    cleaned = cleaned.replaceAll(RegExp(r'\[[^\]]*\]'), '');

    // 删除星号包裹的内容，例如：*顔を赤くする*
    // 注意：只删除成对的星号，避免误删单个星号
    cleaned = cleaned.replaceAll(RegExp(r'\*[^*]+\*'), '');

    // 清理删除括号后产生的多余空格和空行
    // 将连续的空格合并为单个空格
    cleaned = cleaned.replaceAll(RegExp(r'  +'), ' ');
    // 将连续的换行合并为单个换行
    cleaned = cleaned.replaceAll(RegExp(r'\n\n+'), '\n');
    // 删除行首行尾的空格
    cleaned = cleaned.trim();

    // 调试输出（上线后可以注释掉这两行）
    if (cleaned != text) {
      print('括号内容已删除');
      print('  原文: $text');
      print('  清理后: $cleaned');
    }

    return cleaned;
  }

  // 将长文本分段（每段不超过30个字符，适合日语）
  static List<String> _splitTextIntoSegments(String text) {
    const int maxCharsPerSegment = 30;
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
  // 注意：此方法与 generateSpeechSegments 同样会清理括号内的动作描述，
  // 如果将来两处逻辑需要分开处理，在各自调用前单独调用 _stripActionDescriptions 即可。
  static Future<String?> generateSpeech({
    required String text,
    required String referWavPath,
    required String promptText,
    required String promptLanguage,
  }) async {
    // 清理括号内的动作、神态描述，与 generateSpeechSegments 保持一致
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
          'speed_factor': 1.0,
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
      // api_v2 的 /tts 端点会返回 422 或 400
      return response.statusCode == 422 ||
          response.statusCode == 400 ||
          response.statusCode == 200;
    } catch (e) {
      print('GPT-SoVITS 连接测试失败: $e');
      return false;
    }
  }

  // 检测文本是否含有中文字符（有一个就算）
  static bool _hasChinese(String text) {
    return RegExp(r'[\u4e00-\u9fff]').hasMatch(text);
  }

  // 将中文文本翻译成日文（兜底方案，DeepSeek输出中文时调用）
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
          'max_tokens': 500,
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

  // 过滤AI回复中混入的中文括号动作描写
  // 例：（微微点头）晚上好 → 晚上好　　（轻轻点头）夜だ → 夜だ
  static String _removeChinese(String text) {
    // 匹配 （...） 括号内包含中文字符的内容，整个括号一起删除
    final chineseBracketPattern = RegExp(r'（[^）]*[\u4e00-\u9fff][^）]*）');
    String result = text.replaceAll(chineseBracketPattern, '').trim();
    if (result.isEmpty) return text; // 若全被过滤则保留原文（方便调试）
    return result;
  }
}
