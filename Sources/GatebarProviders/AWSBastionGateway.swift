import Foundation
import GatebarCore

public final class AWSBastionGateway: Gateway {
    public let profile: Profile
    public var onChange: (() -> Void)?
    public var onAlert: ((String) -> Void)?

    private let settings: AWSBastionSettings
    private let aws: SecurityGroupClient
    private let queue: DispatchQueue
    private var ip: String?
    private var rules: [IngressRule] = []
    private var busy = false
    private var lastError: String?
    private var ticker: Timer?

    public init(profile: Profile, settings: AWSBastionSettings) {
        self.profile = profile
        self.settings = settings
        self.aws = SecurityGroupClient(settings: settings)
        self.queue = DispatchQueue(label: "gatebar.bastion.\(profile.id)")
    }

    private var isOpen: Bool { !rules.isEmpty }
    private var maxOpen: TimeInterval { settings.maxOpenHours * 3600 }
    private var openedAtKey: String { "bastion.openedAt.\(profile.id)" }

    private var openedAt: Date? {
        get { UserDefaults.standard.object(forKey: openedAtKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: openedAtKey) }
    }

    private var expired: Bool {
        openedAt.map { Date().timeIntervalSince($0) > maxOpen } ?? false
    }

    public var state: GatewayState {
        if busy { return .working(L.t("Updating the security group…", "Actualizando el security group…")) }
        if let lastError { return .failed(lastError) }
        if isOpen, let ip {
            return .active(L.t("Port \(settings.port) open for \(ip) · closes in \(remaining())",
                               "Puerto \(settings.port) abierto para \(ip) · se cierra en \(remaining())"))
        }
        return .inactive(L.t("Port \(settings.port) closed for your IP", "Puerto \(settings.port) cerrado para tu IP"))
    }

    public var shortStatus: String {
        if busy { return L.t("updating…", "actualizando…") }
        if lastError != nil { return L.t("error", "error") }
        return isOpen ? L.t("open", "abierto") : L.t("closed", "cerrado")
    }

    public var toggleTitle: String { isOpen ? L.t("Close access", "Cerrar acceso") : L.t("Open access", "Abrir acceso") }
    public var canToggle: Bool { !busy }

    public var actions: [GatewayAction] {
        settings.sshHosts.map { host in
            GatewayAction(title: SSHLauncher.actionTitle(host), isEnabled: !busy) { [weak self] in
                self?.openTerminal(host)
            }
        }
    }

    public func start() {
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
        reconcile(nil)
    }

    public func toggle() { reconcile(!isOpen) }

    public func networkDidChange() {
        guard isOpen, !busy else { return }
        reconcile(nil)
    }

    public func shutdown() {
        ticker?.invalidate()
        ticker = nil
        guard isOpen else { return }
        _ = aws.revoke(rules.map(\.id))
        rules = []
        openedAt = nil
    }

    private func tick() {
        if isOpen, !busy {
            reconcile(expired ? false : nil)
        } else {
            onChange?()
        }
    }

    private func reconcile(_ desired: Bool?, then: (() -> Void)? = nil) {
        guard !busy else { return }
        busy = true
        lastError = nil
        onChange?()
        let keepOpen = desired ?? !expired
        let explicit = desired != nil
        let aws = self.aws
        queue.async {
            let result = aws.apply(open: keepOpen, explicit: explicit)
            DispatchQueue.main.async {
                self.busy = false
                switch result {
                case .success(let snapshot):
                    self.ip = snapshot.ip
                    self.rules = snapshot.open
                    if snapshot.open.isEmpty {
                        self.openedAt = nil
                    } else if self.openedAt == nil || desired == true {
                        self.openedAt = Date()
                    }
                    then?()
                case .failure(let error):
                    self.lastError = error.message
                }
                self.onChange?()
            }
        }
    }

    private func remaining() -> String {
        let left = max(0, maxOpen - Date().timeIntervalSince(openedAt ?? Date()))
        let minutes = Int(left / 60)
        return minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
    }

    private func openTerminal(_ host: SSHHost) {
        let launch = { [weak self] in
            guard let self else { return }
            do {
                try SSHLauncher.open(host, profileID: self.profile.id)
            } catch {
                self.onAlert?(error.localizedDescription)
            }
        }
        if isOpen { launch() } else { reconcile(true, then: launch) }
    }
}

struct IngressRule {
    let id: String
    let cidr: String
    let description: String
}

struct BastionSnapshot {
    let ip: String
    let open: [IngressRule]
}

struct BastionError: Error {
    let message: String
}

struct SecurityGroupClient {
    let settings: AWSBastionSettings

    private var tag: String { settings.effectiveRuleDescription }
    private static let duplicateMessage = "The rule already exists"

    func apply(open: Bool, explicit: Bool) -> Result<BastionSnapshot, BastionError> {
        guard let ip = NetworkInfo.publicIPv4() else {
            return .failure(BastionError(message: L.t("Could not read your public IP: is there internet?",
                                                      "No pude leer tu IP pública: ¿hay internet?")))
        }
        let cidr = "\(ip)/32"
        let all: [IngressRule]
        switch listRules() {
        case .success(let rules): all = rules
        case .failure(let error): return .failure(error)
        }

        let mine = all.filter { $0.description == tag || $0.cidr == cidr }
        var current = mine.filter { $0.cidr == cidr }
        let stale = mine.filter { $0.cidr != cidr }
        let wantOpen = open && (explicit || !current.isEmpty || !stale.isEmpty)

        let toRevoke = stale + (wantOpen ? [] : current)
        if !toRevoke.isEmpty, case .failure(let error) = revoke(toRevoke.map(\.id)) {
            return .failure(error)
        }
        guard wantOpen else { return .success(BastionSnapshot(ip: ip, open: [])) }
        if current.isEmpty {
            switch authorize(cidr) {
            case .success(let rule): current = [rule]
            case .failure(let error): return .failure(error)
            }
        }
        return .success(BastionSnapshot(ip: ip, open: current))
    }

    func listRules() -> Result<[IngressRule], BastionError> {
        aws([
            "ec2", "describe-security-group-rules",
            "--filters", "Name=group-id,Values=\(settings.securityGroupId)",
            "--query", "SecurityGroupRules[?!IsEgress && FromPort==`\(settings.port)`].[SecurityGroupRuleId,CidrIpv4,Description]",
            "--output", "text",
        ]).map { out in
            out.split(separator: "\n").compactMap { line in
                let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                guard fields.count >= 3 else { return nil }
                return IngressRule(id: fields[0], cidr: fields[1], description: fields[2])
            }
        }
    }

    func authorize(_ cidr: String) -> Result<IngressRule, BastionError> {
        let permission: [[String: Any]] = [[
            "IpProtocol": "tcp",
            "FromPort": settings.port,
            "ToPort": settings.port,
            "IpRanges": [["CidrIp": cidr, "Description": tag]],
        ]]
        guard let data = try? JSONSerialization.data(withJSONObject: permission),
              let json = String(data: data, encoding: .utf8) else {
            return .failure(BastionError(message: "JSON"))
        }
        let result = aws([
            "ec2", "authorize-security-group-ingress",
            "--group-id", settings.securityGroupId,
            "--ip-permissions", json,
            "--query", "SecurityGroupRules[0].SecurityGroupRuleId",
            "--output", "text",
        ])
        switch result {
        case .success(let id):
            return .success(IngressRule(id: id.trimmingCharacters(in: .whitespacesAndNewlines), cidr: cidr, description: tag))
        case .failure(let error) where error.message == Self.duplicateMessage:
            if case .success(let rules) = listRules(), let rule = rules.first(where: { $0.cidr == cidr }) {
                return .success(rule)
            }
            return .failure(error)
        case .failure(let error):
            return .failure(error)
        }
    }

    @discardableResult
    func revoke(_ ids: [String]) -> Result<String, BastionError> {
        aws(["ec2", "revoke-security-group-ingress", "--group-id", settings.securityGroupId,
             "--security-group-rule-ids"] + ids)
    }

    private func aws(_ args: [String]) -> Result<String, BastionError> {
        guard let cli = Shell.which("aws") else {
            return .failure(BastionError(message: L.t("AWS CLI not found: brew install awscli",
                                                      "No encontré el AWS CLI: brew install awscli")))
        }
        var env = ["AWS_PAGER": ""]
        if let profile = settings.awsProfile, !profile.isEmpty { env["AWS_PROFILE"] = profile }
        let result = Shell.run(cli, args + ["--region", settings.region], environment: env)
        if result.ok { return .success(result.stdout) }
        return .failure(BastionError(message: explain(result.stderr)))
    }

    private func explain(_ err: String) -> String {
        if err.contains("InvalidPermission.Duplicate") { return Self.duplicateMessage }
        if err.contains("UnauthorizedOperation") {
            return L.t("Your AWS user cannot edit the security group", "Tu usuario de AWS no puede editar el security group")
        }
        if err.contains("Unable to locate credentials") || err.contains("ExpiredToken") || err.contains("AuthFailure")
            || err.contains("Token has expired") {
            return L.t("Invalid AWS credentials: check ~/.aws or run aws sso login",
                       "Credenciales de AWS no válidas: revisa ~/.aws o ejecuta aws sso login")
        }
        let line = err.split(separator: "\n").first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return L.t("AWS error: ", "Error de AWS: ") + String((line ?? "unknown").prefix(90))
    }
}
