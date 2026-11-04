import AppKit
import Network
import ServiceManagement
import GatebarCore
import GatebarProviders

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let store = ProfileStore()
    private var gateways: [Gateway] = []
    private var invalidProfiles: [(name: String, errors: [ValidationError])] = []
    private var loadError: String?
    private let pathMonitor = NWPathMonitor()
    private var networkCheck: DispatchWorkItem?
    private lazy var settings = SettingsWindowController(store: store) { [weak self] in self?.reloadProfiles() }

    func applicationDidFinishLaunching(_ notification: Notification) {
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
        reloadProfiles()

        pathMonitor.pathUpdateHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.scheduleNetworkCheck() }
        }
        pathMonitor.start(queue: .global(qos: .utility))

        if gateways.isEmpty && invalidProfiles.isEmpty && loadError == nil {
            settings.show()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        gateways.forEach { $0.shutdown() }
    }

    func menuNeedsUpdate(_ menu: NSMenu) { render() }

    func reloadProfiles() {
        var profiles: [Profile] = []
        loadError = nil
        do {
            profiles = try store.load()
        } catch {
            loadError = error.localizedDescription
        }

        var next: [Gateway] = []
        invalidProfiles = []
        var seen = Set<String>()
        for profile in profiles {
            var errors = profile.validate()
            if !seen.insert(profile.id).inserted {
                errors.append(ValidationError("id", L.t("Another gateway already uses this id.", "Otra puerta ya usa este id.")))
            }
            if !errors.isEmpty {
                invalidProfiles.append((name: profile.name.isEmpty ? profile.id : profile.name, errors: errors))
                continue
            }
            if let existing = gateways.first(where: { $0.profile == profile }) {
                next.append(existing)
            } else if let gateway = GatewayFactory.make(for: profile) {
                gateway.onChange = { [weak self] in self?.render() }
                gateway.onAlert = { [weak self] message in self?.alert(message) }
                next.append(gateway)
            }
        }
        for old in gateways where !next.contains(where: { $0 === old }) {
            old.shutdown()
        }
        let fresh = next.filter { gateway in !gateways.contains(where: { $0 === gateway }) }
        gateways = next
        fresh.forEach { $0.start() }
        render()
    }

    private func scheduleNetworkCheck() {
        networkCheck?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.gateways.forEach { $0.networkDidChange() } }
        networkCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    private func render() {
        renderIcon()
        menu.removeAllItems()

        if let loadError {
            menu.addItem(disabled("⚠︎ " + loadError))
            menu.addItem(.separator())
        }
        if gateways.isEmpty && invalidProfiles.isEmpty {
            menu.addItem(disabled(L.t("No gateways yet", "Aún no hay puertas")))
            menu.addItem(action(L.t("Add your first gateway…", "Agrega tu primera puerta…"), #selector(openSettings)))
        }
        for gateway in gateways {
            menu.addItem(item(for: gateway))
        }
        for invalid in invalidProfiles {
            let entry = NSMenuItem(title: "\(invalid.name): " + L.t("invalid settings", "configuración no válida"), action: nil, keyEquivalent: "")
            entry.image = dot(.systemOrange)
            let sub = NSMenu()
            invalid.errors.forEach { sub.addItem(disabled($0.message)) }
            sub.addItem(.separator())
            sub.addItem(action(L.t("Fix in Settings…", "Corregir en Ajustes…"), #selector(openSettings)))
            entry.submenu = sub
            menu.addItem(entry)
        }

        menu.addItem(.separator())
        let settingsItem = action(L.t("Settings…", "Ajustes…"), #selector(openSettings))
        settingsItem.keyEquivalent = ","
        menu.addItem(settingsItem)
        let login = action(L.t("Open at login", "Abrir al iniciar sesión"), #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        let quit = action(L.t("Quit Gatebar", "Salir de Gatebar"), #selector(quit))
        quit.keyEquivalent = "q"
        menu.addItem(quit)
    }

    private func item(for gateway: Gateway) -> NSMenuItem {
        let entry = NSMenuItem(title: "\(gateway.profile.name): \(gateway.shortStatus)", action: nil, keyEquivalent: "")
        entry.image = dot(color(for: gateway.state))
        let sub = NSMenu()
        sub.autoenablesItems = false
        sub.addItem(disabled(gateway.state.detail))
        sub.addItem(.separator())
        let toggle = ClosureMenuItem(title: gateway.toggleTitle) { [weak gateway] in gateway?.toggle() }
        toggle.isEnabled = gateway.canToggle
        sub.addItem(toggle)
        let actions = gateway.actions
        if !actions.isEmpty {
            sub.addItem(.separator())
            for action in actions {
                let item = ClosureMenuItem(title: action.title, handler: action.perform)
                item.isEnabled = action.isEnabled
                sub.addItem(item)
            }
        }
        entry.submenu = sub
        return entry
    }

    private func color(for state: GatewayState) -> NSColor {
        switch state {
        case .inactive: return .tertiaryLabelColor
        case .working: return .systemOrange
        case .active: return .systemGreen
        case .failed: return .systemRed
        }
    }

    private func renderIcon() {
        let states = gateways.map(\.state)
        var badge: NSColor?
        if states.contains(where: { if case .failed = $0 { return true }; return false }) {
            badge = .systemRed
        } else if states.contains(where: { if case .working = $0 { return true }; return false }) {
            badge = .systemOrange
        } else if states.contains(where: { if case .active = $0 { return true }; return false }) {
            badge = .systemGreen
        }
        statusItem.button?.image = StatusIcon.make(badge: badge)
        let open = states.filter { if case .active = $0 { return true }; return false }.count
        statusItem.button?.toolTip = "Gatebar · " + L.t("\(open) of \(gateways.count) open", "\(open) de \(gateways.count) abiertas")
    }

    private func dot(_ color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func openSettings() { settings.show() }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            alert(L.t("Could not change the login item: ", "No pude cambiar el inicio automático: ") + error.localizedDescription)
        }
        render()
    }

    @objc private func quit() { NSApp.terminate(nil) }

    private func alert(_ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Gatebar"
        alert.informativeText = message
        alert.runModal()
    }
}

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func fire() { handler() }
}
