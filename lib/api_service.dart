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
  // ⚠️ 使用前请在火山引擎控制台创建「推理接入点」，把接入点ID填入 doubaoVisionEndpoint
  // ⚠️ 把你的豆包 API Key 填入 doubaoVisionApiKey
  // ========================================
  // 豆包视觉模型 API 地址
  static const String doubaoVisionBaseUrl =
      'https://ark.cn-beijing.volces.com/api/v3';
  // 豆包视觉模型接入点 ID（如：ep-20250611072348-r2klf）
  static const String doubaoVisionEndpoint = 'ep-20260213104644-59ljp';
  // 豆包 API Key（在火山引擎「API Key管理」中获取）
  static const String doubaoVisionApiKey =
      'ee7239b4-0334-4062-9819-2e365b6dd49d';

  // ⚠️ GPT-SoVITS 配置（使用 api_v2）
  static const String gptSovitsBaseUrl = 'http://127.0.0.1:9880';

  // 生成对话回复（日文+中文翻译）
  // imagePath 可选：传入图片路径时，先调用豆包视觉模型理解图片，
  // 将描述注入用户消息，使 AI 角色能自然感知并回应图片内容
  static Future<Map<String, String>> generateResponse({
    required String characterPersonality,
    required List<Message> conversationHistory,
    required String userMessage,
    String? timeContext,
    String? proactiveInstruction, // 主动消息专用：直接注入system层，不作为user消息
    String? imagePath, // 用户发送的图片本地路径（可选）
  }) async {
    try {
      // ----------------------------------------
      // 有图片时：先调用豆包视觉模型获取图片描述，
      // 拼接到用户消息末尾，作为隐式上下文传给 DeepSeek
      // ----------------------------------------
      String imageContext = '';
      if (imagePath != null && imagePath.isNotEmpty) {
        print('📷 检测到图片，调用视觉模型中...');
        final description = await _describeImage(imagePath);
        if (description.isNotEmpty) {
          // 以【图片内容】标签包裹，让 DeepSeek 知道这是图片描述而非用户文字
          imageContext = '\n\n【图片内容】$description';
          print('🖼️ 视觉模型描述: $description');
        }
      }
      // 第一步：生成日文回复
      // 把所有内容合并成一条 system 消息，日语强制指令放在最前面
      // DeepSeek 不支持多条 role=system，多余的会被忽略
      final StringBuffer systemBuffer = StringBuffer();

      // ① 角色人设
      systemBuffer.write(characterPersonality);

      // ② 时间上下文（仅追加，不放在 system 开头）
      if (timeContext != null && timeContext.isNotEmpty) {
        systemBuffer.writeln();
        systemBuffer.write(timeContext);
      }

      // ③ 主动消息指令
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
      /*final systemContent = systemBuffer.toString();
      print(
          '📤 System prompt前150字: ${systemContent.substring(0, systemContent.length > 150 ? 150 : systemContent.length)}');
      print(
          '📤 userMessage: $userMessage | proactiveInstruction: ${proactiveInstruction != null ? "有" : "无"}');*/

      // 添加历史对话（只保留日文部分；用户消息若带图片描述则追加，让AI在后续回合也能记住图片内容）
      japaneseMessages.addAll(conversationHistory.map((msg) {
        String content = msg.content;
        if (msg.role == 'assistant' && content.contains('\n\n中文：')) {
          content = content.split('\n\n中文：')[0];
        }
        // 用户消息：若保存了图片描述，在历史里补上，让 AI 始终能感知图片上下文
        if (msg.role == 'user' &&
            msg.imageDescription != null &&
            msg.imageDescription!.isNotEmpty) {
          // 去掉显示用的 '[图片]' 前缀，换成 AI 能理解的描述
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

      // 主动消息：user 消息留空，让 AI 完全依据 proactiveInstruction 自主生成
      // （原来用的「システムトリガー」会被 AI 当作用户发言原样回显，导致输出无效内容）
      japaneseMessages.add(
        proactiveInstruction != null
            ? {'role': 'user', 'content': ''}
            : {'role': 'user', 'content': '$userMessage$imageContext'},
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

      // 如果去掉动作描写后没有实质内容（全是括号动作），跳过翻译，中文留空
      // 避免把空文本发给翻译 API 导致 prompt 泄露
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
            : '', // 把描述原文返回，供 chat_page 存入 Message.imageDescription
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

  // ========================================
  // 图片理解：调用豆包视觉模型
  // ========================================
  // 读取本地图片 → base64 → 发给豆包视觉模型 → 返回中文描述
  // 调用失败时静默返回空字符串，不阻断正常对话流程
  static Future<String> _describeImage(String imagePath) async {
    try {
      final file = File(imagePath);
      if (!await file.exists()) {
        print('图片文件不存在: $imagePath');
        return '';
      }

      // 读取字节并转 base64
      final bytes = await file.readAsBytes();
      final String b64 = base64Encode(bytes);

      // 根据扩展名确定 MIME 类型（豆包支持 jpeg/png/gif/webp）
      final ext = imagePath.toLowerCase().split('.').last;
      final String mime = const {
            'jpg': 'image/jpeg',
            'jpeg': 'image/jpeg',
            'png': 'image/png',
            'gif': 'image/gif',
            'webp': 'image/webp',
          }[ext] ??
          'image/jpeg';

      // 视觉理解提示词：要求简洁描述，100字内
      // 如需修改描述风格，改这里的字符串
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
