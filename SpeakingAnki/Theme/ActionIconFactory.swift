import UIKit

/// Small programmatic glyphs that remain available on iOS 12.
enum ActionIconFactory {
    enum Kind: String {
        case decks
        case browse
        case cardWalkthrough
        case stats
        case sync
        case settings
        case sidebar
        case sidebarOpen
        case back
        case importFile
        case referenceAudio
        case record
        case playback
        case score
        case undo
        case collapse
        case expand
        case reveal
        case createDeck
        case createSubdeck
        case study
        case customStudy
        case rename
        case moveDeck
        case deckOptions
        case exportDeck
        case exportWithScheduling
        case exportWithoutScheduling
        case delete
        case rebuildFiltered
        case emptyFiltered
    }

    private static let cache = NSCache<NSString, UIImage>()

    static func barItem(kind: Kind, target: Any?, action: Selector, accessibility: String) -> UIBarButtonItem {
        let item = UIBarButtonItem(image: image(kind, pointSize: 18), style: .plain, target: target, action: action)
        item.accessibilityLabel = accessibility
        return item
    }

    static func image(_ kind: Kind, pointSize: CGFloat = 18) -> UIImage {
        let key = "\(kind.rawValue)-\(Int(pointSize * 10))" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let canvas = ceil(pointSize + 8)
        let size = CGSize(width: canvas, height: canvas)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        defer { UIGraphicsEndImageContext() }
        guard let context = UIGraphicsGetCurrentContext() else { return UIImage() }

        UIColor.black.setStroke()
        UIColor.black.setFill()
        context.setLineWidth(1.55)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        let inset = (canvas - pointSize) / 2
        let rect = CGRect(x: inset, y: inset, width: pointSize, height: pointSize)
        func stroke(_ points: [CGPoint], width: CGFloat = 1.55, close: Bool = false) {
            guard let first = points.first else { return }
            let path = UIBezierPath()
            path.move(to: first)
            points.dropFirst().forEach { path.addLine(to: $0) }
            if close { path.close() }
            path.lineWidth = width
            path.stroke()
        }
        func drawPlus(center: CGPoint, radius: CGFloat = 3) {
            stroke([
                CGPoint(x: center.x - radius, y: center.y),
                CGPoint(x: center.x + radius, y: center.y)
            ], width: 1.7)
            stroke([
                CGPoint(x: center.x, y: center.y - radius),
                CGPoint(x: center.x, y: center.y + radius)
            ], width: 1.7)
        }
        func drawDeckBox(_ box: CGRect) {
            let path = UIBezierPath(roundedRect: box, cornerRadius: 1.8)
            path.lineWidth = 1.55
            path.stroke()
            stroke([
                CGPoint(x: box.minX + 2, y: box.minY + 3),
                CGPoint(x: box.maxX - 2, y: box.minY + 3)
            ])
        }
        func drawExportArrow(slash: Bool = false) {
            stroke([
                CGPoint(x: rect.midX, y: rect.maxY - 3),
                CGPoint(x: rect.midX, y: rect.minY + 3),
                CGPoint(x: rect.midX - 3.5, y: rect.minY + 6.5)
            ], width: 1.7)
            stroke([
                CGPoint(x: rect.midX, y: rect.minY + 3),
                CGPoint(x: rect.midX + 3.5, y: rect.minY + 6.5)
            ], width: 1.7)
            stroke([
                CGPoint(x: rect.minX + 2, y: rect.maxY - 6),
                CGPoint(x: rect.minX + 2, y: rect.maxY - 2),
                CGPoint(x: rect.maxX - 2, y: rect.maxY - 2),
                CGPoint(x: rect.maxX - 2, y: rect.maxY - 6)
            ])
            if slash {
                stroke([
                    CGPoint(x: rect.minX + 3, y: rect.minY + 3),
                    CGPoint(x: rect.maxX - 3, y: rect.maxY - 3)
                ], width: 1.8)
            }
        }

        switch kind {
        case .decks:
            let back = UIBezierPath(roundedRect: rect.insetBy(dx: 2.2, dy: 4.2), cornerRadius: 2)
            back.lineWidth = 1.55
            back.stroke()
            let page = UIBezierPath()
            page.move(to: CGPoint(x: rect.minX + 4.5, y: rect.minY + 2.5))
            page.addLine(to: CGPoint(x: rect.maxX - 4.5, y: rect.minY + 2.5))
            page.move(to: CGPoint(x: rect.minX + 5, y: rect.maxY - 2.5))
            page.addLine(to: CGPoint(x: rect.maxX - 5, y: rect.maxY - 2.5))
            page.lineWidth = 1.55
            page.stroke()

        case .browse:
            let circle = UIBezierPath(ovalIn: CGRect(
                x: rect.minX + 2,
                y: rect.minY + 2,
                width: pointSize * 0.56,
                height: pointSize * 0.56
            ))
            circle.lineWidth = 1.55
            circle.stroke()
            let handle = UIBezierPath()
            handle.move(to: CGPoint(x: rect.minX + pointSize * 0.56, y: rect.minY + pointSize * 0.56))
            handle.addLine(to: CGPoint(x: rect.maxX - 2.5, y: rect.maxY - 2.5))
            handle.lineWidth = 1.7
            handle.stroke()

        case .cardWalkthrough:
            let card = UIBezierPath(roundedRect: CGRect(
                x: rect.minX + 2,
                y: rect.minY + 3,
                width: pointSize * 0.62,
                height: pointSize * 0.70
            ), cornerRadius: 2)
            card.lineWidth = 1.55
            card.stroke()
            stroke([
                CGPoint(x: rect.minX + 5, y: rect.minY + 7),
                CGPoint(x: rect.minX + pointSize * 0.48, y: rect.minY + 7)
            ])
            stroke([
                CGPoint(x: rect.minX + pointSize * 0.55, y: rect.midY),
                CGPoint(x: rect.maxX - 2, y: rect.midY),
                CGPoint(x: rect.maxX - 5, y: rect.midY - 3)
            ], width: 1.7)
            stroke([
                CGPoint(x: rect.maxX - 2, y: rect.midY),
                CGPoint(x: rect.maxX - 5, y: rect.midY + 3)
            ], width: 1.7)

        case .stats:
            let bars = UIBezierPath()
            bars.move(to: CGPoint(x: rect.minX + 3, y: rect.maxY - 3))
            bars.addLine(to: CGPoint(x: rect.minX + 3, y: rect.midY + 2))
            bars.move(to: CGPoint(x: rect.midX, y: rect.maxY - 3))
            bars.addLine(to: CGPoint(x: rect.midX, y: rect.minY + 3))
            bars.move(to: CGPoint(x: rect.maxX - 3, y: rect.maxY - 3))
            bars.addLine(to: CGPoint(x: rect.maxX - 3, y: rect.midY - 2))
            bars.lineWidth = 2.7
            bars.stroke()

        case .sync:
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius = pointSize * 0.34
            let topArc = UIBezierPath(
                arcCenter: center,
                radius: radius,
                startAngle: -.pi * 0.85,
                endAngle: .pi * 0.15,
                clockwise: true
            )
            topArc.lineWidth = 1.55
            topArc.stroke()
            let bottomArc = UIBezierPath(
                arcCenter: center,
                radius: radius,
                startAngle: .pi * 0.15,
                endAngle: .pi * 1.15,
                clockwise: true
            )
            bottomArc.lineWidth = 1.55
            bottomArc.stroke()
            let arrows = UIBezierPath()
            arrows.move(to: CGPoint(x: rect.maxX - 2.5, y: rect.midY - 2))
            arrows.addLine(to: CGPoint(x: rect.maxX - 5.8, y: rect.midY - 5.2))
            arrows.move(to: CGPoint(x: rect.minX + 2.5, y: rect.midY + 2))
            arrows.addLine(to: CGPoint(x: rect.minX + 5.8, y: rect.midY + 5.2))
            arrows.lineWidth = 1.55
            arrows.stroke()

        case .settings:
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let outer = UIBezierPath(ovalIn: CGRect(x: center.x - 5.5, y: center.y - 5.5, width: 11, height: 11))
            outer.lineWidth = 1.55
            outer.stroke()
            UIBezierPath(ovalIn: CGRect(x: center.x - 2, y: center.y - 2, width: 4, height: 4)).stroke()
            for index in 0..<6 {
                let angle = CGFloat(index) * .pi / 3
                let start = CGPoint(x: center.x + 5.2 * cos(angle), y: center.y + 5.2 * sin(angle))
                let end = CGPoint(x: center.x + 7.2 * cos(angle), y: center.y + 7.2 * sin(angle))
                let tooth = UIBezierPath()
                tooth.move(to: start)
                tooth.addLine(to: end)
                tooth.lineWidth = 1.8
                tooth.stroke()
            }

        case .sidebar, .sidebarOpen:
            let outer = UIBezierPath(roundedRect: rect.insetBy(dx: 1.5, dy: 2.2), cornerRadius: 2.5)
            outer.lineWidth = 1.55
            outer.stroke()
            let railX = rect.minX + pointSize * 0.39
            let rail = UIBezierPath()
            rail.move(to: CGPoint(x: railX, y: rect.minY + 2.2))
            rail.addLine(to: CGPoint(x: railX, y: rect.maxY - 2.2))
            rail.lineWidth = 1.55
            rail.stroke()
            if kind == .sidebarOpen {
                let chevron = UIBezierPath()
                chevron.move(to: CGPoint(x: rect.midX + 2.8, y: rect.midY - 3.5))
                chevron.addLine(to: CGPoint(x: rect.midX - 0.8, y: rect.midY))
                chevron.addLine(to: CGPoint(x: rect.midX + 2.8, y: rect.midY + 3.5))
                chevron.lineWidth = 1.55
                chevron.stroke()
            }

        case .back:
            let arrow = UIBezierPath()
            arrow.move(to: CGPoint(x: rect.maxX - 2, y: rect.midY))
            arrow.addLine(to: CGPoint(x: rect.minX + 4, y: rect.midY))
            arrow.move(to: CGPoint(x: rect.minX + 4, y: rect.midY))
            arrow.addLine(to: CGPoint(x: rect.minX + 9, y: rect.midY - 5))
            arrow.move(to: CGPoint(x: rect.minX + 4, y: rect.midY))
            arrow.addLine(to: CGPoint(x: rect.minX + 9, y: rect.midY + 5))
            arrow.lineWidth = 1.7
            arrow.stroke()

        case .importFile:
            let tray = UIBezierPath()
            tray.move(to: CGPoint(x: rect.minX + 2, y: rect.maxY - 6))
            tray.addLine(to: CGPoint(x: rect.minX + 2, y: rect.maxY - 2))
            tray.addLine(to: CGPoint(x: rect.maxX - 2, y: rect.maxY - 2))
            tray.addLine(to: CGPoint(x: rect.maxX - 2, y: rect.maxY - 6))
            tray.lineWidth = 1.55
            tray.stroke()
            let arrow = UIBezierPath()
            arrow.move(to: CGPoint(x: rect.midX, y: rect.minY + 2))
            arrow.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - 7))
            arrow.move(to: CGPoint(x: rect.midX, y: rect.maxY - 7))
            arrow.addLine(to: CGPoint(x: rect.midX - 4, y: rect.maxY - 11))
            arrow.move(to: CGPoint(x: rect.midX, y: rect.maxY - 7))
            arrow.addLine(to: CGPoint(x: rect.midX + 4, y: rect.maxY - 11))
            arrow.lineWidth = 1.7
            arrow.stroke()

        case .referenceAudio, .playback:
            let speaker = UIBezierPath()
            speaker.move(to: CGPoint(x: rect.minX + 2, y: rect.midY - 2.5))
            speaker.addLine(to: CGPoint(x: rect.minX + 5.5, y: rect.midY - 2.5))
            speaker.addLine(to: CGPoint(x: rect.midX - 0.5, y: rect.midY - 6))
            speaker.addLine(to: CGPoint(x: rect.midX - 0.5, y: rect.midY + 6))
            speaker.addLine(to: CGPoint(x: rect.minX + 5.5, y: rect.midY + 2.5))
            speaker.addLine(to: CGPoint(x: rect.minX + 2, y: rect.midY + 2.5))
            speaker.close()
            speaker.lineWidth = 1.55
            speaker.stroke()
            let wave = UIBezierPath(
                arcCenter: CGPoint(x: rect.midX, y: rect.midY),
                radius: pointSize * 0.34,
                startAngle: -.pi / 3,
                endAngle: .pi / 3,
                clockwise: true
            )
            wave.lineWidth = 1.55
            wave.stroke()
            if kind == .playback {
                let triangle = UIBezierPath()
                triangle.move(to: CGPoint(x: rect.maxX - 5.5, y: rect.midY - 3))
                triangle.addLine(to: CGPoint(x: rect.maxX - 1, y: rect.midY))
                triangle.addLine(to: CGPoint(x: rect.maxX - 5.5, y: rect.midY + 3))
                triangle.close()
                triangle.fill()
            }

        case .record:
            UIBezierPath(ovalIn: rect.insetBy(dx: 4.5, dy: 4.5)).fill()
            let ring = UIBezierPath(ovalIn: rect.insetBy(dx: 1.5, dy: 1.5))
            ring.lineWidth = 1.4
            ring.stroke()

        case .score:
            let star = UIBezierPath()
            let center = CGPoint(x: rect.midX, y: rect.midY)
            for index in 0..<10 {
                let radius = index.isMultiple(of: 2) ? pointSize * 0.43 : pointSize * 0.19
                let angle = -.pi / 2 + CGFloat(index) * .pi / 5
                let point = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
                if index == 0 {
                    star.move(to: point)
                } else {
                    star.addLine(to: point)
                }
            }
            star.close()
            star.lineWidth = 1.55
            star.stroke()

        case .undo:
            let arrow = UIBezierPath()
            arrow.move(to: CGPoint(x: rect.minX + 2, y: rect.midY - 1))
            arrow.addLine(to: CGPoint(x: rect.minX + 6, y: rect.midY - 5))
            arrow.move(to: CGPoint(x: rect.minX + 2, y: rect.midY - 1))
            arrow.addLine(to: CGPoint(x: rect.minX + 6, y: rect.midY + 3))
            arrow.move(to: CGPoint(x: rect.minX + 3, y: rect.midY - 1))
            arrow.addCurve(
                to: CGPoint(x: rect.maxX - 2, y: rect.midY + 5),
                controlPoint1: CGPoint(x: rect.midX + 1, y: rect.minY + 1),
                controlPoint2: CGPoint(x: rect.maxX - 1, y: rect.midY)
            )
            arrow.lineWidth = 1.7
            arrow.stroke()

        case .collapse, .expand:
            let chevron = UIBezierPath()
            let points: [CGPoint]
            if kind == .collapse {
                points = [
                    CGPoint(x: rect.minX + 3, y: rect.midY + 3),
                    CGPoint(x: rect.midX, y: rect.midY - 3),
                    CGPoint(x: rect.maxX - 3, y: rect.midY + 3)
                ]
            } else {
                points = [
                    CGPoint(x: rect.minX + 3, y: rect.midY - 3),
                    CGPoint(x: rect.midX, y: rect.midY + 3),
                    CGPoint(x: rect.maxX - 3, y: rect.midY - 3)
                ]
            }
            chevron.move(to: points[0])
            chevron.addLine(to: points[1])
            chevron.addLine(to: points[2])
            chevron.lineWidth = 1.7
            chevron.stroke()

        case .reveal:
            let eye = UIBezierPath()
            eye.move(to: CGPoint(x: rect.minX + 1, y: rect.midY))
            eye.addCurve(
                to: CGPoint(x: rect.maxX - 1, y: rect.midY),
                controlPoint1: CGPoint(x: rect.minX + 5, y: rect.minY + 3),
                controlPoint2: CGPoint(x: rect.maxX - 5, y: rect.minY + 3)
            )
            eye.addCurve(
                to: CGPoint(x: rect.minX + 1, y: rect.midY),
                controlPoint1: CGPoint(x: rect.maxX - 5, y: rect.maxY - 3),
                controlPoint2: CGPoint(x: rect.minX + 5, y: rect.maxY - 3)
            )
            eye.lineWidth = 1.55
            eye.stroke()
            UIBezierPath(ovalIn: CGRect(x: rect.midX - 2.2, y: rect.midY - 2.2, width: 4.4, height: 4.4)).fill()

        case .createDeck:
            drawDeckBox(rect.insetBy(dx: 2, dy: 4))
            drawPlus(center: CGPoint(x: rect.maxX - 3, y: rect.minY + 3), radius: 2.5)

        case .createSubdeck:
            drawDeckBox(CGRect(
                x: rect.minX + 1,
                y: rect.minY + 2,
                width: pointSize * 0.64,
                height: pointSize * 0.58
            ))
            drawDeckBox(CGRect(
                x: rect.minX + pointSize * 0.34,
                y: rect.minY + pointSize * 0.42,
                width: pointSize * 0.62,
                height: pointSize * 0.52
            ))
            drawPlus(center: CGPoint(x: rect.maxX - 2, y: rect.minY + 2), radius: 2.2)

        case .study:
            drawDeckBox(rect.insetBy(dx: 2, dy: 3))
            let play = UIBezierPath()
            play.move(to: CGPoint(x: rect.midX - 2.5, y: rect.midY - 4))
            play.addLine(to: CGPoint(x: rect.midX + 4.5, y: rect.midY))
            play.addLine(to: CGPoint(x: rect.midX - 2.5, y: rect.midY + 4))
            play.close()
            play.fill()

        case .customStudy:
            let clock = UIBezierPath(ovalIn: rect.insetBy(dx: 2.5, dy: 2.5))
            clock.lineWidth = 1.55
            clock.stroke()
            stroke([
                CGPoint(x: rect.midX, y: rect.midY),
                CGPoint(x: rect.midX, y: rect.minY + 5)
            ])
            stroke([
                CGPoint(x: rect.midX, y: rect.midY),
                CGPoint(x: rect.midX + 4, y: rect.midY + 2)
            ])
            drawPlus(center: CGPoint(x: rect.maxX - 2.5, y: rect.minY + 3), radius: 2.4)

        case .rename:
            stroke([
                CGPoint(x: rect.minX + 3, y: rect.maxY - 4),
                CGPoint(x: rect.minX + 5, y: rect.maxY - 9),
                CGPoint(x: rect.maxX - 4, y: rect.minY + 2),
                CGPoint(x: rect.maxX - 1.5, y: rect.minY + 4.5),
                CGPoint(x: rect.minX + 7.5, y: rect.maxY - 6.5),
                CGPoint(x: rect.minX + 3, y: rect.maxY - 4)
            ], close: true)
            stroke([
                CGPoint(x: rect.minX + 2, y: rect.maxY - 2),
                CGPoint(x: rect.maxX - 3, y: rect.maxY - 2)
            ])

        case .moveDeck:
            drawDeckBox(rect.insetBy(dx: 2, dy: 3.5))
            stroke([
                CGPoint(x: rect.minX + 5, y: rect.midY),
                CGPoint(x: rect.maxX - 4, y: rect.midY),
                CGPoint(x: rect.maxX - 7, y: rect.midY - 3)
            ], width: 1.7)
            stroke([
                CGPoint(x: rect.maxX - 4, y: rect.midY),
                CGPoint(x: rect.maxX - 7, y: rect.midY + 3)
            ], width: 1.7)

        case .deckOptions:
            for offset in [CGFloat(4), rect.midY - rect.minY, pointSize - 4] {
                let y = rect.minY + offset
                stroke([
                    CGPoint(x: rect.minX + 2, y: y),
                    CGPoint(x: rect.maxX - 2, y: y)
                ])
            }
            for point in [
                CGPoint(x: rect.minX + 7, y: rect.minY + 4),
                CGPoint(x: rect.maxX - 7, y: rect.midY),
                CGPoint(x: rect.midX, y: rect.maxY - 4)
            ] {
                UIBezierPath(ovalIn: CGRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4)).fill()
            }

        case .exportDeck:
            drawExportArrow()

        case .exportWithScheduling:
            drawExportArrow()
            let badge = UIBezierPath(ovalIn: CGRect(x: rect.minX, y: rect.minY, width: 7, height: 7))
            badge.lineWidth = 1.35
            badge.stroke()
            stroke([
                CGPoint(x: rect.minX + 3.5, y: rect.minY + 3.5),
                CGPoint(x: rect.minX + 3.5, y: rect.minY + 1.5)
            ], width: 1.2)

        case .exportWithoutScheduling:
            drawExportArrow(slash: true)

        case .delete:
            let bin = UIBezierPath(roundedRect: CGRect(
                x: rect.minX + 4,
                y: rect.minY + 6,
                width: pointSize - 8,
                height: pointSize - 8
            ), cornerRadius: 1.5)
            bin.lineWidth = 1.55
            bin.stroke()
            stroke([
                CGPoint(x: rect.minX + 2.5, y: rect.minY + 5),
                CGPoint(x: rect.maxX - 2.5, y: rect.minY + 5)
            ], width: 1.8)
            stroke([
                CGPoint(x: rect.midX - 3, y: rect.minY + 2.5),
                CGPoint(x: rect.midX + 3, y: rect.minY + 2.5)
            ])
            stroke([
                CGPoint(x: rect.midX - 2.5, y: rect.minY + 9),
                CGPoint(x: rect.midX - 2.5, y: rect.maxY - 4)
            ])
            stroke([
                CGPoint(x: rect.midX + 2.5, y: rect.minY + 9),
                CGPoint(x: rect.midX + 2.5, y: rect.maxY - 4)
            ])

        case .rebuildFiltered:
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let top = UIBezierPath(
                arcCenter: center, radius: pointSize * 0.35,
                startAngle: -.pi * 0.85, endAngle: .pi * 0.15, clockwise: true
            )
            top.lineWidth = 1.55
            top.stroke()
            let bottom = UIBezierPath(
                arcCenter: center, radius: pointSize * 0.35,
                startAngle: .pi * 0.15, endAngle: .pi * 1.15, clockwise: true
            )
            bottom.lineWidth = 1.55
            bottom.stroke()
            stroke([
                CGPoint(x: rect.maxX - 2, y: rect.midY - 2),
                CGPoint(x: rect.maxX - 5, y: rect.midY - 5)
            ])
            stroke([
                CGPoint(x: rect.minX + 2, y: rect.midY + 2),
                CGPoint(x: rect.minX + 5, y: rect.midY + 5)
            ])
            stroke([
                CGPoint(x: rect.midX - 3, y: rect.minY + 5),
                CGPoint(x: rect.midX + 3, y: rect.minY + 5),
                CGPoint(x: rect.midX + 1, y: rect.midY),
                CGPoint(x: rect.midX + 1, y: rect.midY + 3)
            ])

        case .emptyFiltered:
            stroke([
                CGPoint(x: rect.minX + 2, y: rect.minY + 3),
                CGPoint(x: rect.maxX - 2, y: rect.minY + 3),
                CGPoint(x: rect.midX + 2, y: rect.midY),
                CGPoint(x: rect.midX + 2, y: rect.maxY - 4),
                CGPoint(x: rect.midX - 2, y: rect.maxY - 2),
                CGPoint(x: rect.midX - 2, y: rect.midY),
                CGPoint(x: rect.minX + 2, y: rect.minY + 3)
            ], close: true)
            stroke([
                CGPoint(x: rect.minX + 3, y: rect.maxY - 4),
                CGPoint(x: rect.maxX - 3, y: rect.minY + 4)
            ], width: 1.8)
        }

        let result = (UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()).withRenderingMode(.alwaysTemplate)
        cache.setObject(result, forKey: key)
        return result
    }
}
