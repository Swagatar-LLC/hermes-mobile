import Foundation

/// A blocking approval: the agent is waiting for the user to approve/deny a dangerous action
/// (e.g. a destructive shell command). Answered via `approval.respond`.
///
/// Wire shape verified against `hermes-agent` `tui_gateway/server.py::_approval_request_payload`
/// (gateway 0.21.6+764): `{request_id, command, description, choices, pattern_key(s), …}`. It
/// arrives as the `approval` server→client request, in `session.resume`'s `pending_approval`
/// snapshot, and (older agents) as an `approval.request` event.
///
/// **`request_id` is the approval queue entry's own id and is the ONLY safe binding.** The
/// server's per-session queue is FIFO, so a response without it resolves the oldest entry —
/// not necessarily the one on screen — and `all: true` resolves every queued entry blind.
/// Every response therefore carries `request_id` (see `canRespond`); a request without one is
/// displayed but cannot be answered from the phone. Every field is decoded leniently so a
/// partial payload still yields a card rather than silently degrading to `.unknown`.
/// Deliberately only `Equatable`: the card's view identity comes from the reducer's monotonic
/// `pendingInteractionToken`, never from the request's value — two back-to-back approvals can
/// be *equal* (an agent retrying the same command), which is exactly the pair a value-derived
/// id cannot tell apart.
public struct ApprovalRequest: Equatable, Sendable, Decodable {
  /// The command awaiting approval (shown verbatim in the card).
  public var command: String?
  /// Human-readable summary of what will happen (server's `description`).
  public var detail: String?
  /// The danger pattern that matched (server's `pattern_key`).
  public var patternKey: String?
  /// All matched danger patterns when several commands are batched together.
  public var patternKeys: [String]
  /// The queue entry's id; every response is bound to it.
  public var requestID: String?
  /// The decisions the server allows (`once`/`session`/`always`/`deny`); empty when not sent.
  public var choices: [String]

  enum CodingKeys: String, CodingKey {
    case command
    case detail = "description"
    case patternKey = "pattern_key"
    case patternKeys = "pattern_keys"
    case requestID = "request_id"
    case choices
  }

  public init(
    command: String? = nil,
    detail: String? = nil,
    patternKey: String? = nil,
    patternKeys: [String] = [],
    requestID: String? = nil,
    choices: [String] = []
  ) {
    self.command = command
    self.detail = detail
    self.patternKey = patternKey
    self.patternKeys = patternKeys
    self.requestID = requestID
    self.choices = choices
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    command = try c.decodeIfPresent(String.self, forKey: .command)
    detail = try c.decodeIfPresent(String.self, forKey: .detail)
    patternKey = try c.decodeIfPresent(String.self, forKey: .patternKey)
    patternKeys = try c.decodeIfPresent([String].self, forKey: .patternKeys) ?? []
    requestID = try c.decodeIfPresent(String.self, forKey: .requestID)
    choices = (try? c.decodeIfPresent([String].self, forKey: .choices)) ?? []
  }

  /// Whether a response can be bound to this request. Without an id there is nothing to bind
  /// to and the client must fail closed: no approve, no deny, nothing sent.
  public var canRespond: Bool { requestID?.isEmpty == false }

  /// An absent `choices` list means "not stated" (`?? true`), a present one is authoritative.
  private func allows(_ choice: String) -> Bool { choices.isEmpty || choices.contains(choice) }

  /// Whether the card may offer "Approve all in this session" (`choice: "session"`, which
  /// persists the matched danger pattern for the rest of the session). It is scoped to THIS
  /// request id — it no longer resolves the rest of the queue.
  public var offersSessionApproval: Bool {
    (command?.isEmpty == false || patternKey?.isEmpty == false || !patternKeys.isEmpty) && allows("session")
  }

  /// Approval needs a bound request AND the command itself: a pattern or description is not
  /// what the user is being asked to authorize.
  public var canApprove: Bool {
    canRespond && allows("once") && command?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
  }
}

/// Payload for a `clarify.request` event. `choices` is empty when the agent expects
/// free-text. Responded to via `clarify.respond`.
/// Shape not yet verified against a live request — to confirm in M2 (Task 10).
public struct ClarifyRequest: Equatable, Sendable, Decodable {
  public var requestID: String
  public var question: String
  public var choices: [String]

  enum CodingKeys: String, CodingKey {
    case requestID = "request_id"
    case question
    case choices
  }

  public init(requestID: String, question: String, choices: [String] = []) {
    self.requestID = requestID
    self.question = question
    self.choices = choices
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    requestID = try c.decode(String.self, forKey: .requestID)
    question = try c.decodeIfPresent(String.self, forKey: .question) ?? ""
    choices = try c.decodeIfPresent([String].self, forKey: .choices) ?? []
  }
}
