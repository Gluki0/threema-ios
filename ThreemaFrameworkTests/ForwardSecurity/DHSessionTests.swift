//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2022-2023 Threema GmbH
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

import XCTest
@testable import ThreemaFramework

class DHSessionTests: XCTestCase {
    private var initiatorDHSession: DHSession!
    private var responderDHSession: DHSession!
    
    private var aliceIdentityStore: MyIdentityStoreMock!
    private var bobIdentityStore: MyIdentityStoreMock!
    
    override func setUp() {
        continueAfterFailure = false
        aliceIdentityStore = MyIdentityStoreMock(
            identity: "AAAAAAAA",
            secretKey: Data(base64Encoded: "2Hi7lA4boz9eLl0ozdeb2uKj2+i/wD2PUTRczwshp1Y=")!
        )
        bobIdentityStore = MyIdentityStoreMock(
            identity: "BBBBBBBB",
            secretKey: Data(base64Encoded: "WE2g/Mu8jeGHMUX0pqyCP+ypW6gCu2xEBKESOyqgbn0=")!
        )
    }
    
    private func createSessions() throws {
        // Alice is the initiator
        initiatorDHSession = DHSession(
            peerIdentity: bobIdentityStore.identity,
            peerPublicKey: bobIdentityStore.publicKey,
            identityStore: aliceIdentityStore
        )
        
        // Bob gets an init message from Alice with her ephemeral public key
        responderDHSession = try DHSession(
            id: initiatorDHSession.id,
            peerEphemeralPublicKey: initiatorDHSession.myEphemeralPublicKey,
            peerIdentity: aliceIdentityStore.identity,
            peerPublicKey: aliceIdentityStore.publicKey,
            identityStore: bobIdentityStore
        )
    }
    
    func test2DHKeyExchange() throws {
        try createSessions()
        
        // At this point, both parties should have the same 2DH chain keys
        XCTAssertNotNil(initiatorDHSession.myRatchet2DH)
        XCTAssertNotNil(responderDHSession.peerRatchet2DH)
        XCTAssertEqual(
            initiatorDHSession.myRatchet2DH!.currentEncryptionKey,
            responderDHSession.peerRatchet2DH!.currentEncryptionKey
        )
    }
    
    func test4DHKeyExchange() throws {
        try createSessions()
        
        // Now Bob sends his ephemeral public key back to Alice
        try initiatorDHSession.processAccept(
            peerEphemeralPublicKey: responderDHSession.myEphemeralPublicKey,
            peerPublicKey: bobIdentityStore.publicKey,
            identityStore: aliceIdentityStore
        )
        
        // At this point, both parties should have the same 4DH chain keys
        XCTAssertEqual(
            initiatorDHSession.myRatchet4DH!.currentEncryptionKey,
            responderDHSession.peerRatchet4DH!.currentEncryptionKey
        )
        
        // The keys should be different for both directions
        XCTAssertNotEqual(
            initiatorDHSession.myRatchet4DH!.currentEncryptionKey,
            responderDHSession.myRatchet4DH!.currentEncryptionKey
        )
        
        // Ensure that the private keys have been discarded
        XCTAssertNil(initiatorDHSession.myEphemeralPrivateKey)
        XCTAssertNil(responderDHSession.myEphemeralPrivateKey)
    }
    
    func testKDFRotation() throws {
        try test4DHKeyExchange()
        
        // Turn the 4DH ratchet a couple of times on both sides and ensure the keys match
        for _ in 1...3 {
            initiatorDHSession.myRatchet4DH!.turn()
            responderDHSession.peerRatchet4DH!.turn()
            
            XCTAssertEqual(
                initiatorDHSession.myRatchet4DH!.currentEncryptionKey,
                responderDHSession.peerRatchet4DH!.currentEncryptionKey
            )
            
            initiatorDHSession.peerRatchet4DH!.turn()
            responderDHSession.myRatchet4DH!.turn()
            
            XCTAssertEqual(
                initiatorDHSession.peerRatchet4DH!.currentEncryptionKey,
                responderDHSession.myRatchet4DH!.currentEncryptionKey
            )
        }
        
        // Turn the 4DH ratchet several times on one side and verify that the other side can catch up
        let myTurns: UInt64 = 3
        for _ in 1...myTurns {
            initiatorDHSession.myRatchet4DH!.turn()
        }
        let responderTurns = try responderDHSession.peerRatchet4DH!
            .turnUntil(targetCounterValue: initiatorDHSession.myRatchet4DH!.counter)
        XCTAssertEqual(myTurns, responderTurns)
        XCTAssertEqual(
            initiatorDHSession.myRatchet4DH!.currentEncryptionKey,
            responderDHSession.peerRatchet4DH!.currentEncryptionKey
        )
    }
}