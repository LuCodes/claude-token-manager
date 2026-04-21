import AppKit
import QuartzCore
import SwiftUI

final class BurstIconView: NSView {

    private let crossLayer = CAShapeLayer()
    private let diagonalLayer = CAShapeLayer()
    private let centerLayer = CAShapeLayer()

    private let animationKey = "claudeBurstBreathing"

    /// When non-nil, overrides the appearance-driven `labelColor`.
    /// Useful inside dark surfaces like the dropdown header.
    var tintOverride: NSColor? {
        didSet { applyTintColor() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setupLayers()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var wantsUpdateLayer: Bool { true }

    private func setupLayers() {
        guard let rootLayer = layer else { return }

        rootLayer.addSublayer(crossLayer)
        rootLayer.addSublayer(diagonalLayer)
        rootLayer.addSublayer(centerLayer)

        crossLayer.strokeColor = nil
        diagonalLayer.strokeColor = nil
        centerLayer.strokeColor = nil

        crossLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        diagonalLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        centerLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)

        applyTintColor()
    }

    override func layout() {
        super.layout()
        let bounds = self.bounds

        crossLayer.frame = bounds
        diagonalLayer.frame = bounds
        centerLayer.frame = bounds

        crossLayer.path = makeCrossPath(in: bounds).compatCGPath
        diagonalLayer.path = makeDiagonalPath(in: bounds).compatCGPath
        centerLayer.path = makeCenterPath(in: bounds).compatCGPath
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTintColor()
    }

    // MARK: - Path generation

    private func makeCrossPath(in bounds: CGRect) -> NSBezierPath {
        let w = bounds.width
        let cx = w / 2
        let cy = bounds.height / 2

        let rayLength = w * 0.25
        let rayWidth = w * 0.07
        let rayOffset = w * 0.08
        let radius = rayWidth / 2

        let path = NSBezierPath()

        path.append(NSBezierPath(
            roundedRect: CGRect(
                x: cx - rayWidth / 2,
                y: cy + rayOffset,
                width: rayWidth,
                height: rayLength
            ),
            xRadius: radius,
            yRadius: radius
        ))

        path.append(NSBezierPath(
            roundedRect: CGRect(
                x: cx - rayWidth / 2,
                y: cy - rayOffset - rayLength,
                width: rayWidth,
                height: rayLength
            ),
            xRadius: radius,
            yRadius: radius
        ))

        path.append(NSBezierPath(
            roundedRect: CGRect(
                x: cx - rayOffset - rayLength,
                y: cy - rayWidth / 2,
                width: rayLength,
                height: rayWidth
            ),
            xRadius: radius,
            yRadius: radius
        ))

        path.append(NSBezierPath(
            roundedRect: CGRect(
                x: cx + rayOffset,
                y: cy - rayWidth / 2,
                width: rayLength,
                height: rayWidth
            ),
            xRadius: radius,
            yRadius: radius
        ))

        return path
    }

    private func makeDiagonalPath(in bounds: CGRect) -> NSBezierPath {
        let w = bounds.width
        let cx = w / 2
        let cy = bounds.height / 2

        let rayLength = w * 0.22
        let rayWidth = w * 0.07
        let rayOffset = w * 0.09
        let radius = rayWidth / 2

        let path = NSBezierPath()

        func addDiagonalRay(angle: CGFloat) {
            let ray = NSBezierPath(
                roundedRect: CGRect(
                    x: cx - rayWidth / 2,
                    y: cy + rayOffset,
                    width: rayWidth,
                    height: rayLength
                ),
                xRadius: radius,
                yRadius: radius
            )

            var transform = AffineTransform.identity
            transform.translate(x: cx, y: cy)
            transform.rotate(byDegrees: angle)
            transform.translate(x: -cx, y: -cy)
            ray.transform(using: transform)

            path.append(ray)
        }

        addDiagonalRay(angle: 45)
        addDiagonalRay(angle: -45)
        addDiagonalRay(angle: 135)
        addDiagonalRay(angle: -135)

        return path
    }

    private func makeCenterPath(in bounds: CGRect) -> NSBezierPath {
        let w = bounds.width
        let cx = w / 2
        let cy = bounds.height / 2
        let radius = w * 0.05

        return NSBezierPath(
            ovalIn: CGRect(
                x: cx - radius,
                y: cy - radius,
                width: radius * 2,
                height: radius * 2
            )
        )
    }

    // MARK: - Animation

    func startBreathingAnimation() {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            return
        }
        guard crossLayer.animation(forKey: animationKey) == nil else { return }

        let totalDuration: CFTimeInterval = 2.4
        let easing = CAMediaTimingFunction(name: .easeInEaseOut)
        let timingFunctions = [easing, easing, easing, easing]

        let crossOpacity = CAKeyframeAnimation(keyPath: "opacity")
        crossOpacity.values = [1.0, 1.0, 1.0, 0.0, 1.0]
        crossOpacity.keyTimes = [0.0, 0.25, 0.5, 0.75, 1.0]
        crossOpacity.duration = totalDuration
        crossOpacity.repeatCount = .infinity
        crossOpacity.timingFunctions = timingFunctions

        let crossScale = CAKeyframeAnimation(keyPath: "transform.scale")
        crossScale.values = [1.0, 1.0, 1.0, 0.5, 1.0]
        crossScale.keyTimes = [0.0, 0.25, 0.5, 0.75, 1.0]
        crossScale.duration = totalDuration
        crossScale.repeatCount = .infinity
        crossScale.timingFunctions = timingFunctions

        let crossGroup = CAAnimationGroup()
        crossGroup.animations = [crossOpacity, crossScale]
        crossGroup.duration = totalDuration
        crossGroup.repeatCount = .infinity

        crossLayer.add(crossGroup, forKey: animationKey)

        let diagOpacity = CAKeyframeAnimation(keyPath: "opacity")
        diagOpacity.values = [1.0, 0.0, 1.0, 1.0, 1.0]
        diagOpacity.keyTimes = [0.0, 0.25, 0.5, 0.75, 1.0]
        diagOpacity.duration = totalDuration
        diagOpacity.repeatCount = .infinity
        diagOpacity.timingFunctions = timingFunctions

        let diagScale = CAKeyframeAnimation(keyPath: "transform.scale")
        diagScale.values = [1.0, 0.5, 1.0, 1.0, 1.0]
        diagScale.keyTimes = [0.0, 0.25, 0.5, 0.75, 1.0]
        diagScale.duration = totalDuration
        diagScale.repeatCount = .infinity
        diagScale.timingFunctions = timingFunctions

        let diagGroup = CAAnimationGroup()
        diagGroup.animations = [diagOpacity, diagScale]
        diagGroup.duration = totalDuration
        diagGroup.repeatCount = .infinity

        diagonalLayer.add(diagGroup, forKey: animationKey)
    }

    func stopBreathingAnimation() {
        crossLayer.removeAnimation(forKey: animationKey)
        diagonalLayer.removeAnimation(forKey: animationKey)
    }

    // MARK: - Tint

    private func applyTintColor() {
        // In the menu bar, NSColor.labelColor resolved on a CAShapeLayer comes
        // out as a muted gray while NSTextField next to us renders its
        // labelColor as full white — they disagree visually. Since this view
        // only runs in the (always dark-appearance) macOS menu bar for this
        // app, fall back to pure white for parity with the percent label.
        let resolved = (tintOverride ?? NSColor.white).cgColor
        crossLayer.fillColor = resolved
        diagonalLayer.fillColor = resolved
        centerLayer.fillColor = resolved
    }
}

// MARK: - SwiftUI bridge

struct BurstIconRepresentable: NSViewRepresentable {
    var tint: NSColor?

    func makeNSView(context: Context) -> BurstIconView {
        let view = BurstIconView(frame: .zero)
        view.tintOverride = tint
        return view
    }

    func updateNSView(_ nsView: BurstIconView, context: Context) {
        nsView.tintOverride = tint
    }
}

// MARK: - NSBezierPath → CGPath (macOS 13 compat)

private extension NSBezierPath {
    var compatCGPath: CGPath {
        if #available(macOS 14, *) { return self.cgPath }
        let path = CGMutablePath()
        var points = [CGPoint](repeating: .zero, count: 3)
        for i in 0..<elementCount {
            switch element(at: i, associatedPoints: &points) {
            case .moveTo:
                path.move(to: points[0])
            case .lineTo:
                path.addLine(to: points[0])
            case .curveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePath:
                path.closeSubpath()
            default:
                break
            }
        }
        return path
    }
}
