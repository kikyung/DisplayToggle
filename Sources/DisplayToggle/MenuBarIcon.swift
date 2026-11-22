import AppKit

enum MenuBarIcon {
    static func makeImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 19, height: 18), flipped: false) { _ in
            NSColor.black.set()

            // Only draw the parts of the rear display that are visible above or beside the front one.
            let rear = NSBezierPath()
            rear.move(to: NSPoint(x: 6.5, y: 13.7))
            rear.line(to: NSPoint(x: 6.5, y: 14.5))
            rear.curve(to: NSPoint(x: 8, y: 16),
                       controlPoint1: NSPoint(x: 6.5, y: 15.3), controlPoint2: NSPoint(x: 7.2, y: 16))
            rear.line(to: NSPoint(x: 16.5, y: 16))
            rear.curve(to: NSPoint(x: 18, y: 14.5),
                       controlPoint1: NSPoint(x: 17.3, y: 16), controlPoint2: NSPoint(x: 18, y: 15.3))
            rear.line(to: NSPoint(x: 18, y: 9.5))
            rear.curve(to: NSPoint(x: 16.5, y: 8),
                       controlPoint1: NSPoint(x: 18, y: 8.7), controlPoint2: NSPoint(x: 17.3, y: 8))
            rear.line(to: NSPoint(x: 14.7, y: 8))
            rear.lineWidth = 1.3
            rear.lineCapStyle = .round
            rear.stroke()

            let front = NSBezierPath(roundedRect: NSRect(x: 1, y: 4, width: 12, height: 9),
                                     xRadius: 1.5, yRadius: 1.5)
            front.lineWidth = 1.4
            front.stroke()
            NSBezierPath(rect: NSRect(x: 6.3, y: 2, width: 1.4, height: 2)).fill()
            NSBezierPath(roundedRect: NSRect(x: 4.4, y: 1, width: 5.2, height: 1.4),
                         xRadius: 0.7, yRadius: 0.7).fill()

            let toggle = NSBezierPath(roundedRect: NSRect(x: 3.3, y: 6.4, width: 7.4, height: 4.2),
                                      xRadius: 2.1, yRadius: 2.1)
            toggle.appendOval(in: NSRect(x: 7.1, y: 7.1, width: 2.8, height: 2.8))
            toggle.windingRule = .evenOdd
            toggle.fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "DisplayToggle"
        return image
    }
}
