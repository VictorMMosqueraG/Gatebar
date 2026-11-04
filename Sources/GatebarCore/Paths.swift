import Foundation

public enum Paths {
    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    public static var appSupport: URL { home.appendingPathComponent("Library/Application Support/Gatebar") }
    public static var profiles: URL { appSupport.appendingPathComponent("profiles.json") }
    public static var sshLaunchers: URL { appSupport.appendingPathComponent("ssh") }
    public static var logs: URL { home.appendingPathComponent("Library/Logs/Gatebar") }

    public static func log(for profileID: String) -> URL {
        logs.appendingPathComponent("\(profileID).log")
    }

    public static let helper = "/Library/PrivilegedHelperTools/gatebar-helper"
    public static let vpncScript = "/Library/PrivilegedHelperTools/gatebar-vpnc-script"
    public static let systemVPNConfigs = "/Library/Application Support/Gatebar/vpn"
    public static let runDir = "/var/run/gatebar"

    public static func systemVPNConfig(for profileID: String) -> String {
        "\(systemVPNConfigs)/\(profileID).conf"
    }

    public static func pidFile(for profileID: String) -> String { "\(runDir)/\(profileID).pid" }
    public static func ipFile(for profileID: String) -> String { "\(runDir)/\(profileID).ip" }

    public static var bundledHelperDir: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("helper")
    }
}
