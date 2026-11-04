# Modelo de seguridad

Gatebar toca dos cosas delicadas: un cliente de VPN que debe correr como root y reglas de firewall frente a servidores de producción. Aquí se explica cómo se mantiene cada una lo más acotada posible.

## VPNs: nada de comandos libres como root

openconnect necesita root para crear la interfaz del túnel, las rutas y el DNS. Una regla general como `sudo openconnect *` permitiría que cualquier programa que corra con tu usuario ejecute openconnect con cualquier argumento (por ejemplo `--script /tmp/lo-que-sea`), que en la práctica es lo mismo que darle root. Gatebar lo evita así:

1. **Los datos se copian a una carpeta de root.** La primera vez que conectas una VPN, o cuando cambian sus datos, Gatebar le pide a macOS tu clave de administrador y ejecuta `gatebar-helper install-profile <id> <archivo>`. El helper copia el archivo a `/Library/Application Support/Gatebar/vpn/<id>.conf` (root:wheel, 644) y valida cada valor con reglas estrictas: el servidor debe ser `https://…`, ningún valor puede empezar con `-`, solo protocolos conocidos, etc. El archivo se lee línea por línea; nunca se ejecuta.
2. **sudo solo permite dos verbos.** `/etc/sudoers.d/gatebar` deja que tu usuario ejecute sin contraseña únicamente `gatebar-helper connect <id>` y `gatebar-helper disconnect <id>`. El helper lee todo lo demás desde el archivo de root, lo vuelve a validar y lanza openconnect con opciones fijas.
3. **El helper vive en carpetas de root.** `/Library/PrivilegedHelperTools/` pertenece a root, así que un proceso de tu usuario no puede reemplazar el script que sudo ejecuta.
4. **La contraseña no toca el disco ni los argumentos.** Se lee del Llavero y se le pasa a openconnect por la entrada estándar (`--passwd-on-stdin`).
5. **Pin del servidor.** Con `serverCert` (`pin-sha256:…`), otro servidor no puede hacerse pasar por tu VPN.

`connect` escribe `/var/run/gatebar/<id>.pid`. Cuando el túnel sube, el vpnc-script escribe `/var/run/gatebar/<id>.ip`. `disconnect` solo envía la señal a un proceso cuyo nombre sea `openconnect`.

Las mismas reglas de validación están en `Sources/GatebarCore/Validation.swift` y en `Helper/gatebar-helper`. Si cambias una, cambia la otra.

## Bastiones AWS: la menor exposición posible

- La regla se abre solo para tu IP pública actual (`/32`) y en el puerto configurado.
- Cada regla lleva una descripción (por defecto `gatebar-<usuario>`), así Gatebar solo toca sus propias reglas y la de tu IP actual.
- La regla sigue a tu IP: si cambia, la vieja se revoca. También se revoca al cerrar el acceso, al salir de la app y al cumplirse `maxOpenHours`, aunque la app se haya cerrado de golpe en el medio (se revisa al volver a abrirla).
- Gatebar usa las credenciales de tu AWS CLI. Dale a esa identidad solo `ec2:DescribeSecurityGroupRules`, `ec2:AuthorizeSecurityGroupIngress` y `ec2:RevokeSecurityGroupIngress`, idealmente limitados al security group del bastión.

## Qué se guarda y dónde

| Dato | Ubicación |
|---|---|
| Perfiles (sin secretos) | `~/Library/Application Support/Gatebar/profiles.json` (600) |
| Contraseñas | Llavero de inicio de sesión, servicio `Gatebar`, cuenta = id del perfil |
| Datos de VPN para el helper | `/Library/Application Support/Gatebar/vpn/` (root) |
| Logs | `~/Library/Logs/Gatebar/<id>.log` |

## Reportar una vulnerabilidad

No abras un issue público. Usa *Report a vulnerability* en la pestaña Security de este repositorio en GitHub.
