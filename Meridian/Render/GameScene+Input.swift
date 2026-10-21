import SpriteKit
import MeridianCore
#if os(iOS)
import UIKit
#else
import AppKit
#endif

extension GameScene {

    // Shared handlers (view coordinates).

    func handleTap(_ p: CGPoint) {
        let (x, y) = worldPoint(fromView: p)
        ctl.tap(worldX: x, y: y, zoom: Double(zoom))
    }

    func handleDoubleTap(_ p: CGPoint) {
        let (x, y) = worldPoint(fromView: p)
        if let e = ctl.pick(x, y, radius: 0.9), e.owner == ctl.me { ctl.selectSameType(as: e, visibleOnly: visibleWorldQuad()) }
    }

    func pan(by d: CGPoint) {
        battleCam.manualOverride()
        cam.position.x -= d.x * zoom
        cam.position.y += d.y * zoom
        clampCamera()
    }

    func zoom(by factor: CGFloat, around p: CGPoint?) {
        battleCam.manualOverride()
        let before = p.map { convertPoint(fromView: $0) }
        zoom /= factor
        applyZoom()
        if let p = p, let b = before {
            let after = convertPoint(fromView: p)
            cam.position.x += b.x - after.x
            cam.position.y += b.y - after.y
            clampCamera()
        }
    }

    /// Box selection in view coordinates.
    func updateBox(_ a: CGPoint, _ b: CGPoint) {
        let sa = cam.convert(convertPoint(fromView: a), from: self), sb = cam.convert(convertPoint(fromView: b), from: self)
        let r = CGRect(x: min(sa.x, sb.x), y: min(sa.y, sb.y), width: abs(sa.x - sb.x), height: abs(sa.y - sb.y))
        boxNode.path = CGPath(rect: r, transform: nil)
        boxNode.isHidden = false
    }

    func finishBox(_ a: CGPoint, _ b: CGPoint) {
        boxNode.isHidden = true
        let corners = [CGPoint(x: a.x, y: a.y), CGPoint(x: b.x, y: a.y), CGPoint(x: b.x, y: b.y), CGPoint(x: a.x, y: b.y)].map { worldPoint(fromView: $0) }
        if hypot(a.x - b.x, a.y - b.y) < 8 { handleTap(a); return }
        ctl.selectBox((0, 0), (0, 0), corners: corners)
    }

    var placing: Bool { if case .place = ctl.mode { return true }; return false }
}

#if os(iOS)
extension GameScene: UIGestureRecognizerDelegate {
    /// Hold time (seconds) before a still finger switches from box-select to free camera movement.
    static let holdToPanDelay: TimeInterval = 0.4

    /// "Drag to select" (default): one-finger drag box-selects; touch-and-hold then drag pans the camera.
    /// Classic: one-finger drag pans; touch-and-hold then drag box-selects. Two fingers always pan.
    var dragSelects: Bool { UserDefaults.standard.object(forKey: "input.dragSelects") as? Bool ?? true }

    func setupTouch(_ view: SKView) {
        let tap = UITapGestureRecognizer(target: self, action: #selector(onTap(_:)))
        let dbl = UITapGestureRecognizer(target: self, action: #selector(onDoubleTap(_:)))
        dbl.numberOfTapsRequired = 2
        tap.require(toFail: dbl)
        let long = UILongPressGestureRecognizer(target: self, action: #selector(onLong(_:)))
        long.minimumPressDuration = GameScene.holdToPanDelay
        long.allowableMovement = 10
        let drag = UIPanGestureRecognizer(target: self, action: #selector(onDrag(_:)))
        drag.minimumNumberOfTouches = 1
        drag.maximumNumberOfTouches = 1
        drag.require(toFail: long)
        let twoFinger = UIPanGestureRecognizer(target: self, action: #selector(onTwoFingerPan(_:)))
        twoFinger.minimumNumberOfTouches = 2
        twoFinger.maximumNumberOfTouches = 2
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(onPinch(_:)))
        for g in [tap, dbl, long, drag, twoFinger, pinch] as [UIGestureRecognizer] { g.delegate = self; view.addGestureRecognizer(g) }
        dbl.delaysTouchesEnded = false
    }

    public func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith o: UIGestureRecognizer) -> Bool {
        (g is UIPinchGestureRecognizer && o is UIPanGestureRecognizer) || (o is UIPinchGestureRecognizer && g is UIPanGestureRecognizer)
    }

    @objc func onTap(_ g: UITapGestureRecognizer) { handleTap(g.location(in: view)) }
    @objc func onDoubleTap(_ g: UITapGestureRecognizer) { handleDoubleTap(g.location(in: view)) }

    // Box selection, shared by both control schemes.
    func boxGesture(_ state: UIGestureRecognizer.State, _ p: CGPoint) {
        switch state {
        case .began: boxStart = p; updateBox(p, p)
        case .changed: if let s = boxStart { updateBox(s, p) }
        case .ended: if let s = boxStart { finishBox(s, p) }; boxStart = nil
        default: boxNode.isHidden = true; boxStart = nil
        }
    }

    // Camera drag, shared by both control schemes.
    func panGesture(_ state: UIGestureRecognizer.State, _ p: CGPoint) {
        switch state {
        case .began: lastPanPoint = p
        case .changed:
            if let l = lastPanPoint { pan(by: CGPoint(x: p.x - l.x, y: p.y - l.y)) }
            lastPanPoint = p
        default: lastPanPoint = nil
        }
    }

    /// One finger, moving right away.
    @objc func onDrag(_ g: UIPanGestureRecognizer) {
        let p = g.location(in: view)
        if placing { let (x, y) = worldPoint(fromView: p); ctl.moveGhost(worldX: x, y: y); return }
        if dragSelects { boxGesture(g.state, p) } else { panGesture(g.state, p) }
    }

    /// One finger, held still first, then moving.
    @objc func onLong(_ g: UILongPressGestureRecognizer) {
        let p = g.location(in: view)
        if placing { let (x, y) = worldPoint(fromView: p); ctl.moveGhost(worldX: x, y: y); return }
        if g.state == .began { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        if dragSelects { panGesture(g.state, p) } else { boxGesture(g.state, p) }
    }

    @objc func onTwoFingerPan(_ g: UIPanGestureRecognizer) {
        let t = g.translation(in: view)
        pan(by: t)
        g.setTranslation(.zero, in: view)
    }

    @objc func onPinch(_ g: UIPinchGestureRecognizer) {
        zoom(by: g.scale, around: g.location(in: view))
        g.scale = 1
    }
}
#else
extension GameScene {
    func setupTouch(_ view: SKView) {}

    override func mouseDown(with e: NSEvent) {
        guard let v = view else { return }
        let p = v.convert(e.locationInWindow, from: nil)
        let vp = CGPoint(x: p.x, y: v.bounds.height - p.y)
        if placing { let (x, y) = worldPoint(fromView: vp); ctl.moveGhost(worldX: x, y: y); return }
        if e.clickCount == 2 { handleDoubleTap(vp); return }
        boxStart = vp
    }

    override func mouseDragged(with e: NSEvent) {
        guard let v = view else { return }
        let p = v.convert(e.locationInWindow, from: nil)
        let vp = CGPoint(x: p.x, y: v.bounds.height - p.y)
        if placing { let (x, y) = worldPoint(fromView: vp); ctl.moveGhost(worldX: x, y: y); return }
        if let s = boxStart { updateBox(s, vp) }
    }

    override func mouseUp(with e: NSEvent) {
        guard let v = view else { return }
        let p = v.convert(e.locationInWindow, from: nil)
        let vp = CGPoint(x: p.x, y: v.bounds.height - p.y)
        if placing { ctl.confirmPlacement(); return }
        if let s = boxStart {
            if hypot(s.x - vp.x, s.y - vp.y) < 6 {
                // Left click selects (never commands) on desktop.
                let (x, y) = worldPoint(fromView: vp)
                if ctl.mode != .normal { ctl.tap(worldX: x, y: y, zoom: Double(zoom)) }
                else if let h = ctl.pick(x, y, radius: 0.8) { ctl.select([h.id]) }
                else if let si = ctl.pickSite(x, y) { ctl.selectSite(si) }
                else { ctl.clearSelection() }
                boxNode.isHidden = true
            } else { finishBox(s, vp) }
        }
        boxStart = nil
    }

    override func rightMouseDown(with e: NSEvent) {
        guard let v = view else { return }
        let p = v.convert(e.locationInWindow, from: nil)
        let vp = CGPoint(x: p.x, y: v.bounds.height - p.y)
        if ctl.mode != .normal { ctl.cancelMode(); return }
        let (x, y) = worldPoint(fromView: vp)
        ctl.command(at: x, y: y, target: ctl.pick(x, y, radius: 0.8))
    }

    override func scrollWheel(with e: NSEvent) {
        if e.hasPreciseScrollingDeltas && !e.modifierFlags.contains(.command) {
            pan(by: CGPoint(x: e.scrollingDeltaX, y: e.scrollingDeltaY))
        } else {
            zoom(by: e.scrollingDeltaY > 0 ? 1.1 : 0.9, around: nil)
        }
    }

    override func magnify(with e: NSEvent) { zoom(by: 1 + e.magnification, around: nil) }

    override func keyDown(with e: NSEvent) {
        guard let ch = e.charactersIgnoringModifiers?.lowercased().first else { return }
        let step: CGFloat = 40
        switch e.keyCode {
        case 123: pan(by: CGPoint(x: step, y: 0)); return
        case 124: pan(by: CGPoint(x: -step, y: 0)); return
        case 125: pan(by: CGPoint(x: 0, y: -step)); return
        case 126: pan(by: CGPoint(x: 0, y: step)); return
        default: break
        }
        if let n = Int(String(ch)), (1...9).contains(n) {
            if e.modifierFlags.contains(.command) || e.modifierFlags.contains(.control) { ctl.groupAssign(n) } else { ctl.groupRecall(n) }
            return
        }
        switch ch {
        case "\u{1b}": ctl.cancelMode()
        case " ": ctl.paused.toggle()
        case "w": pan(by: CGPoint(x: 0, y: step))
        case "x": ctl.selectArmy()
        case "i": ctl.selectIdleWorker()
        case "t": ctl.showTech.toggle()
        default:
            if let b = ctl.hud.buttons.first(where: { $0.hotkey == ch && $0.enabled }) { b.action() }
        }
    }
}
#endif

