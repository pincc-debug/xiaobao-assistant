import SwiftUI

/// Classroom priorities stay separate from the notebook and audit timeline.
struct ClassroomPanel: View {
    @ObservedObject var store: Store
    var fade: CGFloat = 16   // bottom fade into the footer lines (DetailBoard)
    private var questions: Int { store.classroomQuestionCount }
    private var feedback: Int { store.classroomFeedbackCount }
    @Environment(\.assistantPet) private var assistantPet
    enum Section: Equatable { case live, reminders, questions, feedback }
    /// Group order. Default 进行中 → 提醒 → 待答 → 反馈; while questions are waiting they need an answer now,
    /// so 待答问题 moves to the top (running cards only show status). Empty groups are dropped.
    static func sections(live: Bool, reminders: Bool, questions: Bool, feedback: Bool) -> [Section] {
        var list: [Section] = []
        if questions { list.append(.questions) }
        if live { list.append(.live) }
        if reminders { list.append(.reminders) }
        if feedback { list.append(.feedback) }
        return list
    }
    private var empty: Bool { store.pinnedInteractions.isEmpty && store.currentReminders.isEmpty && questions == 0 && feedback == 0 }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if empty {   // nothing to handle yet: centred in the area below the tab bar
                EmptyStateView(systemImage: "bubble.left.and.bubble.right", title: "课堂很安静", subtitle: "学员的提问和反馈会出现在这里",
                               avatarPet: assistantPet ?? store.saved.preferences.pet)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
            // One scrolling list for the whole tab (order: `sections`): every card shows in full,
            // and the bottom fade above the activity line / caption covers the scroll edge.
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Self.sections(live: !store.pinnedInteractions.isEmpty, reminders: !store.currentReminders.isEmpty,
                                          questions: questions > 0, feedback: feedback > 0), id: \.self) { section in
                        switch section {
                        case .live:
                            VStack(alignment: .leading, spacing: 6) {
                                heading("进行中", count: store.pinnedInteractions.count)
                                ActiveInteractions(store: store).padding(.horizontal, 18)
                            }
                        case .reminders:
                            ClassroomRemindersView(store: store)
                        case .questions:
                            VStack(alignment: .leading, spacing: 6) {
                                heading("待答问题", count: questions)
                                PendingBoard(cardRows: true, store: store, embedded: true, includedKinds: [.question, .material], showGroupTitles: false)
                            }
                        case .feedback:
                            VStack(alignment: .leading, spacing: 6) {
                                heading("课堂反馈", count: feedback)
                                PendingBoard(cardRows: true, store: store, embedded: true, includedKinds: [.technical, .risk], showGroupTitles: false)
                            }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 12)
            }.scrollIndicators(.hidden).frame(maxWidth: .infinity, maxHeight: .infinity)
            .modifier(BottomEdgeFade(height: fade))
            }
            // The latest-activity line now sits in the 工作台 footer above the transcript caption (DetailBoard).
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    /// Group title + count (11pt textHint number); groups with 0 rows are not shown at all.
    private func heading(_ title: String, count: Int, quiet: Bool = false) -> some View {
        HStack(spacing: 4) {
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(Ink.group)
            if count > 0 { Text("\(count)").font(.system(size: 11).monospacedDigit()).foregroundStyle(AppTheme.textHint) }
        }.padding(.horizontal, 18)
    }
}
