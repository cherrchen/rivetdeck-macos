import SwiftUI
import AppKit

/// Tabbed settings mirroring DSH's General/Models/inventory split, at prototype scope.
struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var apiKey = ""
    @State private var credentialStatus = ""
    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
            modelTab
                .tabItem { Label("Model", systemImage: "cpu") }
            capabilitiesTab
                .tabItem { Label("Capabilities", systemImage: "checklist") }
        }
        .padding(Tokens.Spacing.lg)
        .frame(width: 640, height: 560)
    }
    private var generalTab: some View {
        Form {
            Section("Appearance") {
                LabeledContent {
                    Picker("", selection: $model.appearance) {
                        ForEach(AppearancePreference.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 220)
                } label: {
                    fieldLabel("Theme", "System follows macOS; Light and Dark pin the app.")
                }
                LabeledContent {
                    Picker("", selection: $model.contentTextSize) {
                        ForEach(ContentTextSize.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 220)
                } label: {
                    fieldLabel("Message text size", "Applies to prompts, replies and the composer.")
                }
                LabeledContent {
                    Toggle("", isOn: $model.autoCollapseWork).labelsHidden()
                } label: {
                    fieldLabel("Collapse work details when a turn completes", "Completed turns fold their tool steps behind a disclosure row.")
                }
            }
            Section("Official DSH Runtime") {
                pathField("Node executable", text: $model.nodePath, directory: false)
                pathField("Runtime directory", text: $model.runtimePath, directory: true)
                pathField("DSH home", text: $model.homePath, directory: true)
                Text("Run npm ci --prefix runtime before connecting. Node.js 24 recommended; version-manager shims fail under Process. Nothing installs at app launch.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Workspace") {
                LabeledContent("Current", value: model.workspace.isEmpty ? "None" : model.workspace)
                Text("Changing workspace requires disconnecting — one runtime owns one workspace. Up to 12 recent paths are stored locally.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
    private var modelTab: some View {
        Form {
            Section("Model route · applies after reconnect") {
                TextField("Provider", text: $model.provider)
                TextField("Model", text: $model.model)
                Text("Defaults are deepseek-official / deepseek-flash. The model ID must be supported by your provider configuration in DSH.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Credential") {
                SecureField("DeepSeek API Key", text: $apiKey)
                HStack {
                    Button("Save to Keychain") { credentialOperation { try CredentialStore.save(apiKey); apiKey = "" } }
                        .disabled(apiKey.isEmpty)
                    Spacer()
                    Button("Remove saved key") { credentialOperation { try CredentialStore.delete() } }
                }
                if !credentialStatus.isEmpty { Text(credentialStatus).font(.caption) }
                Text("Keys live in the login Keychain and are passed only to the runtime's environment — never to preferences or diagnostics. DSH's own stored credentials still take precedence.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
    private var capabilitiesTab: some View {
        Form {
            Section("Verified surface") {
                capability("Direct SDK stdio", ok: true, detail: "NDJSON JSON-RPC to the official dsh bin, profile sdk")
                capability("Sessions & prompts", ok: true, detail: "Create, resume by ID, prompt, live status")
                capability("Working directory", ok: true, detail: "Per-session get/set inside the workspace")
                capability("Bounded shutdown", ok: true, detail: "shutdown → SIGTERM → SIGKILL")
            }
            Section("Not in the SDK — shown, never faked") {
                capability("Session catalog & history replay", ok: false, detail: "Resume restores the Agent, not old messages")
                capability("Per-session cancel & disposal", ok: false, detail: "Disconnect stops the whole runtime")
                capability("Approval replies", ok: false, detail: "workspace-write + ask; unanswered approvals fail closed")
                capability("Token deltas & plugin RPC", ok: false, detail: "Events are recorded log entries, not streams")
            }
            Section("Trust") {
                Text("The SDK Profile owns models, tools, sandbox policy and persistence. Untrusted workspaces can still affect the Host through their own DSH configuration — do not select a workspace you do not trust.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
    private func capability(_ name: String, ok: Bool, detail: String) -> some View {
        LabeledContent {
            VStack(alignment: .trailing, spacing: Tokens.Spacing.xxs) {
                Image(systemName: ok ? "checkmark.circle.fill" : "minus.circle")
                    .foregroundStyle(ok ? Tokens.Color.statusOK : .secondary)
                Text(detail).font(.caption2).foregroundStyle(.tertiary).multilineTextAlignment(.trailing)
            }
        } label: { Text(name) }
    }
    private func credentialOperation(_ operation: () throws -> Void) {
        do { try operation(); credentialStatus = "Keychain updated." }
        catch { credentialStatus = "Keychain could not be updated (\((error as NSError).code))." }
    }
    private func fieldLabel(_ title: String, _ description: String) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
            Text(title)
            Text(description).font(.caption).foregroundStyle(.secondary)
        }
    }
    private func pathField(_ title: String, text: Binding<String>, directory: Bool) -> some View {
        LabeledContent(title) {
            HStack {
                TextField(title, text: text).labelsHidden()
                Button("Choose…") {
                    let panel = NSOpenPanel(); panel.canChooseDirectories = directory; panel.canChooseFiles = !directory
                    if panel.runModal() == .OK, let url = panel.url { text.wrappedValue = url.path }
                }
            }
        }
    }
}
