import 'dart:convert';
import 'package:http/http.dart' as http;
import 'character_config.dart';

// ========================================
// 情绪分析服务
// ========================================
// 负责在 TTS 之前对 AI 生成的文本进行逐句情绪分析，
// 返回每个句子对应的情绪类型（SpeechEmotion 枚举）。
//
// 与上一版本的核心区别：
// - 可用情绪标签从角色的 emotionAudioMap 动态读取，
//   每个角色只声明自己有参考音频的情绪，模型只在这些里面选，
//   不会出现"有标签但没有参考音频"的情况。
// - 角色情绪表达特征说明（hint）由角色自己在配置里填写（emotionCharacterHint 字段），
//   代码里不再写死任何角色的判断逻辑。
//
// 调用方式（在 chat_page.dart 的 _sendAIMessage 里）：
//   final sentences = EmotionAnalyzer.splitSentences(japaneseText);
//   final emotions = await EmotionAnalyzer.analyzeEmotions(
//     sentences: sentences,
//     character: widget.character,
//   );
// 然后按 sentences[i] + emotions[i] 分别调用 TTS，传入对应情绪的参考语音。

class EmotionAnalyzer {
  // ----------------------------------------
  // DeepSeek API 配置（和 api_service.dart 保持同步）
  // ----------------------------------------
  // 如果 API Key 或 base URL 有变化，在 api_service.dart 里改完后同步更新这里。
  static const String _apiKey = 'sk-70f5215dc38d48838a52e3f47856679d';
  static const String _model = 'deepseek-chat';
  static const String _baseUrl = 'https://api.deepseek.com/v1';

  // ========================================
  // 主方法：分析一组句子的情绪
  // ========================================
  // 参数：
  //   sentences - 已经分好句的文本列表，每个元素对应一个 TTS 片段
  //   character - 当前角色对象，用于动态读取该角色支持的情绪标签和提示文字
  //
  // 返回：
  //   与 sentences 等长的 SpeechEmotion 列表，顺序一一对应。
  //   如果某句分析失败，该位置默认返回该角色的 fallback 情绪（通常是 neutral）。
  //
  // 网络或解析失败时不抛异常，返回全 fallback 列表，不阻断 TTS 流程。
  static Future<List<SpeechEmotion>> analyzeEmotions({
    required List<String> sentences,
    required Character character,
  }) async {
    if (sentences.isEmpty) return [];

    // ----------------------------------------
    // 从角色配置里读取该角色支持的情绪列表
    // ----------------------------------------
    // emotionAudioMap 里有哪些 key，就支持哪些情绪。
    // 如果某个角色只配置了 neutral 和 happy，模型就只会从这两个里选，
    // 不可能返回角色没有配置参考音频的情绪标签。
    final List<SpeechEmotion> availableEmotions =
        character.emotionAudioMap?.availableEmotions ?? [SpeechEmotion.neutral];

    // fallback：分析失败时的兜底情绪，优先用 neutral
    final SpeechEmotion fallback =
        availableEmotions.contains(SpeechEmotion.neutral)
            ? SpeechEmotion.neutral
            : availableEmotions.first;

    final List<SpeechEmotion> defaults =
        List.filled(sentences.length, fallback);

    // 只有一种情绪时不需要分析，直接全部返回
    if (availableEmotions.length == 1) {
      print(
          '角色 ${character.id} 只有一种情绪（${availableEmotions.first.name}），跳过情绪分析');
      return defaults;
    }

    try {
      // ----------------------------------------
      // 构造可用情绪标签的说明文本（动态生成，每个角色不同）
      // ----------------------------------------
      // 格式示例：
      //   - neutral      常规平静语气，大多数日常句子使用这个
      //   - happy        开心愉快，语调轻快上扬
      // 说明文字来自角色配置里的 emotionDescription，在 character_config.dart 里填写。
      final StringBuffer labelDescriptions = StringBuffer();
      for (final emotion in availableEmotions) {
        final String description =
            character.emotionAudioMap!.getEmotionDescription(emotion);
        labelDescriptions
            .writeln('- ${emotion.name.padRight(12)} $description');
      }

      // ----------------------------------------
      // 构造待分析句子列表（带编号，方便模型按顺序输出）
      // ----------------------------------------
      final StringBuffer sentenceList = StringBuffer();
      for (int i = 0; i < sentences.length; i++) {
        sentenceList.writeln('$i: ${sentences[i]}');
      }

      // ----------------------------------------
      // system prompt：任务说明 + 动态标签列表 + 输出格式要求
      // ----------------------------------------
      // 标签列表是动态的，只含该角色实际配置了参考音频的情绪，
      // 模型不会返回"没有对应参考音频"的标签。
      final String systemPrompt = '你是一个专业的日语语音情绪标注器。\n'
          '你的任务是为每一句日语文本判断最合适的 TTS 朗读语气，帮助 TTS 系统选择对应的参考语音。\n'
          '\n'
          '可用的情绪标签如下（只能从这些里选，不能使用其他标签）：\n'
          '$labelDescriptions'
          '\n'
          '判断原则：\n'
          '1. 判断的是"用什么样的语气朗读这句话最合适"，不是分析字面情感\n'
          '2. 有些角色说刻薄话时用的是平静语气，那就应该标 neutral\n'
          '3. 括号里的动作描述（如「（照れながら）」）可以参考语气，但不是主体\n'
          '4. 如果一句话有多种可能，选最适合 TTS 朗读效果的那个\n'
          '5. 严格只用上方列出的标签，不能发明新标签\n'
          '\n'
          '输出格式（严格遵守，不得有任何额外内容）：\n'
          '- 只输出一个 JSON 数组，长度和输入句子数量完全相同\n'
          '- 每个元素是一个字符串，对应那句话应使用的情绪标签\n'
          '- 不输出任何额外文字、解释或代码块标记（不要加 ```json）\n'
          '- 示例（3句话时）：["neutral", "happy", "neutral"]';

      // ----------------------------------------
      // user prompt：角色提示 + 待分析句子
      // ----------------------------------------
      // 角色提示由角色自己在配置里填写（Character.emotionCharacterHint），
      // 不再在代码里硬编码任何角色的判断规则。
      // 如果某个角色没有填 hint，这段就省略，让模型只凭标签描述判断。
      final String characterHintSection =
          character.emotionCharacterHint.isNotEmpty
              ? '角色语气特征说明（需严格按此执行）：\n'
                  '${character.emotionCharacterHint}\n'
                  '\n'
              : '';

      final String userPrompt = '$characterHintSection'
          '请为以下 ${sentences.length} 句话逐一标注情绪（按编号顺序输出）：\n'
          '$sentenceList';

      // ----------------------------------------
      // 调用 DeepSeek API
      // ----------------------------------------
      final response = await http.post(
        Uri.parse('$_baseUrl/chat/completions'),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': _model,
          'messages': [
            {'role': 'system', 'content': systemPrompt},
            {'role': 'user', 'content': userPrompt},
          ],
          // max_tokens：每个标签约 14 字符，200 足够约 14 句话
          'max_tokens': 200,
          // temperature 设低，分类任务要稳定，不需要创意
          'temperature': 0.2,
          'stream': false,
        }),
      );

      if (response.statusCode != 200) {
        print('情绪分析 API 错误 ${response.statusCode}，回退到默认情绪');
        return defaults;
      }

      final data = jsonDecode(utf8.decode(response.bodyBytes));
      final String rawContent =
          data['choices'][0]['message']['content'] as String;

      return _parseEmotionResponse(
        rawContent: rawContent,
        expectedCount: sentences.length,
        availableEmotions: availableEmotions,
        fallback: fallback,
        defaults: defaults,
        sentences: sentences,
      );
    } catch (e) {
      print('情绪分析失败: $e，回退到默认情绪');
      return defaults;
    }
  }

  // ========================================
  // 内部方法：解析 API 返回的情绪标签字符串
  // ========================================
  // rawContent 期望格式为 ["neutral", "happy", ...]
  // 解析失败的位置用 fallback 填充，不抛出异常。
  //
  // availableEmotions 用于校验标签是否在该角色支持的范围内：
  // 不在范围内的标签（比如角色没有配置的情绪）回退到 fallback。
  //
  // sentences 仅用于在调试日志中附带句子内容，方便排查跳句问题。
  static List<SpeechEmotion> _parseEmotionResponse({
    required String rawContent,
    required int expectedCount,
    required List<SpeechEmotion> availableEmotions,
    required SpeechEmotion fallback,
    required List<SpeechEmotion> defaults,
    required List<String> sentences,
  }) {
    try {
      // 清理可能残留的代码块标记（有些模型不听话会加 ```json）
      String cleaned =
          rawContent.replaceAll('```json', '').replaceAll('```', '').trim();

      // 找到 JSON 数组的起止位置，截取出来单独解析
      // 即使模型在数组前后加了额外文字，也能正确提取
      final int start = cleaned.indexOf('[');
      final int end = cleaned.lastIndexOf(']');
      if (start == -1 || end == -1 || end <= start) {
        print('情绪分析：返回格式不含有效 JSON 数组，回退到默认情绪');
        print('  原始内容：$cleaned');
        return defaults;
      }

      final String jsonStr = cleaned.substring(start, end + 1);
      final List<dynamic> parsed = jsonDecode(jsonStr) as List<dynamic>;

      // 构造"标签字符串 -> 枚举"映射表，只包含该角色支持的情绪
      // 不在映射表里的标签查不到，会回退到 fallback
      final Map<String, SpeechEmotion> labelMap = {
        for (final e in availableEmotions) e.name: e,
      };

      final List<SpeechEmotion> result = [];
      for (int i = 0; i < expectedCount; i++) {
        if (i < parsed.length) {
          final String label =
              (parsed[i] as String? ?? '').toLowerCase().trim();
          if (!labelMap.containsKey(label)) {
            // 模型返回了该角色不支持的标签，打印警告，回退到 fallback
            print('  警告：句子 [$i] 返回了不支持的标签 "$label"，'
                '已替换为 ${fallback.name}');
          }
          result.add(labelMap[label] ?? fallback);
        } else {
          // 模型返回数量不足，用 fallback 补齐
          result.add(fallback);
        }
      }

      // 打印最终结果，附带对应句子内容，方便调试时对照检查情绪是否准确、是否有跳句
      print('情绪分析完成（共 ${result.length} 句）：');
      for (int i = 0; i < result.length; i++) {
        final sentencePreview = i < sentences.length ? sentences[i] : '(无对应句子)';
        print('  [$i] ${result[i].name} | $sentencePreview');
      }

      return result;
    } catch (e) {
      print('情绪分析解析失败: $e，回退到默认情绪');
      return defaults;
    }
  }

  // ========================================
  // 工具方法：将日语文本按句子切分
  // ========================================
  // 按日语句子结束符（句号、叹号、问号、换行）切分，
  // 切分结果同时用于情绪分析和逐句 TTS 调用。
  //
  // 注意：和 api_service.dart 里的 _splitTextIntoSegments 用途不同：
  //   - _splitTextIntoSegments 是为了控制单段字数（不超过 30 字）
  //   - 这里是以完整句子为单位，保留完整语义供情绪分析
  // 如果某句话超过 30 字，TTS 那边会在 generateSpeech 内部自动处理长句问题。
  //
  // 返回：过滤掉空字符串后的句子列表，至少包含一个元素
  static List<String> splitSentences(String text) {
    // 先清理括号内的动作描述，和 api_service.dart 里的规则保持一致
    String cleaned = text
        .replaceAll(RegExp(r'（[^）]*）'), '') // 全角圆括号
        .replaceAll(RegExp(r'\([^)]*\)'), '') // 半角圆括号
        .replaceAll(RegExp(r'【[^】]*】'), '') // 全角方括号
        .replaceAll(RegExp(r'\[[^\]]*\]'), '') // 半角方括号
        .replaceAll(RegExp(r'\*[^*]+\*'), '') // 星号包裹的动作描述
        .trim();

    // 如果清理后为空（全是动作描述），返回原文作为单句
    // 让后续 TTS 至少尝试合成，不会直接丢掉这条消息
    if (cleaned.isEmpty) return [text];

    // 按句子结束符切分，lookbehind 保留标点在前面那句末尾
    final List<String> sentences = [];
    final parts = cleaned.split(RegExp(r'(?<=[。！？\n!?])'));

    for (final part in parts) {
      final trimmed = part.trim();
      if (trimmed.isNotEmpty) {
        sentences.add(trimmed);
      }
    }

    // 如果整段没有任何句子结束符，把整段当一句话处理
    if (sentences.isEmpty) return [cleaned];

    return sentences;
  }
}
