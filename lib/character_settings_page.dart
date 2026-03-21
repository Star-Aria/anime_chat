import 'dart:ui'; // 用于毛玻璃滤镜 ImageFilter
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'character_config.dart';

// ========================================
// 自定义配置区域：设置页面视觉与排版
// ========================================

// 1. 字体与文本样式配置
// 你可以在这里分别设置不同层级文字的 fontFamily、fontSize 等属性
const String SETTINGS_TITLE_FONT = 'SimSun'; // 顶栏标题字体
const double SETTINGS_TITLE_SIZE = 16.0;

const String SETTINGS_SECTION_FONT = 'SimSun'; // 区块标题字体 (如 "用户设置")
const double SETTINGS_SECTION_SIZE = 13.0;

const String SETTINGS_ITEM_TITLE_FONT = 'FangSong'; // 设置项主标题字体 (如 "你的称呼")
const double SETTINGS_ITEM_TITLE_SIZE = 14.0;

const String SETTINGS_ITEM_DESC_FONT = 'FangSong'; // 设置项描述字体
const double SETTINGS_ITEM_DESC_SIZE = 13.0;

const String SETTINGS_INPUT_TEXT_FONT = 'FangSong'; // 输入框内文字字体
const double SETTINGS_INPUT_TEXT_SIZE = 13.0;

// 2. 页面背景配置
// 调整这个颜色可以改变设置页的全局基础背景色（默认为淡灰色）
const Color SETTINGS_PAGE_BG_COLOR = Color(0xFFF0F2F5);

// 3. 液态彩色玻璃质感核心配置 (重要调整区域)
const double GLASS_BLUR_SIGMA = 16.0; // 毛玻璃模糊度。数值越大，透出的底层灰色背景越模糊、越柔和
const double GLASS_BORDER_OPACITY = 0.5; // 卡片边缘白色高光的透明度。0.0 完全透明，1.0 是纯白实线

// 以下参数控制玻璃面板卡片的径向渐变 (RadialGradient) 效果
// 核心逻辑：中心使用极淡的白色透过灰色背景，边缘使用角色专属颜色
const double GLASS_CENTER_WHITE_OPACITY = 0.08; // 中心的白色透明度。越低越通透，越高玻璃越呈磨砂白
const double GLASS_EDGE_COLOR_OPACITY = 0.35; // 边缘角色的彩色透明度。数值越大，边缘的颜色越浓重

// 发光阴影配置
// 注意：如果透明度过高，阴影会从卡片中心穿透出来，破坏玻璃的通透感
const double GLASS_GLOW_BLUR_RADIUS = 20.0; // 发光效果的模糊扩散范围
const double GLASS_GLOW_SPREAD_RADIUS = 0.0; // 发光效果的向外扩张程度，设为0保持光晕柔和
const double GLASS_GLOW_OPACITY = 0.15; // 发光颜色的透明度，建议保持在 0.1~0.2 之间避免穿透

// ========================================
// 角色独立设置页面
// ========================================
// 每个角色拥有一套独立的设置，互不干扰。
// 所有设置均保存在 SharedPreferences，key 格式为 {设置名}_{character.id}。
//
// 涵盖的设置分类：
//   1. 用户设置      - 用户称呼（AI 如何叫你）及读音（供 TTS 使用）
//   2. 主动消息设置  - 开关、发送间隔、触发概率
//   3. 语音与显示设置 - TTS 语速、情绪分析开关、原文/翻译显示开关
//   4. 角色提示词    - 完整 system prompt 编辑 + 一键重置

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
  late TextEditingController _userNameController;
  late TextEditingController _userNamePronunciationController; // 新增：用户称呼的读音/假名
  late TextEditingController _personalityController;

  // ----------------------------------------
  // 主动消息设置
  // ----------------------------------------
  bool _proactiveEnabled = true;
  double _proactiveIntervalHours = 1.0;
  double _proactiveChance = 1.0;

  // ----------------------------------------
  // TTS 与情绪分析设置
  // ----------------------------------------
  double _ttsSpeed = 1.0;
  bool _emotionAnalysisEnabled = true;

  // ----------------------------------------
  // 显示设置
  // ----------------------------------------
  bool _showOriginal = true; // 新增：是否显示日文原文
  bool _showTranslation = true;

  // ----------------------------------------
  // 页面状态
  // ----------------------------------------
  bool _isLoading = true;
  bool _hasUnsavedChanges = false;

  @override
  void initState() {
    super.initState();
    _userNameController = TextEditingController();
    _userNamePronunciationController = TextEditingController(); // 初始化读音控制器
    _personalityController = TextEditingController();
    _loadSettings();
  }

  @override
  void dispose() {
    _userNameController.dispose();
    _userNamePronunciationController.dispose();
    _personalityController.dispose();
    super.dispose();
  }

  // ========================================
  // 读取设置
  // ========================================
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final id = widget.character.id;

    // 用户称呼与读音
    _userNameController.text = prefs.getString('user_name_$id') ?? '';
    _userNamePronunciationController.text =
        prefs.getString('user_name_pronunciation_$id') ?? '';

    // 提示词
    final savedOverride = prefs.getString('personality_override_$id') ?? '';
    _personalityController.text =
        savedOverride.isNotEmpty ? savedOverride : widget.character.personality;

    // 主动消息设置
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
    _showOriginal = prefs.getBool('show_original_$id') ?? true; // 读取原文显示设置
    _showTranslation = prefs.getBool('show_translation_$id') ?? true;

    if (mounted) {
      setState(() => _isLoading = false);
    }

    _userNameController.addListener(_markUnsaved);
    _userNamePronunciationController.addListener(_markUnsaved);
    _personalityController.addListener(_markUnsaved);
  }

  void _markUnsaved() {
    if (!_hasUnsavedChanges && mounted) {
      setState(() => _hasUnsavedChanges = true);
    }
  }

  // ========================================
  // 保存设置
  // ========================================
  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final id = widget.character.id;

    // 保存用户称呼
    final userName = _userNameController.text.trim();
    if (userName.isEmpty) {
      await prefs.remove('user_name_$id');
    } else {
      await prefs.setString('user_name_$id', userName);
    }

    // 保存读音
    final userPronunciation = _userNamePronunciationController.text.trim();
    if (userPronunciation.isEmpty) {
      await prefs.remove('user_name_pronunciation_$id');
    } else {
      await prefs.setString('user_name_pronunciation_$id', userPronunciation);
    }

    // 提示词覆盖
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
    await prefs.setBool('show_original_$id', _showOriginal);
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
    return result == 'discard';
  }

  // ========================================
  // 重置提示词
  // ========================================
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
    // 取出为当前角色配置的彩色玻璃发光颜色
    final glassColor = widget.character.settingsGlassColor;

    return WillPopScope(
      onWillPop: _confirmExit,
      child: Scaffold(
        backgroundColor: SETTINGS_PAGE_BG_COLOR, // 使用统一的淡灰色背景
        extendBodyBehindAppBar: true, // 允许背景延伸到 AppBar 底部
        appBar: AppBar(
          backgroundColor: Colors.white.withOpacity(0.7), // AppBar 增加微透明
          elevation: 0,
          flexibleSpace: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(color: Colors.transparent),
            ),
          ),
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
                    fontFamily: SETTINGS_TITLE_FONT,
                    fontSize: SETTINGS_TITLE_SIZE,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2D3142)),
              ),
              Text(
                widget.character.nameJp,
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                    fontFamily: 'Times New Roman'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: _saveSettings,
              child: Text(
                '保存',
                style: TextStyle(
                  fontFamily: SETTINGS_TITLE_FONT,
                  color: _hasUnsavedChanges ? themeColor : Colors.grey[500],
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: _isLoading
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
                      _buildSectionTitle('用户设置', Icons.person_outline),
                      _buildCard(
                        glassColor: glassColor,
                        children: [
                          _buildTextField(
                            controller: _userNameController,
                            label: '你的称呼 ',
                            hint: '例如：凛野',
                            helperText: '你希望AI称呼你使用的名字',
                            maxLines: 1,
                          ),
                          const SizedBox(height: 16),
                          _buildTextField(
                            controller: _userNamePronunciationController,
                            label: '你的称呼读音 ',
                            hint: '请填写假名，例如：りんの',
                            helperText: '如果不填，语音合成可能无法准确读出你的名字。',
                            maxLines: 1,
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // ----------------------------------------
                      // 区块 2：主动消息设置
                      // ----------------------------------------
                      _buildSectionTitle('主动消息设置', Icons.schedule_outlined),
                      _buildCard(
                        glassColor: glassColor,
                        children: [
                          _buildSwitch(
                            title: '启用主动消息',
                            description: '允许角色在没有对话时主动向你发送消息',
                            value: _proactiveEnabled,
                            color: themeColor, // 组件交互颜色仍使用角色主色调
                            onChanged: (v) => setState(() {
                              _proactiveEnabled = v;
                              _hasUnsavedChanges = true;
                            }),
                          ),
                          if (_proactiveEnabled) ...[
                            const Divider(
                                height: 24,
                                thickness: 0.5,
                                color: Colors.white54),
                            _buildSlider(
                              title: '最短发送间隔',
                              description: '两次主动消息之间的最短等待时间',
                              value: _proactiveIntervalHours,
                              min: 0,
                              max: 168,
                              divisions: 168,
                              displayLabel: _proactiveIntervalHours == 0
                                  ? '无限制'
                                  : '${_proactiveIntervalHours.round()} 小时',
                              color: themeColor,
                              onChanged: (v) => setState(() {
                                _proactiveIntervalHours = v;
                                _hasUnsavedChanges = true;
                              }),
                            ),
                            const Divider(
                                height: 24,
                                thickness: 0.5,
                                color: Colors.white54),
                            _buildSlider(
                              title: '触发概率',
                              description: '定时器到点时实际发送消息的概率',
                              value: _proactiveChance,
                              min: 0.0,
                              max: 1.0,
                              divisions: 20,
                              displayLabel:
                                  '${(_proactiveChance * 100).round()}%',
                              color: themeColor,
                              onChanged: (v) => setState(() {
                                _proactiveChance = v;
                                _hasUnsavedChanges = true;
                              }),
                            ),
                          ],
                        ],
                      ),

                      const SizedBox(height: 20),

                      // ----------------------------------------
                      // 区块 3：语音与显示设置
                      // ----------------------------------------
                      _buildSectionTitle('语音与显示设置', Icons.tune_outlined),
                      _buildCard(
                        glassColor: glassColor,
                        children: [
                          _buildSlider(
                            title: 'TTS 语速',
                            description: '语音合成的播放速度倍率，1.0为正常速度',
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
                          const Divider(
                              height: 24,
                              thickness: 0.5,
                              color: Colors.white54),
                          _buildSwitch(
                            title: '启用情绪分析',
                            description: '根据文本内容自动匹配合适的语音合成情绪',
                            value: _emotionAnalysisEnabled,
                            color: themeColor,
                            onChanged: (v) => setState(() {
                              _emotionAnalysisEnabled = v;
                              _hasUnsavedChanges = true;
                            }),
                          ),
                          const Divider(
                              height: 24,
                              thickness: 0.5,
                              color: Colors.white54),
                          _buildSwitch(
                            title: '显示日文原文',
                            description: '在消息气泡中显示AI回复的日文原文',
                            value: _showOriginal,
                            color: themeColor,
                            onChanged: (v) => setState(() {
                              _showOriginal = v;
                              _hasUnsavedChanges = true;
                            }),
                          ),
                          const Divider(
                              height: 24,
                              thickness: 0.5,
                              color: Colors.white54),
                          _buildSwitch(
                            title: '显示中文翻译',
                            description: '在消息气泡中显示AI回复的中文翻译',
                            value: _showTranslation,
                            color: themeColor,
                            onChanged: (v) => setState(() {
                              _showTranslation = v;
                              _hasUnsavedChanges = true;
                            }),
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // ----------------------------------------
                      // 区块 4：角色提示词
                      // ----------------------------------------
                      _buildSectionTitle('角色提示词', Icons.edit_note_outlined),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          '修改角色的system prompt，控制AI的性格、语气和背景设定。\n修改不当可能导致角色行为异常，可随时重置为程序默认值。',
                          style: TextStyle(
                              fontFamily: SETTINGS_ITEM_DESC_FONT,
                              fontSize: SETTINGS_ITEM_DESC_SIZE,
                              color: Colors.black54,
                              height: 1.5),
                        ),
                      ),
                      _buildCard(
                        glassColor: glassColor,
                        children: [
                          _buildTextField(
                            controller: _personalityController,
                            label: '提示词内容',
                            hint: '输入角色提示词...',
                            maxLines: 20,
                            useFangSong: true,
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.restore, size: 16),
                              label: const Text('恢复默认提示词',
                                  style: TextStyle(
                                      fontFamily: SETTINGS_ITEM_TITLE_FONT,
                                      fontSize: 13)),
                              onPressed: _resetPersonalityToDefault,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red[600],
                                side: BorderSide(color: Colors.red.shade200),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 10),
                                backgroundColor:
                                    Colors.white.withOpacity(0.5), // 按钮也带点半透明质感
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 48),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  // ========================================
  // 辅助 Widget 构建方法
  // ========================================

  Widget _buildSectionTitle(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Row(
        children: [
          Icon(icon, size: 15, color: Colors.black87),
          const SizedBox(width: 5),
          Text(
            title,
            style: const TextStyle(
                fontFamily: SETTINGS_SECTION_FONT,
                fontSize: SETTINGS_SECTION_SIZE,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
                letterSpacing: 0.4),
          ),
        ],
      ),
    );
  }

  // 构建液态彩色边缘发光的玻璃质感卡片
  Widget _buildCard(
      {required Color glassColor, required List<Widget> children}) {
    return Container(
      // 外层容器专门用于渲染彩色发光阴影
      // 如果阴影透明度过高，就会发生“阴影穿透”，导致卡片中心全部变成底部的阴影色
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: glassColor.withOpacity(GLASS_GLOW_OPACITY),
            blurRadius: GLASS_GLOW_BLUR_RADIUS,
            spreadRadius: GLASS_GLOW_SPREAD_RADIUS,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          // 毛玻璃滤镜：模糊掉底部的阴影和灰色背景
          filter: ImageFilter.blur(
              sigmaX: GLASS_BLUR_SIGMA, sigmaY: GLASS_BLUR_SIGMA),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              // 核心修复：使用 RadialGradient 并配合 stops 来强制划分中心与边缘
              gradient: RadialGradient(
                colors: [
                  // 中心区域：极度透明的白色，确保能透出灰色的背景，展现“清透”的玻璃感
                  Colors.white.withOpacity(GLASS_CENTER_WHITE_OPACITY),
                  // 边缘区域：应用角色专属的彩色
                  glassColor.withOpacity(GLASS_EDGE_COLOR_OPACITY),
                ],
                // stops 控制渐变比例：0.0到0.3的区域保留中心色，0.3之后才开始向边缘的彩色过渡
                // 这个参数是防止边缘颜色向内过度蔓延的关键
                stops: const [0.3, 1.0],
                radius: 1.2, // 半径 1.2 适合长方形卡片，既能看到边缘色，又不至于拉伸变形
              ),
              borderRadius: BorderRadius.circular(16),
              // 高光边框：增加玻璃切边的反光质感
              border: Border.all(
                color: Colors.white.withOpacity(GLASS_BORDER_OPACITY),
                width: 1.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    String? helperText,
    int maxLines = 1,
    bool useFangSong = false,
  }) {
    final themeColor = Color(int.parse('0xFF${widget.character.color}'));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontFamily: SETTINGS_ITEM_TITLE_FONT,
                fontSize: SETTINGS_ITEM_TITLE_SIZE,
                fontWeight: FontWeight.w600,
                color: Color(0xFF2D3142))),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: maxLines,
          style: TextStyle(
            fontFamily: useFangSong ? 'FangSong' : SETTINGS_INPUT_TEXT_FONT,
            fontSize: SETTINGS_INPUT_TEXT_SIZE,
            color: const Color(0xFF2D3142),
            height: 1.5,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
                fontFamily: SETTINGS_INPUT_TEXT_FONT,
                color: Colors.grey[500],
                fontSize: SETTINGS_INPUT_TEXT_SIZE),
            helperText: helperText,
            helperStyle: TextStyle(
                fontFamily: SETTINGS_ITEM_DESC_FONT,
                fontSize: 11,
                color: Colors.black54,
                height: 1.4),
            helperMaxLines: 3,
            filled: true,
            fillColor: Colors.white.withOpacity(0.6), // 输入框轻微透明，融入玻璃卡片
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.8)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.8)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: themeColor), // 聚焦时使用角色主题色
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
      ],
    );
  }

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
                      fontFamily: SETTINGS_ITEM_TITLE_FONT,
                      fontSize: SETTINGS_ITEM_TITLE_SIZE,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF2D3142))),
              const SizedBox(height: 2),
              Text(description,
                  style: const TextStyle(
                      fontFamily: SETTINGS_ITEM_DESC_FONT,
                      fontSize: SETTINGS_ITEM_DESC_SIZE,
                      color: Colors.black54,
                      height: 1.3)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // 使用 Transform.scale 缩小 Switch 组件的体积
        Transform.scale(
          scale: 0.75,
          child: Switch(value: value, onChanged: onChanged, activeColor: color),
        ),
      ],
    );
  }

  Widget _buildSlider({
    required String title,
    required String description,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String displayLabel,
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
                          fontFamily: SETTINGS_ITEM_TITLE_FONT,
                          fontSize: SETTINGS_ITEM_TITLE_SIZE,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF2D3142))),
                  const SizedBox(height: 2),
                  Text(description,
                      style: const TextStyle(
                          fontFamily: SETTINGS_ITEM_DESC_FONT,
                          fontSize: SETTINGS_ITEM_DESC_SIZE,
                          color: Colors.black54,
                          height: 1.3)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withOpacity(0.3)), // 气泡描边
              ),
              child: Text(
                displayLabel,
                style: TextStyle(
                    fontFamily: SETTINGS_ITEM_TITLE_FONT,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: color),
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: color,
            inactiveTrackColor: color.withOpacity(0.2),
            thumbColor: color,
            overlayColor: color.withOpacity(0.12),
            trackHeight: 3.0, // 让滑轨变细一点，看起来更精致
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
