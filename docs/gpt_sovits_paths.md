# GPT-SoVITS 路径与搬家说明

程序不再绑定 `C:` 或 `E:`。自动启动、角色模型加载、参考音频转换使用同一个检测到的安装目录。原有角色配置中的 `GPT-SoVITS\...` 是逻辑路径，会映射到这个目录，无需逐个修改角色。

## 当前用法

整合包在 `E:\GPT-SoVITS-v2pro-20250604-nvidia50` 时，程序和项目根目录的 `启动GPT-SoVITS.cmd` 都会自动找到它。修改 Dart 代码后，正在运行的旧版程序需要停止并重新运行；已经打包的旧 EXE 需要重新构建。

查找顺序如下，只接受同时包含 `api_v2.py`、`runtime/python.exe`、`GPT_SoVITS/configs/tts_infer.yaml` 的完整安装：

1. `GPT_SOVITS_ROOT` 环境变量（相对路径以程序所在目录为基准）。
2. 程序所在目录、项目/工作目录及其上级目录中的 `gpt_sovits_path.txt`。
3. 程序所在目录及其上级目录，然后工作目录及其上级目录中的 `GPT-SoVITS` 或 `GPT-SoVITS-*` 文件夹。
4. 各个本地盘根目录中的 `GPT-SoVITS` 或 `GPT-SoVITS-*` 文件夹。

失效的旧配置会跳过，继续自动查找。存在多份安装时，建议用路径文件明确指定需要使用的那一份。

## 最适合整体搬家的结构

```text
聊天整合包/
  app/
    anime_chat_app.exe
    ...其余 Flutter 打包文件
  GPT-SoVITS-v2pro-20250604-nvidia50/
    api_v2.py
    runtime/
    GPT_SoVITS/
    GPT_weights_v2ProPlus/
    SoVITS_weights_v2ProPlus/
```

保持这种相对关系，可以把整个 `聊天整合包` 移到任意盘符、任意目录。开发时将引擎放在项目目录中或项目上级目录也可以。

若只把整合包从 E 盘根目录移到 F 盘根目录，保留 `GPT-SoVITS-*` 名称，也不需要改配置。移动前请关闭语音引擎和聊天程序，移动后重新启动。

## 单独放在任意深层目录，或重命名整合包

程序不会递归搜索整块硬盘。在聊天程序 EXE 旁边（开发时放项目根目录）创建 UTF-8 文本文件 `gpt_sovits_path.txt`，内容只写一个路径，例如：

```text
../语音工具/我的语音引擎
```

这个相对路径始终以 **路径文件所在目录** 为基准，与从哪里双击启动无关。也可以填写 `E:\语音工具\我的语音引擎` 这样的绝对路径，但单独移动目标后需要更新。该文件已加入 Git 忽略，不会把个人电脑路径提交进去。

相对路径只能适应“双方相对位置不变”的搬家；单独移动到完全未知的位置后，需要更新路径文件。这是预期边界，不代表相对路径失效。

## 引擎自身的模型配置

引擎会把模型切换 API 收到的路径写回 `GPT_SoVITS/configs/tts_infer.yaml`。现在程序会传整合包内的相对模型路径，避免重新写死盘符；整合包外的自定义模型仍保留原路径。

对于搬家前已保存的绝对路径，提供一次性修复工具：

```powershell
# 默认只预览；以下示例在项目根目录运行。
& 'E:\GPT-SoVITS-v2pro-20250604-nvidia50\runtime\python.exe' `
  tool/make_sovits_config_portable.py 'E:\GPT-SoVITS-v2pro-20250604-nvidia50'

# 确认后添加 --apply 应用。
& 'E:\GPT-SoVITS-v2pro-20250604-nvidia50\runtime\python.exe' `
  tool/make_sovits_config_portable.py 'E:\GPT-SoVITS-v2pro-20250604-nvidia50' --apply
```

仅转换当前整合包内确实存在的路径，保留设备、精度和版本设置，不修改模型文件。首次修改前会保留 `tts_infer.yaml.before-portable.bak`。如果以后使用其他工具重新写入了绝对路径，可再次运行此修复工具。

这里只调整 GPT-SoVITS 相关路径，不会更改聊天记录、API 配置或其他资源的存放方式。
