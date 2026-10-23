# 课堂互动记录（0.2.7）

## 行为

讲师明确发题、签到或公告后，平台发送成功才创建置顶记录。自动答疑、讲课转写不触发这些动作；语音发起成功后结束本轮工具调用，防止模型随后自行收题。

- 答题：固定不限时，讲师点击“结束答题”。数据每轮约5秒查询，显示已答人数、正确率，笔记保留选项分布。数据发生变化时最多每30秒生成一份补讲建议，最终结束时重新生成。
- 签到：SDK要求时长，发起时需明确指定（现有支持范围1–120秒），卡片显示剩余时间；可提前点击“结束签到”，也会识别平台到时结束。没有应到名单，不以在线人数计算出勤率、不推断缺勤。按签到ID分页收集实际签到名单，未完整同步保留待同步卡片。
- 公告：显示正文和撤下按钮。撤下前检查当前公告内容，避免误撤其他人后来发布的公告。平台公告被替换或撤下时同步结束状态。

置顶卡片与“讲师笔记 → 课堂互动”共享CourseSession.interactions同一份记录，课后在课程回顾的课程笔记中查看。记录包括内容、平台ID、起止时间、统计快照、名单和分析；连续统计最多保留最近200个变化快照。公告不生成分析。

## 实时与结束后统计（修正）

- 签到进行中使用 `CheckIn.getCheckInNum`（Socket `GET_SIGN_IN_STATUS_FOR_LARGE`）读取人数，前后校验当前签到 ID。结束后才读取 `getCheckInDetail` 的最终统计和分页名单，避免把尚未同步的明细人数显示为实时人数。
- 答题进行中以 `AnswerCard.getOngoingStatus.statistics` 的总人数和选项分布为准。`getQuestionStatistics` 的正确人数只在总人数和选项分布匹配时附加，否则保持未知，不显示虚假的 0%。
- 结束后统计若低于已观察到的人数，保留原人数并继续同步，不将滞后的 0 作为最终结果。状态面板、笔记、语音查询使用相同统计逻辑。

## 失败与并发

- 结束动作失败，卡片保留并可重试。
- 平台结束已确认、统计拉取失败时，重试只拉取数据，不重复发送结束动作。
- 结束前核对平台题目/签到ID，避免结束其他活动。
- 当前统计与上次分析不同步时标注“上次分析”；分析不改变客观计数。
- 场次变化后丢弃旧请求的返回值。结束上课本身不会擅自撤下平台互动，历史记录显示未确认状态。
- 分析失败仍保存统计，并提供本场重试分析入口。

## 验证

离线Swift测试覆盖实时更新同一记录、手动结束、最终分析、失败重试、签到名单、跨场次迟到响应和公告替换。官方SDK桥接测试确认答题请求未携带duration和autoSendResult。没有启动软件或向真实频道发送互动，实际显示效果和平台实时数据延迟仍需实播验收。

官方SDK参考：
- https://help.polyv.net/live/js/new_sdk/interactions_launch_sdk/sdk/answer_card/
- https://help.polyv.net/live/js/new_sdk/interactions_launch_sdk/sdk/docs/interfaces/interfaces_apps_answer_card.questionsetting.html
- 已打包 @polyv/interactions-launch-sdk 0.7.0 的CheckIn.getCheckInDetail / getCheckInNum及AnswerCard.getQuestionStatistics类型声明。
