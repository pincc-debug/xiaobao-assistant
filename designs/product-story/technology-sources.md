# 技术概览的代码依据

本页根据本项目当前实现整理，不据此宣称所有接口均通过生产端到端验收。

| 图中节点 | 当前代码依据 | 图中职责 |
| --- | --- | --- |
| 小保助教 Agent | Sources/Assistant/AssistantTools.swift、ProviderAPI.swift、Preparation.swift、ClassroomSpaceView.swift | 课程上下文、任务决策、工具调用 |
| 保利威互动 SDK | InteractionBridge.swift:24 加载 polyv-il-0.7.0.js；AssistantTools.swift:229 起调用 CheckIn，:246 起调用 AnswerCard；LiveInteractionRuntime.swift 更新互动状态 | 发题、签到等课堂互动 |
| 保利威聊天室接入 | Services.swift 导入 SocketIO，ChatGateway.connect 获取保利威聊天 token 并建立 Socket.IO 连接；注册事件并发送消息 | 提问与回复等实时消息收发 |
| 保利威 Open API | CourseDataRuntime.swift:81/139/156/178 实时在线、场次概况、并发、历史公聊；LessonAssets.swift:137/163 查询及保存题目；ChannelOwnership.swift:21 频道校验 | 频道、题库、统计等资源与数据 |
| 大语言模型 | ProviderAPI.swift:37 generate；:68 chooseTool，OpenAI兼容与Anthropic协议原生工具调用；ChatStream.swift 流式解析 | 内容生成、工具调用 |
| Jev 决策 | Services.swift ModelsClient.jev 调用 jev-latest；classify 识别消息类型及同类问题；answer 再次核验回答依据 | 消息分类、答案核验 |
| 语音识别 | Voice.swift:27 qwen3-asr-flash-realtime；WebSocket实时转写；LiveStreamVoice.swift 直播音频入口 | 课堂转写、语音指令 |
| 知识检索 | HybridRetrieval.swift:43 text-embedding-v4；:54 gte-rerank-v2；:66 retrieve 混合关键词与语义检索，并保留课堂上下文 | 语义召回、重排序 |

聊天室命名边界：当前原生应用使用 Swift Socket.IO 适配保利威聊天室协议，没有直接加载保利威网页聊天室 SDK，因此图中写「聊天室接入 / Socket.IO 协议」。互动 SDK 则真实加载官方 JS 包，通过 WebKit 与原生传输桥执行。

图中不绑定某个通用大语言模型品牌，因为 ProviderAPI 接收所选 provider；具体模型由用户配置。ASR、向量与重排模型在代码中的名称如上。Jev 当前使用文本/结构化状态，图中不宣称直接理解视频画面。
