//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2020-2022 Threema GmbH
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

class GroupManagerTests: XCTestCase {
    private var databaseCnx: DatabaseContext!
    private var databasePreparer: DatabasePreparer!
    
    private var ddLoggerMock: DDLoggerMock!
    
    private let groupPhotoSenderMock = GroupPhotoSenderMock()
    
    override func setUpWithError() throws {
        // Necessary for ValidationLogger
        AppGroup.setGroupID("group.ch.threema") // THREEMA_GROUP_IDENTIFIER @"group.ch.threema"
        
        let (_, mainCnx, _) = DatabasePersistentContext.devNullContext()
        databaseCnx = DatabaseContext(mainContext: mainCnx, backgroundContext: nil)
        databasePreparer = DatabasePreparer(context: mainCnx)

        ddLoggerMock = DDLoggerMock()
        DDTTYLogger.sharedInstance?.logFormatter = LogFormatterCustom()
        DDLog.add(ddLoggerMock)
    }

    override func tearDownWithError() throws {
        DDLog.remove(ddLoggerMock)
    }

    /// Spec: https://clients.pages.threema.dev/protocols/threema-protocols/structbuf/csp/#m:e2e:group-setup
    /// Section: When sending this message to all group members: 1.
    func testSendGroupSetupIamNotCreator() throws {
        let myIdentityStoreMock = MyIdentityStoreMock()
        let taskManagerMock = TaskManagerMock()

        let expectedGroupID: Data = BytesUtility.generateRandomBytes(length: ThreemaProtocol.groupIDLength)!
        let expectedGroupCreator = "MEMBER01"
        let expectedMembers: Set<String> = [myIdentityStoreMock.identity, "MEMBER02", "MEMBER03"]

        let groupManager = GroupManager(
            myIdentityStoreMock,
            ContactStoreMock(callOnCompletion: true),
            taskManagerMock,
            UserSettingsMock(),
            EntityManager(databaseContext: databaseCnx, myIdentityStore: myIdentityStoreMock),
            groupPhotoSenderMock
        )

        let expec = expectation(description: "Group create or update")

        var resultError: Error?
        var isErrorHandlerCalled = false

        groupManager.createOrUpdate(
            groupID: expectedGroupID,
            creator: expectedGroupCreator,
            members: expectedMembers,
            systemMessageDate: Date()
        )
        .done { _, _ in
            expec.fulfill()
            XCTFail("Error handler should be called")
        }
        .catch { error in
            resultError = error
            isErrorHandlerCalled = true
            expec.fulfill()
        }

        waitForExpectations(timeout: 1)

        let err = try XCTUnwrap(resultError as? GroupManager.GroupError)
        XCTAssertTrue(isErrorHandlerCalled)
        XCTAssertTrue(err == GroupManager.GroupError.notCreator)
        XCTAssertEqual(0, taskManagerMock.addedTasks.count)
    }
    
    /// Spec: https://clients.pages.threema.dev/protocols/threema-protocols/structbuf/csp/#m:e2e:group-setup
    /// Section: When sending this message to all group members: 2.
    func testSendGroupSetupIamCreator() throws {
        let myIdentityStoreMock = MyIdentityStoreMock()
        let contactStoreMock = ContactStoreMock(callOnCompletion: true)
        let taskManagerMock = TaskManagerMock()
        let userSettingsMock = UserSettingsMock()
        
        let expectedGroupID: Data = BytesUtility.generateRandomBytes(length: ThreemaProtocol.groupIDLength)!
        let expectedGroupCreator: String = myIdentityStoreMock.identity
        let expectedMembers: Set<String> = ["MEMBER01", "MEMBER02", "MEMBER03"]
        
        for member in expectedMembers {
            databasePreparer.createContact(
                publicKey: BytesUtility.generateRandomBytes(length: 32)!,
                identity: member,
                verificationLevel: 0
            )
        }
        
        let groupManager = GroupManager(
            myIdentityStoreMock,
            contactStoreMock,
            taskManagerMock,
            userSettingsMock,
            EntityManager(databaseContext: databaseCnx, myIdentityStore: myIdentityStoreMock),
            groupPhotoSenderMock
        )
        
        var resultGroup: Group?
        var resultNewMembers: Set<String>?
        
        let expec = expectation(description: "Group create or update")

        groupManager.createOrUpdate(
            groupID: expectedGroupID,
            creator: expectedGroupCreator,
            members: expectedMembers,
            systemMessageDate: Date()
        )
        .done { grp, newMembers in
            resultGroup = grp
            resultNewMembers = newMembers

            expec.fulfill()
        }
        .catch { error in
            XCTFail(error.localizedDescription)
        }

        waitForExpectations(timeout: 1)

        let actualGroup = try XCTUnwrap(resultGroup)
        XCTAssertEqual(actualGroup.groupID, expectedGroupID)
        XCTAssertEqual(actualGroup.groupCreatorIdentity, expectedGroupCreator)
        XCTAssertNil(actualGroup.conversation.contact) // If I'm the creator this should be true
        XCTAssertEqual(actualGroup.allMemberIdentities.count, expectedMembers.count + 1)
        XCTAssertTrue(actualGroup.allMemberIdentities.contains(myIdentityStoreMock.identity))
        XCTAssertNil(actualGroup.lastSyncRequest)
        
        XCTAssertNil(resultNewMembers)
        
        XCTAssertEqual(1, taskManagerMock.addedTasks.filter { $0 is TaskDefinitionSendGroupCreateMessage }.count)
        
        let task = try XCTUnwrap(taskManagerMock.addedTasks.first as? TaskDefinitionSendGroupCreateMessage)
        XCTAssertTrue(expectedGroupID.elementsEqual(task.groupID!))
        XCTAssertEqual(expectedGroupCreator, task.groupCreatorIdentity)
        XCTAssertEqual(expectedMembers, task.members)
        let removedMembers = try XCTUnwrap(task.removedMembers)
        XCTAssertTrue(removedMembers.isEmpty)
        XCTAssertEqual(
            expectedMembers.count,
            task.toMembers
                .filter { $0.elementsEqual("MEMBER01") || $0.elementsEqual("MEMBER02") || $0.elementsEqual("MEMBER03") }
                .count
        )
    }
    
    func testSendGroupSetupIamCreatorAddMember() throws {
        let myIdentityStoreMock = MyIdentityStoreMock()
        let contactStoreMock = ContactStoreMock(callOnCompletion: true)
        let taskManagerMock = TaskManagerMock()
        let userSettingsMock = UserSettingsMock()

        let expectedGroupID: Data = BytesUtility.generateRandomBytes(length: ThreemaProtocol.groupIDLength)!
        let expectedGroupCreator: String = myIdentityStoreMock.identity
        let expectedNewMembers: Set<String> = ["MEMBER01"]

        for member in expectedNewMembers {
            databasePreparer.createContact(
                publicKey: BytesUtility.generateRandomBytes(length: 32)!,
                identity: member,
                verificationLevel: 0
            )
        }

        let groupManager = GroupManager(
            myIdentityStoreMock,
            contactStoreMock,
            taskManagerMock,
            userSettingsMock,
            EntityManager(databaseContext: databaseCnx, myIdentityStore: myIdentityStoreMock),
            groupPhotoSenderMock
        )

        createOrUpdateDBWait(
            groupManager: groupManager,
            groupID: expectedGroupID,
            creator: expectedGroupCreator,
            members: []
        )

        var resultGroup: Group?
        var resultNewMembers: Set<String>?

        let expec = expectation(description: "Group create or update")

        groupManager.createOrUpdate(
            groupID: expectedGroupID,
            creator: expectedGroupCreator,
            members: expectedNewMembers,
            systemMessageDate: Date()
        )
        .done { grp, newMembers in
            resultGroup = grp
            resultNewMembers = newMembers

            expec.fulfill()
        }
        .catch { error in
            XCTFail(error.localizedDescription)
        }

        waitForExpectations(timeout: 1)

        let resultGrp = try XCTUnwrap(resultGroup)
        XCTAssertEqual(resultGrp.groupID, expectedGroupID)
        XCTAssertEqual(resultGrp.groupCreatorIdentity, expectedGroupCreator)
        XCTAssertEqual(resultGrp.allMemberIdentities.count, expectedNewMembers.count + 1)
        XCTAssertTrue(resultGrp.allMemberIdentities.contains(myIdentityStoreMock.identity))
        XCTAssertNil(resultGrp.lastSyncRequest)

        XCTAssertEqual(expectedNewMembers, resultNewMembers)
        XCTAssertEqual(1, taskManagerMock.addedTasks.filter { $0 is TaskDefinitionSendGroupCreateMessage }.count)

        let task = try XCTUnwrap(taskManagerMock.addedTasks.first as? TaskDefinitionSendGroupCreateMessage)
        XCTAssertTrue(expectedGroupID.elementsEqual(task.groupID!))
        XCTAssertEqual(expectedGroupCreator, task.groupCreatorIdentity)
        XCTAssertEqual(expectedNewMembers, task.members)
        XCTAssertTrue(task.removedMembers?.isEmpty ?? false)
        XCTAssertEqual(
            expectedNewMembers.count,
            task.toMembers.filter { $0.elementsEqual("MEMBER01") }.count
        )
    }

    func testSendGroupSetupIamCreatorRemoveMember() throws {
        let myIdentityStoreMock = MyIdentityStoreMock()
        let contactStoreMock = ContactStoreMock(callOnCompletion: true)
        let taskManagerMock = TaskManagerMock()
        let userSettingsMock = UserSettingsMock()
        
        let expectedGroupID: Data = BytesUtility.generateRandomBytes(length: ThreemaProtocol.groupIDLength)!
        let expectedGroupCreator: String = myIdentityStoreMock.identity
        let expectedMembers: Set<String> = ["MEMBER01", "MEMBER02", "MEMBER03"]
        
        for member in expectedMembers {
            databasePreparer.createContact(
                publicKey: BytesUtility.generateRandomBytes(length: 32)!,
                identity: member,
                verificationLevel: 0
            )
        }
        
        let groupManager = GroupManager(
            myIdentityStoreMock,
            contactStoreMock,
            taskManagerMock,
            userSettingsMock,
            EntityManager(databaseContext: databaseCnx, myIdentityStore: myIdentityStoreMock),
            groupPhotoSenderMock
        )
        
        createOrUpdateDBWait(
            groupManager: groupManager,
            groupID: expectedGroupID,
            creator: expectedGroupCreator,
            members: expectedMembers
        )

        var resultGroup: Group?
        var resultNewMembers: Set<String>?
        
        let expectedNewMembers = expectedMembers.filter { $0 != "MEMBER02" }
        
        let expec = expectation(description: "Group create or update")

        groupManager.createOrUpdate(
            groupID: expectedGroupID,
            creator: expectedGroupCreator,
            members: expectedNewMembers,
            systemMessageDate: Date()
        )
        .done { grp, newMembers in
            resultGroup = grp
            resultNewMembers = newMembers

            expec.fulfill()
        }
        .catch { error in
            XCTFail(error.localizedDescription)
        }

        waitForExpectations(timeout: 1)

        let resultGrp = try XCTUnwrap(resultGroup)
        XCTAssertEqual(resultGrp.groupID, expectedGroupID)
        XCTAssertEqual(resultGrp.groupCreatorIdentity, expectedGroupCreator)
        XCTAssertEqual(resultGrp.allMemberIdentities.count, expectedNewMembers.count + 1)
        XCTAssertTrue(resultGrp.allMemberIdentities.contains(myIdentityStoreMock.identity))
        XCTAssertNil(resultGrp.lastSyncRequest)
        
        XCTAssertNil(resultNewMembers)
        XCTAssertEqual(1, taskManagerMock.addedTasks.filter { $0 is TaskDefinitionSendGroupCreateMessage }.count)
        
        let task = try XCTUnwrap(taskManagerMock.addedTasks.first as? TaskDefinitionSendGroupCreateMessage)
        XCTAssertTrue(expectedGroupID.elementsEqual(task.groupID!))
        XCTAssertEqual(expectedGroupCreator, task.groupCreatorIdentity)
        XCTAssertEqual(expectedNewMembers, task.members)
        XCTAssertEqual(1, task.removedMembers?.filter { $0 == "MEMBER02" }.count)
        XCTAssertEqual(
            expectedNewMembers.count,
            task.toMembers.filter { $0.elementsEqual("MEMBER01") || $0.elementsEqual("MEMBER03") }.count
        )
    }

    /// Spec: https://clients.pages.threema.dev/protocols/threema-protocols/structbuf/csp/#m:e2e:group-setup
    /// Section: When receiving this message: 4. / 1.
    func testReceiveGroupSetupFromBlockedContactAndUnknownGroupIamNotMember() throws {
        let myIdentityStoreMock = MyIdentityStoreMock()
        let userSettingsMock = UserSettingsMock()
        userSettingsMock.blacklist = ["MEMBER01"]
        let taskManagerMock = TaskManagerMock()

        let expectedGroupID = BytesUtility.generateRandomBytes(length: ThreemaProtocol.groupIDLength)!
        let expectedGroupCreator = "MEMBER01"
        let expectedMembers: Set<String> = ["MEMBER02", "MEMBER03"]

        databasePreparer.createContact(
            publicKey: BytesUtility.generateRandomBytes(length: 32)!,
            identity: expectedGroupCreator,
            verificationLevel: 0
        )

        for member in expectedMembers.filter({ $0 != myIdentityStoreMock.identity }) {
            _ = databasePreparer.createContact(
                publicKey: BytesUtility.generateRandomBytes(length: 32)!,
                identity: member,
                verificationLevel: 0
            )
        }

        let groupManager = GroupManager(
            myIdentityStoreMock,
            ContactStoreMock(callOnCompletion: true),
            taskManagerMock,
            userSettingsMock,
            EntityManager(databaseContext: databaseCnx, myIdentityStore: myIdentityStoreMock),
            groupPhotoSenderMock
        )

        let group = createOrUpdateDBWait(
            groupManager: groupManager,
            groupID: expectedGroupID,
            creator: expectedGroupCreator,
            members: expectedMembers
        )

        XCTAssertNil(group)
        XCTAssertEqual(0, taskManagerMock.addedTasks.count)
    }

    /// Spec: https://clients.pages.threema.dev/protocols/threema-protocols/structbuf/csp/#m:e2e:group-setup
    /// Section: When receiving this message: 4. / 2.
    func testReceiveGroupSetupFromBlockedContactAndUnknownGroup() throws {
        let myIdentityStoreMock = MyIdentityStoreMock()
        let userSettingsMock = UserSettingsMock()
        userSettingsMock.blacklist = ["MEMBER01"]
        let taskManagerMock = TaskManagerMock()

        let expectedGroupID = BytesUtility.generateRandomBytes(length: ThreemaProtocol.groupIDLength)!
        let expectedGroupCreator = "MEMBER01"
        let expectedMembers: Set<String> = [myIdentityStoreMock.identity, "MEMBER02", "MEMBER03"]

        databasePreparer.createContact(
            publicKey: BytesUtility.generateRandomBytes(length: 32)!,
            identity: expectedGroupCreator,
            verificationLevel: 0
        )

        for member in expectedMembers.filter({ $0 != myIdentityStoreMock.identity }) {
            databasePreparer.createContact(
                publicKey: BytesUtility.generateRandomBytes(length: 32)!,
                identity: member,
                verificationLevel: 0
            )
        }

        let groupManager = GroupManager(
            myIdentityStoreMock,
            ContactStoreMock(callOnCompletion: true),
            taskManagerMock,
            userSettingsMock,
            EntityManager(databaseContext: databaseCnx, myIdentityStore: myIdentityStoreMock),
            groupPhotoSenderMock
        )

        let group = createOrUpdateDBWait(
            groupManager: groupManager,
            groupID: expectedGroupID,
            creator: expectedGroupCreator,
            members: expectedMembers
        )

        XCTAssertNil(group)
        XCTAssertEqual(1, taskManagerMock.addedTasks.count)
        let leaveTask = try XCTUnwrap(
            taskManagerMock.addedTasks
                .first(where: { $0 is TaskDefinitionSendGroupLeaveMessage
                }) as? TaskDefinitionSendGroupLeaveMessage
        )
        XCTAssertTrue(expectedGroupID.elementsEqual(leaveTask.groupID!))
        XCTAssertEqual(expectedGroupCreator, leaveTask.groupCreatorIdentity)
        XCTAssertEqual(myIdentityStoreMock.identity, leaveTask.fromMember)
        XCTAssertEqual(
            expectedMembers.count,
            leaveTask.toMembers
                .filter { $0.elementsEqual("MEMBER01") || $0.elementsEqual("MEMBER02") || $0.elementsEqual("MEMBER03") }
                .count
        )
    }

    /// Spec: https://clients.pages.threema.dev/protocols/threema-protocols/structbuf/csp/#m:e2e:group-setup
    /// Section: When receiving this message: 5.
    func testReceiveGroupSetupExistingGroupIamNotMember() throws {
        let myIdentityStoreMock = MyIdentityStoreMock()

        let expectedGroupCreator = "MEMBER01"
        let expectedInitialMembers: Set<String> = [myIdentityStoreMock.identity, "MEMBER02", "MEMBER03"]

        databasePreparer.createContact(
            publicKey: BytesUtility.generateRandomBytes(length: 32)!,
            identity: expectedGroupCreator,
            verificationLevel: 0
        )
        for member in expectedInitialMembers.filter({ $0 != myIdentityStoreMock.identity }) {
            databasePreparer.createContact(
                publicKey: BytesUtility.generateRandomBytes(length: 32)!,
                identity: member,
                verificationLevel: 0
            )
        }
        databasePreparer.createContact(
            publicKey: BytesUtility.generateRandomBytes(length: 32)!,
            identity: "MEMBER04",
            verificationLevel: 0
        )

        for expectedMembers in [Set<String>(["MEMBER02", "MEMBER04"]), Set<String>([])] {
            let expectedGroupID: Data = BytesUtility.generateRandomBytes(length: ThreemaProtocol.groupIDLength)!

            let groupManager = GroupManager(
                myIdentityStoreMock,
                ContactStoreMock(callOnCompletion: true),
                TaskManagerMock(),
                UserSettingsMock(),
                EntityManager(databaseContext: databaseCnx, myIdentityStore: myIdentityStoreMock),
                groupPhotoSenderMock
            )

            let initialGrp = try XCTUnwrap(
                createOrUpdateDBWait(
                    groupManager: groupManager,
                    groupID: expectedGroupID,
                    creator: expectedGroupCreator,
                    members: expectedInitialMembers
                )
            )

            XCTAssertEqual(4, initialGrp.numberOfMembers)
            XCTAssertTrue(initialGrp.allMemberIdentities.contains(myIdentityStoreMock.identity))
            XCTAssertTrue(initialGrp.allMemberIdentities.contains("MEMBER01"))
            XCTAssertTrue(initialGrp.allMemberIdentities.contains("MEMBER02"))
            XCTAssertTrue(initialGrp.allMemberIdentities.contains("MEMBER03"))
            XCTAssertFalse(initialGrp.didCreatorLeave)
            XCTAssertFalse(initialGrp.didLeave)
            XCTAssertFalse(initialGrp.didForcedLeave)
            XCTAssertTrue(initialGrp.isSelfMember)
            XCTAssertFalse(initialGrp.isNoteGroup)

            // Hold old members to list chat history and to clone
            let grp = try XCTUnwrap(
                createOrUpdateDBWait(
                    groupManager: groupManager,
                    groupID: expectedGroupID,
                    creator: expectedGroupCreator,
                    members: expectedMembers
                )
            )

            XCTAssertEqual(3, grp.numberOfMembers)
            XCTAssertTrue(grp.allMemberIdentities.contains("MEMBER01"))
            XCTAssertTrue(grp.allMemberIdentities.contains("MEMBER02"))
            XCTAssertTrue(grp.allMemberIdentities.contains("MEMBER03"))
            XCTAssertFalse(grp.didCreatorLeave)
            XCTAssertFalse(grp.didLeave)
            XCTAssertTrue(grp.didForcedLeave)
            XCTAssertFalse(grp.isSelfMember)
            XCTAssertFalse(grp.isNoteGroup)
        }
    }
    
    func testReceiveGroupSetupWithRevokedMember() throws {
        let myIdentityStoreMock = MyIdentityStoreMock()

        let expectedGroupCreator = "MEMBER01"
        let expectedInitialMembers: Set<String> = [myIdentityStoreMock.identity, "MEMBER02", "MEMBER03"]

        databasePreparer.createContact(
            publicKey: BytesUtility.generateRandomBytes(length: 32)!,
            identity: expectedGroupCreator,
            verificationLevel: 0
        )
        for member in expectedInitialMembers.filter({ $0 != myIdentityStoreMock.identity }) {
            databasePreparer.createContact(
                publicKey: BytesUtility.generateRandomBytes(length: 32)!,
                identity: member,
                verificationLevel: 0
            )
        }
        
        let expectedMembers = expectedInitialMembers.union(Set(arrayLiteral: "MEMBER04"))
        let expectedGroupID: Data = BytesUtility.generateRandomBytes(length: ThreemaProtocol.groupIDLength)!

        let error = NSError(domain: NSURLErrorDomain, code: 404)
            
        let groupManager = GroupManager(
            myIdentityStoreMock,
            ContactStoreMock(callOnCompletion: true, errorHandler: error),
            TaskManagerMock(),
            UserSettingsMock(),
            EntityManager(databaseContext: databaseCnx, myIdentityStore: myIdentityStoreMock),
            groupPhotoSenderMock
        )

        let initialGrp = try XCTUnwrap(
            createOrUpdateDBWait(
                groupManager: groupManager,
                groupID: expectedGroupID,
                creator: expectedGroupCreator,
                members: expectedInitialMembers
            )
        )

        XCTAssertEqual(4, initialGrp.numberOfMembers)
        XCTAssertTrue(initialGrp.allMemberIdentities.contains(myIdentityStoreMock.identity))
        XCTAssertTrue(initialGrp.allMemberIdentities.contains("MEMBER01"))
        XCTAssertTrue(initialGrp.allMemberIdentities.contains("MEMBER02"))
        XCTAssertTrue(initialGrp.allMemberIdentities.contains("MEMBER03"))
        XCTAssertFalse(initialGrp.didCreatorLeave)
        XCTAssertFalse(initialGrp.didLeave)
        XCTAssertFalse(initialGrp.didForcedLeave)
        XCTAssertTrue(initialGrp.isSelfMember)
        XCTAssertFalse(initialGrp.isNoteGroup)

        // Hold old members to list chat history and to clone
            
        let grp = try XCTUnwrap(
            createOrUpdateDBWait(
                groupManager: groupManager,
                groupID: expectedGroupID,
                creator: expectedGroupCreator,
                members: expectedMembers
            )
        )

        XCTAssertEqual(4, grp.numberOfMembers)
        XCTAssertTrue(grp.allMemberIdentities.contains(myIdentityStoreMock.identity))
        XCTAssertTrue(grp.allMemberIdentities.contains("MEMBER01"))
        XCTAssertTrue(grp.allMemberIdentities.contains("MEMBER02"))
        XCTAssertTrue(grp.allMemberIdentities.contains("MEMBER03"))
        XCTAssertFalse(grp.didCreatorLeave)
        XCTAssertFalse(grp.didLeave)
        XCTAssertFalse(grp.didForcedLeave)
        XCTAssertTrue(grp.isSelfMember)
        XCTAssertFalse(grp.isNoteGroup)
    }
    
    func testReceiveGroupSetupWithRevokedMemberPartiallyApplyGroupSetup() throws {
        let myIdentityStoreMock = MyIdentityStoreMock()

        let expectedGroupCreator = "MEMBER01"
        let expectedInitialMembers: Set<String> = [myIdentityStoreMock.identity, "MEMBER02", "MEMBER03"]

        databasePreparer.createContact(
            publicKey: BytesUtility.generateRandomBytes(length: 32)!,
            identity: expectedGroupCreator,
            verificationLevel: 0
        )
        for member in expectedInitialMembers.filter({ $0 != myIdentityStoreMock.identity }) {
            databasePreparer.createContact(
                publicKey: BytesUtility.generateRandomBytes(length: 32)!,
                identity: member,
                verificationLevel: 0
            )
        }
        
        databasePreparer.createContact(
            publicKey: BytesUtility.generateRandomBytes(length: 32)!,
            identity: "MEMBER05",
            verificationLevel: 0
        )
        
        let expectedMembers = expectedInitialMembers.union(Set(arrayLiteral: "MEMBER04", "MEMBER05"))
        
        let expectedGroupID: Data = BytesUtility.generateRandomBytes(length: ThreemaProtocol.groupIDLength)!

        // A made up error; If we ever check for this in the future we need to change this test.
        let error = NSError(domain: NSURLErrorDomain, code: 404)
            
        let groupManager = GroupManager(
            myIdentityStoreMock,
            ContactStoreMock(callOnCompletion: true, errorHandler: error),
            TaskManagerMock(),
            UserSettingsMock(),
            EntityManager(databaseContext: databaseCnx, myIdentityStore: myIdentityStoreMock),
            groupPhotoSenderMock
        )

        let initialGrp = try XCTUnwrap(
            createOrUpdateDBWait(
                groupManager: groupManager,
                groupID: expectedGroupID,
                creator: expectedGroupCreator,
                members: expectedInitialMembers
            )
        )

        XCTAssertEqual(4, initialGrp.numberOfMembers)
        XCTAssertTrue(initialGrp.allMemberIdentities.contains(myIdentityStoreMock.identity))
        XCTAssertTrue(initialGrp.allMemberIdentities.contains("MEMBER01"))
        XCTAssertTrue(initialGrp.allMemberIdentities.contains("MEMBER02"))
        XCTAssertTrue(initialGrp.allMemberIdentities.contains("MEMBER03"))
        XCTAssertFalse(initialGrp.didCreatorLeave)
        XCTAssertFalse(initialGrp.didLeave)
        XCTAssertFalse(initialGrp.didForcedLeave)
        XCTAssertTrue(initialGrp.isSelfMember)
        XCTAssertFalse(initialGrp.isNoteGroup)
            
        let grp = try XCTUnwrap(
            createOrUpdateDBWait(
                groupManager: groupManager,
                groupID: expectedGroupID,
                creator: expectedGroupCreator,
                members: expectedMembers
            )
        )

        XCTAssertEqual(5, grp.numberOfMembers)
        XCTAssertTrue(grp.allMemberIdentities.contains(myIdentityStoreMock.identity))
        XCTAssertTrue(grp.allMemberIdentities.contains("MEMBER01"))
        XCTAssertTrue(grp.allMemberIdentities.contains("MEMBER02"))
        XCTAssertTrue(grp.allMemberIdentities.contains("MEMBER03"))
        XCTAssertTrue(grp.allMemberIdentities.contains("MEMBER05"))
        XCTAssertFalse(grp.allMemberIdentities.contains("MEMBER04"))
        XCTAssertFalse(grp.didCreatorLeave)
        XCTAssertFalse(grp.didLeave)
        XCTAssertFalse(grp.didForcedLeave)
        XCTAssertTrue(grp.isSelfMember)
        XCTAssertFalse(grp.isNoteGroup)
    }
    
    func testReceiveGroupSetupWithMissingLocalMember() throws {
        let myIdentityStoreMock = MyIdentityStoreMock()

        let expectedGroupCreator = "MEMBER01"
        let expectedInitialMembers: Set<String> = [myIdentityStoreMock.identity, "MEMBER02", "MEMBER03"]

        databasePreparer.createContact(
            publicKey: BytesUtility.generateRandomBytes(length: 32)!,
            identity: expectedGroupCreator,
            verificationLevel: 0
        )
        for member in expectedInitialMembers.filter({ $0 != myIdentityStoreMock.identity }) {
            databasePreparer.createContact(
                publicKey: BytesUtility.generateRandomBytes(length: 32)!,
                identity: member,
                verificationLevel: 0
            )
        }
        
        let expectedMembers = expectedInitialMembers.union(Set(arrayLiteral: "MEMBER04"))
        
        let expectedGroupID: Data = BytesUtility.generateRandomBytes(length: ThreemaProtocol.groupIDLength)!

        // A made up error; If we ever check for this in the future we need to change this test.
        let error = NSError(domain: NSPOSIXErrorDomain, code: 8_765_432_187)
            
        let groupManager = GroupManager(
            myIdentityStoreMock,
            ContactStoreMock(callOnCompletion: true, errorHandler: error),
            TaskManagerMock(),
            UserSettingsMock(),
            EntityManager(databaseContext: databaseCnx, myIdentityStore: myIdentityStoreMock),
            groupPhotoSenderMock
        )

        let initialGrp = try XCTUnwrap(
            createOrUpdateDBWait(
                groupManager: groupManager,
                groupID: expectedGroupID,
                creator: expectedGroupCreator,
                members: expectedInitialMembers
            )
        )

        XCTAssertEqual(4, initialGrp.numberOfMembers)
        XCTAssertTrue(initialGrp.allMemberIdentities.contains(myIdentityStoreMock.identity))
        XCTAssertTrue(initialGrp.allMemberIdentities.contains("MEMBER01"))
        XCTAssertTrue(initialGrp.allMemberIdentities.contains("MEMBER02"))
        XCTAssertTrue(initialGrp.allMemberIdentities.contains("MEMBER03"))
        XCTAssertFalse(initialGrp.didCreatorLeave)
        XCTAssertFalse(initialGrp.didLeave)
        XCTAssertFalse(initialGrp.didForcedLeave)
        XCTAssertTrue(initialGrp.isSelfMember)
        XCTAssertFalse(initialGrp.isNoteGroup)
            
        XCTAssertNil(
            createOrUpdateDBWait(
                groupManager: groupManager,
                groupID: expectedGroupID,
                creator: expectedGroupCreator,
                members: expectedMembers
            )
        )
    }

    func testSetName() throws {
        let myIdentityStoreMock = MyIdentityStoreMock()
        let contactStoreMock = ContactStoreMock(callOnCompletion: true)
        let taskManagerMock = TaskManagerMock()
        let userSettingsMock = UserSettingsMock()
        
        let expectedGroupID: Data = BytesUtility.generateRandomBytes(length: ThreemaProtocol.groupIDLength)!
        let expectedGroupCreator: String = myIdentityStoreMock.identity
        let expectedMembers: Set<String> = ["MEMBER01", "MEMBER02", "MEMBER03"]
        let expectedName = "Test name 123"
        
        for member in expectedMembers {
            databasePreparer.createContact(
                publicKey: BytesUtility.generateRandomBytes(length: 32)!,
                identity: member,
                verificationLevel: 0
            )
        }
        
        let groupManager: GroupManagerProtocol = GroupManager(
            myIdentityStoreMock,
            contactStoreMock,
            taskManagerMock,
            userSettingsMock,
            EntityManager(databaseContext: databaseCnx, myIdentityStore: myIdentityStoreMock),
            groupPhotoSenderMock
        )
        
        let grp = try XCTUnwrap(
            createOrUpdateDBWait(
                groupManager: groupManager,
                groupID: expectedGroupID,
                creator: expectedGroupCreator,
                members: expectedMembers
            )
        )

        XCTAssertNil(grp.name)
        
        let expec = expectation(description: "Set group name completed")
        
        groupManager.setName(group: grp, name: expectedName)
            .done {
                expec.fulfill()
            }
            .catch { error in
                XCTFail(error.localizedDescription)
            }
        
        waitForExpectations(timeout: 6)

        XCTAssertEqual(expectedName, grp.name)
        XCTAssertEqual(1, taskManagerMock.addedTasks.filter { $0 is TaskDefinitionSendGroupRenameMessage }.count)
        let task = try XCTUnwrap(taskManagerMock.addedTasks.first as? TaskDefinitionSendGroupRenameMessage)
        XCTAssertTrue(expectedGroupID.elementsEqual(task.groupID!))
        XCTAssertEqual(expectedGroupCreator, task.groupCreatorIdentity)
        XCTAssertEqual(myIdentityStoreMock.identity, task.fromMember)
        XCTAssertEqual(
            expectedMembers.count,
            task.toMembers
                .filter { $0.elementsEqual("MEMBER01") || $0.elementsEqual("MEMBER02") || $0.elementsEqual("MEMBER03") }
                .count
        )
        XCTAssertEqual(expectedName, task.name)
    }
    
    func testSetAndDeletePhoto() throws {
        
        // Setup
        
        let myIdentityStoreMock = MyIdentityStoreMock()
        let contactStoreMock = ContactStoreMock(callOnCompletion: true)
        let taskManagerMock = TaskManagerMock()
        let userSettingsMock = UserSettingsMock()
        
        let expectedGroupID: Data = BytesUtility.generateRandomBytes(length: ThreemaProtocol.groupIDLength)!
        let expectedGroupCreator: String = myIdentityStoreMock.identity
        let expectedMembers: Set<String> = ["MEMBER01", "MEMBER02", "MEMBER03"]
        let expectedPhoto: Data = try! Data(contentsOf: ResourceLoader.urlResource("Bild-1-0", "jpg")!)
        
        for member in expectedMembers {
            _ = databasePreparer.createContact(
                publicKey: BytesUtility.generateRandomBytes(length: 32)!,
                identity: member,
                verificationLevel: 0
            )
        }
        
        let groupManager = GroupManager(
            myIdentityStoreMock,
            contactStoreMock,
            taskManagerMock,
            userSettingsMock,
            EntityManager(databaseContext: databaseCnx, myIdentityStore: myIdentityStoreMock),
            groupPhotoSenderMock
        )
        
        let grp = try XCTUnwrap(
            createOrUpdateDBWait(
                groupManager: groupManager,
                groupID: expectedGroupID,
                creator: expectedGroupCreator,
                members: expectedMembers
            )
        )

        XCTAssertNil(grp.photo)
        
        let expecSetGroupPhoto = expectation(description: "Set group photo")
        
        // Run set photo test
        
        groupManager.setPhoto(group: grp, imageData: expectedPhoto, sentDate: Date())
            .done {
                expecSetGroupPhoto.fulfill()
            }
            .catch { error in
                XCTFail(error.localizedDescription)
            }
        
        // Validate set photo test
        
        waitForExpectations(timeout: 6)

        XCTAssertTrue(grp.photo!.data!.elementsEqual(expectedPhoto))
        XCTAssertEqual(1, taskManagerMock.addedTasks.filter { $0 is TaskDefinitionSendGroupSetPhotoMessage }.count)
        
        let setTask = try XCTUnwrap(taskManagerMock.addedTasks.first as? TaskDefinitionSendGroupSetPhotoMessage)
        XCTAssertTrue(expectedGroupID.elementsEqual(setTask.groupID!))
        XCTAssertEqual(expectedGroupCreator, setTask.groupCreatorIdentity)
        XCTAssertEqual(myIdentityStoreMock.identity, setTask.fromMember)
        XCTAssertEqual(
            expectedMembers.count,
            setTask.toMembers
                .filter { $0.elementsEqual("MEMBER01") || $0.elementsEqual("MEMBER02") || $0.elementsEqual("MEMBER03") }
                .count
        )
        XCTAssertEqual(expectedPhoto.count, Int(setTask.size))
        XCTAssertEqual(groupPhotoSenderMock.blobID, setTask.blobID)
        XCTAssertEqual(groupPhotoSenderMock.encryptionKey, setTask.encryptionKey)
        
        // Run delete photo test
        
        let expecDeleteGroupPhoto = expectation(description: "Delete group photo")
        
        groupManager.deletePhoto(groupID: grp.groupID, creator: grp.groupCreatorIdentity, sentDate: Date())
            .done {
                expecDeleteGroupPhoto.fulfill()
            }
            .catch { error in
                XCTFail(error.localizedDescription)
            }
        
        // Validate delete photo test
        
        waitForExpectations(timeout: 6)

        XCTAssertNil(grp.photo)
        XCTAssertEqual(1, taskManagerMock.addedTasks.filter { $0 is TaskDefinitionSendGroupDeletePhotoMessage }.count)
        
        let deleteTask = try XCTUnwrap(
            taskManagerMock.addedTasks
                .first(where: { $0 is TaskDefinitionSendGroupDeletePhotoMessage
                }) as? TaskDefinitionSendGroupDeletePhotoMessage
        )
        XCTAssertTrue(expectedGroupID.elementsEqual(deleteTask.groupID!))
        XCTAssertEqual(expectedGroupCreator, deleteTask.groupCreatorIdentity)
        XCTAssertEqual(myIdentityStoreMock.identity, deleteTask.fromMember)
        XCTAssertEqual(
            expectedMembers.count,
            deleteTask.toMembers
                .filter { $0.elementsEqual("MEMBER01") || $0.elementsEqual("MEMBER02") || $0.elementsEqual("MEMBER03") }
                .count
        )
    }

    // Spec: https://clients.pages.threema.dev/protocols/threema-protocols/structbuf/csp-e2e/#m:e2e:group-leave
    func testSendLeaveAsCreator() throws {
        let myIdentityStoreMock = MyIdentityStoreMock()
        let contactStoreMock = ContactStoreMock(callOnCompletion: true)
        let taskManagerMock = TaskManagerMock()
        let userSettingsMock = UserSettingsMock()
        
        let expectedGroupID: Data = BytesUtility.generateRandomBytes(length: ThreemaProtocol.groupIDLength)!
        let expectedGroupCreator: String = myIdentityStoreMock.identity
        let expectedMembers: Set<String> = ["MEMBER01", "MEMBER02", "MEMBER03"]
        
        for member in expectedMembers {
            databasePreparer.createContact(
                publicKey: BytesUtility.generateRandomBytes(length: 32)!,
                identity: member,
                verificationLevel: 0
            )
        }

        let groupManager = GroupManager(
            myIdentityStoreMock,
            contactStoreMock,
            taskManagerMock,
            userSettingsMock,
            EntityManager(databaseContext: databaseCnx, myIdentityStore: myIdentityStoreMock),
            groupPhotoSenderMock
        )
        
        let grp = createOrUpdateDBWait(
            groupManager: groupManager,
            groupID: expectedGroupID,
            creator: expectedGroupCreator,
            members: expectedMembers
        )
        
        XCTAssertNotNil(grp)

        groupManager.leave(
            groupID: expectedGroupID,
            creator: expectedGroupCreator,
            toMembers: nil,
            systemMessageDate: Date()
        )

        DDLog.flushLog()

        XCTAssertTrue(ddLoggerMock.exists(message: "Group creator can't leave the group"))
        XCTAssertEqual(0, taskManagerMock.addedTasks.count)
    }

    // Spec: https://clients.pages.threema.dev/protocols/threema-protocols/structbuf/csp-e2e/#m:e2e:group-leave
    func testSendLeaveAsMember() throws {
        let myIdentityStoreMock = MyIdentityStoreMock()
        let contactStoreMock = ContactStoreMock(callOnCompletion: true)
        let taskManagerMock = TaskManagerMock()
        let userSettingsMock = UserSettingsMock()

        let expectedGroupID: Data = BytesUtility.generateRandomBytes(length: ThreemaProtocol.groupIDLength)!
        let expectedGroupCreator = "MEMBER01"
        let expectedMembers: Set<String> = [myIdentityStoreMock.identity, "MEMBER02", "MEMBER03"]

        databasePreparer.createContact(
            publicKey: BytesUtility.generateRandomBytes(length: 32)!,
            identity: expectedGroupCreator,
            verificationLevel: 0
        )
        for member in expectedMembers {
            databasePreparer.createContact(
                publicKey: BytesUtility.generateRandomBytes(length: 32)!,
                identity: member,
                verificationLevel: 0
            )
        }

        let groupManager = GroupManager(
            myIdentityStoreMock,
            contactStoreMock,
            taskManagerMock,
            userSettingsMock,
            EntityManager(databaseContext: databaseCnx, myIdentityStore: myIdentityStoreMock),
            groupPhotoSenderMock
        )

        let grp = createOrUpdateDBWait(
            groupManager: groupManager,
            groupID: expectedGroupID,
            creator: expectedGroupCreator,
            members: expectedMembers
        )

        XCTAssertNotNil(grp)

        groupManager.leave(
            groupID: expectedGroupID,
            creator: expectedGroupCreator,
            toMembers: nil,
            systemMessageDate: Date()
        )

        XCTAssertEqual(1, taskManagerMock.addedTasks.filter { $0 is TaskDefinitionSendGroupLeaveMessage }.count)
        let task = try XCTUnwrap(taskManagerMock.addedTasks.first as? TaskDefinitionSendGroupLeaveMessage)
        XCTAssertTrue(expectedGroupID.elementsEqual(task.groupID!))
        XCTAssertEqual(expectedGroupCreator, task.groupCreatorIdentity)
        XCTAssertEqual(myIdentityStoreMock.identity, task.fromMember)
        XCTAssertEqual(
            3,
            task.toMembers?
                .filter { $0.elementsEqual("MEMBER01") || $0.elementsEqual("MEMBER02") || $0.elementsEqual("MEMBER03") }
                .count
        )
    }

    func testSendLeaveToParticularMember() throws {
        let myIdentityStoreMock = MyIdentityStoreMock()
        let contactStoreMock = ContactStoreMock(callOnCompletion: true)
        let taskManagerMock = TaskManagerMock()
        let userSettingsMock = UserSettingsMock()

        let expectedGroupID: Data = BytesUtility.generateRandomBytes(length: ThreemaProtocol.groupIDLength)!
        let expectedGroupCreator = "MEMBER01"
        let expectedMembers: Set<String> = [myIdentityStoreMock.identity, "MEMBER02", "MEMBER03"]

        databasePreparer.createContact(
            publicKey: BytesUtility.generateRandomBytes(length: 32)!,
            identity: expectedGroupCreator,
            verificationLevel: 0
        )
        for member in expectedMembers {
            databasePreparer.createContact(
                publicKey: BytesUtility.generateRandomBytes(length: 32)!,
                identity: member,
                verificationLevel: 0
            )
        }

        let groupManager = GroupManager(
            myIdentityStoreMock,
            contactStoreMock,
            taskManagerMock,
            userSettingsMock,
            EntityManager(databaseContext: databaseCnx, myIdentityStore: myIdentityStoreMock),
            groupPhotoSenderMock
        )

        let grp = createOrUpdateDBWait(
            groupManager: groupManager,
            groupID: expectedGroupID,
            creator: expectedGroupCreator,
            members: expectedMembers
        )

        XCTAssertNotNil(grp)

        groupManager.leave(
            groupID: expectedGroupID,
            creator: expectedGroupCreator,
            toMembers: ["MEMBER02"],
            systemMessageDate: Date()
        )

        XCTAssertEqual(1, taskManagerMock.addedTasks.filter { $0 is TaskDefinitionSendGroupLeaveMessage }.count)
        let task = try XCTUnwrap(taskManagerMock.addedTasks.first as? TaskDefinitionSendGroupLeaveMessage)
        XCTAssertTrue(expectedGroupID.elementsEqual(task.groupID!))
        XCTAssertEqual(expectedGroupCreator, task.groupCreatorIdentity)
        XCTAssertEqual(myIdentityStoreMock.identity, task.fromMember)
        XCTAssertEqual(1, task.toMembers.count)
        XCTAssertTrue(try XCTUnwrap(task.toMembers).contains("MEMBER02"))
    }

    func testSendLeaveAndAdd() throws {
        let myIdentityStoreMock = MyIdentityStoreMock()
        let contactStoreMock = ContactStoreMock(callOnCompletion: true)
        let taskManagerMock = TaskManagerMock()
        let userSettingsMock = UserSettingsMock()

        let expectedGroupID: Data = BytesUtility.generateRandomBytes(length: ThreemaProtocol.groupIDLength)!
        let expectedGroupCreator = "MEMBER01"
        let expectedMembers: Set<String> = ["MEMBER02", "MEMBER03", myIdentityStoreMock.identity]

        databasePreparer.createContact(
            publicKey: BytesUtility.generateRandomBytes(length: 32)!,
            identity: expectedGroupCreator,
            verificationLevel: 0
        )
        for member in expectedMembers {
            _ = databasePreparer.createContact(
                publicKey: BytesUtility.generateRandomBytes(length: 32)!,
                identity: member,
                verificationLevel: 0
            )
        }

        let groupManager = GroupManager(
            myIdentityStoreMock,
            contactStoreMock,
            taskManagerMock,
            userSettingsMock,
            EntityManager(databaseContext: databaseCnx, myIdentityStore: myIdentityStoreMock),
            groupPhotoSenderMock
        )

        let grp = try XCTUnwrap(
            createOrUpdateDBWait(
                groupManager: groupManager,
                groupID: expectedGroupID,
                creator: expectedGroupCreator,
                members: expectedMembers
            )
        )

        XCTAssertEqual(4, grp.allMemberIdentities.count)
        XCTAssertFalse(grp.didLeave)

        groupManager.leave(
            groupID: expectedGroupID,
            creator: expectedGroupCreator,
            toMembers: nil,
            systemMessageDate: Date()
        )

        let grpLeft = try XCTUnwrap(groupManager.getGroup(expectedGroupID, creator: expectedGroupCreator))
        XCTAssertEqual(3, grpLeft.allMemberIdentities.count)
        XCTAssertTrue(grpLeft.didLeave)

        let grpAdded = try XCTUnwrap(
            createOrUpdateDBWait(
                groupManager: groupManager,
                groupID: expectedGroupID,
                creator: expectedGroupCreator,
                members: expectedMembers
            )
        )

        XCTAssertEqual(4, grpAdded.allMemberIdentities.count)
        XCTAssertFalse(grpAdded.didLeave)
    }

    // Spec: https://clients.pages.threema.dev/protocols/threema-protocols/structbuf/csp/#m:e2e:group-leave
    // Section: When receiving this message: 1.
    //      -> In step 1 the group creator will be removed from the group. And a system message 'group is not mutable anymore' will be added.
    //      -> Later in step 1 the group will be left. And system message 'group must be cloned' will be added.
    func testReceiveLeaveFromCreator() throws {
        let myIdentityStoreMock = MyIdentityStoreMock()
        let contactStoreMock = ContactStoreMock(callOnCompletion: true)
        let taskManagerMock = TaskManagerMock()
        let userSettingsMock = UserSettingsMock()

        let expectedGroupID: Data = BytesUtility.generateRandomBytes(length: ThreemaProtocol.groupIDLength)!
        let expectedGroupCreator = "MEMBER01"
        let expectedMembers: Set<String> = [myIdentityStoreMock.identity, "MEMBER02", "MEMBER03"]

        databasePreparer.createContact(
            publicKey: BytesUtility.generateRandomBytes(length: 32)!,
            identity: expectedGroupCreator,
            verificationLevel: 0
        )
        for member in expectedMembers {
            databasePreparer.createContact(
                publicKey: BytesUtility.generateRandomBytes(length: 32)!,
                identity: member,
                verificationLevel: 0
            )
        }

        let entityManager = EntityManager(databaseContext: databaseCnx, myIdentityStore: myIdentityStoreMock)
        let groupManager = GroupManager(
            myIdentityStoreMock,
            contactStoreMock,
            taskManagerMock,
            userSettingsMock,
            entityManager,
            groupPhotoSenderMock
        )

        createOrUpdateDBWait(
            groupManager: groupManager,
            groupID: expectedGroupID,
            creator: expectedGroupCreator,
            members: expectedMembers
        )

        groupManager.leaveDB(
            groupID: expectedGroupID,
            creator: expectedGroupCreator,
            member: expectedGroupCreator,
            systemMessageDate: Date()
        )

        let group = try XCTUnwrap(
            groupManager.getGroup(expectedGroupID, creator: expectedGroupCreator)
        )

        DDLog.flushLog()

        XCTAssertFalse(group.didLeave)
        XCTAssertFalse(group.didForcedLeave)
        XCTAssertEqual(3, group.allMemberIdentities.count)
        XCTAssertTrue(group.allMemberIdentities.contains("MEMBER02"))
        XCTAssertFalse(group.allMemberIdentities.contains(expectedGroupCreator))

        // Check added system messages

        let messageFetcher = MessageFetcher(for: group.conversation, with: entityManager)
        XCTAssertEqual(messageFetcher.count(), 5)

        let systemMessageTypes = messageFetcher.messages(at: 0, count: 0).map { ($0 as? SystemMessage)?.type ?? 0 }
        XCTAssertEqual(3, systemMessageTypes.filter { $0.intValue == kSystemMessageGroupMemberAdd }.count)
        XCTAssertEqual(kSystemMessageGroupCreatorLeft, systemMessageTypes.last?.intValue)
    }

    func testDissolveAsAdmin() throws {
        let myIdentityStoreMock = MyIdentityStoreMock()
        let contactStoreMock = ContactStoreMock(callOnCompletion: true)
        let taskManagerMock = TaskManagerMock()
        let userSettingsMock = UserSettingsMock()

        let expectedGroupID: Data = BytesUtility.generateRandomBytes(length: ThreemaProtocol.groupIDLength)!
        let expectedGroupCreator: String = myIdentityStoreMock.identity
        let expectedMembers: Set<String> = ["MEMBER01", "MEMBER02", "MEMBER03"]

        for member in expectedMembers {
            databasePreparer.createContact(
                publicKey: BytesUtility.generateRandomBytes(length: 32)!,
                identity: member,
                verificationLevel: 0
            )
        }

        let groupManager = GroupManager(
            myIdentityStoreMock,
            contactStoreMock,
            taskManagerMock,
            userSettingsMock,
            EntityManager(databaseContext: databaseCnx, myIdentityStore: myIdentityStoreMock),
            groupPhotoSenderMock
        )

        let grp = try XCTUnwrap(
            createOrUpdateDBWait(
                groupManager: groupManager,
                groupID: expectedGroupID,
                creator: expectedGroupCreator,
                members: expectedMembers
            )
        )

        groupManager.dissolve(groupID: grp.groupID, to: nil)

        let group = try XCTUnwrap(
            groupManager.getGroup(expectedGroupID, creator: expectedGroupCreator)
        )

        XCTAssertTrue(group.didLeave)
        XCTAssertFalse(group.didForcedLeave)
        XCTAssertFalse(group.allMemberIdentities.contains(expectedGroupCreator))
        XCTAssertEqual(3, group.allMemberIdentities.count)

        let task = try XCTUnwrap(taskManagerMock.addedTasks.first as? TaskDefinitionSendGroupCreateMessage)
        XCTAssertEqual(0, task.toMembers.count)
        XCTAssertEqual(4, task.members.count)
        XCTAssertEqual(3, task.removedMembers?.count)
    }

    func testDissolveAsAdminTwoMembers() throws {
        let myIdentityStoreMock = MyIdentityStoreMock()
        let contactStoreMock = ContactStoreMock(callOnCompletion: true)
        let taskManagerMock = TaskManagerMock()
        let userSettingsMock = UserSettingsMock()

        let expectedGroupID: Data = BytesUtility.generateRandomBytes(length: ThreemaProtocol.groupIDLength)!
        let expectedGroupCreator: String = myIdentityStoreMock.identity
        let expectedMembers: Set<String> = ["MEMBER01", "MEMBER02", "MEMBER03"]

        for member in expectedMembers {
            databasePreparer.createContact(
                publicKey: BytesUtility.generateRandomBytes(length: 32)!,
                identity: member,
                verificationLevel: 0
            )
        }

        let groupManager = GroupManager(
            myIdentityStoreMock,
            contactStoreMock,
            taskManagerMock,
            userSettingsMock,
            EntityManager(databaseContext: databaseCnx, myIdentityStore: myIdentityStoreMock),
            groupPhotoSenderMock
        )

        let grp = try XCTUnwrap(
            createOrUpdateDBWait(
                groupManager: groupManager,
                groupID: expectedGroupID,
                creator: expectedGroupCreator,
                members: expectedMembers
            )
        )

        groupManager.dissolve(groupID: grp.groupID, to: ["MEMBER01", "MEMBER02"])

        let group = try XCTUnwrap(
            groupManager.getGroup(expectedGroupID, creator: expectedGroupCreator)
        )

        XCTAssertTrue(group.didLeave)
        XCTAssertFalse(group.didForcedLeave)
        XCTAssertFalse(group.allMemberIdentities.contains(expectedGroupCreator))
        XCTAssertEqual(3, group.allMemberIdentities.count)

        let task = try XCTUnwrap(taskManagerMock.addedTasks.first as? TaskDefinitionSendGroupCreateMessage)
        XCTAssertEqual(0, task.toMembers.count)
        XCTAssertEqual(4, task.members.count)
        XCTAssertEqual(2, task.removedMembers?.count)
        XCTAssertTrue(task.removedMembers?.contains("MEMBER01") ?? false)
        XCTAssertTrue(task.removedMembers?.contains("MEMBER02") ?? false)
    }

    func testDissolveAsMember() throws {
        let myIdentityStoreMock = MyIdentityStoreMock()
        let contactStoreMock = ContactStoreMock(callOnCompletion: true)
        let taskManagerMock = TaskManagerMock()
        let userSettingsMock = UserSettingsMock()

        let expectedGroupID: Data = BytesUtility.generateRandomBytes(length: ThreemaProtocol.groupIDLength)!
        let expectedGroupCreator = "MEMBER01"
        let expectedMembers: Set<String> = [myIdentityStoreMock.identity, "MEMBER02", "MEMBER03"]

        databasePreparer.createContact(
            publicKey: BytesUtility.generateRandomBytes(length: 32)!,
            identity: expectedGroupCreator,
            verificationLevel: 0
        )
        for member in expectedMembers {
            databasePreparer.createContact(
                publicKey: BytesUtility.generateRandomBytes(length: 32)!,
                identity: member,
                verificationLevel: 0
            )
        }

        let groupManager = GroupManager(
            myIdentityStoreMock,
            contactStoreMock,
            taskManagerMock,
            userSettingsMock,
            EntityManager(databaseContext: databaseCnx, myIdentityStore: myIdentityStoreMock),
            groupPhotoSenderMock
        )

        let grp = try XCTUnwrap(
            createOrUpdateDBWait(
                groupManager: groupManager,
                groupID: expectedGroupID,
                creator: expectedGroupCreator,
                members: expectedMembers
            )
        )

        groupManager.dissolve(groupID: grp.groupID, to: nil)

        let group = try XCTUnwrap(
            groupManager.getGroup(expectedGroupID, creator: expectedGroupCreator)
        )

        XCTAssertFalse(group.didLeave)
        XCTAssertFalse(group.didForcedLeave)
        XCTAssertEqual(4, group.allMemberIdentities.count)
        XCTAssertEqual(0, taskManagerMock.addedTasks.count)
    }

    // Test with blocked contact
    func testSyncAllMembers() throws {
        // Setup
        
        let myIdentityStoreMock = MyIdentityStoreMock()
        let contactStoreMock = ContactStoreMock(callOnCompletion: true)
        let taskManagerMock = TaskManagerMock()
        let userSettingsMock = UserSettingsMock()
        
        let expectedGroupID: Data = BytesUtility.generateRandomBytes(length: ThreemaProtocol.groupIDLength)!
        let expectedGroupCreator: String = myIdentityStoreMock.identity
        let expectedMembers: Set<String> = ["MEMBER01", "MEMBER02", "MEMBER03"]
        let expectedPhoto: Data = try XCTUnwrap(Data(contentsOf: ResourceLoader.urlResource("Bild-1-0", "jpg")!))
        
        for member in expectedMembers {
            _ = databasePreparer.createContact(
                publicKey: BytesUtility.generateRandomBytes(length: 32)!,
                identity: member,
                verificationLevel: 0
            )
        }
        
        let groupManager = GroupManager(
            myIdentityStoreMock,
            contactStoreMock,
            taskManagerMock,
            userSettingsMock,
            EntityManager(databaseContext: databaseCnx, myIdentityStore: myIdentityStoreMock),
            groupPhotoSenderMock
        )
        
        let grp = try XCTUnwrap(
            createOrUpdateDBWait(
                groupManager: groupManager,
                groupID: expectedGroupID,
                creator: expectedGroupCreator,
                members: expectedMembers
            )
        )

        // Set photo
        let expectationPhoto = expectation(description: "Set photo")
        groupManager.setPhoto(group: grp, imageData: expectedPhoto, sentDate: Date())
            .done {
                expectationPhoto.fulfill()
            }
            .catch { error in
                XCTFail(error.localizedDescription)
            }
        
        waitForExpectations(timeout: 1)
        
        let expectationSyncAllMembers = expectation(description: "Sync all members")
        
        // Run
        
        groupManager.sync(group: grp, to: nil, withoutCreateMessage: false)
            .done {
                expectationSyncAllMembers.fulfill()
            }
            .catch { error in
                XCTFail(error.localizedDescription)
            }
        
        // Validate
        
        waitForExpectations(timeout: 1)
        
        // SetPhoto, Create, Rename, SetPhoto => 4
        XCTAssertEqual(4, taskManagerMock.addedTasks.count)

        let createMessageTask = try XCTUnwrap(taskManagerMock.addedTasks[1] as? TaskDefinitionSendGroupCreateMessage)
        XCTAssertEqual(expectedGroupID, createMessageTask.groupID)
        XCTAssertEqual(expectedGroupCreator, createMessageTask.groupCreatorIdentity)
        XCTAssertEqual(expectedMembers, Set(createMessageTask.toMembers))
        XCTAssertNil(createMessageTask.removedMembers)
        XCTAssertEqual(expectedMembers, createMessageTask.members)
        
        let renameMessageTask = try XCTUnwrap(taskManagerMock.addedTasks[2] as? TaskDefinitionSendGroupRenameMessage)
        XCTAssertEqual(expectedGroupID, renameMessageTask.groupID)
        XCTAssertEqual(expectedGroupCreator, renameMessageTask.groupCreatorIdentity)
        XCTAssertEqual(myIdentityStoreMock.identity, renameMessageTask.fromMember)
        XCTAssertEqual(expectedMembers, Set(renameMessageTask.toMembers))
        XCTAssertNil(renameMessageTask.name)
        
        let setPhotoTask = try XCTUnwrap(taskManagerMock.addedTasks[3] as? TaskDefinitionSendGroupSetPhotoMessage)
        XCTAssertEqual(expectedGroupID, setPhotoTask.groupID)
        XCTAssertEqual(expectedGroupCreator, setPhotoTask.groupCreatorIdentity)
        XCTAssertEqual(myIdentityStoreMock.identity, setPhotoTask.fromMember)
        XCTAssertEqual(expectedMembers, Set(setPhotoTask.toMembers))
        XCTAssertEqual(groupPhotoSenderMock.blobID, setPhotoTask.blobID)
        XCTAssertEqual(groupPhotoSenderMock.encryptionKey, setPhotoTask.encryptionKey)
    }
    
    func testSyncOneMember() throws {
        // Setup
        
        let myIdentityStoreMock = MyIdentityStoreMock()
        let contactStoreMock = ContactStoreMock(callOnCompletion: true)
        let taskManagerMock = TaskManagerMock()
        let userSettingsMock = UserSettingsMock()
        
        let expectedGroupID: Data = BytesUtility.generateRandomBytes(length: ThreemaProtocol.groupIDLength)!
        let expectedGroupCreator: String = myIdentityStoreMock.identity
        let expectedMembers: Set<String> = ["MEMBER01", "MEMBER02", "MEMBER03"]
        let expectedToMember = Set(["MEMBER01"])
        
        for member in expectedMembers {
            _ = databasePreparer.createContact(
                publicKey: BytesUtility.generateRandomBytes(length: 32)!,
                identity: member,
                verificationLevel: 0
            )
        }
        
        let groupManager = GroupManager(
            myIdentityStoreMock,
            contactStoreMock,
            taskManagerMock,
            userSettingsMock,
            EntityManager(databaseContext: databaseCnx, myIdentityStore: myIdentityStoreMock),
            groupPhotoSenderMock
        )
        
        let grp = try XCTUnwrap(
            createOrUpdateDBWait(
                groupManager: groupManager,
                groupID: expectedGroupID,
                creator: expectedGroupCreator,
                members: expectedMembers
            )
        )

        let expectationSync = expectation(description: "Sync")
        
        // Run
        
        groupManager.sync(group: grp, to: expectedToMember, withoutCreateMessage: false)
            .done {
                expectationSync.fulfill()
            }
            .catch { error in
                XCTFail(error.localizedDescription)
            }
        
        // Validate
        
        waitForExpectations(timeout: 1)
        
        // Create, Rename, DeletePhoto => 3
        XCTAssertEqual(3, taskManagerMock.addedTasks.count)

        let createMessageTask = try XCTUnwrap(taskManagerMock.addedTasks[0] as? TaskDefinitionSendGroupCreateMessage)
        XCTAssertEqual(expectedGroupID, createMessageTask.groupID)
        XCTAssertEqual(expectedGroupCreator, createMessageTask.groupCreatorIdentity)
        XCTAssertEqual(expectedToMember, Set(createMessageTask.toMembers))
        XCTAssertNil(createMessageTask.removedMembers)
        XCTAssertEqual(expectedMembers, createMessageTask.members)
        
        let renameMessageTask = try XCTUnwrap(taskManagerMock.addedTasks[1] as? TaskDefinitionSendGroupRenameMessage)
        XCTAssertEqual(expectedGroupID, renameMessageTask.groupID)
        XCTAssertEqual(expectedGroupCreator, renameMessageTask.groupCreatorIdentity)
        XCTAssertEqual(myIdentityStoreMock.identity, renameMessageTask.fromMember)
        XCTAssertEqual(expectedToMember, Set(renameMessageTask.toMembers))
        XCTAssertNil(renameMessageTask.name)
        
        let setPhotoTask = try XCTUnwrap(taskManagerMock.addedTasks[2] as? TaskDefinitionSendGroupDeletePhotoMessage)
        XCTAssertEqual(expectedGroupID, setPhotoTask.groupID)
        XCTAssertEqual(expectedGroupCreator, setPhotoTask.groupCreatorIdentity)
        XCTAssertEqual(myIdentityStoreMock.identity, setPhotoTask.fromMember)
        XCTAssertEqual(expectedToMember, Set(setPhotoTask.toMembers))
    }
    
    func testSyncUnknownMember() throws {
        // Setup
        
        let myIdentityStoreMock = MyIdentityStoreMock()
        let contactStoreMock = ContactStoreMock(callOnCompletion: true)
        let taskManagerMock = TaskManagerMock()
        let userSettingsMock = UserSettingsMock()
        
        let expectedGroupID: Data = BytesUtility.generateRandomBytes(length: ThreemaProtocol.groupIDLength)!
        let expectedGroupCreator: String = myIdentityStoreMock.identity
        let expectedMembers: Set<String> = ["MEMBER01", "MEMBER02", "MEMBER03"]
        
        let unknownMember = "MEMBER04"
        
        for member in expectedMembers {
            _ = databasePreparer.createContact(
                publicKey: BytesUtility.generateRandomBytes(length: 32)!,
                identity: member,
                verificationLevel: 0
            )
        }
        
        let groupManager = GroupManager(
            myIdentityStoreMock,
            contactStoreMock,
            taskManagerMock,
            userSettingsMock,
            EntityManager(databaseContext: databaseCnx, myIdentityStore: myIdentityStoreMock),
            groupPhotoSenderMock
        )
        
        let grp = try XCTUnwrap(
            createOrUpdateDBWait(
                groupManager: groupManager,
                groupID: expectedGroupID,
                creator: expectedGroupCreator,
                members: expectedMembers
            )
        )

        let expectationSync = expectation(description: "Sync")
        
        // Run
        
        groupManager.sync(group: grp, to: Set([unknownMember]), withoutCreateMessage: false)
            .done {
                expectationSync.fulfill()
            }
            .catch { error in
                XCTFail(error.localizedDescription)
            }
        
        // Validate
        
        waitForExpectations(timeout: 1)

        // A group create message with an empty member list should be synced to a unknown contact
        XCTAssertEqual(1, taskManagerMock.addedTasks.count)
        
        let createMessageTask = try XCTUnwrap(taskManagerMock.addedTasks[0] as? TaskDefinitionSendGroupCreateMessage)
        XCTAssertEqual(expectedGroupID, createMessageTask.groupID)
        XCTAssertEqual(expectedGroupCreator, createMessageTask.groupCreatorIdentity)
        XCTAssertEqual(0, createMessageTask.toMembers.count)
        XCTAssertEqual([unknownMember], createMessageTask.removedMembers)
        XCTAssertEqual(expectedMembers, createMessageTask.members)
    }
    
    func testPeriodicSync() throws {
        // Setup
        
        let myIdentityStoreMock = MyIdentityStoreMock()
        let contactStoreMock = ContactStoreMock(callOnCompletion: true)
        let taskManagerMock = TaskManagerMock()
        let userSettingsMock = UserSettingsMock()
        
        let startDate = Date()
        let expectedGroupID: Data = BytesUtility.generateRandomBytes(length: ThreemaProtocol.groupIDLength)!
        let expectedGroupCreator: String = myIdentityStoreMock.identity
        let expectedMembers: Set<String> = ["MEMBER01", "MEMBER02", "MEMBER03"]
        let expectedPhoto: Data = try XCTUnwrap(Data(contentsOf: ResourceLoader.urlResource("Bild-1-0", "jpg")!))
        
        let expectationPhotoTaskAdded = expectation(description: "Photo task added")
        var taskCount = 0
        taskManagerMock.taskAdded = {
            taskCount += 1
            
            if taskCount == 4 {
                expectationPhotoTaskAdded.fulfill()
            }
        }
        
        for member in expectedMembers {
            _ = databasePreparer.createContact(
                publicKey: BytesUtility.generateRandomBytes(length: 32)!,
                identity: member,
                verificationLevel: 0
            )
        }

        let entityManager = EntityManager(databaseContext: databaseCnx, myIdentityStore: myIdentityStoreMock)
        let groupManager = GroupManager(
            myIdentityStoreMock,
            contactStoreMock,
            taskManagerMock,
            userSettingsMock,
            entityManager,
            groupPhotoSenderMock
        )
        
        let grp = try XCTUnwrap(
            createOrUpdateDBWait(
                groupManager: groupManager,
                groupID: expectedGroupID,
                creator: expectedGroupCreator,
                members: expectedMembers
            )
        )

        entityManager.performSyncBlockAndSafe {
            if let grpEntity = entityManager.entityFetcher.groupEntity(
                for: grp.groupID,
                with: nil
            ) {
                grpEntity.lastPeriodicSync = Date(timeIntervalSinceNow: Double(-kGroupPeriodicSyncInterval))
            }
        }

        // Set photo
        let expectationPhoto = expectation(description: "Set photo")
        groupManager.setPhoto(group: grp, imageData: expectedPhoto, sentDate: Date())
            .done {
                expectationPhoto.fulfill()
            }
            .catch { error in
                XCTFail(error.localizedDescription)
            }
        
        wait(for: [expectationPhoto], timeout: 1)
        
        // Run
        
        groupManager.periodicSyncIfNeeded(for: grp)
        
        // Wait for delayed send photo task
        
        wait(for: [expectationPhotoTaskAdded], timeout: 5)
        
        // Validate
        
        let lastPeriodicSync = try XCTUnwrap(grp.lastPeriodicSync)
        XCTAssertTrue(lastPeriodicSync > startDate)
        
        // SetPhoto, Create, Rename, send photo
        XCTAssertEqual(4, taskManagerMock.addedTasks.count)
        
        let createMessageTask = try XCTUnwrap(taskManagerMock.addedTasks[1] as? TaskDefinitionSendGroupCreateMessage)
        XCTAssertEqual(expectedGroupID, createMessageTask.groupID)
        XCTAssertEqual(expectedGroupCreator, createMessageTask.groupCreatorIdentity)
        XCTAssertEqual(expectedMembers, Set(createMessageTask.toMembers))
        XCTAssertNil(createMessageTask.removedMembers)
        XCTAssertEqual(expectedMembers, createMessageTask.members)
        
        let renameMessageTask = try XCTUnwrap(taskManagerMock.addedTasks[2] as? TaskDefinitionSendGroupRenameMessage)
        XCTAssertEqual(expectedGroupID, renameMessageTask.groupID)
        XCTAssertEqual(expectedGroupCreator, renameMessageTask.groupCreatorIdentity)
        XCTAssertEqual(myIdentityStoreMock.identity, renameMessageTask.fromMember)
        XCTAssertEqual(expectedMembers, Set(renameMessageTask.toMembers))
        XCTAssertNil(renameMessageTask.name)
        
        let setPhotoTask = try XCTUnwrap(taskManagerMock.addedTasks[3] as? TaskDefinitionSendGroupSetPhotoMessage)
        XCTAssertEqual(expectedGroupID, setPhotoTask.groupID)
        XCTAssertEqual(expectedGroupCreator, setPhotoTask.groupCreatorIdentity)
        XCTAssertEqual(myIdentityStoreMock.identity, setPhotoTask.fromMember)
        XCTAssertEqual(expectedMembers, Set(setPhotoTask.toMembers))
        XCTAssertEqual(groupPhotoSenderMock.blobID, setPhotoTask.blobID)
        XCTAssertEqual(groupPhotoSenderMock.encryptionKey, setPhotoTask.encryptionKey)
    }
    
    func testPeriodicSyncWithDelayedPhotoSending() throws {
        // Setup
        
        let myIdentityStoreMock = MyIdentityStoreMock()
        let contactStoreMock = ContactStoreMock(callOnCompletion: true)
        let taskManagerMock = TaskManagerMock()
        let userSettingsMock = UserSettingsMock()
        let delayedGroupPhotoSenderMock = GroupPhotoSenderMock(delay: 5000)
        
        let startDate = Date()
        let expectedGroupID: Data = BytesUtility.generateRandomBytes(length: ThreemaProtocol.groupIDLength)!
        let expectedGroupCreator: String = myIdentityStoreMock.identity
        let expectedMembers: Set<String> = ["MEMBER01", "MEMBER02", "MEMBER03"]
        let expectedPhoto: Data = try XCTUnwrap(Data(contentsOf: ResourceLoader.urlResource("Bild-1-0", "jpg")!))
        
        for member in expectedMembers {
            _ = databasePreparer.createContact(
                publicKey: BytesUtility.generateRandomBytes(length: 32)!,
                identity: member,
                verificationLevel: 0
            )
        }

        let entityManager = EntityManager(databaseContext: databaseCnx, myIdentityStore: myIdentityStoreMock)
        let groupManagerForPreparation = GroupManager(
            myIdentityStoreMock,
            contactStoreMock,
            taskManagerMock,
            userSettingsMock,
            entityManager,
            groupPhotoSenderMock
        )
        
        let grp = try XCTUnwrap(
            createOrUpdateDBWait(
                groupManager: groupManagerForPreparation,
                groupID: expectedGroupID,
                creator: expectedGroupCreator,
                members: expectedMembers
            )
        )

        entityManager.performSyncBlockAndSafe {
            if let grpEntity = entityManager.entityFetcher.groupEntity(
                for: grp.groupID,
                with: nil
            ) {
                grpEntity.lastPeriodicSync = Date(timeIntervalSinceNow: Double(-kGroupPeriodicSyncInterval))
            }
        }
        
        // Set photo
        let expectationPhoto = expectation(description: "Set photo")
        groupManagerForPreparation.setPhoto(group: grp, imageData: expectedPhoto, sentDate: Date())
            .done {
                expectationPhoto.fulfill()
            }
            .catch { error in
                XCTFail(error.localizedDescription)
            }
        
        waitForExpectations(timeout: 1)
        
        let groupManager = GroupManager(
            myIdentityStoreMock,
            contactStoreMock,
            taskManagerMock,
            userSettingsMock,
            EntityManager(databaseContext: databaseCnx, myIdentityStore: myIdentityStoreMock),
            delayedGroupPhotoSenderMock
        )
        
        // Run
        
        groupManager.periodicSyncIfNeeded(for: grp)
        
        // Validate
        
        let lastPeriodicSync = try XCTUnwrap(grp.lastPeriodicSync)
        XCTAssertTrue(lastPeriodicSync > startDate)
        
        // SetPhoto, Create, Rename (photo sending is delayed)
        XCTAssertEqual(3, taskManagerMock.addedTasks.count)
        
        let createMessageTask = try XCTUnwrap(taskManagerMock.addedTasks[1] as? TaskDefinitionSendGroupCreateMessage)
        XCTAssertEqual(expectedGroupID, createMessageTask.groupID)
        XCTAssertEqual(expectedGroupCreator, createMessageTask.groupCreatorIdentity)
        XCTAssertEqual(expectedMembers, Set(createMessageTask.toMembers))
        XCTAssertNil(createMessageTask.removedMembers)
        XCTAssertEqual(expectedMembers, createMessageTask.members)
        
        let renameMessageTask = try XCTUnwrap(taskManagerMock.addedTasks[2] as? TaskDefinitionSendGroupRenameMessage)
        XCTAssertEqual(expectedGroupID, renameMessageTask.groupID)
        XCTAssertEqual(expectedGroupCreator, renameMessageTask.groupCreatorIdentity)
        XCTAssertEqual(myIdentityStoreMock.identity, renameMessageTask.fromMember)
        XCTAssertEqual(expectedMembers, Set(renameMessageTask.toMembers))
        XCTAssertNil(renameMessageTask.name)
    }

    func testPeriodicSyncNoPhoto() throws {
        // Setup

        let myIdentityStoreMock = MyIdentityStoreMock()
        let contactStoreMock = ContactStoreMock(callOnCompletion: true)
        let taskManagerMock = TaskManagerMock()
        let userSettingsMock = UserSettingsMock()
        let delayedGroupPhotoSenderMock = GroupPhotoSenderMock(delay: 5000)

        let startDate = Date()
        let expectedGroupID: Data = BytesUtility.generateRandomBytes(length: ThreemaProtocol.groupIDLength)!
        let expectedGroupCreator: String = myIdentityStoreMock.identity
        let expectedMembers: Set<String> = ["MEMBER01", "MEMBER02", "MEMBER03"]

        for member in expectedMembers {
            _ = databasePreparer.createContact(
                publicKey: BytesUtility.generateRandomBytes(length: 32)!,
                identity: member,
                verificationLevel: 0
            )
        }

        let entityManager = EntityManager(databaseContext: databaseCnx, myIdentityStore: myIdentityStoreMock)
        let groupManager = GroupManager(
            myIdentityStoreMock,
            contactStoreMock,
            taskManagerMock,
            userSettingsMock,
            entityManager,
            delayedGroupPhotoSenderMock
        )

        let grp = try XCTUnwrap(
            createOrUpdateDBWait(
                groupManager: groupManager,
                groupID: expectedGroupID,
                creator: expectedGroupCreator,
                members: expectedMembers
            )
        )

        entityManager.performSyncBlockAndSafe {
            if let grpEntity = entityManager.entityFetcher.groupEntity(
                for: grp.groupID,
                with: nil
            ) {
                grpEntity.lastPeriodicSync = Date(timeIntervalSinceNow: Double(-kGroupPeriodicSyncInterval))
            }
        }

        // Run

        groupManager.periodicSyncIfNeeded(for: grp)

        // Validate

        let lastPeriodicSync = try XCTUnwrap(grp.lastPeriodicSync)
        XCTAssertTrue(lastPeriodicSync > startDate)
        
        // Create, Rename and Delete photo
        XCTAssertEqual(3, taskManagerMock.addedTasks.count)

        let createMessageTask = try XCTUnwrap(taskManagerMock.addedTasks[0] as? TaskDefinitionSendGroupCreateMessage)
        XCTAssertEqual(expectedGroupID, createMessageTask.groupID)
        XCTAssertEqual(expectedGroupCreator, createMessageTask.groupCreatorIdentity)
        XCTAssertEqual(expectedMembers, Set(createMessageTask.toMembers))
        XCTAssertNil(createMessageTask.removedMembers)
        XCTAssertEqual(expectedMembers, createMessageTask.members)

        let renameMessageTask = try XCTUnwrap(taskManagerMock.addedTasks[1] as? TaskDefinitionSendGroupRenameMessage)
        XCTAssertEqual(expectedGroupID, renameMessageTask.groupID)
        XCTAssertEqual(expectedGroupCreator, renameMessageTask.groupCreatorIdentity)
        XCTAssertEqual(myIdentityStoreMock.identity, renameMessageTask.fromMember)
        XCTAssertEqual(expectedMembers, Set(renameMessageTask.toMembers))
        XCTAssertNil(renameMessageTask.name)

        let deleteTask = try XCTUnwrap(taskManagerMock.addedTasks[2] as? TaskDefinitionSendGroupDeletePhotoMessage)
        XCTAssertTrue(expectedGroupID.elementsEqual(deleteTask.groupID!))
        XCTAssertEqual(expectedGroupCreator, deleteTask.groupCreatorIdentity)
        XCTAssertEqual(myIdentityStoreMock.identity, deleteTask.fromMember)
        XCTAssertEqual(expectedMembers, Set(deleteTask.toMembers))
    }
    
    func testPeriodicSyncNotNeeded() throws {
        // Setup

        let myIdentityStoreMock = MyIdentityStoreMock()
        let contactStoreMock = ContactStoreMock(callOnCompletion: true)
        let taskManagerMock = TaskManagerMock()
        let userSettingsMock = UserSettingsMock()
        let delayedGroupPhotoSenderMock = GroupPhotoSenderMock(delay: 5000)

        let lastPeriodicSync = Date(timeIntervalSinceNow: -24 * 60 * 60) // One day in the past
        let expectedGroupID: Data = BytesUtility.generateRandomBytes(length: ThreemaProtocol.groupIDLength)!
        let expectedGroupCreator: String = myIdentityStoreMock.identity
        let expectedMembers: Set<String> = ["MEMBER01", "MEMBER02", "MEMBER03"]

        for member in expectedMembers {
            _ = databasePreparer.createContact(
                publicKey: BytesUtility.generateRandomBytes(length: 32)!,
                identity: member,
                verificationLevel: 0
            )
        }

        let entityManager = EntityManager(databaseContext: databaseCnx, myIdentityStore: myIdentityStoreMock)
        let groupManager = GroupManager(
            myIdentityStoreMock,
            contactStoreMock,
            taskManagerMock,
            userSettingsMock,
            entityManager,
            delayedGroupPhotoSenderMock
        )
        let grp = try XCTUnwrap(
            createOrUpdateDBWait(
                groupManager: groupManager,
                groupID: expectedGroupID,
                creator: expectedGroupCreator,
                members: expectedMembers
            )
        )

        entityManager.performSyncBlockAndSafe {
            if let grpEntity = entityManager.entityFetcher.groupEntity(
                for: grp.groupID,
                with: nil
            ) {
                grpEntity.lastPeriodicSync = lastPeriodicSync
            }
        }

        // Run

        groupManager.periodicSyncIfNeeded(for: grp)

        // Validate

        let actualLastPeriodicSync = try XCTUnwrap(grp.lastPeriodicSync)
        XCTAssertEqual(lastPeriodicSync, actualLastPeriodicSync)

        XCTAssertEqual(0, taskManagerMock.addedTasks.count)
    }
    
    func testGetGroupImCreator() throws {
        let myIdentityStoreMock = MyIdentityStoreMock()
        let contactStoreMock = ContactStoreMock(callOnCompletion: true)
        let taskManagerMock = TaskManagerMock()
        let userSettingsMock = UserSettingsMock()
        
        let expectedGroupID: Data = BytesUtility.generateRandomBytes(length: ThreemaProtocol.groupIDLength)!
        let expectedGroupCreator: String = myIdentityStoreMock.identity
        let expectedMembers: Set<String> = ["MEMBER01", "MEMBER02", "MEMBER03"]
        
        for member in expectedMembers {
            _ = databasePreparer.createContact(
                publicKey: BytesUtility.generateRandomBytes(length: 32)!,
                identity: member,
                verificationLevel: 0
            )
        }
        
        let groupManager = GroupManager(
            myIdentityStoreMock,
            contactStoreMock,
            taskManagerMock,
            userSettingsMock,
            EntityManager(databaseContext: databaseCnx, myIdentityStore: myIdentityStoreMock),
            groupPhotoSenderMock
        )
        
        let expectedGroup = try XCTUnwrap(
            createOrUpdateDBWait(
                groupManager: groupManager,
                groupID: expectedGroupID,
                creator: expectedGroupCreator,
                members: expectedMembers
            )
        )

        let actualGroup = try XCTUnwrap(
            groupManager
                .getGroup(expectedGroupID, creator: expectedGroupCreator)
        )
        
        XCTAssertEqual(actualGroup.groupID, expectedGroupID)
        XCTAssertEqual(actualGroup.groupCreatorIdentity, expectedGroupCreator)
        XCTAssertEqual(actualGroup.conversation, expectedGroup.conversation)
    }
    
    func testGetGroupOtherCreator() throws {
        let myIdentityStoreMock = MyIdentityStoreMock()
        let contactStoreMock = ContactStoreMock(callOnCompletion: true)
        let taskManagerMock = TaskManagerMock()
        let userSettingsMock = UserSettingsMock()
        
        let expectedGroupID: Data = BytesUtility.generateRandomBytes(length: ThreemaProtocol.groupIDLength)!
        let expectedGroupCreator = "MEMBER01"
        let expectedMembers: Set<String> = [myIdentityStoreMock.identity, "MEMBER01", "MEMBER02", "MEMBER03"]
        
        for member in expectedMembers {
            _ = databasePreparer.createContact(
                publicKey: BytesUtility.generateRandomBytes(length: 32)!,
                identity: member,
                verificationLevel: 0
            )
        }
        
        let groupManager = GroupManager(
            myIdentityStoreMock,
            contactStoreMock,
            taskManagerMock,
            userSettingsMock,
            EntityManager(databaseContext: databaseCnx, myIdentityStore: myIdentityStoreMock),
            groupPhotoSenderMock
        )
        
        let expectedGroup = try XCTUnwrap(
            createOrUpdateDBWait(
                groupManager: groupManager,
                groupID: expectedGroupID,
                creator: expectedGroupCreator,
                members: expectedMembers
            )
        )

        let actualGroup = try XCTUnwrap(
            groupManager
                .getGroup(expectedGroupID, creator: expectedGroupCreator)
        )

        XCTAssertEqual(actualGroup.groupID, expectedGroupID)
        XCTAssertEqual(actualGroup.groupCreatorIdentity, expectedGroupCreator)
        XCTAssertEqual(actualGroup.conversation, expectedGroup.conversation)
    }
    
    func testAddMemberToGroupWithOpenBallot() throws {
        let myIdentityStoreMock = MyIdentityStoreMock()
        let contactStoreMock = ContactStoreMock(callOnCompletion: true)
        let taskManagerMock = TaskManagerMock()
        let userSettingsMock = UserSettingsMock()
        
        let expectedGroupID: Data = BytesUtility.generateRandomBytes(length: ThreemaProtocol.groupIDLength)!
        let expectedGroupCreator: String = myIdentityStoreMock.identity
        
        let initialMembers: Set<String> = ["MEMBER01", "MEMBER02"]
        let newMember = "MEMBER03"
        let expectedMembers = initialMembers.union(Set([newMember]))
        
        // Setup stuff
        
        for member in expectedMembers {
            _ = databasePreparer.createContact(
                publicKey: BytesUtility.generateRandomBytes(length: 32)!,
                identity: member,
                verificationLevel: 0
            )
        }
        
        let groupManager = GroupManager(
            myIdentityStoreMock,
            contactStoreMock,
            taskManagerMock,
            userSettingsMock,
            EntityManager(databaseContext: databaseCnx, myIdentityStore: myIdentityStoreMock),
            groupPhotoSenderMock
        )
        
        let group = try XCTUnwrap(
            createOrUpdateDBWait(
                groupManager: groupManager,
                groupID: expectedGroupID,
                creator: expectedGroupCreator,
                members: initialMembers
            )
        )

        // Add open ballot
        
        var ballot: Ballot!
        databasePreparer.save {
            ballot = databasePreparer.createBallotMessage(
                conversation: group.conversation,
                ballotID: BytesUtility.generateRandomBytes(length: ThreemaProtocol.ballotIDLength)!
            )
            ballot.creatorID = myIdentityStoreMock.identity
            ballot.state = NSNumber(integerLiteral: kBallotStateOpen)
        }
        
        // Test
        
        var resultGroup: Group?
        var resultNewMembers: Set<String>?
        var resultError: Error?
        
        let expec = expectation(description: "Group update with ballots")
        
        groupManager.createOrUpdate(
            groupID: expectedGroupID,
            creator: expectedGroupCreator,
            members: expectedMembers,
            systemMessageDate: Date()
        )
        .done { grp, newMembers in
            resultGroup = grp
            resultNewMembers = newMembers

            expec.fulfill()
        }
        .catch { error in
            resultError = error

            expec.fulfill()
        }

        waitForExpectations(timeout: 1)
             
        if let error = resultError {
            XCTFail(error.localizedDescription)
        }
        else {
            XCTAssertNil(resultError)
            XCTAssertNotNil(resultGroup)
            XCTAssertEqual(resultGroup?.groupID, expectedGroupID)
            XCTAssertEqual(resultGroup?.groupCreatorIdentity, expectedGroupCreator)
            XCTAssertEqual(resultGroup?.allMemberIdentities.count, expectedMembers.count + 1)
            XCTAssertTrue(resultGroup!.allMemberIdentities.contains(myIdentityStoreMock.identity))
            XCTAssertTrue(resultNewMembers!.contains(newMember))
            // Allow MyIdentity injection in the future for `Ballot` to actually create send
            // message tasks and check for them here
        }
    }
    
    func testCreateNoteGroup() {
        let myIdentityStoreMock = MyIdentityStoreMock()
        let contactStoreMock = ContactStoreMock(callOnCompletion: true)
        let taskManagerMock = TaskManagerMock()
        let userSettingsMock = UserSettingsMock()
        let entityManager = EntityManager(databaseContext: databaseCnx, myIdentityStore: myIdentityStoreMock)
        
        let expectedGroupID: Data = BytesUtility.generateRandomBytes(length: ThreemaProtocol.groupIDLength)!
        let expectedGroupCreator: String = myIdentityStoreMock.identity
        
        let groupManager = GroupManager(
            myIdentityStoreMock,
            contactStoreMock,
            taskManagerMock,
            userSettingsMock,
            entityManager,
            groupPhotoSenderMock
        )
        
        let grp = createOrUpdateDBWait(
            groupManager: groupManager,
            groupID: expectedGroupID,
            creator: expectedGroupCreator,
            members: []
        )
        
        XCTAssertNotNil(grp)
        XCTAssertEqual(grp?.groupID, expectedGroupID)
        
        let conversation = entityManager.entityFetcher.conversation(for: grp!.groupID)
        
        XCTAssertNotNil(conversation)
        
        let messageFetcher = MessageFetcher(for: conversation!, with: entityManager)
        let lastMessage: SystemMessage = messageFetcher.lastMessage() as! SystemMessage
        
        XCTAssertNotNil(grp)
        XCTAssertEqual(grp?.groupID, expectedGroupID)
        XCTAssertEqual(grp?.groupCreatorIdentity, expectedGroupCreator)
        XCTAssertEqual(grp?.allMemberIdentities.count, 1)
        XCTAssertTrue(grp?.allMemberIdentities.contains(myIdentityStoreMock.identity) ?? false)
        XCTAssertNil(grp?.lastSyncRequest)
        XCTAssertEqual(lastMessage.type, NSNumber(value: kSystemMessageStartNoteGroupInfo))
    }
    
    func testAddMemberToNoteGroup() {
        let myIdentityStoreMock = MyIdentityStoreMock()
        let contactStoreMock = ContactStoreMock(callOnCompletion: true)
        let taskManagerMock = TaskManagerMock()
        let userSettingsMock = UserSettingsMock()
        let entityManager = EntityManager(databaseContext: databaseCnx, myIdentityStore: myIdentityStoreMock)
        
        let expectedGroupID: Data = BytesUtility.generateRandomBytes(length: ThreemaProtocol.groupIDLength)!
        let expectedGroupCreator: String = myIdentityStoreMock.identity
        
        let groupManager = GroupManager(
            myIdentityStoreMock,
            contactStoreMock,
            taskManagerMock,
            userSettingsMock,
            entityManager,
            groupPhotoSenderMock
        )
        createOrUpdateDBWait(
            groupManager: groupManager,
            groupID: expectedGroupID,
            creator: expectedGroupCreator,
            members: []
        )
        
        let expectedNewMembers: Set<String> = ["MEMBER01"]
        for member in expectedNewMembers {
            _ = databasePreparer.createContact(
                publicKey: BytesUtility.generateRandomBytes(length: 32)!,
                identity: member,
                verificationLevel: 0
            )
        }
        let grp = createOrUpdateDBWait(
            groupManager: groupManager,
            groupID: expectedGroupID,
            creator: expectedGroupCreator,
            members: expectedNewMembers
        )
        XCTAssertNotNil(grp)
        
        let conversation = entityManager.entityFetcher.conversation(for: grp!.groupID)
        XCTAssertNotNil(conversation)
        
        let messageFetcher = MessageFetcher(for: conversation!, with: entityManager)
        var endNoteGroupInfoCount = 0
        for message in messageFetcher.messages(at: 0, count: messageFetcher.count()) {
            if let tmpMessage = message as? SystemMessage,
               tmpMessage.type.isEqual(to: NSNumber(value: kSystemMessageEndNoteGroupInfo)) {
                endNoteGroupInfoCount += 1
            }
        }
        
        XCTAssertEqual(grp?.groupID, expectedGroupID)
        XCTAssertEqual(grp?.groupCreatorIdentity, expectedGroupCreator)
        XCTAssertEqual(grp?.allMemberIdentities.count, expectedNewMembers.count + 1)
        XCTAssertTrue(grp?.allMemberIdentities.contains(myIdentityStoreMock.identity) ?? false)
        XCTAssertNil(grp?.lastSyncRequest)
        XCTAssertEqual(endNoteGroupInfoCount, 1)
    }
    
    func testRemoveMemberFromNoteGroup() {
        let myIdentityStoreMock = MyIdentityStoreMock()
        let contactStoreMock = ContactStoreMock(callOnCompletion: true)
        let taskManagerMock = TaskManagerMock()
        let userSettingsMock = UserSettingsMock()
        let entityManager = EntityManager(databaseContext: databaseCnx, myIdentityStore: myIdentityStoreMock)
        
        let expectedGroupID: Data = BytesUtility.generateRandomBytes(length: ThreemaProtocol.groupIDLength)!
        let expectedGroupCreator: String = myIdentityStoreMock.identity
        
        let expectedMembers: Set<String> = ["MEMBER01"]
        
        for member in expectedMembers {
            _ = databasePreparer.createContact(
                publicKey: BytesUtility.generateRandomBytes(length: 32)!,
                identity: member,
                verificationLevel: 0
            )
        }
        
        let groupManager = GroupManager(
            myIdentityStoreMock,
            contactStoreMock,
            taskManagerMock,
            userSettingsMock,
            entityManager,
            groupPhotoSenderMock
        )
        createOrUpdateDBWait(
            groupManager: groupManager,
            groupID: expectedGroupID,
            creator: expectedGroupCreator,
            members: expectedMembers
        )
        let grp = createOrUpdateDBWait(
            groupManager: groupManager,
            groupID: expectedGroupID,
            creator: expectedGroupCreator,
            members: []
        )
        XCTAssertNotNil(grp)
        
        let conversation = entityManager.entityFetcher.conversation(for: grp!.groupID)
        XCTAssertNotNil(conversation)
        
        let messageFetcher = MessageFetcher(for: conversation!, with: entityManager)
        var startNoteGroupInfoCount = 0
        for message in messageFetcher.messages(at: 0, count: messageFetcher.count()) {
            if let tmpMessage = message as? SystemMessage,
               tmpMessage.type.isEqual(to: NSNumber(value: kSystemMessageStartNoteGroupInfo)) {
                startNoteGroupInfoCount += 1
            }
        }
        
        XCTAssertEqual(grp?.groupID, expectedGroupID)
        XCTAssertEqual(grp?.groupCreatorIdentity, expectedGroupCreator)
        XCTAssertEqual(grp?.allMemberIdentities.count, 1)
        XCTAssertTrue(grp?.allMemberIdentities.contains(myIdentityStoreMock.identity) ?? false)
        XCTAssertNil(grp?.lastSyncRequest)
        XCTAssertEqual(startNoteGroupInfoCount, 1)
    }
    
    func testAddAndRemoveMemberFromNoteGroup() {
        let myIdentityStoreMock = MyIdentityStoreMock()
        let contactStoreMock = ContactStoreMock(callOnCompletion: true)
        let taskManagerMock = TaskManagerMock()
        let userSettingsMock = UserSettingsMock()
        let entityManager = EntityManager(databaseContext: databaseCnx, myIdentityStore: myIdentityStoreMock)

        let expectedGroupID: Data = BytesUtility.generateRandomBytes(length: ThreemaProtocol.groupIDLength)!
        let expectedGroupCreator: String = myIdentityStoreMock.identity
        
        let groupManager = GroupManager(
            myIdentityStoreMock,
            contactStoreMock,
            taskManagerMock,
            userSettingsMock,
            entityManager,
            groupPhotoSenderMock
        )
        createOrUpdateDBWait(
            groupManager: groupManager,
            groupID: expectedGroupID,
            creator: expectedGroupCreator,
            members: []
        )
        
        let expectedNewMembers: Set<String> = ["MEMBER01"]
        for member in expectedNewMembers {
            _ = databasePreparer.createContact(
                publicKey: BytesUtility.generateRandomBytes(length: 32)!,
                identity: member,
                verificationLevel: 0
            )
        }
        createOrUpdateDBWait(
            groupManager: groupManager,
            groupID: expectedGroupID,
            creator: expectedGroupCreator,
            members: expectedNewMembers
        )
        let grp = createOrUpdateDBWait(
            groupManager: groupManager,
            groupID: expectedGroupID,
            creator: expectedGroupCreator,
            members: []
        )
        XCTAssertNotNil(grp)
        
        let conversation = entityManager.entityFetcher.conversation(for: grp!.groupID)
        XCTAssertNotNil(conversation)
        
        let messageFetcher = MessageFetcher(for: conversation!, with: entityManager)
        var startNoteGroupInfoCount = 0
        var endNoteGroupInfoCount = 0
        for message in messageFetcher.messages(at: 0, count: messageFetcher.count()) {
            if let tmpMessage = message as? SystemMessage {
                switch tmpMessage.type.intValue {
                case kSystemMessageStartNoteGroupInfo:
                    startNoteGroupInfoCount += 1
                case kSystemMessageEndNoteGroupInfo:
                    endNoteGroupInfoCount += 1
                default: break
                }
            }
        }
        
        XCTAssertEqual(grp?.groupID, expectedGroupID)
        XCTAssertEqual(grp?.groupCreatorIdentity, expectedGroupCreator)
        XCTAssertEqual(grp?.allMemberIdentities.count, 1)
        XCTAssertTrue(grp?.allMemberIdentities.contains(myIdentityStoreMock.identity) ?? false)
        XCTAssertNil(grp?.lastSyncRequest)
        XCTAssertEqual(startNoteGroupInfoCount, 2)
        XCTAssertEqual(endNoteGroupInfoCount, 1)
    }
    
    func testAddUnknownGroupToAlertList() {
        let myIdentityStoreMock = MyIdentityStoreMock()
        let contactStoreMock = ContactStoreMock(callOnCompletion: true)
        let taskManagerMock = TaskManagerMock()
        let userSettingsMock = UserSettingsMock()
        
        let expectedGroupID: Data = BytesUtility.generateRandomBytes(length: ThreemaProtocol.groupIDLength)!
        let expectedGroupCreator: String = myIdentityStoreMock.identity
        
        let groupManager = GroupManager(
            myIdentityStoreMock,
            contactStoreMock,
            taskManagerMock,
            userSettingsMock,
            EntityManager(databaseContext: databaseCnx, myIdentityStore: myIdentityStoreMock),
            groupPhotoSenderMock
        )
        
        groupManager.unknownGroup(groupID: expectedGroupID, creator: expectedGroupCreator)
        
        let expec = XCTestExpectation(description: "Wait till alert is added to the list after 5 seconds")
        Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { _ in
            expec.fulfill()
        }
        wait(for: [expec], timeout: 10.0, enforceOrder: false)
        
        let unknownGroupAlertList = userSettingsMock.unknownGroupAlertList!
        let groupDict = ["groupid": expectedGroupID, "creator": expectedGroupCreator] as [String: AnyHashable]
        XCTAssertTrue(unknownGroupAlertList.map { $0 as! [String: AnyHashable] == groupDict }.contains(true))
    }
    
    func testRemoveUnknownGroupFromAlertList() {
        let myIdentityStoreMock = MyIdentityStoreMock()
        let contactStoreMock = ContactStoreMock(callOnCompletion: true)
        let taskManagerMock = TaskManagerMock()
        let userSettingsMock = UserSettingsMock()
        
        let expectedGroupID: Data = BytesUtility.generateRandomBytes(length: ThreemaProtocol.groupIDLength)!
        let expectedGroupCreator: String = myIdentityStoreMock.identity
        
        let groupManager = GroupManager(
            myIdentityStoreMock,
            contactStoreMock,
            taskManagerMock,
            userSettingsMock,
            EntityManager(databaseContext: databaseCnx, myIdentityStore: myIdentityStoreMock),
            groupPhotoSenderMock
        )
        
        groupManager.unknownGroup(groupID: expectedGroupID, creator: expectedGroupCreator)
        
        let expec = XCTestExpectation(description: "Wait till alert is added to the list after 5 seconds")
        Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { _ in
            expec.fulfill()
        }
        wait(for: [expec], timeout: 10.0, enforceOrder: false)
        
        createOrUpdateDBWait(
            groupManager: groupManager,
            groupID: expectedGroupID,
            creator: expectedGroupCreator,
            members: []
        )
        let unknownGroupAlertList = userSettingsMock.unknownGroupAlertList!
        let groupDict = ["groupid": expectedGroupID, "creator": expectedGroupCreator] as [String: AnyHashable]
        XCTAssertFalse(unknownGroupAlertList.map { $0 as! [String: AnyHashable] == groupDict }.contains(true))
    }

    func testCreateOrUpdateBlockUnknownContact() throws {
        let myIdentityStoreMock = MyIdentityStoreMock()

        let userSettingsMock = UserSettingsMock()
        userSettingsMock.blockUnknown = true

        let errorBlockUnknown = NSError(domain: "ThreemaErrorDomain", code: Int(kBlockUnknownContactErrorCode))
        let contactStoreMock = ContactStoreMock(callOnCompletion: true, nil, errorHandler: errorBlockUnknown)

        let taskManagerMock = TaskManagerMock()

        let expectedGroupID: Data = BytesUtility.generateRandomBytes(length: ThreemaProtocol.groupIDLength)!
        let expectedGroupCreator = "CREATOR01"
        let expectedGroupMembers = Set(["MEMBER01", "MEMBER02", "MEMBER03", myIdentityStoreMock.identity])

        databasePreparer.save {
            databasePreparer.createContact(
                publicKey: BytesUtility.generateRandomBytes(length: 32)!,
                identity: expectedGroupCreator,
                verificationLevel: 0
            )

            databasePreparer.createContact(
                publicKey: BytesUtility.generateRandomBytes(length: 32)!,
                identity: "MEMBER02",
                verificationLevel: 0
            )
        }

        let groupManager = GroupManager(
            myIdentityStoreMock,
            contactStoreMock,
            taskManagerMock,
            userSettingsMock,
            EntityManager(databaseContext: databaseCnx, myIdentityStore: myIdentityStoreMock),
            groupPhotoSenderMock
        )

        let expec = expectation(description: "Group create")

        var result: Group?
        groupManager.createOrUpdateDB(
            groupID: expectedGroupID,
            creator: expectedGroupCreator,
            members: expectedGroupMembers,
            systemMessageDate: nil
        )
        .done { group in
            result = group
            expec.fulfill()
        }
        .catch { error in
            XCTFail("\(error)")
        }

        wait(for: [expec], timeout: 60)

        let group = try XCTUnwrap(result)
        XCTAssertEqual(3, group.numberOfMembers)
    }

    /// Create or update group in DB and wait until finished.
    @discardableResult private func createOrUpdateDBWait(
        groupManager: GroupManagerProtocol,
        groupID: Data,
        creator: String,
        members: Set<String>
    ) -> Group? {
        var group: Group?

        let expec = expectation(description: "Group create or update")

        groupManager.createOrUpdateDB(
            groupID: groupID,
            creator: creator,
            members: members,
            systemMessageDate: Date()
        )
        .done { grp in
            group = grp
            expec.fulfill()
        }
        .catch { _ in
            expec.fulfill()
        }

        wait(for: [expec], timeout: 30)

        return group
    }
}
