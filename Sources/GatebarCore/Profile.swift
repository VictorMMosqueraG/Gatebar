import Foundation

public enum GatewayKind: String, Codable, CaseIterable {
    case openconnect
    case awsBastion = "aws-bastion"

    public var displayName: String {
        switch self {
        case .openconnect: return L.t("OpenConnect VPN", "VPN OpenConnect")
        case .awsBastion: return L.t("AWS bastion", "Bastión AWS")
        }
    }
}

public struct Profile: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var type: GatewayKind
    public var openconnect: OpenConnectSettings?
    public var awsBastion: AWSBastionSettings?

    public init(id: String, name: String, type: GatewayKind,
                openconnect: OpenConnectSettings? = nil, awsBastion: AWSBastionSettings? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.openconnect = openconnect
        self.awsBastion = awsBastion
    }

    public static func template(kind: GatewayKind, id: String, name: String) -> Profile {
        switch kind {
        case .openconnect:
            return Profile(id: id, name: name, type: kind, openconnect: OpenConnectSettings())
        case .awsBastion:
            return Profile(id: id, name: name, type: kind, awsBastion: AWSBastionSettings())
        }
    }

    public static func makeID(from name: String, existing: Set<String>) -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
        var slug = ""
        for scalar in folded.lowercased().unicodeScalars {
            if ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) {
                slug.unicodeScalars.append(scalar)
            } else if !slug.isEmpty, !slug.hasSuffix("-") {
                slug.append("-")
            }
        }
        while slug.hasSuffix("-") { slug.removeLast() }
        if slug.isEmpty { slug = "gateway" }
        slug = String(slug.prefix(36))
        while slug.hasSuffix("-") { slug.removeLast() }
        var candidate = slug
        var counter = 2
        while existing.contains(candidate) {
            candidate = "\(slug)-\(counter)"
            counter += 1
        }
        return candidate
    }
}

public struct VPNProtocolOption: Identifiable, Hashable {
    public let id: String
    public let title: String
}

public struct OpenConnectSettings: Codable, Equatable {
    public static let protocols: [VPNProtocolOption] = [
        VPNProtocolOption(id: "gp", title: "Palo Alto GlobalProtect"),
        VPNProtocolOption(id: "anyconnect", title: "Cisco AnyConnect"),
        VPNProtocolOption(id: "fortinet", title: "Fortinet"),
        VPNProtocolOption(id: "pulse", title: "Pulse / Ivanti"),
        VPNProtocolOption(id: "nc", title: "Juniper Network Connect"),
        VPNProtocolOption(id: "f5", title: "F5 BIG-IP"),
        VPNProtocolOption(id: "array", title: "Array Networks"),
    ]

    public var server: String
    public var vpnProtocol: String
    public var user: String
    public var serverCert: String?
    public var splitDNS: [String]

    enum CodingKeys: String, CodingKey {
        case server, vpnProtocol = "protocol", user, serverCert, splitDNS
    }

    public init(server: String = "", vpnProtocol: String = "gp", user: String = "",
                serverCert: String? = nil, splitDNS: [String] = []) {
        self.server = server
        self.vpnProtocol = vpnProtocol
        self.user = user
        self.serverCert = serverCert
        self.splitDNS = splitDNS
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        server = try c.decode(String.self, forKey: .server)
        vpnProtocol = try c.decodeIfPresent(String.self, forKey: .vpnProtocol) ?? "gp"
        user = try c.decode(String.self, forKey: .user)
        serverCert = try c.decodeIfPresent(String.self, forKey: .serverCert)
        splitDNS = try c.decodeIfPresent([String].self, forKey: .splitDNS) ?? []
    }
}

public struct SSHHost: Codable, Hashable, Identifiable {
    public let id = UUID()
    public var label: String
    public var host: String

    enum CodingKeys: String, CodingKey { case label, host }

    public init(label: String, host: String) {
        self.label = label
        self.host = host
    }

    public static func == (a: SSHHost, b: SSHHost) -> Bool { a.label == b.label && a.host == b.host }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(label)
        hasher.combine(host)
    }
}

public struct AWSBastionSettings: Codable, Equatable {
    public var region: String
    public var securityGroupId: String
    public var port: Int
    public var maxOpenHours: Double
    public var awsProfile: String?
    public var ruleDescription: String?
    public var sshHosts: [SSHHost]

    enum CodingKeys: String, CodingKey {
        case region, securityGroupId, port, maxOpenHours, awsProfile, ruleDescription, sshHosts
    }

    public init(region: String = "us-east-1", securityGroupId: String = "", port: Int = 22,
                maxOpenHours: Double = 8, awsProfile: String? = nil, ruleDescription: String? = nil,
                sshHosts: [SSHHost] = []) {
        self.region = region
        self.securityGroupId = securityGroupId
        self.port = port
        self.maxOpenHours = maxOpenHours
        self.awsProfile = awsProfile
        self.ruleDescription = ruleDescription
        self.sshHosts = sshHosts
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        region = try c.decode(String.self, forKey: .region)
        securityGroupId = try c.decode(String.self, forKey: .securityGroupId)
        port = try c.decodeIfPresent(Int.self, forKey: .port) ?? 22
        maxOpenHours = try c.decodeIfPresent(Double.self, forKey: .maxOpenHours) ?? 8
        awsProfile = try c.decodeIfPresent(String.self, forKey: .awsProfile)
        ruleDescription = try c.decodeIfPresent(String.self, forKey: .ruleDescription)
        sshHosts = try c.decodeIfPresent([SSHHost].self, forKey: .sshHosts) ?? []
    }

    public var effectiveRuleDescription: String {
        if let ruleDescription, !ruleDescription.isEmpty { return ruleDescription }
        let user = NSUserName().lowercased().filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return "gatebar-" + (user.isEmpty ? "user" : user)
    }
}
