import SwiftUI

/// Edits the complete document used by email and background Review.
struct ReviewPolicyView: View {
    @Bindable var model: DashboardModel
    private let registration: String
    private let storage: ObjectIdentifier?
    @Environment(\.dismiss) private var dismiss
    @State private var expected: ReviewPolicyCapture
    @State private var text: String
    @State private var selectedVersion: ReviewPolicyVersion?
    @State private var resetting = false
    @State private var showFeedback = false
    @State private var error: String?
    init(model: DashboardModel) {
        self.model = model
        registration = model.chatGPT.activeID
        storage = model.container.map(ObjectIdentifier.init)
        let capture = model.emailSummaries.policy(model.chatGPT.activeID)
        _expected = State(initialValue: capture); _text = State(initialValue: capture.text)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Review guidance").font(.title2.weight(.semibold))
                Spacer()
                Button("Cancel") {dismiss()}.keyboardShortcut(.cancelAction)
                Button("Save") {save()}.keyboardShortcut(.defaultAction)
                    .disabled(!ReviewPolicyRules.validText(text) || !model.emailSummaries.reviewPolicies.writable || registration.isEmpty)
            }
            Text("This complete guide is supplied whenever 3PO assesses information for Review. Heartbeats merge new learned guidance into it. Edit it here to correct what matters to you.").font(.callout).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Your Review guidance").font(.headline)
                    TextEditor(text: $text).font(.body).frame(height: 300).padding(6).border(Color.secondary.opacity(0.25)).accessibilityLabel("Review guidance text")
                    HStack {
                        Text("Plain text or Markdown · \(text.count)/\(ReviewPolicyRules.textLimit)").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Use default") {text = ReviewPolicyRules.defaultText; selectedVersion = nil; resetting = true}
                    }.controlSize(.small)
                    DisclosureGroup("Policy history") {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(model.emailSummaries.policyHistory(registration)) {version in
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Text(version.created.formatted(date: .abbreviated, time: .shortened)).font(.caption.weight(.semibold))
                                        Text(version.consolidatedFrom == nil ? "Edited by you" : "Consolidated by 3PO").font(.caption).foregroundStyle(.secondary)
                                        if version.id.uuidString == expected.revision {Text("Current").font(.caption).foregroundStyle(.secondary)}
                                        Spacer()
                                        Button("Use this version") {text = version.text; resetting = false; selectedVersion = version}.controlSize(.small)
                                    }
                                    Text(version.text).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                }.padding(10).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                            }
                            if model.emailSummaries.policyHistory(registration).isEmpty {Text("Your first saved edit will appear here. Restoring creates a new version.").font(.caption).foregroundStyle(.secondary)}
                        }.padding(.top, 6)
                    }
                    Divider()
                    Button("Original feedback and history…") {showFeedback = true}.controlSize(.small)
                    Text("Your original words remain available for inspection. Review decisions receive the guidance above. Source access and approval of actions remain separate.").font(.caption).foregroundStyle(.secondary)
                    if !model.assistant.memory.enabled {Text("Memory use is paused. Saved learned guidance becomes available when memory use resumes.").font(.caption).foregroundStyle(.secondary)}
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if let error = error ?? model.emailSummaries.reviewPolicies.error {Text(error).font(.caption).foregroundStyle(.orange)}
        }.padding(24).frame(width: 680, height: 660)
        .sheet(isPresented: $showFeedback) {ReviewRelevancePreferencesView(model: model)}
        .onChange(of: model.chatGPT.activeID) {dismiss()}
    }
    private func save() {
        guard registration == model.chatGPT.activeID, storage == model.container.map(ObjectIdentifier.init) else {error = "The account changed. Reopen Review guidance before saving."; return}
        let saved: Bool
        if resetting && text == ReviewPolicyRules.defaultText {saved = model.emailSummaries.resetPolicy(registration: registration, expected: expected)}
        else if let selectedVersion, text == selectedVersion.text {saved = model.emailSummaries.restorePolicy(selectedVersion, expected: expected)}
        else {saved = model.emailSummaries.savePolicy(text, registration: registration, expected: expected)}
        guard saved else {error = model.emailSummaries.reviewPolicies.error; return}
        expected = model.emailSummaries.policy(registration); dismiss()
    }
}
