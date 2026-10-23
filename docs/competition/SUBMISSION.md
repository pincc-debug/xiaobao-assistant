# 参赛提交说明

- 源码快照：2026-10-23。
- 应用：小保助教 0.1.19（build 48），macOS 14+，Apple Silicon。
- 安装包：[GitHub Release](https://github.com/pincc-debug/xiaobao-assistant/releases/tag/v0.1.19)。仅提供最新 DMG。
- 签名：本机 ad-hoc 签名，未做 Developer ID 公证。
- DMG SHA-256：`e0c2e1b34739d18cec67f1e43fab3dbcac40460b2e81c0e92121c36e2a49ee02`。

## 保利威 API / SDK 使用说明

| 接入 | 用途 | 源码 |
| --- | --- | --- |
| 官方 `@polyv/interactions-launch-sdk@0.7.0` | 公告、签到、答题卡等直播互动 | `Sources/Assistant/Resources/polyv-il-0.7.0.js`、`InteractionBridge.swift`、`Resources/interaction-bridge.js`、`AssistantTools.swift` |
| 聊天室协议 / Swift Socket.IO 适配 | 接收消息、发送回复及聊天室操作 | `Sources/Assistant/Services.swift`、`AssistantTools.swift` |
| 保利威 Open API | 频道归属、题库、直播数据与开播入口 | `Sources/Assistant/PlatformAPI.swift`、`CourseDataRuntime.swift`、`BroadcastLaunch.swift` |

源码路径中省略的目录均为 `Sources/Assistant/`。完整调用链见 [技术评审索引](AI_REVIEW_GUIDE.md)。

## 本次检查

- `swift test`：269 项，12 项条件跳过，0 失败。
- `node scripts/check-interaction-sdk.cjs`：通过。
- 应用签名检查与 `hdiutil verify`：通过。
- SDK 检查采用模拟传输；本次没有执行真实直播端到端验收。

## 提交内容

包含源码、测试、构建脚本、运行资源和参赛说明。个人凭据、真实课堂数据、测试媒体、运行日志、截图录像、缓存、历史安装包均不提交。历史开发文档中引用的本地 evidence 和 test-fixtures 不随仓库分发。

可选视频回放测试通过 `XB_VIDEO_REPLAY_DIR` 指定本机素材目录；默认不运行。
