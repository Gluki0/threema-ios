// DO NOT EDIT.
// swift-format-ignore-file
//
// Generated by the Swift generator plugin for the protocol buffer compiler.
// Source: md-d2d-join.proto
//
// For information on using the generated types, please see the documentation:
//   https://github.com/apple/swift-protobuf/

// ## Device Join Protocol
//
// This protocol specifies how to add a new device to an existing device
// family.
//
// ### Terminology
//
// - `ED`: Existing device
// - `ND`: New device to be added
// - `PSK`: Key derived from the passphrase chosen by the user
//
// ### Key Derivation
//
//     PSK = scrypt(
//       password=<passphrase>,
//       salt='3ma-mdev-join',
//       key-length=32,
//       parameters={r=8, N=65536, p=1}
//     )
//
// ### Blobs
//
// For binary data, the usual Blob scheme is being used by ED. However,
// instead of transferring Blob data via the Blob server, the data is
// transmitted in form of a `common.BlobData` message ahead of a message
// referencing that Blob by the associated Blob ID.
//
// ND is supposed to cache received `common.BlobData` until it can associate
// the data to a Blob referencing its ID. Once the rendezvous connection has
// been closed, any remaining cached `common.BlobData` can be discarded.
//
// ### Protocol Kickoff Flow
//
// ND or ED may choose to start the protocol. If ND starts the protocol it is
// _requesting to join the device family_. If ED starts the protocol it is
// _offering to join the device family_.
//
// Either way, the user must first be asked for a passphrase to encrypt the data
// to prevent the user from unintentionally adding a device to the device
// family. The passphrase must not be empty. From that passphrase, derive the
// Passphrase Key (PSK).
//
// If ED started the protocol:
//
// - `purpose` must be set to _offer to join the device family_.
// - ED takes the role of RID
// - ND takes the role of RRD
//
// If ND started the protocol:
//
// - `purpose` must be set to _request to join the device family_.
// - ND takes the role of RID
// - ED takes the role of RRD
//
// #### Connection Setup
//
// RID creates an `rendezvous.RendezvousInit` by following the Connection
// Rendezvous Protocol. It encrypts the created `rendezvous.RendezvousInit`
// with `PSK`, wraps it in a `url.DeviceFamilyJoinRequestOrOffer` and offers
// it in form of a URL or a QR code.
//
// RRD scans the QR code and parses the `url.DeviceFamilyJoinRequestOrOffer`.
// It will then ask the user for the passphrase to decrypt the contained
// `rendezvous.RendezvousInit`. Once decrypted, the enclosed
// `rendezvous.RendezvousInit` must be handled according to the Connection
// Rendezvous Protocol.
//
// Once the Connection Rendezvous Protocol has established at least one
// connection path, ND waits another 3s or until all connection paths have
// been established. Nomination is then done by ND following the Connection
// Rendezvous Protocol.
//
// Note that all messages on the nominated connection path must be end-to-end
// encrypted as defined by the Connection Rendezvous Protocol. All transmitted
// messages are to be wrapped in:
//
// - `TowardsExistingDeviceEnvelope` when sending from ND to ED, and
// - `TowardsNewDeviceEnvlope` when sending from ED to ND.
//
// #### Device Join Flow
//
// As soon as one of the connection paths has been nominated, ND sends a
// `Begin` message to start the device join process.
//
//     ED <------ Begin ------- ND   [1]
//
// ED will now send all `EssentialData` (with `common.BlobData` ahead).
//
//     ED -- common.BlobData -> ND   [0..N]
//     ED --- EssentialData --> ND   [1]
//
// Once ND successfully registered itself on the Mediator server, it sends a
// `Registered` message.
//
//     ED <---- Registered ---- ND   [1]
//
// ND may now either close the connection or leave it open to transition to
// the History Exchange Protocol. Any further messages ED receives from ND
// will transition into the History Exchange Protocol.

import Foundation
import SwiftProtobuf

// If the compiler emits an error on this type, it is because this file
// was generated by a version of the `protoc` Swift plug-in that is
// incompatible with the version of SwiftProtobuf to which you are linking.
// Please ensure that you are building against the same version of the API
// that was used to generate this file.
fileprivate struct _GeneratedWithProtocGenSwiftVersion: SwiftProtobuf.ProtobufAPIVersionCheck {
  struct _2: SwiftProtobuf.ProtobufAPIVersion_2 {}
  typealias Version = _2
}

/// Root message envelope for messages towards the existing device (ED).
struct Join_TowardsExistingDeviceEnvelope {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// The enveloped message
  var content: Join_TowardsExistingDeviceEnvelope.OneOf_Content? = nil

  var begin: Join_Begin {
    get {
      if case .begin(let v)? = content {return v}
      return Join_Begin()
    }
    set {content = .begin(newValue)}
  }

  var registered: Join_Registered {
    get {
      if case .registered(let v)? = content {return v}
      return Join_Registered()
    }
    set {content = .registered(newValue)}
  }

  var unknownFields = SwiftProtobuf.UnknownStorage()

  /// The enveloped message
  enum OneOf_Content: Equatable {
    case begin(Join_Begin)
    case registered(Join_Registered)

  #if !swift(>=4.1)
    static func ==(lhs: Join_TowardsExistingDeviceEnvelope.OneOf_Content, rhs: Join_TowardsExistingDeviceEnvelope.OneOf_Content) -> Bool {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch (lhs, rhs) {
      case (.begin, .begin): return {
        guard case .begin(let l) = lhs, case .begin(let r) = rhs else { preconditionFailure() }
        return l == r
      }()
      case (.registered, .registered): return {
        guard case .registered(let l) = lhs, case .registered(let r) = rhs else { preconditionFailure() }
        return l == r
      }()
      default: return false
      }
    }
  #endif
  }

  init() {}
}

/// Root message envelope for messages towards the new device (ND).
struct Join_TowardsNewDeviceEnvelope {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// The enveloped message
  var content: Join_TowardsNewDeviceEnvelope.OneOf_Content? = nil

  var blobData: Common_BlobData {
    get {
      if case .blobData(let v)? = content {return v}
      return Common_BlobData()
    }
    set {content = .blobData(newValue)}
  }

  var essentialData: Join_EssentialData {
    get {
      if case .essentialData(let v)? = content {return v}
      return Join_EssentialData()
    }
    set {content = .essentialData(newValue)}
  }

  var unknownFields = SwiftProtobuf.UnknownStorage()

  /// The enveloped message
  enum OneOf_Content: Equatable {
    case blobData(Common_BlobData)
    case essentialData(Join_EssentialData)

  #if !swift(>=4.1)
    static func ==(lhs: Join_TowardsNewDeviceEnvelope.OneOf_Content, rhs: Join_TowardsNewDeviceEnvelope.OneOf_Content) -> Bool {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch (lhs, rhs) {
      case (.blobData, .blobData): return {
        guard case .blobData(let l) = lhs, case .blobData(let r) = rhs else { preconditionFailure() }
        return l == r
      }()
      case (.essentialData, .essentialData): return {
        guard case .essentialData(let l) = lhs, case .essentialData(let r) = rhs else { preconditionFailure() }
        return l == r
      }()
      default: return false
      }
    }
  #endif
  }

  init() {}
}

/// Initial message sent by ND after a connection has been established.
///
/// When receiving this message:
///
/// 1. If `Begin` has been received before, close the connection and abort
///    these steps.
/// 2. Begin a transaction with scope `NEW_DEVICE_SYNC` on the D2M connection.
///    This transaction is to be held until the connection to ND drops or until
///    a `Registered` message was received. While the transaction is being
///    held, no `Reflected` and no end-to-end encrypted message coming from the
///    chat server is allowed to be processed! If the D2M connection is lost,
///    the established connection must also be closed, aborting any running
///    steps.
/// 3. Gather all data necessary to create `EssentialData`. Any Blobs must now
///    be sent in form of `common.BlobData` messages.
/// 4. Send the gathered `EssentialData` to ND.
struct Join_Begin {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}
}

/// Essential data ND needs to be able to participate in the device family.
///
/// When receiving this message:
///
/// 1. If `EssentialData` has been received before, close the connection and
///    abort these steps.
/// 2. If any Blob ID is missing from the previously received set of
///    `common.BlobData`, close the connection and abort these steps.
/// 3. Store the data in the device's database.
/// 4. Generate a random Mediator Device ID and a random CSP Device ID and
///    store both in the device's database.
/// 5. Establish a D2M connection by connecting to the provided mediator
///    server.
/// 6. Wait until the `ServerInfo` has been received on the D2M connection.
///    Validate that the provided `DeviceSlotState` is `NEW`. Otherwise, close
///    both the D2M connection (normally) and the connection to ED and
///    abort these steps.
/// 7. Send a `Registered` message to ED.
/// 8. Ask the user whether conversation history data should be requested from
///    ND:
///    1. If the user wants to request conversation history data from ED, leave
///       the connection running and start the History Exchange Protocol. Abort
///       these steps.
///    2. If the user does not want to request conversation history data, wait
///       until all buffered data on the connection has been written. Then,
///       close the connection.
struct Join_EssentialData {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  var mediatorServer: Join_EssentialData.MediatorServer {
    get {return _storage._mediatorServer ?? Join_EssentialData.MediatorServer()}
    set {_uniqueStorage()._mediatorServer = newValue}
  }
  /// Returns true if `mediatorServer` has been explicitly set.
  var hasMediatorServer: Bool {return _storage._mediatorServer != nil}
  /// Clears the value of `mediatorServer`. Subsequent reads from it will return its default value.
  mutating func clearMediatorServer() {_uniqueStorage()._mediatorServer = nil}

  /// The private key associated with the Threema ID
  var privateKey: Data {
    get {return _storage._privateKey}
    set {_uniqueStorage()._privateKey = newValue}
  }

  /// The user's profile
  var userProfile: Sync_UserProfile {
    get {return _storage._userProfile ?? Sync_UserProfile()}
    set {_uniqueStorage()._userProfile = newValue}
  }
  /// Returns true if `userProfile` has been explicitly set.
  var hasUserProfile: Bool {return _storage._userProfile != nil}
  /// Clears the value of `userProfile`. Subsequent reads from it will return its default value.
  mutating func clearUserProfile() {_uniqueStorage()._userProfile = nil}

  /// Shared settings
  var settings: Sync_Settings {
    get {return _storage._settings ?? Sync_Settings()}
    set {_uniqueStorage()._settings = newValue}
  }
  /// Returns true if `settings` has been explicitly set.
  var hasSettings: Bool {return _storage._settings != nil}
  /// Clears the value of `settings`. Subsequent reads from it will return its default value.
  mutating func clearSettings() {_uniqueStorage()._settings = nil}

  /// Contacts
  var contacts: [Sync_Contact] {
    get {return _storage._contacts}
    set {_uniqueStorage()._contacts = newValue}
  }

  /// Groups
  var groups: [Sync_Group] {
    get {return _storage._groups}
    set {_uniqueStorage()._groups = newValue}
  }

  /// Distribution lists
  var distributionLists: [Sync_DistributionList] {
    get {return _storage._distributionLists}
    set {_uniqueStorage()._distributionLists = newValue}
  }

  var unknownFields = SwiftProtobuf.UnknownStorage()

  /// Mediator server public key and address
  struct MediatorServer {
    // SwiftProtobuf.Message conformance is added in an extension below. See the
    // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
    // methods supported on all messages.

    /// Public key of the server
    var publicKey: Data = Data()

    /// Server address
    var address: Join_EssentialData.MediatorServer.OneOf_Address? = nil

    /// Hostname of the WebSocket server
    var webSocketHostname: String {
      get {
        if case .webSocketHostname(let v)? = address {return v}
        return String()
      }
      set {address = .webSocketHostname(newValue)}
    }

    var unknownFields = SwiftProtobuf.UnknownStorage()

    /// Server address
    enum OneOf_Address: Equatable {
      /// Hostname of the WebSocket server
      case webSocketHostname(String)

    #if !swift(>=4.1)
      static func ==(lhs: Join_EssentialData.MediatorServer.OneOf_Address, rhs: Join_EssentialData.MediatorServer.OneOf_Address) -> Bool {
        // The use of inline closures is to circumvent an issue where the compiler
        // allocates stack space for every case branch when no optimizations are
        // enabled. https://github.com/apple/swift-protobuf/issues/1034
        switch (lhs, rhs) {
        case (.webSocketHostname, .webSocketHostname): return {
          guard case .webSocketHostname(let l) = lhs, case .webSocketHostname(let r) = rhs else { preconditionFailure() }
          return l == r
        }()
        }
      }
    #endif
    }

    init() {}
  }

  init() {}

  fileprivate var _storage = _StorageClass.defaultInstance
}

/// Lets ED know that ND has received all essential data and successfully
/// registered itself on the mediator server.
///
/// When receiving this message:
///
/// 1. Release the transaction on the D2M connection. From this point on,
///    processing `Reflected` and end-to-end encrypted message coming from the
///    chat server is allowed again.
/// 2. Wait for ND to either close the connection or for ND to request
///    conversation history data. Any further messages from ND will move into
///    the History Exchange Protocol.
struct Join_Registered {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}
}

// MARK: - Code below here is support for the SwiftProtobuf runtime.

fileprivate let _protobuf_package = "join"

extension Join_TowardsExistingDeviceEnvelope: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".TowardsExistingDeviceEnvelope"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "begin"),
    2: .same(proto: "registered"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try {
        var v: Join_Begin?
        var hadOneofValue = false
        if let current = self.content {
          hadOneofValue = true
          if case .begin(let m) = current {v = m}
        }
        try decoder.decodeSingularMessageField(value: &v)
        if let v = v {
          if hadOneofValue {try decoder.handleConflictingOneOf()}
          self.content = .begin(v)
        }
      }()
      case 2: try {
        var v: Join_Registered?
        var hadOneofValue = false
        if let current = self.content {
          hadOneofValue = true
          if case .registered(let m) = current {v = m}
        }
        try decoder.decodeSingularMessageField(value: &v)
        if let v = v {
          if hadOneofValue {try decoder.handleConflictingOneOf()}
          self.content = .registered(v)
        }
      }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    // The use of inline closures is to circumvent an issue where the compiler
    // allocates stack space for every case branch when no optimizations are
    // enabled. https://github.com/apple/swift-protobuf/issues/1034
    switch self.content {
    case .begin?: try {
      guard case .begin(let v)? = self.content else { preconditionFailure() }
      try visitor.visitSingularMessageField(value: v, fieldNumber: 1)
    }()
    case .registered?: try {
      guard case .registered(let v)? = self.content else { preconditionFailure() }
      try visitor.visitSingularMessageField(value: v, fieldNumber: 2)
    }()
    case nil: break
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Join_TowardsExistingDeviceEnvelope, rhs: Join_TowardsExistingDeviceEnvelope) -> Bool {
    if lhs.content != rhs.content {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Join_TowardsNewDeviceEnvelope: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".TowardsNewDeviceEnvelope"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "blob_data"),
    2: .standard(proto: "essential_data"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try {
        var v: Common_BlobData?
        var hadOneofValue = false
        if let current = self.content {
          hadOneofValue = true
          if case .blobData(let m) = current {v = m}
        }
        try decoder.decodeSingularMessageField(value: &v)
        if let v = v {
          if hadOneofValue {try decoder.handleConflictingOneOf()}
          self.content = .blobData(v)
        }
      }()
      case 2: try {
        var v: Join_EssentialData?
        var hadOneofValue = false
        if let current = self.content {
          hadOneofValue = true
          if case .essentialData(let m) = current {v = m}
        }
        try decoder.decodeSingularMessageField(value: &v)
        if let v = v {
          if hadOneofValue {try decoder.handleConflictingOneOf()}
          self.content = .essentialData(v)
        }
      }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    // The use of inline closures is to circumvent an issue where the compiler
    // allocates stack space for every case branch when no optimizations are
    // enabled. https://github.com/apple/swift-protobuf/issues/1034
    switch self.content {
    case .blobData?: try {
      guard case .blobData(let v)? = self.content else { preconditionFailure() }
      try visitor.visitSingularMessageField(value: v, fieldNumber: 1)
    }()
    case .essentialData?: try {
      guard case .essentialData(let v)? = self.content else { preconditionFailure() }
      try visitor.visitSingularMessageField(value: v, fieldNumber: 2)
    }()
    case nil: break
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Join_TowardsNewDeviceEnvelope, rhs: Join_TowardsNewDeviceEnvelope) -> Bool {
    if lhs.content != rhs.content {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Join_Begin: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".Begin"
  static let _protobuf_nameMap = SwiftProtobuf._NameMap()

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let _ = try decoder.nextFieldNumber() {
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Join_Begin, rhs: Join_Begin) -> Bool {
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Join_EssentialData: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".EssentialData"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "mediator_server"),
    2: .standard(proto: "private_key"),
    3: .standard(proto: "user_profile"),
    4: .same(proto: "settings"),
    5: .same(proto: "contacts"),
    6: .same(proto: "groups"),
    7: .standard(proto: "distribution_lists"),
  ]

  fileprivate class _StorageClass {
    var _mediatorServer: Join_EssentialData.MediatorServer? = nil
    var _privateKey: Data = Data()
    var _userProfile: Sync_UserProfile? = nil
    var _settings: Sync_Settings? = nil
    var _contacts: [Sync_Contact] = []
    var _groups: [Sync_Group] = []
    var _distributionLists: [Sync_DistributionList] = []

    static let defaultInstance = _StorageClass()

    private init() {}

    init(copying source: _StorageClass) {
      _mediatorServer = source._mediatorServer
      _privateKey = source._privateKey
      _userProfile = source._userProfile
      _settings = source._settings
      _contacts = source._contacts
      _groups = source._groups
      _distributionLists = source._distributionLists
    }
  }

  fileprivate mutating func _uniqueStorage() -> _StorageClass {
    if !isKnownUniquelyReferenced(&_storage) {
      _storage = _StorageClass(copying: _storage)
    }
    return _storage
  }

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    _ = _uniqueStorage()
    try withExtendedLifetime(_storage) { (_storage: _StorageClass) in
      while let fieldNumber = try decoder.nextFieldNumber() {
        // The use of inline closures is to circumvent an issue where the compiler
        // allocates stack space for every case branch when no optimizations are
        // enabled. https://github.com/apple/swift-protobuf/issues/1034
        switch fieldNumber {
        case 1: try { try decoder.decodeSingularMessageField(value: &_storage._mediatorServer) }()
        case 2: try { try decoder.decodeSingularBytesField(value: &_storage._privateKey) }()
        case 3: try { try decoder.decodeSingularMessageField(value: &_storage._userProfile) }()
        case 4: try { try decoder.decodeSingularMessageField(value: &_storage._settings) }()
        case 5: try { try decoder.decodeRepeatedMessageField(value: &_storage._contacts) }()
        case 6: try { try decoder.decodeRepeatedMessageField(value: &_storage._groups) }()
        case 7: try { try decoder.decodeRepeatedMessageField(value: &_storage._distributionLists) }()
        default: break
        }
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try withExtendedLifetime(_storage) { (_storage: _StorageClass) in
      if let v = _storage._mediatorServer {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 1)
      }
      if !_storage._privateKey.isEmpty {
        try visitor.visitSingularBytesField(value: _storage._privateKey, fieldNumber: 2)
      }
      if let v = _storage._userProfile {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 3)
      }
      if let v = _storage._settings {
        try visitor.visitSingularMessageField(value: v, fieldNumber: 4)
      }
      if !_storage._contacts.isEmpty {
        try visitor.visitRepeatedMessageField(value: _storage._contacts, fieldNumber: 5)
      }
      if !_storage._groups.isEmpty {
        try visitor.visitRepeatedMessageField(value: _storage._groups, fieldNumber: 6)
      }
      if !_storage._distributionLists.isEmpty {
        try visitor.visitRepeatedMessageField(value: _storage._distributionLists, fieldNumber: 7)
      }
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Join_EssentialData, rhs: Join_EssentialData) -> Bool {
    if lhs._storage !== rhs._storage {
      let storagesAreEqual: Bool = withExtendedLifetime((lhs._storage, rhs._storage)) { (_args: (_StorageClass, _StorageClass)) in
        let _storage = _args.0
        let rhs_storage = _args.1
        if _storage._mediatorServer != rhs_storage._mediatorServer {return false}
        if _storage._privateKey != rhs_storage._privateKey {return false}
        if _storage._userProfile != rhs_storage._userProfile {return false}
        if _storage._settings != rhs_storage._settings {return false}
        if _storage._contacts != rhs_storage._contacts {return false}
        if _storage._groups != rhs_storage._groups {return false}
        if _storage._distributionLists != rhs_storage._distributionLists {return false}
        return true
      }
      if !storagesAreEqual {return false}
    }
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Join_EssentialData.MediatorServer: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = Join_EssentialData.protoMessageName + ".MediatorServer"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "public_key"),
    2: .standard(proto: "web_socket_hostname"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularBytesField(value: &self.publicKey) }()
      case 2: try {
        var v: String?
        try decoder.decodeSingularStringField(value: &v)
        if let v = v {
          if self.address != nil {try decoder.handleConflictingOneOf()}
          self.address = .webSocketHostname(v)
        }
      }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if !self.publicKey.isEmpty {
      try visitor.visitSingularBytesField(value: self.publicKey, fieldNumber: 1)
    }
    if case .webSocketHostname(let v)? = self.address {
      try visitor.visitSingularStringField(value: v, fieldNumber: 2)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Join_EssentialData.MediatorServer, rhs: Join_EssentialData.MediatorServer) -> Bool {
    if lhs.publicKey != rhs.publicKey {return false}
    if lhs.address != rhs.address {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Join_Registered: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".Registered"
  static let _protobuf_nameMap = SwiftProtobuf._NameMap()

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let _ = try decoder.nextFieldNumber() {
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: Join_Registered, rhs: Join_Registered) -> Bool {
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}