import Foundation
import GatebarCore

public final class OpenConnectGateway: Gateway {
    public let profile: Profile
    public var onChange: (() -> Void)?
    public var onAlert: ((String) -> Void)?
    public private(set) var state: GatewayState = .inactive(L.t("Disconnected", "Desconectada")) {
        didSet {
            launchPendingTerminal()
            onChange?()
        }
    }

    private let settings: OpenConnectSettings
    private var process: Process?
    private var monitor: Timer?
    private var logHandle: FileHandle?
    private var recentOutput = ""
    private var userStopped = false
    private var wasConnected = false
    private var restartPending = false
    private var preparing = false
    private var networkAtConnect: String?
    private var pendingTerminal: SSHHost?

    public init(profile: Profile, settings: OpenConnectSettings) {
        self.profile = profile
        self.settings = settings
    }

    public var shortStatus: String {
        switch state {
        case .inactive: return L.t("disconnected", "desconectada")
        case .working: return L.t("working…", "en curso…")
        case .active: return L.t("connected", "conectada")
        case .failed: return L.t("error", "error")
        }
    }

    public var toggleTitle: String {
        switch state {
        case .inactive: return L.t("Connect", "Conectar")
        case .failed: return L.t("Reconnect", "Reconectar")
        case .working: return L.t("Cancel", "Cancelar")
        case .active: return L.t("Disconnect", "Desconectar")
        }
    }

    public var canToggle: Bool { !preparing }

    public var actions: [GatewayAction] {
        let terminals = settings.sshHosts.map { host in
            GatewayAction(title: SSHLauncher.actionTitle(host), isEnabled: canToggle) { [weak self] in
                self?.openTerminal(host)
            }
        }
        return terminals + [GatewayAction(title: L.t("Show log", "Ver log")) { [weak self] in self?.openLog() }]
    }

    public func start() {
        guard runningPID() != nil else { return }
        userStopped = false
        wasConnected = true
        networkAtConnect = NetworkInfo.physicalNetwork()
        state = .active(connectedText(tunnelIP()))
        startMonitor()
    }

    public func toggle() {
        switch state {
        case .inactive, .failed:
            connect()
        case .working, .active:
            restartPending = false
            disconnect()
        }
    }

    public func networkDidChange() {
        let current = NetworkInfo.physicalNetwork()
        switch state {
        case .working, .active:
            break
        case .failed where !userStopped && current != nil && current != networkAtConnect:
            connect()
            return
        default:
            return
        }
        guard let current, let previous = networkAtConnect, current != previous else { return }
        restartPending = true
        disconnect()
    }

    public func shutdown() {
        restartPending = false
        monitor?.invalidate()
        monitor = nil
        guard process?.isRunning == true || runningPID() != nil else { return }
        userStopped = true
        let result = Shell.run("/usr/bin/sudo", ["-n", Paths.helper, "disconnect", profile.id])
        if !result.ok { process?.interrupt() }
        process?.waitUntilExit()
    }

    private func connect() {
        guard !preparing, process == nil else { return }
        guard HelperConfig.isHelperInstalled else {
            fail(L.t("system component not installed", "falta el componente del sistema"), alert: L.t(
                "\(profile.name) needs Gatebar's system component. Open Settings and press \"Install system component\".",
                "\(profile.name) necesita el componente del sistema de Gatebar. Abre Ajustes y pulsa \"Instalar componente del sistema\"."))
            return
        }
        guard let password = Keychain.password(for: profile.id) else {
            fail(L.t("no password saved", "sin contraseña guardada"), alert: L.t(
                "There is no password for \(profile.name). Add it in Settings.",
                "No hay contraseña para \(profile.name). Agrégala en Ajustes."))
            return
        }
        userStopped = false
        if HelperConfig.isInstalled(profileID: profile.id, settings: settings) {
            launch(password: password)
            return
        }
        preparing = true
        state = .working(L.t("Waiting for administrator approval…", "Esperando aprobación del administrador…"))
        let profileID = profile.id
        let settings = settings
        DispatchQueue.global(qos: .userInitiated).async {
            let result = HelperConfig.install(profileID: profileID, settings: settings)
            DispatchQueue.main.async {
                self.preparing = false
                if result.ok {
                    self.launch(password: password)
                } else if AdminRunner.wasCancelled(result) {
                    self.state = .inactive(L.t("Disconnected", "Desconectada"))
                } else {
                    self.fail(L.t("could not install the profile", "no pude instalar el perfil"),
                              alert: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
        }
    }

    private func launch(password: String) {
        let logURL = Paths.log(for: profile.id)
        try? FileManager.default.createDirectory(at: Paths.logs, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        logHandle = try? FileHandle(forWritingTo: logURL)
        recentOutput = ""

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        p.arguments = ["-n", Paths.helper, "connect", profile.id]
        let stdin = Pipe()
        let output = Pipe()
        p.standardInput = stdin
        p.standardOutput = output
        p.standardError = output
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            DispatchQueue.main.async { self?.consume(data) }
        }
        p.terminationHandler = { [weak self] finished in
            DispatchQueue.main.async {
                output.fileHandleForReading.readabilityHandler = nil
                self?.processEnded(status: finished.terminationStatus)
            }
        }
        do {
            try p.run()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            fail(L.t("could not start", "no pude iniciar"), alert: error.localizedDescription)
            return
        }
        stdin.fileHandleForWriting.write(Data((password + "\n").utf8))
        try? stdin.fileHandleForWriting.close()

        process = p
        wasConnected = false
        networkAtConnect = NetworkInfo.physicalNetwork()
        state = .working(L.t("Connecting…", "Conectando…"))
        startMonitor()
    }

    private func disconnect() {
        let running = process?.isRunning == true
        guard running || runningPID() != nil else {
            restartPending = false
            state = .inactive(L.t("Disconnected", "Desconectada"))
            return
        }
        userStopped = true
        state = .working(L.t("Disconnecting…", "Desconectando…"))
        let profileID = profile.id
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Shell.run("/usr/bin/sudo", ["-n", Paths.helper, "disconnect", profileID])
            if !result.ok {
                DispatchQueue.main.async { self.process?.interrupt() }
            }
        }
    }

    private func startMonitor() {
        monitor?.invalidate()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(timer, forMode: .common)
        monitor = timer
    }

    private func poll() {
        let pid = runningPID()
        if case .working = state, !userStopped, pid != nil, let ip = tunnelIP() {
            wasConnected = true
            state = .active(connectedText(ip))
        }
        if pid == nil, process == nil {
            processEnded(status: nil)
        }
    }

    private func consume(_ data: Data) {
        logHandle?.write(data)
        recentOutput += String(decoding: data, as: UTF8.self)
        if recentOutput.count > 4000 { recentOutput = String(recentOutput.suffix(4000)) }
        if case .working = state, !userStopped,
           let ip = firstCapture(#"(?:Configured as|Connected as) ([0-9.]+)"#, in: recentOutput) {
            wasConnected = true
            state = .active(connectedText(ip))
        }
    }

    private func processEnded(status: Int32?) {
        monitor?.invalidate()
        monitor = nil
        process = nil
        logHandle?.closeFile()
        logHandle = nil
        if restartPending {
            restartPending = false
            connect()
        } else if userStopped {
            state = .inactive(L.t("Disconnected", "Desconectada"))
        } else if wasConnected {
            state = .failed(L.t("the connection dropped", "se cayó la conexión"))
        } else {
            state = .failed(explainFailure(status: status))
        }
    }

    private func explainFailure(status: Int32?) -> String {
        let text = recentOutput.lowercased()
        if text.contains("a password is required") || text.contains("not allowed to execute") {
            return L.t("sudo rule missing: reinstall the system component", "falta la regla de sudo: reinstala el componente del sistema")
        }
        if text.contains("not installed") {
            return L.t("profile not installed: connect again", "perfil no instalado: vuelve a conectar")
        }
        if text.contains("openconnect not found") {
            return L.t("openconnect not found: brew install openconnect", "no encontré openconnect: brew install openconnect")
        }
        if text.contains("login failed") || text.contains("authentication failed") || text.contains("401") {
            return L.t("login failed: check user and password", "inicio de sesión fallido: revisa usuario y contraseña")
        }
        if text.contains("certificate") {
            return L.t("server certificate does not match the pin", "el certificado del servidor no coincide con el pin")
        }
        let code = status.map { " (\($0))" } ?? ""
        return L.t("could not connect\(code): see the log", "error al conectar\(code): revisa el log")
    }

    private func fail(_ reason: String, alert: String?) {
        state = .failed(reason)
        if let alert, !alert.isEmpty { onAlert?(alert) }
    }

    private func connectedText(_ ip: String?) -> String {
        if let ip { return L.t("Connected (\(ip))", "Conectada (\(ip))") }
        return L.t("Connected", "Conectada")
    }

    private func openTerminal(_ host: SSHHost) {
        switch state {
        case .active:
            launch(host)
        case .working:
            pendingTerminal = host
        case .inactive, .failed:
            pendingTerminal = host
            connect()
        }
    }

    private func launchPendingTerminal() {
        switch state {
        case .active:
            if let host = pendingTerminal {
                pendingTerminal = nil
                launch(host)
            }
        case .inactive, .failed:
            pendingTerminal = nil
        case .working:
            break
        }
    }

    private func launch(_ host: SSHHost) {
        do {
            try SSHLauncher.open(host, profileID: profile.id)
        } catch {
            onAlert?(error.localizedDescription)
        }
    }

    private func openLog() {
        let url = Paths.log(for: profile.id)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: Paths.logs, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        Shell.run("/usr/bin/open", [url.path])
    }

    private func runningPID() -> Int32? {
        guard let text = try? String(contentsOfFile: Paths.pidFile(for: profile.id), encoding: .utf8),
              let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 1 else { return nil }
        guard kill(pid, 0) == 0 || errno == EPERM else { return nil }
        let command = Shell.run("/bin/ps", ["-p", "\(pid)", "-o", "comm="]).stdout
        return command.contains("openconnect") ? pid : nil
    }

    private func tunnelIP() -> String? {
        guard let text = try? String(contentsOfFile: Paths.ipFile(for: profile.id), encoding: .utf8) else { return nil }
        let ip = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return NetworkInfo.isIPv4(ip) ? ip : nil
    }
}
