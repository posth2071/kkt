import ArgumentParser
import KktCore

@main
struct Kkt: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: KktConstants.commandName,
        abstract: KktConstants.commandDescription,
        subcommands: [AuthCommand.self, ServeCommand.self, SendCommand.self, JoinCommand.self, ContactCommand.self,
                      ChatsCommand.self, MessagesCommand.self, SearchCommand.self, QueryCommand.self, NoticeCommand.self,
                      DoctorCommand.self]
    )

    @Flag(name: .customLong(KktConstants.Version.option), help: ArgumentHelp(KktConstants.Version.help))
    var version = false

    func run() throws {
        guard version else { throw CleanExit.helpRequest(self) }
        KktOutput.emitLine(VersionReport.live().standardOutput())
    }
}
