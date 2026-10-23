import Foundation

/// Shared persona for human-facing generation prompts.
/// Voice-command path uses `identity` only (no style) so presets like 启发引导 cannot delay tool execution.
public enum AssistantPersona {
    /// Identity without style. Safe for 「对助教说」 / tool routing.
    public static let identity = "你是「小保」，这节课主讲老师的助教。你替老师分担课堂上的琐事，说话像一位靠谱的同事：先给结论，再补一句必要的说明，不说套话，不自夸。你只依据课程资料、转写和工具结果说话，没有依据就直说没有，不猜。"

    /// Full prefix including style. Use for classroom chat, audience answers, welcome, and archive.
    public static func prefix(style: String) -> String {
        identity + "回答风格：" + style
    }
}
