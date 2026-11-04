import AppKit

enum StatusIcon {
    static func make(badge: NSColor?) -> NSImage {
        let symbol = NSImage(systemSymbolName: "door.left.hand.open", accessibilityDescription: "Gatebar")
            ?? NSImage(systemSymbolName: "shield", accessibilityDescription: "Gatebar")
        guard let badge else {
            let image = symbol ?? NSImage()
            image.isTemplate = true
            return image
        }
        let image = NSImage(size: NSSize(width: 20, height: 18), flipped: false) { rect in
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
                .applying(NSImage.SymbolConfiguration(paletteColors: [.labelColor]))
            if let glyph = symbol?.withSymbolConfiguration(config) {
                let size = glyph.size
                glyph.draw(in: NSRect(x: 1, y: (rect.height - size.height) / 2 + 1,
                                      width: size.width, height: size.height))
            }
            let dotRect = NSRect(x: rect.width - 9, y: 0.5, width: 8, height: 8)
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: dotRect.insetBy(dx: -1.5, dy: -1.5)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            badge.setFill()
            NSBezierPath(ovalIn: dotRect).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}
