import Foundation

// Synthesized Codable models use these concrete overloads for persisted string
// sets. Sets have no order; stable arrays let AgentDatabase recognize unchanged
// state. Ordinary arrays (journal, replay order, notifications) are untouched,
// and older unsorted arrays still decode through Set's standard Codable support.
extension KeyedEncodingContainer {
  mutating func encode(_ value: Set<String>, forKey key: Key) throws {
    try encode(value.sorted(), forKey: key)
  }

  mutating func encodeIfPresent(_ value: Set<String>?, forKey key: Key) throws {
    if let value { try encode(value, forKey: key) }
  }
}
