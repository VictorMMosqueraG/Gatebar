import Foundation

public enum NetworkInfo {
    public static func physicalNetwork() -> String? {
        let result = Shell.run("/sbin/route", ["-n", "get", "default"])
        guard result.ok,
              let interface = firstCapture(#"interface: (\S+)"#, in: result.stdout),
              !interface.hasPrefix("utun") else { return nil }
        let gateway = firstCapture(#"gateway: (\S+)"#, in: result.stdout) ?? "-"
        return "\(interface) \(gateway)"
    }

    public static func publicIPv4() -> String? {
        let result = Shell.run("/usr/bin/curl", ["-s", "--max-time", "6", "https://checkip.amazonaws.com"])
        let ip = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.ok && isIPv4(ip) ? ip : nil
    }

    public static func isIPv4(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard !part.isEmpty, part.count <= 3, let number = Int(part) else { return false }
            return number <= 255
        }
    }
}
