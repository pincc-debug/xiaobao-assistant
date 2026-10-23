# 复现与验证说明

本页供技术评委复现，也供团队准备提交包。
项目价值见 [参赛介绍](README.md)。
代码定位见 [AI 与技术评审索引](AI_REVIEW_GUIDE.md)。

## 环境与启动

需要 macOS 14 或以上版本。
使用支持 Swift tools 5.9 的 Xcode 工具链。
完整应用打包还需要本机 FFmpeg 和 Python 3。
SDK 检查需要 Node.js 内置 FormData。
建议使用 Node.js 20 或以上版本。
首次构建需要下载 SwiftPM 依赖。

在仓库根目录运行：

```sh
swift test
node scripts/check-interaction-sdk.cjs
./scripts/build.sh
open dist/小保助教.app
```

构建脚本默认生成 Release 应用，并进行本机签名。
FFmpeg 可通过 `FFMPEG_BINARY` 指定路径。
应用为 macOS 原生项目。
UI 测试不能直接在 Linux 上运行。

## 无直播凭据时

可以检查源码、运行常规测试和 SDK 模拟传输检查。
构建后可使用独立预览模式：

```sh
open dist/小保助教.app --args --preview
```

切换模式前先退出已有实例。
预览使用临时数据和模拟待处理消息。
预览中的发送不会向真实聊天室发送。
它用于查看界面，不证明真实平台通信成功。

## 真实演示配置

在应用设置中配置保利威账号及回答模型服务。
按功能需求配置 Jev 与语音服务密钥。
准备属于该账号的测试频道，并检查相关接口权限。
语音功能还需授予系统麦克风权限。
使用观看端账号验证实际收发与互动。

凭据保存在本机 Application Support 目录。
`credentials.json` 使用 0600 文件权限。
本地存储不代表完全离线，模型功能会调用外部服务。
评审请使用合成课程资料和测试频道。

## 已有证据及其含义

| 证据 | 位置 | 可以说明什么 |
| --- | --- | --- |
| 官方 SDK 模拟传输检查 | `scripts/check-interaction-sdk.cjs` | 官方包可通过桥接发起对应调用 |
| Swift 测试源码 | `Tests/` | 状态、检索、互动和异常处理有覆盖 |
| 课堂事项验证记录 | `specs/classroom-harness/verification.md` | 记录离线回归及真实模型合成样本结果 |
| 互动说明 | `docs/live-interactions.md` | 说明统计同步与失败恢复规则 |
| 知识检索说明 | `docs/knowledge-retrieval.md` | 说明来源、降级与测试边界 |

上述路径相对仓库根目录。
已有记录不等于本次提交重新执行后的结果。
测试数量以最终提交对应的运行输出为准。
真实模型样本结果不等同于大规模准确率。

部分测试由环境变量开启，默认跳过。
例如以下命令会调用本机已配置的模型，可能产生费用：

```sh
XB_HARNESS_LIVE=1 swift test --filter ClassroomHarnessTests.testRealModelRecoveryAndFollowupWithoutChatConnection
```

该测试使用合成样本，不连接真实聊天室。
不要把模型测试、SDK 模拟测试与真实直播验收混为一项。

## 待通过真实演示补齐的证据

- 真实观众消息到达、自动回复和平台回执。
- 观看端签到、答题卡及最终统计展示。
- 真实语音输入、模型工具选择与平台执行。
- 完整课程的持续运行、回复延迟和调用成本。

本地应用已有相关实现和测试入口。
这些项目用于补充现场证据，不代表功能不存在。

## 提交包核对

- 包含源码、`Package.swift`、`Package.resolved` 与测试。
- 包含 `Sources/Assistant/Resources/` 中所需资源。
- 包含本目录文档和 `scripts/` 中的复现脚本。
- 核对当前未跟踪的新文件是否进入最终提交。
- 记录提交哈希、系统版本、命令及实际验证结果。
- 移除个人凭据、真实观众资料和不宜公开的运行日志。
- 核对第三方 SDK、依赖与素材的许可和来源说明。
- 提交二进制时说明本机签名及未公证状态。

桌宠图集由 AI 生成，来源说明见根 README。
保利威品牌人物属于本项目设计方案。
不将其表述为保利威既有官方 IP。
