import ArgumentParser
import Foundation
import KktCore

struct DoctorCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: KktConstants.Doctor.command, abstract: KktConstants.Doctor.description
    )

    @Flag(name: .customLong(KktConstants.Read.jsonOption))
    var json = false

    func run() throws {
        let config = try? KktConfig.load(environment: ProcessInfo.processInfo.environment)
        let executable = Bundle.main.executableURL?.path ?? CommandLine.arguments.first ?? KktConstants.Doctor.executableFallback
        let report = DoctorChecks(config: config, probes: .live(config: config)).run(executablePath: executable)
        if json { KktOutput.emit(report) }
        else { KktOutput.emitLine(report.humanOutput) }
        if report.exitCode != KktConstants.successExitCode { throw ExitCode(report.exitCode) }
    }
}
