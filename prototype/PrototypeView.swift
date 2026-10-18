import SwiftUI
import AppKit

extension Notification.Name {
    static let maieFocusDiscussion = Notification.Name("maie.prototype.focusDiscussion")
}

private struct ConversationScrollState: Equatable {
    let requestID: UUID
    let messageCount: Int
    let proposal: String?
    let isThinking: Bool
    let isExpanded: Bool
    let isWaiting: Bool
    let revealID: UUID
}

private struct ConversationEnd: NSViewRepresentable {
    let state: ConversationScrollState

    final class EndView: NSView {
        var scrollState: ConversationScrollState?
        var scrollToQuestion = false
        var animateScroll = false
        private var needsScroll = false
        private var scrollScheduled = false

        func requestScroll() {
            needsScroll = true
            scheduleScroll()
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil { scheduleScroll() }
        }
        override func layout() {
            super.layout()
            scheduleScroll()
        }
        private func scheduleScroll() {
            guard needsScroll, !scrollScheduled, window != nil else { return }
            scrollScheduled = true
            // Let SwiftUI install the new content before scrolling its native container.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.scrollScheduled = false
                guard self.needsScroll, let scroll = self.enclosingScrollView,
                      let document = scroll.documentView else { return }
                self.needsScroll = false
                scroll.layoutSubtreeIfNeeded()
                document.layoutSubtreeIfNeeded()
                let clip = scroll.contentView
                let start = document.isFlipped ? document.bounds.minY
                    : max(document.bounds.minY, document.bounds.maxY - clip.bounds.height)
                let end = document.isFlipped ? max(document.bounds.minY, document.bounds.maxY - clip.bounds.height)
                    : document.bounds.minY
                let point = NSPoint(x: clip.bounds.minX, y: self.scrollToQuestion ? start : end)
                if self.animateScroll && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = 0.18
                        clip.animator().setBoundsOrigin(point)
                    }
                } else { clip.scroll(to: point) }
                scroll.reflectScrolledClipView(clip)
            }
        }
    }
    func makeNSView(context: Context) -> EndView { EndView() }
    func updateNSView(_ view: EndView, context: Context) {
        guard view.scrollState != state else { return }
        let previous = view.scrollState
        view.scrollToQuestion = previous.map { $0.requestID != state.requestID || $0.revealID != state.revealID } ?? state.isWaiting
        view.animateScroll = previous != nil && view.scrollToQuestion
        view.scrollState = state
        view.requestScroll()
    }
}

final class PrototypePresentation: ObservableObject {
    @Published var showsSessions = false
    @Published var showsConnection = false
    @Published var showsContext = false
    @Published var showsDetails = false
    @Published var showsPreview = false
    @Published var showsFullPayload = false
    @Published var confirmsDelete = false
    @Published var deletionTargetID: String?
    @Published var deletionTargetLabel = ""
    @Published var discussionOpen = true
}

struct PrototypeView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var connection: OpenAIConnection
    let resize: (Bool) -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var presentation = PrototypePresentation()
    @FocusState private var focus: Input?
    private enum Input { case draft, discussion }
    private var ink: Color { Color(nsColor: .labelColor) }
    private var muted: Color { Color(nsColor: .secondaryLabelColor) }
    private var accent: Color {
        scheme == .dark ? Color(red: 0.66, green: 0.78, blue: 0.69) : Color(red: 0.28, green: 0.39, blue: 0.32)
    }
    private var paper: Color {
        scheme == .dark ? Color(red: 0.12, green: 0.13, blue: 0.125) : Color(red: 0.975, green: 0.969, blue: 0.95)
    }
    private var line: Color { ink.opacity(0.09) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(line).frame(height: 1)
            if let notice = store.questionNotice {
                HStack(spacing: 8) {
                    Circle().fill(accent).frame(width: 5, height: 5)
                    Text(notice.count == 1 ? "New question" : "New questions").fontWeight(.medium)
                    Text(notice.title).foregroundStyle(muted).lineLimit(1)
                    Spacer(minLength: 4)
                    Button("Show") { store.showNewQuestions() }.foregroundStyle(accent)
                    Button { store.dismissQuestionNotice() } label: { Image(systemName: "xmark") }
                        .help("Dismiss notice")
                }.font(.system(size: 11)).buttonStyle(.plain)
                    .padding(.horizontal, 22).padding(.vertical, 10).background(accent.opacity(0.07))
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if let request = store.activeRequest, let session = store.activeSession {
                requestHeader(request, session: session)
                if store.reviewingGroupID == request.bridgeID && store.activeGroup.count > 1 {
                    answerReview(request)
                } else { workingContent(request, session: session) }
            } else {
                Spacer()
                VStack(alignment: .leading, spacing: 14) {
                    Text("Room to think.").font(.system(size: 28, design: .serif))
                    Text("Claude’s next question will appear here.")
                        .font(.system(size: 13)).foregroundStyle(muted)
                    Button("Connection") { presentation.showsConnection = true }
                        .buttonStyle(.bordered)
                    if !store.sessions.isEmpty {
                        Button("Sessions") { presentation.showsSessions = true }
                            .popover(isPresented: $presentation.showsSessions) { sessionsPopover }
                    }
                }.padding(26)
                Spacer()
            }
            if !store.error.isEmpty {
                HStack(alignment: .top) {
                    Text(store.error).font(.system(size: 11)).textSelection(.enabled)
                    Spacer()
                    Button { store.error = "" } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                }.padding(12).background(Color.orange.opacity(0.08))
            }
            HStack(spacing: 6) {
                Text(connection.isConnected ? connection.billing : "Not connected")
                if connection.isConnected {
                    Text("·")
                    Link("Manage usage", destination: URL(string: "https://chatgpt.com/settings/usage")!)
                }
            }.font(.system(size: 10)).foregroundStyle(muted).padding(.vertical, 12)
        }
        .foregroundStyle(ink).background(paper).tint(accent)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: store.questionNotice?.id)
        .task(id: store.questionNotice?.id) {
            guard let notice = store.questionNotice, notice.id == store.activeRequest?.bridgeID else { return }
            do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { return }
            if store.questionNotice?.id == notice.id { store.dismissQuestionNotice() }
        }
        .onAppear { if !connection.isConnected { presentation.showsConnection = true } }
        .onReceive(NotificationCenter.default.publisher(for: .maieFocusDiscussion)) { _ in
            presentation.discussionOpen = true; focus = .discussion
        }
        .onChange(of: store.activeRequestID) { _ in focus = nil }
        .onChange(of: focus) { store.editorFocused = $0 != nil }
        .onDisappear { store.editorFocused = false }
        .onChange(of: connection.selectedModel) { _ in store.preview = nil }
        .onChange(of: connection.selectedEffort) { _ in store.preview = nil }
        .onChange(of: connection.authorizationRevision) { _ in store.preview = nil }
        .onChange(of: connection.billing) { _ in store.preview = nil }
        .onChange(of: store.preview?.text) { value in
            presentation.showsFullPayload = false
            presentation.showsPreview = value != nil
        }
        .onChange(of: presentation.showsPreview) { value in if !value { store.preview = nil } }
        .popover(isPresented: $presentation.showsPreview, arrowEdge: .trailing) { payloadPreview }
        .alert("Delete this session?", isPresented: $presentation.confirmsDelete) {
            Button("Delete session", role: .destructive) {
                if let target = presentation.deletionTargetID { store.deleteSession(target) }
                presentation.deletionTargetID = nil
            }
            Button("Keep session", role: .cancel) { presentation.deletionTargetID = nil }
        } message: { Text("Deletes \(presentation.deletionTargetLabel)’s Maie history and drafts, and cancels its pending questions. Claude’s history is kept.") }
    }

    private var header: some View {
        HStack(spacing: 9) {
            MaieMark().stroke(accent, style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                .frame(width: 22, height: 27).accessibilityHidden(true)
            Text("maie").font(.system(size: 25, design: .serif)).tracking(-0.9)
            WindowDragRegion().frame(maxWidth: .infinity).frame(height: 38)
                .help("Drag this window next to your chat")
            Button { presentation.showsConnection.toggle() } label: {
                Image(systemName: connection.verified ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
                    .font(.system(size: 15)).frame(width: 28, height: 28)
            }.buttonStyle(.plain).help("Connection and billing")
                .popover(isPresented: $presentation.showsConnection, arrowEdge: .bottom) {
                    ConnectionView(connection: connection).disabled(!store.busySessionIDs.isEmpty)
                }
        }.padding(.leading, 20).padding(.trailing, 12).padding(.vertical, 9)
    }

    private func requestHeader(_ request: SavedRequest, session: SavedSession) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(sessionLabel(session)).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Text(request.question).font(.system(size: 10)).foregroundStyle(muted).lineLimit(1)
                }
                Spacer()
                Button { presentation.showsSessions.toggle() } label: {
                    HStack(spacing: 5) {
                        let waiting = Set(store.sessions.flatMap(\.requests).filter { $0.status == .waiting && $0.bridgeID != request.bridgeID }.map(\.bridgeID)).count
                        if waiting > 0 { Circle().fill(accent).frame(width: 5, height: 5); Text("+\(waiting)") }
                        Text("Sessions"); Image(systemName: "chevron.down").font(.system(size: 8))
                    }.font(.system(size: 11))
                }.buttonStyle(.plain)
                    .popover(isPresented: $presentation.showsSessions) { sessionsPopover }
            }
            if let index = request.questionIndex, let count = request.questionCount {
                Text("Question \(index + 1) of \(count)")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(accent)
            }
            HStack {
                Text(statusText(request.status)).font(.system(size: 11)).foregroundStyle(muted)
                Button("Details") { presentation.showsDetails.toggle() }
                    .font(.system(size: 10)).buttonStyle(.plain).foregroundStyle(muted)
                    .popover(isPresented: $presentation.showsDetails) { requestDetails(request, session: session) }
                Spacer()
                if request.status == .waiting {
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        let remaining = max(0, Int(request.expiresAt.timeIntervalSince(timeline.date)))
                        Text("\(remaining / 60):\(String(format: "%02d", remaining % 60)) left")
                            .font(.system(size: 10).monospacedDigit()).foregroundStyle(muted)
                    }
                }
            }
        }.padding(.horizontal, 22).padding(.top, 15).padding(.bottom, 12)
    }

    private func sessionLabel(_ session: SavedSession) -> String {
        let matching = store.sessions.filter { $0.title == session.title }
        guard matching.count > 1, let index = matching.firstIndex(where: { $0.id == session.id }) else { return session.title }
        return "\(session.title) · Session \(index + 1)"
    }

    private func requestDetails(_ request: SavedRequest, session: SavedSession) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Details").font(.system(size: 19, design: .serif))
                Text("Project").font(.system(size: 11, weight: .medium))
                Text(request.cwd).textSelection(.enabled)
                Text("Session ID").font(.system(size: 11, weight: .medium))
                Text(session.id).textSelection(.enabled)
                Text("Request ID").font(.system(size: 11, weight: .medium))
                Text(request.toolUseID).textSelection(.enabled)
                Text("Received \(request.created.formatted())")
                Text("Deadline \(request.expiresAt.formatted())")
                Text("Discussions stay separate for each Claude session. Automatic child-session grouping is not available.")
                    .foregroundStyle(muted)
            }.font(.system(size: 12)).padding(20)
        }.frame(width: 350, height: 360)
    }

    private func workingContent(_ request: SavedRequest, session: SavedSession) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(request.question).font(.system(size: 23, design: .serif)).lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(request.allowsMultiple ? "Choose one or more, or write your own answer." : "Choose an option or write your own answer.")
                                .font(.system(size: 11)).foregroundStyle(muted)
                            ForEach(request.options) { option in
                                Button { store.choose(option) } label: {
                                    HStack(alignment: .top, spacing: 9) {
                                        let selected = request.selectedOptions?.contains(option.title) == true
                                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 13)).foregroundStyle(selected ? accent : muted)
                                            .padding(.top, 1)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(option.title).font(.system(size: 12, weight: .medium))
                                            Text(option.detail).font(.system(size: 11)).foregroundStyle(muted)
                                        }.frame(maxWidth: .infinity, alignment: .leading)
                                    }.padding(10)
                                        .background(ink.opacity(0.025), in: RoundedRectangle(cornerRadius: 11))
                                        .overlay(RoundedRectangle(cornerRadius: 11).stroke(line, lineWidth: 1))
                                }.buttonStyle(.plain).disabled(request.status == .sending || request.status == .submitted)
                                    .help("Use this option as an editable draft")
                            }
                        }
                        contextControls(session)
                        if presentation.discussionOpen { discussion(session, request: request) }
                        if let proposal = request.proposal {
                            VStack(alignment: .leading, spacing: 10) {
                            Text("Proposed answer").font(.system(size: 11, weight: .medium))
                                Text(proposal).font(.system(size: 13)).textSelection(.enabled)
                                HStack {
                                    Button("Use in draft") { store.acceptProposal() }
                                        .disabled(request.status == .submitted || request.status == .sending)
                                    Button("Dismiss") { store.discardProposal() }
                                }.font(.system(size: 11))
                            }.padding(12).background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                                .id("proposal-\(request.id)")
                        }
                        ConversationEnd(state: ConversationScrollState(requestID: request.id,
                            messageCount: store.discussionMessages(for: request).count, proposal: request.proposal,
                            isThinking: store.isThinking(request.id),
                            isExpanded: presentation.discussionOpen, isWaiting: request.status == .waiting,
                            revealID: store.questionRevealID))
                            .frame(height: 1).accessibilityHidden(true)
                    }.padding(.horizontal, 22).padding(.bottom, 16)
            }
            if presentation.discussionOpen { composer(request, session: session) }
            draftEditor(request, session: session)
            HStack(spacing: 10) {
                Button {
                    presentation.discussionOpen.toggle(); resize(presentation.discussionOpen)
                } label: {
                    Label(presentation.discussionOpen ? "Collapse" : "Discuss ⌘J", systemImage: "bubble.left")
                        .font(.system(size: 12)).foregroundStyle(muted)
                }.buttonStyle(.plain)
                Spacer()
                if store.activeGroup.count > 1 {
                    Button("Previous") { store.moveQuestion(-1) }
                        .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(muted)
                        .disabled(request.questionIndex == 0)
                    let last = request.questionIndex == store.activeGroup.count - 1
                    primaryAction(last ? "Review answers" : "Next", enabled: !last || store.canReviewAnswers) {
                        if last { store.beginAnswerReview() } else { store.moveQuestion(1) }
                    }
                } else {
                    primaryAction("Send to Claude", enabled: store.canSubmit) { store.submit() }
                        .help("Send this draft to Claude")
                }
                // No Return/default shortcut can submit the final answer.
            }.padding(.horizontal, 22).padding(.top, 12)
        }
    }

    private func primaryAction(_ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(enabled ? paper : muted)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(enabled ? accent : ink.opacity(0.055), in: RoundedRectangle(cornerRadius: 11))
        }.buttonStyle(.plain).disabled(!enabled)
    }

    private func answerReview(_ request: SavedRequest) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Your answers").font(.system(size: 23, design: .serif))
                    Text("Review all answers before sending them together.")
                        .font(.system(size: 12)).foregroundStyle(muted)
                    ForEach(store.activeGroup) { saved in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top) {
                                Text(saved.question).font(.system(size: 13, weight: .medium))
                                Spacer()
                                Button("Edit") { store.selectRequest(saved.id) }
                                    .font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(accent)
                            }
                            Text(saved.draft).font(.system(size: 13)).lineSpacing(3).textSelection(.enabled)
                            Rectangle().fill(line).frame(height: 1).padding(.top, 8)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(22)
            }
            HStack {
                Button("Back") { store.endAnswerReview() }.buttonStyle(.plain)
                Spacer()
                primaryAction("Send to Claude", enabled: store.canSubmit) { store.submit() }
            }.font(.system(size: 12)).padding(.horizontal, 22).padding(.top, 12)
        }
    }

    private func contextControls(_ session: SavedSession) -> some View {
        HStack {
            Toggle("Include Claude history", isOn: Binding(get: { session.contextEnabled }, set: store.enableContext))
                .toggleStyle(.switch).controlSize(.mini).font(.system(size: 11))
                .help("Add a limited excerpt from this Claude session to your next request")
            Spacer()
            Button("View") { presentation.showsContext = true }.font(.system(size: 10)).buttonStyle(.plain)
                .popover(isPresented: $presentation.showsContext) { contextPopover }
        }
    }
    private var contextPopover: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Claude history").font(.system(size: 19, design: .serif))
                Text("A limited excerpt from this session. Project files are not included. Review everything before sending.")
                if let context = store.activeRequest?.context, store.activeSession?.contextEnabled == true {
                    Text(context.source).font(.system(size: 10)).textSelection(.enabled)
                    Text("Captured \(context.captured.formatted())").font(.system(size: 10))
                    if let modified = context.modified { Text("Transcript modified \(modified.formatted())").font(.system(size: 10)) }
                    Text(context.note)
                    Text(context.text.isEmpty ? "No extra context included." : context.text).textSelection(.enabled)
                    Button("Refresh") { store.refreshContext() }
                } else { Text("Claude history is off. The current question and Maie discussion are still included.") }
            }.font(.system(size: 12)).padding(20)
        }.frame(width: 380, height: 430)
    }

    private func discussion(_ session: SavedSession, request: SavedRequest) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Rectangle().fill(line).frame(height: 1)
            Text("Discuss").font(.system(size: 11, weight: .medium)).foregroundStyle(muted)
            if store.discussionMessages(for: request).isEmpty {
                Text("What would you like to understand?").font(.system(size: 15, design: .serif))
                Button("Explain these options") { store.requestModel(.discuss, starter: "I do not understand these options. Please explain them simply.") }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(accent)
            }
            ForEach(store.discussionMessages(for: request)) { message in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(message.role == "user" ? "You" : "maie")
                        if message.requestID != store.activeRequestID,
                           let index = session.discussionMessages.firstIndex(where: { $0.id == message.id }),
                           index == 0 || session.discussionMessages[index - 1].requestID != message.requestID {
                            Text("· earlier question")
                        }
                    }.font(.system(size: 10, weight: .medium)).foregroundStyle(message.role == "user" ? muted : accent)
                    Text(message.role == "user" ? AttributedString(message.text) : DiscussionGuidance.displayText(message.text)).font(.system(size: 13)).lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }.frame(maxWidth: .infinity, alignment: .leading)
                    .padding(message.role == "user" ? 12 : 0)
                    .background(message.role == "user" ? ink.opacity(0.035) : .clear, in: RoundedRectangle(cornerRadius: 12))
                    .id(message.id)
            }
            if store.busySessionIDs.contains(session.id) {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(store.isThinking(request.id) ? "Thinking…" : "Replying to another question…").font(.system(size: 11))
                    Button("Stop") { store.stopResponse() }
                }
            }
        }
    }
    private var modelMenu: some View {
        Menu {
            Picker("Model", selection: $connection.selectedModel) {
                ForEach(connection.models) { Text($0.name).tag($0.id) }
            }
            Picker("Thinking time", selection: Binding(get: { connection.selectedEffort }, set: connection.selectEffort)) {
                ForEach(connection.effortChoices, id: \.self) { Text($0.label).tag($0) }
            }
        } label: {
            Text("\(connection.currentModel?.name ?? "Choose model") · \(connection.selectedEffort.label)")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(muted)
                .lineLimit(1).truncationMode(.middle)
        }
        .menuStyle(.borderlessButton).fixedSize(horizontal: false, vertical: true)
        .font(.system(size: 11)).foregroundStyle(muted)
        .frame(maxWidth: 280, alignment: .leading)
        .disabled(connection.models.isEmpty || connection.busy || !store.busySessionIDs.isEmpty)
        .help("Choose a model and thinking time")
        .accessibilityLabel("Model and thinking time")
    }

    private func composer(_ request: SavedRequest, session: SavedSession) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                modelMenu
                Spacer()
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Ask Maie…", text: Binding(get: { store.activeRequest?.composer ?? "" }, set: store.setComposer), axis: .vertical)
                    .textFieldStyle(.plain).font(.system(size: 13)).lineLimit(1...3).focused($focus, equals: .discussion)
                    .onSubmit { store.requestModel(.discuss) }
                Button { store.requestModel(.discuss) } label: {
                    Image(systemName: "arrow.up").font(.system(size: 12, weight: .medium)).frame(width: 26, height: 26)
                        .background(accent.opacity(0.1), in: Circle())
                }.buttonStyle(.plain)
                    .disabled(request.composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.busySessionIDs.contains(session.id))
                    .help("Send message")
            }.padding(11).background(ink.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(line, lineWidth: 1))
        }.padding(.horizontal, 22).padding(.top, 10).padding(.bottom, 12)
            .background(paper)
            .overlay(alignment: .top) { Rectangle().fill(line).frame(height: 1) }
    }
    private func draftEditor(_ request: SavedRequest, session: SavedSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Your answer").font(.system(size: 11, weight: .medium))
                Spacer()
                Button("Suggest answer") { store.requestModel(.suggest) }
                    .disabled((request.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && store.discussionMessages(for: request).isEmpty) || connection.busy || store.busySessionIDs.contains(session.id))
            }.font(.system(size: 10)).buttonStyle(.plain)
            TextEditor(text: Binding(get: { store.activeRequest?.draft ?? "" }, set: store.setDraft))
                .font(.system(size: 13)).lineSpacing(3).scrollContentBackground(.hidden).focused($focus, equals: .draft)
                .accessibilityLabel("Editable draft final answer to Claude")
                .padding(7).frame(height: 88)
                .background(ink.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(line, lineWidth: 1))
                .disabled(request.status == .submitted || request.status == .sending)
            if request.status == .inactive || request.status == .cancelled {
                Text("Draft saved · this question is no longer active")
                    .font(.system(size: 10)).foregroundStyle(muted)
            } else if request.draft.utf8.count > 8_192 {
                Text("Draft is too long to send (8 KiB limit).").font(.system(size: 10)).foregroundStyle(.orange)
            }
        }.padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 10)
            .background(accent.opacity(0.025))
            .overlay(alignment: .top) { Rectangle().fill(line).frame(height: 1) }
    }
    private var sessionsPopover: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Sessions").font(.system(size: 18, design: .serif))
                ForEach(store.sessions) { session in
                    VStack(alignment: .leading, spacing: 7) {
                        Button { store.selectSession(session.id); presentation.showsSessions = false } label: {
                            HStack(alignment: .top) {
                                Text(sessionLabel(session)).frame(maxWidth: .infinity, alignment: .leading)
                                if session.id == store.activeSessionID {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(accent)
                                }
                            }
                        }
                            .buttonStyle(.plain).font(.system(size: 12, weight: .medium))
                        ForEach(session.requests) { request in
                            Button {
                                store.selectSession(session.id); store.selectRequest(request.id); presentation.showsSessions = false
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(request.questionCount.map { "Question \((request.questionIndex ?? 0) + 1) of \($0) · \(request.question)" } ?? request.question).lineLimit(2)
                                    Text("\(request.created.formatted(date: .abbreviated, time: .shortened)) · \(statusText(request.status))").foregroundStyle(.secondary)
                                }.font(.system(size: 11)).padding(6)
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(session.id == store.activeSessionID ? accent.opacity(0.12) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(session.id == store.activeSessionID ? accent.opacity(0.4) : .clear))
                }
                Divider()
                Text("Cancelled and completed questions stay in history.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Button("Cancel current question") { store.cancel(); presentation.showsSessions = false }
                    .disabled(store.activeRequest?.status != .waiting)
                Button("Delete this session…", role: .destructive) {
                    guard let session = store.activeSession else { return }
                    presentation.deletionTargetID = session.id
                    presentation.deletionTargetLabel = sessionLabel(session)
                    presentation.showsSessions = false; presentation.confirmsDelete = true
                }
                .disabled(store.activeSession == nil)
            }.padding(18)
        }.frame(width: 360, height: 450)
    }
    private var payloadPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let preview = store.preview {
                Text(preview.action.title).font(.system(size: 22, design: .serif))
                Text("\(connection.models.first { $0.id == preview.model }?.name ?? preview.model) · \(preview.effort.label)")
                    .font(.system(size: 12, weight: .medium))
                Text(preview.billing).font(.system(size: 11)).foregroundStyle(.secondary)
                if store.previewNeedsConfirmation {
                    Text("Following requests send directly in this session.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                if preview.action != .discuss {
                    Text("Apply changes with Use in draft.").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if preview.action == .discuss {
                            Text("Your question").font(.system(size: 11, weight: .medium))
                            Text(preview.composer).font(.system(size: 13)).textSelection(.enabled)
                        } else {
                            Text("Suggest an answer from your discussion and draft.")
                                .font(.system(size: 13))
                            if !preview.draft.isEmpty {
                                Text("Your draft").font(.system(size: 11, weight: .medium))
                                Text(preview.draft).font(.system(size: 13)).textSelection(.enabled)
                            }
                        }
                        Text("Includes this question, draft, recent discussion and prior answers. \(preview.contextDescription)")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        DisclosureGroup("View everything sent to OpenAI", isExpanded: $presentation.showsFullPayload) {
                            Text(preview.text).font(.system(size: 11)).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10)
                        }.font(.system(size: 11))
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    Button("Back") { store.preview = nil; presentation.showsPreview = false }
                    Spacer()
                    Button(preview.action.confirmation) { store.sendPreview(); presentation.showsPreview = false }
                        .help("Uses the displayed OpenAI connection. Nothing is sent to Claude.")
                        .buttonStyle(.borderedProminent).disabled(connection.busy)
                }
            }
        }.padding(20).frame(width: 400, height: 420)
    }
    private func statusText(_ status: RequestStatus) -> String {
        switch status {
        case .waiting: return "Waiting for you"
        case .sending: return "Sending to Claude…"
        case .submitted: return "Sent to Claude"
        case .cancelled: return "Cancelled"
        case .inactive: return "Inactive"
        }
    }
}

struct MaieMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.22, y: rect.height * 0.86))
        path.addCurve(to: CGPoint(x: rect.width * 0.76, y: rect.height * 0.12),
                      control1: CGPoint(x: rect.width * 0.82, y: rect.height * 0.78),
                      control2: CGPoint(x: rect.width * 0.05, y: rect.height * 0.30))
        path.addCurve(to: CGPoint(x: rect.width * 0.22, y: rect.height * 0.86),
                      control1: CGPoint(x: rect.width * 1.04, y: rect.height * 0.50),
                      control2: CGPoint(x: rect.width * 0.65, y: rect.height * 0.92))
        return path
    }
}
struct WindowDragRegion: NSViewRepresentable {
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
        override var mouseDownCanMoveWindow: Bool { true }
    }
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) { }
}
