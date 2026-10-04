# 日语、英语游戏实况术语

## 当前应用怎样使用词典

LiveLingo 的识别是 Apple SpeechAnalyzer / SpeechTranscriber，翻译是 Apple Translation，均在本机运行。词典已经接入翻译流程；它约束指定术语的中文译名，不修改识别原文，也不训练模型权重。

控制台勾选 **游戏术语词典**，默认 **综合游戏（全部）** 同时使用所有分类，无需逐个切换。需要明确歧义词的游戏语境时，再选择单游戏。内置 `Resources/game-glossary.json` 有 112 条术语、11 个分类和综合入口，其中 91 条保护译名、21 条歧义词不强制替换。所有术语存放在同一个文件，不需要导入多份词库。综合模式遇到同一别名有不同译名或策略时，不强制替换；候选仅保存在内部诊断结果中。各游戏继承通用实况词；魂游还继承魂游通用词，具体游戏的同名条目优先。

macOS 26.4 起支持 [AttributedString 的 skipsTranslation 属性](https://developer.apple.com/documentation/foundation/attributescopes/translationattributes/skipstranslation)。应用匹配原文术语后，用标记为跳过翻译的占位符发送给 Apple；返回后逐个校验占位符只出现一次，再恢复中文译名。直接保护日语或中文字符串在低延迟模型的实测中仍可能被改写，因此不能只依赖属性而不检查结果。

如果占位符缺失、重复、改写或有未知标记，应用用未经修改的原文重新翻译一次；不会把占位符显示到字幕。取消会话时不会重试。macOS 26.0–26.3 使用普通翻译，不保护译名。中文仍是完整文字的分段修订，保留原有的过期响应拒绝与稳定前缀逻辑。

0.4 起，悬浮窗和字幕记录只显示原文与中文，不额外显示词典译名、候选对照或回退说明。词典仍然在后台处理译名；CLI 的 `--glossary-report` 可用于诊断哪些术语已应用。SRT 写入原始识别原文与最终中文，保留未完成译文标记，不额外添加对照行。

`build`、`plant`、`farm` 等歧义词默认 `hint`，不会在所有句子中强行替换。日语按最长短语匹配；英语不区分大小写并检查 Unicode 词边界，不会把 `Netherland` 当作 `Nether`。游戏专名与不同机制仍需选择正确分类。词典不能修复语音误识别，也不能保证整句翻译准确率。

## 导入和编辑

点击 **导入 JSON** 选择词典文件。导入成功后完整替换当前词典，复制到本机应用支持目录并在重启后加载；原文件保留。非法 JSON、重复分类 ID、未知模式或循环继承会被拒绝，保留当前有效词典。点击 **恢复内置** 可重新使用内置词典。文件上限 2 MB、64 个分类、2000 条术语。

要在完整内置词库上增加条目，复制 `Resources/game-glossary.json` 后编辑，再导入。`examples/game-glossary.json` 是一个小型自定义格式示例，导入它只提供其中的分类与条目。

点击 **试译** 可以输入一句日语或英语，调用同一词典和真实 Apple 翻译检查结果，不读取直播音频。字幕会明确标注“文字试译”，不能当作语音识别或实时直播验证。

```json
{
  "schemaVersion": 2,
  "profiles": [{
    "id": "minecraft",
    "title": "Minecraft",
    "terms": [{
      "ja": ["クリーパー"],
      "en": ["Creeper", "creepers"],
      "zh-Hans": "苦力怕",
      "mode": "protect"
    }]
  }]
}
```

`ja`、`en` 是精确短语及别名列表，至少一组非空。`mode` 可为 `protect` 或 `hint`，缺省按 `hint` 处理。`inherits` 可列出同一文件中的其他分类 ID，父分类先加载、子分类覆盖同名别名；设置 `resolveConflicts: "hint"` 可将冲突译名合并为仅供对照的候选（综合模式使用此策略）；不能跨文件继承。英语复数或别称需明确列入别名，不自动猜测词形。词典不支持 MDX 直接导入或整库 JMdict 自动转换。

命令行复核同一翻译流程：

```sh
./build/双语直播字幕.app/Contents/MacOS/LiveLingo --translate-text 'クリーパーが来た。' --game minecraft --glossary-report
./build/双语直播字幕.app/Contents/MacOS/LiveLingo --translate-text 'Use an Ash of War.' --english --game elden_ring
```

可添加 `--glossary-file` 指定 JSON；不加 `--game` 时仍调用普通 Apple 翻译。Apple 没有自定义词典训练参数；本功能使用应用术语处理与公开的翻译属性。`AnalysisContext.contextualStrings` 文档针对 DictationTranscriber；当前 SpeechTranscriber 的识别词汇提示未接入。

## 可用来源

| 来源 | 适用范围 | 本地使用与发布注意 |
| --- | --- | --- |
| [JMdict / EDICT](https://www.edrdg.org/jmdict/j_jmdict.html) | 日语词形、读音、日英释义；通用词库基础 | 日英数据按 [EDRDG 许可](https://www.edrdg.org/edrdg/licence.html) 使用，当前为 CC BY-SA 4.0，需保留署名并遵守数据衍生许可。不是完整日中游戏词库。 |
| [Infil Fighting Game Glossary](https://glossary.infil.net/) | 格斗术语及日英对应，适合 SF、Tekken、Guilty Gear 等实况 | 适合查阅、核对社区惯用语。未确认允许整库再分发，因此本仓库只提供链接，不复制数据库、视频或长定义。 |
| [VALORANT 官方入门指南](https://playvalorant.com/en-us/news/announcements/beginners-guide/) | FPS 回合经济、下包、拆包及基础机制 | 按游戏核对；CS、Apex、VALORANT 的技能和物品名称不能共享一套替换规则。官方攻略不是可自由再分发的词典。 |
| [ELDEN RING 官方战斗指南](https://www.bandainamcoent.com/es_mx/news/elden-ring-introduction-part-4-combat-guide) | 魂游常见操作及 Elden Ring 机制 | 适合核对 stance、parry、guard counter 等机制。Dark Souls、Sekiro、Lies of P、Nioh、Lords of the Fallen 等应各建专名配置。只链接官方文章，不复制全文。 |
| [Minecraft 官方入门介绍](https://www.minecraft.net/en-us/article/exploring-minecraft) | 方块、生物、群系和生存玩法 | 精确物品名最好在本机从自己安装的对应游戏版本读取 `en_us`、`ja_jp`、`zh_cn` 语言资源，按同一键对齐。版本、Java/Bedrock、模组会造成差异；本仓库不捆绑完整游戏资源。 |

## 样例范围

`Resources/game-glossary.json` 包含通用直播、格斗、FPS、魂游、Elden Ring、Dark Souls、Sekiro、Lies of P、Nioh、Lords of the Fallen 和 Minecraft 的日语、英语、简体中文映射。它是起步样例，不是完整官方本地化表。短词和歧义词需要结合原文与游戏确认，不能在所有游戏中无条件强制替换。

推荐优先维护：主播常说的操作与感叹 → 游戏机制 → 装备与技能专名 → Boss 和角色名。根据真实字幕错误逐步扩充，比一次导入巨大通用词典更容易控制效果。

技术依据：[TranslationSession](https://developer.apple.com/documentation/translation/translationsession)、[SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber)。
