import XCTest
@testable import GatebarCore

final class HelperConfigTests: XCTestCase {
    func testRenderFullSettings() {
        let settings = OpenConnectSettings(server: "https://vpn.example.com", vpnProtocol: "anyconnect", user: "jdoe",
                                           serverCert: "pin-sha256:abc=", splitDNS: ["corp.example.com", "intra.local"])
        XCTAssertEqual(HelperConfig.render(settings), """
        SERVER=https://vpn.example.com
        PROTOCOL=anyconnect
        USER=jdoe
        SERVERCERT=pin-sha256:abc=
        SPLIT_DNS=corp.example.com intra.local

        """)
    }

    func testRenderOmitsEmptyOptionalValues() {
        let settings = OpenConnectSettings(server: "https://vpn.example.com", user: "jdoe", serverCert: "")
        XCTAssertEqual(HelperConfig.render(settings), "SERVER=https://vpn.example.com\nPROTOCOL=gp\nUSER=jdoe\n")
    }

    func testShellQuote() {
        XCTAssertEqual(Shell.quote("it's"), #"'it'\''s'"#)
    }

    func testIPv4() {
        XCTAssertTrue(NetworkInfo.isIPv4("10.0.0.1"))
        XCTAssertFalse(NetworkInfo.isIPv4("10.0.0.256"))
        XCTAssertFalse(NetworkInfo.isIPv4("10.0.0"))
    }
}
