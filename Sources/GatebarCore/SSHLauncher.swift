import Foundation

public enum SSHLauncher {
    public static func open(_ host: SSHHost, profileID: String) throws {
        let safeName = String(host.host.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "_" })
        let script = Paths.sshLaunchers.appendingPathComponent("\(profileID)-\(safeName).command")
        try FileManager.default.createDirectory(at: Paths.sshLaunchers, withIntermediateDirectories: true)
        try "#!/bin/sh\nexec ssh \(Shell.quote(host.host))\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        Shell.run("/usr/bin/open", [script.path])
    }

    public static func actionTitle(_ host: SSHHost) -> String {
        L.t("Terminal: \(host.label)", "Terminal: \(host.label)")
    }
}
