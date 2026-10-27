class StickerDefinition {
  final String characterName;
  final String title;
  final String assetPath;
  final String description;

  const StickerDefinition({
    required this.characterName,
    required this.title,
    required this.assetPath,
    required this.description,
  });

  String get fullTitle => '$characterName·$title';

  String get neutralVisualDescription {
    if (!description.startsWith(characterName)) return description;
    return '画面中的角色${description.substring(characterName.length)}';
  }
}

class StickerCatalog {
  const StickerCatalog._();

  static const List<StickerDefinition> all = [
    // 高松灯 · 静态 · 良辰共此曲
    StickerDefinition(
      characterName: '高松灯',
      title: '不要吵架',
      assetPath: 'assets/stickers/良辰共此曲_静态_高松灯_不要吵架.gif',
      description: '高松灯慌张地举起双手劝阻，想让争执停下来。',
    ),
    StickerDefinition(
      characterName: '高松灯',
      title: '创作中',
      assetPath: 'assets/stickers/良辰共此曲_静态_高松灯_创作中.gif',
      description: '高松灯低头在笔记本上写字，专注地创作歌词。',
    ),
    StickerDefinition(
      characterName: '高松灯',
      title: '害羞',
      assetPath: 'assets/stickers/良辰共此曲_静态_高松灯_害羞.gif',
      description: '高松灯脸颊通红，双手紧张地攥在胸前，显得有些手足无措。',
    ),
    StickerDefinition(
      characterName: '高松灯',
      title: '忧郁',
      assetPath: 'assets/stickers/良辰共此曲_静态_高松灯_忧郁.gif',
      description: '高松灯低头抱膝坐着，眼神黯淡而情绪低落。',
    ),

    // 高松灯 · 静态 · MyGO手游
    StickerDefinition(
      characterName: '高松灯',
      title: '哎呀',
      assetPath: 'assets/stickers/MyGO手游_静态_高松灯_哎呀.gif',
      description: '穿着企鹅服的高松灯摔倒在地，露出有点狼狈的表情。',
    ),
    StickerDefinition(
      characterName: '高松灯',
      title: '开唱',
      assetPath: 'assets/stickers/MyGO手游_静态_高松灯_开唱.gif',
      description: '高松灯握住麦克风认真开口歌唱，完全进入演唱状态。',
    ),
    StickerDefinition(
      characterName: '高松灯',
      title: '迷茫',
      assetPath: 'assets/stickers/MyGO手游_静态_高松灯_迷茫.gif',
      description: '高松灯穿着企鹅服发呆，眼神茫然而找不到方向。',
    ),
    StickerDefinition(
      characterName: '高松灯',
      title: '我需要你',
      assetPath: 'assets/stickers/MyGO手游_静态_高松灯_我需要你.gif',
      description: '高松灯表情急切，直接表达对对方的需要。',
    ),
    StickerDefinition(
      characterName: '高松灯',
      title: 'Y',
      assetPath: 'assets/stickers/MyGO手游_静态_高松灯_Y.gif',
      description: '高松灯双手托着脸摆出“MyGO!!!!!”的字母Y，旁边浮现出大写Y。',
    ),

    // 高松灯 · 静态 · 晴空向光行
    StickerDefinition(
      characterName: '高松灯',
      title: '端详',
      assetPath: 'assets/stickers/晴空向光行_静态_高松灯_端详.gif',
      description: '高松灯蹲下开心地捡起小石头端详。',
    ),
    StickerDefinition(
      characterName: '高松灯',
      title: '害羞',
      assetPath: 'assets/stickers/晴空向光行_静态_高松灯_害羞.gif',
      description: '高松灯侧过脸低下视线，耳根和脸颊泛红，安静地害羞。',
    ),
    StickerDefinition(
      characterName: '高松灯',
      title: '开心',
      assetPath: 'assets/stickers/晴空向光行_静态_高松灯_开心.gif',
      description: '高松灯露出明亮笑容，喜悦写在脸上。',
    ),
    StickerDefinition(
      characterName: '高松灯',
      title: '泪目',
      assetPath: 'assets/stickers/晴空向光行_静态_高松灯_泪目.gif',
      description: '高松灯眼里含着泪光，像是被触动了。',
    ),
    StickerDefinition(
      characterName: '高松灯',
      title: '疑惑',
      assetPath: 'assets/stickers/晴空向光行_静态_高松灯_疑惑.gif',
      description: '高松灯头顶冒出问号，满脸疑惑。',
    ),

    // 高松灯 · 动态 · 良辰共此曲
    StickerDefinition(
      characterName: '高松灯',
      title: '鼓掌',
      assetPath: 'assets/stickers/高松灯_鼓掌.gif',
      description: '高松灯双手在胸前鼓掌，表情认真。',
    ),
    StickerDefinition(
      characterName: '高松灯',
      title: '探头',
      assetPath: 'assets/stickers/高松灯_探头.gif',
      description: '高松灯从桌面下边探出脑袋，好奇地观察外面。',
    ),
    StickerDefinition(
      characterName: '高松灯',
      title: '谢谢大家',
      assetPath: 'assets/stickers/高松灯_谢谢大家.gif',
      description: '高松灯在演出谢幕的时候深吸一口气，举起两侧成员的手，低下头，喊出对大家的致谢。',
    ),
    StickerDefinition(
      characterName: '高松灯',
      title: 'emo',
      assetPath: 'assets/stickers/高松灯_emo.gif',
      description: '高松灯闭着眼叹了口气，低下头，安静陷入低落的情绪中。',
    ),

    // 高松灯 · 动态 · MyGO手游
    StickerDefinition(
      characterName: '高松灯',
      title: '哭哭',
      assetPath: 'assets/stickers/MyGO手游_动态_高松灯_哭哭.gif',
      description: '高松灯眼泪汪汪地哭着，显得委屈又需要安慰。',
    ),
    StickerDefinition(
      characterName: '高松灯',
      title: '摸摸',
      assetPath: 'assets/stickers/MyGO手游_动态_高松灯_摸摸.gif',
      description: '高松灯接受着头顶的抚摸。',
    ),

    // 高松灯 · 动态 · 晴空向光行
    StickerDefinition(
      characterName: '高松灯',
      title: '喘气',
      assetPath: 'assets/stickers/晴空向光行_动态_高松灯_喘气.gif',
      description: '高松灯张着嘴急促喘气，看起来刚经历了剧烈活动。',
    ),
    StickerDefinition(
      characterName: '高松灯',
      title: '碰拳',
      assetPath: 'assets/stickers/晴空向光行_动态_高松灯_碰拳.gif',
      description: '高松灯抬起拳头向前碰拳，用动作表达默契和鼓励。',
    ),
    StickerDefinition(
      characterName: '高松灯',
      title: '我会加油的',
      assetPath: 'assets/stickers/晴空向光行_动态_高松灯_我会加油的.gif',
      description: '高松灯表情坚定地点头，认真表示自己会努力。',
    ),

    // 千早爱音 · 静态 · 良辰共此曲
    StickerDefinition(
      characterName: '千早爱音',
      title: '不会吧？',
      assetPath: 'assets/stickers/良辰共此曲_静态_千早爱音_不会吧？.gif',
      description: '千早爱音皱着眉捂着嘴，满脸都是难以置信。',
    ),
    StickerDefinition(
      characterName: '千早爱音',
      title: '生气',
      assetPath: 'assets/stickers/良辰共此曲_静态_千早爱音_生气.gif',
      description: '千早爱音皱紧眉头鼓起脸，咬牙攥拳，样子又气又急。',
    ),
    StickerDefinition(
      characterName: '千早爱音',
      title: '探头',
      assetPath: 'assets/stickers/良辰共此曲_静态_千早爱音_探头.gif',
      description: '千早爱音探出Q版大头，显得又憨又呆。',
    ),
    StickerDefinition(
      characterName: '千早爱音',
      title: 'Love',
      assetPath: 'assets/stickers/良辰共此曲_静态_千早爱音_Love.gif',
      description: '千早爱音双手交叠托在下巴处，眼睛变成爱心瞳孔，传达喜欢和爱意。',
    ),

    // 千早爱音 · 静态 · MyGO手游
    StickerDefinition(
      characterName: '千早爱音',
      title: '!',
      assetPath: 'assets/stickers/MyGO手游_静态_千早爱音_!.gif',
      description: '千早爱音双手向前推，开心地比出“MyGO!!!!!”的“!”。',
    ),
    StickerDefinition(
      characterName: '千早爱音',
      title: '爱音东京',
      assetPath: 'assets/stickers/MyGO手游_静态_千早爱音_爱音东京.gif',
      description: '千早爱音笑着眨眼并张开双臂，身后醒目地写着“ANON TOKYO”。',
    ),
    StickerDefinition(
      characterName: '千早爱音',
      title: '哈？！',
      assetPath: 'assets/stickers/MyGO手游_静态_千早爱音_哈？！.gif',
      description: '千早爱音眉头微皱，嘴巴微张，提高音量反问，像是听到了离谱的话。',
    ),
    StickerDefinition(
      characterName: '千早爱音',
      title: '抢到票啦',
      assetPath: 'assets/stickers/MyGO手游_静态_千早爱音_抢到票啦.gif',
      description: '千早爱音举起手中的手机得意地眯眼大笑，为终于抢到票而兴奋。',
    ),
    StickerDefinition(
      characterName: '千早爱音',
      title: 'SNS见',
      assetPath: 'assets/stickers/MyGO手游_静态_千早爱音_SNS见.gif',
      description: '千早爱音咬牙切齿地戳手机，表示稍后在社交平台见。',
    ),

    // 千早爱音 · 静态 · 晴空向光行
    StickerDefinition(
      characterName: '千早爱音',
      title: '快看',
      assetPath: 'assets/stickers/晴空向光行_静态_千早爱音_快看.gif',
      description: '千早爱音开心地笑着举起手机屏幕给对方看，迫不及待想分享内容。',
    ),
    StickerDefinition(
      characterName: '千早爱音',
      title: '快说吧',
      assetPath: 'assets/stickers/晴空向光行_静态_千早爱音_快说吧.gif',
      description: '千早爱音摊开双手注视对方，催促对方赶快说出来。',
    ),
    StickerDefinition(
      characterName: '千早爱音',
      title: '累瘫',
      assetPath: 'assets/stickers/晴空向光行_静态_千早爱音_累瘫.gif',
      description: '千早爱音双眼紧闭，嘴角耷拉，挂着汗珠，一副疲惫不堪、身心俱疲的模样。',
    ),
    StickerDefinition(
      characterName: '千早爱音',
      title: '天呐',
      assetPath: 'assets/stickers/晴空向光行_静态_千早爱音_天呐.gif',
      description: '千早爱音捂着嘴睁大眼睛，对发生的事情十分震惊。',
    ),
    StickerDefinition(
      characterName: '千早爱音',
      title: '怎么办',
      assetPath: 'assets/stickers/晴空向光行_静态_千早爱音_怎么办.gif',
      description: '千早爱音眉头皱起，不爽地责问对方该怎么办。',
    ),

    // 千早爱音 · 动态 · 良辰共此曲
    StickerDefinition(
      characterName: '千早爱音',
      title: '比心',
      assetPath: 'assets/stickers/千早爱音_比心.gif',
      description: '千早爱音俏皮单眼wink，双手在胸前比出爱心，可爱地传达喜欢和支持。',
    ),
    StickerDefinition(
      characterName: '千早爱音',
      title: '哈？',
      assetPath: 'assets/stickers/千早爱音_哈？.gif',
      description: '千早爱音身体向前探，皱眉张大嘴说“哈？”，神情里带着明显的不解和不爽。',
    ),
    StickerDefinition(
      characterName: '千早爱音',
      title: '泣',
      assetPath: 'assets/stickers/千早爱音_泣.gif',
      description: '千早爱音低下头郁闷地嘤嘤哭着。',
    ),
    StickerDefinition(
      characterName: '千早爱音',
      title: 'TGW',
      assetPath: 'assets/stickers/千早爱音_TGW.gif',
      description: '千早爱音用双手比出字母T、G、W（Togawa集团为丰川祥子家集团的名字）的形状，神情认真又夸张。',
    ),

    // 千早爱音 · 动态 · MyGO手游
    StickerDefinition(
      characterName: '千早爱音',
      title: '按我说',
      assetPath: 'assets/stickers/MyGO手游_动态_千早爱音_按我说.gif',
      description: '千早爱音神情认真，竖起一根食指，一副提出想法、发表观点的样子。',
    ),
    StickerDefinition(
      characterName: '千早爱音',
      title: '这不好吧',
      assetPath: 'assets/stickers/MyGO手游_动态_千早爱音_这不好吧.gif',
      description: '千早爱音皱眉缩起肩膀，脸颊挂着汗珠，面露迟疑，委婉表示不太妥当、有点为难。',
    ),

    // 千早爱音 · 动态 · 晴空向光行
    StickerDefinition(
      characterName: '千早爱音',
      title: '拜托拜托',
      assetPath: 'assets/stickers/晴空向光行_动态_千早爱音_拜托拜托.gif',
      description: '千早爱音双手合十放在胸前，露出恳求又期待的神情。',
    ),
    StickerDefinition(
      characterName: '千早爱音',
      title: '四下观察',
      assetPath: 'assets/stickers/晴空向光行_动态_千早爱音_四下观察.gif',
      description: '千早爱音双手托脸，叹了口气，谨慎确认周围的情况。',
    ),
    StickerDefinition(
      characterName: '千早爱音',
      title: '耶！',
      assetPath: 'assets/stickers/晴空向光行_动态_千早爱音_耶！.gif',
      description: '千早爱音一只手握拳，向上举起庆祝，开心地喊出胜利般的欢呼。',
    ),

    // 长崎爽世 · 静态 · 良辰共此曲
    StickerDefinition(
      characterName: '长崎爽世',
      title: '大哭',
      assetPath: 'assets/stickers/良辰共此曲_静态_长崎爽世_大哭.gif',
      description: '长崎爽世闭着眼张嘴大哭，眼泪不停地往下掉。',
    ),
    StickerDefinition(
      characterName: '长崎爽世',
      title: '发送消息',
      assetPath: 'assets/stickers/良辰共此曲_静态_长崎爽世_发送消息.gif',
      description: '长崎爽世在夜里侧躺在床上，盯着手机发送消息。',
    ),
    StickerDefinition(
      characterName: '长崎爽世',
      title: '让我看看',
      assetPath: 'assets/stickers/良辰共此曲_静态_长崎爽世_让我看看.gif',
      description: '长崎爽世半侧着脸凑近画面仔细看过来。',
    ),
    StickerDefinition(
      characterName: '长崎爽世',
      title: '为什么！',
      assetPath: 'assets/stickers/良辰共此曲_静态_长崎爽世_为什么！.gif',
      description: '长崎爽世瞪大双眼，攥紧拳头，激动地大声质问，满是不解与生气。',
    ),

    // 长崎爽世 · 静态 · MyGO手游
    StickerDefinition(
      characterName: '长崎爽世',
      title: '服了',
      assetPath: 'assets/stickers/MyGO手游_静态_长崎爽世_服了.gif',
      description: '长崎爽世无奈地半垂着眼，嘴巴微张，露出被整无语、服气了的表情。',
    ),
    StickerDefinition(
      characterName: '长崎爽世',
      title: '认真',
      assetPath: 'assets/stickers/MyGO手游_静态_长崎爽世_认真.gif',
      description: '长崎爽世手持手机，神情专注，正在认真查看手机里的内容。',
    ),
    StickerDefinition(
      characterName: '长崎爽世',
      title: '想到了',
      assetPath: 'assets/stickers/MyGO手游_静态_长崎爽世_想到了.gif',
      description: '长崎爽世食指抵在下巴，头顶冒出灯泡灵光一闪，像是突然有了主意。',
    ),
    StickerDefinition(
      characterName: '长崎爽世',
      title: '注视',
      assetPath: 'assets/stickers/MyGO手游_静态_长崎爽世_注视.gif',
      description: '长崎爽世整张脸暗了下来，目光直直盯着前方，安静地凝视，压迫感十足。',
    ),
    StickerDefinition(
      characterName: '长崎爽世',
      title: 'O',
      assetPath: 'assets/stickers/MyGO手游_静态_长崎爽世_O.gif',
      description: '长崎爽世双手在胸前围出圆形，比出“MyGO!!!!!”的“O”的形状。',
    ),

    // 长崎爽世 · 静态 · 晴空向光行
    StickerDefinition(
      characterName: '长崎爽世',
      title: '干嘛',
      assetPath: 'assets/stickers/晴空向光行_静态_长崎爽世_干嘛.gif',
      description: '长崎爽世绷着脸微皱着眉，面无表情地直视前方，眼神淡淡的，一脸 “有什么事？” 的疑惑冷淡感。',
    ),
    StickerDefinition(
      characterName: '长崎爽世',
      title: '黑脸',
      assetPath: 'assets/stickers/晴空向光行_静态_长崎爽世_黑脸.gif',
      description: '长崎爽世低下头，整张脸隐在阴影里，看不清表情，气场压抑，用来表达极度不悦、沉默发火。',
    ),
    StickerDefinition(
      characterName: '长崎爽世',
      title: '是朋友哦',
      assetPath: 'assets/stickers/晴空向光行_静态_长崎爽世_是朋友哦.gif',
      description: '长崎爽世双手交握托着下巴，嘴里说着“是朋友”，心里却在暗暗盘算别的什么。',
    ),
    StickerDefinition(
      characterName: '长崎爽世',
      title: '微笑',
      assetPath: 'assets/stickers/晴空向光行_静态_长崎爽世_微笑.gif',
      description: '长崎爽世眉眼舒展，浅浅地露出温和而安心的微笑。',
    ),
    StickerDefinition(
      characterName: '长崎爽世',
      title: '细品',
      assetPath: 'assets/stickers/晴空向光行_静态_长崎爽世_细品.gif',
      description: '长崎爽世端着杯子慢慢品尝，闭眼感受味道。',
    ),

    // 长崎爽世 · 动态 · 良辰共此曲
    StickerDefinition(
      characterName: '长崎爽世',
      title: '剪切',
      assetPath: 'assets/stickers/长崎爽世_剪切.gif',
      description: '长崎爽世笑着用手比出剪刀动作，像是在剪断什么。',
    ),
    StickerDefinition(
      characterName: '长崎爽世',
      title: '生气',
      assetPath: 'assets/stickers/长崎爽世_生气.gif',
      description: '长崎爽世皱紧眉头鼓起脸，咬牙瞪着眼，冷冷地看向一侧，满脸不高兴，正在发火。',
    ),
    StickerDefinition(
      characterName: '长崎爽世',
      title: '玩头发',
      assetPath: 'assets/stickers/长崎爽世_玩头发.gif',
      description: '长崎爽世嘴角带笑，用手指轻轻撩拨自己的长发，带着玩味的神情。',
    ),
    StickerDefinition(
      characterName: '长崎爽世',
      title: '微笑（动态）',
      assetPath: 'assets/stickers/长崎爽世_微笑（动态）.gif',
      description: '长崎爽世双手合十，轻轻摇晃脑袋，开心地眯眼笑着。',
    ),

    // 长崎爽世 · 动态 · MyGO手游
    StickerDefinition(
      characterName: '长崎爽世',
      title: '苦笑',
      assetPath: 'assets/stickers/MyGO手游_动态_长崎爽世_苦笑.gif',
      description: '长崎爽世眉毛下垂，扯出勉强的笑容，是无可奈何、哭笑不得的苦笑。',
    ),
    StickerDefinition(
      characterName: '长崎爽世',
      title: '有趣',
      assetPath: 'assets/stickers/MyGO手游_动态_长崎爽世_有趣.gif',
      description: '长崎爽世浅浅勾着嘴角，双手交握，眼神平静，一副饶有兴致的样子。',
    ),

    // 长崎爽世 · 动态 · 晴空向光行
    StickerDefinition(
      characterName: '长崎爽世',
      title: '惊吓',
      assetPath: 'assets/stickers/晴空向光行_动态_长崎爽世_惊吓.gif',
      description: '长崎爽世身体猛地后仰，眼睛睁大，嘴巴大张，被突如其来的事物狠狠吓到，满脸惊慌。',
    ),
    StickerDefinition(
      characterName: '长崎爽世',
      title: '下雨天',
      assetPath: 'assets/stickers/晴空向光行_动态_长崎爽世_下雨天.gif',
      description: '长崎爽世隔着布满雨珠的玻璃窗，神情落寞地向外望着，氛围冷清伤感。',
    ),
    StickerDefinition(
      characterName: '长崎爽世',
      title: '真情流露',
      assetPath: 'assets/stickers/晴空向光行_动态_长崎爽世_真情流露.gif',
      description: '长崎爽世微眯着眼，卸下假笑的假面，表露出真实的情绪。',
    ),

    // 椎名立希 · 静态 · 良辰共此曲
    StickerDefinition(
      characterName: '椎名立希',
      title: '哈？',
      assetPath: 'assets/stickers/良辰共此曲_静态_椎名立希_哈？.gif',
      description: '椎名立希皱眉张嘴反问，神情里带着明显的不解和不爽。',
    ),
    StickerDefinition(
      characterName: '椎名立希',
      title: '那我呢？',
      assetPath: 'assets/stickers/良辰共此曲_静态_椎名立希_那我呢？.gif',
      description: '椎名立希眼神略带委屈不甘，微微蹙眉，带着被忽略的失落感，是 “怎么不提我、那我呢” 的神情。',
    ),
    StickerDefinition(
      characterName: '椎名立希',
      title: '请点单',
      assetPath: 'assets/stickers/良辰共此曲_静态_椎名立希_请点单.gif',
      description: '椎名立希黑着脸，眼神向下瞪着，手里拿着笔和本，要求对方点单。',
    ),
    StickerDefinition(
      characterName: '椎名立希',
      title: 'Block!',
      assetPath: 'assets/stickers/良辰共此曲_静态_椎名立希_Block!.gif',
      description: '椎名立希头上冒出红色怒气符号，手指指着手机，气冲冲地要把人拉黑屏蔽。',
    ),

    // 椎名立希 · 静态 · MyGO手游
    StickerDefinition(
      characterName: '椎名立希',
      title: '突然出现',
      assetPath: 'assets/stickers/MyGO手游_静态_椎名立希_突然出现.gif',
      description: '椎名立希头顶着海铃放上来的一盒饮料，悄咪咪地冒出来，有点生无可恋的感觉。',
    ),
    StickerDefinition(
      characterName: '椎名立希',
      title: '不是的',
      assetPath: 'assets/stickers/MyGO手游_静态_椎名立希_不是的.gif',
      description: '椎名立希脸颊泛红，急忙开口否认，神情认真又有些着急。',
    ),
    StickerDefinition(
      characterName: '椎名立希',
      title: '生气',
      assetPath: 'assets/stickers/MyGO手游_静态_椎名立希_生气.gif',
      description: '椎名立希头顶红色怒气符号，气鼓鼓地发火。',
    ),
    StickerDefinition(
      characterName: '椎名立希',
      title: '啧',
      assetPath: 'assets/stickers/MyGO手游_静态_椎名立希_啧.gif',
      description: '椎名立希整张脸压暗，眼神冷淡，抿嘴发出啧的一声，满脸嫌弃、无语。',
    ),
    StickerDefinition(
      characterName: '椎名立希',
      title: 'G',
      assetPath: 'assets/stickers/MyGO手游_静态_椎名立希_G.gif',
      description: '椎名立希眨着一只眼用双手比出“MyGO!!!!!”的“G”，旁边也浮现出大写G。',
    ),

    // 椎名立希 · 静态 · 晴空向光行
    StickerDefinition(
      characterName: '椎名立希',
      title: '盯',
      assetPath: 'assets/stickers/晴空向光行_静态_椎名立希_盯.gif',
      description: '椎名立希皱着眉向前探头，目光直直地紧紧盯住对方，让人感到压力。',
    ),
    StickerDefinition(
      characterName: '椎名立希',
      title: '惊讶',
      assetPath: 'assets/stickers/晴空向光行_静态_椎名立希_惊讶.gif',
      description: '椎名立希睁大眼睛张开嘴，向后仰头，对眼前的情况十分意外。',
    ),
    StickerDefinition(
      characterName: '椎名立希',
      title: '睡觉',
      assetPath: 'assets/stickers/晴空向光行_静态_椎名立希_睡觉.gif',
      description: '椎名立希闭着眼安静躺下，已经进入睡眠状态。',
    ),
    StickerDefinition(
      characterName: '椎名立希',
      title: '我做不到',
      assetPath: 'assets/stickers/晴空向光行_静态_椎名立希_我做不到.gif',
      description: '椎名立希闭眼低下头，紧握双拳，无力地呐喊，沮丧又不甘地表示自己实在做不到。',
    ),
    StickerDefinition(
      characterName: '椎名立希',
      title: '忧郁',
      assetPath: 'assets/stickers/晴空向光行_静态_椎名立希_忧郁.gif',
      description: '椎名立希趴在桌子上，眼神低垂，一脸闷闷不乐。',
    ),

    // 椎名立希 · 动态 · 良辰共此曲
    StickerDefinition(
      characterName: '椎名立希',
      title: '傲娇',
      assetPath: 'assets/stickers/椎名立希_傲娇.gif',
      description: '椎名立希双臂抱在胸前闭着眼偏过头，嘴上像是不肯坦率。',
    ),
    StickerDefinition(
      characterName: '椎名立希',
      title: '瞪',
      assetPath: 'assets/stickers/椎名立希_瞪.gif',
      description: '椎名立希向前逼近，斜眼狠狠瞪过去，目光带着强烈压迫感，充满不悦。',
    ),
    StickerDefinition(
      characterName: '椎名立希',
      title: '逃跑',
      assetPath: 'assets/stickers/椎名立希_逃跑.gif',
      description: '椎名立希神情慌张地转身跑开，想迅速离开现场。',
    ),
    StickerDefinition(
      characterName: '椎名立希',
      title: '再见',
      assetPath: 'assets/stickers/椎名立希_再见.gif',
      description: '椎名立希试图做出酷酷的样子，扬起手道别。',
    ),

    // 椎名立希 · 动态 · MyGO手游
    StickerDefinition(
      characterName: '椎名立希',
      title: '好诶',
      assetPath: 'assets/stickers/MyGO手游_动态_椎名立希_好诶.gif',
      description: '椎名立希握起拳头开心欢呼。',
    ),

    // 椎名立希 · 动态 · 晴空向光行
    StickerDefinition(
      characterName: '椎名立希',
      title: '不给你',
      assetPath: 'assets/stickers/晴空向光行_动态_椎名立希_不给你.gif',
      description: '椎名立希把东西抱在身前，身子侧过去，一脸不肯交出的模样。',
    ),
    StickerDefinition(
      characterName: '椎名立希',
      title: '骑熊猫',
      assetPath: 'assets/stickers/晴空向光行_动态_椎名立希_骑熊猫.gif',
      description: '椎名立希安安静静地坐在熊猫玩偶上向前移动，神情认真又有些滑稽。',
    ),
    StickerDefinition(
      characterName: '椎名立希',
      title: '吸果冻熬夜',
      assetPath: 'assets/stickers/晴空向光行_动态_椎名立希_吸果冻熬夜.gif',
      description: '椎名立希戴着耳机吸食果冻饮料，熬夜作曲。',
    ),

    // 要乐奈 · 静态 · 良辰共此曲
    StickerDefinition(
      characterName: '要乐奈',
      title: '刚睡醒',
      assetPath: 'assets/stickers/良辰共此曲_静态_要乐奈_刚睡醒.gif',
      description: '要乐奈裹在被子里迷迷糊糊地探出头，眼神还没有清醒。',
    ),
    StickerDefinition(
      characterName: '要乐奈',
      title: '溜了溜了',
      assetPath: 'assets/stickers/良辰共此曲_静态_要乐奈_溜了溜了.gif',
      description: '要乐奈拉着音响，摆出准备开溜的样子。',
    ),
    StickerDefinition(
      characterName: '要乐奈',
      title: '抹茶芭菲',
      assetPath: 'assets/stickers/良辰共此曲_静态_要乐奈_抹茶芭菲.gif',
      description: '要乐奈眼神亮晶晶地双手去够最喜欢的抹茶芭菲。',
    ),
    StickerDefinition(
      characterName: '要乐奈',
      title: '有趣的女人',
      assetPath: 'assets/stickers/良辰共此曲_静态_要乐奈_有趣的女人.gif',
      description: '要乐奈趴在桌边饶有兴趣地看着对方，像是发现了有趣的人。',
    ),

    // 要乐奈 · 静态 · MyGO手游
    StickerDefinition(
      characterName: '要乐奈',
      title: '被猫环绕',
      assetPath: 'assets/stickers/MyGO手游_静态_要乐奈_被猫环绕.gif',
      description: '要乐奈抱着吉他坐在几只猫中间，享受被猫包围的状态。',
    ),
    StickerDefinition(
      characterName: '要乐奈',
      title: '捕猎状态',
      assetPath: 'assets/stickers/MyGO手游_静态_要乐奈_捕猎状态.gif',
      description: '要乐奈趴低身体盯着前方，像猫一样进入准备扑出的状态。',
    ),
    StickerDefinition(
      characterName: '要乐奈',
      title: '发现猎物',
      assetPath: 'assets/stickers/MyGO手游_静态_要乐奈_发现猎物.gif',
      description: '要乐奈眼睛一亮，像猫一样发现了目标。',
    ),
    StickerDefinition(
      characterName: '要乐奈',
      title: '喜欢抹茶',
      assetPath: 'assets/stickers/MyGO手游_静态_要乐奈_喜欢抹茶.gif',
      description: '要乐奈捧着抹茶芭菲眼睛发亮，明显非常喜欢。',
    ),
    StickerDefinition(
      characterName: '要乐奈',
      title: 'M',
      assetPath: 'assets/stickers/MyGO手游_静态_要乐奈_M.gif',
      description: '要乐奈双手在胸前比出“MyGO!!!!!”的“M”，旁边浮现出大写M。',
    ),

    // 要乐奈 · 静态 · 晴空向光行
    StickerDefinition(
      characterName: '要乐奈',
      title: '比三',
      assetPath: 'assets/stickers/晴空向光行_静态_要乐奈_比三.gif',
      description: '要乐奈抱着猫抬起手比出数字三，神情认真又可爱。',
    ),
    StickerDefinition(
      characterName: '要乐奈',
      title: '来玩乐队',
      assetPath: 'assets/stickers/晴空向光行_静态_要乐奈_来玩乐队.gif',
      description: '要乐奈眼神期待，表情兴奋，主动发出邀请，希望对方一起来玩乐队。',
    ),
    StickerDefinition(
      characterName: '要乐奈',
      title: '我剪',
      assetPath: 'assets/stickers/晴空向光行_静态_要乐奈_我剪.gif',
      description: '要乐奈拿着剪刀，主动表示由自己来剪。',
    ),
    StickerDefinition(
      characterName: '要乐奈',
      title: '我吗',
      assetPath: 'assets/stickers/晴空向光行_静态_要乐奈_我吗.gif',
      description: '要乐奈指向自己露出疑惑神情，确认对方说的是不是她。',
    ),
    StickerDefinition(
      characterName: '要乐奈',
      title: '无聊',
      assetPath: 'assets/stickers/晴空向光行_静态_要乐奈_无聊.gif',
      description: '要乐奈目光斜视，半眯眼发呆，显得提不起兴致，百无聊赖。',
    ),

    // 要乐奈 · 动态 · 良辰共此曲
    StickerDefinition(
      characterName: '要乐奈',
      title: '观察',
      assetPath: 'assets/stickers/要乐奈_观察.gif',
      description: '要乐奈叼着勺子，有兴趣地看向前方观察着。',
    ),
    StickerDefinition(
      characterName: '要乐奈',
      title: '思考',
      assetPath: 'assets/stickers/要乐奈_思考.gif',
      description: '要乐奈仰头，眼神放空，脑中闪过无数东西。',
    ),
    StickerDefinition(
      characterName: '要乐奈',
      title: '握手',
      assetPath: 'assets/stickers/要乐奈_握手.gif',
      description: '要乐奈做出猫爪一样的手型向前伸，期待与人握手。',
    ),
    StickerDefinition(
      characterName: '要乐奈',
      title: 'rua猫',
      assetPath: 'assets/stickers/要乐奈_rua猫.gif',
      description: '对方伸出手来拨弄要乐奈的下巴，要乐奈闭着眼，一脸舒服享受。',
    ),

    // 要乐奈 · 动态 · MyGO手游
    StickerDefinition(
      characterName: '要乐奈',
      title: '吃吃',
      assetPath: 'assets/stickers/MyGO手游_动态_要乐奈_吃吃.gif',
      description: '要乐奈张嘴接过抹茶小零食，专心又满足地吃着。',
    ),
    StickerDefinition(
      characterName: '要乐奈',
      title: '有动静',
      assetPath: 'assets/stickers/MyGO手游_动态_要乐奈_有动静.gif',
      description: '要乐奈眼神锐利，眉头微蹙，察觉到周遭异动，警惕看向一侧。',
    ),

    // 要乐奈 · 动态 · 晴空向光行
    StickerDefinition(
      characterName: '要乐奈',
      title: '好困',
      assetPath: 'assets/stickers/晴空向光行_动态_要乐奈_好困.gif',
      description: '要乐奈埋进被子枕头里，困倦地躺着。',
    ),
    StickerDefinition(
      characterName: '要乐奈',
      title: '爽弹',
      assetPath: 'assets/stickers/晴空向光行_动态_要乐奈_爽弹.gif',
      description: '要乐奈抱着吉他演奏，沉浸在畅快弹奏的状态里。',
    ),
    StickerDefinition(
      characterName: '要乐奈',
      title: '投喂',
      assetPath: 'assets/stickers/晴空向光行_动态_要乐奈_投喂.gif',
      description: '要乐奈张嘴接过递来的抹茶小零食，乖乖接受投喂。',
    ),

    // 丰川祥子 · 静态 · 夜奏未终
    StickerDefinition(
      characterName: '丰川祥子',
      title: '害怕',
      assetPath: 'assets/stickers/丰川祥子_害怕.gif',
      description: '丰川祥子身体后仰并睁大眼睛，面露惊恐。',
    ),
    StickerDefinition(
      characterName: '丰川祥子',
      title: '美味',
      assetPath: 'assets/stickers/丰川祥子_美味.gif',
      description: '丰川祥子眼睛发亮地品尝食物，露出觉得很好吃的表情。',
    ),
    StickerDefinition(
      characterName: '丰川祥子',
      title: '我有话说',
      assetPath: 'assets/stickers/丰川祥子_我有话说.gif',
      description: '丰川祥子举高手示意并认真看向前方，表示自己想发言。',
    ),
    StickerDefinition(
      characterName: '丰川祥子',
      title: '愉快',
      assetPath: 'assets/stickers/丰川祥子_愉快.gif',
      description: '丰川祥子脸颊泛红地开心笑着，情绪轻快而满足。',
    ),

    // 丰川祥子 · 静态 · 夜愿华章
    StickerDefinition(
      characterName: '丰川祥子',
      title: '撩发',
      assetPath: 'assets/stickers/撩发.gif',
      description: 'CRYCHIC时期的丰川祥子单手拨弄蓝色长发，弯下腰来，露出温柔又关心的笑容，如春日暖阳般明媚。',
    ),
    StickerDefinition(
      characterName: '丰川祥子',
      title: '呐喊',
      assetPath: 'assets/stickers/呐喊.gif',
      description:
          'CHYCHIC时期的丰川祥子伏在天桥的栏杆上闭眼大声呐喊在高松灯的笔记本上看到的那句“好想成为人类啊”，她认为灯的歌词是内心的呐喊。“好想成为人类啊”是当时灯的心声，在某种程度上也是祥子的心声。',
    ),
    StickerDefinition(
      characterName: '丰川祥子',
      title: '思考',
      assetPath: 'assets/stickers/思考.gif',
      description: '丰川祥子抱臂低头，皱着眉，头顶冒出表示思考中的圆点。',
    ),
    StickerDefinition(
      characterName: '丰川祥子',
      title: '小祥',
      assetPath: 'assets/stickers/小祥.gif',
      description: '小时候的丰川祥子闭眼微笑，怀里抱着母亲留下的小人偶。',
    ),

    // 丰川祥子 · 动态 · 夜奏未终
    StickerDefinition(
      characterName: '丰川祥子',
      title: '打call',
      assetPath: 'assets/stickers/丰川祥子_打call.gif',
      description: '丰川祥子挥动沙锤热情应援，整个人显得十分投入。',
    ),
    StickerDefinition(
      characterName: '丰川祥子',
      title: '神降临',
      assetPath: 'assets/stickers/丰川祥子_神降临.gif',
      description: '丰川祥子带着自信的笑容，宣布自己要成为Ave Mujica的神明，承担下队伍的一切责任。',
    ),
    StickerDefinition(
      characterName: '丰川祥子',
      title: '退勤',
      assetPath: 'assets/stickers/丰川祥子_退勤.gif',
      description: '丰川祥子点击电脑屏幕上的“退勤”按钮，结束了打工的客服工作，准备离开。',
    ),
    StickerDefinition(
      characterName: '丰川祥子',
      title: 'cool',
      assetPath: 'assets/stickers/丰川祥子_cool.gif',
      description: 'Ave Mujica的演出上，丰川祥子戴着黑色花纹面具，抬手遮在嘴前摇动，显得神秘又帅气。',
    ),

    // 丰川祥子 · 动态 · 夜愿华章
    StickerDefinition(
      characterName: '丰川祥子',
      title: '不可以',
      assetPath: 'assets/stickers/丰川祥子_不可以.gif',
      description: '丰川祥子神情严肃地探过头来，作出制止的姿态。',
    ),
    StickerDefinition(
      characterName: '丰川祥子',
      title: '鼓掌',
      assetPath: 'assets/stickers/丰川祥子_鼓掌.gif',
      description: '丰川祥子双手在胸前认真又开心地鼓掌。',
    ),
    StickerDefinition(
      characterName: '丰川祥子',
      title: '伸手',
      assetPath: 'assets/stickers/丰川祥子_伸手.gif',
      description: '丰川祥子露出明朗的笑容，眼睛发亮，一只手伸向前方，热情地发出邀约。',
    ),

    // 若叶睦 · 静态 · 夜奏未终
    StickerDefinition(
      characterName: '若叶睦',
      title: '诶',
      assetPath: 'assets/stickers/若叶睦_诶.gif',
      description: '若叶睦（此时为Mortis人格）手指抵着嘴唇，露出微微意外或疑惑的神情。',
    ),
    StickerDefinition(
      characterName: '若叶睦',
      title: '哼',
      assetPath: 'assets/stickers/若叶睦_哼.gif',
      description: '若叶睦（此时为Mortis人格）鼓起脸，带着一点不服气的情绪。',
    ),
    StickerDefinition(
      characterName: '若叶睦',
      title: '开心',
      assetPath: 'assets/stickers/若叶睦_开心.gif',
      description: '若叶睦（此时为Mortis人格）双眼弯成月牙，开怀大笑。',
    ),
    StickerDefinition(
      characterName: '若叶睦',
      title: '怎么突然',
      assetPath: 'assets/stickers/若叶睦_怎么突然.gif',
      description: '若叶睦（此时为Mortis人格）睁大眼睛看向上方，脸上挂着汗珠，露出意外和心虚的表情。',
    ),

    // 若叶睦 · 静态 · 夜愿华章
    StickerDefinition(
      characterName: '若叶睦',
      title: '抱抱',
      assetPath: 'assets/stickers/抱抱.gif',
      description: '若叶睦神情平静地向前伸出双手，像是在等待拥抱。',
    ),
    StickerDefinition(
      characterName: '若叶睦',
      title: '唱歌',
      assetPath: 'assets/stickers/唱歌.gif',
      description: '若叶睦拿着麦克风开口唱歌，旁边飘着音符。',
    ),
    StickerDefinition(
      characterName: '若叶睦',
      title: '是秘密哦',
      assetPath: 'assets/stickers/是秘密哦.gif',
      description: '若叶睦（此时是Mortis人格）把手指竖在唇前，咧着嘴露出有点坏的笑，示意对方保守秘密。',
    ),
    StickerDefinition(
      characterName: '若叶睦',
      title: '雨天',
      assetPath: 'assets/stickers/雨天.gif',
      description: '若叶睦站在雨中，神情痛苦地看着前方，身上被淋得湿透。',
    ),

    // 若叶睦 · 动态 · 夜奏未终
    StickerDefinition(
      characterName: '若叶睦',
      title: '喝饮料',
      assetPath: 'assets/stickers/若叶睦_喝饮料.gif',
      description: '若叶睦叼着吸管默不作声地喝芒果汁。',
    ),
    StickerDefinition(
      characterName: '若叶睦',
      title: '浇黄瓜',
      assetPath: 'assets/stickers/若叶睦_浇黄瓜.gif',
      description: '若叶睦抱着水壶认真给黄瓜浇水，神情专注而平静。',
    ),
    StickerDefinition(
      characterName: '若叶睦',
      title: '撒娇',
      assetPath: 'assets/stickers/若叶睦_撒娇.gif',
      description: '若叶睦（此时为Mortis人格）闭起双眼，攥着拳头上下挥动双臂，噘嘴撒娇耍赖。',
    ),
    StickerDefinition(
      characterName: '若叶睦',
      title: '捂嘴笑',
      assetPath: 'assets/stickers/若叶睦_捂嘴笑.gif',
      description: '若叶睦抬手捂住嘴巴，眉眼弯弯，偷偷憋笑。',
    ),

    // 若叶睦 · 动态 · 夜愿华章
    StickerDefinition(
      characterName: '若叶睦',
      title: '叫我吗',
      assetPath: 'assets/stickers/若叶睦_叫我吗.gif',
      description: '若叶睦（此时为Mortis人格）从门框后探出脸，像是听见有人叫自己。',
    ),
    StickerDefinition(
      characterName: '若叶睦',
      title: '生气',
      assetPath: 'assets/stickers/若叶睦_生气.gif',
      description: '若叶睦背后炸开黑色鬼影，面无表情地直视前方，气场很凶。',
    ),
    StickerDefinition(
      characterName: '若叶睦',
      title: 'wink',
      assetPath: 'assets/stickers/若叶睦_wink.gif',
      description: '若叶睦歪头，单眼眨动，露出俏皮的微笑。',
    ),

    // 三角初华 · 静态 · 夜奏未终
    StickerDefinition(
      characterName: '三角初华',
      title: '比叉叉',
      assetPath: 'assets/stickers/三角初华_比叉叉.gif',
      description: '三角初华用两根手指在身前比出叉号，紫眼睛亮晶晶，脸颊微红，表情灵动。',
    ),
    StickerDefinition(
      characterName: '三角初华',
      title: '挺好',
      assetPath: 'assets/stickers/三角初华_挺好.gif',
      description: '三角初华眉毛下垂，双眼眯起，露出略带苦涩的笑。',
    ),
    StickerDefinition(
      characterName: '三角初华',
      title: '再等一下',
      assetPath: 'assets/stickers/三角初华_再等一下.gif',
      description: '三角初华从门框后方探出半个身子，手抓着门边向外张望，表情略带羞涩，请对方再稍等片刻。',
    ),
    StickerDefinition(
      characterName: '三角初华',
      title: '震惊',
      assetPath: 'assets/stickers/三角初华_震惊.gif',
      description: '三角初华双眼圆睁，瞳孔缩小，身体僵住，满是错愕，像是受到了很大的打击。',
    ),

    // 三角初华 · 静态 · 夜愿华章
    StickerDefinition(
      characterName: '三角初华',
      title: '点赞',
      assetPath: 'assets/stickers/点赞.gif',
      description: '三角初华笑着伸出大拇指，传达认可和鼓励。',
    ),
    StickerDefinition(
      characterName: '三角初华',
      title: '害羞',
      assetPath: 'assets/stickers/害羞.gif',
      description: '三角初华脸红地双手贴在胸前，显得害羞又心动。',
    ),
    StickerDefinition(
      characterName: '三角初华',
      title: '接电话',
      assetPath: 'assets/stickers/接电话.gif',
      description: '三角初华拿着电话侧耳倾听，十分专注认真。',
    ),
    StickerDefinition(
      characterName: '三角初华',
      title: '没收',
      assetPath: 'assets/stickers/没收.gif',
      description: '三角初华的手机被别人拿走没收，神情惊慌。',
    ),

    // 三角初华 · 动态 · 夜奏未终
    StickerDefinition(
      characterName: '三角初华',
      title: '淋湿了',
      assetPath: 'assets/stickers/三角初华_淋湿了.gif',
      description: '淋浴的水顺着三角初华头发和脸往下淌，她情绪低落沮丧。',
    ),
    StickerDefinition(
      characterName: '三角初华',
      title: '实现了',
      assetPath: 'assets/stickers/三角初华_实现了.gif',
      description: '三角初华抬手托着脸颊，幸福开心地笑，一脸如愿以偿、欣喜激动的表情。',
    ),
    StickerDefinition(
      characterName: '三角初华',
      title: '咋舌',
      assetPath: 'assets/stickers/三角初华_咋舌.gif',
      description: '三角初华侧头，嘴角勾起一抹狡黠的浅笑，眼神带着玩味，轻轻咋舌。',
    ),
    StickerDefinition(
      characterName: '三角初华',
      title: '摘面具',
      assetPath: 'assets/stickers/三角初华_摘面具.gif',
      description: '三角初华帅气优雅地抬手把脸上的面具取下。',
    ),

    // 三角初华 · 动态 · 夜愿华章
    StickerDefinition(
      characterName: '三角初华',
      title: '领域展开',
      assetPath: 'assets/stickers/三角初华_领域展开.gif',
      description: '三角初华帅气地唱歌，背后展开黑色的蝙蝠翅膀，显现出Ave Mujica的标志。',
    ),
    StickerDefinition(
      characterName: '三角初华',
      title: '喜极而泣',
      assetPath: 'assets/stickers/三角初华_喜极而泣.gif',
      description: '三角初华喜极落泪，一边抹眼泪一边笑。',
    ),
    StickerDefinition(
      characterName: '三角初华',
      title: '摘墨镜',
      assetPath: 'assets/stickers/三角初华_摘墨镜.gif',
      description: '三角初华用手拉下墨镜露出眼睛，摆出自信又帅气的表情。',
    ),

    // 八幡海铃 · 静态 · 夜奏未终
    StickerDefinition(
      characterName: '八幡海铃',
      title: '难道？',
      assetPath: 'assets/stickers/八幡海铃_难道？.gif',
      description: '八幡海铃单手抵着下巴微微皱眉，眼神带着疑惑，一脸若有所思。',
    ),
    StickerDefinition(
      characterName: '八幡海铃',
      title: '睡觉',
      assetPath: 'assets/stickers/八幡海铃_睡觉.gif',
      description: '八幡海铃眼睛紧闭，双臂抱胸，向后靠在沙发靠背上，已经进入睡眠状态。',
    ),
    StickerDefinition(
      characterName: '八幡海铃',
      title: '我要告你',
      assetPath: 'assets/stickers/八幡海铃_我要告你.gif',
      description: '八幡海铃抱起双臂板着脸，眼神斜视，表示要去告状。',
    ),
    StickerDefinition(
      characterName: '八幡海铃',
      title: '一次买够',
      assetPath: 'assets/stickers/八幡海铃_一次买够.gif',
      description: '八幡海铃举起双臂，两只手臂上都挂满了购物袋，表情一本正经，摆出要一次买齐的架势。',
    ),

    // 八幡海铃 · 静态 · 夜愿华章
    StickerDefinition(
      characterName: '八幡海铃',
      title: '恭敬',
      assetPath: 'assets/stickers/恭敬.gif',
      description: '八幡海铃右手贴在胸前作“遵命”状，神情认真而恭敬。',
    ),
    StickerDefinition(
      characterName: '八幡海铃',
      title: '开门',
      assetPath: 'assets/stickers/开门.gif',
      description: '八幡海铃张口喊着“开门”。',
    ),
    StickerDefinition(
      characterName: '八幡海铃',
      title: '哟豁',
      assetPath: 'assets/stickers/哟豁.gif',
      description: '八幡海铃一只手托着下巴，露出玩味的神情。',
    ),
    StickerDefinition(
      characterName: '八幡海铃',
      title: '真谄媚啊',
      assetPath: 'assets/stickers/真谄媚啊.gif',
      description: '八幡海铃微张嘴巴，眉头轻皱，面露吐槽、嫌弃又无奈的神情。',
    ),

    // 八幡海铃 · 动态 · 夜奏未终
    StickerDefinition(
      characterName: '八幡海铃',
      title: '憋不住了',
      assetPath: 'assets/stickers/八幡海铃_憋不住了.gif',
      description: '八幡海铃睁大眼睛，手捂住嘴，极力忍耐快要绷不住。',
    ),
    StickerDefinition(
      characterName: '八幡海铃',
      title: '干得好',
      assetPath: 'assets/stickers/八幡海铃_干得好.gif',
      description: '八幡海铃双手在胸前认真鼓掌，表示肯定和赞许。',
    ),
    StickerDefinition(
      characterName: '八幡海铃',
      title: '想要信赖',
      assetPath: 'assets/stickers/八幡海铃_想要信赖.gif',
      description: '八幡海铃张大嘴巴，眉头紧蹙，情绪激动地表示希望对方能信任她。',
    ),
    StickerDefinition(
      characterName: '八幡海铃',
      title: '再吃一个',
      assetPath: 'assets/stickers/八幡海铃_再吃一个.gif',
      description: '八幡海铃拿起马卡龙一个接一个地往嘴里送。',
    ),

    // 八幡海铃 · 动态 · 夜愿华章
    StickerDefinition(
      characterName: '八幡海铃',
      title: '豪饮',
      assetPath: 'assets/stickers/八幡海铃_豪饮.gif',
      description: '八幡海铃举起纸盒饮料大口猛喝。',
    ),
    StickerDefinition(
      characterName: '八幡海铃',
      title: '帅气抹脸',
      assetPath: 'assets/stickers/八幡海铃_帅气抹脸.gif',
      description: '八幡海铃抬手从脸前潇洒划过，摆出帅气又从容的姿态。',
    ),
    StickerDefinition(
      characterName: '八幡海铃',
      title: '摇摇',
      assetPath: 'assets/stickers/八幡海铃_摇摇.gif',
      description: '八幡海铃拿着蛋白粉杯子左摇右摇。',
    ),

    // 祐天寺若麦 · 静态 · 夜奏未终
    StickerDefinition(
      characterName: '祐天寺若麦',
      title: '不行',
      assetPath: 'assets/stickers/祐天寺若麦_不行.gif',
      description: '祐天寺若麦闭眼交叉双臂，用坚决的动作表示拒绝。',
    ),
    StickerDefinition(
      characterName: '祐天寺若麦',
      title: '赌气',
      assetPath: 'assets/stickers/祐天寺若麦_赌气.gif',
      description: '祐天寺若麦鼓起脸颊偏过头，明显在闹别扭。',
    ),
    StickerDefinition(
      characterName: '祐天寺若麦',
      title: '记得微笑',
      assetPath: 'assets/stickers/祐天寺若麦_记得微笑.gif',
      description: '祐天寺若麦用手指托起嘴角示范笑容，提醒对方别忘了微笑。',
    ),
    StickerDefinition(
      characterName: '祐天寺若麦',
      title: '委屈',
      assetPath: 'assets/stickers/祐天寺若麦_委屈.gif',
      description: '祐天寺若麦眼眶泛红并抿着嘴，像是受了委屈却强忍着。',
    ),

    // 祐天寺若麦 · 静态 · 夜愿华章
    StickerDefinition(
      characterName: '祐天寺若麦',
      title: '坏坏',
      assetPath: 'assets/stickers/坏坏.gif',
      description: '祐天寺若麦双手抱胸，坏坏地笑，像在故意使坏或逗人。',
    ),
    StickerDefinition(
      characterName: '祐天寺若麦',
      title: '加个好友',
      assetPath: 'assets/stickers/加个好友.gif',
      description: '祐天寺若麦微笑着递出手机，邀请对方加个好友。',
    ),
    StickerDefinition(
      characterName: '祐天寺若麦',
      title: '难道说',
      assetPath: 'assets/stickers/难道说.gif',
      description: '祐天寺若麦看着手机惊讶地瞪大眼、张大嘴，像是发现了意外情况。',
    ),
    StickerDefinition(
      characterName: '祐天寺若麦',
      title: '哦',
      assetPath: 'assets/stickers/哦.gif',
      description: '祐天寺若麦半低着头发出“哦”，带着恍然或意外。',
    ),

    // 祐天寺若麦 · 动态 · 夜奏未终
    StickerDefinition(
      characterName: '祐天寺若麦',
      title: '拜托了喵',
      assetPath: 'assets/stickers/祐天寺若麦_拜托了喵.gif',
      description: '祐天寺若麦双手合十靠近脸颊，认真又可爱地向对方拜托。',
    ),
    StickerDefinition(
      characterName: '祐天寺若麦',
      title: '感动大哭',
      assetPath: 'assets/stickers/祐天寺若麦_感动大哭.gif',
      description: '祐天寺若麦捧着杯子哭得停不下来，像是被深深感动了。',
    ),
    StickerDefinition(
      characterName: '祐天寺若麦',
      title: '晚上好喵',
      assetPath: 'assets/stickers/祐天寺若麦_晚上好喵.gif',
      description: '祐天寺若麦抬起手作猫爪状，可爱地向对方道晚安。',
    ),
    StickerDefinition(
      characterName: '祐天寺若麦',
      title: '嘻嘻喵',
      assetPath: 'assets/stickers/祐天寺若麦_嘻嘻喵.gif',
      description: '祐天寺若麦歪头眯眼偷笑，作出俏皮的猫咪姿态。',
    ),

    // 祐天寺若麦 · 动态 · 夜愿华章
    StickerDefinition(
      characterName: '祐天寺若麦',
      title: '哇',
      assetPath: 'assets/stickers/祐天寺若麦_哇.gif',
      description: '祐天寺若麦睁大眼睛张开嘴，毫不掩饰自己的惊叹。',
    ),
    StickerDefinition(
      characterName: '祐天寺若麦',
      title: '再见',
      assetPath: 'assets/stickers/祐天寺若麦_再见.gif',
      description: '祐天寺若麦抬手向对方挥别，用动作认真道别。',
    ),
    StickerDefinition(
      characterName: '祐天寺若麦',
      title: '张望',
      assetPath: 'assets/stickers/祐天寺若麦_张望.gif',
      description: '祐天寺若麦抬起头左右查看，像是在寻找某个人或东西。',
    ),

    // 纯田真奈 · 静态 · 夜愿华章
    StickerDefinition(
      characterName: '纯田真奈',
      title: '分你一半',
      assetPath: 'assets/stickers/分你一半.gif',
      description: '纯田真奈笑着把甜甜圈分成两半，愿意与对方分享。',
    ),
    StickerDefinition(
      characterName: '纯田真奈',
      title: '伸懒腰',
      assetPath: 'assets/stickers/伸懒腰.gif',
      description: '纯田真奈闭眼伸着懒腰，神情轻松而舒服。',
    ),
    StickerDefinition(
      characterName: '纯田真奈',
      title: '五冠王',
      assetPath: 'assets/stickers/五冠王.gif',
      description: '纯田真奈捧着脸笑，头顶写着她在唱歌比赛里取得的“五冠王”的成就，显得十分兴奋。',
    ),
    StickerDefinition(
      characterName: '纯田真奈',
      title: 'wink',
      assetPath: 'assets/stickers/wink.gif',
      description: '纯田真奈笑着眨眼挥手，活泼地向对方打招呼。',
    ),

    // 熊猫 · 静态 · 夜愿华章
    StickerDefinition(
      characterName: '熊猫',
      title: '哭哭',
      assetPath: 'assets/stickers/哭哭.gif',
      description: '一只熊猫眼泪汪汪地哭泣，显得委屈又可怜。这是海铃手机里的表情包。立希也喜欢熊猫',
    ),

    // BanGDream · 静态
    StickerDefinition(
      characterName: '户山香澄',
      title: '期待',
      assetPath: 'assets/stickers/户山香澄_期待.gif',
      description: '户山香澄双眼发亮地望向前方，满脸都是期待。',
    ),
    StickerDefinition(
      characterName: '市谷有咲',
      title: '汗',
      assetPath: 'assets/stickers/市谷有咲_汗.gif',
      description: '市谷有咲脸上挂着汗滴，露出为难又不知道怎么接话的表情。',
    ),
    StickerDefinition(
      characterName: '牛込里美',
      title: '害羞',
      assetPath: 'assets/stickers/牛込里美_害羞.gif',
      description: '牛込里美脸颊泛红并收紧动作，不好意思地避开视线。',
    ),
    StickerDefinition(
      characterName: '山吹沙绫',
      title: '没问题',
      assetPath: 'assets/stickers/山吹沙绫_没问题.gif',
      description: '山吹沙绫自信地作出肯定动作，表示事情可以放心交给她。',
    ),
    StickerDefinition(
      characterName: '花园多惠',
      title: '震惊',
      assetPath: 'assets/stickers/花园多惠_震惊.gif',
      description: '花园多惠双眼圆睁身体僵住，被眼前的情况震惊得说不出话。',
    ),
    StickerDefinition(
      characterName: '凑友希那',
      title: '满足',
      assetPath: 'assets/stickers/凑友希那_满足.gif',
      description: '凑友希那眯起眼露出惬意笑容，显得非常满足。',
    ),
    StickerDefinition(
      characterName: '冰川纱夜',
      title: '不高兴',
      assetPath: 'assets/stickers/冰川纱夜_不高兴.gif',
      description: '冰川纱夜皱着眉侧过脸，明显露出不高兴的表情。',
    ),
    StickerDefinition(
      characterName: '今井莉莎',
      title: '点赞',
      assetPath: 'assets/stickers/今井莉莎_点赞.gif',
      description: '今井莉莎笑着竖起大拇指，直接表达认可和鼓励。',
    ),
    StickerDefinition(
      characterName: '宇田川亚子',
      title: '打call',
      assetPath: 'assets/stickers/宇田川亚子_打call.gif',
      description: '宇田川亚子挥动应援棒热情应援，整个人显得十分投入。',
    ),
    StickerDefinition(
      characterName: '白金燐子',
      title: '懵',
      assetPath: 'assets/stickers/白金燐子_懵.gif',
      description: '白金燐子呆呆看着前方没有反应，像是完全没弄清状况。',
    ),
    StickerDefinition(
      characterName: '美竹兰',
      title: '嫌弃',
      assetPath: 'assets/stickers/美竹兰_嫌弃.gif',
      description: '美竹兰皱眉侧目看向一旁，露出毫不掩饰的嫌弃。',
    ),
    StickerDefinition(
      characterName: '青叶摩卡',
      title: '满足',
      assetPath: 'assets/stickers/青叶摩卡_满足.gif',
      description: '青叶摩卡眯起眼露出惬意笑容，显得非常满足。',
    ),
    StickerDefinition(
      characterName: '宇田川巴',
      title: '尴尬',
      assetPath: 'assets/stickers/宇田川巴_尴尬.gif',
      description: '宇田川巴神情僵住并避开视线，显得十分尴尬。',
    ),
    StickerDefinition(
      characterName: '上原绯玛丽',
      title: '宠溺',
      assetPath: 'assets/stickers/上原绯玛丽_宠溺.gif',
      description: '上原绯玛丽托着脸露出温柔笑容，眼神里带着明显的宠爱。',
    ),
    StickerDefinition(
      characterName: '羽泽鸫',
      title: '讨厌',
      assetPath: 'assets/stickers/羽泽鸫_讨厌.gif',
      description: '羽泽鸫皱眉露出抗拒表情，明确表现出不喜欢。',
    ),
    StickerDefinition(
      characterName: '丸山彩',
      title: '躲藏',
      assetPath: 'assets/stickers/丸山彩_躲藏.gif',
      description: '丸山彩把身体藏到遮挡物后，只露出一部分悄悄张望。',
    ),
    StickerDefinition(
      characterName: '白鹭千圣',
      title: '暗中观察',
      assetPath: 'assets/stickers/白鹭千圣_暗中观察.gif',
      description: '白鹭千圣躲在一旁悄悄探出视线，谨慎地观察周围。',
    ),
    StickerDefinition(
      characterName: '冰川日菜',
      title: '挽留',
      assetPath: 'assets/stickers/冰川日菜_挽留.gif',
      description: '冰川日菜伸手拉住对方，认真表达不希望对方离开。',
    ),
    StickerDefinition(
      characterName: '若宫伊芙',
      title: '比心',
      assetPath: 'assets/stickers/若宫伊芙_比心.gif',
      description: '若宫伊芙双手在胸前比出爱心，笑着传达喜欢和支持。',
    ),
    StickerDefinition(
      characterName: '大和麻弥',
      title: '紧张',
      assetPath: 'assets/stickers/大和麻弥_紧张.gif',
      description: '大和麻弥神情僵硬并冒出冷汗，显得非常紧张。',
    ),
    StickerDefinition(
      characterName: '弦卷心',
      title: '好耶',
      assetPath: 'assets/stickers/弦卷心_好耶.gif',
      description: '弦卷心高举双手兴奋欢呼，毫不掩饰自己的开心。',
    ),
    StickerDefinition(
      characterName: '濑田薰',
      title: '送花',
      assetPath: 'assets/stickers/濑田薰_送花.gif',
      description: '濑田薰微笑着把花递向前方，优雅地表达好意。',
    ),
    StickerDefinition(
      characterName: '北泽育美',
      title: '高兴',
      assetPath: 'assets/stickers/北泽育美_高兴.gif',
      description: '北泽育美眉眼舒展开来露出灿烂笑容，显得十分高兴。',
    ),
    StickerDefinition(
      characterName: '松原花音',
      title: '害怕',
      assetPath: 'assets/stickers/松原花音_害怕.gif',
      description: '松原花音身体微微缩起并睁大眼睛，显得紧张害怕。',
    ),
    StickerDefinition(
      characterName: '米歇尔',
      title: 'DJ',
      assetPath: 'assets/stickers/米歇尔_DJ.gif',
      description: '米歇尔站在打碟设备前挥动双手，投入地进行DJ表演。',
    ),
    StickerDefinition(
      characterName: '和奏瑞依',
      title: '拽',
      assetPath: 'assets/stickers/和奏瑞依_拽.gif',
      description: '和奏瑞依微微扬起下巴露出酷酷的神情，显得很有气势。',
    ),
    StickerDefinition(
      characterName: '朝日六花',
      title: '不可以',
      assetPath: 'assets/stickers/朝日六花_不可以.gif',
      description: '朝日六花神情严肃地作出制止动作，明确表示不允许。',
    ),
    StickerDefinition(
      characterName: '佐藤益木',
      title: '来了',
      assetPath: 'assets/stickers/佐藤益木_来了.gif',
      description: '佐藤益木从画面一侧迅速出现，像是在回应呼唤赶来。',
    ),
    StickerDefinition(
      characterName: '鳰原令王那',
      title: '太好了',
      assetPath: 'assets/stickers/鳰原令王那_太好了.gif',
      description: '鳰原令王那露出灿烂笑容开心庆祝，像是听到了好消息。',
    ),
    StickerDefinition(
      characterName: '珠手知由',
      title: '阴谋',
      assetPath: 'assets/stickers/珠手知由_阴谋.gif',
      description: '珠手知由双手交握露出狡黠笑容，像是在计划小小的阴谋。',
    ),
    StickerDefinition(
      characterName: '仓田真白',
      title: '惊慌',
      assetPath: 'assets/stickers/仓田真白_惊慌.gif',
      description: '仓田真白瞪大眼睛慌张后退，一时不知道该怎么办。',
    ),
    StickerDefinition(
      characterName: '二叶筑紫',
      title: '不满',
      assetPath: 'assets/stickers/二叶筑紫_不满.gif',
      description: '二叶筑紫鼓着脸皱起眉，对眼前的情况很不满意。',
    ),
    StickerDefinition(
      characterName: '桐谷透子',
      title: '心虚',
      assetPath: 'assets/stickers/桐谷透子_心虚.gif',
      description: '桐谷透子避开视线露出不自然的笑，明显有些心虚。',
    ),
    StickerDefinition(
      characterName: '广町七深',
      title: '安详',
      assetPath: 'assets/stickers/广町七深_安详.gif',
      description: '广町七深闭着眼平静地躺着，神情放松而安详。',
    ),
    StickerDefinition(
      characterName: '八潮瑠唯',
      title: '优雅',
      assetPath: 'assets/stickers/八潮瑠唯_优雅.gif',
      description: '八潮瑠唯姿态端正从容，举止显得安静而优雅。',
    ),
    StickerDefinition(
      characterName: '高松灯',
      title: '放松',
      assetPath: 'assets/stickers/高松灯_放松.gif',
      description: '高松灯舒展开身体露出轻松表情，紧绷感明显消失。',
    ),
    StickerDefinition(
      characterName: '千早爱音',
      title: '不解',
      assetPath: 'assets/stickers/千早爱音_不解.gif',
      description: '千早爱音歪着头皱起眉，显得疑惑而没有弄明白。',
    ),
    StickerDefinition(
      characterName: '长崎爽世',
      title: '微笑',
      assetPath: 'assets/stickers/长崎爽世_微笑.gif',
      description: '长崎爽世微微眯起眼睛，带着礼貌而平静的浅笑。',
    ),
    StickerDefinition(
      characterName: '椎名立希',
      title: '怒',
      assetPath: 'assets/stickers/椎名立希_怒.gif',
      description: '椎名立希眉头紧锁并露出怒容，显然正在生气。',
    ),
    StickerDefinition(
      characterName: '要乐奈',
      title: '困',
      assetPath: 'assets/stickers/要乐奈_困.gif',
      description: '要乐奈半闭着眼打不起精神，明显已经困倦。',
    ),
  ];

  static String userMessageContent(StickerDefinition sticker) => '【用户发送了表情包】\n'
      '表达标签：${sticker.title}\n'
      '画面人物：${sticker.characterName}\n'
      '画面内容：${sticker.neutralVisualDescription}\n'
      '理解方式：这是用户对当前聊天作出的非文字回应。'
      '默认把画面中的表情和动作理解为用户此刻借表情包表达的状态、态度或意图。'
      '画面人物只是素材中的人物信息，不代表用户必然在谈论她；'
      '只有此前对话的当前话题明确围绕该人物时，才把人物身份用于理解这次回应。\n'
      '回复要求：结合表达标签、画面和此前对话，先接住用户这次表达的含义，再自然承接当前话题。'
      '不要仅因为看到“画面人物”就在回复里点名她；'
      '不要把你对表情包的猜测写成“你是想说……吗”一类确认意图的问句；'
      '无法确定唯一含义时，保持宽泛理解并自然回应，不要逼用户确认你的解读；'
      '除非上下文明确如此，不要把表情包当成现实中正在发生的事；'
      '不要忽略表情包另起话题，也不要向用户解释你读取了这些信息。';
}
