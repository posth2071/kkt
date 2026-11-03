import ArgumentParser
import KktCore

struct SearchCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: KktConstants.Read.searchCommand)

    @Argument
    var text: String

    @Option(name: .customLong(KktConstants.Read.chatIdOption))
    var chatId: Int64?

    @Option(name: .customLong(KktConstants.Read.sinceOption))
    var since: String?

    @Option(name: .customLong(KktConstants.Read.limitOption))
    var limit: Int = KktConstants.Read.searchLimit

    @Flag(name: .customLong(KktConstants.Read.jsonOption))
    var json = false

    func validate() throws { try validateReadOptions(since: since, limit: limit) }

    func run() throws {
        let sinceDate = since.flatMap { ReadQueries.parseSince($0) }
        let messages = try withReadDatabase {
            try $0.search(text: text, chatId: chatId, since: sinceDate, limit: limit)
        }
        if json { KktOutput.emit(messages) }
        else { KktOutput.emitLine(TableOutput.messages(messages)) }
    }
}
