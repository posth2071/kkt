import ApplicationServices
import Darwin
import Foundation

public struct SkyLightFocus {
    struct API {
        var windowId: (AXUIElement) -> UInt32?
        var processSerial: (pid_t) -> [UInt32]?
        var post: ([UInt32], [UInt8]) -> Bool
    }

    private typealias PostRecord = @convention(c) (UnsafeMutablePointer<UInt32>, UnsafeMutablePointer<UInt8>) -> Int32
    private typealias WindowLookup = @convention(c) (AXUIElement, UnsafeMutablePointer<UInt32>) -> Int32
    private typealias SerialLookup = @convention(c) (pid_t, UnsafeMutablePointer<UInt32>) -> Int32

    private let api: API?
    private let pid: (AXUIElement) -> pid_t?
    private let sleep: (TimeInterval) -> Void

    public init() {
        self.init(api: Self.liveAPI(), pid: { element in
            var pid: pid_t = .zero
            return AXUIElementGetPid(element, &pid) == .success ? pid : nil
        }, sleep: { Thread.sleep(forTimeInterval: $0) })
    }

    init(api: API?, pid: @escaping (AXUIElement) -> pid_t?, sleep: @escaping (TimeInterval) -> Void) {
        self.api = api
        self.pid = pid
        self.sleep = sleep
    }

    public static func isAvailable() -> Bool { liveAPI() != nil }

    public func acquire(window: AXUIElement) -> (() -> Void)? {
        guard let api, let pid = pid(window), let windowId = api.windowId(window),
              let serial = api.processSerial(pid) else { return nil }
        typealias C = KktConstants.SkyLight
        guard api.post(serial, Self.focusRecord(windowId: windowId, state: C.acquireState)) else { return nil }
        let release = { _ = api.post(serial, Self.focusRecord(windowId: windowId, state: C.releaseState)) }
        sleep(C.recordGap)
        for kind in C.keyKinds where !api.post(serial, Self.keyRecord(windowId: windowId, kind: kind)) {
            release()
            return nil
        }
        return release
    }

    static func focusRecord(windowId: UInt32, state: UInt8) -> [UInt8] {
        typealias C = KktConstants.SkyLight
        var record = baseRecord(windowId: windowId, kind: C.focusKind)
        record[C.focusStateOffset] = state
        return record
    }

    static func keyRecord(windowId: UInt32, kind: UInt8) -> [UInt8] {
        typealias C = KktConstants.SkyLight
        var record = baseRecord(windowId: windowId, kind: kind)
        record[C.keyFlagOffset] = C.keyFlag
        for index in C.keyMaskRange { record[index] = C.keyMask }
        return record
    }

    private static func baseRecord(windowId: UInt32, kind: UInt8) -> [UInt8] {
        typealias C = KktConstants.SkyLight
        var record = [UInt8](repeating: .zero, count: C.recordSize)
        record[C.sizeOffset] = UInt8(C.recordSize)
        record[C.kindOffset] = kind
        withUnsafeBytes(of: windowId.littleEndian) { bytes in
            for (offset, byte) in bytes.enumerated() { record[C.windowOffset + offset] = byte }
        }
        return record
    }

    private static func liveAPI() -> API? {
        typealias C = KktConstants.SkyLight
        let process = UnsafeMutableRawPointer(bitPattern: C.defaultHandle)
        guard let framework = dlopen(C.frameworkPath, RTLD_LAZY),
              let postSymbol = dlsym(framework, C.postSymbol),
              let windowSymbol = dlsym(process, C.windowSymbol),
              let serialSymbol = dlsym(process, C.serialSymbol) else { return nil }
        let postRecord = unsafeBitCast(postSymbol, to: PostRecord.self)
        let windowLookup = unsafeBitCast(windowSymbol, to: WindowLookup.self)
        let serialLookup = unsafeBitCast(serialSymbol, to: SerialLookup.self)
        return API(windowId: { window in
            var windowId: UInt32 = .zero
            return windowLookup(window, &windowId) == .zero && windowId != .zero ? windowId : nil
        }, processSerial: { pid in
            var serial = [UInt32](repeating: .zero, count: C.serialWords)
            return serialLookup(pid, &serial) == .zero ? serial : nil
        }, post: { serial, record in
            var serial = serial, record = record
            return postRecord(&serial, &record) == .zero
        })
    }
}

extension KktConstants {
    enum SkyLight {
        static let frameworkPath = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
        static let postSymbol = "SLPSPostEventRecordTo"
        static let windowSymbol = "_AXUIElementGetWindow"
        static let serialSymbol = "GetProcessForPID"
        static let defaultHandle = -2
        static let serialWords = 2
        static let recordSize = 0xf8
        static let sizeOffset = 0x04
        static let kindOffset = 0x08
        static let windowOffset = 0x3c
        static let focusStateOffset = 0x8a
        static let keyFlagOffset = 0x3a
        static let keyMaskRange = 0x20..<0x30
        static let focusKind: UInt8 = 0x0d
        static let acquireState: UInt8 = 1
        static let releaseState: UInt8 = 2
        static let keyKinds: [UInt8] = [1, 2]
        static let keyFlag: UInt8 = 0x10
        static let keyMask: UInt8 = 0xff
        static let recordGap: TimeInterval = 0.1
    }
}
