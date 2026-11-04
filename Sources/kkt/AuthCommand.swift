import ArgumentParser
import Foundation
import KktCore

struct AuthCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: KktConstants.authCommandName,
        abstract: KktConstants.authDescription
    )

    mutating func run() throws {
        do {
            var config = try KktConfig.load(environment: ProcessInfo.processInfo.environment)
            if config.userId == nil {
                guard let hash = DeviceInfo.activeAccountHash(),
                      let userId = ProgressIndicator.forTerminal().during(.checkingAccount, {
                          UserIdRecovery.recover(sha512Hex: hash, range: KktConstants.recoveryRange,
                                                 workers: ProcessInfo.processInfo.activeProcessorCount)
                      }) else {
                    throw KktError.notFound(KktConstants.userIdEnv)
                }
                config.userId = userId
            }
            let database = try KakaoDatabase.open(config: config)
            defer { database.close() }
            try KktConfig.save(config)
            KktOutput.emit(AuthResult(result: KktConstants.okResult, userId: config.userId,
                                      database: URL(fileURLWithPath: database.databasePath).lastPathComponent))
        } catch {
            KktOutput.emit(AuthFailure(result: KktConstants.failedResult,
                                       reason: (error as? KktError)?.code ?? KktError.invalidConfig.code))
            throw ExitCode.failure
        }
    }
}

private struct AuthResult: Encodable {
    let result: String
    let userId: Int?
    let database: String
}

private struct AuthFailure: Encodable {
    let result: String
    let reason: String
}
