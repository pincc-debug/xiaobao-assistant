# 教室流式聊天（0.3.3 / build 29）

## 行为

- 教室聊天使用 API 原生流式输出（OpenAI 兼容协议 / Anthropic），正文实时更新，完成后一次性保存正式消息。工具参数分片单独拼接，完成并通过 JSON 解析后才能执行。推理内容不显示。
- SSE 按字节处理 UTF-8、CRLF、注释心跳与多行 data；限制响应大小，校验完成原因，拒绝截断、失败、多个同时工具调用。停止后关闭请求，迟到回调按运行与步骤 ID 丢弃。中断时保留暂存正文但不当成已完成消息，允许重试。
- 新回复复用现有聊天气泡；50ms 更新节流。位于底部时跟随输出，上翻阅读时不强制拉回。课内会话隔离，不能把另一节课的流式正文显示进来。
- 原生 Markdown 渲染标题、段落、粗体、斜体、行内代码、链接、列表、引用、围栏代码、分隔线和基础表格。不执行 HTML，不加载远程图片，链接仅允许 http/https/mailto。未闭合代码围栏仍按代码显示。用户原话维持纯文本。
- 新建教室：必填频道号在上，可选名称在下。

## 移除本机 Codex

根据用户要求删除本机 Codex 调用实现、设置入口和相关执行测试。仅在旧状态迁移时识别该服务并剔除，保留 API 服务、教室和课程；原默认是已移除服务时改为首个剩余 API 服务。无 API 服务时要求用户配置。不会卸载机器上的 Codex，不接触其登录或配置。

此前“模型未返回有效结构化结果，请更换模型后重试”来自该本机文本转 JSON 链路；该链路已移除。API 原生聊天正文不做 JSON 解析，只有工具参数和明确要求结构化的业务生成结果才解析。格式报错不再武断要求更换模型。

## 验证

- 全量非界面测试：147 项通过、5 项显式跳过，0 失败；日志 `evidence/chat-stream/headless-tests.log`。
- 新增 SSE 分片/UTF-8/心跳、多行 data、正文与推理隔离、工具参数拼接、缺失完成/截断拒绝、Anthropic、Markdown 分块、旧模型配置迁移测试。
- `XB_CHAT_STREAM_LIVE=1 XB_UI_TESTS=0 swift test --filter ChatStreamTests.testRealAPIConversationStreamsTwoTurns`：使用当前配置的 deepseek-v4.1-flash，在临时状态中测试问候和追问，两轮均捕获完成前的增量正文并正确落盘，8.677 秒。日志 `evidence/chat-stream/live-deepseek.log`。
- 文档+答题卡真实生成首轮只生成了文档，却回复两项完成；发现工具描述仍混称“题目草稿”。修正描述、成功结果约束及本轮产物清单后，复测通过，13.224 秒，文档及结构化题目均落盘、platformID/sentAt 均为空。失败与成功日志均保留。单次成功不意味着所有模型任务均必然成功。
- 遵循用户要求未打开应用或进行界面验收。Markdown 视觉与滚动手感仍需实际界面确认；Anthropic 流式只做协议测试，未真实调用。

协议依据：[DeepSeek Chat Completions](https://api-docs.deepseek.com/api/create-chat-completion/)。没有新增第三方 UI 或 Agent 运行时依赖。
