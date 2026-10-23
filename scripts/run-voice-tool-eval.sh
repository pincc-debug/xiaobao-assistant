#!/bin/zsh
# Live 「对助教说」 tool-choice eval. Uses app state + credentials; never prints secrets.
set -euo pipefail
cd "${0:A:h}/.."
export XB_VOICE_TOOL_EVAL=1
export XB_VOICE_TOOL_EVAL_REPORT="${XB_VOICE_TOOL_EVAL_REPORT:-$HOME/br-tmp/duizhujiao-eval-report-4981e33.md}"
mkdir -p "$(dirname "$XB_VOICE_TOOL_EVAL_REPORT")"
# Long-running live calls; keep XCTest process alive.
swift test --filter VoiceToolChoiceEval.testLiveVoiceToolChoiceEval 2>&1
echo "Report: $XB_VOICE_TOOL_EVAL_REPORT"
