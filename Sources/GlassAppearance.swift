import AppKit

enum GlassAppearance {
    static func isDark(_ appearance: NSAppearance) -> Bool { appearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua }
    static func base(dark: Bool, solid: Bool) -> NSColor {
        if solid { return NSColor(white:dark ? 0.20 : 0.94,alpha:1) }
        return NSColor(white:dark ? 0.70 : 1,alpha:dark ? 0.14 : 0.32)
    }
    static func wrap(_ content: NSView, size: NSSize) -> NSView {
        let frame = NSRect(origin:.zero,size:size)
        content.frame = frame; content.autoresizingMask = [.width,.height]
        // NSPopover draws the backdrop, arrow and corners as one continuous surface.
        return content
    }
    static func card(_ content: NSView, width: CGFloat, height: CGFloat) -> NSView {
        let box = NSBox(); box.boxType = .custom; box.titlePosition = .noTitle
        box.cornerRadius = 16; box.borderWidth = 0.5
        box.borderColor = .separatorColor
        box.fillColor = NSColor(name:nil) { appearance in
            NSColor(white:isDark(appearance) ? 0.12 : 1,alpha:NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? 1 : 0.65)
        }
        box.contentViewMargins = NSSize(width:14,height:14); box.contentView = content
        box.widthAnchor.constraint(equalToConstant:width).isActive = true
        box.heightAnchor.constraint(equalToConstant:height + 28).isActive = true
        return box
    }
}
