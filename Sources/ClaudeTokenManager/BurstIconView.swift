import AppKit
import QuartzCore
import SwiftUI

final class BurstIconView: NSView {

    private let crossLayer = CAShapeLayer()
    private let diagonalLayer = CAShapeLayer()
    private let centerLayer = CAShapeLayer()

    private let animationKey = "claudeBurstBreathing"

    // Cache the last bounds the paths were generated for. Status bar items
    // are resized whenever the percent label changes width — without this
    // cache, every relayout rebuilt all three NSBezierPaths from scratch,
    // and (worse) marked the menu bar item as needing a new shadow image,
    // which goes through expensive vImage Gaussian convolution on macOS.
    private var lastPathBounds: CGRect = .zero

    // Discrete-step pulse driven by a Timer — see startBreathingAnimation()
    // for why this replaced CAAnimation. Each tick toggles between full and
    // dimmed opacity using CATransaction with actions disabled, so the
    // change is instant and produces a single shadow regen per tick.
    private var pulseTimer: Timer?
    private var pulseDimmed: Bool = false

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

        // Skip the path rebuild + shape-layer assignment when nothing about
        // the icon's geometry changed. Reassigning a CAShapeLayer's path
        // dirties the layer hierarchy and forces the menu bar to regenerate
        // the status-item shadow image (Gaussian blur via vImage), which is
        // the dominant CPU cost during a long Claude Code session.
        guard bounds != lastPathBounds else { return }
        lastPathBounds = bounds

        crossLayer.path = Self.makeCrossPath(in: bounds).compatCGPath
        diagonalLayer.path = Self.makeDiagonalPath(in: bounds).compatCGPath
        centerLayer.path = Self.makeCenterPath(in: bounds).compatCGPath
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTintColor()
    }

    // MARK: - Path generation

    /// Renders the burst icon as a template NSImage so it can be assigned to
    /// `NSStatusItem.button.image`. Status bar items render their content
    /// with a system-managed shadow pass; on macOS 26 a layer-backed custom
    /// view in the menu bar triggers that pass at ~30 Hz, pinning ~one CPU
    /// core. Drawing the icon as a flat template image avoids the entire
    /// custom-view path while preserving the look (AppKit retints template
    /// images to match the menu bar appearance).
    static func renderTemplateImage(size: NSSize) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            makeCrossPath(in: rect).fill()
            makeDiagonalPath(in: rect).fill()
            makeCenterPath(in: rect).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    static func makeCrossPath(in bounds: CGRect) -> NSBezierPath {
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

    static func makeDiagonalPath(in bounds: CGRect) -> NSBezierPath {
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

    static func makeCenterPath(in bounds: CGRect) -> NSBezierPath {
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
        guard pulseTimer == nil else { return }

        pulseDimmed = false
        applyPulseOpacity(dimmed: false)
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.pulseDimmed.toggle()
            self.applyPulseOpacity(dimmed: self.pulseDimmed)
        }
    }

    func stopBreathingAnimation() {
        pulseTimer?.invalidate()
        pulseTimer = nil
        applyPulseOpacity(dimmed: false)
    }

    private func applyPulseOpacity(dimmed: Bool) {
        let target: Float = dimmed ? 0.35 : 1.0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        crossLayer.opacity = target
        diagonalLayer.opacity = target
        CATransaction.commit()
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
