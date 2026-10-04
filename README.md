<p align="center"><img src="Resources/AppIcon.png" width="160" alt="LiveLingo icon"></p>

# LiveLingo · Safari 双语直播字幕

原生 macOS 应用，读取 Safari 正在播放的声音，显示日语或英语原文与简体中文。日语优先，适用于没有 CC 的 YouTube 直播、视频和其他 Safari 网页音频。当前版本 **0.4.0**。

识别使用 **Apple SpeechAnalyzer / SpeechTranscriber**，翻译使用 **Apple Translation**。模型在本机执行，无需 API Key、云端翻译订阅或 BlackHole；首次下载语言模型需要联网。

## 系统与构建

- Apple Silicon，macOS 26 或更新。
- 构建工具需包含 macOS 26.4 或更新 SDK。使用 Xcode 或 Command Line Tools 自带 Swift、sips、iconutil 与 codesign，无第三方依赖。
- 当前构建采用 ad-hoc 签名，尚未进行 Developer ID 签名或 Apple 公证。下载构建在其他 Mac 上的 Gatekeeper 行为未验证；可阅读源码并自行构建。

```sh
git clone https://github.com/hamletroyophelia/safari-live-subtitles.git
cd safari-live-subtitles
./scripts/build.sh
./scripts/test.sh
```

双击 `打开双语字幕.command`，或打开 `build/双语直播字幕.app`。修改源码后先退出正在运行的应用再重新构建。

## 使用

1. 选择日语或英语，点击 **准备语言模型**，完成首次模型下载。
2. 在 Safari 播放有声音的直播或视频，点击 **开始字幕**。
3. 按 macOS 官方选择器选择 **Safari 应用** 并确认本次共享。也可在系统设置 → 隐私与安全性 → 录屏与系统录音授予持续权限，再按系统提示重开应用。
4. 按住字幕窗顶部拖动条移动；拖动右下角手柄调整宽度和高度。手动调整后保留尺寸，勾选 **自动高度** 可恢复自适应。
5. 鼠标穿透开启时可直接操作视频；要移动或缩放字幕，先从控制台或菜单栏关闭穿透。

Safari 输入电平持续为零时，可先停止，再选 **全部系统声音** 作为兼容路径，这会包含其他应用声音。关闭控制台后应用仍在菜单栏运行；菜单中可停止识别、显示窗口或完全退出。每次开始会新建字幕记录，需保存上一段时先导出 SRT。

## 字幕行为

- 原文以流式临时结果立即更新，后续识别可能修正前文。
- 部分结果约每 0.3 秒送译，最终结果立即送译；这是送译间隔，端到端延迟还包含模型处理时间。
- 原文继续追加时保留上一版中文，新的译文完成后替换；前缀被修正时拒绝不匹配的旧译文，较早的短译文也不能覆盖最新长译文。
- macOS 26.4 及更新使用 `lowLatency` 翻译策略。中文以整段修订更新，Apple 接口没有逐 token 输出。
- 翻译队列只保留最新 4 项，严重落后时可能跳过旧项。未完整翻译的记录在 SRT 中标注“中文翻译尚未完成”。
- 字幕窗可置顶、跨桌面，配置为全屏辅助面板；位置、尺寸、字号、背景深度与自动高度偏好保留。长句优先显示末尾，控制台保留完整内容。
- 控制台显示最近 80 条，内存最多保留 2000 条。SRT 时间相对于本次捕获开始，不是视频绝对时间码。
- 单次会话使用一种原语言；混合语言识别尚未评估。外观预览是明确标注的演示文字。

## 字幕样式

控制台点击 **字幕样式…**，设置实时生效并在重启后保留：

- 原文和中文的独立字号、颜色与粗细；系统黑体、圆角或衬线字体设计。
- 左中右对齐、原文或中文在上、隐藏原文、两行间距和文字阴影。
- 背景颜色、不透明度（含全透明）、圆角和细边框。
- 深色默认、透明字幕、中文突出预设，以及恢复默认样式。

面板内有标明“演示文字”的预览。样式只影响悬浮字幕，SRT 内容不受影响。手动尺寸不足以容纳新字号时会增加到最小可读高度；自动高度继续按内容调整。

## 游戏词典

内置 [112 条日英中术语](Resources/game-glossary.json)，覆盖 11 个分类和综合入口：格斗、FPS、常见魂游和 Minecraft。控制台勾选 **游戏术语词典**，默认 **综合游戏（全部）** 同时覆盖所有分类；也可选择单游戏。可导入自定义 JSON 或恢复内置，重启保留选择。

macOS 26.4+ 通过受保护占位符与结果校验恢复中文译名；校验失败时用原文重译。原始词库含 91 条保护译名、21 条歧义词；综合模式中同词不同译名也不强制替换。0.4 起字幕记录和悬浮窗只显示原文与中文，词典在后台处理，不额外显示术语或对照行。macOS 26.0–26.3 使用普通翻译。识别原文保持不变，SRT 使用最终中文。

导入是完整替换当前词库；[JSON 示例](examples/game-glossary.json) 和 [使用、格式、词典来源说明](docs/GAME_GLOSSARIES.md) 可供扩充。此功能不训练 Apple 模型，不支持直接导入 MDX。

## 验证与限制

- 在 macOS 27 / arm64 编译，Info.plist 与 ad-hoc 签名校验通过。
- 字幕范围修正、流式译文保留、过期响应拒绝、最终结果、历史容量、SRT 与显示末尾检查通过。
- 词典匹配、继承、英文边界、Unicode、重复术语、占位符校验、失败回退、取消、流式记录及 SRT 检查通过。9 个真实本地翻译用例覆盖日语、英语和 5 个游戏分类，均保留指定译名且未泄漏占位符。
- 原生 UI 已验证字幕窗拖动、宽高调整、偏好保存与恢复，以及重复准备日语模型。词典文字试译、JSON 导入、重启保留和恢复内置已验证。0.4 的真实本机试译确认保留指定译名且没有额外术语行，样式面板和预览已由用户确认正常。
- 216 组本机字体、字号、粗细和原文显示组合的行高与手动窗口空间计算检查通过。
- 日语、英语测试文件曾通过真实 SpeechAnalyzer；日中、英中 Translation 调用成功。Safari 音频 → 原文 → 中文流程曾用测试播放和无 CC 日语视频回放跑通。
- 最新修订版本的持续直播准确率、端到端延迟、长时间稳定性、其他 Mac 的安装与 Safari 全屏叠加仍需实测。文件测试和演示文字不能代替实时直播验证。

## 隐私与资料

应用不保存录音或屏幕图像，不自动保存字幕；主动导出 SRT 才写出文字。公开仓库排除本地测试素材、日志、截图、偏好、凭据和机器路径。详见 [PRIVACY.md](PRIVACY.md)。

- [Apple ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos)
- [Apple SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer)
- [Apple TranslationSession](https://developer.apple.com/documentation/translation/translationsession)
- [图标生成方式与提示词](Resources/ICON_PROMPT.md)
- [第三方资料说明](THIRD_PARTY_NOTICES.md)
