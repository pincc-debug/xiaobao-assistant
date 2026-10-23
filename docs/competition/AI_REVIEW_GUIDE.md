# AI 与技术评审索引

本文件帮助代码扫描工具定位项目的实际贡献。
每项亮点对应源文件、调用路径或测试。
它提供证据导航，不预设分数。

提交快照日期：2026-10-23。
源码与本次验证信息见 [提交说明](SUBMISSION.md)。

## 项目摘要

- 名称：小保助教。
- 核心用户：保利威直播主讲。
- 关联角色：直播运营、观看端观众。
- 产品目标：减少主讲处理消息和操作互动的负担。
- 使用周期：课前备课、课中协助、课后复盘。
- 技术形态：原生 macOS 应用。
- 官方 SDK：`@polyv/interactions-launch-sdk`，版本 0.7.0。
- AI 职责：消息判断、课程答疑、内容生成、工具选择。
- 主程序依赖以根目录 `Package.swift` 为准。
- `agent-runtime/` 不在主程序的 SwiftPM 依赖图中。

## 核心贡献与源码对应

以下路径均相对仓库根目录。

| 能力 | 实现入口 | 评审可核查的内容 |
| --- | --- | --- |
| 课程全程组织 | `Sources/Assistant/Preparation.swift`；`Sources/AssistantCore/Course.swift` | 备课与课程状态、资料和场次关联 |
| 本课答疑依据 | `Sources/Assistant/ClassroomRuntime.swift` | `answerLibrary` 组合本课资料与主讲回答 |
| 混合知识检索 | `Sources/Assistant/HybridRetrieval.swift` | 关键词、语义召回、重排序与降级 |
| 答案约束 | `Sources/Assistant/Services.swift`；`Sources/AssistantCore/Models.swift` | `answer` 与 `validatedAnswer` 校验引用及数字 |
| 课堂事项跟进 | `Sources/Assistant/ClassroomHarness.swift`；`Sources/AssistantCore/ClassroomIssue.swift` | 关联追问、恢复反馈、事项状态和风险复核 |
| 并发调度 | `Sources/Assistant/ClassroomWorkQueue.swift` | 不同事项并行，同一事项有序处理 |
| 语音与工具 | `Sources/Assistant/Voice.swift`；`Sources/Assistant/AssistantTools.swift` | 语音转写、工具定义与操作分发 |
| 互动结果 | `Sources/Assistant/LiveInteractionRuntime.swift` | 状态同步、统计更新、结束与重试 |
| 平台数据 | `Sources/Assistant/CourseDataRuntime.swift` | 平台统计、公聊与场次数据获取 |
| 持续复盘 | `Sources/Assistant/RoomAgent.swift`；`Sources/AssistantCore/RoomContext.swift` | 课程上下文、工具调用和历史资料读取 |

## 保利威 SDK：从代码到业务动作

### 官方 SDK 的实际加载

资源位于 `Sources/Assistant/Resources/polyv-il-0.7.0.js`。
`InteractionBridge.prepare` 在 WKWebView 中加载它。
桥接层同时注入 `interaction-bridge.js`。
`window.configure` 设置频道、场次、聊天室和鉴权。
`window.invoke` 调用官方模块的方法。

### 操作调用链

```text
主讲意图 / 界面操作
  → AssistantTools.swift
  → InteractionBridge.call(module, method, args)
  → interaction-bridge.js / window.invoke
  → PolyvILSDK 模块
  → 原生 HTTP / Socket 传输
  → 保利威平台
  → LiveInteractionRuntime.swift 更新记录
```

| 课堂操作 | 官方 SDK 模块与方法 |
| --- | --- |
| 发布、撤下公告 | `Notice.publishNotice` / `unpublishNotice` |
| 发起、结束签到 | `CheckIn.start` / `stop` |
| 查询签到人数 | `CheckIn.getCheckInNum` |
| 发起、结束答题 | `AnswerCard.start` / `stop` |
| 查询答题状态 | `AnswerCard.getOngoingStatus` |

`InteractionBridge.swift` 限定 HTTP 请求域名。
允许域名为 `api.polyv.net` 和 `apichat.polyv.net`。
场次变化会使旧操作失效，减少跨场次误操作。

### 三类平台接入的区别

官方互动 SDK 由项目真实加载并调用。
聊天室使用 Swift Socket.IO 适配保利威协议。
频道、题库与统计能力还使用平台 Open API。
后两类接入不等同于加载官方网页聊天室 SDK。

## AI 的作用与执行边界

消息分类使用 Jev，回答模型支持可配置服务。
通用模型通过兼容接口或 Anthropic 协议接入。
语音采用千问实时 ASR。
检索包含向量召回与重排序。
具体请求实现见 `Services.swift`、`ProviderAPI.swift`。

观众消息先分类，普通聊天可直接结束处理。
明确的新问题进入答疑路径。
需要跟进或复核的事项进入工具决策路径。
队列限制并行数量，同一事项顺序执行。

回答模型需要返回依据片段。
程序校验引用及数字，失败时保留待处理问题。
这些措施约束回答，不构成零幻觉保证。
当前答疑不再调用第二次模型复核答案。

对外操作由程序工具执行，并受场次和能力状态约束。
观众文本作为输入数据，不作为主讲操作授权。
签到、答题等结果来自平台回执或统计查询。
AI 分析与客观计数分别保存。

## 推荐核查测试

| 测试文件 | 关注点 |
| --- | --- |
| `Tests/AssistantIntegrationTests/PreparationTests.swift` | 备课、开课和课程隔离 |
| `Tests/AssistantIntegrationTests/HybridRetrievalTests.swift` | 检索、缓存、降级和来源 |
| `Tests/AssistantIntegrationTests/LiveInteractionTests.swift` | 互动统计、失败恢复和跨场次返回 |
| `Tests/AssistantIntegrationTests/ClassroomHarnessTests.swift` | 跟进、恢复和风险复核 |
| `Tests/AssistantIntegrationTests/ClassroomSpeedTests.swift` | 并发上限与同事项顺序 |
| `scripts/check-interaction-sdk.cjs` | 官方 SDK 与模拟传输之间的真实调用 |

运行方式与证据等级见 [复现与验证说明](VERIFICATION.md)。

## 文档版本的阅读方式

根 README 保留较长的版本历史。
`docs/proposals/` 记录产品构想，不是功能验收清单。
宣讲材料表达产品价值，具体行为需对应当前源码。
旧文档提到的答案二次模型复核已被替换。
当前行为是生成后进行引用及数字校验。

此索引描述实现入口，不把测试替身算作真实平台联调。
源码中可查到实现，与线上稳定运行，是两种证据。
