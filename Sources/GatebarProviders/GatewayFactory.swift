import GatebarCore

public enum GatewayFactory {
    public static func make(for profile: Profile) -> Gateway? {
        switch profile.type {
        case .openconnect:
            return profile.openconnect.map { OpenConnectGateway(profile: profile, settings: $0) }
        case .awsBastion:
            return profile.awsBastion.map { AWSBastionGateway(profile: profile, settings: $0) }
        }
    }
}
