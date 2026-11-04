import Foundation

public struct ValidationError: Error, Hashable, CustomStringConvertible {
    public let field: String
    public let message: String

    public init(_ field: String, _ message: String) {
        self.field = field
        self.message = message
    }

    public var description: String { "\(field): \(message)" }
}

public enum Patterns {
    public static let id = "^[a-z0-9][a-z0-9-]{0,39}$"
    public static let server = "^https://[A-Za-z0-9.:/_-]+$"
    public static let user = "^[A-Za-z0-9._@][A-Za-z0-9._@-]*$"
    public static let serverCert = "^(pin-sha256:[A-Za-z0-9+/=]+|sha1:[0-9a-fA-F]+|sha256:[0-9a-fA-F]+)$"
    public static let domain = "^[A-Za-z0-9][A-Za-z0-9.-]*$"
    public static let region = "^[a-z]{2}(-[a-z]+)+-[0-9]+$"
    public static let securityGroup = "^sg-[0-9a-f]{8,17}$"
    public static let awsProfile = "^[A-Za-z0-9._-]+$"
    public static let ruleDescription = "^[A-Za-z0-9 ._:/=+@-]{1,255}$"
    public static let sshHost = "^[A-Za-z0-9._@:][A-Za-z0-9._@:-]*$"
}

public func fullMatch(_ value: String, _ pattern: String) -> Bool {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
    let range = NSRange(value.startIndex..., in: value)
    guard let match = regex.firstMatch(in: value, range: range) else { return false }
    return match.range == range
}

public func firstCapture(_ pattern: String, in text: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
          match.numberOfRanges > 1,
          let range = Range(match.range(at: 1), in: text) else { return nil }
    return String(text[range])
}

extension Profile {
    public func validate() -> [ValidationError] {
        var errors: [ValidationError] = []
        if !fullMatch(id, Patterns.id) {
            errors.append(.init("id", L.t("Use lowercase letters, numbers and dashes.", "Usa minúsculas, números y guiones.")))
        }
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append(.init("name", L.t("Give it a name.", "Ponle un nombre.")))
        }
        switch type {
        case .openconnect:
            if let settings = openconnect {
                errors += settings.validate()
            } else {
                errors.append(.init("openconnect", L.t("Missing VPN settings.", "Faltan los datos de la VPN.")))
            }
        case .awsBastion:
            if let settings = awsBastion {
                errors += settings.validate()
            } else {
                errors.append(.init("awsBastion", L.t("Missing bastion settings.", "Faltan los datos del bastión.")))
            }
        }
        return errors
    }

    public static func validateAll(_ profiles: [Profile]) -> [String: [ValidationError]] {
        var result: [String: [ValidationError]] = [:]
        var seen = Set<String>()
        for profile in profiles {
            var errors = profile.validate()
            if !seen.insert(profile.id).inserted {
                errors.append(.init("id", L.t("Another gateway already uses this id.", "Otra puerta ya usa este id.")))
            }
            if !errors.isEmpty { result[profile.id, default: []] += errors }
        }
        return result
    }
}

extension OpenConnectSettings {
    public func validate() -> [ValidationError] {
        var errors: [ValidationError] = []
        if !fullMatch(server, Patterns.server) {
            errors.append(.init("server", L.t("The server must start with https://", "El servidor debe empezar con https://")))
        }
        if !Self.protocols.contains(where: { $0.id == vpnProtocol }) {
            errors.append(.init("protocol", L.t("Unknown protocol.", "Protocolo desconocido.")))
        }
        if !fullMatch(user, Patterns.user) {
            errors.append(.init("user", L.t("Invalid user name.", "Usuario no válido.")))
        }
        if let serverCert, !serverCert.isEmpty, !fullMatch(serverCert, Patterns.serverCert) {
            errors.append(.init("serverCert", L.t("Use pin-sha256:…, sha1:… or sha256:…", "Usa pin-sha256:…, sha1:… o sha256:…")))
        }
        for domain in splitDNS where !fullMatch(domain, Patterns.domain) {
            errors.append(.init("splitDNS", L.t("Invalid domain: \(domain)", "Dominio no válido: \(domain)")))
        }
        return errors
    }
}

extension AWSBastionSettings {
    public func validate() -> [ValidationError] {
        var errors: [ValidationError] = []
        if !fullMatch(region, Patterns.region) {
            errors.append(.init("region", L.t("Invalid region (e.g. us-east-1).", "Región no válida (ej. us-east-1).")))
        }
        if !fullMatch(securityGroupId, Patterns.securityGroup) {
            errors.append(.init("securityGroupId", L.t("Invalid security group (e.g. sg-0123abcd).", "Security group no válido (ej. sg-0123abcd).")))
        }
        if !(1...65535).contains(port) {
            errors.append(.init("port", L.t("The port must be between 1 and 65535.", "El puerto debe estar entre 1 y 65535.")))
        }
        if !(maxOpenHours > 0 && maxOpenHours <= 24) {
            errors.append(.init("maxOpenHours", L.t("Use between 0 and 24 hours.", "Usa entre 0 y 24 horas.")))
        }
        if let awsProfile, !awsProfile.isEmpty, !fullMatch(awsProfile, Patterns.awsProfile) {
            errors.append(.init("awsProfile", L.t("Invalid AWS profile name.", "Nombre de perfil de AWS no válido.")))
        }
        if !fullMatch(effectiveRuleDescription, Patterns.ruleDescription) {
            errors.append(.init("ruleDescription", L.t("Invalid rule description.", "Descripción de regla no válida.")))
        }
        for host in sshHosts {
            if host.label.trimmingCharacters(in: .whitespaces).isEmpty {
                errors.append(.init("sshHosts", L.t("Every terminal needs a name.", "Cada terminal necesita un nombre.")))
            }
            if !fullMatch(host.host, Patterns.sshHost) {
                errors.append(.init("sshHosts", L.t("Invalid SSH host: \(host.host)", "Host SSH no válido: \(host.host)")))
            }
        }
        return errors
    }
}
