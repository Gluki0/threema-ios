//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2021-2023 Threema GmbH
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

import SwiftProtobuf
import XCTest
@testable import ThreemaFramework

class MediatorReflectedIncomingMessageProcessorTests: XCTestCase {
    private var dbMainCnx: DatabaseContext!
    private var dbBackgroundCnx: DatabaseContext!
    private var dbPreparer: DatabasePreparer!

    private var frameworkInjectorMock: BusinessInjectorMock!
    private var messageStoreMock: MessageStoreMock!

    override func setUpWithError() throws {
        // Necessary for ValidationLogger
        AppGroup.setGroupID("group.ch.threema") // THREEMA_GROUP_IDENTIFIER @"group.ch.threema"

        let (_, mainCnx, backgroundCnx) = DatabasePersistentContext.devNullContext()
        dbMainCnx = DatabaseContext(mainContext: mainCnx, backgroundContext: nil)
        dbBackgroundCnx = DatabaseContext(mainContext: mainCnx, backgroundContext: backgroundCnx)
        dbPreparer = DatabasePreparer(context: mainCnx)
    }

    func testProcessTextMessageThrowsContactNotFound() throws {
        let (frameworkInjectorMock, messageStoreMock) = setUpMocks(group: nil)

        let expectedAbstractMessage = BoxTextMessage()
        expectedAbstractMessage.fromIdentity = frameworkInjectorMock.myIdentityStore.identity
        expectedAbstractMessage.toIdentity = "ECHOECHO"
        expectedAbstractMessage.text = "Test text message"
        let expectedEnvelope = getEnvelopeForIncomingMessage(abstractMessage: expectedAbstractMessage)

        let processor = MediatorReflectedIncomingMessageProcessor(
            frameworkInjector: frameworkInjectorMock,
            messageStore: messageStoreMock,
            messageProcessorDelegate: MessageProcessorDelegateMock(),
            timestamp: Date(),
            maxBytesToDecrypt: 0,
            timeoutDownloadThumbnail: 0
        )

        XCTAssertThrowsError(
            try processor
                .process(incomingMessage: expectedEnvelope.incomingMessage, abstractMessage: expectedAbstractMessage)
        )
    }

    func testProcessTextMessage() throws {
        // Initialize test data and mocks
        dbPreparer.save {
            dbPreparer.createContact(
                publicKey: BytesUtility.generateRandomBytes(length: Int(32))!,
                identity: "ECHOECHO",
                verificationLevel: 0
            )
        }
        let (frameworkInjectorMock, messageStoreMock) = setUpMocks(group: nil)

        let expectedAbstractMessage = BoxTextMessage()
        expectedAbstractMessage.fromIdentity = "ECHOECHO"
        expectedAbstractMessage.toIdentity = frameworkInjectorMock.myIdentityStore.identity
        expectedAbstractMessage.text = "Test text message"
        let expectedEnvelope = getEnvelopeForIncomingMessage(abstractMessage: expectedAbstractMessage)

        let processor = MediatorReflectedIncomingMessageProcessor(
            frameworkInjector: frameworkInjectorMock,
            messageStore: messageStoreMock,
            messageProcessorDelegate: MessageProcessorDelegateMock(),
            timestamp: Date(),
            maxBytesToDecrypt: 0,
            timeoutDownloadThumbnail: 0
        )

        let expec = expectation(description: "process incoming message")
        var error: Error?
        try processor.process(
            incomingMessage: expectedEnvelope.incomingMessage,
            abstractMessage: expectedAbstractMessage
        )
        .ensure {
            expec.fulfill()
        }
        .catch { err in
            error = err
        }

        wait(for: [expec], timeout: 1)

        XCTAssertNil(error)
        XCTAssertEqual(1, messageStoreMock.saveTextMessageCalls.count)
        XCTAssertEqual(
            expectedAbstractMessage.messageID,
            messageStoreMock.saveTextMessageCalls.first?.textMessage.messageID
        )
        XCTAssertEqual(expectedAbstractMessage.text, messageStoreMock.saveTextMessageCalls.first?.textMessage.text)
        XCTAssertEqual(
            expectedAbstractMessage.fromIdentity,
            messageStoreMock.saveTextMessageCalls.first?.conversationIdentity
        )
    }

    func testProcessGroupTextMessageThrowsGroupNotFound() throws {
        let (frameworkInjectorMock, messageStoreMock) = setUpMocks(group: nil)

        let expectedAbstractMessage = GroupTextMessage()
        expectedAbstractMessage.groupID = BytesUtility.generateRandomBytes(length: ThreemaProtocol.groupIDLength)!
        expectedAbstractMessage.groupCreator = "MEMBER01"
        expectedAbstractMessage.fromIdentity = "MEMBER02"
        expectedAbstractMessage.toIdentity = frameworkInjectorMock.myIdentityStore.identity
        expectedAbstractMessage.text = "Test text message"
        let expectedEnvelope = getEnvelopeForIncomingMessage(abstractMessage: expectedAbstractMessage)

        let processor = MediatorReflectedIncomingMessageProcessor(
            frameworkInjector: frameworkInjectorMock,
            messageStore: messageStoreMock,
            messageProcessorDelegate: MessageProcessorDelegateMock(),
            timestamp: Date(),
            maxBytesToDecrypt: 0,
            timeoutDownloadThumbnail: 0
        )

        XCTAssertThrowsError(
            try processor.process(
                incomingMessage: expectedEnvelope.incomingMessage,
                abstractMessage: expectedAbstractMessage
            )
        )
    }

    func testProcessGroupTextMessageThrowsContactNotFound() throws {
        // Initialize test data and mocks
        let groupID = BytesUtility.generateRandomBytes(length: ThreemaProtocol.groupIDLength)!
        var group: Group!
        dbPreparer.save {
            let groupCreator = dbPreparer.createContact(
                publicKey: BytesUtility.generateRandomBytes(length: Int(32))!,
                identity: "MEMBER01",
                verificationLevel: 0
            )
            let conversation = dbPreparer
                .createConversation(marked: false, typing: false, unreadMessageCount: 0) { conversation in
                    conversation.groupID = groupID
                    conversation.contact = groupCreator
                }
            let groupEntity = dbPreparer.createGroupEntity(
                groupID: groupID,
                groupCreator: "MEMBER01"
            )

            group = Group(
                myIdentityStore: MyIdentityStoreMock(),
                userSettings: UserSettingsMock(),
                groupEntity: groupEntity,
                conversation: conversation,
                lastSyncRequest: nil
            )
        }
        let (
            frameworkInjectorMock,
            messageStoreMock
        ) = setUpMocks(group: group)

        let expectedAbstractMessage = GroupTextMessage()
        expectedAbstractMessage.groupID = groupID
        expectedAbstractMessage.groupCreator = "MEMBER01"
        expectedAbstractMessage.fromIdentity = "MEMBER02"
        expectedAbstractMessage.toIdentity = frameworkInjectorMock.myIdentityStore.identity
        expectedAbstractMessage.text = "Test text message"
        let expectedEnvelope = getEnvelopeForIncomingMessage(abstractMessage: expectedAbstractMessage)

        let processor = MediatorReflectedIncomingMessageProcessor(
            frameworkInjector: frameworkInjectorMock,
            messageStore: messageStoreMock,
            messageProcessorDelegate: MessageProcessorDelegateMock(),
            timestamp: Date(),
            maxBytesToDecrypt: 0,
            timeoutDownloadThumbnail: 0
        )

        XCTAssertThrowsError(
            try processor.process(
                incomingMessage: expectedEnvelope.incomingMessage,
                abstractMessage: expectedAbstractMessage
            )
        )
    }

    func testProcessGroupTextMessage() throws {
        // Initialize test data and mocks
        let groupID = BytesUtility.generateRandomBytes(length: ThreemaProtocol.groupIDLength)!
        var group: Group!
        dbPreparer.save {
            dbPreparer.createContact(
                publicKey: BytesUtility.generateRandomBytes(length: Int(32))!,
                identity: "MEMBER02",
                verificationLevel: 0
            )
            let groupCreator = dbPreparer.createContact(
                publicKey: BytesUtility.generateRandomBytes(length: Int(32))!,
                identity: "MEMBER01",
                verificationLevel: 0
            )
            let conversation = dbPreparer
                .createConversation(marked: false, typing: false, unreadMessageCount: 0) { conversation in
                    conversation.groupID = groupID
                    conversation.contact = groupCreator
                }
            let groupEntity = dbPreparer.createGroupEntity(
                groupID: groupID,
                groupCreator: "MEMBER01"
            )

            group = Group(
                myIdentityStore: MyIdentityStoreMock(),
                userSettings: UserSettingsMock(),
                groupEntity: groupEntity,
                conversation: conversation,
                lastSyncRequest: nil
            )
        }
        let (
            frameworkInjectorMock,
            messageStoreMock
        ) = setUpMocks(group: group)

        let expectedAbstractMessage = GroupTextMessage()
        expectedAbstractMessage.groupID = groupID
        expectedAbstractMessage.groupCreator = "MEMBER01"
        expectedAbstractMessage.fromIdentity = "MEMBER02"
        expectedAbstractMessage.toIdentity = frameworkInjectorMock.myIdentityStore.identity
        expectedAbstractMessage.text = "Test text message"
        let expectedEnvelope = getEnvelopeForIncomingMessage(abstractMessage: expectedAbstractMessage)

        let processor = MediatorReflectedIncomingMessageProcessor(
            frameworkInjector: frameworkInjectorMock,
            messageStore: messageStoreMock,
            messageProcessorDelegate: MessageProcessorDelegateMock(),
            timestamp: Date(),
            maxBytesToDecrypt: 0,
            timeoutDownloadThumbnail: 0
        )

        let expec = expectation(description: "process incoming message")
        var error: Error?
        try processor.process(
            incomingMessage: expectedEnvelope.incomingMessage,
            abstractMessage: expectedAbstractMessage
        )
        .ensure {
            expec.fulfill()
        }
        .catch { err in
            error = err
        }

        wait(for: [expec], timeout: 1)

        XCTAssertNil(error)
        XCTAssertEqual(0, messageStoreMock.saveTextMessageCalls.count)
        XCTAssertEqual(1, messageStoreMock.saveGroupTextMessageCalls.count)
        XCTAssertEqual(
            expectedAbstractMessage.messageID,
            messageStoreMock.saveGroupTextMessageCalls.first?.groupTextMessage.messageID
        )
        XCTAssertEqual(
            expectedAbstractMessage.text,
            messageStoreMock.saveGroupTextMessageCalls.first?.groupTextMessage.text
        )
        XCTAssertEqual(
            expectedAbstractMessage.fromIdentity,
            messageStoreMock.saveGroupTextMessageCalls.first?.senderIdentity
        )
    }

    private func getEnvelopeForIncomingMessage(abstractMessage: AbstractMessage) -> D2d_Envelope {
        let mediatorMessageProtocol = MediatorMessageProtocol(
            deviceGroupKeys: DeviceGroupKeys(
                dgpk: BytesUtility.generateRandomBytes(length: Int(kDeviceGroupKeyLen))!,
                dgrk: BytesUtility.generateRandomBytes(length: Int(kDeviceGroupKeyLen))!,
                dgdik: BytesUtility.generateRandomBytes(length: Int(kDeviceGroupKeyLen))!,
                dgsddk: BytesUtility.generateRandomBytes(length: Int(kDeviceGroupKeyLen))!,
                dgtsk: BytesUtility.generateRandomBytes(length: Int(kDeviceGroupKeyLen))!,
                deviceGroupIDFirstByteHex: "a1"
            )
        )
        return mediatorMessageProtocol.getEnvelopeForIncomingMessage(
            type: Int32(abstractMessage.type()),
            body: abstractMessage.body(),
            messageID: abstractMessage.messageID.convert(),
            senderIdentity: abstractMessage.fromIdentity,
            createdAt: abstractMessage.date
        )
    }

    private func setUpMocks(group: Group?)
        -> (frameworkInjectorMock: BusinessInjectorMock, messageStoreMock: MessageStoreMock) {

        if let group = group {
            let backgroundGroupManagerMock = GroupManagerMock()
            backgroundGroupManagerMock.getGroupReturns = group

            frameworkInjectorMock = BusinessInjectorMock(
                backgroundEntityManager: EntityManager(databaseContext: dbBackgroundCnx),
                backgroundGroupManager: backgroundGroupManagerMock,
                backgroundUnreadMessages: UnreadMessages(
                    entityManager: EntityManager(databaseContext: dbBackgroundCnx)
                ),
                contactStore: ContactStoreMock(),
                entityManager: EntityManager(databaseContext: dbMainCnx),
                groupManager: GroupManagerMock(),
                licenseStore: LicenseStore.shared(),
                messageSender: MessageSenderMock(),
                multiDeviceManager: MultiDeviceManagerMock(),
                myIdentityStore: MyIdentityStoreMock(),
                userSettings: UserSettingsMock(),
                serverConnector: ServerConnectorMock(),
                mediatorMessageProtocol: MediatorMessageProtocolMock(),
                messageProcessor: MessageProcessorMock()
            )
        }
        else {
            frameworkInjectorMock = BusinessInjectorMock(
                entityManager: EntityManager(databaseContext: dbMainCnx),
                backgroundEntityManager: EntityManager(databaseContext: dbBackgroundCnx)
            )
        }

        return (frameworkInjectorMock, MessageStoreMock())
    }
}
