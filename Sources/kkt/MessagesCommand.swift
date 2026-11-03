import ArgumentParser
import KktCore

struct MessagesCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: KktConstants.Read.messagesCommand)

    @Option(name: .customLong(KktConstants.Read.chatIdOption))
    var chatId: Int64?

    @Option(name: .customLong(KktConstants.Read.chatOption))
    var chat: String?

    @Option(name: .customLong(KktConstants.Read.sinceOption))
    var since: String?

    @Option(name: .customLong(KktConstants.Read.limitOption))
    var limit: Int = KktConstants.Read.defaultLimit

    @Flag(name: .customLong(KktConstants.Read.jsonOption))
    var json = false

    func validate() throws {
        guard (chatId != nil) != (chat != nil), chat?.isEmpty != true else {
            throw ValidationError(KktConstants.Read.invalidTarget)
        }
        try validateReadOptions(since: since, limit: limit)
    }

    func run() throws {
        let sinceDate = since.flatMap { ReadQueries.parseSince($0) }
        let result = try withReadDatabase { reader -> (ChatNameResolution?, [ReadMessage]) in
            if let chatId { return (nil, try reader.messages(chatId: chatId, since: sinceDate, limit: limit)) }
            guard let chat else { throw ValidationError(KktConstants.Read.invalidTarget) }
            let resolution = try reader.resolveChat(named: chat)
            guard let id = resolution.chatId else { return (resolution, []) }
            return (resolution, try reader.messages(chatId: id, since: sinceDate, limit: limit))
        }
        if let resolution = result.0, resolution.chatId == nil {
            if json { KktOutput.emit(resolution.candidates) }
            else { KktOutput.emitLine(TableOutput.candidates(resolution.candidates)) }
            throw ExitCode(resolution.exitCode)
        }
        if json { KktOutput.emit(result.1) }
        else { KktOutput.emitLine(TableOutput.messages(result.1.reversed())) }
    }
}
