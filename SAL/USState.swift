import Foundation

enum USState: String, CaseIterable, Identifiable, Codable {
    case alabama = "AL", alaska = "AK", arizona = "AZ", arkansas = "AR"
    case california = "CA", colorado = "CO", connecticut = "CT", delaware = "DE"
    case districtOfColumbia = "DC", florida = "FL", georgia = "GA", hawaii = "HI"
    case idaho = "ID", illinois = "IL", indiana = "IN", iowa = "IA", kansas = "KS"
    case kentucky = "KY", louisiana = "LA", maine = "ME", maryland = "MD"
    case massachusetts = "MA", michigan = "MI", minnesota = "MN", mississippi = "MS"
    case missouri = "MO", montana = "MT", nebraska = "NE", nevada = "NV"
    case newHampshire = "NH", newJersey = "NJ", newMexico = "NM", newYork = "NY"
    case northCarolina = "NC", northDakota = "ND", ohio = "OH", oklahoma = "OK"
    case oregon = "OR", pennsylvania = "PA", rhodeIsland = "RI"
    case southCarolina = "SC", southDakota = "SD", tennessee = "TN", texas = "TX"
    case utah = "UT", vermont = "VT", virginia = "VA", washington = "WA"
    case westVirginia = "WV", wisconsin = "WI", wyoming = "WY"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .districtOfColumbia: return "District of Columbia"
        case .newHampshire: return "New Hampshire"
        case .newJersey: return "New Jersey"
        case .newMexico: return "New Mexico"
        case .newYork: return "New York"
        case .northCarolina: return "North Carolina"
        case .northDakota: return "North Dakota"
        case .rhodeIsland: return "Rhode Island"
        case .southCarolina: return "South Carolina"
        case .southDakota: return "South Dakota"
        case .westVirginia: return "West Virginia"
        default: return String(describing: self).capitalized
        }
    }

    static let sorted = allCases.sorted { $0.name < $1.name }

    static func resolve(codeOrName: String) -> USState? {
        let value = codeOrName.trimmingCharacters(in: .whitespacesAndNewlines)
        return USState(rawValue: value.uppercased())
            ?? allCases.first { $0.name.caseInsensitiveCompare(value) == .orderedSame }
    }
}
