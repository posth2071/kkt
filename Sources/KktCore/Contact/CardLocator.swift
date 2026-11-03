import Foundation

public struct TextBox: Equatable, Sendable {
    public let text: String
    public let rect: CGRect

    public init(text: String, rect: CGRect) {
        self.text = text
        self.rect = rect
    }

    var center: CGPoint { CGPoint(x: rect.midX, y: rect.midY) }
}

public func locateCardButtons(boxes: [TextBox], nickname: String) -> (primary: CGPoint, label: String)? {
    let names = boxes.filter { $0.text == nickname }.sorted { $0.rect.minY > $1.rect.minY }
    for name in names {
        let below = boxes.filter {
            $0.rect.minY >= name.rect.maxY
                && $0.rect.minY - name.rect.maxY <= KktConstants.cardButtonMaxDY
        }
        let primary = below.filter {
            $0.text == KktConstants.cardLabelDirect || $0.text == KktConstants.cardLabelAdd
        }.sorted { $0.rect.minY < $1.rect.minY }
        for button in primary {
            guard let profile = below.first(where: {
                $0.text == KktConstants.cardLabelProfile && sameContactRow(button, $0)
            }) else { continue }
            let row = button.rect.union(profile.rect)
            guard row.minX <= name.rect.maxX, row.maxX >= name.rect.minX else { continue }
            let selected = button.text == KktConstants.cardLabelDirect ? button : profile
            return (selected.center, selected.text)
        }
    }
    return nil
}

public func locatePopoverButton(boxes: [TextBox], label: String) -> CGPoint? {
    guard !KktConstants.forbiddenLabels.contains(label),
          label == KktConstants.cardLabelAdd || label == KktConstants.cardLabelDirect else { return nil }
    let candidates = boxes.filter { candidate in
        candidate.text == label && !boxes.contains {
            $0.text == KktConstants.cardLabelProfile && sameContactRow(candidate, $0)
        }
    }
    return candidates.first?.center
}

func sameContactRow(_ lhs: TextBox, _ rhs: TextBox) -> Bool {
    abs(lhs.rect.midY - rhs.rect.midY) <= KktConstants.cardRowTolerance
}

func validateContactClick(_ point: CGPoint, label: String, boxes: [TextBox]) throws {
    let forbidden = KktConstants.forbiddenLabels.contains(label) || boxes.contains {
        KktConstants.forbiddenLabels.contains($0.text) && $0.rect.contains(point)
    }
    guard !forbidden else { throw KktError.automation(KktConstants.forbiddenLabelCode) }
    assert(!forbidden)
    guard boxes.contains(where: { $0.text == label && $0.rect.contains(point) }) else {
        throw KktError.automation(KktConstants.buttonNotFoundCode)
    }
}
