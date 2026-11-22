import DisplayToggleCore
import Foundation

/// 영어 원문을 키로 쓴다. 번역이 없거나 번들 밖에서 실행하면 영어가 그대로 나온다.
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: NSLocalizedString(key, comment: ""), arguments: args)
}

extension DenyReason {
    var localized: String {
        switch self {
        case .displayNotFound: return L("Display not found")
        case .alreadyOff: return L("Already off")
        case .lastActiveDisplay: return L("Cannot turn off the last display")
        }
    }
}

extension ToggleWarning {
    var localized: String {
        switch self {
        case .layoutNotRestored: return L("Could not restore the resolution and arrangement of other displays")
        }
    }
}
