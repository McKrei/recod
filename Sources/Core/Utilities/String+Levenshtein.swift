import Foundation

extension String {
    /// Computes the Levenshtein distance between two strings.
    /// This represents the minimum number of single-character edits (insertions, deletions, or substitutions)
    /// required to change one word into the other.
    func levenshteinDistance(to other: String) -> Int {
        let empty = [Int](repeating: 0, count: other.count + 1)
        var last = [Int](0...other.count)

        for (i, selfChar) in self.enumerated() {
            var current = [Int](repeating: 0, count: other.count + 1)
            current[0] = i + 1

            for (j, otherChar) in other.enumerated() {
                if selfChar == otherChar {
                    current[j + 1] = last[j]
                } else {
                    current[j + 1] = Swift.min(last[j], last[j + 1], current[j]) + 1
                }
            }
            last = current
        }
        return last.last ?? 0
    }
}
