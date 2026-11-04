# Cómo agregar un tipo de puerta

Un tipo de puerta (otra VPN, un túnel, un bastión distinto…) es un **proveedor**. Agregar uno toca estos lugares y nada más:

1. **`GatewayKind`** en `Sources/GatebarCore/Profile.swift`: agrega un caso con el valor que se usará en `profiles.json` (por ejemplo `case wireguard = "wireguard"`) y su `displayName`.
2. **Struct de datos** en el mismo archivo: un struct `Codable, Equatable` con los campos que necesita el proveedor, y una propiedad opcional para él en `Profile` (por ejemplo `wireguard: WireGuardSettings?`). Actualiza también `Profile.template(kind:id:name:)`.
3. **Validación** en `Sources/GatebarCore/Validation.swift`: un `validate()` para el struct, llamado desde `Profile.validate()`. Sé estricto con todo lo que termine como argumento de un comando y nunca aceptes valores que empiecen con `-`.
4. **El proveedor** en `Sources/GatebarProviders/`: una clase que cumpla el protocolo `Gateway` (`Sources/GatebarCore/Gateway.swift`). Haz el trabajo lento (procesos, red) en una cola de fondo y llama `onChange` en el hilo principal cuando cambie el estado. `OpenConnectGateway` y `AWSBastionGateway` sirven de referencia.
5. **`GatewayFactory`**: crea tu clase para el nuevo tipo.
6. **Formulario de Ajustes** en `Sources/Gatebar/Settings.swift`: una vista `...Fields` y un caso en `ProfileEditor`.
7. **Pruebas** en `Tests/GatebarCoreTests/` para la lectura del JSON y la validación, y un ejemplo en `examples/profiles.example.json`.

Si el proveedor necesita root, amplía `Helper/gatebar-helper` con las mismas reglas: los datos salen de un archivo de root escrito con aprobación del administrador, y la regla de sudoers solo permite verbos fijos. Mira [seguridad.md](seguridad.md).

## El contrato `Gateway`

| Miembro | Para qué sirve |
|---|---|
| `profile` | El perfil que la creó. |
| `state` | `inactive`, `working`, `active` o `failed`, con un texto de detalle. |
| `shortStatus` | Una o dos palabras para el título del menú ("conectada", "cerrado"). |
| `toggleTitle` / `canToggle` | Texto y disponibilidad del botón principal. |
| `actions` | Entradas extra del submenú (terminales, ver log…). |
| `onChange` / `onAlert` | Los asigna la app: avisar que cambió el estado o mostrar un mensaje. |
| `start()` | Se llama una vez al crearla: retomar lo que haya quedado abierto. |
| `toggle()` | Abrir o cerrar. |
| `networkDidChange()` | El Mac cambió de red. |
| `shutdown()` | La app se cierra o el perfil se borró: cerrar lo que esté abierto. |
