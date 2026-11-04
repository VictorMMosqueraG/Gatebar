# Gatebar

**Un ícono, todas tus puertas de entrada.**

Gatebar es una app ligera para la barra de menú de macOS, pensada para desarrolladores que trabajan en varios proyectos y cada uno tiene su propia forma de entrar: la VPN corporativa de un cliente, el bastión en AWS de otro, un jump host para staging.

En vez de recordar comandos, entrar a la consola de AWS para autorizar tu IP o tener tres clientes de VPN instalados, Gatebar lista cada *puerta de entrada* bajo un solo ícono. Un clic para conectar, otro para desconectar, y el estado de cada una a la vista.

```
🚪 ●
├── ● VPN ACME: conectada            ▸  Conectada (10.20.0.14)
│                                        Desconectar · Ver log
├── ● Bastión Shop: abierto          ▸  Puerto 22 abierto para 181.x.x.x · se cierra en 7 h 12 min
│                                        Cerrar acceso · Terminal: Prod · Terminal: QA
├── ○ VPN proyecto personal: desconectada
├── Ajustes…
└── Salir de Gatebar
```

## Qué hace

- **VPNs** con [openconnect](https://www.infradead.org/openconnect/): Palo Alto GlobalProtect, Cisco AnyConnect, Fortinet, Pulse/Ivanti, Juniper, F5 y Array. Con **DNS dividido**: solo los dominios del proyecto pasan por el túnel y el Mac sigue funcionando cuando cambias de red.
- **Bastiones en AWS:** abre el puerto del security group solo para tu IP pública actual (/32), se ajusta si tu IP cambia y lo cierra al cerrarlo, al salir de la app o al cumplirse un tiempo límite.
- **Terminales SSH con un clic** a los servidores que hay detrás de cada puerta.
- **Perfiles, no código:** agregas, renombras o quitas puertas desde la ventana de Ajustes. Las contraseñas quedan en el Llavero de macOS.
- **Reconecta** la VPN al cambiar de Wi-Fi y retoma túneles y puertos abiertos si reinicias la app.
- **Varias VPNs a la vez**, cada una con su propio estado.
- **Extensible:** cada tipo de puerta es un proveedor pequeño. Se puede sumar WireGuard, Tailscale o AWS SSM sin tocar lo demás ([cómo](docs/agregar-un-proveedor.md)).

## Requisitos

- macOS 13 Ventura o superior.
- Para VPNs: `brew install openconnect`.
- Para bastiones: `brew install awscli` con credenciales funcionando (`aws configure` o `aws sso login`).
- Para compilar: Xcode 15 o Swift 5.9+.

## Instalación

```sh
git clone https://github.com/VictorMMosqueraG/Gatebar.git
cd Gatebar
scripts/bundle.sh --install     # compila y abre ~/Applications/Gatebar.app
```

Luego abre **Ajustes…** desde el ícono y agrega tus puertas.

Las VPN necesitan además el **componente del sistema** (una sola vez; pide tu clave de administrador): Ajustes → *Instalar componente del sistema…*, o desde la terminal `sudo sh Helper/install.sh`.

### Opciones de `bundle.sh`

| Comando | Qué hace |
|---|---|
| `scripts/bundle.sh` | Arma `dist/Gatebar.app`. |
| `scripts/bundle.sh --install` | Además lo copia a `~/Applications` y lo abre. |
| `scripts/bundle.sh --zip` | Además crea `dist/Gatebar-<versión>.zip` (lo usa el CI al publicar). |

La app se firma *ad hoc*. Después de cada compilación nueva, macOS puede preguntar una vez si permites el acceso al Llavero: pulsa **Permitir siempre**.

## Configuración

Ajustes guarda todo en `~/Library/Application Support/Gatebar/profiles.json`. También puedes editarlo a mano; mira [examples/profiles.example.json](examples/profiles.example.json).

### Campos comunes

| Campo | Descripción |
|---|---|
| `id` | Minúsculas, números y guiones. Se crea a partir del nombre y no cambia después de guardar. Es también la cuenta de la contraseña en el Llavero. |
| `name` | El nombre que quieras. Es lo que ves en el menú. |
| `type` | `openconnect` o `aws-bastion`. |

### VPN (`openconnect`)

| Campo | Descripción |
|---|---|
| `server` | Dirección del servidor, siempre `https://…`. |
| `protocol` | `gp`, `anyconnect`, `fortinet`, `pulse`, `nc`, `f5` o `array`. |
| `user` | Usuario. La contraseña va al Llavero (servicio `Gatebar`). |
| `serverCert` | Opcional. Pin del certificado, por ejemplo `pin-sha256:…`. openconnect lo muestra la primera vez que conectas. |
| `splitDNS` | Dominios que se resuelven por la VPN. Si lo dejas vacío, todo el DNS pasa por la VPN. |

### Bastión AWS (`aws-bastion`)

| Campo | Descripción |
|---|---|
| `region` | Por ejemplo `us-east-1`. |
| `securityGroupId` | Security group del bastión. |
| `port` | Por defecto 22. |
| `maxOpenHours` | La regla se quita sola después de estas horas. Por defecto 8. |
| `awsProfile` | Opcional. Perfil del AWS CLI. |
| `ruleDescription` | Opcional. Por defecto `gatebar-<tu usuario>`. Gatebar la usa para reconocer sus propias reglas. |
| `sshHosts` | `[{ "label": "Prod", "host": "alias-en-ssh-config" }]` |

El usuario de AWS necesita `ec2:DescribeSecurityGroupRules`, `ec2:AuthorizeSecurityGroupIngress` y `ec2:RevokeSecurityGroupIngress` sobre ese security group.

## Arquitectura

El proyecto está organizado por capas. Cada capa solo usa la que tiene debajo, y `Package.swift` lo hace cumplir.

```
┌───────────────────────────────────────────────┐
│ 1. Gatebar (app)       AppKit + SwiftUI       │  ícono, menú, Ajustes
├───────────────────────────────────────────────┤
│ 2. GatebarProviders    un archivo por tipo    │  VPN OpenConnect, bastión AWS
├───────────────────────────────────────────────┤
│ 3. GatebarCore         sin interfaz           │  perfiles, validación, Llavero,
│                                               │  shell, red, contrato Gateway
├═══════════════ límite de privilegios ═════════┤  sudo: solo connect / disconnect
│ 4. Helper (root)       scripts sh             │  gatebar-helper, vpnc-script
└───────────────────────────────────────────────┘
```

```
Sources/
├── Gatebar/            capa 1: main, AppDelegate, Settings, StatusIcon
├── GatebarProviders/   capa 2: OpenConnectGateway, AWSBastionGateway, GatewayFactory
└── GatebarCore/        capa 3: Gateway, Profile, Validation, ProfileStore, Keychain, Shell…
Helper/                 capa 4: gatebar-helper, gatebar-vpnc-script, install.sh, uninstall.sh
Tests/                  pruebas de la capa 3
scripts/bundle.sh       arma Gatebar.app
docs/                   seguridad y cómo agregar un proveedor
```

- Todas las puertas cumplen el mismo contrato (`Gateway`): estado, botón principal, acciones extra y qué hacer al arrancar, al cambiar de red y al cerrar. El menú no sabe si es una VPN o un bastión.
- `GatewayFactory` es el único lugar donde se registra un tipo nuevo.
- openconnect necesita root. Gatebar nunca lo ejecuta con argumentos que vengan de la app: los datos de la VPN se copian, con tu clave de administrador, a una carpeta de root, y sudo solo permite `gatebar-helper connect <id>` y `disconnect <id>`. Detalles en [docs/seguridad.md](docs/seguridad.md).

## Desarrollo

```sh
swift build
swift test
shellcheck -s sh Helper/* scripts/bundle.sh
```

El código va en inglés y sin comentarios; la documentación va en español. Más detalles en [CONTRIBUTING.md](CONTRIBUTING.md).

## Desinstalar

```sh
sudo sh Helper/uninstall.sh
rm -rf ~/Applications/Gatebar.app ~/Library/Application\ Support/Gatebar ~/Library/Logs/Gatebar
```

Las contraseñas quedan en el Llavero con el servicio `Gatebar`; bórralas desde Acceso a Llaveros.

## Licencia

[MIT](LICENSE) © 2026 Víctor Mosquera · VM Software
