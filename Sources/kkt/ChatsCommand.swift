import ArgumentParser
import KktCore

struct ChatsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: KktConstants.Read.chatsCommand)

    @Option(name: .customLong(KktConstants.Read.limitOption))
    var limit: Int = KktConstants.Read.defaultLimit

    @Flag(name: .customLong(KktConstants.Read.jsonOption))
    var json = false

    func validate() throws {
        guard limit > .zero else { throw ValidationError(KktConstants.Read.invalidLimit) }
    }

    func run() throws {
        let chats = try withReadDatabase { try $0.chats(limit: limit) }
        if json { KktOutput.emit(chats) }
        else { KktOutput.emitLine(TableOutput.chats(chats)) }
    }
}
