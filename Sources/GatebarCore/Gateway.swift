import Foundation

public enum GatewayState: Equatable {
    case inactive(String)
    case working(String)
    case active(String)
    case failed(String)

    public var detail: String {
        switch self {
        case .inactive(let text), .working(let text), .active(let text), .failed(let text):
            return text
        }
    }
}

public struct GatewayAction {
    public let title: String
    public let isEnabled: Bool
    public let perform: () -> Void

    public init(title: String, isEnabled: Bool = true, perform: @escaping () -> Void) {
        self.title = title
        self.isEnabled = isEnabled
        self.perform = perform
    }
}

public protocol Gateway: AnyObject {
    var profile: Profile { get }
    var state: GatewayState { get }
    var shortStatus: String { get }
    var toggleTitle: String { get }
    var canToggle: Bool { get }
    var actions: [GatewayAction] { get }

    var onChange: (() -> Void)? { get set }
    var onAlert: ((String) -> Void)? { get set }

    func start()
    func toggle()
    func networkDidChange()
    func shutdown()
}
