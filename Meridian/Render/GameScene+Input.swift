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
        // Placing a building: double-tap a spot to build there.
        if placing { ctl.moveGhost(worldX: x, y: y); ctl.confirmPlacement(); return }
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

    /// Drag the building ghost and remember where it is held, so holding it near a screen edge scrolls the map.
    func dragGhost(_ p: CGPoint, held: Bool = true) {
        placeDragPoint = held ? p : nil
        let (x, y) = worldPoint(fromView: p)
        ctl.moveGhost(worldX: x, y: y)
    }

    /// While a building ghost is held near an edge of the visible map (inside the HUD), pan the camera that way
    /// (faster nearer the edge, full speed once over the HUD) and keep the ghost under the finger.
    func edgeScrollWhilePlacing(_ dt: Double) {
        if !placing { placeDragPoint = nil }
        guard let p = placeDragPoint, let v = view else { return }
        let w = v.bounds.width, top = max(0, hudTopY), bottom = min(v.bounds.height, hudBottomY)
        let margin = max(24, min(70, min(w, bottom - top) * 0.12)), speed: CGFloat = 900   // view points per second at the very edge
        func push(_ d: CGFloat) -> CGFloat { d < margin ? (1 - max(d, 0) / margin) : 0 }
        let ex = push(w - p.x) - push(p.x), ey = push(p.y - top) - push(bottom - p.y)
        guard ex != 0 || ey != 0 else { return }
        pan(by: CGPoint(x: -ex * speed * CGFloat(dt), y: ey * speed * CGFloat(dt)))
        let (x, y) = worldPoint(fromView: p)
        ctl.moveGhost(worldX: x, y: y)
    }
}

#if os(iOS)
extension GameScene: UIGestureRecognizerDelegate {
    /// Touch controls:
    ///  - one finger: tap selects / commands, double-tap selects all of a type, drag moves the camera;
    ///  - press and hold on the map, then drag: a selection box;
    ///  - two fingers: pinch to zoom (dragging two fingers together also draws a box);
    ///  - while placing a building, one finger drags the placement ghost and a double-tap builds there.
    func setupTouch(_ view: SKView) {
        let tap = UITapGestureRecognizer(target: self, action: #selector(onTap(_:)))
        let dbl = UITapGestureRecognizer(target: self, action: #selector(onDoubleTap(_:)))
        dbl.numberOfTapsRequired = 2
        tap.require(toFail: dbl)
        let drag = UIPanGestureRecognizer(target: self, action: #selector(onDrag(_:)))
        drag.minimumNumberOfTouches = 1
        drag.maximumNumberOfTouches = 1
        let two = UIPanGestureRecognizer(target: self, action: #selector(onTwoFinger(_:)))
        two.minimumNumberOfTouches = 2
        two.maximumNumberOfTouches = 2
        // Hold briefly, then drag, to draw a selection box. A quick drag still pans straight away.
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(onHold(_:)))
        hold.minimumPressDuration = 0.35
        hold.allowableMovement = 10
        drag.require(toFail: hold)
        for g in [tap, dbl, drag, two, hold] as [UIGestureRecognizer] { g.delegate = self; view.addGestureRecognizer(g) }
        dbl.delaysTouchesEnded = false
    }

    @objc func onTap(_ g: UITapGestureRecognizer) { handleTap(g.location(in: view)) }
    @objc func onDoubleTap(_ g: UITapGestureRecognizer) { handleDoubleTap(g.location(in: view)) }

    /// One finger: move the camera (or the placement ghost).
    @objc func onDrag(_ g: UIPanGestureRecognizer) {
        let p = g.location(in: view)
        if placing { dragGhost(p, held: g.state == .began || g.state == .changed); return }
        switch g.state {
        case .began: lastPanPoint = p
        case .changed:
            if let l = lastPanPoint { pan(by: CGPoint(x: p.x - l.x, y: p.y - l.y)) }
            lastPanPoint = p
        default: lastPanPoint = nil
        }
    }

    /// Hold, then drag: a selection box from where the finger was held.
    @objc func onHold(_ g: UILongPressGestureRecognizer) {
        let p = g.location(in: view)
        if placing { dragGhost(p, held: g.state == .began || g.state == .changed); return }
        switch g.state {
        case .began:
            boxStart = p
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            updateBox(p, CGPoint(x: p.x + 1, y: p.y + 1))
        case .changed:
            if let s = boxStart { updateBox(s, p) }
        case .ended:
            if let s = boxStart {
                // Held without dragging: nothing to box, so just hide it.
                if hypot(s.x - p.x, s.y - p.y) < 8 { boxNode.isHidden = true } else { finishBox(s, p) }
            }
            boxStart = nil
        default:
            boxNode.isHidden = true; boxStart = nil
        }
    }

    /// Two fingers: a selection box from where the fingers started to where they are, or a pinch zoom.
    @objc func onTwoFinger(_ g: UIPanGestureRecognizer) {
        guard let v = view else { return }
        let mid = g.location(in: v)
        let spread: CGFloat? = g.numberOfTouches >= 2 ? hypot(g.location(ofTouch: 0, in: v).x - g.location(ofTouch: 1, in: v).x,
                                                              g.location(ofTouch: 0, in: v).y - g.location(ofTouch: 1, in: v).y) : nil
        switch g.state {
        case .began:
            twoStart = mid; twoSpread = spread ?? 0; twoMode = 0
        case .changed:
            guard let s0 = twoStart else { return }
            if twoMode == 0, let sp = spread {
                // Decide by the first clear motion: fingers spreading/closing = zoom, moving together = select.
                if abs(sp - twoSpread) > 18 { twoMode = 2 }
                else if hypot(mid.x - s0.x, mid.y - s0.y) > 14 { twoMode = 1; UISelectionFeedbackGenerator().selectionChanged() }
            }
            if twoMode == 1 { updateBox(s0, mid) }
            else if twoMode == 2, let sp = spread, twoSpread > 1 {
                zoom(by: sp / twoSpread, around: mid)
                twoSpread = sp
            }
        case .ended:
            if twoMode == 1, let s0 = twoStart { finishBox(s0, mid) }
            boxNode.isHidden = true; twoStart = nil; twoMode = 0
        default:
            boxNode.isHidden = true; twoStart = nil; twoMode = 0
        }
    }
}
#else
extension GameScene {
    func setupTouch(_ view: SKView) {}

    override func mouseDown(with e: NSEvent) {
        guard let v = view else { return }
        let p = v.convert(e.locationInWindow, from: nil)
        let vp = CGPoint(x: p.x, y: v.bounds.height - p.y)
        if placing { dragGhost(vp); return }
        if e.clickCount == 2 { handleDoubleTap(vp); return }
        boxStart = vp
    }

    override func mouseDragged(with e: NSEvent) {
        guard let v = view else { return }
        let p = v.convert(e.locationInWindow, from: nil)
        let vp = CGPoint(x: p.x, y: v.bounds.height - p.y)
        if placing { dragGhost(vp); return }
        if let s = boxStart { updateBox(s, vp) }
    }

    override func mouseUp(with e: NSEvent) {
        guard let v = view else { return }
        let p = v.convert(e.locationInWindow, from: nil)
        let vp = CGPoint(x: p.x, y: v.bounds.height - p.y)
        if placing { placeDragPoint = nil; ctl.confirmPlacement(); return }
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
        case "y": ctl.selectIdleArmy()
        case "t": ctl.showTech.toggle()
        default:
            if let b = ctl.hud.buttons.first(where: { $0.hotkey == ch && $0.enabled }) { b.action() }
        }
    }
}
#endif

