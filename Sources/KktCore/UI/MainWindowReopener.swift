import Foundation

enum MainWindowReopener {
    static func find<Window>(
        windows: () -> [Window], isMainWindow: (Window) -> Bool, reopen: () throws -> Void,
        sleep: (TimeInterval) -> Void, clock: () -> Date, restoreFocus: () -> Void,
        selfActivated: () -> Bool = { true }
    ) throws -> (mainWindow: Window, windows: [Window]) {
        let current = windows()
        if let mainWindow = current.first(where: isMainWindow) { return (mainWindow, current) }
        do {
            try reopen()
            let deadline = clock().addingTimeInterval(KktConstants.mainWindowReopenTimeout)
            repeat {
                let reopened = windows()
                if let mainWindow = reopened.first(where: isMainWindow) {
                    let activationDeadline = clock().addingTimeInterval(KktConstants.mainWindowActivationWait)
                    while !selfActivated(), clock() < activationDeadline { sleep(KktConstants.mainWindowPoll) }
                    restoreFocus()
                    sleep(KktConstants.actionSettle)
                    return (mainWindow, reopened)
                }
                let remaining = deadline.timeIntervalSince(clock())
                guard remaining > KktConstants.zeroInterval else {
                    throw KktError.automation(KktConstants.automationCode)
                }
                sleep(min(KktConstants.mainWindowPoll, remaining))
            } while clock() <= deadline
            throw KktError.automation(KktConstants.automationCode)
        } catch {
            restoreFocus()
            throw error
        }
    }
}

