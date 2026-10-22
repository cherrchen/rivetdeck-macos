import SwiftUI
import AppKit

struct RuntimeSettings: View {
    @Bindable var model: AppModel
    @State private var apiKey = ""
    @State private var credentialStatus = ""
    var body: some View {
        Form {
            Section("Official DSH Runtime") {
                pathField("Node executable", text: $model.nodePath, directory: false)
                pathField("Runtime directory", text: $model.runtimePath, directory: true)
                pathField("DSH home", text: $model.homePath, directory: true)
                Text("Install dependencies before connecting: npm ci --prefix runtime. Node.js 24 is recommended. No package manager runs at app launch.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Model route · applies after reconnect") {
                TextField("Provider", text: $model.provider)
                TextField("Model", text: $model.model)
                SecureField("DeepSeek API Key", text: $apiKey)
                HStack {
                    Button("Save to Keychain") { credentialOperation { try CredentialStore.save(apiKey); apiKey = "" }; }
                        .disabled(apiKey.isEmpty)
                    Button("Remove saved key") { credentialOperation { try CredentialStore.delete() } }
                }
                if !credentialStatus.isEmpty { Text(credentialStatus).font(.caption) }
                Text("The SDK Profile owns models, tools, sandbox policy and persistence. Other provider routes must be configured in DSH itself.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Prototype capabilities") {
                Text("Direct SDK stdio · full sdk Profile · independent DSH home")
                Text("No session catalog, historical message replay, token deltas, single-session cancellation or approval responses. Approval requests without an answerer fail closed. Disconnect stops the entire runtime.")
                    .foregroundStyle(.secondary)
                Text("Changing workspace requires disconnecting. Recent workspace paths and connection preferences are saved locally; conversation history remains owned by DSH.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped).padding(12).frame(width: 680, height: 640)
    }
    private func credentialOperation(_ operation: () throws -> Void) {
        do { try operation(); credentialStatus = "Keychain updated." }
        catch { credentialStatus = "Keychain could not be updated (\((error as NSError).code))." }
    }
    private func pathField(_ title: String, text: Binding<String>, directory: Bool) -> some View {
        HStack {
            TextField(title, text: text)
            Button("Choose…") {
                let panel = NSOpenPanel(); panel.canChooseDirectories = directory; panel.canChooseFiles = !directory
                if panel.runModal() == .OK, let url = panel.url { text.wrappedValue = url.path }
            }
        }
    }
}
