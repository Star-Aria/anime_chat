import 'dart:ui'; // 用于毛玻璃滤镜 ImageFilter
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'character_config.dart';

// ========================================
// 自定义配置区域：设置页面视觉与排版
// ========================================

const String SETTINGS_TITLE_FONT = 'SimSun';
const double SETTINGS_TITLE_SIZE = 16.0;

const String SETTINGS_SECTION_FONT = 'SimSun';
const double SETTINGS_SECTION_SIZE = 13.0;

const String SETTINGS_ITEM_TITLE_FONT = 'FangSong';
const double SETTINGS_ITEM_TITLE_SIZE = 14.0;

const String SETTINGS_ITEM_DESC_FONT = 'FangSong';
const double SETTINGS_ITEM_DESC_SIZE = 13.0;

const String SETTINGS_INPUT_TEXT_FONT = 'FangSong';
const double SETTINGS_INPUT_TEXT_SIZE = 13.0;

// ========================================
// 纯净雾面白玻璃质感配置 (回归柔和明亮模式)
// ========================================
const double GLASS_BLUR_SIGMA = 20.0; // 容器毛玻璃模糊程度。配合低饱和背景呈现柔和磨砂感
const double GLASS_BG_OPACITY =
    0.38; // 容器背景白色透明度。降低白色遮盖，让背景色更鲜明（可调范围 0.25~0.55）
const double GLASS_BORDER_OPACITY = 0.5; // 容器边缘白色高光线段透明度（可调范围 0.3~0.7）
const double GLASS_SHADOW_OPACITY = 0.05; // 容器底部极微弱投影，保持轻盈感

// ========================================
// 角色独立设置页面
// ========================================
class CharacterSettingsPage extends StatefulWidget {
  final Character character;

  const CharacterSettingsPage({super.key, required this.character});

  @override
  State<CharacterSettingsPage> createState() => _CharacterSettingsPageState();
}

class _CharacterSettingsPageState extends State<CharacterSettingsPage> {
  late TextEditingController _userNameController;
  late TextEditingController _userNamePronunciationController;
  late TextEditingController _personalityController;

  bool _proactiveEnabled = true;
  double _proactiveIntervalHours = 1.0;
  double _proactiveChance = 1.0;

  double _ttsSpeed = 1.0;
  bool _emotionAnalysisEnabled = true;

  bool _showOriginal = true;
  bool _showTranslation = true;

  bool _isLoading = true;
  bool _hasUnsavedChanges = false;

  @override
  void initState() {
    super.initState();
    _userNameController = TextEditingController();
    _userNamePronunciationController = TextEditingController();
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

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final id = widget.character.id;

    _userNameController.text = prefs.getString('user_name_$id') ?? '';
    _userNamePronunciationController.text =
        prefs.getString('user_name_pronunciation_$id') ?? '';

    final savedOverride = prefs.getString('personality_override_$id') ?? '';
    _personalityController.text =
        savedOverride.isNotEmpty ? savedOverride : widget.character.personality;

    _proactiveEnabled = prefs.getBool('proactive_enabled_$id') ?? true;
    _proactiveIntervalHours = (prefs.getInt('proactive_interval_$id') ??
            widget.character.proactiveMinIntervalHours)
        .toDouble();
    _proactiveChance = prefs.getDouble('proactive_chance_$id') ??
        widget.character.proactiveIdleChance;

    _ttsSpeed = prefs.getDouble('tts_speed_$id') ?? 1.0;
    _emotionAnalysisEnabled =
        prefs.getBool('emotion_analysis_enabled_$id') ?? true;

    _showOriginal = prefs.getBool('show_original_$id') ?? true;
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

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final id = widget.character.id;

    final userName = _userNameController.text.trim();
    if (userName.isEmpty) {
      await prefs.remove('user_name_$id');
    } else {
      await prefs.setString('user_name_$id', userName);
    }

    final userPronunciation = _userNamePronunciationController.text.trim();
    if (userPronunciation.isEmpty) {
      await prefs.remove('user_name_pronunciation_$id');
    } else {
      await prefs.setString('user_name_pronunciation_$id', userPronunciation);
    }

    final personalityText = _personalityController.text;
    if (personalityText.isEmpty ||
        personalityText == widget.character.personality) {
      await prefs.remove('personality_override_$id');
    } else {
      await prefs.setString('personality_override_$id', personalityText);
    }

    await prefs.setBool('proactive_enabled_$id', _proactiveEnabled);
    await prefs.setInt(
        'proactive_interval_$id', _proactiveIntervalHours.round());
    await prefs.setDouble('proactive_chance_$id', _proactiveChance);

    await prefs.setDouble('tts_speed_$id', _ttsSpeed);
    await prefs.setBool(
        'emotion_analysis_enabled_$id', _emotionAnalysisEnabled);

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

  Future<bool> _confirmExit() async {
    if (!_hasUnsavedChanges) return true;

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('有未保存的更改',
            style: TextStyle(
                fontWeight: FontWeight.bold, color: Color(0xFF2D3142))),
        content: const Text('是否在退出前保存设置？',
            style: TextStyle(color: Color(0xFF5A5F73))),
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

  Future<void> _resetPersonalityToDefault() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('重置提示词',
            style: TextStyle(
                fontWeight: FontWeight.bold, color: Color(0xFF2D3142))),
        content: const Text('确定要将提示词恢复为程序默认值吗？\n当前的修改将会丢失。',
            style: TextStyle(color: Color(0xFF5A5F73))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('取消', style: TextStyle(color: Colors.grey[600])),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red[700]),
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

  @override
  Widget build(BuildContext context) {
    final themeColor = Color(int.parse('0xFF${widget.character.color}'));

    return WillPopScope(
      onWillPop: _confirmExit,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        // 不设置 appBar 属性，改为将顶部栏放进 body 的 Stack 中浮动显示，
        // 这样 bar 底部的圆角才能正确露出，不会被系统 AppBar 背景层遮挡
        body: Stack(
          children: [
            // 第一层：低饱和度的柔和雾面弥散背景
            _buildDiffuseBackground(
                context: context, colors: widget.character.settingsBgColors),

            // 第二层：页面主要内容
            SafeArea(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      // --- top padding 需要留出 bar 高度的空间，避免内容被 bar 遮挡 ---
                      // kToolbarHeight 约 56，再加上额外间距
                      // 可调：如果 bar 高度有变化，相应调整这里的 top 值
                      padding: const EdgeInsets.only(
                          left: 16, right: 16, top: 68, bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionTitle('用户设置', Icons.person_outline),
                          _buildCard([
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
                          ]),
                          const SizedBox(height: 20),
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
                            if (_proactiveEnabled) ...[
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8.0),
                                child: Divider(
                                    height: 1,
                                    thickness: 0.5,
                                    color: Colors.black.withOpacity(0.05)),
                              ),
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
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8.0),
                                child: Divider(
                                    height: 1,
                                    thickness: 0.5,
                                    color: Colors.black.withOpacity(0.05)),
                              ),
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
                          ]),
                          const SizedBox(height: 20),
                          _buildSectionTitle('语音与显示设置', Icons.tune_outlined),
                          _buildCard([
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
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 8.0),
                              child: Divider(
                                  height: 1,
                                  thickness: 0.5,
                                  color: Colors.black.withOpacity(0.05)),
                            ),
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
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 8.0),
                              child: Divider(
                                  height: 1,
                                  thickness: 0.5,
                                  color: Colors.black.withOpacity(0.05)),
                            ),
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
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 8.0),
                              child: Divider(
                                  height: 1,
                                  thickness: 0.5,
                                  color: Colors.black.withOpacity(0.05)),
                            ),
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
                          ]),
                          const SizedBox(height: 20),
                          _buildSectionTitle('角色提示词', Icons.edit_note_outlined),
                          const Padding(
                            padding: EdgeInsets.only(bottom: 8),
                            child: Text(
                              '修改角色的system prompt，控制AI的性格、语气和背景设定。\n修改不当可能导致角色行为异常，可随时重置为程序默认值。',
                              style: TextStyle(
                                  fontFamily: SETTINGS_ITEM_DESC_FONT,
                                  fontSize: SETTINGS_ITEM_DESC_SIZE,
                                  color: Colors.black54, // 提示文字恢复深色
                                  height: 1.5),
                            ),
                          ),
                          _buildCard([
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
                                      Colors.white.withOpacity(0.5),
                                ),
                              ),
                            ),
                          ]),
                          const SizedBox(height: 48),
                        ],
                      ),
                    ),
            ),

            // ========================================
            // 第三层：顶部悬浮栏 -- 磨砂陶瓷质感，底部圆角，阴影悬浮
            // ========================================
            // 放在 Stack 最顶层，浮在背景和滚动内容之上。
            // 不使用 Scaffold.appBar，这样 bar 底部圆角可以直接露出弥散背景，
            // 不会被系统 AppBar 的不透明矩形背景层遮挡。
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                // --- 外层 Container 只负责投射阴影，不裁切 ---
                // 因为 ClipRRect 会把 boxShadow 也裁掉，
                // 所以阴影放在 ClipRRect 外面的这个 Container 上
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(18),
                    bottomRight: Radius.circular(18),
                  ),
                  boxShadow: [
                    // 外层浅阴影：制造悬浮离地感
                    // blurRadius 控制阴影扩散范围（可调 6~20），opacity 控制深浅（可调 0.04~0.15）
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                    // 第二层更柔和的远距离阴影，增加空间层次感
                    BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 30,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  // --- 底部圆角半径（可调范围 0~24，0 为直角）---
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(18),
                    bottomRight: Radius.circular(18),
                  ),
                  child: BackdropFilter(
                    // --- 磨砂模糊程度（可调范围 10~40，越大越模糊越朦胧）---
                    filter: ImageFilter.blur(sigmaX: 32, sigmaY: 32),
                    child: Container(
                      decoration: BoxDecoration(
                        // --- 陶瓷底色渐变：从上到下由浅白到微灰白，模拟真实陶瓷的柔和光泽 ---
                        // 上方 opacity 可调 0.7~0.92（越大越白实），下方 0.55~0.8
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withOpacity(0.88),
                            Colors.white.withOpacity(0.72),
                          ],
                        ),
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(18),
                          bottomRight: Radius.circular(18),
                        ),
                        // --- 统一颜色的边框（borderRadius 要求四边颜色一致）---
                        // 用极淡的灰线勾勒整体轮廓，让 bar 边界更清晰
                        // opacity 可调 0.04~0.12，越大轮廓越明显
                        border: Border.all(
                          color: Colors.black.withOpacity(0.06),
                          width: 0.8,
                        ),
                      ),
                      child: SafeArea(
                        bottom: false,
                        child: SizedBox(
                          height: kToolbarHeight,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.arrow_back,
                                      color: Color(0xFF2D3142)), // 恢复深色图标
                                  onPressed: () async {
                                    if (await _confirmExit()) {
                                      Navigator.pop(context);
                                    }
                                  },
                                ),
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${widget.character.name} 的设置',
                                        style: const TextStyle(
                                            fontFamily: SETTINGS_TITLE_FONT,
                                            fontSize: SETTINGS_TITLE_SIZE,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF2D3142)), // 恢复深色标题
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
                                ),
                                TextButton(
                                  onPressed: _saveSettings,
                                  child: Text(
                                    '保存',
                                    style: TextStyle(
                                      fontFamily: SETTINGS_TITLE_FONT,
                                      color: _hasUnsavedChanges
                                          ? themeColor
                                          : Colors.grey[500],
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ========================================
  // 辅助 Widget 构建方法
  // ========================================

  // 构建真正的丝滑弥散渐变背景 (Mesh Gradient)
  Widget _buildDiffuseBackground(
      {required BuildContext context, required List<Color> colors}) {
    final baseColor = colors.isNotEmpty ? colors[0] : const Color(0xFFF0F2F5);
    final color1 = colors.length > 1 ? colors[1] : baseColor;
    final color2 = colors.length > 2 ? colors[2] : color1;
    final color3 = colors.length > 3 ? colors[3] : color1;

    final size = MediaQuery.of(context).size;
    final double maxDim = size.width > size.height ? size.width : size.height;

    return Container(
      color: baseColor,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 左上角光晕
          Positioned(
            top: -maxDim * 0.1,
            left: -maxDim * 0.1,
            child: Container(
              width: maxDim * 0.8,
              height: maxDim * 0.8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  // 光晕不透明度：控制背景颜色鲜艳程度（可调范围 0.6~1.0，越大越鲜艳）
                  colors: [color1.withOpacity(0.92), color1.withOpacity(0.0)],
                  stops: const [0.2, 1.0],
                ),
              ),
            ),
          ),

          // 右下角光晕
          Positioned(
            bottom: -maxDim * 0.2,
            right: -maxDim * 0.1,
            child: Container(
              width: maxDim * 0.9,
              height: maxDim * 0.9,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [color2.withOpacity(0.82), color2.withOpacity(0.0)],
                  stops: const [0.2, 1.0],
                ),
              ),
            ),
          ),

          // 右侧中部偏小光晕
          Positioned(
            top: size.height * 0.2,
            right: -maxDim * 0.1,
            child: Container(
              width: maxDim * 0.7,
              height: maxDim * 0.7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [color3.withOpacity(0.72), color3.withOpacity(0.0)],
                  stops: const [0.2, 1.0],
                ),
              ),
            ),
          ),

          // 左下角光晕
          Positioned(
            bottom: size.height * 0.1,
            left: -maxDim * 0.2,
            child: Container(
              width: maxDim * 0.7,
              height: maxDim * 0.7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [color1.withOpacity(0.6), color1.withOpacity(0.0)],
                  stops: const [0.2, 1.0],
                ),
              ),
            ),
          ),

          // 顶层全局高斯模糊：消除色带，产生极致细腻的液体融合感
          // 降低模糊值让背景色更清晰可见，同时保持柔和过渡（可调范围 50~100）
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
            child: Container(color: Colors.transparent),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Row(
        children: [
          Icon(icon, size: 15, color: Colors.black87), // 恢复深色图标
          const SizedBox(width: 5),
          Text(
            title,
            style: const TextStyle(
                fontFamily: SETTINGS_SECTION_FONT,
                fontSize: SETTINGS_SECTION_SIZE,
                fontWeight: FontWeight.w600,
                color: Colors.black87, // 恢复深色标题
                letterSpacing: 0.4),
          ),
        ],
      ),
    );
  }

  // 构建雾面半透明白玻璃容器
  Widget _buildCard(List<Widget> children) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(
            sigmaX: GLASS_BLUR_SIGMA, sigmaY: GLASS_BLUR_SIGMA),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(GLASS_BG_OPACITY),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withOpacity(GLASS_BORDER_OPACITY),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(GLASS_SHADOW_OPACITY),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
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
                color: Color(0xFF2D3142))), // 标签文字恢复深色
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: maxLines,
          style: TextStyle(
            fontFamily: useFangSong ? 'FangSong' : SETTINGS_INPUT_TEXT_FONT,
            fontSize: SETTINGS_INPUT_TEXT_SIZE,
            color: const Color(0xFF2D3142), // 输入框内文字恢复深色
            height: 1.5,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
                fontFamily: SETTINGS_INPUT_TEXT_FONT,
                color: Colors.grey[500], // 占位符灰色
                fontSize: SETTINGS_INPUT_TEXT_SIZE),
            helperText: helperText,
            helperStyle: const TextStyle(
                fontFamily: SETTINGS_ITEM_DESC_FONT,
                fontSize: 11,
                color: Colors.black54, // 辅助文字灰色
                height: 1.4),
            helperMaxLines: 3,
            filled: true,
            fillColor:
                Colors.white.withOpacity(0.6), // 文本框使用稍微不透明的白色，在玻璃卡片内形成层次
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
              borderSide: BorderSide(color: themeColor),
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
                      color: Color(0xFF2D3142))), // 标题深色
              const SizedBox(height: 2),
              Text(description,
                  style: const TextStyle(
                      fontFamily: SETTINGS_ITEM_DESC_FONT,
                      fontSize: SETTINGS_ITEM_DESC_SIZE,
                      color: Colors.black54, // 描述灰色
                      height: 1.3)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Transform.scale(
          scale: 0.75,
          child: Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: color,
          ),
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
                border: Border.all(color: color.withOpacity(0.3)),
              ),
              child: Text(
                displayLabel,
                style: TextStyle(
                    fontFamily: SETTINGS_ITEM_TITLE_FONT,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: color), // 标签值保留主题色
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: color,
            inactiveTrackColor: color.withOpacity(0.2), // 轨道恢复颜色
            thumbColor: color,
            overlayColor: color.withOpacity(0.12),
            trackHeight: 3.0,
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
