//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2019-2022 Threema GmbH
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License, version 3,
// as published by the Free Software Foundation.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

import Foundation
import ThreemaFramework

class MyIdentityStoreMock: NSObject, MyIdentityStoreProtocol {
    
    var pushFromName: String!
    
    var linkEmailPending = false
    
    var linkedEmail: String?
    
    var linkMobileNoPending = false
    
    var linkedMobileNo: String?
    
    var profilePicture: NSMutableDictionary?
    
    func encryptData(_ data: Data!, withNonce nonce: Data!, publicKey: Data!) -> Data! {
        NaClCrypto.shared()?.encryptData(data, withPublicKey: publicKey, signKey: secretKey, nonce: nonce)
    }
    
    func decryptData(_ data: Data!, withNonce nonce: Data!, publicKey _publicKey: Data!) -> Data! {
        NaClCrypto.shared()?.decryptData(data, withSecretKey: secretKey, signKey: _publicKey, nonce: nonce)
    }
    
    private let secretKey: Data!
    
    init(identity: String, secretKey: Data) {
        self.identity = identity
        self.secretKey = secretKey
    }

    override convenience init() {
        self.init(identity: "TESTERID", secretKey: Data(base64Encoded: "WAXm465d3CNnP1pf84RF0mYRgV/Umqwe/8Hun9ntTdQ=")!)
    }
    
    var identity: String
     
    func keySecret() -> Data! {
        secretKey
    }
    
    func isKeychainLocked() -> Bool {
        false
    }

    func updateConnectionRights() {
        // no-op
    }
    
    func isProvisioned() -> Bool {
        false
    }
}