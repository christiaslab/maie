import SwiftUI

final class ConnectionPresentation: ObservableObject {
    @Published var apiKey = ""
    @Published var showsAPI = false
}

struct ConnectionView: View {
    @ObservedObject var connection: OpenAIConnection
    @StateObject private var presentation = ConnectionPresentation()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Connection").font(.system(size: 25, design: .serif))
                Text("Use your ChatGPT plan. Usage is shared with your other apps.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                if !connection.accounts.isEmpty {
                    Picker("Saved account", selection: $connection.selectedAccountID) {
                        Text("Choose account").tag("")
                        ForEach(connection.accounts) { Text($0.label).tag($0.id) }
                    }
                }
                Button("Continue with ChatGPT") { Task { await connection.signIn() } }
                    .buttonStyle(.borderedProminent).disabled(connection.busy)
                if !connection.accounts.isEmpty {
                    Button("Add account") { Task { await connection.signIn(new: true) } }
                        .disabled(connection.busy)
                }
                if connection.busy { ProgressView().controlSize(.small) }
                Text(connection.billing == "ChatGPT plan" ? connection.accountDescription : "Optional API key active")
                    .font(.system(size: 11)).textSelection(.enabled)
                Text(connection.billing)
                    .font(.system(size: 12, weight: .medium))
                Link("Manage usage", destination: URL(string: "https://chatgpt.com/settings/usage")!)
                if connection.isConnected {
                    Button("Refresh models") { Task { await connection.refreshModels() } }.disabled(connection.busy)
                }
                if !connection.models.isEmpty {
                    Picker("Model", selection: $connection.selectedModel) {
                        ForEach(connection.models) { Text($0.name).tag($0.id) }
                    }.disabled(connection.busy)
                    Picker("Effort", selection: Binding(get: { connection.selectedEffort }, set: connection.selectEffort)) {
                        ForEach(connection.effortChoices, id: \.self) { Text($0.label).tag($0) }
                    }.disabled(connection.busy).help(connection.effortChoices == [.modelDefault]
                        ? "Effort choices are not confirmed for this model. Its default will be used."
                        : "Higher effort gives the model more time to reason and may use more of your plan.")
                    Text("Test sends only: “Say exactly: Maie connection verified.”")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Button("Test connection") { Task { await connection.verify() } }.disabled(connection.busy)
                }
                Text(connection.status).font(.system(size: 12)).textSelection(.enabled)
                if connection.signingIn { Button("Cancel sign-in") { connection.cancelSignIn() } }
                if connection.isConnected {
                    Button("Sign out") { Task { await connection.signOut() } }.disabled(connection.busy)
                }
                Divider()
                DisclosureGroup("API key · separate billing", isExpanded: $presentation.showsAPI) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Optional, with separate API charges. Maie never switches billing automatically.")
                            .font(.system(size: 11))
                        SecureField("OpenAI API key", text: $presentation.apiKey)
                        Button("Use API key · separate billing") {
                            let key = presentation.apiKey; presentation.apiKey = ""
                            Task { await connection.useAPIKey(key) }
                        }.disabled(connection.busy || presentation.apiKey.isEmpty)
                        Button("Return to ChatGPT plan") { connection.useChatGPT() }.disabled(connection.busy)
                        Button("Remove saved API key") { connection.forgetAPIKey() }.disabled(connection.busy)
                    }.padding(.top, 10)
                }
            }.padding(22)
        }.frame(width: 380, height: 560)
        .alert("Using your ChatGPT plan", isPresented: $connection.welcome) {
            Button("Got it") { connection.dismissWelcome() }
        } message: { Text("Eligible AI requests use your ChatGPT plan. Manage usage in ChatGPT settings.") }
    }
}
