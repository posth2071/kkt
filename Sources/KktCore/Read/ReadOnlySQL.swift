import Foundation

public enum ReadOnlySQL {
    public static func validate(_ sql: String) throws {
        typealias C = KktConstants.ReadSQL
        let characters = Array(sql)
        guard !characters.contains(C.nul) else { throw KktError.readOnlySQL }
        var index = KktConstants.zero
        var tokens: [String] = []
        var ended = false
        while index < characters.count {
            let character = characters[index]
            let next = index + KktConstants.one
            if character.isWhitespace {
                index = next
            } else if character == C.dash, next < characters.count, characters[next] == C.dash {
                index += C.pairLength
                while index < characters.count, !characters[index].isNewline { index += KktConstants.one }
            } else if character == C.slash, next < characters.count, characters[next] == C.star {
                index += C.pairLength
                while index + KktConstants.one < characters.count,
                      !(characters[index] == C.star && characters[index + KktConstants.one] == C.slash) {
                    index += KktConstants.one
                }
                guard index + KktConstants.one < characters.count else { throw KktError.readOnlySQL }
                index += C.pairLength
            } else {
                guard !ended else { throw KktError.readOnlySQL }
                if character == C.semicolon {
                    ended = true
                    index = next
                } else if C.quotes.contains(character) || character == C.bracketOpen {
                    guard !tokens.isEmpty else { throw KktError.readOnlySQL }
                    let close = character == C.bracketOpen ? C.bracketClose : character
                    index = next
                    var closed = false
                    while index < characters.count {
                        if characters[index] == close {
                            index += KktConstants.one
                            if close != C.bracketClose, index < characters.count, characters[index] == close {
                                index += KktConstants.one
                            } else {
                                closed = true
                                break
                            }
                        } else {
                            index += KktConstants.one
                        }
                    }
                    guard closed else { throw KktError.readOnlySQL }
                } else if character.isLetter || character == C.underscore {
                    let start = index
                    repeat { index += KktConstants.one }
                    while index < characters.count && (characters[index].isLetter || characters[index].isNumber
                                                        || characters[index] == C.underscore)
                    tokens.append(String(characters[start..<index]).uppercased())
                } else {
                    guard !tokens.isEmpty else { throw KktError.readOnlySQL }
                    index = next
                }
            }
        }
        guard let first = tokens.first, C.allowed.contains(first) else { throw KktError.readOnlySQL }
    }
}

extension KktConstants {
    enum ReadSQL {
        static let allowed: Set<String> = ["SELECT", "WITH", "PRAGMA"]
        static let nul: Character = "\0"
        static let dash: Character = "-"
        static let slash: Character = "/"
        static let star: Character = "*"
        static let semicolon: Character = ";"
        static let quotes: Set<Character> = ["'", "\"", "`"]
        static let bracketOpen: Character = "["
        static let bracketClose: Character = "]"
        static let underscore: Character = "_"
        static let pairLength = 2
    }
}
