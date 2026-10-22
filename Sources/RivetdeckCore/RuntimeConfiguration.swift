import Foundation

public struct RuntimeConfiguration: Sendable {
    public var node: URL
    public var runtimeRoot: URL
    public var home: URL
    public var workspace: URL
    public var provider: String
    public var model: String
    public var credential: String?
    public var baseURL: String?
    public init(node: URL, runtimeRoot: URL, home: URL, workspace: URL, provider: String = "deepseek-official", model: String = "deepseek-flash", credential: String? = nil, baseURL: String? = nil) {
        self.node = node; self.runtimeRoot = runtimeRoot; self.home = home; self.workspace = workspace
        self.provider = provider; self.model = model; self.credential = credential; self.baseURL = baseURL
    }
    public var entry: URL { runtimeRoot.appendingPathComponent("node_modules/@deepseek-ai/dsh/lib/bin.js") }
    public func validate() throws {
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: node.path) else { throw ClientError.invalidConfiguration("Select a real Node.js 24 executable, not a version-manager shim.") }
        guard fm.fileExists(atPath: entry.path) else { throw ClientError.invalidConfiguration("DSH is not installed in the selected runtime directory. Run npm ci --prefix runtime.") }
        for package in ["dsh", "dsh-sdk-protocol"] {
            let metadata = runtimeRoot.appendingPathComponent("node_modules/@deepseek-ai/\(package)/package.json")
            guard let bytes = try? Data(contentsOf: metadata),
                  let manifest = try? JSONDecoder().decode(JSONValue.self, from: bytes),
                  manifest["version"].string == "0.2.1-rc.2" else {
                throw ClientError.invalidConfiguration("Unsupported or missing \(package) package. Install the locked DSH 0.2.1-rc.2 runtime before connecting.")
            }
        }
        var directory: ObjCBool = false
        guard workspace.path.hasPrefix("/"), fm.fileExists(atPath: workspace.path, isDirectory: &directory), directory.boolValue else {
            throw ClientError.invalidConfiguration("Workspace must be an existing local directory.")
        }
        guard !provider.isEmpty, !model.isEmpty else { throw ClientError.invalidConfiguration("Provider and model are required.") }
        try fm.createDirectory(at: home, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
    public var environment: [String: String] {
        // Deliberately exclude NODE_OPTIONS, arbitrary DSH policy overrides, and ambient secrets.
        var env = ["PATH": node.deletingLastPathComponent().path + ":/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
                   "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
                   "DSH_HOME": home.path, "SHELL": "/bin/zsh", "LANG": "en_US.UTF-8"]
        if let temp = ProcessInfo.processInfo.environment["TMPDIR"] { env["TMPDIR"] = temp }
        if let credential, !credential.isEmpty { env["DEEPSEEK_API_KEY"] = credential }
        if let baseURL, !baseURL.isEmpty { env["DEEPSEEK_BASE_URL"] = baseURL }
        return env
    }
    public static var defaultHome: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Rivetdeck Native/DSH", isDirectory: true)
    }
}

public protocol DSHClient: Sendable {
    func events() async -> AsyncThrowingStream<DSHEvent, Error>
    func connect(configuration: RuntimeConfiguration) async throws
    func createSession(id: String) async throws -> String
    func resumeSession(id: String) async throws
    func workingDirectory(id: String, path: String?) async throws -> String
    func prompt(sessionID: String, text: String) async throws -> String
    func wait(sessionID: String) async throws
    func disconnect() async
}
