import Foundation

// Synthesized Codable models use these concrete overloads for persisted string
// sets. Sets have no order; stable arrays let AgentDatabase recognize unchanged
// state. Ordinary arrays (journal, replay order, notifications) are untouched,
// and older unsorted arrays still decode through Set's standard Codable support.
extension KeyedEncodingContainer {
  /// Encodes membership in sorted order so equal string sets produce equal bytes.
  mutating func encode(_ value: Set<String>, forKey key: Key) throws {
    try encode(value.sorted(), forKey: key)
  }

  /// Omits absent sets and uses stable membership order for present sets.
  mutating func encodeIfPresent(_ value: Set<String>?, forKey key: Key) throws {
    if let value { try encode(value, forKey: key) }
  }
}
