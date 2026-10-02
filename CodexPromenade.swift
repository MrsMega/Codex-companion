import AppKit
import ApplicationServices
import CoreGraphics
import ImageIO

private let spriteWidth = 192
private let spriteHeight = 208
private let petSize = NSSize(width: 96, height: 104)
private let landingDuration = 1.42

final class PetView: NSView {
    var image: NSImage? { didSet { needsDisplay = true } }
    var mirrorImage = false { didSet { if mirrorImage != oldValue { needsDisplay = true } } }
    // -1 hides the hands; 0 rests on the keys; 1/2 press left/right.
    var typingPose = -1 { didSet { if typingPose != oldValue { needsDisplay = true } } }
    var onPickUp: (() -> Void)?
    var onDrag: ((NSPoint) -> Void)?
    var onDrop: ((NSPoint) -> Void)?
    var onMenu: (() -> Void)?
    var onOpen: (() -> Void)?
    private var dragOffset = NSPoint.zero
    private var dragStart = NSPoint.zero
    private var isDragging = false

    override func draw(_ dirtyRect: NSRect) {
        guard let image else { return }
        NSGraphicsContext.current?.imageInterpolation = .none
        if mirrorImage {
            NSGraphicsContext.saveGraphicsState()
            let transform = NSAffineTransform()
            transform.translateX(by: bounds.width, yBy: 0)
            transform.scaleX(by: -1, yBy: 1)
            transform.concat()
            image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
        } else {
            image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
        }
        if typingPose >= 0 { drawTypingHands() }
    }

    private func drawTypingHands() {
        // The official laptop sprite already supplies the seated body and
        // keyboard. Two small hands move over its keys without altering it.
        let outline = NSColor(calibratedRed: 0.13, green: 0.18, blue: 0.41, alpha: 1)
        let gloveGradient = NSGradient(starting: NSColor(calibratedRed: 0.42, green: 0.61, blue: 0.98, alpha: 1),
                                       ending: NSColor(calibratedRed: 0.24, green: 0.40, blue: 0.84, alpha: 1))!
        let highlight = NSColor(calibratedRed: 0.49, green: 0.68, blue: 0.99, alpha: 1)

        func hand(x: CGFloat, y: CGFloat, width: CGFloat) {
            let shape = NSBezierPath(roundedRect: NSRect(x: x, y: y, width: width, height: 6.2),
                                     xRadius: 2.7, yRadius: 2.7)
            outline.setFill(); shape.fill()
            let inner = NSBezierPath(roundedRect: NSRect(x: x + 1.1, y: y + 1.2,
                                                          width: width - 2.2, height: 3.8),
                                     xRadius: 1.9, yRadius: 1.9)
            gloveGradient.draw(in: inner, angle: 90)
            highlight.setFill()
            NSRect(x: x + 2.0, y: y + 4.0, width: width - 4.5, height: 0.9).fill()
        }

        let leftPressed = typingPose == 1
        let rightPressed = typingPose == 2
        hand(x: 35.5, y: leftPressed ? 23.4 : 27.0, width: 8.0)
        hand(x: 42.0, y: rightPressed ? 23.4 : 27.0, width: 7.3)
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let mouse = NSEvent.mouseLocation
        dragOffset = NSPoint(x: mouse.x - window.frame.minX, y: mouse.y - window.frame.minY)
        dragStart = mouse
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard window != nil else { return }
        let mouse = NSEvent.mouseLocation
        if !isDragging {
            guard hypot(mouse.x - dragStart.x, mouse.y - dragStart.y) > 3 else { return }
            isDragging = true
            onPickUp?()
        }
        onDrag?(NSPoint(x: mouse.x - dragOffset.x, y: mouse.y - dragOffset.y))
    }

    override func rightMouseDown(with event: NSEvent) { onMenu?() }
    override func mouseUp(with event: NSEvent) {
        if isDragging {
            isDragging = false
            let mouse = NSEvent.mouseLocation
            onDrop?(NSPoint(x: mouse.x - dragOffset.x, y: mouse.y - dragOffset.y))
            return
        }
        if event.clickCount == 2 { onOpen?() }
    }
}

final class PetController: NSObject, NSApplicationDelegate {
    private enum Activity {
        case idle, walk, think, wait, look, wave, jump, backflip, review, bump, laugh
        case surprise, pout, context, selection, rest, sleep, attend, carried, falling, land
        case handshake, dance, conversation, duoFlip, sharedLaugh

        var isSocial: Bool {
            switch self {
            case .handshake, .dance, .conversation, .duoFlip, .sharedLaugh: true
            default: false
            }
        }
    }
    private static var companions: [PetController] = []
    private static let companionLimit = 6
    private struct DragSample {
        let position: NSPoint
        let time: Double
    }

    private var window: NSWindow!
    private var view: PetView!
    private var timer: Timer?
    private var lastTick = ProcessInfo.processInfo.systemUptime
    private var lastFocusPollAt = 0.0
    private var lastPermissionPollAt = 0.0
    private var lastAttentionEventAt = 0.0
    private var lastKeyAt = 0.0
    private var typingKeyCount = 0
    private var focusSignature = ""
    private var selectionSignature = ""
    private var observedDragStart: NSPoint?
    private var observedDragDistance = 0.0
    private var focusPoint: NSPoint?
    private var attentionPoint: NSPoint?
    private var attentionLookIndex = 0
    private var attentionTyping = false
    private var attentionEnabled = true
    private var globalClickMonitor: Any?
    private var globalSelectionMonitor: Any?
    private var globalKeyMonitor: Any?
    private var activationObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?
    private var activity: Activity = .idle
    private var activityAge = 0.0
    private var activityDuration = 1.8
    private var facingRight = true
    private var forcedDirection: Bool?
    private var firstJourney = true
    private var consecutiveActions = 0
    private var nextBackflipAt = ProcessInfo.processInfo.systemUptime + Double.random(in: 18...32)
    private var nextWaveAt = ProcessInfo.processInfo.systemUptime + Double.random(in: 9...18)
    private var nextLaughAt = ProcessInfo.processInfo.systemUptime + Double.random(in: 12...24)
    private var nextRestAt = ProcessInfo.processInfo.systemUptime + Double.random(in: 35...60)
    private var paused = false
    private var dragReleaseAt = 0.0
    private var carryTarget = NSPoint.zero
    private var carryVelocityX = 0.0
    private var carryVelocityY = 0.0
    private var dragSamples: [DragSample] = []
    private var flightVelocityX = 0.0
    private var fallVelocity = 0.0
    private var bounceCount = 0
    private var x = 0.0
    private var y = 0.0
    private var walkTarget = 0.0
    private var walkTargetY = 0.0
    private var walkSpeed = 0.0
    private var walkMaxSpeed = 56.0
    private var walkAnimationPhase = 0.0
    private var headingForEdge = false
    private var impactX = 0.0
    private weak var socialPartner: PetController?
    private var nextSocialAt = 0.0
    private var nextSocialCheckAt = 0.0
    private var idleFrames: [NSImage] = []
    private var rightFrames: [NSImage] = []
    private var leftFrames: [NSImage] = []
    private var waveFrames: [NSImage] = []
    private var jumpFrames: [NSImage] = []
    private var backflipFrames: [NSImage] = []
    private var bumpFrames: [NSImage] = []
    private var waitingFrames: [NSImage] = []
    private var thinkFrames: [NSImage] = []
    private var reviewFrames: [NSImage] = []
    private var lookFrames: [NSImage] = []
    private var laughFrames: [NSImage] = []
    private var surpriseFrames: [NSImage] = []
    private var poutFrames: [NSImage] = []
    private var contextFrames: [NSImage] = []
    private var selectionFrames: [NSImage] = []
    private var carryFrames: [NSImage] = []
    private var landingFrames: [NSImage] = []
    private var restFrames: [NSImage] = []
    private var sleepFrames: [NSImage] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        launch(near: nil)
    }

    private func launch(near neighbor: PetController?) {
        NSApp.setActivationPolicy(.accessory)
        guard loadSprites() else {
            let alert = NSAlert()
            alert.messageText = "La feuille de sprites Codex est introuvable."
            alert.informativeText = "Réinstallez Codex Promenade avec son dossier Resources."
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        let screen = neighbor?.currentScreenFrame()
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        if let neighbor {
            let minX = Double(screen.minX)
            let maxX = Double(screen.maxX - petSize.width)
            let candidates = [78.0, -78.0, 156.0, -156.0, 234.0, -234.0]
                .map { min(maxX, max(minX, neighbor.x + $0)) }
            let nearby = PetController.companions.filter { abs($0.y - neighbor.y) <= 35 }
            func clearance(_ candidate: Double) -> Double {
                nearby.map { abs(candidate - $0.x) }.min() ?? .infinity
            }
            x = candidates.first(where: { clearance($0) >= 58 })
                ?? candidates.max(by: { clearance($0) < clearance($1) })
                ?? neighbor.x
            y = neighbor.y
            firstJourney = false
        } else {
            x = Double(screen.midX - petSize.width / 2)
            y = Double(screen.minY + 24)
        }
        window = NSWindow(contentRect: NSRect(origin: NSPoint(x: x, y: y), size: petSize),
                          styleMask: .borderless, backing: .buffered, defer: false)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = false
        view = PetView(frame: NSRect(origin: .zero, size: petSize))
        view.image = idleFrames[0]
        view.onPickUp = { [weak self] in self?.pickUp() }
        view.onDrag = { [weak self] target in self?.dragged(to: target) }
        view.onDrop = { [weak self] target in self?.dropPet(at: target) }
        view.onMenu = { [weak self] in
            self?.react(to: .context, at: NSEvent.mouseLocation)
            self?.showMenu()
        }
        view.onOpen = { [weak self] in self?.openChatGPT() }
        window.contentView = view
        window.orderFrontRegardless()
        PetController.companions.append(self)

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                self?.handleScreenChange()
            }

        timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
        installAttentionMonitoring()
    }

    func applicationWillTerminate(_ notification: Notification) {
        for companion in PetController.companions { companion.stop() }
    }

    private func stop() {
        if let partner = socialPartner { partner.begin(.idle, duration: 0.6) }
        timer?.invalidate()
        timer = nil
        if let globalClickMonitor { NSEvent.removeMonitor(globalClickMonitor) }
        if let globalSelectionMonitor { NSEvent.removeMonitor(globalSelectionMonitor) }
        if let globalKeyMonitor { NSEvent.removeMonitor(globalKeyMonitor) }
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        window?.close()
    }

    private func installAttentionMonitoring() {
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                let kind = event.type
                let clickCount = event.clickCount
                let point = NSEvent.mouseLocation
                DispatchQueue.main.async {
                    self?.handleGlobalClick(kind: kind, clickCount: clickCount, at: point)
                }
            }
        globalSelectionMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
                let kind = event.type
                let point = NSEvent.mouseLocation
                DispatchQueue.main.async {
                    self?.handleExternalDrag(kind: kind, at: point)
                }
            }
        installKeyboardMonitorIfAvailable()
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main) { [weak self] _ in
                self?.handleApplicationActivation()
            }
    }

    private var keyboardAccessAvailable: Bool {
        AXIsProcessTrusted() || CGPreflightListenEventAccess()
    }

    private func installKeyboardMonitorIfAvailable() {
        guard globalKeyMonitor == nil, keyboardAccessAvailable else { return }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            // Only the event kind and time are used. Key codes and text are ignored.
            if event.type == .keyDown {
                DispatchQueue.main.async { self?.handleKeyActivity() }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    self?.pollTextSelection()
                }
            }
        }
    }

    private func handleApplicationActivation() {
        guard attentionEnabled,
              let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        if AXIsProcessTrusted() {
            pollFocusedElement(force: true)
        } else {
            // A standard account can still see app switches and the cursor.
            // The focused control itself remains unavailable without AX access.
            let point = NSEvent.mouseLocation
            focusPoint = point
            startAttention(to: point, typing: false,
                           at: ProcessInfo.processInfo.systemUptime)
        }
    }

    private func loadSprites() -> Bool {
        guard let url = Bundle.main.url(forResource: "codex-spritesheet-v6", withExtension: "webp"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let atlas = CGImageSourceCreateImageAtIndex(source, 0, nil),
              atlas.width == 1536, atlas.height == 2288 else { return false }
        func cell(_ row: Int, _ column: Int) -> CGImage? {
            let rect = CGRect(x: column * spriteWidth, y: row * spriteHeight,
                              width: spriteWidth, height: spriteHeight)
            return atlas.cropping(to: rect)
        }
        func row(_ index: Int, count: Int) -> [NSImage] {
            (0..<count).compactMap { column in
                guard let crop = cell(index, column) else { return nil }
                return NSImage(cgImage: crop, size: petSize)
            }
        }
        idleFrames = row(0, count: 7)
        func spriteStrip(_ name: String, count: Int) -> [NSImage]? {
            guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
                  image.width == count * spriteWidth,
                  image.height == spriteHeight else { return nil }
            let frames: [NSImage] = (0..<count).compactMap { column in
                guard let crop = image.cropping(to: CGRect(x: column * spriteWidth,
                                                           y: 0, width: spriteWidth,
                                                           height: spriteHeight)) else { return nil }
                return NSImage(cgImage: crop, size: petSize)
            }
            return frames.count == count ? frames : nil
        }
        guard let loadedLaugh = spriteStrip("codex-laugh-v3", count: 6),
              let loadedSurprise = spriteStrip("codex-surprise-v3", count: 6),
              let loadedPout = spriteStrip("codex-pout-v3", count: 6),
              let loadedContext = spriteStrip("codex-context-v1", count: 6),
              let loadedSelection = spriteStrip("codex-selection-v1", count: 6),
              let loadedCarry = spriteStrip("codex-carry-v5", count: 6),
              let loadedLanding = spriteStrip("codex-land-v1", count: 6),
              let loadedRest = spriteStrip("codex-rest-v1", count: 1),
              let loadedDoze = spriteStrip("codex-doze-v1", count: 1),
              let loadedSleep = spriteStrip("codex-sleep-v1", count: 1) else { return false }
        let originalRightWalk = row(1, count: 6)
        let originalLeftWalk = row(2, count: 6)
        guard originalRightWalk.count == 6, originalLeftWalk.count == 6 else { return false }
        // Each half starts on a planted pose and ends after the opposite leg
        // swings through. The unused atlas cells mostly repeat the resting pose.
        let walkOrder = [0, 1, 2, 3, 0, 1, 4, 5]
        rightFrames = walkOrder.map { originalRightWalk[$0] }
        leftFrames = walkOrder.map { originalLeftWalk[$0] }
        laughFrames = loadedLaugh
        surpriseFrames = loadedSurprise
        poutFrames = loadedPout
        contextFrames = loadedContext
        selectionFrames = loadedSelection
        carryFrames = loadedCarry
        landingFrames = loadedLanding
        restFrames = loadedRest
        sleepFrames = loadedRest + loadedDoze + loadedSleep
        waveFrames = row(3, count: 4)
        jumpFrames = row(4, count: 5)
        bumpFrames = row(5, count: 8)
        waitingFrames = row(6, count: 6)
        thinkFrames = row(7, count: 6)
        reviewFrames = row(8, count: 6)
        lookFrames = row(9, count: 8) + row(10, count: 8)
        guard let modeledFrames = spriteStrip("codex-backflip-v3", count: 8),
              let startingFrame = idleFrames.first else { return false }
        backflipFrames = [startingFrame] + modeledFrames + [startingFrame]
        return idleFrames.count == 7 && rightFrames.count == 8 && leftFrames.count == 8
            && waveFrames.count == 4 && jumpFrames.count == 5 && bumpFrames.count == 8
            && waitingFrames.count == 6 && thinkFrames.count == 6
            && reviewFrames.count == 6 && lookFrames.count == 16 && backflipFrames.count == 10
            && laughFrames.count == 6 && surpriseFrames.count == 6 && poutFrames.count == 6
            && contextFrames.count == 6 && selectionFrames.count == 6
            && carryFrames.count == 6 && landingFrames.count == 6
            && restFrames.count == 1 && sleepFrames.count == 3
    }

    private func handleGlobalClick(kind: NSEvent.EventType, clickCount: Int, at point: NSPoint) {
        guard attentionEnabled else { return }
        let now = ProcessInfo.processInfo.systemUptime
        observedDragStart = kind == .leftMouseDown ? point : nil
        observedDragDistance = 0
        focusPoint = point
        if kind == .rightMouseDown {
            react(to: .context, at: point)
        } else if clickCount >= 2 {
            react(to: .laugh, at: point)
        } else {
            startAttention(to: point, typing: false, at: now)
        }
        if AXIsProcessTrusted() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                self?.pollFocusedElement(force: true)
            }
        }
    }

    private func handleExternalDrag(kind: NSEvent.EventType, at point: NSPoint) {
        guard attentionEnabled else { return }
        if kind == .leftMouseDragged {
            if observedDragStart == nil { observedDragStart = point }
            if let start = observedDragStart {
                observedDragDistance = max(observedDragDistance,
                                           Double(hypot(point.x - start.x, point.y - start.y)))
            }
            return
        }
        let draggedFarEnough = observedDragDistance >= 36
        observedDragStart = nil
        observedDragDistance = 0
        if AXIsProcessTrusted() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                self?.pollTextSelection()
            }
        } else if draggedFarEnough {
            // Without Accessibility, a drag is only a gesture; it may not
            // have selected text. Never inspect another app's contents.
            react(to: .selection, at: point)
        }
    }

    private func pollTextSelection() {
        guard attentionEnabled, AXIsProcessTrusted(),
              let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.15)
        guard let focused = copiedElement(root, attribute: kAXFocusedUIElementAttribute as CFString) else {
            selectionSignature = ""
            return
        }
        AXUIElementSetMessagingTimeout(focused, 0.15)
        var rawRange: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused, kAXSelectedTextRangeAttribute as CFString,
                                            &rawRange) == .success,
              let rawRange, CFGetTypeID(rawRange) == AXValueGetTypeID() else {
            selectionSignature = ""
            return
        }
        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(rawRange as! AXValue, .cfRange, &range), range.length > 0 else {
            selectionSignature = ""
            return
        }
        let signature = "\(app.processIdentifier):\(CFHash(focused)):\(range.location):\(range.length)"
        guard signature != selectionSignature else { return }
        selectionSignature = signature
        let point = focusedPoint(of: focused) ?? NSEvent.mouseLocation
        react(to: .selection, at: point)
    }

    private func react(to next: Activity, at point: NSPoint) {
        let now = ProcessInfo.processInfo.systemUptime
        guard attentionEnabled, !paused, now >= dragReleaseAt,
              activity != .carried, activity != .falling, activity != .land else { return }
        attentionPoint = point
        attentionLookIndex = lookIndex(toward: point)
        lastAttentionEventAt = now
        attentionTyping = false
        firstJourney = false
        let duration: Double
        switch next {
        case .context: duration = 1.15
        case .selection: duration = 1.35
        case .laugh: duration = 1.55
        default: duration = 1.2
        }
        begin(next, duration: duration)
        render()
    }

    private func handleKeyActivity() {
        guard attentionEnabled else { return }
        let now = ProcessInfo.processInfo.systemUptime
        lastKeyAt = now
        typingKeyCount += 1
        let point = focusPoint ?? NSEvent.mouseLocation
        startAttention(to: point, typing: true, at: now)
    }

    private func copiedElement(_ parent: AXUIElement, attribute: CFString) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, attribute, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func focusedPoint(of element: AXUIElement) -> NSPoint? {
        var rawPosition: CFTypeRef?
        var rawSize: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString,
                                             &rawPosition) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString,
                                             &rawSize) == .success,
              let rawPosition, let rawSize,
              CFGetTypeID(rawPosition) == AXValueGetTypeID(),
              CFGetTypeID(rawSize) == AXValueGetTypeID() else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(rawPosition as! AXValue, .cgPoint, &position),
              AXValueGetValue(rawSize as! AXValue, .cgSize, &size),
              size.width > 0, size.height > 0 else { return nil }
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        let point = NSPoint(x: position.x + size.width / 2,
                            y: primaryTop - position.y - size.height / 2)
        guard point.x.isFinite, point.y.isFinite,
              NSScreen.screens.contains(where: {
                  $0.frame.insetBy(dx: -40, dy: -40).contains(point)
              }) else { return nil }
        return point
    }

    private func pollFocusedElement(force: Bool = false) {
        guard attentionEnabled else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard force || now - lastFocusPollAt >= 0.45 else { return }
        lastFocusPollAt = now
        guard AXIsProcessTrusted(),
              let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.15)
        let focused = copiedElement(root, attribute: kAXFocusedUIElementAttribute as CFString)
        let focusedWindow = copiedElement(root, attribute: kAXFocusedWindowAttribute as CFString)
        if let focused { AXUIElementSetMessagingTimeout(focused, 0.15) }
        if let focusedWindow { AXUIElementSetMessagingTimeout(focusedWindow, 0.15) }
        guard let point = focused.flatMap(focusedPoint)
                ?? focusedWindow.flatMap(focusedPoint) else { return }
        focusPoint = point
        if activity == .attend {
            attentionPoint = point
            attentionLookIndex = lookIndex(toward: point)
        }
        let identity = focused ?? focusedWindow!
        let signature = "\(app.processIdentifier):\(CFHash(identity))"
        if signature != focusSignature {
            focusSignature = signature
            if now - lastAttentionEventAt > 0.45 {
                startAttention(to: point, typing: false, at: now)
            }
        }
    }

    private func lookIndex(toward point: NSPoint) -> Int {
        let dx = Double(point.x - window.frame.midX)
        let dy = Double(point.y - window.frame.midY)
        guard abs(dx) + abs(dy) > 24 else { return facingRight ? 3 : 14 }
        let sector = Int((atan2(dy, dx) / (.pi / 4)).rounded())
        switch sector {
        case 1: return 1      // up and right
        case 2: return 0      // up
        case 3: return 15     // up and left
        case 4, -4: return 14 // left
        case -3: return 10    // down and left
        case -2: return 7     // down
        case -1: return 5     // down and right
        default: return 3     // right
        }
    }

    private func startAttention(to point: NSPoint, typing: Bool, at now: Double) {
        guard attentionEnabled, !paused, now >= dragReleaseAt,
              activity != .carried, activity != .falling, activity != .land else { return }
        attentionPoint = point
        attentionLookIndex = lookIndex(toward: point)
        lastAttentionEventAt = now
        if typing { attentionTyping = true }
        if activity == .attend {
            activityDuration = max(activityDuration, activityAge + (typing ? 1.55 : 1.2))
        } else if activity != .backflip && activity != .jump && activity != .bump {
            attentionTyping = typing
            begin(.attend, duration: typing ? 1.55 : 1.2)
        }
    }

    private func pickUp() {
        x = Double(window.frame.minX)
        y = Double(window.frame.minY)
        carryTarget = window.frame.origin
        carryVelocityX = 0
        carryVelocityY = 0
        flightVelocityX = 0
        dragSamples.removeAll(keepingCapacity: true)
        firstJourney = false
        attentionTyping = false
        fallVelocity = 0
        begin(.carried, duration: .infinity)
        render()
    }

    private func dragged(to target: NSPoint) {
        carryTarget = target
        let now = ProcessInfo.processInfo.systemUptime
        dragSamples.append(DragSample(position: target, time: now))
        dragSamples.removeAll { now - $0.time > 0.14 }
    }

    private func dropPet(at target: NSPoint) {
        guard activity == .carried else { return }
        dragged(to: target)
        let gestureX: Double
        let gestureY: Double
        if let first = dragSamples.first, let last = dragSamples.last,
           last.time - first.time >= 0.008 {
            let elapsed = last.time - first.time
            gestureX = Double(last.position.x - first.position.x) / elapsed
            gestureY = Double(last.position.y - first.position.y) / elapsed
        } else {
            gestureX = 0
            gestureY = 0
        }
        let gestureSpeed = hypot(gestureX, gestureY)
        let throwX = gestureSpeed > 45 ? 0.85 * gestureX + 0.15 * carryVelocityX : 0
        let throwY = gestureSpeed > 45 ? 0.85 * gestureY + 0.15 * carryVelocityY : 0
        flightVelocityX = min(1050, max(-1050, throwX))
        fallVelocity = min(1050, max(-950, throwY))
        dragSamples.removeAll(keepingCapacity: true)
        bounceCount = 0
        let bounds = currentBounds()
        x = min(bounds.max, max(bounds.min, x))
        dragReleaseAt = ProcessInfo.processInfo.systemUptime + 0.9
        let ground = currentGroundY()
        y = max(y, ground)
        if y == ground && fallVelocity <= 0 {
            begin(.land, duration: landingDuration)
        } else {
            begin(.falling, duration: 120)
        }
        render()
    }

    private func moveWhileCarried(dt: Double) {
        // A damped spring lets the body trail the pointer without oscillating.
        carryVelocityX += (115 * (Double(carryTarget.x) - x) - 18 * carryVelocityX) * dt
        carryVelocityY += (115 * (Double(carryTarget.y) - y) - 18 * carryVelocityY) * dt
        carryVelocityX = min(1800, max(-1800, carryVelocityX))
        carryVelocityY = min(1800, max(-1800, carryVelocityY))
        x += carryVelocityX * dt
        y += carryVelocityY * dt
    }

    private func moveWhileFalling(dt: Double) {
        flightVelocityX *= exp(-0.55 * dt)
        fallVelocity = max(-1100, fallVelocity - 1050 * dt)
        x += flightVelocityX * dt
        y += fallVelocity * dt

        let bounds = currentBounds()
        if x < bounds.min || x > bounds.max {
            x = min(bounds.max, max(bounds.min, x))
            flightVelocityX *= -0.48
        }
        if y > currentCeilingY() {
            y = currentCeilingY()
            fallVelocity = min(0, -abs(fallVelocity) * 0.3)
        }
        if y <= currentGroundY() {
            y = currentGroundY()
            if bounceCount < 2 && fallVelocity < -210 {
                fallVelocity *= bounceCount == 0 ? -0.38 : -0.26
                flightVelocityX *= 0.72
                bounceCount += 1
            } else {
                fallVelocity = 0
                begin(.land, duration: landingDuration)
            }
        }
    }

    private func slideAfterLanding(dt: Double) {
        flightVelocityX *= exp(-9 * dt)
        if abs(flightVelocityX) < 5 { flightVelocityX = 0 }
        x += flightVelocityX * dt
        let bounds = currentBounds()
        x = min(bounds.max, max(bounds.min, x))
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(0.05, max(0, now - lastTick))
        lastTick = now
        if globalKeyMonitor == nil && now - lastPermissionPollAt > 5 {
            lastPermissionPollAt = now
            installKeyboardMonitorIfAvailable()
        }
        guard !paused || activity == .carried || activity == .falling || activity == .land else { return }
        if activity != .carried { pollFocusedElement() }
        activityAge += dt
        if activity == .walk { move(dt: dt) }
        if activity == .carried { moveWhileCarried(dt: dt) }
        if activity == .falling { moveWhileFalling(dt: dt) }
        if activity == .land { slideAfterLanding(dt: dt) }
        if activity == .bump {
            let progress = min(1.0, activityAge / 0.35)
            let recoil = 14.0 * (1.0 - pow(1.0 - progress, 3.0))
            x = impactX - (facingRight ? recoil : -recoil)
        }
        if now >= nextSocialCheckAt {
            nextSocialCheckAt = now + 0.25
            lookForCompanion(at: now)
        }
        if activityAge >= activityDuration { finishActivity() }
        render()
    }

    private func currentScreenFrame() -> NSRect {
        let center = window.frame.center
        let screens = NSScreen.screens
        if let screen = screens.first(where: { $0.frame.contains(center) }) {
            return screen.visibleFrame
        }
        func distanceSquared(to frame: NSRect) -> CGFloat {
            let dx = max(frame.minX - center.x, 0, center.x - frame.maxX)
            let dy = max(frame.minY - center.y, 0, center.y - frame.maxY)
            return dx * dx + dy * dy
        }
        return screens.min(by: { distanceSquared(to: $0.frame) < distanceSquared(to: $1.frame) })?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
    }

    private func handleScreenChange() {
        guard window != nil, activity != .carried else { return }
        let screen = currentScreenFrame()
        let bounds = currentBounds()
        x = min(bounds.max, max(bounds.min, x))
        let ground = Double(screen.minY + 24)
        let ceiling = max(ground, Double(screen.maxY - petSize.height + 12))
        y = min(ceiling, max(ground, y))
        walkTarget = min(bounds.max, max(bounds.min, walkTarget))
        walkTargetY = min(ceiling, max(ground, walkTargetY))
        impactX = x
        render()
    }

    private func currentBounds() -> (min: Double, max: Double) {
        let screen = currentScreenFrame()
        // Only the transparent padding of the sprite window crosses the edge.
        return (Double(screen.minX) - 12.0, Double(screen.maxX - petSize.width) + 12.0)
    }

    private func currentGroundY() -> Double {
        Double(currentScreenFrame().minY + 24)
    }

    private func currentCeilingY() -> Double {
        Double(currentScreenFrame().maxY - petSize.height + 12)
    }

    private func begin(_ next: Activity, duration: Double) {
        if let partner = socialPartner, !next.isSocial {
            socialPartner = nil
            partner.socialPartner = nil
            if partner.activity.isSocial {
                partner.begin(.idle, duration: 0.6)
            }
        }
        activity = next
        activityAge = 0
        activityDuration = duration
        if next != .walk { walkSpeed = 0 }
    }

    private var canSocialize: Bool {
        guard !paused, socialPartner == nil else { return false }
        switch activity {
        case .idle, .walk, .think, .wait, .look, .wave, .laugh, .review:
            return true
        default:
            return false
        }
    }

    private func lookForCompanion(at now: Double) {
        guard now >= nextSocialAt, canSocialize else { return }
        let neighbors = PetController.companions.filter { companion in
            companion !== self && companion.canSocialize && now >= companion.nextSocialAt
                && abs(companion.y - y) <= 22
                && (55...125).contains(abs(companion.x - x))
        }
        guard let partner = neighbors.min(by: { abs($0.x - x) < abs($1.x - x) }) else { return }
        let closeEnoughToTouch = abs(partner.x - x) <= 96 && abs(partner.y - y) <= 14
        let kinds: [Activity] = closeEnoughToTouch
            ? [.handshake, .dance, .conversation, .duoFlip, .sharedLaugh]
            : [.dance, .conversation, .duoFlip, .sharedLaugh]
        let kind = kinds.randomElement() ?? .conversation
        startSocial(with: partner, kind: kind, at: now)
    }

    private func startSocial(with partner: PetController, kind: Activity, at now: Double) {
        guard canSocialize, partner.canSocialize else { return }
        let duration: Double
        switch kind {
        case .handshake: duration = 2.25
        case .dance: duration = 3.6
        case .conversation: duration = 3.2
        case .duoFlip: duration = 3.0
        case .sharedLaugh: duration = 1.75
        default: return
        }
        firstJourney = false
        partner.firstJourney = false
        facingRight = x < partner.x
        partner.facingRight = !facingRight
        socialPartner = partner
        partner.socialPartner = self
        nextSocialAt = now + Double.random(in: 18...28)
        partner.nextSocialAt = now + Double.random(in: 18...28)
        begin(kind, duration: duration)
        partner.begin(kind, duration: duration)
        partner.render()
    }

    private func continueSocial(as next: Activity, duration: Double) {
        guard let partner = socialPartner, partner.activity == activity else {
            startWalk()
            return
        }
        begin(next, duration: duration)
        partner.begin(next, duration: duration)
        partner.render()
    }

    private func nearestAvailableCompanion() -> PetController? {
        PetController.companions.filter {
            $0 !== self && $0.canSocialize
                && abs($0.y - y) <= 22
                && (55...125).contains(abs($0.x - x))
        }.min(by: { abs($0.x - x) < abs($1.x - x) })
    }

    private func startWalk() {
        let bounds = currentBounds()
        let ground = currentGroundY()
        let ceiling = max(ground, currentCeilingY())
        let wasFirstJourney = firstJourney
        let direction = forcedDirection ?? Bool.random()
        forcedDirection = nil
        facingRight = direction
        headingForEdge = firstJourney || Double.random(in: 0...1) < 0.34
        firstJourney = false
        walkMaxSpeed = Double.random(in: 30...54)
        if headingForEdge {
            walkTarget = direction ? bounds.max : bounds.min
        } else {
            let sampledDistance = Double.random(in: 90...min(330, max(100, bounds.max - bounds.min)))
            // Half-cycle distances finish on a planted pose, avoiding a snap
            // from a lifted leg to idle when the companion reaches its goal.
            let distance = (sampledDistance / 20.0).rounded() * 20.0
            walkTarget = min(bounds.max - 20, max(bounds.min + 20, x + (direction ? distance : -distance)))
        }
        if abs(walkTarget - x) < 25 {
            facingRight.toggle()
            walkTarget = x + (facingRight ? 100 : -100)
            walkTarget = min(bounds.max, max(bounds.min, walkTarget))
        }
        walkTargetY = y
        if !wasFirstJourney && ceiling - ground >= 90 && Double.random(in: 0...1) < 0.5 {
            let climb = y <= ground + 50 ? true : y >= ceiling - 50 ? false : Bool.random()
            let distance = Double.random(in: 110...230)
            walkTargetY = min(ceiling, max(ground, y + (climb ? distance : -distance)))
        }
        consecutiveActions = 0
        walkAnimationPhase = 0
        begin(.walk, duration: 120)
    }

    private func move(dt: Double) {
        let bounds = currentBounds()
        let dx = walkTarget - x
        let dy = walkTargetY - y
        let remaining = hypot(dx, dy)
        let brakingSpeed = headingForEdge ? walkMaxSpeed : sqrt(2.0 * 105.0 * remaining)
        let desiredSpeed = min(walkMaxSpeed, brakingSpeed)
        walkSpeed += (desiredSpeed - walkSpeed) * (1.0 - exp(-dt * 6.5))
        let step = min(walkSpeed * dt, remaining)
        if remaining > 0 {
            x += dx / remaining * step
            y += dy / remaining * step
        }
        // Eight ordered poses span roughly 40 points. Advancing with distance
        // keeps the feet in sync as the companion accelerates and brakes.
        walkAnimationPhase += step * (8.0 / 40.0)

        if headingForEdge && (x <= bounds.min + 0.001 || x >= bounds.max - 0.001) {
            x = min(bounds.max, max(bounds.min, x))
            impactX = x
            forcedDirection = !facingRight
            begin(.bump, duration: 0.9)
        } else if hypot(walkTarget - x, walkTargetY - y) < 3.0 && walkSpeed < 10.0 {
            x = walkTarget
            y = walkTargetY
            chooseAction()
        }
    }

    private func chooseAction() {
        consecutiveActions += 1
        let now = ProcessInfo.processInfo.systemUptime
        if now >= nextBackflipAt {
            nextBackflipAt = now + Double.random(in: 35...60)
            begin(.backflip, duration: 1.15)
            return
        }
        if now >= nextLaughAt {
            nextLaughAt = now + Double.random(in: 25...45)
            begin(.laugh, duration: 1.55)
            return
        }
        if now >= nextWaveAt {
            nextWaveAt = now + Double.random(in: 22...40)
            begin(.wave, duration: 1.45)
            return
        }
        if now >= nextRestAt {
            nextRestAt = now + Double.random(in: 65...110)
            if Double.random(in: 0...1) < 0.30 {
                begin(.sleep, duration: Double.random(in: 10...16))
            } else {
                begin(.rest, duration: Double.random(in: 4...7))
            }
            return
        }
        let roll = Int.random(in: 0..<100)
        switch roll {
        case 0..<15: begin(.idle, duration: Double.random(in: 1.0...2.8))
        case 15..<32: begin(.think, duration: Double.random(in: 1.7...3.5))
        case 32..<40: begin(.wait, duration: Double.random(in: 0.9...1.6))
        case 40..<52: begin(.look, duration: Double.random(in: 1.4...2.2))
        case 52..<66: begin(.wave, duration: Double.random(in: 1.1...1.7))
        case 66..<76:
            nextLaughAt = now + Double.random(in: 25...45)
            begin(.laugh, duration: 1.55)
        case 76..<83: begin(.surprise, duration: 1.35)
        case 83..<90: begin(.pout, duration: 1.75)
        case 90..<96: begin(.jump, duration: 0.75)
        default: begin(.review, duration: Double.random(in: 1.3...2.2))
        }
    }

    private func finishActivity() {
        if firstJourney { startWalk(); return }
        if activity != .attend && activity != .bump && activity != .walk,
           ProcessInfo.processInfo.systemUptime - lastAttentionEventAt < 1.4,
           let attentionPoint {
            attentionLookIndex = lookIndex(toward: attentionPoint)
            begin(.attend, duration: 1.2)
            return
        }
        switch activity {
        case .walk:
            chooseAction()
        case .bump:
            facingRight.toggle()
            begin(.surprise, duration: 1.35)
            consecutiveActions = 1
        case .backflip:
            nextWaveAt = ProcessInfo.processInfo.systemUptime + Double.random(in: 22...40)
            begin(.wave, duration: 1.35)
        case .attend:
            attentionTyping = false
            startWalk()
        case .handshake:
            continueSocial(as: .dance, duration: 3.6)
        case .conversation, .duoFlip:
            continueSocial(as: .sharedLaugh, duration: 1.75)
        case .dance, .sharedLaugh:
            startWalk()
        case .land, .falling:
            startWalk()
        case .carried:
            break
        default:
            if consecutiveActions >= 2 || Double.random(in: 0...1) < 0.68 {
                startWalk()
            } else {
                chooseAction()
            }
        }
    }

    private func render() {
        let frames: [NSImage]
        let index: Int
        var bob = 0.0
        var sway = 0.0
        var mirrorImage = false
        var typingPose = -1
        switch activity {
        case .idle:
            frames = idleFrames; index = Int(activityAge * 4.5) % frames.count
        case .walk:
            frames = facingRight ? rightFrames : leftFrames
            index = Int(walkAnimationPhase) % frames.count
        case .think:
            frames = thinkFrames; index = Int(activityAge * 5.0) % frames.count
        case .wait:
            frames = waitingFrames; index = Int(activityAge * 5.0) % frames.count
        case .look:
            frames = lookFrames
            index = min(frames.count - 1, Int(activityAge / activityDuration * Double(frames.count)))
        case .wave:
            frames = waveFrames; index = Int(activityAge * 7.0) % frames.count
        case .handshake:
            frames = waveFrames
            index = [0, 1, 1, 1, 2, 1, 1, 3][Int(activityAge * 6.0) % 8]
            bob = 1.5 * abs(sin(activityAge * 9.0))
            mirrorImage = facingRight
        case .dance:
            frames = jumpFrames
            index = [0, 1, 2, 2, 3, 4, 0, 1, 2, 3][Int(activityAge * 7.0) % 10]
            bob = 7.0 * abs(sin(activityAge * 10.0))
            sway = 3.0 * sin(activityAge * 6.0) * (facingRight ? 1 : -1)
        case .conversation:
            let speaking = (Int(activityAge / 0.8).isMultiple(of: 2)) == facingRight
            if speaking {
                frames = waveFrames
                index = Int(activityAge * 7.0) % frames.count
                mirrorImage = facingRight
                bob = 1.2 * abs(sin(activityAge * 8.0))
            } else {
                frames = lookFrames
                index = facingRight ? 3 : 14
            }
        case .duoFlip:
            let start = facingRight ? 0.2 : 1.5
            let t = (activityAge - start) / 1.15
            if (0..<1).contains(t) {
                frames = backflipFrames
                index = min(frames.count - 1, Int(t * Double(frames.count)))
                bob = 46.0 * 4.0 * t * (1.0 - t)
            } else {
                frames = waveFrames
                index = Int(activityAge * 6.0) % frames.count
                mirrorImage = facingRight
            }
        case .sharedLaugh:
            frames = laughFrames
            index = min(frames.count - 1, Int(activityAge / activityDuration * Double(frames.count)))
            bob = 2.5 * abs(sin(activityAge * 12.0))
        case .jump:
            frames = jumpFrames
            index = min(frames.count - 1, Int(activityAge / activityDuration * Double(frames.count)))
        case .backflip:
            frames = backflipFrames
            let t = min(1.0, activityAge / activityDuration)
            index = min(frames.count - 1, Int(t * Double(frames.count)))
            bob = 46.0 * 4.0 * t * (1.0 - t)
        case .review:
            frames = reviewFrames; index = Int(activityAge * 5.0) % frames.count
        case .bump:
            frames = bumpFrames
            index = min(frames.count - 1, Int(activityAge / activityDuration * Double(frames.count)))
        case .laugh:
            frames = laughFrames
            index = min(frames.count - 1, Int(activityAge / activityDuration * Double(frames.count)))
        case .surprise:
            frames = surpriseFrames
            index = min(frames.count - 1, Int(activityAge / activityDuration * Double(frames.count)))
        case .pout:
            frames = poutFrames
            index = min(frames.count - 1, Int(activityAge / activityDuration * Double(frames.count)))
        case .context:
            frames = contextFrames
            index = min(frames.count - 1, Int(activityAge / activityDuration * Double(frames.count)))
        case .selection:
            frames = selectionFrames
            index = min(frames.count - 1, Int(activityAge / activityDuration * Double(frames.count)))
        case .rest:
            frames = restFrames; index = 0
        case .sleep:
            frames = sleepFrames
            if activityAge < 0.45 || activityAge >= activityDuration - 0.6 {
                index = 0
            } else if activityAge < 1.3 {
                index = 1
            } else {
                index = 2
                bob = 0.6 * max(0, sin(activityAge * 2.4))
            }
        case .attend:
            let recentlyTyping = attentionTyping
                && ProcessInfo.processInfo.systemUptime - lastKeyAt < 1.0
            if recentlyTyping {
                frames = thinkFrames
                index = Int(activityAge * 8.0) % frames.count
                let sinceKey = ProcessInfo.processInfo.systemUptime - lastKeyAt
                typingPose = sinceKey < 0.19 ? (typingKeyCount.isMultiple(of: 2) ? 1 : 2) : 0
            } else {
                frames = lookFrames
                index = attentionLookIndex
            }
        case .carried:
            frames = carryFrames
            let sequence = [0, 1, 0, 2, 0, 3, 4, 5]
            index = sequence[Int(activityAge * 8.0) % sequence.count]
        case .falling:
            frames = jumpFrames
            index = y - currentGroundY() < 22 ? 0 : (fallVelocity > 0 ? 1 : 2)
        case .land:
            frames = landingFrames
            switch activityAge {
            case ..<0.13: index = 0 // impact
            case ..<0.31: index = 1 // sits down
            case ..<0.65: index = 2 // catches breath
            case ..<0.84: index = 3 // pushes up
            case ..<1.07: index = 4 // crouches
            default: index = 5 // stands before walking
            }
        }
        window.setFrameOrigin(NSPoint(x: x + sway, y: y + bob))
        view.typingPose = typingPose
        view.mirrorImage = mirrorImage
        view.image = frames[index]
    }

    private func showMenu() {
        let menu = NSMenu()
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let versionItem = NSMenuItem(title: "Codex Promenade \(version)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        if let iconURL = Bundle.main.url(forResource: "CodexPromenade-icon", withExtension: "png"),
           let icon = NSImage(contentsOf: iconURL) {
            icon.size = NSSize(width: 20, height: 20)
            versionItem.image = icon
        }
        menu.addItem(versionItem)
        menu.addItem(NSMenuItem.separator())
        let addCompanion = menu.addItem(withTitle: "Ajouter un compagnon", action: #selector(addCompanion), keyEquivalent: "")
        addCompanion.isEnabled = PetController.companions.count < PetController.companionLimit
        if PetController.companions.count > 1 {
            menu.addItem(withTitle: "Retirer ce compagnon", action: #selector(removeCompanion), keyEquivalent: "")
        }
        let together = menu.addItem(withTitle: "Faire une activité à deux", action: #selector(triggerTogether), keyEquivalent: "")
        together.isEnabled = nearestAvailableCompanion() != nil
            && activity != .carried && activity != .falling && activity != .land
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Faire un salto arrière", action: #selector(triggerBackflip), keyEquivalent: "")
        menu.addItem(withTitle: "Saluer", action: #selector(triggerWave), keyEquivalent: "")
        menu.addItem(withTitle: "Rire", action: #selector(triggerLaugh), keyEquivalent: "")
        menu.addItem(withTitle: "Être surpris", action: #selector(triggerSurprise), keyEquivalent: "")
        menu.addItem(withTitle: "Bouder", action: #selector(triggerPout), keyEquivalent: "")
        menu.addItem(withTitle: "Se reposer", action: #selector(triggerRest), keyEquivalent: "")
        menu.addItem(withTitle: "Dormir", action: #selector(triggerSleep), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: attentionEnabled ? "Réactions aux actions : activées" : "Réactions aux actions : désactivées",
                     action: #selector(toggleAttention), keyEquivalent: "")
        let focusStatus = NSMenuItem(title: AXIsProcessTrusted() ? "Focus précis : disponible" : "Focus précis : indisponible sur ce Mac",
                                     action: nil, keyEquivalent: "")
        focusStatus.isEnabled = false
        menu.addItem(focusStatus)
        let selectionStatus = NSMenuItem(title: AXIsProcessTrusted() ? "Sélection de texte : disponible" : "Sans Accessibilité : réaction au glisser",
                                         action: nil, keyEquivalent: "")
        selectionStatus.isEnabled = false
        menu.addItem(selectionStatus)
        let keyboardStatus = NSMenuItem(title: keyboardAccessAvailable ? "Clavier : disponible" : "Clavier : indisponible sur ce Mac",
                                        action: nil, keyEquivalent: "")
        keyboardStatus.isEnabled = false
        menu.addItem(keyboardStatus)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: paused ? "Reprendre" : "Pause", action: #selector(togglePause), keyEquivalent: "")
        menu.addItem(withTitle: "Ouvrir ChatGPT", action: #selector(openChatGPT), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quitter", action: #selector(quit), keyEquivalent: "")
        for item in menu.items { item.target = self }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc private func triggerBackflip() {
        paused = false
        firstJourney = false
        nextBackflipAt = ProcessInfo.processInfo.systemUptime + Double.random(in: 35...60)
        begin(.backflip, duration: 1.15)
    }
    @objc private func triggerWave() {
        paused = false
        firstJourney = false
        nextWaveAt = ProcessInfo.processInfo.systemUptime + Double.random(in: 22...40)
        begin(.wave, duration: 1.45)
    }
    @objc private func triggerLaugh() {
        paused = false
        firstJourney = false
        nextLaughAt = ProcessInfo.processInfo.systemUptime + Double.random(in: 25...45)
        begin(.laugh, duration: 1.55)
    }
    @objc private func triggerSurprise() {
        paused = false
        firstJourney = false
        begin(.surprise, duration: 1.35)
    }
    @objc private func triggerPout() {
        paused = false
        firstJourney = false
        begin(.pout, duration: 1.75)
    }
    @objc private func triggerRest() {
        paused = false
        firstJourney = false
        nextRestAt = ProcessInfo.processInfo.systemUptime + Double.random(in: 65...110)
        begin(.rest, duration: 6)
    }
    @objc private func triggerSleep() {
        paused = false
        firstJourney = false
        nextRestAt = ProcessInfo.processInfo.systemUptime + Double.random(in: 65...110)
        begin(.sleep, duration: 14)
    }
    @objc private func addCompanion() {
        guard PetController.companions.count < PetController.companionLimit else { return }
        if activity == .context { begin(.idle, duration: 0.6) }
        let companion = PetController()
        companion.launch(near: self)
        let now = ProcessInfo.processInfo.systemUptime
        let neighbors = PetController.companions.filter {
            $0 !== companion && $0.canSocialize
                && abs($0.y - companion.y) <= 14
                && (55...125).contains(abs($0.x - companion.x))
        }
        if let nearest = neighbors.min(by: {
            abs($0.x - companion.x) < abs($1.x - companion.x)
        }) {
            nearest.startSocial(with: companion, kind: .handshake, at: now)
        }
    }
    @objc private func removeCompanion() {
        guard PetController.companions.count > 1 else { return }
        stop()
        PetController.companions.removeAll { $0 === self }
    }
    @objc private func triggerTogether() {
        guard activity != .carried && activity != .falling && activity != .land else { return }
        paused = false
        firstJourney = false
        if !canSocialize { begin(.idle, duration: 0.6) }
        guard let partner = nearestAvailableCompanion() else { return }
        let kind: Activity = [.conversation, .duoFlip, .sharedLaugh].randomElement() ?? .conversation
        startSocial(with: partner, kind: kind, at: ProcessInfo.processInfo.systemUptime)
    }
    @objc private func toggleAttention() {
        attentionEnabled.toggle()
        if !attentionEnabled && activity == .attend { startWalk() }
        if attentionEnabled { handleApplicationActivation() }
    }
    @objc private func togglePause() {
        if !paused && activity.isSocial {
            begin(.idle, duration: 0.6)
        }
        paused.toggle()
    }
    @objc private func openChatGPT() {
        let systemFallback = URL(fileURLWithPath: "/Applications/ChatGPT.app")
        let userFallback = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/ChatGPT.app")
        let registered = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex")
        guard let appURL = [registered, systemFallback, userFallback].compactMap({ $0 }).first(where: {
            FileManager.default.fileExists(atPath: $0.path)
        }) else {
            let alert = NSAlert()
            alert.messageText = "ChatGPT est introuvable."
            alert.informativeText = "Installez ChatGPT pour utiliser cette commande."
            alert.runModal()
            return
        }
        NSWorkspace.shared.openApplication(at: appURL,
                                           configuration: NSWorkspace.OpenConfiguration()) { _, error in
            guard let error else { return }
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Impossible d’ouvrir ChatGPT."
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }
    @objc private func quit() { NSApp.terminate(nil) }
}

private extension NSRect {
    var center: NSPoint { NSPoint(x: midX, y: midY) }
}

let app = NSApplication.shared
let controller = PetController()
app.delegate = controller
app.run()
