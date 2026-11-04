import AppKit
import SwiftUI
import GatebarCore

final class SettingsWindowController {
    private let model: SettingsModel
    private var window: NSWindow?

    init(store: ProfileStore, onSaved: @escaping () -> Void) {
        model = SettingsModel(store: store)
        model.onSaved = onSaved
    }

    func show() {
        model.reload()
        if window == nil {
            let controller = NSHostingController(rootView: SettingsView(model: model))
            let window = NSWindow(contentViewController: controller)
            window.title = L.t("Gatebar Settings", "Ajustes de Gatebar")
            window.setContentSize(NSSize(width: 860, height: 580))
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

final class SettingsModel: ObservableObject {
    @Published var profiles: [Profile] = []
    @Published var selectedID: String?
    @Published var passwords: [String: String] = [:]
    @Published var savedPasswordIDs: Set<String> = []
    @Published var message: String?
    @Published var helperInstalled = HelperConfig.isHelperInstalled
    @Published var installingHelper = false

    var onSaved: (() -> Void)?
    private let store: ProfileStore
    private var removedIDs: Set<String> = []

    init(store: ProfileStore) {
        self.store = store
    }

    func reload() {
        do {
            profiles = try store.load()
            message = nil
        } catch {
            profiles = []
            message = error.localizedDescription
        }
        if selectedID == nil || !profiles.contains(where: { $0.id == selectedID }) {
            selectedID = profiles.first?.id
        }
        passwords = [:]
        removedIDs = []
        savedPasswordIDs = Set(profiles.map(\.id).filter { Keychain.hasPassword(for: $0) })
        helperInstalled = HelperConfig.isHelperInstalled
    }

    var canSave: Bool { Profile.validateAll(profiles).isEmpty }

    func add(_ kind: GatewayKind) {
        let name = kind == .openconnect ? L.t("New VPN", "Nueva VPN") : L.t("New bastion", "Nuevo bastión")
        let id = Profile.makeID(from: name, existing: Set(profiles.map(\.id)))
        profiles.append(Profile.template(kind: kind, id: id, name: name))
        selectedID = id
        message = L.t("Fill in the fields and press Save.", "Completa los campos y pulsa Guardar.")
    }

    func removeSelected() {
        guard let id = selectedID else { return }
        profiles.removeAll { $0.id == id }
        removedIDs.insert(id)
        passwords[id] = nil
        selectedID = profiles.first?.id
        message = L.t("Removed. Press Save to confirm.", "Eliminada. Pulsa Guardar para confirmar.")
    }

    func renamed(_ id: String) {
        guard !savedIDs.contains(id), let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        let others = Set(profiles.map(\.id)).subtracting([id])
        let newID = Profile.makeID(from: profiles[index].name, existing: others.union(savedIDs))
        guard newID != id else { return }
        profiles[index].id = newID
        if let password = passwords.removeValue(forKey: id) { passwords[newID] = password }
        if selectedID == id { selectedID = newID }
    }

    private var savedIDs: Set<String> {
        Set(((try? store.load()) ?? []).map(\.id))
    }

    func save() {
        profiles.map(\.id).forEach(renamed)
        guard canSave else { return }
        do {
            try store.save(profiles)
            for (id, password) in passwords where !password.isEmpty && profiles.contains(where: { $0.id == id }) {
                try Keychain.setPassword(password, for: id)
            }
            for id in removedIDs where !profiles.contains(where: { $0.id == id }) {
                Keychain.deletePassword(for: id)
            }
            passwords = [:]
            removedIDs = []
            savedPasswordIDs = Set(profiles.map(\.id).filter { Keychain.hasPassword(for: $0) })
            message = L.t("Saved.", "Guardado.")
            onSaved?()
        } catch {
            message = error.localizedDescription
        }
    }

    func installHelper() {
        installingHelper = true
        message = L.t("Waiting for administrator approval…", "Esperando aprobación del administrador…")
        DispatchQueue.global(qos: .userInitiated).async {
            let result = HelperConfig.installHelper()
            DispatchQueue.main.async {
                self.installingHelper = false
                self.helperInstalled = HelperConfig.isHelperInstalled
                if result.ok {
                    self.message = L.t("System component installed.", "Componente del sistema instalado.")
                } else if AdminRunner.wasCancelled(result) {
                    self.message = nil
                } else {
                    self.message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
    }

    func revealProfilesFile() {
        do {
            try store.ensureFileExists()
            NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
        } catch {
            message = error.localizedDescription
        }
    }

    func binding(for id: String) -> Binding<Profile>? {
        guard let current = profiles.first(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { [weak self] in self?.profiles.first(where: { $0.id == id }) ?? current },
            set: { [weak self] value in
                guard let self, let index = self.profiles.firstIndex(where: { $0.id == id }) else { return }
                self.profiles[index] = value
            })
    }

    func passwordBinding(for id: String) -> Binding<String> {
        Binding(get: { [weak self] in self?.passwords[id] ?? "" },
                set: { [weak self] value in self?.passwords[id] = value })
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 230)
            Divider()
            VStack(spacing: 0) {
                if let id = model.selectedID, let profile = model.binding(for: id) {
                    ProfileEditor(profile: profile,
                                  password: model.passwordBinding(for: id),
                                  hasSavedPassword: model.savedPasswordIDs.contains(id),
                                  onNameCommit: { model.renamed(id) })
                        .id(id)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "door.left.hand.open").font(.system(size: 36)).foregroundStyle(.secondary)
                        Text(L.t("Add a gateway with the + button.", "Agrega una puerta con el botón +."))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Divider()
                footer
            }
        }
        .frame(minWidth: 780, minHeight: 520)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $model.selectedID) {
                ForEach(model.profiles) { profile in
                    Label(profile.name.isEmpty ? profile.id : profile.name,
                          systemImage: profile.type == .openconnect ? "network" : "server.rack")
                        .tag(profile.id)
                }
            }
            Divider()
            HStack(spacing: 4) {
                Menu {
                    ForEach(GatewayKind.allCases, id: \.self) { kind in
                        Button(kind.displayName) { model.add(kind) }
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Button {
                    model.removeSelected()
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)
                .disabled(model.selectedID == nil)
                Spacer()
            }
            .padding(8)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button(model.helperInstalled
                   ? L.t("Reinstall system component…", "Reinstalar componente del sistema…")
                   : L.t("Install system component…", "Instalar componente del sistema…")) {
                model.installHelper()
            }
            .disabled(model.installingHelper)
            .help(L.t("Needed by VPN gateways: lets Gatebar start openconnect as root without asking every time.",
                      "Lo necesitan las VPN: permite a Gatebar iniciar openconnect como root sin pedir clave cada vez."))
            Button(L.t("Show profiles.json", "Mostrar profiles.json")) { model.revealProfilesFile() }
            Spacer()
            if let message = model.message {
                Text(message).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
            }
            Button(L.t("Revert", "Descartar")) { model.reload() }
            Button(L.t("Save", "Guardar")) { model.save() }
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(!model.canSave)
        }
        .padding(12)
    }
}

struct ProfileEditor: View {
    @Binding var profile: Profile
    @Binding var password: String
    let hasSavedPassword: Bool
    let onNameCommit: () -> Void

    var body: some View {
        Form {
            Section(L.t("General", "General")) {
                TextField(L.t("Name", "Nombre"), text: $profile.name)
                    .onSubmit(onNameCommit)
                LabeledContent("ID", value: profile.id)
                LabeledContent(L.t("Type", "Tipo"), value: profile.type.displayName)
            }
            switch profile.type {
            case .openconnect:
                OpenConnectFields(settings: openconnect, password: $password, hasSavedPassword: hasSavedPassword)
            case .awsBastion:
                AWSBastionFields(settings: awsBastion)
            }
            let errors = profile.validate()
            if !errors.isEmpty {
                Section(L.t("Fix before saving", "Corrige antes de guardar")) {
                    ForEach(errors, id: \.self) { error in
                        Text(error.message).foregroundStyle(.red)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var openconnect: Binding<OpenConnectSettings> {
        Binding(get: { profile.openconnect ?? OpenConnectSettings() },
                set: { profile.openconnect = $0 })
    }

    private var awsBastion: Binding<AWSBastionSettings> {
        Binding(get: { profile.awsBastion ?? AWSBastionSettings() },
                set: { profile.awsBastion = $0 })
    }
}

struct OpenConnectFields: View {
    @Binding var settings: OpenConnectSettings
    @Binding var password: String
    let hasSavedPassword: Bool
    @State private var domainsText = ""

    var body: some View {
        Section {
            TextField(L.t("Server", "Servidor"), text: $settings.server, prompt: Text("https://vpn.example.com"))
            Picker(L.t("Protocol", "Protocolo"), selection: $settings.vpnProtocol) {
                ForEach(OpenConnectSettings.protocols) { option in
                    Text(option.title).tag(option.id)
                }
            }
            TextField(L.t("User", "Usuario"), text: $settings.user)
            SecureField(L.t("Password", "Contraseña"), text: $password,
                        prompt: Text(hasSavedPassword
                                     ? L.t("Saved in Keychain · type to replace", "Guardada en el Llavero · escribe para cambiarla")
                                     : L.t("Saved in Keychain", "Se guarda en el Llavero")))
            TextField(L.t("Server certificate", "Certificado del servidor"), text: optionalText($settings.serverCert),
                      prompt: Text("pin-sha256:…  " + L.t("(optional)", "(opcional)")))
            TextField(L.t("Split DNS domains", "Dominios por la VPN"), text: $domainsText,
                      prompt: Text("corp.example.com, intranet.local"))
                .onAppear { domainsText = settings.splitDNS.joined(separator: ", ") }
                .onChange(of: domainsText) { text in
                    settings.splitDNS = text.split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                }
        } header: {
            Text("VPN")
        } footer: {
            Text(L.t("Only the split DNS domains are resolved through the VPN. Leave empty to use the VPN DNS for everything.",
                     "Solo los dominios indicados se resuelven por la VPN. Déjalo vacío para usar el DNS de la VPN en todo."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct AWSBastionFields: View {
    @Binding var settings: AWSBastionSettings

    var body: some View {
        Section {
            TextField(L.t("Region", "Región"), text: $settings.region, prompt: Text("us-east-1"))
            TextField("Security group", text: $settings.securityGroupId, prompt: Text("sg-0123456789abcdef0"))
            TextField(L.t("Port", "Puerto"), value: $settings.port, format: .number.grouping(.never))
            TextField(L.t("Close after (hours)", "Cerrar después de (horas)"), value: $settings.maxOpenHours, format: .number)
            TextField(L.t("AWS CLI profile", "Perfil del AWS CLI"), text: optionalText($settings.awsProfile),
                      prompt: Text(L.t("default", "por defecto")))
            TextField(L.t("Rule description", "Descripción de la regla"), text: optionalText($settings.ruleDescription),
                      prompt: Text(settings.effectiveRuleDescription))
        } header: {
            Text("AWS")
        } footer: {
            Text(L.t("Uses your AWS CLI credentials. Opening adds a rule for your public IP only; it is removed when you close it, quit the app or the time runs out.",
                     "Usa las credenciales de tu AWS CLI. Abrir agrega una regla solo para tu IP pública; se quita al cerrar, al salir de la app o al vencer el tiempo."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Section(L.t("SSH terminals", "Terminales SSH")) {
            ForEach($settings.sshHosts) { $host in
                HStack {
                    TextField(L.t("Name", "Nombre"), text: $host.label, prompt: Text("Prod"))
                    TextField(L.t("Host or ~/.ssh/config alias", "Host o alias de ~/.ssh/config"), text: $host.host,
                              prompt: Text("prod-server"))
                    Button {
                        let id = host.id
                        settings.sshHosts.removeAll { $0.id == id }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
                .labelsHidden()
            }
            Button(L.t("Add terminal", "Agregar terminal")) {
                settings.sshHosts.append(SSHHost(label: "", host: ""))
            }
        }
    }
}

private func optionalText(_ binding: Binding<String?>) -> Binding<String> {
    Binding(get: { binding.wrappedValue ?? "" },
            set: { binding.wrappedValue = $0.isEmpty ? nil : $0 })
}
