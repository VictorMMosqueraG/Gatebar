import XCTest
@testable import GatebarCore

final class ProfileTests: XCTestCase {
    private func decode(_ json: String) throws -> [Profile] {
        try JSONDecoder().decode([Profile].self, from: Data(json.utf8))
    }

    func testDecodesBothKindsAndAppliesDefaults() throws {
        let profiles = try decode("""
        [
          { "id": "client-vpn", "name": "Client VPN", "type": "openconnect",
            "openconnect": { "server": "https://vpn.example.com", "user": "jdoe" } },
          { "id": "prod", "name": "Prod bastion", "type": "aws-bastion",
            "awsBastion": { "region": "us-east-1", "securityGroupId": "sg-0123456789abcdef0" } }
        ]
        """)
        XCTAssertEqual(profiles.count, 2)
        XCTAssertEqual(profiles[0].openconnect?.vpnProtocol, "gp")
        XCTAssertEqual(profiles[0].openconnect?.splitDNS, [])
        XCTAssertEqual(profiles[0].openconnect?.sshHosts, [])
        XCTAssertEqual(profiles[1].awsBastion?.port, 22)
        XCTAssertEqual(profiles[1].awsBastion?.maxOpenHours, 8)
        XCTAssertEqual(profiles[1].awsBastion?.sshHosts, [])
        XCTAssertTrue(profiles.allSatisfy { $0.validate().isEmpty })
    }

    func testRoundTripKeepsEquality() throws {
        let profile = Profile(id: "prod", name: "Prod", type: .awsBastion,
                              awsBastion: AWSBastionSettings(securityGroupId: "sg-0123abcd",
                                                             sshHosts: [SSHHost(label: "App", host: "prod-app")]))
        let data = try JSONEncoder().encode([profile])
        let decoded = try JSONDecoder().decode([Profile].self, from: data)
        XCTAssertEqual(decoded, [profile])
    }

    func testRejectsValuesThatCouldInjectArguments() {
        var settings = OpenConnectSettings(server: "https://vpn.example.com --script=/tmp/x", user: "jdoe")
        XCTAssertFalse(settings.validate().isEmpty)
        settings.server = "http://vpn.example.com"
        XCTAssertFalse(settings.validate().isEmpty)
        settings.server = "https://vpn.example.com"
        settings.user = "-oProxyCommand"
        XCTAssertFalse(settings.validate().isEmpty)
        settings.user = "jdoe"
        settings.splitDNS = ["corp.example.com", "-bad"]
        XCTAssertFalse(settings.validate().isEmpty)
        settings.splitDNS = ["corp.example.com"]
        settings.serverCert = "pin-sha256:Q2hhbmdlTWU+/="
        XCTAssertTrue(settings.validate().isEmpty)
    }

    func testVPNTerminals() throws {
        var settings = OpenConnectSettings(server: "https://vpn.example.com", user: "jdoe",
                                           sshHosts: [SSHHost(label: "App", host: "app-server")])
        XCTAssertTrue(settings.validate().isEmpty)
        settings.sshHosts.append(SSHHost(label: "", host: "-oProxyCommand=evil"))
        XCTAssertEqual(settings.validate().count, 2)
        XCTAssertFalse(HelperConfig.render(settings).contains("app-server"))
    }

    func testBastionValidation() {
        var settings = AWSBastionSettings(securityGroupId: "sg-0123abcd")
        XCTAssertTrue(settings.validate().isEmpty)
        settings.securityGroupId = "0123abcd"
        XCTAssertFalse(settings.validate().isEmpty)
        settings.securityGroupId = "sg-0123abcd"
        settings.port = 70000
        XCTAssertFalse(settings.validate().isEmpty)
        settings.port = 22
        settings.sshHosts = [SSHHost(label: "x", host: "-oProxyCommand=evil")]
        XCTAssertFalse(settings.validate().isEmpty)
    }

    func testDuplicateIDs() {
        let a = Profile.template(kind: .openconnect, id: "same", name: "A")
        let b = Profile.template(kind: .awsBastion, id: "same", name: "B")
        XCTAssertNotNil(Profile.validateAll([a, b])["same"])
    }

    func testMakeID() {
        XCTAssertEqual(Profile.makeID(from: "VPN Cliente Ñandú", existing: []), "vpn-cliente-nandu")
        XCTAssertEqual(Profile.makeID(from: "Prod", existing: ["prod"]), "prod-2")
        XCTAssertEqual(Profile.makeID(from: "!!!", existing: []), "gateway")
        XCTAssertTrue(fullMatch(Profile.makeID(from: String(repeating: "a", count: 80), existing: []), Patterns.id))
    }

    func testExampleFileIsValid() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("examples/profiles.example.json")
        let profiles = try JSONDecoder().decode([Profile].self, from: Data(contentsOf: url))
        XCTAssertFalse(profiles.isEmpty)
        XCTAssertTrue(Profile.validateAll(profiles).isEmpty, "\(Profile.validateAll(profiles))")
    }
}
