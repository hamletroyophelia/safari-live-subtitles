# 日语、英语游戏实况术语

## 当前应用怎样使用词典

LiveLingo 0.2 的识别是 Apple SpeechAnalyzer / SpeechTranscriber，翻译是 Apple Translation，均在本机运行。Apple 没有公开这些模型的产品名称或权重版本。

目前的 TranslationSession API 没有自定义 glossary、prompt、MDX 导入或模型微调参数。把词典放进目录不会让模型自动学习。仓库中的 `examples/game-glossary.json` 是原创术语样例，**尚未接入应用运行流程**。

以后可以做应用级术语层：选择游戏配置、匹配原文术语、给字幕附加经过确认的术语对照，或在高置信度时规范译名。不要盲目替换整段译文：`build` 可指角色配装或建筑，`poise` 与 `posture` 属于不同机制，`mob` 在 Minecraft 中也不总是怪物。日语需采用最长短语匹配，英语需检查词边界；专名、缩写、俚语和口语应分开维护。

若将来改用支持提示词或检索的本地语言模型，可只检索当前游戏、当前句子相关的少量术语作为上下文。完整 MDX 或 JMdict 不应直接塞入每次翻译。术语层也不能自动修复所有语音误识别。

Apple 的 [AnalysisContext.contextualStrings](https://developer.apple.com/documentation/speech/analysiscontext/contextualstrings) 文档将词汇提示用于 DictationTranscriber；当前应用使用 SpeechTranscriber，尚未验证相同提示对它生效，不能把该功能当成已实现。

## 可用来源

| 来源 | 适用范围 | 本地使用与发布注意 |
| --- | --- | --- |
| [JMdict / EDICT](https://www.edrdg.org/jmdict/j_jmdict.html) | 日语词形、读音、日英释义；通用词库基础 | 日英数据按 [EDRDG 许可](https://www.edrdg.org/edrdg/licence.html) 使用，当前为 CC BY-SA 4.0，需保留署名并遵守数据衍生许可。不是完整日中游戏词库。 |
| [Infil Fighting Game Glossary](https://glossary.infil.net/) | 格斗术语及日英对应，适合 SF、Tekken、Guilty Gear 等实况 | 适合查阅、核对社区惯用语。未确认允许整库再分发，因此本仓库只提供链接，不复制数据库、视频或长定义。 |
| [VALORANT 官方入门指南](https://playvalorant.com/en-us/news/announcements/beginners-guide/) | FPS 回合经济、下包、拆包及基础机制 | 按游戏核对；CS、Apex、VALORANT 的技能和物品名称不能共享一套替换规则。官方攻略不是可自由再分发的词典。 |
| [ELDEN RING 官方战斗指南](https://www.bandainamcoent.com/es_mx/news/elden-ring-introduction-part-4-combat-guide) | 魂游常见操作及 Elden Ring 机制 | 适合核对 stance、parry、guard counter 等机制。Dark Souls、Sekiro、Lies of P、Nioh、Lords of the Fallen 等应各建专名配置。只链接官方文章，不复制全文。 |
| [Minecraft 官方入门介绍](https://www.minecraft.net/en-us/article/exploring-minecraft) | 方块、生物、群系和生存玩法 | 精确物品名最好在本机从自己安装的对应游戏版本读取 `en_us`、`ja_jp`、`zh_cn` 语言资源，按同一键对齐。版本、Java/Bedrock、模组会造成差异；本仓库不捆绑完整游戏资源。 |

## 样例范围

`examples/game-glossary.json` 包含通用直播、格斗、FPS、魂游、Elden Ring、Dark Souls、Sekiro、Lies of P、Nioh、Lords of the Fallen 和 Minecraft 的日语、英语、简体中文映射。它是起步样例，不是完整官方本地化表。短词和歧义词需要结合原文与游戏确认，不能在所有游戏中无条件强制替换。

推荐优先维护：主播常说的操作与感叹 → 游戏机制 → 装备与技能专名 → Boss 和角色名。根据真实字幕错误逐步扩充，比一次导入巨大通用词典更容易控制效果。

技术依据：[TranslationSession](https://developer.apple.com/documentation/translation/translationsession)、[SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber)。
