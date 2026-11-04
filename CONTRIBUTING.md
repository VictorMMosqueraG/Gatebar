# Cómo contribuir a Gatebar

Gracias por ayudar. Se reciben issues y pull requests.

## Compilar y probar

```sh
swift build
swift test
scripts/bundle.sh --install   # app completa en ~/Applications
```

Los scripts del helper son `sh` POSIX. Antes de enviar cambios, corre `shellcheck -s sh Helper/* scripts/bundle.sh`.

## Reglas del proyecto

- **Código en inglés y sin comentarios.** Los nombres de tipos, funciones y variables deben explicar lo que hacen. Lo que necesite explicación va en `docs/`.
- **Documentación en español:** README, docs, CHANGELOG y descripciones de los pull requests.
- **Textos de la interfaz** con `L.t("English", "Español")`. Para agregar otro idioma, amplía `Sources/GatebarCore/Localization.swift`.
- **Sin dependencias externas:** solo Swift, AppKit, SwiftUI y Foundation.
- **Respeta las capas:** la app usa a los proveedores y al núcleo, los proveedores usan al núcleo, y el núcleo no usa a nadie. Mira la sección Arquitectura del [README](README.md).
- **Un proveedor por archivo.** Para tipos nuevos de puerta, sigue [docs/agregar-un-proveedor.md](docs/agregar-un-proveedor.md).
- **Todo lo que corre como root** pasa por `Helper/gatebar-helper` y debe cumplir [docs/seguridad.md](docs/seguridad.md). Esos cambios se revisan con más cuidado.
- **Nunca subas datos reales:** servidores, IPs, usuarios, pines de certificados ni security groups. Usa valores tipo `example.com` en documentación y pruebas.

## Pull requests

- Un tema por PR, con una descripción corta de qué cambió y cómo lo probaste (versión de macOS, protocolo de VPN o configuración de AWS usada).
- El CI debe pasar: `swift build`, `swift test` y shellcheck.
