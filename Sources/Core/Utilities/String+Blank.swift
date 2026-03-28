import Foundation

extension String {
    func trimmed() -> String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isBlank: Bool {
        trimmed().isEmpty
    }

    var nilIfBlank: String? {
        let value = trimmed()
        return value.isEmpty ? nil : value
    }
}

extension Optional where Wrapped == String {
    var nilIfBlank: String? {
        guard let value = self?.trimmed() else {
            return nil
        }

        return value.isEmpty ? nil : value
    }
}
