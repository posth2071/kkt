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
}
