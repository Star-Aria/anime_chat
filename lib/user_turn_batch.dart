class UserTurnPart {
  final String text;
  final List<String> imagePaths;
  final bool isSticker;

  const UserTurnPart({
    required this.text,
    this.imagePaths = const [],
    this.isSticker = false,
  });
}

class UserTurnBatch {
  final List<UserTurnPart> parts;

  UserTurnBatch(Iterable<UserTurnPart> parts)
      : parts = List.unmodifiable(parts);

  bool get containsSticker => parts.any((part) => part.isSticker);

  bool get isStickerOnly =>
      parts.isNotEmpty && parts.every((part) => part.isSticker);

  List<String> get imagePaths => [
        for (final part in parts) ...part.imagePaths,
      ];

  String get serviceQuery => parts
      .where((part) => !part.isSticker)
      .map((part) => part.text.trim())
      .where((text) => text.isNotEmpty)
      .join('\n');

  String get responsePrompt {
    if (parts.isEmpty) return '';
    if (parts.length == 1) return parts.single.text;

    final buffer = StringBuffer()
      ..writeln('【用户在同一轮连续发送了以下内容】')
      ..writeln('请结合发送顺序把它们作为一个整体理解，只回复一次，不要逐条分别作答。');
    for (int i = 0; i < parts.length; i++) {
      final part = parts[i];
      final kind = part.isSticker ? '表情包' : '文字或图片消息';
      buffer
        ..writeln()
        ..writeln('第${i + 1}条（$kind）：')
        ..write(part.text.trim());
    }
    return buffer.toString().trim();
  }
}
