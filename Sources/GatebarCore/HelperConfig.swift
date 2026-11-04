import Foundation

public enum HelperConfig {
    public static var isHelperInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: Paths.helper)
    }

    public static func render(_ settings: OpenConnectSettings) -> String {
        var lines = [
            "SERVER=\(settings.server)",
            "PROTOCOL=\(settings.vpnProtocol)",
            "USER=\(settings.user)",
        ]
        if let cert = settings.serverCert, !cert.isEmpty { lines.append("SERVERCERT=\(cert)") }
        if !settings.splitDNS.isEmpty { lines.append("SPLIT_DNS=\(settings.splitDNS.joined(separator: " "))") }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func isInstalled(profileID: String, settings: OpenConnectSettings) -> Bool {
        let installed = try? String(contentsOfFile: Paths.systemVPNConfig(for: profileID), encoding: .utf8)
        return installed == render(settings)
    }

    public static func install(profileID: String, settings: OpenConnectSettings) -> CommandResult {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("gatebar-\(profileID)-\(UUID().uuidString).conf")
        do {
            try render(settings).write(to: temp, atomically: true, encoding: .utf8)
        } catch {
            return CommandResult(status: -1, stdout: "", stderr: error.localizedDescription)
        }
        defer { try? FileManager.default.removeItem(at: temp) }
        let command = [Paths.helper, "install-profile", profileID, temp.path].map(Shell.quote).joined(separator: " ")
        return AdminRunner.run(command)
    }

    public static func installHelper() -> CommandResult {
        guard let dir = Paths.bundledHelperDir,
              FileManager.default.fileExists(atPath: dir.appendingPathComponent("install.sh").path) else {
            return CommandResult(status: -1, stdout: "", stderr: L.t(
                "install.sh is not inside the app. Run: sudo sh Helper/install.sh",
                "install.sh no está dentro de la app. Ejecuta: sudo sh Helper/install.sh"))
        }
        let command = "/bin/sh " + Shell.quote(dir.appendingPathComponent("install.sh").path) + " " + Shell.quote(NSUserName())
        return AdminRunner.run(command)
    }
}
