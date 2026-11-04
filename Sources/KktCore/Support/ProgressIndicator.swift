import Foundation

public enum ProgressStage: Equatable, Sendable {
    case preparing
    case openingRoom
    case pastingImages(Int)
    case sending
    case verifying
    case readingNotice
    case joining
    case handlingContact
    case checkingAccount

    public var label: String {
        switch self {
        case .preparing: KktConstants.Progress.preparing
        case .openingRoom: KktConstants.Progress.openingRoom
        case .pastingImages(let count):
            KktConstants.Progress.pastingImagesPrefix + String(count) + KktConstants.Progress.pastingImagesSuffix
        case .sending: KktConstants.Progress.sending
        case .verifying: KktConstants.Progress.verifying
        case .readingNotice: KktConstants.Progress.readingNotice
        case .joining: KktConstants.Progress.joining
        case .handlingContact: KktConstants.Progress.handlingContact
        case .checkingAccount: KktConstants.Progress.checkingAccount
        }
    }
}

/// Draws a one-line status on standard error. Standard output stays reserved for results.
public final class ProgressIndicator: @unchecked Sendable {
    public typealias Tick = @Sendable () -> Void
    public typealias Cancel = @Sendable () -> Void

    private let enabled: Bool
    private let write: @Sendable (String) -> Void
    private let schedule: @Sendable (@escaping Tick) -> Cancel
    private let lock = NSLock()
    private var label: String?
    private var frame = Int.zero
    private var visible = false
    private var cancel: Cancel?

    init(enabled: Bool, write: @escaping @Sendable (String) -> Void,
         schedule: @escaping @Sendable (@escaping Tick) -> Cancel) {
        self.enabled = enabled
        self.write = write
        self.schedule = schedule
    }

    public static func forTerminal(json: Bool = false,
                                   environment: [String: String] = ProcessInfo.processInfo.environment) -> ProgressIndicator {
        let terminal = isatty(STDERR_FILENO) == KktConstants.Progress.isTerminal
        return ProgressIndicator(enabled: isEnabled(stderrIsTerminal: terminal, environment: environment, json: json),
                                 write: { FileHandle.standardError.write(Data($0.utf8)) },
                                 schedule: timer(delay: KktConstants.Progress.firstDrawDelay,
                                                 interval: KktConstants.Progress.frameInterval))
    }

    static func isEnabled(stderrIsTerminal: Bool, environment: [String: String], json: Bool) -> Bool {
        stderrIsTerminal && !json
            && environment[KktConstants.Progress.termKey] != KktConstants.Progress.dumbTerm
            && environment[KktConstants.Progress.disableKey]?.isEmpty != false
    }

    static func timer(delay: TimeInterval, interval: TimeInterval) -> @Sendable (@escaping Tick) -> Cancel {
        { tick in
            let source = DispatchSource.makeTimerSource(queue: DispatchQueue(label: KktConstants.Progress.queueLabel))
            source.schedule(deadline: .now() + delay, repeating: interval)
            source.setEventHandler(handler: tick)
            source.resume()
            return { source.cancel() }
        }
    }

    public func update(_ stage: ProgressStage) {
        guard enabled else { return }
        lock.withLock {
            label = stage.label
            if visible { draw() }
            guard cancel == nil else { return }
            cancel = schedule { [weak self] in self?.tick() }
        }
    }

    public func stop() {
        guard enabled else { return }
        lock.withLock {
            cancel?()
            cancel = nil
            label = nil
            frame = .zero
            if visible { write(KktConstants.Progress.clearLine) }
            visible = false
        }
    }

    public func during<T>(_ stage: ProgressStage, _ body: () throws -> T) rethrows -> T {
        update(stage)
        defer { stop() }
        return try body()
    }

    private func tick() {
        lock.withLock {
            guard label != nil else { return }
            if visible { frame = (frame + KktConstants.Progress.frameStep) % KktConstants.Progress.frames.count }
            visible = true
            draw()
        }
    }

    private func draw() {
        guard let label else { return }
        write(KktConstants.Progress.clearLine + KktConstants.Progress.frames[frame]
            + KktConstants.Progress.separator + label)
    }
}

extension KktConstants {
    enum Progress {
        static let preparing = "준비 중…"
        static let openingRoom = "방 여는 중…"
        static let pastingImagesPrefix = "사진 붙여넣는 중… ("
        static let pastingImagesSuffix = "장)"
        static let sending = "전송 중…"
        static let verifying = "전송 확인 중…"
        static let readingNotice = "공지 화면 읽는 중…"
        static let joining = "참여 처리 중…"
        static let handlingContact = "프로필 카드 처리 중…"
        static let checkingAccount = "계정 확인 중…"
        static let clearLine = "\r\u{1B}[2K"
        static let separator = " "
        static let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
        static let frameStep = 1
        static let firstDrawDelay: TimeInterval = 0.5
        static let frameInterval: TimeInterval = 0.1
        static let isTerminal: Int32 = 1
        static let termKey = "TERM"
        static let dumbTerm = "dumb"
        static let disableKey = "KKT_NO_PROGRESS"
        static let queueLabel = "kkt.progress"
    }
}
