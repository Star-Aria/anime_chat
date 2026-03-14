import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'character_config.dart';

// ========================================
// 角色独立设置页面
// ========================================
// 每个角色拥有一套独立的设置，互不干扰。
// 所有设置均保存在 SharedPreferences，key 格式为 {设置名}_{character.id}。
//
// 涵盖的设置分类：
//   1. 用户设置      - 用户称呼（AI 如何叫你）
//   2. 主动消息设置  - 开关、发送间隔、触发概率
//   3. 语音与显示设置 - TTS 语速、情绪分析开关、翻译显示开关
//   4. 角色提示词    - 完整 system prompt 编辑 + 一键重置
//
// 调用方式（在 chat_page.dart 的 AppBar actions 里）：
//   Navigator.push(context, MaterialPageRoute(
//     builder: (context) => CharacterSettingsPage(character: widget.character),
//   ));
//   // 从设置页返回后，调用 _loadCharacterSettings() 刷新聊天页的设置缓存

class CharacterSettingsPage extends StatefulWidget {
  final Character character;

  const CharacterSettingsPage({Key? key, required this.character})
      : super(key: key);

  @override
  State<CharacterSettingsPage> createState() => _CharacterSettingsPageState();
}

class _CharacterSettingsPageState extends State<CharacterSettingsPage> {
  // ----------------------------------------
  // 文本输入控制器
  // ----------------------------------------
  // 用户在 TextField 里的输入通过这两个控制器读取
  late TextEditingController _userNameController;
  late TextEditingController _personalityController;

  // ----------------------------------------
  // 主动消息设置
  // ----------------------------------------
  // 是否允许角色在无对话时主动向用户发送消息
  bool _proactiveEnabled = true;

  // 两次主动消息之间的最短等待时间（小时）
  // 对应 character_config.dart 中的 proactiveMinIntervalHours 字段
  // 用 double 存储是为了配合 Slider 组件，保存时取整
  double _proactiveIntervalHours = 1.0;

  // 定时器到点时实际发出消息的概率，范围 0.0（从不）~ 1.0（必然发送）
  // 对应 character_config.dart 中的 proactiveIdleChance 字段
  double _proactiveChance = 1.0;

  // ----------------------------------------
  // TTS 与情绪分析设置
  // ----------------------------------------
  // 语音合成播放速度倍率，范围 0.5（慢速）~ 2.0（快速），1.0 为正常速度
  // 传递给 ApiService.generateSpeech() 的 speedFactor 参数
  double _ttsSpeed = 1.0;

  // 是否在 TTS 前调用情绪分析（EmotionAnalyzer.analyzeEmotions）
  // 关闭后每条消息跳过情绪分析，全部使用角色默认参考音频，节省一次 API 调用
  bool _emotionAnalysisEnabled = true;

  // ----------------------------------------
  // 显示设置
  // ----------------------------------------
  // 是否在 AI 消息气泡下方渲染中文翻译区域
  // 关闭后 _buildMessageBubble 只显示日文原文，不显示翻译块
  bool _showTranslation = true;

  // ----------------------------------------
  // 页面状态
  // ----------------------------------------
  // 是否正在从 SharedPreferences 读取初始值
  bool _isLoading = true;

  // 用户修改了任何设置但尚未点击「保存」时为 true
  // AppBar 保存按钮高亮、退出时提示保存均依赖此标志
  bool _hasUnsavedChanges = false;

  @override
  void initState() {
    super.initState();
    _userNameController = TextEditingController();
    _personalityController = TextEditingController();
    _loadSettings();
  }

  @override
  void dispose() {
    _userNameController.dispose();
    _personalityController.dispose();
    super.dispose();
  }

  // ========================================
  // 读取设置
  // ========================================
  // 从 SharedPreferences 加载该角色的所有设置。
  // 未找到某项设置时，回退到 character_config.dart 中的角色默认值。
  // 读取完成后注册文本变化监听，以便在用户修改内容时标记 _hasUnsavedChanges。
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final id = widget.character.id;

    // 用户称呼：未设置时为空字符串，表示沿用提示词中的内置称呼
    _userNameController.text = prefs.getString('user_name_$id') ?? '';

    // 提示词：优先用用户保存的覆盖版本；若未覆盖，显示 character_config.dart 的默认值
    final savedOverride = prefs.getString('personality_override_$id') ?? '';
    _personalityController.text =
        savedOverride.isNotEmpty ? savedOverride : widget.character.personality;

    // 主动消息设置：回退到角色默认配置值
    _proactiveEnabled = prefs.getBool('proactive_enabled_$id') ?? true;
    _proactiveIntervalHours = (prefs.getInt('proactive_interval_$id') ??
            widget.character.proactiveMinIntervalHours)
        .toDouble();
    _proactiveChance = prefs.getDouble('proactive_chance_$id') ??
        widget.character.proactiveIdleChance;

    // TTS 与情绪分析设置
    _ttsSpeed = prefs.getDouble('tts_speed_$id') ?? 1.0;
    _emotionAnalysisEnabled =
        prefs.getBool('emotion_analysis_enabled_$id') ?? true;

    // 显示设置
    _showTranslation = prefs.getBool('show_translation_$id') ?? true;

    if (mounted) {
      setState(() => _isLoading = false);
    }

    // 在加载完成后再注册监听，避免加载过程中触发「有未保存更改」
    _userNameController.addListener(_markUnsaved);
    _personalityController.addListener(_markUnsaved);
  }

  // 标记存在未保存更改（文本控制器和 Switch/Slider 回调共用）
  void _markUnsaved() {
    if (!_hasUnsavedChanges && mounted) {
      setState(() => _hasUnsavedChanges = true);
    }
  }

  // ========================================
  // 保存设置
  // ========================================
  // 将当前 UI 状态全量写入 SharedPreferences。
  // 如果某项值与默认值相同或为空，删除对应 key（节省存储、保持整洁）。
  // 保存完成后弹出 SnackBar 提示，并清除 _hasUnsavedChanges 标志。
  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final id = widget.character.id;

    // 用户称呼：为空时删除 key，让聊天页读到 null 并沿用提示词中的内置称呼
    final userName = _userNameController.text.trim();
    if (userName.isEmpty) {
      await prefs.remove('user_name_$id');
    } else {
      await prefs.setString('user_name_$id', userName);
    }

    // 提示词覆盖：为空或与默认值完全相同时删除 key（表示不覆盖，使用默认值）
    final personalityText = _personalityController.text;
    if (personalityText.isEmpty ||
        personalityText == widget.character.personality) {
      await prefs.remove('personality_override_$id');
    } else {
      await prefs.setString('personality_override_$id', personalityText);
    }

    // 主动消息设置
    await prefs.setBool('proactive_enabled_$id', _proactiveEnabled);
    await prefs.setInt(
        'proactive_interval_$id', _proactiveIntervalHours.round());
    await prefs.setDouble('proactive_chance_$id', _proactiveChance);

    // TTS 与情绪分析设置
    await prefs.setDouble('tts_speed_$id', _ttsSpeed);
    await prefs.setBool(
        'emotion_analysis_enabled_$id', _emotionAnalysisEnabled);

    // 显示设置
    await prefs.setBool('show_translation_$id', _showTranslation);

    if (mounted) {
      setState(() => _hasUnsavedChanges = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('设置已保存'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ========================================
  // 退出确认
  // ========================================
  // 有未保存更改时弹出对话框，询问是否保存后退出。
  // 返回 true 表示可以退出，false 表示留在页面继续编辑。
  Future<bool> _confirmExit() async {
    if (!_hasUnsavedChanges) return true;

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('有未保存的更改',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('是否在退出前保存设置？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'discard'),
            child: Text('不保存', style: TextStyle(color: Colors.grey[600])),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'save'),
            child: const Text('保存',
                style:
                    TextStyle(color: Colors.blue, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (result == 'save') {
      await _saveSettings();
      return true;
    }
    // result == 'discard' 时直接退出，result == null（点背景关闭）时留在页面
    return result == 'discard';
  }

  // ========================================
  // 重置提示词
  // ========================================
  // 将文本框内容恢复为 character_config.dart 中定义的默认提示词。
  // 操作前弹出二次确认，防止误操作丢失用户的修改。
  Future<void> _resetPersonalityToDefault() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title:
            const Text('重置提示词', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('确定要将提示词恢复为程序默认值吗？\n当前的修改将会丢失。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('取消', style: TextStyle(color: Colors.grey[600])),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('重置'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        _personalityController.text = widget.character.personality;
        _hasUnsavedChanges = true;
      });
    }
  }

  // ========================================
  // build
  // ========================================
  @override
  Widget build(BuildContext context) {
    final themeColor = Color(int.parse('0xFF${widget.character.color}'));

    return WillPopScope(
      // 拦截系统返回键，有未保存更改时弹出确认对话框
      onWillPop: _confirmExit,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Color(0xFF2D3142)),
            onPressed: () async {
              if (await _confirmExit()) Navigator.pop(context);
            },
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${widget.character.name} 的设置',
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2D3142)),
              ),
              Text(
                widget.character.nameJp,
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[500],
                    fontFamily: 'Times New Roman'),
              ),
            ],
          ),
          actions: [
            // 保存按钮：有未保存更改时以角色主题色高亮，否则显示灰色
            TextButton(
              onPressed: _saveSettings,
              child: Text(
                '保存',
                style: TextStyle(
                  color: _hasUnsavedChanges ? themeColor : Colors.grey[400],
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ----------------------------------------
                    // 区块 1：用户设置
                    // ----------------------------------------
                    // 控制 AI 在对话中如何称呼用户。
                    // 留空时沿用提示词中内置的称呼，不为空时追加一条覆盖指令到 system prompt。
                    _buildSectionTitle('用户设置', Icons.person_outline),
                    _buildCard([
                      _buildTextField(
                        controller: _userNameController,
                        label: '你的称呼',
                        hint: '',
                        helperText: 'AI 在对话中称呼你的名字。留空则沿用角色提示词中的内置称呼。',
                        maxLines: 1,
                      ),
                    ]),

                    const SizedBox(height: 20),

                    // ----------------------------------------
                    // 区块 2：主动消息设置
                    // ----------------------------------------
                    // 控制角色在无对话时是否主动发消息，以及发送的频率和概率。
                    // 这些设置会覆盖 character_config.dart 中该角色的默认配置，
                    // 由 ProactiveMessageService._getEffectiveSettings() 在触发时读取生效。
                    _buildSectionTitle('主动消息设置', Icons.schedule_outlined),
                    _buildCard([
                      _buildSwitch(
                        title: '启用主动消息',
                        description: '允许角色在没有对话时主动向你发送消息',
                        value: _proactiveEnabled,
                        color: themeColor,
                        onChanged: (v) => setState(() {
                          _proactiveEnabled = v;
                          _hasUnsavedChanges = true;
                        }),
                      ),
                      // 以下两个滑块仅在主动消息开启时显示
                      if (_proactiveEnabled) ...[
                        const Divider(height: 24, thickness: 0.5),
                        _buildSlider(
                          title: '最短发送间隔',
                          description: '两次主动消息之间的最短等待时间',
                          value: _proactiveIntervalHours,
                          min: 0,
                          max: 168, // 最长一周
                          divisions: 168,
                          // 0 小时时显示「无限制」，方便测试时使用
                          displayLabel: _proactiveIntervalHours == 0
                              ? '无限制'
                              : '${_proactiveIntervalHours.round()} 小时',
                          color: themeColor,
                          onChanged: (v) => setState(() {
                            _proactiveIntervalHours = v;
                            _hasUnsavedChanges = true;
                          }),
                        ),
                        const Divider(height: 24, thickness: 0.5),
                        _buildSlider(
                          title: '触发概率',
                          description: '定时器到点时实际发送消息的概率',
                          value: _proactiveChance,
                          min: 0.0,
                          max: 1.0,
                          divisions: 20,
                          displayLabel: '${(_proactiveChance * 100).round()}%',
                          color: themeColor,
                          onChanged: (v) => setState(() {
                            _proactiveChance = v;
                            _hasUnsavedChanges = true;
                          }),
                        ),
                      ],
                    ]),

                    const SizedBox(height: 20),

                    // ----------------------------------------
                    // 区块 3：语音与显示设置
                    // ----------------------------------------
                    // TTS 语速：传递给 ApiService.generateSpeech() 的 speedFactor 参数
                    // 情绪分析开关：关闭时跳过 EmotionAnalyzer，全部使用默认参考音频
                    // 翻译显示开关：关闭时 _buildMessageBubble 只渲染日文原文
                    _buildSectionTitle('语音与显示设置', Icons.tune_outlined),
                    _buildCard([
                      _buildSlider(
                        title: 'TTS 语速',
                        description: '语音合成的播放速度倍率，1.0 为正常速度',
                        value: _ttsSpeed,
                        min: 0.5,
                        max: 2.0,
                        divisions: 15,
                        displayLabel: '${_ttsSpeed.toStringAsFixed(1)}x',
                        color: themeColor,
                        onChanged: (v) => setState(() {
                          _ttsSpeed = v;
                          _hasUnsavedChanges = true;
                        }),
                      ),
                      const Divider(height: 24, thickness: 0.5),
                      _buildSwitch(
                        title: '启用情绪分析',
                        description: '根据文本内容自动匹配情绪语音参考音频，需要消耗一次额外的 API 调用',
                        value: _emotionAnalysisEnabled,
                        color: themeColor,
                        onChanged: (v) => setState(() {
                          _emotionAnalysisEnabled = v;
                          _hasUnsavedChanges = true;
                        }),
                      ),
                      const Divider(height: 24, thickness: 0.5),
                      _buildSwitch(
                        title: '显示中文翻译',
                        description: '在每条 AI 消息气泡下方显示中文翻译内容',
                        value: _showTranslation,
                        color: themeColor,
                        onChanged: (v) => setState(() {
                          _showTranslation = v;
                          _hasUnsavedChanges = true;
                        }),
                      ),
                    ]),

                    const SizedBox(height: 20),

                    // ----------------------------------------
                    // 区块 4：角色提示词
                    // ----------------------------------------
                    // 完整编辑该角色发送给 DeepSeek 的 system prompt。
                    // 修改后保存到 personality_override_{id}，
                    // 聊天页读取时优先使用覆盖版本（_effectivePersonality getter）。
                    // 一键重置按钮可恢复 character_config.dart 中的默认提示词。
                    _buildSectionTitle('角色提示词', Icons.edit_note_outlined),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '修改角色的 system prompt，控制 AI 的性格、语气和背景设定。'
                        '修改不当可能导致角色行为异常，可随时重置为程序默认值。',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey[500], height: 1.5),
                      ),
                    ),
                    _buildCard([
                      _buildTextField(
                        controller: _personalityController,
                        label: '提示词内容',
                        hint: '输入角色提示词...',
                        maxLines: 20,
                        useMonospace: true,
                      ),
                      const SizedBox(height: 12),
                      // 重置按钮：将文本框内容恢复为 character_config.dart 中的默认值
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.restore, size: 16),
                          label: const Text('恢复默认提示词',
                              style: TextStyle(fontSize: 13)),
                          onPressed: _resetPersonalityToDefault,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red[600],
                            side: BorderSide(color: Colors.red.shade200),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                    ]),

                    // 底部留白，避免在软键盘弹起时内容被遮挡
                    const SizedBox(height: 48),
                  ],
                ),
              ),
      ),
    );
  }

  // ========================================
  // 辅助 Widget 构建方法
  // ========================================

  // 区块标题行：小图标 + 分类文字
  Widget _buildSectionTitle(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 2),
      child: Row(
        children: [
          Icon(icon, size: 15, color: Colors.grey[600]),
          const SizedBox(width: 5),
          Text(
            title,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
                letterSpacing: 0.4),
          ),
        ],
      ),
    );
  }

  // 白色圆角卡片容器，用于包裹同一分类下的多个设置项
  Widget _buildCard(List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  // 带标签文字的文本输入框
  // useMonospace：提示词编辑时使用等宽字体，方便查看格式
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    String? helperText,
    int maxLines = 1,
    bool useMonospace = false,
  }) {
    final themeColor = Color(int.parse('0xFF${widget.character.color}'));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Color(0xFF2D3142))),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: maxLines,
          style: TextStyle(
            fontSize: 13,
            fontFamily: useMonospace ? 'monospace' : null,
            color: const Color(0xFF2D3142),
            height: 1.5,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
            helperText: helperText,
            helperStyle:
                TextStyle(fontSize: 11, color: Colors.grey[500], height: 1.4),
            helperMaxLines: 3,
            filled: true,
            fillColor: const Color(0xFFF8F9FB),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            // 聚焦时边框颜色切换为角色主题色
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: themeColor),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
      ],
    );
  }

  // 开关设置行：左侧标题+说明，右侧 Switch
  Widget _buildSwitch({
    required String title,
    required String description,
    required bool value,
    required Color color,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF2D3142))),
              const SizedBox(height: 2),
              Text(description,
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey[500], height: 1.3)),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Switch(value: value, onChanged: onChanged, activeColor: color),
      ],
    );
  }

  // 滑块设置行：标题+说明在左，当前值气泡在右，下方为 Slider
  Widget _buildSlider({
    required String title,
    required String description,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String displayLabel, // 显示在气泡中的当前值文字
    required Color color,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF2D3142))),
                  const SizedBox(height: 2),
                  Text(description,
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey[500], height: 1.3)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // 当前值气泡，使用角色主题色
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                displayLabel,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: color),
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: color,
            inactiveTrackColor: color.withOpacity(0.15),
            thumbColor: color,
            overlayColor: color.withOpacity(0.12),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
