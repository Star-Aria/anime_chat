// 角色配置文件
class Character {
  final String id;
  final String name;
  final String nameJp;
  final String avatar;
  final String referWavPath; // GPT-SoVITS 参考音频路径
  final String promptText; // 参考音频的文本内容
  final String promptLanguage; // 参考音频的语言 (ja=日语)
  final String personality;
  final String color;

  Character({
    required this.id,
    required this.name,
    required this.nameJp,
    required this.avatar,
    required this.referWavPath,
    required this.promptText,
    required this.promptLanguage,
    required this.personality,
    required this.color,
  });
}

// 角色配置
class CharacterConfig {
  static final List<Character> characters = [
    Character(
      id: 'shinobu',
      name: '蝴蝶忍',
      nameJp: 'Shinobu Kocho',
      avatar: '🦋',
      // ⚠️ 重要：请将这些路径替换为你的 GPT-SoVITS 训练好的模型参考音频
      // 参考音频路径可以是绝对路径或相对路径
      referWavPath:
          'D:\\AI model\\Saki model\\参考音频-梦中情祥\\あなたと空を見上げるのは、いつも夏でしたわね.wav',
      promptText: 'あなたと空を見上げるのは、いつも夏でしたわね。', // 参考音频说的内容（日语）
      promptLanguage: 'ja', // 日语
      personality: '''
你是《鬼灭之刃》中的蝴蝶忍。
- 性格温柔优雅，总是带着微笑
- 说话时经常用"あらあら"（阿拉阿拉）开头
- 用日语回答所有问题
- 保持角色的语气和性格特点
''',
      color: '9C27B0', // 紫色
    ),

    // 后期可以添加更多角色，参考下面的模板：
    // Character(
    //   id: 'muichiro',
    //   name: '时透无一郎',
    //   nameJp: 'Muichiro Tokito',
    //   avatar: '☁️',
    //   referWavPath: 'C:/GPT-SoVITS/reference_audio/muichiro.wav',
    //   promptText: 'はい、わかりました。',
    //   promptLanguage: 'ja',
    //   personality: '''在这里填写角色的性格设定...''',
    //   color: '00BCD4',
    // ),
  ];

  static Character getCharacterById(String id) {
    return characters.firstWhere((char) => char.id == id);
  }
}
