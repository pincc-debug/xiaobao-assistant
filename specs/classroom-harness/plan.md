# Chatroom harness: first executable slice

Authorized scope: checkpoint, implement and try the first iteration discussed with the user.

Acceptance: grounded multi-step context lookup; durable issues; unique participants; partial recovery; reopen follow-ups; invalid tool calls repairable; bounded loop; old sessions decode; no live traffic in tests.

Design: automatic messages use a bounded read/decide loop when an answer provider is available. Existing classification remains the fallback without a provider and the test override. The model may read recent messages/transcript and an issue, then submit a typed routing decision. The host validates IDs, issue kinds and transitions. Reply and moderation remain existing executors, with completion receipts updating issues. Model output cannot assert that an external action succeeded.

Limits: first slice is message-driven. No automatic timer wakeups, queue prioritization, parallel classifiers or exactly-once external delivery guarantee. Restored issues appear as pending cards; uncertain delivery must not be blindly retried. Learning feedback uses the existing feedback card presentation and technical-alert capability in this iteration.

Tasks: implement state/reducer; implement read/route loop; wire receive/complete/restore; test state, tool errors and application routing; run existing suite.

## Evidence-driven revisions

Live inference exposed two failures: a normal advertising report was classified as blocked; the model repeatedly read an unchanged snapshot until the step budget expired. Added an independent risk-review tool with a host-side escalation gate, and removed already-consumed snapshot tools from the available tool list. Host validation remains active for models that call removed tools.

A later replay linked learning feedback to a question. Instead of repeatedly rejecting a reasonable topical link, the host now creates a separate feedback issue with relatedIssueID. The original question keeps its type and state. Reading the issue itself is sufficient for follow-ups/recovery; an extra context read is not forced when it adds no evidence.

No classification decision may mark an external action successful. Existing reply/moderation executors remain responsible for their own results. This iteration does not claim exactly-once platform delivery.

## Iteration result

- [x] Durable state/reducer and backward-compatible course storage
- [x] Bounded context/issue/risk tools and terminal routing
- [x] Receive, completion receipt and pending restoration integration
- [x] Offline transition and integration tests
- [x] Four synthetic scenarios against the configured real model
- [x] Full regression suite and verification report

Follow-up work remains explicitly listed in verification.md; this iteration is not a production-readiness claim.
