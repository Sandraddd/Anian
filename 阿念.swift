import AppKit
import EventKit
import Foundation
import QuartzCore
import UserNotifications

struct PetSettings {
    static let todos = "anian.native.todos"
    static let walkMode = "anian.native.walkMode"
    static let pomodoroEnabled = "anian.native.pomodoroEnabled"
    static let pomodoroEndDate = "anian.native.pomodoroEndDate"
    static let pomodoroIsBreak = "anian.native.pomodoroIsBreak"
    static let pomodoroTimerMode = "anian.native.pomodoroTimerMode"
    static let pomodoroCountUpStartDate = "anian.native.pomodoroCountUpStartDate"
    static let pomodoroActiveFocusMinutes = "anian.native.pomodoroActiveFocusMinutes"
    static let pomodoroFocusMinutes = "anian.native.pomodoroFocusMinutes"
    static let pomodoroRestMinutes = "anian.native.pomodoroRestMinutes"
    static let pomodoroLinkedTodoID = "anian.native.pomodoroLinkedTodoID"
    static let pomodoroFocusDay = "anian.native.pomodoroFocusDay"
    static let pomodoroFocusSessions = "anian.native.pomodoroFocusSessions"
    static let pomodoroFocusTotalMinutes = "anian.native.pomodoroFocusTotalMinutes"
    static let pomodoroFocusMonth = "anian.native.pomodoroFocusMonth"
    static let pomodoroMonthFocusSessions = "anian.native.pomodoroMonthFocusSessions"
    static let pomodoroMonthFocusTotalMinutes = "anian.native.pomodoroMonthFocusTotalMinutes"
    static let pomodoroMonthRewardLevel = "anian.native.pomodoroMonthRewardLevel"
    static let onboardingSeen = "anian.native.onboardingSeen"
    static let completionStreak = "anian.native.completionStreak"
    static let completionStreakDay = "anian.native.completionStreakDay"
    static let firstCompletionDay = "anian.native.firstCompletionDay"
    static let calendarSyncSuppressedDay = "anian.native.calendarSyncSuppressedDay"
    static let suppressedCalendarTodoKeys = "anian.native.suppressedCalendarTodoKeys"
}

struct TodoItem: Codable {
    var title: String
    var done: Bool
    var calendarKey: String? = nil
    var id: String? = nil
    var pomodoroSeconds: Int? = nil
    var completedAt: Date? = nil
    var syncedReminderID: String? = nil
}

enum WalkMode: Int {
    case horizontal = 0
    case vertical = 1
    case fourWay = 2
    case still = 3
}

private enum PomodoroTimerMode: Int {
    case countdown = 0
    case countUp = 1
}

private enum MessagePriority: Int {
    case ambient = 0
    case onboarding = 1
    case todo = 2
    case pomodoro = 3
    case reminder = 4
}

private enum CelebrationStyle {
    case small
    case medium
    case big
}

private struct PomodoroReward {
    let minutes: Int
    let name: String
    let emoji: String
    let line: String
    let stickerEmojis: [String]
}

private enum PetLineLibrary {
    static func load() -> [String: [String]] {
        guard let url = Bundle.main.url(forResource: "dog_pet_lines", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }

        var lines: [String: [String]] = [:]
        for (category, value) in root {
            guard let categoryLines = value as? [String] else { continue }
            let usableLines = categoryLines.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            if !usableLines.isEmpty {
                lines[category] = usableLines
            }
        }
        return lines
    }
}

final class PetPanel: NSPanel {
    var allowsPetFrameOutsideScreen = false

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        if allowsPetFrameOutsideScreen {
            return frameRect
        }
        return super.constrainFrameRect(frameRect, to: screen)
    }
}

final class PetContentView: NSView {
    var onBlankClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if hitTest(point) === self {
            onBlankClick?()
            return
        }
        super.mouseDown(with: event)
    }
}

final class CenteredLabel: NSTextField {
    override func draw(_ dirtyRect: NSRect) {
        guard let cell = cell else {
            super.draw(dirtyRect)
            return
        }
        let textSize = cell.cellSize(forBounds: bounds)
        let yOffset = max(0, (bounds.height - textSize.height) / 2)
        let centeredRect = NSRect(
            x: bounds.origin.x,
            y: bounds.origin.y + yOffset,
            width: bounds.width,
            height: textSize.height
        )
        cell.draw(withFrame: centeredRect, in: self)
    }
}

final class PassthroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

final class TodoInputTextView: NSTextView {
    var onSubmit: (() -> Void)?

    override func insertNewline(_ sender: Any?) {
        let flags = NSApp.currentEvent?.modifierFlags ?? []
        if flags.contains(.shift) || flags.contains(.option) {
            super.insertNewline(sender)
        } else {
            onSubmit?()
        }
    }
}

final class EmojiBurstOverlayView: NSView {
    enum Style {
        case allEdgesEmoji
        case sideRibbons
    }

    private struct Piece {
        var start: NSPoint
        var end: NSPoint
        var emoji: String
        var fontSize: CGFloat
        var rotation: CGFloat
        var delay: CGFloat
    }

    private var pieces: [Piece] = []
    private let style: Style
    var progress: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    init(frame frameRect: NSRect, style: Style = .allEdgesEmoji, emojis: [String]? = nil) {
        self.style = style
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        pieces = Self.makePieces(in: frameRect.size, style: style, customEmojis: emojis)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func makePieces(in size: CGSize, style: Style, customEmojis: [String]? = nil) -> [Piece] {
        if style == .sideRibbons {
            return makeBottomCornerRibbonPieces(in: size, customEmojis: customEmojis)
        }

        let defaultEmojis = ["🐾", "💙", "🫧", "🔹", "🐾", "✨", "🍅", "⭐"]
        let emojis = customEmojis?.isEmpty == false ? customEmojis! : defaultEmojis
        var result: [Piece] = []
        let count = 96
        for i in 0..<count {
            let side = i % 4
            let edgeInset: CGFloat = 28
            let start: NSPoint
            let end: NSPoint
            switch side {
            case 0: // left
                let y = CGFloat.random(in: edgeInset...(size.height - edgeInset))
                start = NSPoint(x: CGFloat.random(in: 10...44), y: y)
                end = NSPoint(x: CGFloat.random(in: 110...360), y: y + CGFloat.random(in: -80...80))
            case 1: // right
                let y = CGFloat.random(in: edgeInset...(size.height - edgeInset))
                start = NSPoint(x: size.width - CGFloat.random(in: 10...44), y: y)
                end = NSPoint(x: size.width - CGFloat.random(in: 110...360), y: y + CGFloat.random(in: -80...80))
            case 2: // top
                let x = CGFloat.random(in: edgeInset...(size.width - edgeInset))
                start = NSPoint(x: x, y: size.height - CGFloat.random(in: 10...44))
                end = NSPoint(x: x + CGFloat.random(in: -150...150), y: size.height - CGFloat.random(in: 150...330))
            default: // bottom
                let x = CGFloat.random(in: edgeInset...(size.width - edgeInset))
                start = NSPoint(x: x, y: CGFloat.random(in: 10...44))
                end = NSPoint(x: x + CGFloat.random(in: -150...150), y: CGFloat.random(in: 140...310))
            }
            result.append(Piece(
                start: start,
                end: end,
                emoji: emojis.randomElement() ?? "✨",
                fontSize: CGFloat.random(in: 18...30),
                rotation: CGFloat.random(in: -0.55...0.55),
                delay: CGFloat.random(in: 0...0.18)
            ))
        }
        return result
    }

    private static func makeBottomCornerRibbonPieces(in size: CGSize, customEmojis: [String]? = nil) -> [Piece] {
        let defaultEmojis = ["🎊", "✨", "🍅", "🐾", "💫"]
        let emojis = customEmojis?.isEmpty == false ? customEmojis! : defaultEmojis
        var result: [Piece] = []
        let count = 118

        func random(_ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
            CGFloat.random(in: min(lower, upper)...max(lower, upper))
        }

        for i in 0..<count {
            let fromLeft = i % 2 == 0
            let cornerInset = random(8, 58)
            let start = NSPoint(
                x: fromLeft ? cornerInset : size.width - cornerInset,
                y: random(8, 42)
            )

            let endY: CGFloat
            if i % 5 == 0 {
                endY = random(size.height * 0.72, size.height - 28)
            } else if i % 7 == 0 {
                endY = random(size.height * 0.18, size.height * 0.36)
            } else {
                endY = random(size.height * 0.34, size.height * 0.86)
            }

            let end = NSPoint(
                x: random(34, size.width - 34),
                y: endY
            )

            result.append(Piece(
                start: start,
                end: end,
                emoji: emojis.randomElement() ?? "🎊",
                fontSize: random(15, 27),
                rotation: random(-0.8, 0.8),
                delay: random(0, 0.16)
            ))
        }

        return result
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        for piece in pieces {
            let local = max(0, min(1, (progress - piece.delay) / max(0.01, 1 - piece.delay)))
            guard local > 0 && local < 1 else { continue }
            let eased = 1 - pow(1 - local, 3)
            let x = piece.start.x + (piece.end.x - piece.start.x) * eased
            let gravity: CGFloat = style == .sideRibbons ? 64 : 120
            let y = piece.start.y + (piece.end.y - piece.start.y) * eased - gravity * local * local
            let alpha = Double(max(0, min(1, 1 - local * 0.92)))
            context.saveGState()
            context.translateBy(x: x, y: y)
            context.rotate(by: piece.rotation + local * 1.2)
            context.setAlpha(CGFloat(alpha))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: piece.fontSize)
            ]
            let measured = (piece.emoji as NSString).size(withAttributes: attributes)
            let rect = NSRect(x: -measured.width / 2, y: -measured.height / 2, width: measured.width, height: measured.height)
            (piece.emoji as NSString).draw(in: rect, withAttributes: attributes)
            context.restoreGState()
        }
    }
}

enum PetMood: String {
    case walking
    case idle
    case sleepy
    case curious
    case reminding
    case celebrating

    var tag: String {
        switch self {
        case .walking: return "专注中"
        case .idle: return "陪伴中"
        case .sleepy: return "睡着了"
        case .curious: return "观察中"
        case .reminding: return "提醒你"
        case .celebrating: return "完成啦"
        }
    }

    var line: String {
        switch self {
        case .walking: return "阿念原地陪你专注，不离开当前位置。"
        case .idle: return "阿念坐好陪着你。"
        case .sleepy: return "困了，先趴一小会儿。"
        case .curious: return "我看看你在干嘛。"
        case .reminding: return "该喝水啦。"
        case .celebrating: return "摇尾巴庆祝一下！"
        }
    }

    var usesWalkingPose: Bool {
        self == .walking
    }

    var usesSittingPose: Bool {
        true
    }
}

enum PetProgressMode {
    case empty
    case todos
    case focus
    case rest
}

final class SpritePetView: NSView {
    private static let spriteSheet: NSImage? = {
        let names = ["sprite_sheet", "pet1 3"]
        for name in names {
            if let path = Bundle.main.path(forResource: name, ofType: "png"),
               let image = NSImage(contentsOfFile: path) {
                return image
            }
        }
        if let execPath = Bundle.main.executablePath {
            let execDir = (execPath as NSString).deletingLastPathComponent
            for path in ["\(execDir)/sprite_sheet.png", "\(execDir)/../Resources/sprite_sheet.png"] {
                if let image = NSImage(contentsOfFile: path) { return image }
            }
        }
        return nil
    }()

    // Exact non-empty cells from the supplied 4x11 atlas. Empty cells are
    // excluded so an action can never flash a transparent/missing frame.
    private static let animationFrames: [PetMood: [Int]] = [
        .idle: [0, 1, 2, 3, 4, 5],
        .celebrating: [8, 9, 10, 11, 12, 13, 14],
        .walking: [16, 17, 18, 19, 20, 21],
        .sleepy: [36, 37, 38, 39, 40, 41, 42, 43],
        .curious: [0, 1, 2, 3, 4, 5],
        .reminding: [24, 25, 26, 27, 28, 29, 30, 31, 32, 33],
    ]

    var mood: PetMood = .idle { didSet { needsDisplay = true } }
    var frameIndex = 0 { didSet { needsDisplay = true } }
    var facing: CGFloat = -1 { didSet { needsDisplay = true } }
    var progressValue: CGFloat = 0 { didSet { needsDisplay = true } }
    var progressMode: PetProgressMode = .empty { didSet { needsDisplay = true } }
    var progressFlash = false { didSet { needsDisplay = true } }
    var forceStandingPose = false { didSet { needsDisplay = true } }
    var onHoverBegan: (() -> Void)?
    var onHoverEnded: (() -> Void)?
    var onHeadHover: (() -> Void)?
    var onNoseClick: (() -> Void)?
    var onRightClick: ((NSEvent) -> Void)?

    private var trackingArea: NSTrackingArea?
    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { onHoverBegan?() }
    override func mouseExited(with event: NSEvent) { onHoverEnded?() }
    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if isPointOverHead(point) { onHeadHover?() }
    }
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { onRightClick?(event); return }
        super.mouseDown(with: event)
    }
    override func rightMouseDown(with event: NSEvent) { onRightClick?(event) }
    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if isPointOverNose(point) { onNoseClick?() }
        super.mouseUp(with: event)
    }

    private func isPointOverHead(_ point: NSPoint) -> Bool {
        NSRect(x: bounds.midX - bounds.width * 0.42,
               y: bounds.midY - bounds.height * 0.38,
               width: bounds.width * 0.84,
               height: bounds.height * 0.62).contains(point)
    }

    private func isPointOverNose(_ point: NSPoint) -> Bool {
        NSRect(x: bounds.midX - bounds.width * 0.18,
               y: bounds.midY - bounds.height * 0.12,
               width: bounds.width * 0.36,
               height: bounds.height * 0.24).contains(point)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()
        guard let context = NSGraphicsContext.current?.cgContext,
              let sheet = Self.spriteSheet,
              let image = sheet.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }

        let frameWidth = sheet.size.width / 4
        let frameHeight = sheet.size.height / 11
        let frames = Self.animationFrames[mood] ?? Self.animationFrames[.idle]!
        // Triggered actions are finite: idle/curious/sleepy play once,
        // celebration/reminder play twice, then hold their final pose. The
        // focus run is the only continuous sequence and is bounded by the
        // active Pomodoro session.
        let sequenceIndex: Int
        switch mood {
        case .walking:
            sequenceIndex = frameIndex % frames.count
        case .celebrating, .reminding:
            sequenceIndex = min(frameIndex, frames.count * 2 - 1) % frames.count
        case .idle, .curious, .sleepy:
            sequenceIndex = min(frameIndex, frames.count - 1)
        }
        let frame = frames[sequenceIndex]
        let row = frame / 4
        let column = frame % 4
        let source = CGRect(x: CGFloat(column) * frameWidth,
                            y: CGFloat(row) * frameHeight,
                            width: frameWidth,
                            height: frameHeight)
        guard let sprite = image.cropping(to: source) else { return }

        context.saveGState()
        context.interpolationQuality = .none
        context.setShouldAntialias(false)
        let destination = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height)
        // NSView is flipped for hit testing/layout, while CGImage drawing uses
        // an upward Y axis. Flip the drawing context once so the supplied
        // sprite is shown exactly as authored.
        context.translateBy(x: 0, y: destination.height)
        context.scaleBy(x: 1, y: -1)
        // The supplied running frames already face right. Mirror only when
        // the controller asks the pet to face left.
        if facing < 0 {
            context.translateBy(x: destination.midX, y: 0)
            context.scaleBy(x: -1, y: 1)
            context.translateBy(x: -destination.midX, y: 0)
        }
        context.draw(sprite, in: destination)
        context.restoreGState()

    }
}



final class TodoRowView: NSView {
    let checkbox: NSButton
    private let pawStamp: NSTextField?
    private let detailLabel: NSTextField?

    init(checkbox: NSButton, done: Bool, menu: NSMenu?, detail: String? = nil) {
        self.checkbox = checkbox
        self.pawStamp = done ? NSTextField(labelWithString: "🐾") : nil
        self.detailLabel = detail.map { NSTextField(labelWithString: $0) }
        super.init(frame: .zero)
        self.menu = menu
        checkbox.menu = menu
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.backgroundColor = done
            ? NSColor(hex: 0xF2F7FC, alpha: 0.72).cgColor
            : NSColor(hex: 0xFFFFFF, alpha: 0.30).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = done
            ? NSColor(hex: 0xB8CCE1, alpha: 0.62).cgColor
            : NSColor(hex: 0xFFFFFF, alpha: 0.32).cgColor
        layer?.shadowOpacity = done ? 0.08 : 0.035
        layer?.shadowRadius = done ? 6 : 3
        layer?.shadowOffset = CGSize(width: 0, height: -1)

        checkbox.translatesAutoresizingMaskIntoConstraints = false
        addSubview(checkbox)

        if let detailLabel {
            detailLabel.translatesAutoresizingMaskIntoConstraints = false
            detailLabel.font = .systemFont(ofSize: 12, weight: .semibold)
            detailLabel.textColor = done ? NSColor(hex: 0x347A4E, alpha: 0.82) : NSColor(hex: 0x8B6472)
            detailLabel.drawsBackground = false
            detailLabel.lineBreakMode = .byTruncatingTail
            addSubview(detailLabel)
        }

        if let pawStamp {
            pawStamp.translatesAutoresizingMaskIntoConstraints = false
            pawStamp.font = .systemFont(ofSize: 18, weight: .bold)
            pawStamp.textColor = NSColor(hex: 0x4A7DB5)
            pawStamp.alignment = .center
            pawStamp.setContentHuggingPriority(.required, for: .horizontal)
            pawStamp.setContentCompressionResistancePriority(.required, for: .horizontal)
            addSubview(pawStamp)

            if let detailLabel {
                NSLayoutConstraint.activate([
                    heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
                    checkbox.topAnchor.constraint(equalTo: topAnchor, constant: 5),
                    checkbox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
                    checkbox.trailingAnchor.constraint(lessThanOrEqualTo: pawStamp.leadingAnchor, constant: -6),
                    detailLabel.topAnchor.constraint(equalTo: checkbox.bottomAnchor, constant: 1),
                    detailLabel.leadingAnchor.constraint(equalTo: checkbox.leadingAnchor, constant: 3),
                    detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: pawStamp.leadingAnchor, constant: -6),
                    detailLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
                    pawStamp.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
                    pawStamp.centerYAnchor.constraint(equalTo: centerYAnchor)
                ])
            } else {
                NSLayoutConstraint.activate([
                    heightAnchor.constraint(greaterThanOrEqualToConstant: 30),
                    checkbox.topAnchor.constraint(equalTo: topAnchor, constant: 5),
                    checkbox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
                    checkbox.trailingAnchor.constraint(lessThanOrEqualTo: pawStamp.leadingAnchor, constant: -6),
                    checkbox.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
                    pawStamp.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
                    pawStamp.centerYAnchor.constraint(equalTo: centerYAnchor)
                ])
            }
        } else {
            if let detailLabel {
                NSLayoutConstraint.activate([
                    heightAnchor.constraint(greaterThanOrEqualToConstant: 40),
                    checkbox.topAnchor.constraint(equalTo: topAnchor, constant: 4),
                    checkbox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
                    checkbox.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
                    detailLabel.topAnchor.constraint(equalTo: checkbox.bottomAnchor, constant: 1),
                    detailLabel.leadingAnchor.constraint(equalTo: checkbox.leadingAnchor, constant: 3),
                    detailLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
                    detailLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5)
                ])
            } else {
                NSLayoutConstraint.activate([
                    heightAnchor.constraint(greaterThanOrEqualToConstant: 28),
                    checkbox.topAnchor.constraint(equalTo: topAnchor, constant: 4),
                    checkbox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
                    checkbox.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
                    checkbox.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
                ])
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class BubbleView: NSView {
    private let glassView = NSVisualEffectView()
    private let rimView = PassthroughView()
    let moodLabel = NSTextField(wrappingLabelWithString: "今天干什么大事汪")
    let todoButton = NSPopUpButton()
    let stopButton = NSButton(title: "同步日历", target: nil, action: nil)
    let quitButton = NSButton(title: "退出面板", target: nil, action: nil)
    let settingsButton = NSButton(title: "", target: nil, action: nil)
    let todoScrollView = NSScrollView()
    let todoStackView = NSStackView()
    let newTodoScrollView = NSScrollView()
    let newTodoTextView = TodoInputTextView()
    let addTodoButton = NSButton(title: "+", target: nil, action: nil)
    let clearTodoButton = NSButton(title: "清空已完成", target: nil, action: nil)
    let focusMinutesField = NSTextField()
    let restMinutesField = NSTextField()
    let pomodoroModeControl = NSSegmentedControl()
    let pomodoroTodoPopup = NSPopUpButton()
    let pomodoroCountdownLabel = NSTextField(labelWithString: "番茄钟未开始")
    let pomodoroRecordLabel = NSTextField(labelWithString: "今日累计 0 轮 · 0 分钟")
    let pomodoroMonthLabel = NSTextField(labelWithString: "本月 0分钟 · 距启程爪印还差 2小时")
    let pomodoroCheck = NSButton(title: "🍅 开始", target: nil, action: nil)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        appearance = NSAppearance(named: .aqua)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.cornerRadius = 18
        layer?.shadowOpacity = 0.22
        layer?.shadowRadius = 24
        layer?.shadowOffset = CGSize(width: 0, height: -10)

        glassView.material = .hudWindow
        glassView.blendingMode = .behindWindow
        glassView.state = .active
        glassView.wantsLayer = true
        glassView.layer?.cornerRadius = 18
        glassView.layer?.masksToBounds = true

        rimView.wantsLayer = true
        rimView.layer?.backgroundColor = NSColor(hex: 0xFFFFFF, alpha: 0.10).cgColor
        rimView.layer?.borderWidth = 1
        rimView.layer?.borderColor = NSColor(hex: 0xFFFFFF, alpha: 0.46).cgColor
        rimView.layer?.cornerRadius = 18

        moodLabel.font = .systemFont(ofSize: 13, weight: .bold)
        moodLabel.textColor = NSColor(hex: 0x1E2230)
        moodLabel.drawsBackground = false
        moodLabel.alignment = .center
        moodLabel.maximumNumberOfLines = 2
        moodLabel.lineBreakMode = .byTruncatingTail
        moodLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        todoButton.addItems(withTitles: ["坐下", "四处走", "原地跳", "累死"])
        todoButton.bezelStyle = .rounded
        todoButton.font = .systemFont(ofSize: 12, weight: .bold)
        todoButton.contentTintColor = NSColor(hex: 0x4A7DB5)

        stopButton.bezelStyle = .rounded
        stopButton.font = .systemFont(ofSize: 12, weight: .bold)
        stopButton.contentTintColor = NSColor(hex: 0x1E2230)

        quitButton.bezelStyle = .rounded
        quitButton.font = .systemFont(ofSize: 12, weight: .bold)
        quitButton.contentTintColor = NSColor(hex: 0x4A7DB5)

        settingsButton.bezelStyle = .rounded
        settingsButton.image = NSImage(
            systemSymbolName: "pawprint.fill",
            accessibilityDescription: "设置"
        )
        settingsButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .bold)
        settingsButton.imagePosition = .imageOnly
        settingsButton.contentTintColor = NSColor(hex: 0x7FAAD4)

        todoStackView.orientation = .vertical
        todoStackView.alignment = .leading
        todoStackView.spacing = 4
        todoStackView.edgeInsets = NSEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        todoScrollView.documentView = todoStackView
        todoScrollView.hasVerticalScroller = true
        todoScrollView.drawsBackground = true
        // Clearer liquid card for the todo list: still glassy, but no longer washed out.
        todoScrollView.backgroundColor = NSColor(hex: 0xFFFFFF, alpha: 0.68)
        todoScrollView.borderType = .noBorder
        todoScrollView.wantsLayer = true
        todoScrollView.layer?.cornerRadius = 12
        todoScrollView.layer?.borderWidth = 1.2
        todoScrollView.layer?.borderColor = NSColor(hex: 0xB8CCE1, alpha: 0.48).cgColor
        todoScrollView.layer?.shadowOpacity = 0.08
        todoScrollView.layer?.shadowRadius = 10
        todoScrollView.layer?.shadowOffset = CGSize(width: 0, height: -3)

        newTodoTextView.font = .systemFont(ofSize: 12, weight: .medium)
        newTodoTextView.textColor = NSColor(hex: 0x1E2230)
        newTodoTextView.backgroundColor = NSColor.clear
        newTodoTextView.drawsBackground = false
        newTodoTextView.insertionPointColor = NSColor(hex: 0x1E2230)
        newTodoTextView.textContainerInset = NSSize(width: 8, height: 7)
        newTodoTextView.string = ""
        newTodoScrollView.documentView = newTodoTextView
        newTodoScrollView.hasVerticalScroller = true
        newTodoScrollView.drawsBackground = true
        // Clearer input card: keeps the liquid feel, with stronger edge and readable typing area.
        newTodoScrollView.backgroundColor = NSColor(hex: 0xFFFFFF, alpha: 0.72)
        newTodoScrollView.borderType = .noBorder
        newTodoScrollView.wantsLayer = true
        newTodoScrollView.layer?.cornerRadius = 12
        newTodoScrollView.layer?.borderWidth = 1.2
        newTodoScrollView.layer?.borderColor = NSColor(hex: 0xB8CCE1, alpha: 0.52).cgColor
        newTodoScrollView.layer?.shadowOpacity = 0.09
        newTodoScrollView.layer?.shadowRadius = 9
        newTodoScrollView.layer?.shadowOffset = CGSize(width: 0, height: -2)

        addTodoButton.title = "🐾 发送"
        addTodoButton.bezelStyle = .rounded
        addTodoButton.font = .systemFont(ofSize: 13, weight: .bold)
        addTodoButton.contentTintColor = NSColor(hex: 0x4A7DB5)

        clearTodoButton.bezelStyle = .rounded
        clearTodoButton.font = .systemFont(ofSize: 13, weight: .bold)
        clearTodoButton.contentTintColor = NSColor(hex: 0x4A7DB5)

        focusMinutesField.placeholderString = "专注"
        restMinutesField.placeholderString = "休息"
        [focusMinutesField, restMinutesField].forEach {
            $0.font = .systemFont(ofSize: 12)
            $0.textColor = NSColor(hex: 0x1E2230)
            $0.backgroundColor = NSColor(hex: 0xFFFFFF, alpha: 0.42)
            $0.drawsBackground = true
            $0.alignment = .center
            $0.isBezeled = false
            $0.wantsLayer = true
            $0.layer?.cornerRadius = 7
            $0.layer?.borderWidth = 1
            $0.layer?.borderColor = NSColor(hex: 0xFFFFFF, alpha: 0.36).cgColor
        }
        pomodoroCountdownLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        pomodoroCountdownLabel.textColor = NSColor(hex: 0x1E2230)
        pomodoroCountdownLabel.alignment = .center
        pomodoroRecordLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        pomodoroRecordLabel.textColor = NSColor(hex: 0x5B5460)
        pomodoroRecordLabel.alignment = .center
        pomodoroMonthLabel.font = .systemFont(ofSize: 11, weight: .bold)
        pomodoroMonthLabel.textColor = NSColor(hex: 0x4A7DB5)
        pomodoroMonthLabel.alignment = .center
        pomodoroMonthLabel.lineBreakMode = .byTruncatingTail
        pomodoroTodoPopup.addItem(withTitle: "不绑定待办")
        pomodoroTodoPopup.bezelStyle = .rounded
        pomodoroTodoPopup.font = .systemFont(ofSize: 12, weight: .semibold)
        pomodoroTodoPopup.contentTintColor = NSColor(hex: 0x1E2230)
        pomodoroModeControl.segmentCount = 2
        pomodoroModeControl.setLabel("倒计时", forSegment: 0)
        pomodoroModeControl.setLabel("正计时", forSegment: 1)
        pomodoroModeControl.setWidth(142, forSegment: 0)
        pomodoroModeControl.setWidth(142, forSegment: 1)
        pomodoroModeControl.trackingMode = .selectOne
        pomodoroModeControl.selectedSegment = 0
        pomodoroModeControl.segmentStyle = .rounded
        pomodoroModeControl.font = .systemFont(ofSize: 12, weight: .semibold)
        pomodoroCheck.bezelStyle = .rounded
        pomodoroCheck.font = .systemFont(ofSize: 12, weight: .bold)
        pomodoroCheck.contentTintColor = NSColor(hex: 0x4A7DB5)
        [glassView, rimView, moodLabel, todoButton, stopButton, quitButton, settingsButton, todoScrollView, newTodoScrollView, addTodoButton, clearTodoButton, focusMinutesField, restMinutesField, pomodoroModeControl, pomodoroTodoPopup, pomodoroCountdownLabel, pomodoroRecordLabel, pomodoroMonthLabel, pomodoroCheck].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        todoStackView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            glassView.topAnchor.constraint(equalTo: topAnchor),
            glassView.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: trailingAnchor),
            glassView.bottomAnchor.constraint(equalTo: bottomAnchor),
            rimView.topAnchor.constraint(equalTo: topAnchor),
            rimView.leadingAnchor.constraint(equalTo: leadingAnchor),
            rimView.trailingAnchor.constraint(equalTo: trailingAnchor),
            rimView.bottomAnchor.constraint(equalTo: bottomAnchor),

            moodLabel.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            moodLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            moodLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            moodLabel.heightAnchor.constraint(equalToConstant: 34),

            todoButton.topAnchor.constraint(equalTo: moodLabel.bottomAnchor, constant: 8),
            todoButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            todoButton.widthAnchor.constraint(equalToConstant: 78),
            todoButton.heightAnchor.constraint(equalToConstant: 28),
            stopButton.centerYAnchor.constraint(equalTo: todoButton.centerYAnchor),
            stopButton.leadingAnchor.constraint(equalTo: todoButton.trailingAnchor, constant: 6),
            stopButton.widthAnchor.constraint(equalToConstant: 70),
            stopButton.heightAnchor.constraint(equalToConstant: 28),
            settingsButton.centerYAnchor.constraint(equalTo: todoButton.centerYAnchor),
            settingsButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            settingsButton.widthAnchor.constraint(equalToConstant: 32),
            settingsButton.heightAnchor.constraint(equalToConstant: 28),

            todoScrollView.topAnchor.constraint(equalTo: todoButton.bottomAnchor, constant: 8),
            todoScrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            todoScrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            // Room for about three todo cards before scrolling.
            todoScrollView.heightAnchor.constraint(equalToConstant: 104),

            newTodoScrollView.topAnchor.constraint(equalTo: todoScrollView.bottomAnchor, constant: 6),
            newTodoScrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            newTodoScrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            newTodoScrollView.heightAnchor.constraint(equalToConstant: 48),

            addTodoButton.topAnchor.constraint(equalTo: newTodoScrollView.bottomAnchor, constant: 6),
            addTodoButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            addTodoButton.widthAnchor.constraint(equalToConstant: 132),
            clearTodoButton.leadingAnchor.constraint(equalTo: addTodoButton.trailingAnchor, constant: 8),
            clearTodoButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            clearTodoButton.centerYAnchor.constraint(equalTo: addTodoButton.centerYAnchor),
            clearTodoButton.widthAnchor.constraint(equalToConstant: 92),
            addTodoButton.heightAnchor.constraint(equalToConstant: 32),
            clearTodoButton.heightAnchor.constraint(equalToConstant: 32),

            pomodoroCheck.topAnchor.constraint(equalTo: addTodoButton.bottomAnchor, constant: 8),
            pomodoroCheck.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            pomodoroCheck.widthAnchor.constraint(equalToConstant: 68),
            focusMinutesField.centerYAnchor.constraint(equalTo: pomodoroCheck.centerYAnchor),
            focusMinutesField.leadingAnchor.constraint(equalTo: pomodoroCheck.trailingAnchor, constant: 6),
            focusMinutesField.widthAnchor.constraint(equalToConstant: 38),
            restMinutesField.centerYAnchor.constraint(equalTo: pomodoroCheck.centerYAnchor),
            restMinutesField.leadingAnchor.constraint(equalTo: focusMinutesField.trailingAnchor, constant: 4),
            restMinutesField.widthAnchor.constraint(equalToConstant: 38),
            pomodoroModeControl.topAnchor.constraint(equalTo: pomodoroCheck.bottomAnchor, constant: 6),
            pomodoroModeControl.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            pomodoroModeControl.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            pomodoroModeControl.heightAnchor.constraint(equalToConstant: 26),
            pomodoroTodoPopup.topAnchor.constraint(equalTo: pomodoroModeControl.bottomAnchor, constant: 6),
            pomodoroTodoPopup.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            pomodoroTodoPopup.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            pomodoroTodoPopup.heightAnchor.constraint(equalToConstant: 26),
            pomodoroCountdownLabel.topAnchor.constraint(equalTo: pomodoroTodoPopup.bottomAnchor, constant: 6),
            pomodoroCountdownLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            pomodoroCountdownLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            pomodoroRecordLabel.topAnchor.constraint(equalTo: pomodoroCountdownLabel.bottomAnchor, constant: 4),
            pomodoroRecordLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            pomodoroRecordLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            pomodoroMonthLabel.topAnchor.constraint(equalTo: pomodoroRecordLabel.bottomAnchor, constant: 3),
            pomodoroMonthLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            pomodoroMonthLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            quitButton.topAnchor.constraint(equalTo: pomodoroMonthLabel.bottomAnchor, constant: 8),
            quitButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            quitButton.widthAnchor.constraint(equalToConstant: 86),
            quitButton.heightAnchor.constraint(equalToConstant: 28)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class PetWindowController: NSWindowController {
    private let normalPetSize = NSSize(width: 110, height: 110)
    private let lanePetSize = NSSize(width: 64, height: 64)
    private let hamsterView = SpritePetView(frame: NSRect(x: 155, y: 34, width: 110, height: 110))
    private let tagLabel = CenteredLabel(labelWithString: "巡逻中")
    private let bubbleView = BubbleView(frame: NSRect(x: 0, y: 0, width: 320, height: 110))
    private let eventStore = EKEventStore()
    private var didRequestCalendarAccessThisLaunch = false
    private var didRequestRemindersAccessThisLaunch = false
    private var didShowReminderAccessUnavailableThisLaunch = false
    private var bubblePanel: PetPanel?

    private var mood: PetMood = .idle
    private var facing: CGFloat = -1
    private var verticalDirection: CGFloat = 1
    private var dragStart: NSPoint?
    private var windowStart: NSPoint?
    private var bubbleDragStart: NSPoint?
    private var bubbleWindowStart: NSPoint?
    private var animationTimer: Timer?
    private var moveTimer: Timer?
    private var moodTimer: Timer?
    private var moodHoldTimer: Timer?
    private var calendarTimer: Timer?
    private var pomodoroTimer: Timer?
    private var statusTagHideTimer: Timer?
    private var mouseDownMonitor: Any?
    private var frameIndex = 0
    private var lastCalendarEventKey = ""
    private var settingsVisible = false
    private var todosVisible = true
    private var paused = true
    private var walkMode: WalkMode = .still
    private var selectedActionIndex = 0
    private var pomodoroEnabled = false
    private var pomodoroIsBreak = false
    private var pomodoroTimerMode: PomodoroTimerMode = .countdown
    private var pomodoroEndDate: Date?
    private var pomodoroCountUpStartDate: Date?
    private var pausedBeforePomodoro = false
    private var activeFocusMinutes = 25
    private var pomodoroFocusMinutes = 25
    private var pomodoroRestMinutes = 5
    private let countUpLapSeconds = 25 * 60
    private var pomodoroLinkedTodoID: String?
    private var pomodoroFocusSessions = 0
    private var pomodoroFocusTotalMinutes = 0
    private var pomodoroMonthFocusSessions = 0
    private var pomodoroMonthFocusTotalMinutes = 0
    private var pomodoroMonthRewardLevel = 0
    private var celebrationStartedAt: Date?
    private var celebrationOrigin: NSPoint?
    private var celebrationBubbleFrame: NSRect?
    private var celebrationTagFrame: NSRect?
    private var celebrationBounds: NSRect?
    private var celebrationStyle: CelebrationStyle = .small
    private var completionStreak = 0
    private var progressLaneActive = false
    private var frozenTagPanel: PetPanel?
    private var frozenTagLabel: CenteredLabel?
    private var confettiPanel: PetPanel?
    private var confettiTimer: Timer?
    private var messagePriority: MessagePriority = .ambient
    private var messageHoldUntil: Date?
    private var messageResetTimer: Timer?
    private var progressFlashResetTimer: Timer?
    private var noseTapTimes: [Date] = []
    private var lastAmbientTagRefreshAt: Date = .distantPast
    private var ambientTagText = "喜欢你"
    private let defaultBubbleMessage = "今天干什么大事汪"
    private let petLines = PetLineLibrary.load()
    private var todos: [TodoItem] = []
    private var completedTodosExpanded = false
    private var todayEvents: [(time: String, title: String)] = []
    private var lastCalendarSyncDay = ""
    private let pomodoroRewardMilestones: [PomodoroReward] = [
        PomodoroReward(
            minutes: 120,
            name: "启程爪印",
            emoji: "🐾",
            line: "阿念给你盖下本月第一枚爪印，行动的小路已经亮起来。",
            stickerEmojis: ["🐾", "✨", "🫧"]
        ),
        PomodoroReward(
            minutes: 300,
            name: "星火护符",
            emoji: "✨",
            line: "星火护符已点亮，阿念替你守住这股专注的小火苗。",
            stickerEmojis: ["✨", "🌟", "🐾"]
        ),
        PomodoroReward(
            minutes: 600,
            name: "定心铃铛",
            emoji: "🔔",
            line: "定心铃铛响一下，阿念提醒你：心稳了，事情就会往前走。",
            stickerEmojis: ["🔔", "🌙", "✨", "🐾"]
        ),
        PomodoroReward(
            minutes: 1200,
            name: "阿念小窝",
            emoji: "🏠",
            line: "阿念小窝升级啦，本月的稳定努力已经有了自己的小房子。",
            stickerEmojis: ["🏠", "🐾", "🍵", "✨"]
        ),
        PomodoroReward(
            minutes: 2400,
            name: "阿念月冠",
            emoji: "👑",
            line: "阿念月冠戴上啦，这个月你真的把专注炼成了气场。",
            stickerEmojis: ["👑", "🌙", "💫", "🐾"]
        )
    ]
    // Short blue status bubbles above the puppy: intimate and interactive.
    // Wangmen motto lines belong in the opened todo text box and celebration moments.
    private let casualTags = [
        "喜欢你",
        "看着你",
        "摇尾巴",
        "尾巴摇摇",
        "阿念在呢",
        "陪你一会儿",
        "摸摸头吗",
        "阿念贴贴",
        "你忙你的",
        "偷偷看你",
        "阿念路过",
        "在旁边呢",
        "凑近一点",
        "等你一下",
        "乖乖看着",
        "想你一下"
    ]
    private let floatingEmojis = ["🐾", "💙", "🫧", "✨", "🔹", "🌤️"]
    private var isPetHovered = false
    private var lastHeadHoverEmojiAt: Date = .distantPast

    convenience init() {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let size = NSSize(width: 280, height: 500)
        let origin = NSPoint(x: screenFrame.maxX - size.width - 32, y: screenFrame.minY + 18)
        let window = PetPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        // The puppy occupies only a small area inside this tall transparent
        // effects window. The transparent area may extend past a display edge;
        // clampWindowFrameByPetBounds still keeps the puppy itself on-screen.
        window.allowsPetFrameOutsideScreen = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.hidesOnDeactivate = false
        window.acceptsMouseMovedEvents = true
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = PetContentView(frame: NSRect(origin: .zero, size: size))
        self.init(window: window)
        setupWindow()
    }

    deinit {
        if let mouseDownMonitor {
            NSEvent.removeMonitor(mouseDownMonitor)
        }
        animationTimer?.invalidate()
        moveTimer?.invalidate()
        moodTimer?.invalidate()
        moodHoldTimer?.invalidate()
        calendarTimer?.invalidate()
        pomodoroTimer?.invalidate()
        statusTagHideTimer?.invalidate()
        confettiTimer?.invalidate()
        messageResetTimer?.invalidate()
        progressFlashResetTimer?.invalidate()
    }

    private func setupWindow() {
        guard let contentView = window?.contentView else { return }
        if let petContentView = contentView as? PetContentView {
            petContentView.onBlankClick = { [weak self] in
                self?.closeBubbleFromBlankClick()
            }
        }
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.clear.cgColor

        tagLabel.wantsLayer = true
        tagLabel.layer?.backgroundColor = NSColor(hex: 0x355F89, alpha: 0.86).cgColor
        tagLabel.layer?.borderWidth = 0.5
        tagLabel.layer?.borderColor = NSColor(hex: 0xFFFFFF, alpha: 0.18).cgColor
        tagLabel.layer?.cornerRadius = 10
        tagLabel.layer?.shadowOpacity = 0.18
        tagLabel.layer?.shadowRadius = 10
        tagLabel.layer?.shadowOffset = CGSize(width: 0, height: -3)
        tagLabel.alignment = .center
        tagLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        tagLabel.textColor = NSColor(hex: 0xFFFFFF, alpha: 0.96)
        tagLabel.isBezeled = false
        tagLabel.drawsBackground = false
        tagLabel.frame = NSRect(x: 200, y: 150, width: 80, height: 26)
        tagLabel.isHidden = true
        hamsterView.frame = NSRect(x: 85, y: 34, width: normalPetSize.width, height: normalPetSize.height)
        hamsterView.wantsLayer = true
        contentView.addSubview(hamsterView)
        contentView.addSubview(tagLabel)
        setupBubblePanel()

        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(toggleBubble))
        hamsterView.addGestureRecognizer(clickGesture)
        let panGesture = NSPanGestureRecognizer(target: self, action: #selector(dragPet(_:)))
        hamsterView.addGestureRecognizer(panGesture)
        hamsterView.onHoverBegan = { [weak self] in
            self?.handlePetHoverBegan()
        }
        hamsterView.onHoverEnded = { [weak self] in
            self?.handlePetHoverEnded()
        }
        hamsterView.onHeadHover = { [weak self] in
            self?.handlePetHeadHover()
        }
        hamsterView.onNoseClick = { [weak self] in
            self?.handleNoseClick()
        }
        hamsterView.onRightClick = { [weak self] event in
            self?.showPetContextMenu(event)
        }

        bubbleView.settingsButton.target = self
        bubbleView.settingsButton.action = #selector(toggleSettings)
        bubbleView.todoButton.target = self
        bubbleView.todoButton.action = #selector(actionModeChanged)
        bubbleView.stopButton.target = self
        bubbleView.stopButton.action = #selector(syncCalendarNow)
        bubbleView.quitButton.target = self
        bubbleView.quitButton.action = #selector(closeBubbleFromBlankClick)
        bubbleView.addTodoButton.target = self
        bubbleView.addTodoButton.action = #selector(addTodo)
        bubbleView.clearTodoButton.target = self
        bubbleView.clearTodoButton.action = #selector(clearCompletedTodos)
        bubbleView.focusMinutesField.target = self
        bubbleView.focusMinutesField.action = #selector(settingsChanged)
        bubbleView.restMinutesField.target = self
        bubbleView.restMinutesField.action = #selector(settingsChanged)
        bubbleView.pomodoroModeControl.target = self
        bubbleView.pomodoroModeControl.action = #selector(pomodoroModeChanged)
        bubbleView.pomodoroTodoPopup.target = self
        bubbleView.pomodoroTodoPopup.action = #selector(pomodoroTodoSelectionChanged)
        bubbleView.pomodoroCheck.target = self
        bubbleView.pomodoroCheck.action = #selector(togglePomodoroPrimary)
        bubbleView.newTodoTextView.onSubmit = { [weak self] in
            self?.addTodo()
        }

        loadSettings()
        setSettingsVisible(false)
        setTodosVisible(true)
        renderTodos()
        setMood(.idle)
        startTimers()
        requestNotifications()
        installBlankClickMonitor()
        showFirstRunOnboardingIfNeeded()
    }

    private func setupBubblePanel() {
        let panel = PetPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 110),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.appearance = NSAppearance(named: .aqua)
        panel.contentView = bubbleView
        let bubblePanGesture = NSPanGestureRecognizer(target: self, action: #selector(dragBubble(_:)))
        // Keep the liquid text box draggable, but do not attach the pan gesture to the
        // whole bubble. A full-panel pan gesture can swallow clicks from controls like
        // “发送到待办” and “清空待办”. Drag from the message/title area instead.
        bubbleView.moodLabel.addGestureRecognizer(bubblePanGesture)
        bubblePanel = panel
    }

    private func installBlankClickMonitor() {
        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            DispatchQueue.main.async {
                self?.handleGlobalMouseDown(event)
            }
        }
    }

    private func handleGlobalMouseDown(_ event: NSEvent) {
        guard let bubblePanel, bubblePanel.isVisible else { return }
        let point = NSEvent.mouseLocation
        if bubblePanel.frame.contains(point) { return }
        if let window, window.frame.contains(point) { return }
        closeBubbleFromBlankClick()
    }

    @objc private func closeBubbleFromBlankClick() {
        guard bubblePanel?.isVisible == true else { return }
        bubblePanel?.orderOut(nil)
        window?.makeFirstResponder(nil)
        setMood(baseMoodForCurrentState())
    }

    private func startTimers() {
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.16, repeats: true) { [weak self] _ in
            guard let self else { return }
            // Keep a monotonic action clock. Finite actions hold their last
            // frame; the focus run wraps only while the Pomodoro is active.
            frameIndex += 1
            hamsterView.frameIndex = frameIndex
            if frameIndex % 2 == 0 {
                maybeSpawnFloatingEmoji()
            }
        }
        moveTimer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { [weak self] _ in
            self?.moveIfNeeded()
        }
        moodTimer = Timer.scheduledTimer(withTimeInterval: 12, repeats: true) { [weak self] _ in
            self?.chooseMood()
        }
        let canResumePomodoro = pomodoroTimerMode == .countUp
            ? pomodoroCountUpStartDate != nil
            : pomodoroEndDate != nil
        if pomodoroEnabled, canResumePomodoro {
            paused = true
            updateActionModePopup()
            setMood(pomodoroIsBreak ? .sleepy : .idle)
            updatePomodoroCountdown()
            schedulePomodoroTickTimer()
            checkPomodoro()
        } else {
            resetPomodoroTimer()
        }
        resetCalendarTimer()
        updatePetProgress()
    }

    private func maybeSpawnFloatingEmoji() {
        guard !paused, window?.isVisible == true else { return }

        // A tiny occasional sparkle from the puppy's head.
        // Higher chance while celebrating, subtle chance while simply walking.
        let chance: Int
        switch mood {
        case .celebrating:
            chance = 38
        case .curious, .reminding:
            chance = 16
        case .walking, .idle:
            chance = 8
        case .sleepy:
            chance = 3
        }
        guard Int.random(in: 0..<100) < chance else { return }
        spawnFloatingEmoji()
    }

    private func spawnFloatingEmoji() {
        guard let contentView = window?.contentView else { return }

        let emoji = floatingEmojis.randomElement() ?? "💗"
        let labelSize = NSSize(width: 40, height: 40)
        let startX = hamsterView.frame.midX - labelSize.width / 2 + CGFloat.random(in: -16...16)
        let startY = hamsterView.frame.maxY - 16 + CGFloat.random(in: -6...10)
        let label = CenteredLabel(labelWithString: emoji)
        label.frame = NSRect(origin: NSPoint(x: startX, y: startY), size: labelSize)
        label.font = .systemFont(ofSize: CGFloat.random(in: 22...28), weight: .semibold)
        label.alignment = .center
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        label.isSelectable = false
        label.alphaValue = 0
        label.wantsLayer = true
        label.layer?.shadowColor = NSColor.black.withAlphaComponent(0.16).cgColor
        label.layer?.shadowOpacity = 1
        label.layer?.shadowRadius = 4
        label.layer?.shadowOffset = CGSize(width: 0, height: -1)
        contentView.addSubview(label, positioned: .above, relativeTo: hamsterView)

        let driftX = CGFloat.random(in: -18...18)
        let driftY = CGFloat.random(in: 34...54)
        let duration = TimeInterval.random(in: 1.15...1.75)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            label.animator().alphaValue = 1
            label.animator().setFrameOrigin(NSPoint(x: startX + driftX * 0.22, y: startY + 8))
        } completionHandler: {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                label.animator().alphaValue = 0
                label.animator().setFrameOrigin(NSPoint(x: startX + driftX, y: startY + driftY))
            } completionHandler: {
                label.removeFromSuperview()
            }
        }
    }

    private func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func loadSettings() {
        let defaults = UserDefaults.standard
        pomodoroEnabled = defaults.bool(forKey: PetSettings.pomodoroEnabled)
        bubbleView.pomodoroCheck.state = pomodoroEnabled ? .on : .off
        pomodoroTimerMode = PomodoroTimerMode(rawValue: defaults.integer(forKey: PetSettings.pomodoroTimerMode)) ?? .countdown
        bubbleView.pomodoroModeControl.selectedSegment = pomodoroTimerMode.rawValue
        pomodoroIsBreak = defaults.bool(forKey: PetSettings.pomodoroIsBreak)
        pomodoroFocusMinutes = defaults.integer(forKey: PetSettings.pomodoroFocusMinutes)
        if pomodoroFocusMinutes <= 0 { pomodoroFocusMinutes = 25 }
        pomodoroRestMinutes = defaults.integer(forKey: PetSettings.pomodoroRestMinutes)
        if pomodoroRestMinutes <= 0 { pomodoroRestMinutes = 5 }
        let savedLinkedTodoID = defaults.string(forKey: PetSettings.pomodoroLinkedTodoID)
        pomodoroLinkedTodoID = savedLinkedTodoID?.isEmpty == false ? savedLinkedTodoID : nil
        activeFocusMinutes = defaults.integer(forKey: PetSettings.pomodoroActiveFocusMinutes)
        if activeFocusMinutes <= 0 { activeFocusMinutes = pomodoroFocusMinutes }
        let storedEndDate = defaults.double(forKey: PetSettings.pomodoroEndDate)
        let storedCountUpStartDate = defaults.double(forKey: PetSettings.pomodoroCountUpStartDate)
        if pomodoroEnabled, pomodoroTimerMode == .countUp {
            pomodoroIsBreak = false
            pomodoroEndDate = nil
            pomodoroCountUpStartDate = storedCountUpStartDate > 0
                ? Date(timeIntervalSince1970: storedCountUpStartDate)
                : Date()
        } else if pomodoroEnabled, storedEndDate > 0 {
            pomodoroEndDate = Date(timeIntervalSince1970: storedEndDate)
            pomodoroCountUpStartDate = nil
        } else {
            pomodoroEndDate = nil
            pomodoroCountUpStartDate = nil
        }
        bubbleView.focusMinutesField.stringValue = "\(pomodoroFocusMinutes)"
        bubbleView.restMinutesField.stringValue = "\(pomodoroRestMinutes)"
        updatePomodoroModeControls()
        loadPomodoroFocusRecord()
        updatePomodoroCountdown()
        walkMode = .still
        defaults.set(walkMode.rawValue, forKey: PetSettings.walkMode)
        updateActionModePopup()
        if let data = defaults.data(forKey: PetSettings.todos),
           let savedTodos = try? JSONDecoder().decode([TodoItem].self, from: data) {
            todos = savedTodos
        } else {
            todos = [
                TodoItem(title: "赶紧干活啦", done: false, calendarKey: nil, id: UUID().uuidString),
                TodoItem(title: "喝口水再继续", done: false, calendarKey: nil, id: UUID().uuidString)
            ]
        }
        if ensureTodoIDs() {
            saveTodos()
        }
        cleanupPomodoroLinkedTodoIfNeeded()
        refreshPomodoroTodoPopup()
        syncPomodoroSettingsFromUI()
        let today = dayKey()
        if defaults.string(forKey: PetSettings.completionStreakDay) == today {
            completionStreak = defaults.integer(forKey: PetSettings.completionStreak)
        } else {
            completionStreak = 0
            defaults.set(today, forKey: PetSettings.completionStreakDay)
            defaults.set(0, forKey: PetSettings.completionStreak)
        }
    }

    @objc private func settingsChanged() {
        let defaults = UserDefaults.standard
        syncPomodoroSettingsFromUI()
        defaults.set(pomodoroEnabled, forKey: PetSettings.pomodoroEnabled)
        defaults.set(pomodoroTimerMode.rawValue, forKey: PetSettings.pomodoroTimerMode)
        defaults.set(pomodoroFocusMinutes, forKey: PetSettings.pomodoroFocusMinutes)
        defaults.set(pomodoroRestMinutes, forKey: PetSettings.pomodoroRestMinutes)
        if pomodoroEnabled {
            persistPomodoroState()
            updatePomodoroCountdown()
            setBubbleMessage("新的番茄时间已保存，下一轮生效。", priority: .pomodoro, hold: 5)
        }
    }

    @objc private func pomodoroModeChanged() {
        guard !pomodoroEnabled else {
            bubbleView.pomodoroModeControl.selectedSegment = pomodoroTimerMode.rawValue
            return
        }
        pomodoroTimerMode = PomodoroTimerMode(rawValue: bubbleView.pomodoroModeControl.selectedSegment) ?? .countdown
        UserDefaults.standard.set(pomodoroTimerMode.rawValue, forKey: PetSettings.pomodoroTimerMode)
        updatePomodoroModeControls()
        updatePomodoroCountdown()
        let message = pomodoroTimerMode == .countUp
            ? "阿念切到正计时：每25分钟跑完一圈，点结束才会停。"
            : "阿念切到倒计时：按专注与休息时长完成一组。"
        setBubbleMessage(message, priority: .pomodoro, hold: 7)
    }

    private func updatePomodoroModeControls() {
        let usesCountdown = pomodoroTimerMode == .countdown
        bubbleView.pomodoroModeControl.selectedSegment = pomodoroTimerMode.rawValue
        bubbleView.pomodoroModeControl.isEnabled = !pomodoroEnabled
        bubbleView.focusMinutesField.isEnabled = usesCountdown && !pomodoroEnabled
        bubbleView.restMinutesField.isEnabled = usesCountdown && !pomodoroEnabled
        bubbleView.focusMinutesField.alphaValue = usesCountdown ? 1 : 0.38
        bubbleView.restMinutesField.alphaValue = usesCountdown ? 1 : 0.38
    }

    @objc private func actionModeChanged() {
        let defaults = UserDefaults.standard
        if progressLaneActive {
            setProgressLaneActive(false)
        }
        selectedActionIndex = bubbleView.todoButton.indexOfSelectedItem
        updateWindowLevelForMode()
        switch selectedActionIndex {
        case 0:
            paused = true
            walkMode = .still
            defaults.set(walkMode.rawValue, forKey: PetSettings.walkMode)
            setMood(.idle)
            setBubbleMessage(petLine("daily", fallback: "阿念坐镇，乖乖待机。"), priority: .todo, hold: 6)
        case 1:
            paused = false
            walkMode = .fourWay
            defaults.set(walkMode.rawValue, forKey: PetSettings.walkMode)
            setMood(.walking)
            setBubbleMessage(petLine("walk", fallback: "阿念开始四处走走。"), priority: .todo, hold: 6)
        case 2:
            paused = true
            walkMode = .still
            defaults.set(walkMode.rawValue, forKey: PetSettings.walkMode)
            performInPlaceJump()
            setBubbleMessage(petLine("touch", fallback: "阿念原地跳两下。"), priority: .todo, hold: 4)
        default:
            paused = true
            walkMode = .still
            defaults.set(walkMode.rawValue, forKey: PetSettings.walkMode)
            setMood(.sleepy)
            setBubbleMessage(petLine("tired", fallback: "阿念累趴了，摸摸它还会回应你。"), priority: .todo, hold: 6)
        }
        updateActionModePopup()
    }

    private func updateActionModePopup() {
        let index = min(max(selectedActionIndex, 0), bubbleView.todoButton.numberOfItems - 1)
        bubbleView.todoButton.selectItem(at: index)
    }

    private func performInPlaceJump() {
        setMood(.celebrating, hold: 1.35)
        guard let layer = hamsterView.layer else { return }
        let jump = CAKeyframeAnimation(keyPath: "transform.translation.y")
        jump.values = [0, 14, 0, 10, 0]
        jump.keyTimes = [0, 0.2, 0.45, 0.68, 1]
        jump.duration = 1.25
        jump.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeIn),
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeIn)
        ]
        layer.add(jump, forKey: "anian.inPlaceJump")
        spawnFloatingEmoji()
    }

    private func updateWindowLevelForMode() {
        window?.alphaValue = 1
        window?.level = .floating
        bubblePanel?.level = .statusBar
        window?.orderFront(nil)
    }

    @objc private func togglePomodoroPrimary() {
        if pomodoroEnabled {
            stopPomodoro()
        } else {
            startNewPomodoro()
        }
    }

    private func startNewPomodoro() {
        syncPomodoroSettingsFromUI()
        syncPomodoroLinkedTodoFromPopup()
        pausedBeforePomodoro = paused
        pomodoroEnabled = true
        pomodoroIsBreak = false
        activeFocusMinutes = pomodoroTimerMode == .countUp ? 25 : pomodoroFocusMinutes
        pomodoroCountUpStartDate = pomodoroTimerMode == .countUp ? Date() : nil
        bubbleView.pomodoroCheck.state = .on
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: PetSettings.pomodoroEnabled)
        defaults.set(pomodoroFocusMinutes, forKey: PetSettings.pomodoroFocusMinutes)
        defaults.set(pomodoroRestMinutes, forKey: PetSettings.pomodoroRestMinutes)
        defaults.set(pomodoroTimerMode.rawValue, forKey: PetSettings.pomodoroTimerMode)
        defaults.set(pomodoroLinkedTodoID ?? "", forKey: PetSettings.pomodoroLinkedTodoID)
        refreshPomodoroTodoPopup()
        resetPomodoroTimer()
    }

    private func stopPomodoro() {
        let wasCountUp = pomodoroTimerMode == .countUp
        let elapsedFocusSeconds = pomodoroIsBreak ? 0 : currentFocusElapsedSeconds()
        var unlockedRewardLevel: Int?
        pomodoroTimer?.invalidate()
        pomodoroTimer = nil
        pomodoroEnabled = false
        pomodoroIsBreak = false
        pomodoroEndDate = nil
        pomodoroCountUpStartDate = nil
        if wasCountUp {
            unlockedRewardLevel = recordCountUpFocusCompletion(seconds: elapsedFocusSeconds)
        } else {
            recordLinkedTodoPomodoro(seconds: elapsedFocusSeconds)
        }
        if progressLaneActive {
            setProgressLaneActive(false)
        }
        paused = pausedBeforePomodoro
        bubbleView.pomodoroCheck.state = .off
        clearPomodoroState()
        syncPomodoroSettingsFromUI()
        updatePomodoroCountdown()
        updateActionModePopup()
        refreshPomodoroTodoPopup()
        updatePomodoroModeControls()
        setMood(paused ? .idle : .walking)
        if let unlockedRewardLevel {
            triggerPomodoroMonthlyReward(level: unlockedRewardLevel)
        } else if wasCountUp {
            setBubbleMessage("正计时已结束，阿念记下 \(formatTodoDuration(elapsedFocusSeconds))。", priority: .pomodoro, hold: 8)
        } else {
            setBubbleMessage("番茄钟已停止，阿念先把番茄收起来。", priority: .pomodoro, hold: 5)
        }
    }

    @objc private func toggleSettings() {
        settingsVisible.toggle()
        setSettingsVisible(settingsVisible)
        if settingsVisible {
            setBubbleMessage("阿念打开设置：番茄钟、退出都在这里。", priority: .todo, hold: 6)
        }
    }

    @objc private func showPomodoroOptions() {
        settingsVisible = true
        setSettingsVisible(true)
        setBubbleMessage("阿念打开番茄钟：专注一轮，盖一枚爪印。", priority: .todo, hold: 7)
    }

    @objc private func syncCalendarNow() {
        setBubbleMessage("阿念正在召集今日日程和提醒事项……", priority: .todo, hold: 5)
        let before = todos.count
        var calendarGranted = false
        var remindersGranted = false
        var calendarFinished = false
        var remindersFinished = false

        func finishIfReady() {
            guard calendarFinished, remindersFinished else { return }
            todosVisible = true
            setTodosVisible(true)
            renderTodos()
            updateBubbleSize()
            bubblePanel?.orderFront(nil)

            let added = max(0, todos.count - before)
            let scheduledCount = todos.filter { $0.calendarKey != nil }.count
            if added > 0 {
                setBubbleMessage("阿念已把 \(added) 个日程/提醒事项收入阿念册子。", priority: .todo, hold: 8)
            } else if scheduledCount > 0 {
                setBubbleMessage("阿念看过了，今日事项已经在阿念册子里。", priority: .todo, hold: 8)
            } else if !calendarGranted && !remindersGranted {
                setBubbleMessage("阿念进不去日历和提醒事项，请先开权限。", priority: .todo, hold: 9)
            } else if !remindersGranted {
                setBubbleMessage("阿念未发现日程；提醒事项权限还没开。", priority: .todo, hold: 9)
            } else if !calendarGranted {
                setBubbleMessage("阿念未发现提醒；日历权限还没开。", priority: .todo, hold: 9)
            } else {
                setBubbleMessage("阿念巡查完毕，今天暂无可同步事项。", priority: .todo, hold: 8)
            }
        }

        requestCalendarAccess { [weak self] granted in
            guard let self else { return }
            calendarGranted = granted
            if granted {
                self.refreshTodayEvents()
            }
            calendarFinished = true
            finishIfReady()
        }

        requestRemindersAccess { [weak self] granted in
            guard let self else { return }
            remindersGranted = granted
            guard granted else {
                remindersFinished = true
                finishIfReady()
                return
            }
            self.refreshTodayReminders {
                remindersFinished = true
                finishIfReady()
            }
        }
    }

    @objc private func toggleTodos() {
        todosVisible.toggle()
        setTodosVisible(todosVisible)
        if todosVisible {
            let category = todos.contains { !$0.done } ? "procrastinate" : "daily"
            setBubbleMessage(petLine(category, fallback: "先挑一件最小的开始吧，汪。"), priority: .todo, hold: 8)
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
            window?.makeFirstResponder(bubbleView.newTodoTextView)
        } else if messagePriority == .todo {
            setBubbleMessage(petLine("daily", fallback: "阿念在旁边守着。"), priority: .ambient, hold: 4)
        }
    }

    private func setSettingsVisible(_ visible: Bool) {
        if visible {
            updatePomodoroFocusRecordLabel()
        }
        bubbleView.focusMinutesField.isHidden = !visible
        bubbleView.restMinutesField.isHidden = !visible
        bubbleView.pomodoroModeControl.isHidden = !visible
        bubbleView.pomodoroTodoPopup.isHidden = !visible
        bubbleView.pomodoroCountdownLabel.isHidden = !visible
        bubbleView.pomodoroRecordLabel.isHidden = !visible
        bubbleView.pomodoroMonthLabel.isHidden = !visible
        bubbleView.pomodoroCheck.isHidden = !visible
        bubbleView.quitButton.isHidden = !visible
        updatePomodoroModeControls()
        updateBubbleSize()
    }

    private func setTodosVisible(_ visible: Bool) {
        bubbleView.todoScrollView.isHidden = !visible
        bubbleView.newTodoScrollView.isHidden = !visible
        bubbleView.addTodoButton.isHidden = !visible
        bubbleView.clearTodoButton.isHidden = !visible
        updateBubbleSize()
    }

    private func updateBubbleSize() {
        guard let bubblePanel else { return }
        let oldFrame = bubblePanel.frame
        let newSize: NSSize
        if todosVisible && settingsVisible {
            // Fit the last settings control with only a small rounded-corner inset.
            newSize = NSSize(width: 320, height: 490)
        } else if todosVisible {
            // The todo list itself is scrollable; extra panel height only creates dead space.
            newSize = NSSize(width: 320, height: 300)
        } else if settingsVisible {
            newSize = NSSize(width: 320, height: 490)
        } else {
            // Compact state: when the todo section is closed, the whole liquid box
            // collapses back to a small control bubble instead of keeping the tall panel.
            newSize = NSSize(width: 300, height: 110)
        }

        var frame = oldFrame
        // Preserve the top edge while expanding/collapsing, so the bubble feels like it
        // folds itself up instead of sliding around the desktop.
        frame.origin.y = oldFrame.maxY - newSize.height
        frame.size = newSize
        frame = clampBubbleFrameToVisibleScreen(frame)

        bubbleView.frame = NSRect(origin: .zero, size: newSize)
        bubblePanel.setContentSize(newSize)

        if mood == .celebrating {
            celebrationBubbleFrame = frame
            bubblePanel.setFrame(frame, display: true, animate: true)
            restoreCelebrationTextOverlaysIfNeeded()
            return
        }

        // Keep the bubble where it was opened or dragged. Resizing should not make it chase the pet.
        bubblePanel.setFrame(frame, display: true, animate: true)
    }

    private func clampBubbleFrameToVisibleScreen(_ frame: NSRect) -> NSRect {
        guard let screenFrame = bubblePanel?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame else { return frame }
        var clamped = frame
        clamped.origin.x = min(max(clamped.origin.x, screenFrame.minX + 8), screenFrame.maxX - clamped.width - 8)
        clamped.origin.y = min(max(clamped.origin.y, screenFrame.minY + 8), screenFrame.maxY - clamped.height - 8)
        return clamped
    }

    @objc private func toggleBubble() {
        guard let bubblePanel else { return }
        if bubblePanel.isVisible {
            bubblePanel.orderOut(nil)
        } else {
            todosVisible = true
            setTodosVisible(true)
            positionBubblePanelSmartly()
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
            bubblePanel.orderFront(nil)
        }
        performTouchSpin()
    }

    private func positionBubblePanelSmartly() {
        if mood == .celebrating {
            restoreCelebrationTextOverlaysIfNeeded()
            return
        }
        guard let window, let bubblePanel, let screenFrame = NSScreen.main?.visibleFrame else { return }
        let size = bubblePanel.frame.size
        let petRect = NSRect(
            x: window.frame.minX + hamsterView.frame.minX,
            y: window.frame.minY + hamsterView.frame.minY,
            width: hamsterView.frame.width,
            height: hamsterView.frame.height
        )
        let gap: CGFloat = 12
        let centerX = petRect.midX - size.width / 2
        let centerY = petRect.midY - size.height / 2
        let candidates = [
            NSRect(x: petRect.minX - size.width - gap, y: centerY, width: size.width, height: size.height),
            NSRect(x: petRect.maxX + gap, y: centerY, width: size.width, height: size.height),
            NSRect(x: centerX, y: petRect.maxY + gap, width: size.width, height: size.height),
            NSRect(x: centerX, y: petRect.minY - size.height - gap, width: size.width, height: size.height),
            NSRect(x: petRect.minX - size.width - gap, y: petRect.maxY + gap, width: size.width, height: size.height),
            NSRect(x: petRect.maxX + gap, y: petRect.maxY + gap, width: size.width, height: size.height),
            NSRect(x: petRect.minX - size.width - gap, y: petRect.minY - size.height - gap, width: size.width, height: size.height),
            NSRect(x: petRect.maxX + gap, y: petRect.minY - size.height - gap, width: size.width, height: size.height)
        ].map { clamp($0, inside: screenFrame.insetBy(dx: 8, dy: 8)) }

        let occupied = visibleWindowRects(excluding: [window.windowNumber, bubblePanel.windowNumber])
        let best = candidates.max { lhs, rhs in
            bubbleScore(lhs, petRect: petRect, occupied: occupied, screenFrame: screenFrame) <
                bubbleScore(rhs, petRect: petRect, occupied: occupied, screenFrame: screenFrame)
        } ?? candidates[0]
        bubblePanel.setFrame(best, display: true)
    }

    private func bubbleScore(_ rect: NSRect, petRect: NSRect, occupied: [NSRect], screenFrame: NSRect) -> CGFloat {
        let overlap = occupied.reduce(CGFloat(0)) { partial, other in
            partial + rect.intersection(other).area
        }
        let petOverlap = rect.intersection(petRect.insetBy(dx: -10, dy: -10)).area
        let petDistance = hypot(rect.midX - petRect.midX, rect.midY - petRect.midY)
        let edgeComfort = min(
            rect.minX - screenFrame.minX,
            screenFrame.maxX - rect.maxX,
            rect.minY - screenFrame.minY,
            screenFrame.maxY - rect.maxY
        )
        return edgeComfort - overlap * 4 - petOverlap * 60 - petDistance * 0.08
    }

    private func clamp(_ rect: NSRect, inside bounds: NSRect) -> NSRect {
        var result = rect
        result.origin.x = min(max(result.origin.x, bounds.minX), bounds.maxX - result.width)
        result.origin.y = min(max(result.origin.y, bounds.minY), bounds.maxY - result.height)
        return result
    }

    private func visibleWindowRects(excluding excludedWindowNumbers: Set<Int>) -> [NSRect] {
        guard
            let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else {
            return []
        }
        let currentPID = NSRunningApplication.current.processIdentifier
        let fullHeight = NSScreen.screens.map(\.frame).reduce(CGFloat(0)) { max($0, $1.maxY) }
        return infoList.compactMap { info in
            guard
                let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                let alpha = cgFloat(info[kCGWindowAlpha as String]), alpha > 0.05,
                let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != currentPID,
                let number = info[kCGWindowNumber as String] as? Int, !excludedWindowNumbers.contains(number),
                let bounds = info[kCGWindowBounds as String] as? [String: Any],
                let x = cgFloat(bounds["X"]), let y = cgFloat(bounds["Y"]),
                let width = cgFloat(bounds["Width"]), let height = cgFloat(bounds["Height"]),
                width > 80, height > 80
            else {
                return nil
            }
            return NSRect(x: x, y: fullHeight - y - height, width: width, height: height)
        }
    }

    private func cgFloat(_ value: Any?) -> CGFloat? {
        if let number = value as? NSNumber {
            return CGFloat(truncating: number)
        }
        if let value = value as? CGFloat {
            return value
        }
        if let value = value as? Double {
            return CGFloat(value)
        }
        if let value = value as? Int {
            return CGFloat(value)
        }
        return nil
    }

    @objc private func addTodo() {
        let rawText = bubbleView.newTodoTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let titles = rawText
            .components(separatedBy: .newlines)
            .map { line in
                line.trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: #"^\s*(?:[-*•]|\d+[.、])\s+"#, with: "", options: .regularExpression)
            }
            .filter { !$0.isEmpty && $0 != "一行一个待办" }
        guard !titles.isEmpty else { return }
        todos.append(contentsOf: titles.map { TodoItem(title: $0, done: false, calendarKey: nil, id: UUID().uuidString) })
        bubbleView.newTodoTextView.string = ""
        saveTodos()
        renderTodos()
        setBubbleMessage("阿念已收录。现在选一枚阿念小爪印，开工啦。", priority: .todo, hold: 8)
    }

    @objc private func toggleTodo(_ sender: NSButton) {
        guard sender.tag >= 0 && sender.tag < todos.count else { return }
        let wasDone = todos[sender.tag].done
        let willBeDone = sender.state == .on
        if !wasDone && willBeDone && isTodoLinkedToActiveFocus(todos[sender.tag]) {
            let elapsedSeconds = currentFocusElapsedSeconds()
            if elapsedSeconds > 0 {
                todos[sender.tag].pomodoroSeconds = (todos[sender.tag].pomodoroSeconds ?? 0) + elapsedSeconds
            }
        }
        todos[sender.tag].done = willBeDone
        todos[sender.tag].completedAt = willBeDone ? Date() : nil
        if willBeDone {
            completedTodosExpanded = true
        }
        let updatedTodo = todos[sender.tag]
        saveTodos()
        renderTodos()
        if updatedTodo.done {
            handleTodoCompletion(wasDone: wasDone)
        } else {
            setBubbleMessage("阿念准许重来：重新开始也算行动。", priority: .todo, hold: 8)
        }
        if let id = todoID(updatedTodo) {
            syncReminderCompletion(forTodoID: id, completed: willBeDone)
        }
    }

    @objc private func strikeTodoFromMenu(_ sender: NSMenuItem) {
        let index = sender.tag
        guard index >= 0 && index < todos.count else { return }
        suppressCalendarTodosForToday([todos[index].calendarKey].compactMap { $0 })
        let removedTitle = todos[index].title
        todos.remove(at: index)
        saveTodos()
        renderTodos()
        setBubbleMessage("阿念已划掉：\(removedTitle)", priority: .todo, hold: 7)
    }

    @objc private func unstrikeTodoFromMenu(_ sender: NSMenuItem) {
        let index = sender.tag
        guard index >= 0 && index < todos.count else { return }
        todos[index].done = false
        todos[index].completedAt = nil
        let updatedTodo = todos[index]
        saveTodos()
        renderTodos()
        setBubbleMessage("阿念把这一爪先放回待办里。", priority: .todo, hold: 8)
        if let id = todoID(updatedTodo) {
            syncReminderCompletion(forTodoID: id, completed: false)
        }
    }

    @objc private func clearCompletedTodos() {
        let completed = todos.filter { $0.done }
        guard !completed.isEmpty else {
            setBubbleMessage("阿念看过了，还没有已完成的小爪印。", priority: .todo, hold: 8)
            return
        }
        suppressCalendarTodosForToday(completed.compactMap { $0.calendarKey })
        todos.removeAll { $0.done }
        completedTodosExpanded = false
        saveTodos()
        renderTodos()
        setBubbleMessage("阿念已清理完成项，阿念册子变清爽啦。", priority: .todo, hold: 8)
    }

    @objc private func toggleCompletedTodosExpanded() {
        completedTodosExpanded.toggle()
        renderTodos()
    }

    @objc private func togglePaused() {
        paused.toggle()
        updateActionModePopup()
        setMood(paused ? .idle : .walking)
        setBubbleMessage(paused ? "阿念坐镇，乖乖待机。" : "阿念出巡啦。", priority: .todo, hold: 6)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func showPetContextMenu(_ event: NSEvent) {
        let menu = NSMenu()
        let quitItem = NSMenuItem(title: "退出阿念", action: #selector(quitApp), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)
        NSMenu.popUpContextMenu(menu, with: event, for: hamsterView)
    }

    private func handleTodoCompletion(wasDone: Bool) {
        updatePetProgress(flash: true)
        guard !wasDone else {
            setBubbleMessage(petLine("praise", fallback: "好耶！你又完成一件大事。"), priority: .todo, hold: 8)
            celebrateCompletion(style: .small, triggerGlobalEffect: false)
            return
        }

        let today = dayKey()
        let defaults = UserDefaults.standard
        if defaults.string(forKey: PetSettings.completionStreakDay) != today {
            completionStreak = 0
            defaults.set(today, forKey: PetSettings.completionStreakDay)
        }
        completionStreak += 1
        defaults.set(completionStreak, forKey: PetSettings.completionStreak)

        let isFirstCompletionToday = defaults.string(forKey: PetSettings.firstCompletionDay) != today
        if isFirstCompletionToday {
            defaults.set(today, forKey: PetSettings.firstCompletionDay)
        }
        let allTodosDone = !todos.isEmpty && !todos.contains { !$0.done }

        if allTodosDone {
            setBubbleMessage("今日待办清空啦！" + petLine("praise", fallback: "阿念给你叼一根骨头当奖杯。"), priority: .todo, hold: 9)
            celebrateCompletion(style: .big, triggerGlobalEffect: true)
        } else if completionStreak > 0 && completionStreak % 3 == 0 {
            setBubbleMessage("连胜三爪！" + petLine("praise", fallback: "剩下的我也相信你。"), priority: .todo, hold: 9)
            celebrateCompletion(style: .medium, triggerGlobalEffect: true)
        } else if isFirstCompletionToday {
            setBubbleMessage("今日第一件完成！" + petLine("praise", fallback: "行动已经启动啦。"), priority: .todo, hold: 8)
            celebrateCompletion(style: .medium, triggerGlobalEffect: false)
        } else {
            setBubbleMessage(petLine("praise", fallback: "好耶！你又完成一件大事。"), priority: .todo, hold: 8)
            celebrateCompletion(style: .small, triggerGlobalEffect: false)
        }
    }

    private func celebrateCompletion(style: CelebrationStyle = .small, triggerGlobalEffect: Bool = false) {
        guard let window else { return }
        celebrationStyle = style
        celebrationOrigin = window.frame.origin
        celebrationBubbleFrame = bubblePanel?.isVisible == true ? bubblePanel?.frame : nil
        celebrationTagFrame = currentTagScreenFrame()
        if let screenFrame = NSScreen.main?.visibleFrame {
            celebrationBounds = makeCelebrationBounds(around: petScreenFrame(for: window.frame), inside: screenFrame, style: style)
        } else {
            celebrationBounds = nil
        }
        if triggerGlobalEffect {
            triggerGlobalCelebrationEffectShortcut()
        }
        // Keep the small status tag attached to the puppy during celebration.
        // The liquid todo bubble remains fixed; no extra frozen tag window is created.
        celebrationStartedAt = Date()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.15) { [weak self] in
            guard let self, self.mood == .celebrating else { return }
            self.finishCelebrationIfNeeded(returningToOrigin: true)
        }
        paused = false
        updateActionModePopup()
        bubbleView.stopButton.title = "同步日历"
        setMood(.celebrating)
    }

    private func dayKey(for date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func monthKey(for date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: date)
    }

    private func saveTodos() {
        if let data = try? JSONEncoder().encode(todos) {
            UserDefaults.standard.set(data, forKey: PetSettings.todos)
        }
        cleanupPomodoroLinkedTodoIfNeeded()
        refreshPomodoroTodoPopup()
        updatePetProgress()
    }

    @discardableResult
    private func ensureTodoIDs() -> Bool {
        var changed = false
        for index in todos.indices {
            if todos[index].id?.isEmpty != false {
                todos[index].id = UUID().uuidString
                changed = true
            }
        }
        return changed
    }

    private func todoID(_ todo: TodoItem) -> String? {
        guard let id = todo.id, !id.isEmpty else { return nil }
        return id
    }

    private func cleanupPomodoroLinkedTodoIfNeeded() {
        guard let linkedID = pomodoroLinkedTodoID else { return }
        let stillAvailable = todos.contains { todo in
            !todo.done && todoID(todo) == linkedID
        }
        if !stillAvailable {
            pomodoroLinkedTodoID = nil
            UserDefaults.standard.set("", forKey: PetSettings.pomodoroLinkedTodoID)
        }
    }

    private func refreshPomodoroTodoPopup() {
        let popup = bubbleView.pomodoroTodoPopup
        let selectedID = pomodoroLinkedTodoID
        popup.removeAllItems()
        popup.addItem(withTitle: "不绑定待办")
        popup.lastItem?.representedObject = ""

        for todo in todos where !todo.done {
            guard let id = todoID(todo) else { continue }
            let itemTitle = "绑定：\(shortTodoTitle(todo.title, limit: 16))"
            popup.addItem(withTitle: itemTitle)
            popup.lastItem?.representedObject = id
        }

        if let selectedID,
           let item = popup.itemArray.first(where: { ($0.representedObject as? String) == selectedID }) {
            popup.select(item)
        } else {
            popup.selectItem(at: 0)
        }
        popup.isEnabled = !pomodoroEnabled && popup.numberOfItems > 1
    }

    private func shortTodoTitle(_ title: String, limit: Int) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        let prefix = trimmed.prefix(limit)
        return "\(prefix)…"
    }

    @objc private func pomodoroTodoSelectionChanged() {
        let selectedID = bubbleView.pomodoroTodoPopup.selectedItem?.representedObject as? String
        pomodoroLinkedTodoID = selectedID?.isEmpty == false ? selectedID : nil
        UserDefaults.standard.set(pomodoroLinkedTodoID ?? "", forKey: PetSettings.pomodoroLinkedTodoID)
        if let title = linkedTodoTitle() {
            setBubbleMessage("阿念已把番茄钟绑定到：\(title)", priority: .pomodoro, hold: 5)
        } else {
            setBubbleMessage("阿念已取消本轮待办绑定。", priority: .pomodoro, hold: 5)
        }
    }

    private func syncPomodoroLinkedTodoFromPopup() {
        let selectedID = bubbleView.pomodoroTodoPopup.selectedItem?.representedObject as? String
        pomodoroLinkedTodoID = selectedID?.isEmpty == false ? selectedID : nil
        UserDefaults.standard.set(pomodoroLinkedTodoID ?? "", forKey: PetSettings.pomodoroLinkedTodoID)
    }

    private func linkedTodoTitle() -> String? {
        guard let linkedID = pomodoroLinkedTodoID else { return nil }
        return todos.first { todo in
            !todo.done && todoID(todo) == linkedID
        }?.title
    }

    private func currentPetProgress() -> (mode: PetProgressMode, value: CGFloat, label: String) {
        if pomodoroEnabled, pomodoroTimerMode == .countUp {
            let elapsed = currentFocusElapsedSeconds()
            let lapElapsed = elapsed % countUpLapSeconds
            let value = CGFloat(lapElapsed) / CGFloat(countUpLapSeconds)
            return (.focus, max(0, min(1, value)), pomodoroLaneText())
        }

        if pomodoroEnabled, let endDate = pomodoroEndDate {
            if pomodoroIsBreak {
                return (.rest, 0, pomodoroLaneText())
            }
            let totalMinutes = max(1, activeFocusMinutes)
            let totalSeconds = CGFloat(totalMinutes * 60)
            let remaining = max(0, CGFloat(endDate.timeIntervalSinceNow))
            let value = max(0, min(1, 1 - remaining / totalSeconds))
            return (.focus, value, pomodoroLaneText())
        }

        return (.empty, 0, "番茄钟未开始")
    }

    private func pomodoroLaneText() -> String {
        if pomodoroEnabled, pomodoroTimerMode == .countUp {
            return "正计时 \(formatCountUpClock(currentFocusElapsedSeconds()))"
        }
        guard pomodoroEnabled, let endDate = pomodoroEndDate else { return "番茄钟未开始" }
        let remaining = max(0, Int(ceil(endDate.timeIntervalSinceNow)))
        let minutes = remaining / 60
        let seconds = remaining % 60
        let phase = pomodoroIsBreak ? "休息中" : "专注中"
        return String(format: "%@ %02d:%02d", phase, minutes, seconds)
    }

    private func updatePetProgress(flash: Bool = false) {
        if progressLaneActive && (!pomodoroEnabled || pomodoroIsBreak) {
            setProgressLaneActive(false)
            return
        }
        let progress = currentPetProgress()
        hamsterView.progressMode = progress.mode
        hamsterView.progressValue = progress.value
        if pomodoroEnabled && mood != .reminding && mood != .celebrating {
            setMood(baseMoodForCurrentState())
        }
        if flash {
            flashPetProgress()
        }
        guard progressLaneActive else { return }
        if mood != .celebrating && mood != .reminding && mood != .walking {
            setMood(.walking)
        }
        positionPetOnProgressLane(progress.value)
        refreshVisibleStatusTagIfNeeded(pomodoroLaneText())
    }

    private func flashPetProgress() {
        progressFlashResetTimer?.invalidate()
        hamsterView.progressFlash = true
        progressFlashResetTimer = Timer.scheduledTimer(withTimeInterval: 0.65, repeats: false) { [weak self] _ in
            self?.hamsterView.progressFlash = false
        }
    }

    private func progressLaneTriggerContainsCurrentPet() -> Bool {
        guard let window else { return false }
        let screenFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        guard let screenFrame else { return false }
        let petFrame = petScreenFrame(for: window.frame)
        // Keep the intended bottom-left gesture, but make the drop zone forgiving.
        // The former target was too small, especially on scaled displays.
        let leftZoneMaxX = screenFrame.minX + max(240, petFrame.width * 2.4)
        let bottomZoneMaxY = screenFrame.minY + max(125, petFrame.height * 1.55)
        return petFrame.midX <= leftZoneMaxX && petFrame.midY <= bottomZoneMaxY
    }

    private func progressLaneTriggerContains(dropPoint: NSPoint) -> Bool {
        let screenFrame = NSScreen.screens.first(where: { $0.frame.contains(dropPoint) })?.visibleFrame
            ?? window?.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
        guard let screenFrame else { return false }
        let leftZoneMaxX = screenFrame.minX + 360
        let bottomZoneMaxY = screenFrame.minY + 220
        return dropPoint.x <= leftZoneMaxX && dropPoint.y <= bottomZoneMaxY
    }

    private func setProgressLaneActive(_ active: Bool) {
        if active && !pomodoroEnabled {
            progressLaneActive = false
            hideStatusTag()
            setBubbleMessage("阿念等番茄钟开始后，才会进入底部跑道。", priority: .todo, hold: 6)
            return
        }
        if active && pomodoroIsBreak {
            progressLaneActive = false
            hideStatusTag()
            resizePet(to: normalPetSize)
            paused = true
            setMood(.sleepy)
            setBubbleMessage("阿念休息中不用跑道，先坐着陪你喘口气。", priority: .pomodoro, hold: 6)
            return
        }
        guard progressLaneActive != active else {
            updatePetProgress()
            return
        }
        progressLaneActive = active
        if active {
            updateWindowLevelForMode()
            resizePet(to: lanePetSize)
            facing = 1
            hamsterView.facing = 1
            setMood(.walking)
            updatePetProgress()
            showProgressLaneEnteredEffect()
            let message = pomodoroTimerMode == .countUp
                ? "阿念进入进度跑道，每25分钟从左到右跑一圈。"
                : "阿念进入进度跑道，开始陪你把番茄走完。"
            setBubbleMessage(message, priority: .todo, hold: 6)
        } else {
            hideStatusTag()
            resizePet(to: normalPetSize)
            setMood(baseMoodForCurrentState())
            setBubbleMessage("阿念离开底部进度跑道。", priority: .todo, hold: 5)
        }
    }

    private func resizePet(to size: NSSize) {
        guard let window else {
            hamsterView.frame.size = size
            return
        }
        let currentPetFrame = petScreenFrame(for: window.frame)
        let center = NSPoint(x: currentPetFrame.midX, y: currentPetFrame.midY)
        hamsterView.frame.size = size
        var frame = windowFrame(window.frame, placingPetCenterAt: center)
        if let screenFrame = NSScreen.main?.visibleFrame {
            frame = clampWindowFrameByPetBounds(frame, inside: screenFrame.insetBy(dx: 4, dy: 2))
        }
        window.setFrame(frame, display: true)
        resizeStatusTag(for: tagLabel.stringValue)
    }

    private func showProgressLaneEnteredEffect() {
        flashPetProgress()
        for delay in [0.0, 0.12, 0.24] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.spawnFloatingEmoji()
            }
        }
        showStatusTag("跑道就绪", duration: 1.2)
    }

    private func positionPetOnProgressLane(_ value: CGFloat) {
        guard let window, let screenFrame = NSScreen.main?.visibleFrame else { return }
        if hamsterView.frame.size != lanePetSize {
            resizePet(to: lanePetSize)
        }
        let clamped = max(0, min(1, value))
        let petSize = hamsterView.frame.size
        let inset: CGFloat = 8
        let startX = screenFrame.minX + inset + petSize.width / 2
        let endX = screenFrame.maxX - inset - petSize.width / 2
        let centerX = startX + (endX - startX) * clamped
        let centerY = screenFrame.minY + 4 + petSize.height / 2
        var frame = windowFrame(window.frame, placingPetCenterAt: NSPoint(x: centerX, y: centerY))
        frame = clampWindowFrameByPetBounds(frame, inside: screenFrame.insetBy(dx: 4, dy: 2))
        facing = 1
        hamsterView.facing = 1
        window.setFrame(frame, display: true)
    }

    private func todoSourcePrefix(for todo: TodoItem) -> String {
        guard let key = todo.calendarKey else { return "" }
        if key.hasPrefix("reminder#") { return "提醒" }
        return "日程"
    }

    private func todoPomodoroDetail(for todo: TodoItem) -> String? {
        let seconds = todoPomodoroSecondsForDisplay(todo)
        if todo.done {
            if let completedAt = todo.completedAt {
                guard seconds > 0 else { return "✓ \(clockTime(completedAt)) 完成" }
                let spent = formatTodoDuration(seconds)
                return "🍅 用时 \(spent) · \(clockTime(completedAt)) 完成"
            }
            guard seconds > 0 else { return "✓ 已完成" }
            return "🍅 用时 \(formatTodoDuration(seconds))"
        }
        guard seconds > 0 else { return nil }
        let spent = formatTodoDuration(seconds)
        if isTodoLinkedToActiveFocus(todo) {
            return "🍅 已用 \(spent) · 本轮进行中"
        }
        return "🍅 已用 \(spent)"
    }

    private func todoPomodoroSecondsForDisplay(_ todo: TodoItem) -> Int {
        var seconds = todo.pomodoroSeconds ?? 0
        if isTodoLinkedToActiveFocus(todo) {
            seconds += currentFocusElapsedSeconds()
        }
        return seconds
    }

    private func isTodoLinkedToActiveFocus(_ todo: TodoItem) -> Bool {
        guard pomodoroEnabled,
              !pomodoroIsBreak,
              let linkedID = pomodoroLinkedTodoID,
              let id = todoID(todo),
              !todo.done
        else { return false }
        return linkedID == id
    }

    private func currentFocusElapsedSeconds() -> Int {
        guard pomodoroEnabled, !pomodoroIsBreak else { return 0 }
        if pomodoroTimerMode == .countUp {
            guard let startDate = pomodoroCountUpStartDate else { return 0 }
            return max(0, Int(Date().timeIntervalSince(startDate)))
        }
        guard let endDate = pomodoroEndDate else { return 0 }
        let totalSeconds = max(1, activeFocusMinutes * 60)
        let remaining = max(0, Int(ceil(endDate.timeIntervalSinceNow)))
        return max(0, min(totalSeconds, totalSeconds - remaining))
    }

    private func formatCountUpClock(_ seconds: Int) -> String {
        let safeSeconds = max(0, seconds)
        let hours = safeSeconds / 3600
        let minutes = (safeSeconds % 3600) / 60
        let remainder = safeSeconds % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, remainder)
        }
        return String(format: "%02d:%02d", minutes, remainder)
    }

    private func formatTodoDuration(_ seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds)秒"
        }
        let minutes = seconds / 60
        let restSeconds = seconds % 60
        if minutes < 60 {
            return restSeconds == 0 ? "\(minutes)分钟" : "\(minutes)分钟\(restSeconds)秒"
        }
        let hours = minutes / 60
        let restMinutes = minutes % 60
        return restMinutes == 0 ? "\(hours)小时" : "\(hours)小时\(restMinutes)分钟"
    }

    private func clockTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func renderTodos() {
        updatePetProgress()
        for view in bubbleView.todoStackView.arrangedSubviews {
            bubbleView.todoStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let unfinishedTodos = todos.enumerated().filter { !$0.element.done }
        let completedTodos = todos.enumerated().filter { $0.element.done }

        if todos.isEmpty {
            let empty = NSTextField(labelWithString: "今天先写一个小目标。")
            empty.font = .systemFont(ofSize: 12, weight: .semibold)
            empty.textColor = NSColor(hex: 0x202334)
            empty.drawsBackground = false
            bubbleView.todoStackView.addArrangedSubview(empty)
            return
        }

        let syncedCount = todos.filter { $0.calendarKey != nil }.count
        if syncedCount > 0 {
            let syncedHint = NSTextField(labelWithString: "已同步今日事项：\(syncedCount) 个")
            syncedHint.font = .systemFont(ofSize: 11, weight: .semibold)
            syncedHint.textColor = NSColor(hex: 0x5B5460)
            bubbleView.todoStackView.addArrangedSubview(syncedHint)
        }

        func appendTodoRow(index: Int, todo: TodoItem) {
            let prefix = todoSourcePrefix(for: todo)
            let unfinishedTitle = prefix.isEmpty ? todo.title : "\(prefix)  \(todo.title)"
            let displayTitle = todo.done ? "✓ 已完成  \(todo.title)" : unfinishedTitle
            let item = NSButton(checkboxWithTitle: displayTitle, target: self, action: #selector(toggleTodo(_:)))
            item.tag = index
            item.state = todo.done ? .on : .off
            item.font = .systemFont(ofSize: 12, weight: todo.done ? .semibold : .bold)
            item.contentTintColor = todo.done ? NSColor(hex: 0x347A4E) : NSColor(hex: 0x202334)
            item.cell?.lineBreakMode = .byTruncatingTail
            let menu = todoContextMenu(for: index, done: todo.done)
            item.menu = menu
            item.attributedTitle = NSAttributedString(
                string: displayTitle,
                attributes: [
                    .foregroundColor: todo.done ? NSColor(hex: 0x347A4E) : NSColor(hex: 0x202334),
                    .strikethroughStyle: todo.done ? NSUnderlineStyle.single.rawValue : 0,
                    .kern: 0.1
                ]
            )

            let row = TodoRowView(checkbox: item, done: todo.done, menu: menu, detail: todoPomodoroDetail(for: todo))
            row.translatesAutoresizingMaskIntoConstraints = false
            row.widthAnchor.constraint(equalToConstant: 280).isActive = true
            bubbleView.todoStackView.addArrangedSubview(row)
        }

        if unfinishedTodos.isEmpty {
            let empty = NSTextField(labelWithString: "未完成清空啦，阿念摇尾巴。")
            empty.font = .systemFont(ofSize: 12, weight: .semibold)
            empty.textColor = NSColor(hex: 0x4A7DB5)
            empty.drawsBackground = false
            bubbleView.todoStackView.addArrangedSubview(empty)
        } else {
            for (index, todo) in unfinishedTodos {
                appendTodoRow(index: index, todo: todo)
            }
        }

        if !completedTodos.isEmpty {
            let title = completedTodosExpanded ? "🐾 已完成 \(completedTodos.count) 项 ▾" : "🐾 已完成 \(completedTodos.count) 项 ▸"
            let foldButton = NSButton(title: title, target: self, action: #selector(toggleCompletedTodosExpanded))
            foldButton.bezelStyle = .rounded
            foldButton.font = .systemFont(ofSize: 12, weight: .bold)
            foldButton.contentTintColor = NSColor(hex: 0x4A7DB5)
            foldButton.alignment = .left
            bubbleView.todoStackView.addArrangedSubview(foldButton)

            if completedTodosExpanded {
                for (index, todo) in completedTodos {
                    appendTodoRow(index: index, todo: todo)
                }
            }
        }
    }

    private func todoContextMenu(for index: Int, done: Bool) -> NSMenu {
        let menu = NSMenu()
        let strikeItem = NSMenuItem(title: "划掉并删除", action: #selector(strikeTodoFromMenu(_:)), keyEquivalent: "")
        strikeItem.target = self
        strikeItem.tag = index
        menu.addItem(strikeItem)
        if done {
            let undoItem = NSMenuItem(title: "取消完成", action: #selector(unstrikeTodoFromMenu(_:)), keyEquivalent: "")
            undoItem.target = self
            undoItem.tag = index
            menu.addItem(undoItem)
        }
        return menu
    }

    @objc private func dragPet(_ recognizer: NSPanGestureRecognizer) {
        guard let window else { return }
        switch recognizer.state {
        case .began:
            // A large settings panel could collide with the manually dragged pet
            // and push it back out of the progress-lane trigger. Fold the panel
            // away as soon as an active focus pet is picked up.
            if pomodoroEnabled && !pomodoroIsBreak {
                bubblePanel?.orderOut(nil)
            }
            hamsterView.forceStandingPose = true
            dragStart = NSEvent.mouseLocation
            windowStart = window.frame.origin
        case .changed:
            guard let dragStart, let windowStart else { return }
            let current = NSEvent.mouseLocation
            let dx = current.x - dragStart.x
            let dy = current.y - dragStart.y
            var frame = window.frame
            frame.origin = NSPoint(x: windowStart.x + dx, y: windowStart.y + dy)
            let targetScreenFrame = NSScreen.screens.first(where: { $0.frame.contains(current) })?.visibleFrame
                ?? window.screen?.visibleFrame
                ?? NSScreen.main?.visibleFrame
            if let screenFrame = targetScreenFrame {
                frame = clampWindowFrameByPetBounds(frame, inside: screenFrame.insetBy(dx: 8, dy: 8))
                frame = adjustedPetFrameAvoidingBubble(frame, screenFrame: screenFrame)
            }
            window.setFrame(frame, display: true)
            followPetWithBubbleIfNeeded()
        case .ended:
            let dropPoint = NSEvent.mouseLocation
            hamsterView.forceStandingPose = false
            dragStart = nil
            windowStart = nil
            let shouldEnterLane = progressLaneTriggerContains(dropPoint: dropPoint)
                || progressLaneTriggerContainsCurrentPet()
            setProgressLaneActive(shouldEnterLane)
        case .cancelled, .failed:
            hamsterView.forceStandingPose = false
            dragStart = nil
            windowStart = nil
        default:
            break
        }
    }

    @objc private func dragBubble(_ recognizer: NSPanGestureRecognizer) {
        guard let bubblePanel, bubblePanel.isVisible, let screenFrame = NSScreen.main?.visibleFrame else { return }
        switch recognizer.state {
        case .began:
            bubbleDragStart = NSEvent.mouseLocation
            bubbleWindowStart = bubblePanel.frame.origin
        case .changed:
            guard let bubbleDragStart, let bubbleWindowStart else { return }
            let current = NSEvent.mouseLocation
            let dx = current.x - bubbleDragStart.x
            let dy = current.y - bubbleDragStart.y
            var frame = bubblePanel.frame
            frame.origin = NSPoint(x: bubbleWindowStart.x + dx, y: bubbleWindowStart.y + dy)
            frame = clamp(frame, inside: screenFrame.insetBy(dx: 8, dy: 8))
            bubblePanel.setFrame(frame, display: true)
            if mood == .celebrating {
                celebrationBubbleFrame = frame
            }
        default:
            bubbleDragStart = nil
            bubbleWindowStart = nil
        }
    }

    private func handlePetHoverBegan() {
        isPetHovered = true
        guard mood != .reminding else { return }
        if progressLaneActive {
            showStatusTag(pomodoroLaneText(), duration: 5)
            return
        }
        let text = petLine("touch", fallback: "阿念收到摸头礼。")
        setBubbleMessage(text, priority: .ambient)
    }

    private func handlePetHoverEnded() {
        isPetHovered = false
        if progressLaneActive { return }
        guard !paused, mood != .celebrating && mood != .reminding else { return }
        setMood(baseMoodForCurrentState())
    }

    private func handlePetHeadHover() {
        if progressLaneActive {
            showStatusTag(pomodoroLaneText(), duration: 5)
            return
        }
        guard isPetHovered, mood != .celebrating else { return }
        let now = Date()
        guard now.timeIntervalSince(lastHeadHoverEmojiAt) > 0.55 else { return }
        lastHeadHoverEmojiAt = now
        spawnFloatingEmoji()
    }

    private func handleNoseClick() {
        let now = Date()
        noseTapTimes = (noseTapTimes + [now]).filter { now.timeIntervalSince($0) <= 1.4 }
        if noseTapTimes.count >= 3 {
            noseTapTimes.removeAll()
            NSApp.terminate(nil)
        } else if noseTapTimes.count == 2 {
            setBubbleMessage("再点一下阿念鼻子，就退出啦。", priority: .todo, hold: 3)
        }
    }

    private func chooseMood() {
        updatePomodoroFocusRecordLabel()
        guard !progressLaneActive && !pomodoroEnabled && !paused && !isPetHovered && mood != .celebrating else { return }
        let hour = Calendar.current.component(.hour, from: Date())
        if hour >= 23 || hour < 7 {
            setMood(.sleepy)
            return
        }
        setMood(selectedActionIndex == 1 ? .walking : .idle)
    }

    private func setMood(_ next: PetMood, hold seconds: TimeInterval? = nil) {
        let resolved = next
        let changed = mood != resolved
        if changed || seconds != nil {
            moodHoldTimer?.invalidate()
            moodHoldTimer = nil
        }
        mood = resolved
        hamsterView.mood = resolved
        if changed {
            frameIndex = 0
            hamsterView.frameIndex = 0
        }
        updateStatusTag()
        if resolved != .reminding && !todosVisible {
            let text = petLine("daily", fallback: "阿念在旁边守着。")
            setBubbleMessage(text, priority: .ambient)
        }
        if let seconds, seconds > 0 {
            moodHoldTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
                guard let self else { return }
                self.setMood(self.baseMoodForCurrentState())
            }
        }
    }

    private func baseMoodForCurrentState() -> PetMood {
        if progressLaneActive { return .walking }
        if selectedActionIndex == 1 && !paused { return .walking }
        if selectedActionIndex == 3 { return .sleepy }
        if pomodoroEnabled && pomodoroIsBreak { return .sleepy }
        return .idle
    }

    private func performTouchSpin() {
        guard mood != .reminding else { return }
        setMood(.celebrating, hold: 1.35)
        frameIndex = 0
        hamsterView.frameIndex = 0
        spawnFloatingEmoji()
    }

    private func petLine(_ category: String, fallback: String) -> String {
        let relatedCategories: [String]
        switch category {
        case "daily":
            relatedCategories = ["daily", "special"]
        case "tired":
            relatedCategories = ["tired", "comfort"]
        case "rest":
            relatedCategories = ["rest", "comfort"]
        default:
            relatedCategories = [category]
        }
        let candidates = relatedCategories.flatMap { petLines[$0] ?? [] }
        return candidates.randomElement() ?? fallback
    }

    private func petLine(_ category: String, task: String, fallback: String) -> String {
        petLine(category, fallback: fallback).replacingOccurrences(of: "{task}", with: task)
    }

    private func setBubbleMessage(_ text: String, priority: MessagePriority, hold seconds: TimeInterval? = nil) {
        expireMessageHoldIfNeeded()
        guard priority.rawValue >= messagePriority.rawValue else { return }
        messageResetTimer?.invalidate()
        messageResetTimer = nil
        messagePriority = priority
        messageHoldUntil = seconds.map { Date().addingTimeInterval($0) }
        bubbleView.moodLabel.stringValue = text
        if let seconds {
            messageResetTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
                self?.restoreBubbleMessageAfterHold()
            }
        }
    }

    private func expireMessageHoldIfNeeded() {
        guard let holdUntil = messageHoldUntil, Date() >= holdUntil else { return }
        messageResetTimer?.invalidate()
        messageResetTimer = nil
        restoreBubbleMessageAfterHold()
    }

    private func restoreBubbleMessageAfterHold() {
        messagePriority = .ambient
        messageHoldUntil = nil
        messageResetTimer?.invalidate()
        messageResetTimer = nil
        if pomodoroEnabled {
            bubbleView.moodLabel.stringValue = pomodoroIsBreak
                ? petLine("rest", fallback: "阿念休息一下汪。")
                : petLine("focus", fallback: "阿念坐着陪你专注汪。")
        } else {
            bubbleView.moodLabel.stringValue = petLine("daily", fallback: defaultBubbleMessage)
        }
    }

    private func showFirstRunOnboardingIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: PetSettings.onboardingSeen) else { return }
        defaults.set(true, forKey: PetSettings.onboardingSeen)
        todosVisible = true
        setTodosVisible(true)
        updateBubbleSize()
        positionBubblePanelSmartly()
        bubblePanel?.orderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        setBubbleMessage("阿念教你阿念入门：点阿念开面板；一行一个待办；日程会入册；🍅 负责专注。", priority: .onboarding, hold: 18)
    }

    private func updateStatusTag() {
        if progressLaneActive {
            refreshVisibleStatusTagIfNeeded(pomodoroLaneText())
            return
        }
        if pomodoroEnabled {
            updatePomodoroStatusTag()
            return
        }
        switch mood {
        case .walking:
            hideStatusTag()
        case .idle, .curious:
            showStatusTag(ambientStatusText(), duration: 4.5)
        case .sleepy, .reminding, .celebrating:
            showStatusTag(mood.tag, duration: 6)
        }
    }

    private func ambientStatusText() -> String {
        if mood == .walking || mood == .idle || mood == .curious {
            let now = Date()
            if now.timeIntervalSince(lastAmbientTagRefreshAt) > 35 || ambientTagText.isEmpty {
                ambientTagText = casualTags.randomElement() ?? mood.tag
                lastAmbientTagRefreshAt = now
            }
            return ambientTagText
        }
        return mood.tag
    }

    private func moveIfNeeded() {
        if progressLaneActive {
            updatePetProgress()
            return
        }
        guard !paused, !isPetHovered, mood.usesWalkingPose, dragStart == nil, let window, let screenFrame = NSScreen.main?.visibleFrame else { return }
        var frame = window.frame
        let previousPetCenter = center(of: petScreenFrame(for: frame))

        if mood == .celebrating {
            let elapsed = celebrationStartedAt.map { Date().timeIntervalSince($0) } ?? 0
            let duration: TimeInterval = 2.0
            if elapsed >= duration {
                finishCelebrationIfNeeded(returningToOrigin: true)
                return
            }

            let progress = max(0, min(CGFloat(elapsed / duration), 1))
            let bounds = celebrationBounds ?? makeCelebrationBounds(around: petScreenFrame(for: window.frame), inside: screenFrame, style: celebrationStyle)
            let center = NSPoint(x: bounds.midX, y: bounds.midY)
            let petSize = hamsterView.frame.size
            let maxRadiusX = max(12, bounds.width / 2 - petSize.width / 2)
            let maxRadiusY = max(12, bounds.height / 2 - petSize.height / 2)
            let radiusPulse = sin(progress * CGFloat.pi)
            let angle = progress * CGFloat.pi * 4.6
            let wobble = sin(progress * CGFloat.pi * 9) * 0.18

            let targetPetCenter = NSPoint(
                x: center.x + cos(angle) * maxRadiusX * (0.35 + 0.65 * radiusPulse),
                y: center.y + sin(angle + wobble) * maxRadiusY * (0.35 + 0.65 * radiusPulse)
            )
            frame = windowFrame(frame, placingPetCenterAt: targetPetCenter)
            frame = clampWindowFrameByPetBounds(frame, inside: bounds)
            frame = softlyAdjustedCelebrationFrameAvoidingBubble(frame, screenFrame: screenFrame, movementBounds: bounds)
        } else {
            var dx: CGFloat = 0
            var dy: CGFloat = 0
            switch walkMode {
            case .horizontal:
                dx = facing * 3.5
            case .vertical:
                dy = verticalDirection * 3.5
            case .fourWay:
                if Int.random(in: 0...18) == 0 {
                    let dirs: [(CGFloat, CGFloat)] = [(1, 0), (-1, 0), (0, 1), (0, -1)]
                    let next = dirs.randomElement() ?? (1, 0)
                    facing = next.0 == 0 ? facing : next.0
                    verticalDirection = next.1 == 0 ? verticalDirection : next.1
                }
                dx = facing * 3.5
                dy = verticalDirection * 2.8
            case .still:
                setMood(.idle)
                return
            }
            frame.origin.x += dx
            frame.origin.y += dy
        }

        let petFrameBeforeClamp = petScreenFrame(for: frame)
        if petFrameBeforeClamp.minX < screenFrame.minX + 8 || petFrameBeforeClamp.maxX > screenFrame.maxX - 8 {
            setWalkingFacing(-facing)
        }
        if petFrameBeforeClamp.minY < screenFrame.minY + 8 || petFrameBeforeClamp.maxY > screenFrame.maxY - 8 {
            verticalDirection *= -1
        }
        let allowedPetBounds = (mood == .celebrating ? celebrationBounds : nil) ?? screenFrame.insetBy(dx: 8, dy: 8)
        frame = clampWindowFrameByPetBounds(frame, inside: allowedPetBounds)
        if mood == .celebrating {
            frame = softlyAdjustedCelebrationFrameAvoidingBubble(frame, screenFrame: screenFrame, movementBounds: celebrationBounds)
        } else {
            frame = adjustedPetFrameAvoidingBubble(frame, screenFrame: screenFrame)
        }
        updateFacingFromActualMovement(previousCenter: previousPetCenter, finalFrame: frame)
        window.setFrame(frame, display: false)
        followPetWithBubbleIfNeeded()
    }

    private func finishCelebrationIfNeeded(returningToOrigin: Bool) {
        guard mood == .celebrating else { return }
        if returningToOrigin, let window, let origin = celebrationOrigin {
            var frame = window.frame
            frame.origin = origin
            window.setFrame(frame, display: true)
        }
        endCelebrationTextFreeze()
        celebrationStartedAt = nil
        celebrationOrigin = nil
        celebrationBubbleFrame = nil
        celebrationTagFrame = nil
        celebrationBounds = nil
        celebrationStyle = .small
        if pomodoroEnabled {
            paused = true
            updateActionModePopup()
            setMood(baseMoodForCurrentState())
            updatePomodoroCountdown()
        } else {
            setMood(baseMoodForCurrentState())
        }
    }

    private func center(of rect: NSRect) -> NSPoint {
        NSPoint(x: rect.midX, y: rect.midY)
    }

    private func updateFacingFromActualMovement(previousCenter: NSPoint, finalFrame: NSRect) {
        let finalCenter = center(of: petScreenFrame(for: finalFrame))
        let horizontalDelta = finalCenter.x - previousCenter.x
        // Face the real movement direction after clamp / bubble-avoid adjustments.
        // This prevents the puppy from looking forward on the planned path but visually moonwalking after correction.
        guard abs(horizontalDelta) > 0.7 else { return }
        let actualFacing: CGFloat = horizontalDelta > 0 ? 1 : -1
        setWalkingFacing(actualFacing)
    }

    private func setWalkingFacing(_ newFacing: CGFloat) {
        guard newFacing != facing else { return }
        facing = newFacing
        hamsterView.facing = newFacing

        guard mood.usesWalkingPose else { return }
        // Turn on an even frame, where one paw has just made contact, so the
        // mirrored stride does not visibly reverse in mid-air.
        let contactFrame = frameIndex.isMultiple(of: 2)
            ? frameIndex
            : (frameIndex + 1) % 8
        frameIndex = contactFrame
        hamsterView.frameIndex = contactFrame
    }

    private func makeCelebrationBounds(around petFrame: NSRect, inside screenFrame: NSRect, style: CelebrationStyle = .small) -> NSRect {
        // Product rule: daily movement stays calm, while important moments get a little more room.
        // Even the largest celebration is now far smaller than the old quarter-screen sweep.
        let size: NSSize
        switch style {
        case .small:
            size = NSSize(width: max(150, screenFrame.width * 0.16), height: max(120, screenFrame.height * 0.14))
        case .medium:
            size = NSSize(width: max(190, screenFrame.width * 0.22), height: max(145, screenFrame.height * 0.18))
        case .big:
            size = NSSize(width: max(230, screenFrame.width * 0.28), height: max(170, screenFrame.height * 0.22))
        }
        let center = NSPoint(x: petFrame.midX, y: petFrame.midY)
        let raw = NSRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
        return clamp(raw, inside: screenFrame.insetBy(dx: 12, dy: 12))
    }

    private func triggerGlobalCelebrationEffectShortcut() {
        // Use a soft emoji burst instead of geometric confetti. It feels more like
        // the puppy is celebrating with you, and avoids Accessibility shortcuts.
        showEdgeConfettiOverlay()
    }

    private func showEdgeConfettiOverlay() {
        showEdgeConfettiOverlay(style: .allEdgesEmoji, duration: 2.05)
    }

    private func showSideRibbonBurst() {
        showEdgeConfettiOverlay(style: .sideRibbons, duration: 2.85)
    }

    private func showEdgeConfettiOverlay(style: EmojiBurstOverlayView.Style, duration: TimeInterval, emojis: [String]? = nil) {
        guard let screen = NSScreen.main else { return }
        confettiTimer?.invalidate()
        confettiPanel?.orderOut(nil)

        let frame = screen.frame
        let overlay = EmojiBurstOverlayView(frame: NSRect(origin: .zero, size: frame.size), style: style, emojis: emojis)
        let panel = PetPanel(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.contentView = overlay
        confettiPanel = panel
        panel.orderFrontRegardless()

        let started = Date()
        confettiTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self, weak overlay] timer in
            let elapsed = Date().timeIntervalSince(started)
            let progress = CGFloat(min(1, elapsed / duration))
            overlay?.progress = progress
            if progress >= 1 {
                timer.invalidate()
                self?.confettiTimer = nil
                self?.confettiPanel?.orderOut(nil)
                self?.confettiPanel = nil
            }
        }
    }

    private func softlyAdjustedCelebrationFrameAvoidingBubble(_ proposedFrame: NSRect, screenFrame: NSRect, movementBounds: NSRect? = nil) -> NSRect {
        guard let bubblePanel, bubblePanel.isVisible else { return proposedFrame }

        let safetyGap: CGFloat = 16
        let bubbleRect = bubblePanel.frame.insetBy(dx: -safetyGap, dy: -safetyGap)
        let proposedPet = petScreenFrame(for: proposedFrame)
        guard proposedPet.intersects(bubbleRect) else { return proposedFrame }

        let allowedPetBounds = movementBounds ?? screenFrame.insetBy(dx: 8, dy: 8)
        var frame = proposedFrame
        let petCenter = NSPoint(x: proposedPet.midX, y: proposedPet.midY)
        let bubbleCenter = NSPoint(x: bubbleRect.midX, y: bubbleRect.midY)

        var vx = petCenter.x - bubbleCenter.x
        var vy = petCenter.y - bubbleCenter.y
        if abs(vx) < 0.001 && abs(vy) < 0.001 {
            vx = facing >= 0 ? 1 : -1
            vy = 0.35
        }

        let length = max(1, hypot(vx, vy))
        let nx = vx / length
        let ny = vy / length
        let overlapX = min(proposedPet.maxX, bubbleRect.maxX) - max(proposedPet.minX, bubbleRect.minX)
        let overlapY = min(proposedPet.maxY, bubbleRect.maxY) - max(proposedPet.minY, bubbleRect.minY)
        let push = max(10, min(42, min(overlapX, overlapY) + safetyGap))

        frame.origin.x += nx * push
        frame.origin.y += ny * push
        return clampWindowFrameByPetBounds(frame, inside: allowedPetBounds)
    }

    private func adjustedPetFrameAvoidingBubble(_ proposedFrame: NSRect, screenFrame: NSRect, movementBounds: NSRect? = nil) -> NSRect {
        guard let bubblePanel, bubblePanel.isVisible else { return proposedFrame }
        let safetyGap: CGFloat = 18
        let bubbleRect = bubblePanel.frame.insetBy(dx: -safetyGap, dy: -safetyGap)
        let proposedPet = petScreenFrame(for: proposedFrame)
        guard proposedPet.intersects(bubbleRect) else { return proposedFrame }

        let allowedPetBounds = movementBounds ?? screenFrame.insetBy(dx: 8, dy: 8)
        var candidates: [NSRect] = []

        func candidateWithPetOrigin(x: CGFloat? = nil, y: CGFloat? = nil) -> NSRect {
            var candidate = proposedFrame
            let currentPet = petScreenFrame(for: candidate)
            if let x {
                candidate.origin.x += x - currentPet.minX
            }
            if let y {
                candidate.origin.y += y - currentPet.minY
            }
            return clampWindowFrameByPetBounds(candidate, inside: allowedPetBounds)
        }

        candidates.append(candidateWithPetOrigin(x: bubbleRect.minX - proposedPet.width - safetyGap))
        candidates.append(candidateWithPetOrigin(x: bubbleRect.maxX + safetyGap))
        candidates.append(candidateWithPetOrigin(y: bubbleRect.maxY + safetyGap))
        candidates.append(candidateWithPetOrigin(y: bubbleRect.minY - proposedPet.height - safetyGap))

        let safeCandidates = candidates.filter { !petScreenFrame(for: $0).intersects(bubbleRect) }
        let pool = safeCandidates.isEmpty ? candidates : safeCandidates
        let best = pool.max { lhs, rhs in
            let lhsPet = petScreenFrame(for: lhs)
            let rhsPet = petScreenFrame(for: rhs)
            let lhsDistance = hypot(lhsPet.midX - bubbleRect.midX, lhsPet.midY - bubbleRect.midY)
            let rhsDistance = hypot(rhsPet.midX - bubbleRect.midX, rhsPet.midY - bubbleRect.midY)
            return lhsDistance < rhsDistance
        }

        if let best {
            let bestPet = petScreenFrame(for: best)
            if bestPet.midX < bubbleRect.midX { facing = -1 }
            if bestPet.midX > bubbleRect.midX { facing = 1 }
            hamsterView.facing = facing
            return best
        }
        return proposedFrame
    }

    private func petScreenFrame(for windowFrame: NSRect) -> NSRect {
        let pet = hamsterView.frame
        return NSRect(
            x: windowFrame.origin.x + pet.origin.x,
            y: windowFrame.origin.y + pet.origin.y,
            width: pet.width,
            height: pet.height
        )
    }

    private func windowFrame(_ windowFrame: NSRect, placingPetCenterAt petCenter: NSPoint) -> NSRect {
        var frame = windowFrame
        frame.origin.x = petCenter.x - hamsterView.frame.midX
        frame.origin.y = petCenter.y - hamsterView.frame.midY
        return frame
    }

    private func clampWindowFrameByPetBounds(_ windowFrame: NSRect, inside bounds: NSRect) -> NSRect {
        var frame = windowFrame
        let pet = petScreenFrame(for: frame)

        if pet.minX < bounds.minX {
            frame.origin.x += bounds.minX - pet.minX
        }
        if pet.maxX > bounds.maxX {
            frame.origin.x -= pet.maxX - bounds.maxX
        }
        let petAfterX = petScreenFrame(for: frame)
        if petAfterX.minY < bounds.minY {
            frame.origin.y += bounds.minY - petAfterX.minY
        }
        if petAfterX.maxY > bounds.maxY {
            frame.origin.y -= petAfterX.maxY - bounds.maxY
        }
        return frame
    }

    private func followPetWithBubbleIfNeeded() {
        // The liquid bubble is intentionally anchored after opening.
        // It should not follow the pet while walking, dragging, or celebrating.
        if mood == .celebrating {
            restoreCelebrationTextOverlaysIfNeeded()
        }
    }

    private func currentTagScreenFrame() -> NSRect? {
        guard let window else { return nil }
        return NSRect(
            x: window.frame.minX + tagLabel.frame.minX,
            y: window.frame.minY + tagLabel.frame.minY,
            width: tagLabel.frame.width,
            height: tagLabel.frame.height
        )
    }

    private func showFrozenTagPanelIfNeeded() {
        // Intentionally unused now: the old detached “完成啦” tag could remain stuck on screen.
        // The status tag stays inside the pet window and auto-resizes instead.
        endCelebrationTextFreeze()
    }

    private func restoreCelebrationTextOverlaysIfNeeded() {
        if bubblePanel?.isVisible == true, let celebrationBubbleFrame {
            bubblePanel?.setFrame(celebrationBubbleFrame, display: true)
        }
    }

    private func endCelebrationTextFreeze() {
        frozenTagPanel?.orderOut(nil)
        frozenTagPanel = nil
        frozenTagLabel = nil
        hideStatusTag()
    }

    private func showStatusTag(_ text: String, duration: TimeInterval) {
        statusTagHideTimer?.invalidate()
        tagLabel.stringValue = text
        frozenTagLabel?.stringValue = text
        resizeStatusTag(for: text)
        tagLabel.isHidden = false
        tagLabel.alphaValue = 1
        if duration > 0 {
            statusTagHideTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                self?.hideStatusTag()
            }
        }
    }

    private func refreshVisibleStatusTagIfNeeded(_ text: String) {
        guard !tagLabel.isHidden else { return }
        tagLabel.stringValue = text
        frozenTagLabel?.stringValue = text
        resizeStatusTag(for: text)
    }

    private func hideStatusTag() {
        statusTagHideTimer?.invalidate()
        statusTagHideTimer = nil
        tagLabel.isHidden = true
        frozenTagLabel?.isHidden = true
    }

    private func resizeStatusTag(for text: String) {
        let font = tagLabel.font ?? .systemFont(ofSize: 10, weight: .bold)
        let measured = (text as NSString).size(withAttributes: [.font: font])
        let width = max(66, min(136, ceil(measured.width) + 22))
        let height: CGFloat = 22
        let centerX = hamsterView.frame.midX
        tagLabel.frame = NSRect(
            x: centerX - width / 2,
            y: hamsterView.frame.maxY + 2,
            width: width,
            height: height
        )
    }

    private func resetPomodoroTimer() {
        pomodoroTimer?.invalidate()
        syncPomodoroSettingsFromUI()
        guard pomodoroEnabled else {
            pomodoroEndDate = nil
            pomodoroCountUpStartDate = nil
            pomodoroIsBreak = false
            clearPomodoroState()
            updatePomodoroCountdown()
            updatePomodoroFocusRecordLabel()
            return
        }

        if pomodoroTimerMode == .countUp {
            pomodoroIsBreak = false
            activeFocusMinutes = 25
            pomodoroEndDate = nil
            if pomodoroCountUpStartDate == nil {
                pomodoroCountUpStartDate = Date()
            }
            paused = true
            updateActionModePopup()
            setMood(.idle)
            if let title = linkedTodoTitle() {
                setBubbleMessage("阿念开始正计时，绑定「\(shortTodoTitle(title, limit: 18))」；每25分钟跑一圈。", priority: .pomodoro, hold: 9)
            } else {
                setBubbleMessage("阿念开始正计时：每25分钟跑一圈，点结束才会停。", priority: .pomodoro, hold: 9)
            }
            updatePomodoroCountdown()
            updatePomodoroFocusRecordLabel()
            persistPomodoroState()
            updatePomodoroModeControls()
            schedulePomodoroTickTimer()
            return
        }

        pomodoroIsBreak = false
        pomodoroCountUpStartDate = nil
        activeFocusMinutes = pomodoroFocusMinutes
        pomodoroEndDate = Date().addingTimeInterval(TimeInterval(pomodoroFocusMinutes * 60))
        paused = true
        updateActionModePopup()
        setMood(.idle)
        if let title = linkedTodoTitle() {
            setBubbleMessage("阿念启动番茄：\(pomodoroFocusMinutes)分钟绑定「\(shortTodoTitle(title, limit: 18))」。", priority: .pomodoro, hold: 8)
        } else {
            setBubbleMessage("阿念启动番茄钟：专注 \(pomodoroFocusMinutes) 分钟。", priority: .pomodoro, hold: 8)
        }
        updatePomodoroCountdown()
        updatePomodoroFocusRecordLabel()
        persistPomodoroState()
        updatePomodoroModeControls()
        schedulePomodoroTickTimer()
    }

    private func schedulePomodoroTickTimer() {
        pomodoroTimer?.invalidate()
        pomodoroTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.checkPomodoro()
        }
    }

    private func persistPomodoroState() {
        let defaults = UserDefaults.standard
        defaults.set(pomodoroEnabled, forKey: PetSettings.pomodoroEnabled)
        defaults.set(pomodoroIsBreak, forKey: PetSettings.pomodoroIsBreak)
        defaults.set(pomodoroTimerMode.rawValue, forKey: PetSettings.pomodoroTimerMode)
        defaults.set(pomodoroCountUpStartDate?.timeIntervalSince1970 ?? 0, forKey: PetSettings.pomodoroCountUpStartDate)
        defaults.set(activeFocusMinutes, forKey: PetSettings.pomodoroActiveFocusMinutes)
        defaults.set(pomodoroEndDate?.timeIntervalSince1970 ?? 0, forKey: PetSettings.pomodoroEndDate)
        defaults.set(pomodoroFocusMinutes, forKey: PetSettings.pomodoroFocusMinutes)
        defaults.set(pomodoroRestMinutes, forKey: PetSettings.pomodoroRestMinutes)
        defaults.set(pomodoroLinkedTodoID ?? "", forKey: PetSettings.pomodoroLinkedTodoID)
    }

    private func clearPomodoroState() {
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: PetSettings.pomodoroEnabled)
        defaults.set(false, forKey: PetSettings.pomodoroIsBreak)
        defaults.set(0, forKey: PetSettings.pomodoroEndDate)
        defaults.set(0, forKey: PetSettings.pomodoroCountUpStartDate)
        defaults.set(activeFocusMinutes, forKey: PetSettings.pomodoroActiveFocusMinutes)
    }

    private func checkPomodoro() {
        guard pomodoroEnabled else {
            updatePomodoroCountdown()
            return
        }
        if pomodoroTimerMode == .countUp {
            updatePomodoroCountdown()
            return
        }
        guard pomodoroEnabled, let endDate = pomodoroEndDate else {
            updatePomodoroCountdown()
            return
        }
        guard Date() >= endDate else {
            updatePomodoroCountdown()
            return
        }

        if pomodoroIsBreak {
            finishPomodoroSession()
        } else {
            let unlockedRewardLevel = recordPomodoroFocusCompletion()
            updatePetProgress(flash: true)
            syncPomodoroSettingsFromUI()
            pomodoroIsBreak = true
            pomodoroEndDate = Date().addingTimeInterval(TimeInterval(pomodoroRestMinutes * 60))
            paused = true
            if progressLaneActive {
                setProgressLaneActive(false)
            } else {
                setMood(.sleepy)
            }
            updateActionModePopup()
            persistPomodoroState()
            remind(title: "番茄钟休息", body: "阿念记功：专注完成，休息 \(pomodoroRestMinutes) 分钟。")
            if let unlockedRewardLevel {
                triggerPomodoroMonthlyReward(level: unlockedRewardLevel)
            } else {
                setBubbleMessage("阿念记功：今日第 \(pomodoroFocusSessions) 个番茄完成，盖爪印。", priority: .pomodoro, hold: 9)
                showSideRibbonBurst()
            }
        }
        updatePomodoroCountdown()
    }

    private func finishPomodoroSession() {
        pomodoroTimer?.invalidate()
        pomodoroTimer = nil
        pomodoroEnabled = false
        pomodoroIsBreak = false
        pomodoroEndDate = nil
        pomodoroCountUpStartDate = nil
        if progressLaneActive {
            setProgressLaneActive(false)
        }
        paused = true
        bubbleView.pomodoroCheck.state = .off
        clearPomodoroState()
        syncPomodoroSettingsFromUI()
        updatePomodoroCountdown()
        updateActionModePopup()
        refreshPomodoroTodoPopup()
        setMood(.idle)
        showSideRibbonBurst()
        setBubbleMessage("阿念陪你完成一组番茄，先停在这里，不自动重复。", priority: .pomodoro, hold: 9)
        remind(title: "番茄钟完成", body: "阿念报告：休息结束，这一组番茄完成啦。")
    }

    private func syncPomodoroSettingsFromUI() {
        pomodoroFocusMinutes = boundedMinute(bubbleView.focusMinutesField.stringValue, fallback: pomodoroFocusMinutes)
        pomodoroRestMinutes = boundedMinute(bubbleView.restMinutesField.stringValue, fallback: pomodoroRestMinutes)
        bubbleView.focusMinutesField.stringValue = "\(pomodoroFocusMinutes)"
        bubbleView.restMinutesField.stringValue = "\(pomodoroRestMinutes)"
        if pomodoroEnabled, pomodoroTimerMode == .countUp {
            bubbleView.pomodoroCheck.title = "⏱ 结束"
        } else {
            bubbleView.pomodoroCheck.title = pomodoroEnabled ? "🍅 停止" : "🍅 开始"
        }
        updatePomodoroModeControls()
        updatePomodoroFocusRecordLabel()
    }

    private func loadPomodoroFocusRecord() {
        resetPomodoroFocusRecordIfNeeded()
        let defaults = UserDefaults.standard
        pomodoroFocusSessions = defaults.integer(forKey: PetSettings.pomodoroFocusSessions)
        pomodoroFocusTotalMinutes = defaults.integer(forKey: PetSettings.pomodoroFocusTotalMinutes)
        pomodoroMonthFocusSessions = defaults.integer(forKey: PetSettings.pomodoroMonthFocusSessions)
        pomodoroMonthFocusTotalMinutes = defaults.integer(forKey: PetSettings.pomodoroMonthFocusTotalMinutes)
        pomodoroMonthRewardLevel = defaults.integer(forKey: PetSettings.pomodoroMonthRewardLevel)
        updatePomodoroFocusRecordLabel()
    }

    private func resetPomodoroFocusRecordIfNeeded() {
        let defaults = UserDefaults.standard
        let today = dayKey()
        if defaults.string(forKey: PetSettings.pomodoroFocusDay) != today {
            defaults.set(today, forKey: PetSettings.pomodoroFocusDay)
            defaults.set(0, forKey: PetSettings.pomodoroFocusSessions)
            defaults.set(0, forKey: PetSettings.pomodoroFocusTotalMinutes)
            pomodoroFocusSessions = 0
            pomodoroFocusTotalMinutes = 0
        }
        let month = monthKey()
        if defaults.string(forKey: PetSettings.pomodoroFocusMonth) != month {
            defaults.set(month, forKey: PetSettings.pomodoroFocusMonth)
            defaults.set(0, forKey: PetSettings.pomodoroMonthFocusSessions)
            defaults.set(0, forKey: PetSettings.pomodoroMonthFocusTotalMinutes)
            defaults.set(0, forKey: PetSettings.pomodoroMonthRewardLevel)
            pomodoroMonthFocusSessions = 0
            pomodoroMonthFocusTotalMinutes = 0
            pomodoroMonthRewardLevel = 0
        }
    }

    private func recordPomodoroFocusCompletion() -> Int? {
        resetPomodoroFocusRecordIfNeeded()
        pomodoroFocusSessions += 1
        pomodoroFocusTotalMinutes += activeFocusMinutes
        pomodoroMonthFocusSessions += 1
        pomodoroMonthFocusTotalMinutes += activeFocusMinutes
        recordLinkedTodoPomodoro(seconds: activeFocusMinutes * 60)
        let defaults = UserDefaults.standard
        defaults.set(dayKey(), forKey: PetSettings.pomodoroFocusDay)
        defaults.set(pomodoroFocusSessions, forKey: PetSettings.pomodoroFocusSessions)
        defaults.set(pomodoroFocusTotalMinutes, forKey: PetSettings.pomodoroFocusTotalMinutes)
        defaults.set(monthKey(), forKey: PetSettings.pomodoroFocusMonth)
        defaults.set(pomodoroMonthFocusSessions, forKey: PetSettings.pomodoroMonthFocusSessions)
        defaults.set(pomodoroMonthFocusTotalMinutes, forKey: PetSettings.pomodoroMonthFocusTotalMinutes)

        let newRewardLevel = rewardLevel(for: pomodoroMonthFocusTotalMinutes)
        if newRewardLevel > pomodoroMonthRewardLevel {
            pomodoroMonthRewardLevel = newRewardLevel
            defaults.set(pomodoroMonthRewardLevel, forKey: PetSettings.pomodoroMonthRewardLevel)
            updatePomodoroFocusRecordLabel()
            return newRewardLevel
        }
        updatePomodoroFocusRecordLabel()
        return nil
    }

    private func recordCountUpFocusCompletion(seconds: Int) -> Int? {
        guard seconds > 0 else { return nil }
        resetPomodoroFocusRecordIfNeeded()
        let elapsedMinutes = max(1, (seconds + 59) / 60)
        pomodoroFocusSessions += 1
        pomodoroFocusTotalMinutes += elapsedMinutes
        pomodoroMonthFocusSessions += 1
        pomodoroMonthFocusTotalMinutes += elapsedMinutes
        recordLinkedTodoPomodoro(seconds: seconds)

        let defaults = UserDefaults.standard
        defaults.set(dayKey(), forKey: PetSettings.pomodoroFocusDay)
        defaults.set(pomodoroFocusSessions, forKey: PetSettings.pomodoroFocusSessions)
        defaults.set(pomodoroFocusTotalMinutes, forKey: PetSettings.pomodoroFocusTotalMinutes)
        defaults.set(monthKey(), forKey: PetSettings.pomodoroFocusMonth)
        defaults.set(pomodoroMonthFocusSessions, forKey: PetSettings.pomodoroMonthFocusSessions)
        defaults.set(pomodoroMonthFocusTotalMinutes, forKey: PetSettings.pomodoroMonthFocusTotalMinutes)

        let newRewardLevel = rewardLevel(for: pomodoroMonthFocusTotalMinutes)
        if newRewardLevel > pomodoroMonthRewardLevel {
            pomodoroMonthRewardLevel = newRewardLevel
            defaults.set(pomodoroMonthRewardLevel, forKey: PetSettings.pomodoroMonthRewardLevel)
            updatePomodoroFocusRecordLabel()
            return newRewardLevel
        }
        updatePomodoroFocusRecordLabel()
        return nil
    }

    private func recordLinkedTodoPomodoro(seconds: Int) {
        guard seconds > 0,
              let linkedID = pomodoroLinkedTodoID,
              let index = todos.firstIndex(where: { !$0.done && todoID($0) == linkedID })
        else { return }

        todos[index].pomodoroSeconds = (todos[index].pomodoroSeconds ?? 0) + seconds
        saveTodos()
        if todosVisible {
            renderTodos()
        }
    }

    private func updatePomodoroFocusRecordLabel() {
        resetPomodoroFocusRecordIfNeeded()
        bubbleView.pomodoroRecordLabel.stringValue = "今日累计 \(pomodoroFocusSessions) 轮 · \(formatFocusDuration(pomodoroFocusTotalMinutes))"
        bubbleView.pomodoroMonthLabel.stringValue = monthlyPomodoroSummaryText()
    }

    private func rewardLevel(for totalMinutes: Int) -> Int {
        pomodoroRewardMilestones.filter { totalMinutes >= $0.minutes }.count
    }

    private func rewardMilestone(at level: Int) -> PomodoroReward? {
        guard level > 0, level <= pomodoroRewardMilestones.count else { return nil }
        return pomodoroRewardMilestones[level - 1]
    }

    private func monthlyPomodoroSummaryText() -> String {
        let total = formatFocusDuration(pomodoroMonthFocusTotalMinutes)
        let currentLevel = rewardLevel(for: pomodoroMonthFocusTotalMinutes)

        if currentLevel == 0 {
            let next = pomodoroRewardMilestones[0]
            let remaining = max(0, next.minutes - pomodoroMonthFocusTotalMinutes)
            return "本月 \(total) · 距\(next.name)还差 \(formatFocusDuration(remaining))"
        }

        guard currentLevel < pomodoroRewardMilestones.count else {
            let top = pomodoroRewardMilestones[pomodoroRewardMilestones.count - 1]
            return "本月 \(total) · \(top.name) \(top.emoji)"
        }

        let current = pomodoroRewardMilestones[currentLevel - 1]
        let next = pomodoroRewardMilestones[currentLevel]
        let remaining = max(0, next.minutes - pomodoroMonthFocusTotalMinutes)
        return "本月 \(total) · \(current.name) \(current.emoji) · 下阶 \(formatFocusDuration(remaining))"
    }

    private func formatFocusDuration(_ minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes)分钟"
        }
        let hours = minutes / 60
        let rest = minutes % 60
        if rest == 0 {
            return "\(hours)小时"
        }
        return "\(hours)小时\(rest)分钟"
    }

    private func triggerPomodoroMonthlyReward(level: Int) {
        guard let reward = rewardMilestone(at: level) else { return }
        let total = formatFocusDuration(pomodoroMonthFocusTotalMinutes)
        setBubbleMessage("阿念授勋：\(reward.name) \(reward.emoji) 解锁！\(reward.line)", priority: .pomodoro, hold: 12)
        showEdgeConfettiOverlay(style: .allEdgesEmoji, duration: 2.6, emojis: reward.stickerEmojis)
        celebrateCompletion(style: level >= 4 ? .big : .medium, triggerGlobalEffect: false)

        let content = UNMutableNotificationContent()
        content.title = "阿念月度奖励"
        content.body = "\(reward.name) \(reward.emoji) 解锁，本月已专注 \(total)。"
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func boundedMinute(_ rawValue: String, fallback: Int) -> Int {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = Int(trimmed) ?? fallback
        return min(max(value, 1), 180)
    }

    private func updatePomodoroCountdown() {
        guard pomodoroEnabled else {
            bubbleView.pomodoroCountdownLabel.stringValue = "番茄钟未开始"
            updatePetProgress()
            return
        }
        if pomodoroTimerMode == .countUp {
            let elapsed = pomodoroLaneText()
            bubbleView.pomodoroCountdownLabel.stringValue = elapsed
            updatePetProgress()
            refreshLinkedTodoTimeIfNeeded()
            updatePomodoroStatusTag(text: elapsed)
            return
        }
        guard let endDate = pomodoroEndDate else {
            bubbleView.pomodoroCountdownLabel.stringValue = "番茄钟未开始"
            updatePetProgress()
            return
        }
        let remaining = max(0, Int(ceil(endDate.timeIntervalSinceNow)))
        let minutes = remaining / 60
        let seconds = remaining % 60
        let phase = pomodoroIsBreak ? "休息中" : "专注中"
        let countdown = String(format: "%@ %02d:%02d", phase, minutes, seconds)
        bubbleView.pomodoroCountdownLabel.stringValue = countdown
        updatePetProgress()
        refreshLinkedTodoTimeIfNeeded()
        updatePomodoroStatusTag(text: countdown)
    }

    private func refreshLinkedTodoTimeIfNeeded() {
        guard todosVisible,
              pomodoroEnabled,
              !pomodoroIsBreak,
              pomodoroLinkedTodoID != nil
        else { return }
        renderTodos()
    }

    private func updatePomodoroStatusTag(text providedText: String? = nil) {
        guard pomodoroEnabled else { return }
        if progressLaneActive {
            refreshVisibleStatusTagIfNeeded(pomodoroLaneText())
            return
        }
        if pomodoroTimerMode == .countUp {
            showStatusTag(providedText ?? pomodoroLaneText(), duration: 0)
            return
        }
        if let providedText {
            showStatusTag(providedText, duration: 0)
            return
        }
        guard let endDate = pomodoroEndDate else {
            showStatusTag(pomodoroIsBreak ? "休息中" : "专注中", duration: 0)
            return
        }
        let remaining = max(0, Int(ceil(endDate.timeIntervalSinceNow)))
        let minutes = remaining / 60
        let seconds = remaining % 60
        let phase = pomodoroIsBreak ? "休息中" : "专注中"
        showStatusTag(String(format: "%@ %02d:%02d", phase, minutes, seconds), duration: 0)
    }

    private func resetCalendarTimer() {
        calendarTimer?.invalidate()
        requestCalendarAccess { [weak self] granted in
            guard let self else { return }
            if granted {
                self.checkCalendar()
            }
            self.requestRemindersAccess { [weak self] remindersGranted in
                guard let self, remindersGranted else { return }
                self.syncPendingReminderCompletions()
            }
        }
        calendarTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self, self.hasCalendarReadAccess() else { return }
            self.checkCalendar()
        }
    }

    private func requestCalendarAccess(completion: ((Bool) -> Void)? = nil) {
        let status = EKEventStore.authorizationStatus(for: .event)
        if hasCalendarReadAccess() {
            completion?(true)
            return
        }
        guard status == .notDetermined, !didRequestCalendarAccessThisLaunch else {
            completion?(false)
            return
        }
        didRequestCalendarAccessThisLaunch = true
        if #available(macOS 14.0, *) {
            eventStore.requestFullAccessToEvents { granted, _ in
                DispatchQueue.main.async {
                    completion?(granted)
                }
            }
        } else {
            eventStore.requestAccess(to: .event) { granted, _ in
                DispatchQueue.main.async {
                    completion?(granted)
                }
            }
        }
    }

    private func requestRemindersAccess(completion: ((Bool) -> Void)? = nil) {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        if hasReminderWriteAccess() {
            completion?(true)
            return
        }
        guard status == .notDetermined, !didRequestRemindersAccessThisLaunch else {
            completion?(false)
            return
        }
        didRequestRemindersAccessThisLaunch = true
        if #available(macOS 14.0, *) {
            eventStore.requestFullAccessToReminders { granted, _ in
                DispatchQueue.main.async {
                    completion?(granted)
                }
            }
        } else {
            eventStore.requestAccess(to: .reminder) { granted, _ in
                DispatchQueue.main.async {
                    completion?(granted)
                }
            }
        }
    }

    private func checkCalendar() {
        let start = Date()
        refreshTodayEvents()
        let end = start.addingTimeInterval(5 * 60)
        let calendars = eventStore.calendars(for: .event)
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: calendars)
        let events = eventStore.events(matching: predicate).sorted { $0.startDate < $1.startDate }
        guard let event = events.first else { return }
        let title = event.title ?? "Untitled"
        let startTime = event.startDate?.timeIntervalSince1970 ?? 0
        let key = "\(event.eventIdentifier ?? title)-\(startTime)"
        guard key != lastCalendarEventKey else { return }
        lastCalendarEventKey = key
        remind(title: "5 分钟内有日程", body: event.title)
    }

    private func refreshTodayEvents() {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return }
        let calendars = eventStore.calendars(for: .event)
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: calendars)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"

        let rawEvents = eventStore.events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }

        todayEvents = rawEvents.prefix(8).map { event in
            let time = event.startDate.map { formatter.string(from: $0) } ?? "--:--"
            return (time: time, title: event.title ?? "Untitled")
        }

        syncCalendarEventsIntoTodos(rawEvents, formatter: formatter)
        renderTodos()
    }

    private func syncCalendarEventsIntoTodos(_ events: [EKEvent], formatter: DateFormatter) {
        let today = dayKey()
        if lastCalendarSyncDay != today {
            lastCalendarSyncDay = today
            resetSuppressedCalendarTodosIfNeeded(for: today)
        }

        let suppressedKeys = suppressedCalendarTodoKeys()
        let existingKeys = Set(todos.compactMap { $0.calendarKey })
        var inserted = 0

        for event in events.prefix(8) {
            let key = calendarTodoKey(for: event)
            guard !existingKeys.contains(key), !suppressedKeys.contains(key) else { continue }
            let time = event.startDate.map { formatter.string(from: $0) } ?? "--:--"
            let rawTitle = (event.title ?? "Untitled").trimmingCharacters(in: .whitespacesAndNewlines)
            let title = "📅 \(time)  \(rawTitle.isEmpty ? "未命名日程" : rawTitle)"
            todos.append(TodoItem(title: title, done: false, calendarKey: key, id: UUID().uuidString))
            inserted += 1
        }

        if inserted > 0 {
            saveTodos()
            let message = inserted == 1 ? "阿念已收编 1 个今日日程。" : "阿念已收编 \(inserted) 个今日日程。"
            setBubbleMessage(message, priority: .todo, hold: 7)
        }
    }

    private func refreshTodayReminders(completion: (() -> Void)? = nil) {
        let calendars = eventStore.calendars(for: .reminder)
        let predicate = eventStore.predicateForReminders(in: calendars)
        eventStore.fetchReminders(matching: predicate) { [weak self] reminders in
            DispatchQueue.main.async {
                guard let self else {
                    completion?()
                    return
                }
                let calendar = Calendar.current
                let start = calendar.startOfDay(for: Date())
                guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
                    completion?()
                    return
                }
                let dueToday = (reminders ?? [])
                    .filter { reminder in
                        guard !reminder.isCompleted else { return false }
                        guard let components = reminder.dueDateComponents,
                              let dueDate = calendar.date(from: components) else { return false }
                        return dueDate >= start && dueDate < end
                    }
                    .sorted { lhs, rhs in
                        let lhsDate = lhs.dueDateComponents.flatMap { calendar.date(from: $0) } ?? Date.distantFuture
                        let rhsDate = rhs.dueDateComponents.flatMap { calendar.date(from: $0) } ?? Date.distantFuture
                        return lhsDate < rhsDate
                    }
                self.syncReminderItemsIntoTodos(dueToday)
                completion?()
            }
        }
    }

    private func syncReminderItemsIntoTodos(_ reminders: [EKReminder]) {
        let today = dayKey()
        if lastCalendarSyncDay != today {
            lastCalendarSyncDay = today
            resetSuppressedCalendarTodosIfNeeded(for: today)
        }

        let suppressedKeys = suppressedCalendarTodoKeys()
        var existingKeys = Set(todos.compactMap { $0.calendarKey })
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        var inserted = 0

        for reminder in reminders.prefix(12) {
            let key = reminderTodoKey(for: reminder)
            guard !existingKeys.contains(key), !suppressedKeys.contains(key) else { continue }
            let rawTitle = (reminder.title ?? "未命名提醒").trimmingCharacters(in: .whitespacesAndNewlines)
            let dueDate = reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
            let title: String
            if let dueDate {
                title = "📝 \(formatter.string(from: dueDate))  \(rawTitle.isEmpty ? "未命名提醒" : rawTitle)"
            } else {
                title = "📝 \(rawTitle.isEmpty ? "未命名提醒" : rawTitle)"
            }
            todos.append(TodoItem(title: title, done: false, calendarKey: key, id: UUID().uuidString))
            existingKeys.insert(key)
            inserted += 1
        }

        if inserted > 0 {
            saveTodos()
        }
    }

    private func reminderTodoKey(for reminder: EKReminder) -> String {
        let id = reminder.calendarItemIdentifier
        let due = reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
        let dueTime = Int(due?.timeIntervalSince1970 ?? 0)
        return "reminder#\(id)#\(dueTime)"
    }

    private func reminderIdentifier(for todo: TodoItem) -> String? {
        if let identifier = todo.syncedReminderID, !identifier.isEmpty {
            return identifier
        }
        guard let key = todo.calendarKey, key.hasPrefix("reminder#") else { return nil }
        let value = key.dropFirst("reminder#".count)
        guard let separator = value.lastIndex(of: "#") else { return nil }
        let identifier = value[..<separator]
        return identifier.isEmpty ? nil : String(identifier)
    }

    private func hasCalendarReadAccess() -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14.0, *) {
            return status == .fullAccess
        }
        return status.rawValue == 3
    }

    private func hasReminderWriteAccess() -> Bool {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        if #available(macOS 14.0, *) {
            return status == .fullAccess
        }
        return status.rawValue == 3
    }

    private func syncPendingReminderCompletions() {
        let pendingIDs = todos
            .filter { $0.done }
            .compactMap(todoID)
        pendingIDs.forEach { id in
            syncReminderCompletion(forTodoID: id, completed: true)
        }
    }

    private func syncReminderCompletion(forTodoID id: String, completed: Bool) {
        guard let index = todos.firstIndex(where: { todoID($0) == id }) else { return }

        if !hasReminderWriteAccess() {
            if !didShowReminderAccessUnavailableThisLaunch {
                didShowReminderAccessUnavailableThisLaunch = true
                setBubbleMessage("提醒事项权限未开启，阿念已先保留本地完成状态。", priority: .todo, hold: 9)
            }
            return
        }

        let todo = todos[index]
        if let identifier = reminderIdentifier(for: todo) {
            guard let reminder = eventStore.calendarItem(withIdentifier: identifier) as? EKReminder else {
                setBubbleMessage("阿念没找到对应的提醒事项，待办状态已保留。", priority: .todo, hold: 8)
                return
            }

            let previousDate = reminder.completionDate
            reminder.completionDate = completed ? (todo.completedAt ?? Date()) : nil
            do {
                try eventStore.save(reminder, commit: true)
            } catch {
                reminder.completionDate = previousDate
                setBubbleMessage("阿念没能同步到提醒事项，请检查提醒事项权限。", priority: .todo, hold: 9)
            }
            return
        }

        guard completed else { return }
        guard let calendar = eventStore.defaultCalendarForNewReminders() else {
            setBubbleMessage("阿念没找到可写入的提醒事项列表，待办状态已保留。", priority: .todo, hold: 9)
            return
        }

        let reminder = EKReminder(eventStore: eventStore)
        reminder.calendar = calendar
        reminder.title = todo.title
        let seconds = todoPomodoroSecondsForDisplay(todo)
        reminder.notes = seconds > 0
            ? "由阿念同步\n完成用时：\(formatTodoDuration(seconds))"
            : "由阿念同步"
        reminder.completionDate = todo.completedAt ?? Date()
        do {
            try eventStore.save(reminder, commit: true)
            todos[index].syncedReminderID = reminder.calendarItemIdentifier
            saveTodos()
            if todosVisible {
                renderTodos()
            }
        } catch {
            setBubbleMessage("阿念没能把完成事项写入提醒事项，请检查权限。", priority: .todo, hold: 9)
        }
    }

    private func calendarTodoKey(for event: EKEvent) -> String {
        let id = event.eventIdentifier ?? event.title ?? "event"
        let start = Int(event.startDate?.timeIntervalSince1970 ?? 0)
        return "\(id)#\(start)"
    }

    private func resetSuppressedCalendarTodosIfNeeded(for today: String = "") {
        let day = today.isEmpty ? dayKey() : today
        let defaults = UserDefaults.standard
        if defaults.string(forKey: PetSettings.calendarSyncSuppressedDay) != day {
            defaults.set(day, forKey: PetSettings.calendarSyncSuppressedDay)
            defaults.set([String](), forKey: PetSettings.suppressedCalendarTodoKeys)
        }
    }

    private func suppressedCalendarTodoKeys() -> Set<String> {
        resetSuppressedCalendarTodosIfNeeded()
        return Set(UserDefaults.standard.stringArray(forKey: PetSettings.suppressedCalendarTodoKeys) ?? [])
    }

    private func suppressCalendarTodosForToday(_ keys: [String]) {
        guard !keys.isEmpty else { return }
        resetSuppressedCalendarTodosIfNeeded()
        let defaults = UserDefaults.standard
        var suppressed = Set(defaults.stringArray(forKey: PetSettings.suppressedCalendarTodoKeys) ?? [])
        keys.forEach { suppressed.insert($0) }
        defaults.set(Array(suppressed), forKey: PetSettings.suppressedCalendarTodoKeys)
    }

    private func remind(title: String, body: String) {
        // Reminder reaction is deliberately finite; it returns to the current
        // resting state after the same ten-second hold as the message bubble.
        setMood(.reminding, hold: 10)
        let task = shortTodoTitle(body, limit: 24)
        let displayBody = body.hasPrefix("阿念")
            ? body
            : petLine("remind", task: task, fallback: "阿念提醒：{task}")
        setBubbleMessage(displayBody, priority: .reminder, hold: 10)
        updateBubbleSize()
        positionBubblePanelSmartly()
        bubblePanel?.orderFront(nil)
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = displayBody
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

}

extension NSColor {
    convenience init(hex: Int, alpha: CGFloat = 1) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        self.init(calibratedRed: red, green: green, blue: blue, alpha: alpha)
    }
}

extension NSRect {
    var area: CGFloat {
        guard !isNull && !isEmpty else { return 0 }
        return width * height
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var petController: PetWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.appearance = NSAppearance(named: .aqua)
        let controller = PetWindowController()
        petController = controller
        controller.showWindow(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
