import SwiftUI

final class ConnectionPresentation: ObservableObject {
    @Published var apiKey = ""
    @Published var showsAPI = false
    @Published var showsCheck = false
    @Published var showsAccounts = false
}

struct ConnectionView: View {
    @ObservedObject var connection: OpenAIConnection
    @StateObject private var presentation = ConnectionPresentation()
    private var usingAPI: Bool { connection.billing == "OpenAI API · separate billing" }
    private var statusMessage: String {
        switch connection.status {
        case "Connect your ChatGPT account. No API key required.", "Connected to ChatGPT.",
             "Using ChatGPT plan. Check models and verify a response.", "Models updated.": return ""
        case "Signed out. Registration retained for a later sign-in.": return "Signed out."
        default: return connection.status
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Connection").font(.system(size: 25, design: .serif))
                VStack(alignment: .leading, spacing: 10) {
                    sectionLabel("Account")
                    if connection.isConnected {
                        if usingAPI {
                            Text("Using an API key").font(.system(size: 13, weight: .medium))
                            Text("Separate API charges apply.").foregroundStyle(.secondary)
                        } else {
                            Text(connection.accountDescription).font(.system(size: 13, weight: .medium))
                                .textSelection(.enabled)
                            Text("Using your ChatGPT plan.").foregroundStyle(.secondary)
                        }
                        HStack {
                            Link("Manage usage", destination: URL(string: "https://chatgpt.com/settings/usage")!)
                            Spacer()
                            Button("Sign out") { Task { await connection.signOut() } }.disabled(connection.busy)
                        }
                    } else {
                        Text("Connect your ChatGPT account to discuss questions with Maie.")
                            .foregroundStyle(.secondary)
                        if !connection.accounts.isEmpty { accountPicker }
                        Button("Continue with ChatGPT") { Task { await connection.signIn() } }
                            .buttonStyle(.borderedProminent).disabled(connection.busy)
                    }
                    if connection.isConnected {
                        DisclosureGroup("Other accounts", isExpanded: $presentation.showsAccounts) {
                            VStack(alignment: .leading, spacing: 10) {
                                if !connection.accounts.isEmpty { accountPicker }
                                Button("Continue with ChatGPT") { Task { await connection.signIn() } }
                                    .disabled(connection.busy)
                                Button("Add account") { Task { await connection.signIn(new: true) } }
                                    .disabled(connection.busy)
                            }.padding(.top, 8)
                        }
                    }
                    if !connection.isConnected && !connection.accounts.isEmpty {
                        Button("Use another account") { Task { await connection.signIn(new: true) } }.disabled(connection.busy)
                    }
                    if connection.busy { ProgressView().controlSize(.small) }
                    if connection.signingIn { Button("Cancel sign-in") { connection.cancelSignIn() } }
                    if !statusMessage.isEmpty {
                        Text(statusMessage).font(.system(size: 11)).textSelection(.enabled)
                    }
                }
                Divider()
                if !connection.models.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        sectionLabel("Model")
                        Picker("Model", selection: $connection.selectedModel) {
                            ForEach(connection.models) { Text($0.name).tag($0.id) }
                        }.disabled(connection.busy)
                        Picker("Thinking time", selection: Binding(get: { connection.selectedEffort }, set: connection.selectEffort)) {
                            ForEach(connection.effortChoices, id: \.self) { Text($0.label).tag($0) }
                        }.disabled(connection.busy).help(connection.effortChoices == [.modelDefault]
                            ? "This model uses its default thinking time."
                            : "More thinking time may use more of your plan.")
                    }
                    Divider()
                }
                DisclosureGroup("Connection check", isExpanded: $presentation.showsCheck) {
                    VStack(alignment: .leading, spacing: 10) {
                        Button("Reload models") { Task { await connection.refreshModels() } }
                            .disabled(connection.busy || !connection.isConnected)
                        Text("Sends a short request using the account and model above: “Say exactly: Maie connection verified.”")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        Button("Check connection") { Task { await connection.verify() } }
                            .disabled(connection.busy || connection.models.isEmpty)
                    }.padding(.top, 8)
                }
                DisclosureGroup("API key (optional)", isExpanded: $presentation.showsAPI) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Uses separate API billing. Maie switches only when you choose it.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        SecureField("OpenAI API key", text: $presentation.apiKey)
                        Button("Use API key · separate billing") {
                            let key = presentation.apiKey; presentation.apiKey = ""
                            Task { await connection.useAPIKey(key) }
                        }.disabled(connection.busy || presentation.apiKey.isEmpty)
                        Button("Use ChatGPT plan") { connection.useChatGPT() }.disabled(connection.busy)
                        Button("Remove saved API key") { connection.forgetAPIKey() }.disabled(connection.busy)
                    }.padding(.top, 8)
                }
            }.font(.system(size: 12)).padding(24)
        }.frame(width: 360, height: 510)
        .alert("Connected to ChatGPT", isPresented: $connection.welcome) {
            Button("Done") { connection.dismissWelcome() }
        } message: { Text("Requests use your ChatGPT plan. Usage is shared with your other apps.") }
    }
    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
    }
    private var accountPicker: some View {
        Picker("Account", selection: $connection.selectedAccountID) {
            Text("Choose account").tag("")
            ForEach(Array(connection.accounts.enumerated()), id: \.element.id) { index, account in
                let repeated = connection.accounts.filter { $0.email == account.email }.count > 1
                Text(repeated ? "\(account.email) · Account \(index + 1)" : account.email).tag(account.id)
            }
        }.disabled(connection.busy)
    }
}
