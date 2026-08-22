# 音乐分享起步说明

## 音频格式

优先使用 MP3：

- 推荐：`.mp3`
- 编码：128-192kbps
- 采样率：44.1kHz
- 声道：stereo

也可以尝试 `.wav`、`.m4a`，但 MP3 在 Windows、Android、iOS 和 Flutter 播放库里的兼容性最好。

## 文件放置

当前曲库文件：

```text
music/music_catalog.json
```

推荐音频目录：

```text
music/AveMujica/
music/MyGO/
```

示例：

```text
music/AveMujica/KiLLKiSS.mp3
music/MyGO/Haruhikage.mp3
```

如果你的文件名不同，修改 `music/music_catalog.json` 里的 `localAudioPath` 即可。

## 注意

这些音频只建议用于你自己的本地私用。不要把完整商业歌曲打包进公开发布版本；公开分发时更适合使用授权音频、短预览或外部链接。
