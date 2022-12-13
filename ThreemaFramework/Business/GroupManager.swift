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

import CocoaLumberjackSwift
import Foundation
import PromiseKit

public class GroupManager: NSObject, GroupManagerProtocol {
    
    public enum GroupError: Error {
        case creatorNotFound
        case membersMissing
        case groupConversationNotFound
        case groupNotFound
        case decodingFailed
        case blobIDOrKeyMissing
        case photoUploadFailed
        case notCreator
        case contactForCreatorMissing
        case contactForMemberMissing
    }
    
    /// Used for error handling when fetching unknown contacts
    private enum FetchedContactOrError: Equatable {
        case added
        case revokedOrInvalid(String)
        case blocked(String)
        case localNotFound
        case error
    }
    
    private let myIdentityStore: MyIdentityStoreProtocol
    private let contactStore: ContactStoreProtocol
    private let taskManager: TaskManagerProtocol
    private let userSettings: UserSettingsProtocol
    private let entityManager: EntityManager
    private let groupPhotoSender: GroupPhotoSenderProtocol
    
    init(
        _ myIdentityStore: MyIdentityStoreProtocol,
        _ contactStore: ContactStoreProtocol,
        _ taskManager: TaskManagerProtocol,
        _ userSettings: UserSettingsProtocol,
        _ entityManager: EntityManager,
        _ groupPhotoSender: GroupPhotoSenderProtocol
    ) {
        self.myIdentityStore = myIdentityStore
        self.contactStore = contactStore
        self.taskManager = taskManager
        self.userSettings = userSettings
        self.entityManager = entityManager
        self.groupPhotoSender = groupPhotoSender
    }
    
    @objc public convenience init(entityManager: EntityManager) {
        self.init(
            MyIdentityStore.shared(),
            ContactStore.shared(),
            TaskManager(),
            UserSettings.shared(),
            entityManager,
            GroupPhotoSender()
        )
    }
    
    override public convenience init() {
        self.init(
            MyIdentityStore.shared(),
            ContactStore.shared(),
            TaskManager(),
            UserSettings.shared(),
            EntityManager(),
            GroupPhotoSender()
        )
    }
    
    // MARK: - Create or update
    
    /// Create or update group members and send group create messages to members, if I'm the creator.
    ///
    /// Also sends ballot messages to new members, if necessary.
    ///
    /// - Parameters:
    ///   - groupID: ID (8 bytes) of the group, unique with creator
    ///   - creator: Creator (identity) of the group, unique with ID
    ///   - members: Members (identity list) of the group
    ///   - systemMessageDate: Date for new system message(s)
    /// - Returns: Group and list of new members (identity)
    /// - Throws: ThreemaError, GroupError.notCreator, TaskManagerError
    public func createOrUpdate(
        groupID: Data,
        creator: String,
        members: Set<String>,
        systemMessageDate: Date
    ) -> Promise<(Group, Set<String>?)> {

        guard creator.elementsEqual(myIdentityStore.identity) else {
            return Promise(error: GroupError.notCreator)
        }
        
        removeUnknownGroupFromAlertList(groupID: groupID, creator: creator)

        var oldMembers = [String]()
        var removedMembers = [String]()

        // If group already exists get old and removed members
        entityManager.performBlockAndWait {
            if let oldConversation = self.getConversation(for: GroupIdentity(id: groupID, creator: creator)) {
                oldMembers = oldConversation.members.map(\.identity)
                removedMembers = oldMembers.filter { !members.contains($0) }
            }
        }

        return createOrUpdateDB(
            groupID: groupID,
            creator: creator,
            members: members,
            systemMessageDate: systemMessageDate
        ).then { group -> Promise<(Group, Set<String>?)> in
            guard let group = group else {
                return Promise(error: GroupError.groupNotFound)
            }

            var newMembers: Set<String>?
            self.entityManager.performBlockAndWait {
                if !oldMembers.isEmpty,
                   let conversation = self
                   .getConversation(for: GroupIdentity(id: group.groupID, creator: group.groupCreatorIdentity)) {
                    newMembers = Set(
                        conversation.members
                            .filter { !oldMembers.contains($0.identity) }
                            .map(\.identity)
                    )
                    if newMembers?.isEmpty == true {
                        newMembers = nil
                    }
                }
            }

            if creator.elementsEqual(self.myIdentityStore.identity) {
                // Send group create message to each active member
                let task = TaskDefinitionSendGroupCreateMessage(
                    group: group,
                    to: group.allActiveMemberIdentitiesWithoutCreator,
                    removed: removedMembers,
                    members: members
                )

                self.taskManager.add(taskDefinition: task) { _, error in
                    if error == nil {
                        self.sendGroupBallotIsNotClosed(group, newMembers)
                    }
                }
            }
            else {
                self.sendGroupBallotIsNotClosed(group, newMembers)
            }

            return Promise { $0.fulfill((group, newMembers)) }
        }
    }

    /// Objective-c bridge
    @objc public func createOrUpdateObjc(
        groupID: Data,
        creator: String,
        members: Set<String>,
        systemMessageDate: Date,
        completionHandler: @escaping (Group, Set<String>?) -> Void,
        errorHandler: @escaping (Error?) -> Void
    ) {
        createOrUpdate(groupID: groupID, creator: creator, members: members, systemMessageDate: systemMessageDate)
            .done { group, newMembers in
                completionHandler(group, newMembers)
            }
            .catch { error in
                errorHandler(error)
            }
    }

    /// Create or update group members in DB.
    /// - Parameters:
    ///   - groupID: ID (8 bytes) of the group, unique with creator
    ///   - creator: Creator (identity) of the group, unique with ID
    ///   - members: Members (identity list) of the group
    ///   - systemMessageDate: Date for new system message(s), if `nil` no message is posted
    /// - Returns: Created or updated group or is Nil when group is deleted
    /// - Throws: GroupError.contactForCreatorMissing, GroupError.contactForMemberMissing
    public func createOrUpdateDB(
        groupID: Data,
        creator: String,
        members: Set<String>,
        systemMessageDate: Date?
    ) -> Promise<Group?> {
        if !creator.elementsEqual(myIdentityStore.identity) {
            // Record a pseudo sync request so we won't trigger another one if we process
            // messages in this new group while we are still processing the group create
            recordSendSyncRequest(groupID, creator)
        }

        // Am I the creator? Then Conversation.contact and GroupEntity.groupCreator have to be `nil`.
        var creatorContact: Contact?
        if !creator.elementsEqual(myIdentityStore.identity) {

            // If the creator blocked and group not found, then send leave messages to sender and all provided members
            if userSettings.blacklist.contains(creator),
               getGroup(groupID, creator: creator) == nil {
                if members.contains(myIdentityStore.identity) {
                    var toMembers = [String](members)
                    if !toMembers.contains(creator) {
                        toMembers.append(creator)
                    }

                    leave(groupID: groupID, creator: creator, toMembers: toMembers)
                }

                return Promise { $0.fulfill(nil) }
            }

            creatorContact = entityManager.entityFetcher.contact(for: creator)
            guard creatorContact != nil else {
                return Promise(error: GroupError.contactForCreatorMissing)
            }
        }

        removeUnknownGroupFromAlertList(groupID: groupID, creator: creator)

        var group: Group?

        // Adjust group members and group state
        var allMembers = Set<String>(members)
        if !allMembers.contains(creator) {
            allMembers.insert(creator)
        }

        if allMembers.contains(myIdentityStore.identity) {
            // I'm member of this group
            var groupNewCreated = false

            // First fetch all contacts
            var identitiesToFetch = [String]()
            entityManager.performBlockAndWait {
                for member in members.filter({ $0 != self.myIdentityStore.identity }) {
                    if self.entityManager.entityFetcher.contact(for: member) == nil {
                        identitiesToFetch.append(member)
                    }
                }
            }
            
            return fetchContacts(identities: identitiesToFetch).then { fetchedIdentities in
                when(fulfilled: fetchedIdentities).then { fetchedIdentities -> Promise<Group?> in
                    var internalError: Error?

                    self.entityManager.performSyncBlockAndSafe {
                        let conversation: Conversation
                        if let existingConversation = self.entityManager.entityFetcher.conversation(
                            for: groupID,
                            creator: creator
                        ) {
                            conversation = existingConversation
                        }
                        else {
                            conversation = self.entityManager.entityCreator.conversation()
                            conversation.groupID = groupID
                            conversation.contact = creatorContact
                            conversation.groupMyIdentity = self.myIdentityStore.identity
                        }

                        let groupEntity: GroupEntity
                        if let existingGroup = self.entityManager.entityFetcher.groupEntity(for: conversation) {
                            groupEntity = existingGroup
                        }
                        else {
                            groupEntity = self.entityManager.entityCreator.groupEntity()
                            groupEntity.groupID = groupID
                            groupEntity.groupCreator = creatorContact != nil ? creator : nil
                            groupEntity.state = NSNumber(value: GroupState.active.rawValue)
                            groupNewCreated = true
                        }
                        groupEntity.lastPeriodicSync = Date()

                        let currentMembers: [String] = conversation.members.map(\.identity)

                        // I am member of this group, set group state active
                        if groupEntity.state != NSNumber(value: GroupState.active.rawValue) {
                            groupEntity.state = NSNumber(value: GroupState.active.rawValue)

                            if let systemMessageDate = systemMessageDate {
                                self.postSystemMessage(
                                    in: conversation,
                                    type: kSystemMessageGroupSelfAdded,
                                    arg: nil,
                                    date: systemMessageDate
                                )
                            }
                        }

                        // My ID should be set on active group conversation (could be an old ID e.g. after restored a backup)
                        if let groupMyIdentity = conversation.groupMyIdentity,
                           !groupMyIdentity.elementsEqual(self.myIdentityStore.identity) {
                            conversation.groupMyIdentity = self.myIdentityStore.identity
                        }

                        // Remove deleted members
                        for memberIdentity in currentMembers {
                            guard !allMembers.contains(memberIdentity) else {
                                continue
                            }

                            if let memberContact = self.entityManager.entityFetcher.contact(for: memberIdentity) {
                                conversation.removeMembersObject(memberContact)

                                if let systemMessageDate = systemMessageDate {
                                    self.postSystemMessage(
                                        in: conversation,
                                        member: memberContact,
                                        type: kSystemMessageGroupMemberForcedLeave,
                                        date: systemMessageDate
                                    )
                                }
                            }
                        }
                        
                        // Add new members
                        for memberIdentity in allMembers {
                            guard !currentMembers.contains(memberIdentity),
                                  !memberIdentity.elementsEqual(self.myIdentityStore.identity) else {
                                continue
                            }

                            guard let contact = self.entityManager.entityFetcher.contact(for: memberIdentity) else {
                                let isIdentityRevoked = fetchedIdentities.contains { contactState in
                                    if case .revokedOrInvalid(memberIdentity) = contactState {
                                        return true
                                    }
                                    else if case .blocked(memberIdentity) = contactState {
                                        return true
                                    }
                                    return false
                                }
                                if isIdentityRevoked {
                                    // Do nothing because the contact never existed or was revoked or blocked
                                    DDLogVerbose("Skip invalid, revoked or blocked contact")
                                    continue
                                }
                                else {
                                    internalError = GroupError.contactForMemberMissing
                                    return
                                }
                            }

                            conversation.addMembersObject(contact)

                            if let systemMessageDate = systemMessageDate {
                                self.postSystemMessage(
                                    in: conversation,
                                    member: contact,
                                    type: kSystemMessageGroupMemberAdd,
                                    date: systemMessageDate
                                )
                            }
                        }

                        if creator.elementsEqual(self.myIdentityStore.identity) {
                            // Check is note group or not anymore
                            if allMembers.count == 1, allMembers.contains(self.myIdentityStore.identity) {
                                self.postSystemMessage(
                                    in: conversation,
                                    type: kSystemMessageStartNoteGroupInfo,
                                    arg: nil,
                                    date: Date()
                                )
                            }
                            else if !groupNewCreated, allMembers.count > 1, currentMembers.isEmpty {
                                self.postSystemMessage(
                                    in: conversation,
                                    type: kSystemMessageEndNoteGroupInfo,
                                    arg: nil,
                                    date: Date()
                                )
                            }
                        }

                        let lastSyncRequestSince = Date(timeIntervalSinceNow: TimeInterval(-kGroupSyncRequestInterval))
                        let lastSyncRequest = self.entityManager.entityFetcher.lastGroupSyncRequest(
                            for: groupID,
                            groupCreator: creator,
                            since: lastSyncRequestSince
                        )

                        group = Group(
                            myIdentityStore: self.myIdentityStore,
                            userSettings: self.userSettings,
                            groupEntity: groupEntity,
                            conversation: conversation,
                            lastSyncRequest: lastSyncRequest?.lastSyncRequest
                        )
                    }

                    if let internalError = internalError {
                        return Promise(error: internalError)
                    }

                    return Promise { $0.fulfill(group) }
                }
            }
        }
        else {
            if !creator.elementsEqual(myIdentityStore.identity) {
                entityManager.performSyncBlockAndSafe {
                    if let groupEntity = self.entityManager.entityFetcher.groupEntity(
                        for: groupID,
                        with: creator
                    ) {
                        var addSystemMessage = false

                        if groupEntity.state != NSNumber(value: GroupState.forcedLeft.rawValue) {
                            groupEntity.state = NSNumber(value: GroupState.forcedLeft.rawValue)
                            addSystemMessage = true
                        }

                        if let conversation = self.entityManager.entityFetcher.conversation(
                            for: groupID,
                            creator: creator
                        ) {
                            if addSystemMessage, let systemMessageDate = systemMessageDate {
                                self.postSystemMessage(
                                    in: conversation,
                                    type: kSystemMessageGroupSelfRemoved,
                                    arg: nil,
                                    date: systemMessageDate
                                )
                            }

                            let lastSyncRequestSince =
                                Date(timeIntervalSinceNow: TimeInterval(-kGroupSyncRequestInterval))
                            let lastSyncRequest = self.entityManager.entityFetcher.lastGroupSyncRequest(
                                for: groupID,
                                groupCreator: creator,
                                since: lastSyncRequestSince
                            )

                            group = Group(
                                myIdentityStore: self.myIdentityStore,
                                userSettings: self.userSettings,
                                groupEntity: groupEntity,
                                conversation: conversation,
                                lastSyncRequest: lastSyncRequest?.lastSyncRequest
                            )
                        }
                    }
                }
            }

            return Promise { $0.fulfill(group) }
        }
    }

    /// Objective-c bridge
    public func createOrUpdateDBObjc(
        groupID: Data,
        creator: String,
        members: Set<String>,
        systemMessageDate: Date?
    ) -> AnyPromise {
        AnyPromise(createOrUpdateDB(
            groupID: groupID,
            creator: creator,
            members: members,
            systemMessageDate: systemMessageDate
        ))
    }
    
    private func fetchContacts(identities: [String]) -> Promise<[Promise<FetchedContactOrError>]> {
        Promise { seal in
            self.contactStore.prefetchIdentityInfo(Set(identities)) {
                let fetchResults = identities.map { identity in
                    Promise<FetchedContactOrError> { singleContactSeal in
                        self.contactStore.fetchPublicKey(
                            for: identity,
                            entityManager: self.entityManager,
                            onCompletion: { _ in
                                guard self.entityManager.entityFetcher.contact(for: identity) != nil else {
                                    singleContactSeal.fulfill(.localNotFound)
                                    return
                                }
                                singleContactSeal.fulfill(.added)
                            }
                        ) { error in
                            DDLogError("Error fetch public key")
                            if let nsError = error as? NSError, nsError.domain == NSURLErrorDomain,
                               nsError.code == 404 {
                                singleContactSeal.fulfill(.revokedOrInvalid(identity))
                            }
                            else if let nsError = error as? NSError, nsError.code == kBlockUnknownContactErrorCode {
                                singleContactSeal.fulfill(.blocked(identity))
                            }
                            else {
                                singleContactSeal.fulfill(.error)
                            }
                        }
                    }
                }
                seal.fulfill(fetchResults)
            } onError: { error in
                seal.reject(error)
            }
        }
    }
    
    /// Individually fetches the contacts with the listed identities from the database or requests them individually from the directory server.
    /// Use `fetchContacts` to fetch multiple contacts
    /// - Parameter identites: identities to fetch from the database or directory server
    /// - Returns: The fetched contact or an error
    private func directFetchContacts(identites: [String]) -> [Promise<FetchedContactOrError>] {
        var fetchResults = [Promise<FetchedContactOrError>]()

        for identity in identites {
            fetchResults.append(
                Promise<FetchedContactOrError> { seal in
                    self.contactStore.fetchPublicKey(for: identity, entityManager: entityManager, onCompletion: { _ in
                        guard self.entityManager.entityFetcher.contact(for: identity) != nil else {
                            seal.fulfill(.localNotFound)
                            return
                        }
                        seal.fulfill(.added)
                    }) { error in
                        DDLogError("Error fetch public key")
                        if let nsError = error as? NSError, nsError.domain == NSURLErrorDomain, nsError.code == 404 {
                            seal.fulfill(.revokedOrInvalid(identity))
                        }
                        else {
                            seal.fulfill(.error)
                        }
                    }
                }
            )
        }

        return fetchResults
    }

    // MARK: - Set name
    
    @discardableResult public func setName(
        groupID: Data,
        creator: String,
        name: String?,
        systemMessageDate: Date,
        send: Bool
    ) -> Promise<Void> {
        guard let grp = getGroup(groupID, creator: creator) else {
            return Promise(error: GroupError.groupNotFound)
        }
        return setName(group: grp, name: name, systemMessageDate: systemMessageDate, send: send)
    }
    
    /// Update group name in DB. If I'm the creator send group rename message (`GroupRenameMessage`) to members.
    ///
    /// - Parameters:
    ///   - group: Group to update name
    ///   - name: New name of the group
    ///   - systemMessageDate: Date for new system message
    ///   - send: Send group rename messages if I'm the creator?
    @discardableResult public func setName(
        group: Group,
        name: String?,
        systemMessageDate: Date,
        send: Bool
    ) -> Promise<Void> {
        guard group.name != name else {
            // Name didn't change
            return Promise()
        }
        
        entityManager.performSyncBlockAndSafe {
            guard let conversation = self.entityManager.entityFetcher.conversation(
                for: group.groupID,
                creator: group.groupCreatorIdentity
            ) else {
                return
            }

            conversation.groupName = name
            
            self.postSystemMessage(
                in: conversation,
                type: kSystemMessageRenameGroup,
                arg: name?.data(using: .utf8),
                date: systemMessageDate
            )
        }
        
        if send, group.isOwnGroup {
            let task = createGroupRenameTask(for: group, to: group.allActiveMemberIdentitiesWithoutCreator)
            return add(task: task)
        }
        else {
            return Promise()
        }
    }
    
    /// Objective-c bridge
    @objc public func setNameObjc(
        groupID: Data,
        creator: String,
        name: String?,
        systemMessageDate: Date,
        send: Bool
    ) -> AnyPromise {
        AnyPromise(setName(groupID: groupID, creator: creator, name: name, systemMessageDate: systemMessageDate))
    }
    
    /// Objective-c bridge
    @objc @discardableResult public func setNameObjc(
        group: Group,
        name: String?,
        systemMessageDate: Date,
        send: Bool
    ) -> AnyPromise {
        AnyPromise(setName(group: group, name: name, systemMessageDate: systemMessageDate, send: send))
    }
    
    // MARK: - Set photo
    
    @discardableResult public func setPhoto(
        groupID: Data,
        creator: String,
        imageData: Data,
        sentDate: Date,
        send: Bool
    ) -> Promise<Void> {
        guard let grp = getGroup(groupID, creator: creator) else {
            return Promise(error: GroupError.groupNotFound)
        }
        return setPhoto(group: grp, imageData: imageData, sentDate: sentDate, send: send)
    }
    
    /// Update group photo and upload photo and send group set photo message (`GroupSetPhotoMessage`) to members, if I'm the creator.
    ///
    /// - Parameters:
    ///   - group: Group to update photo
    ///   - imageData: Photo raw image data, supporting UIImage
    ///   - sentDate: Sent date of set photo message
    ///   - send: If `True` and I'm the creator: upload photo and send group set photo messages
    /// - Throws: GroupError.groupConversationNotFound, GroupError.decodingFailed
    ///           GroupError.notCreator, GroupError.photoUploadFailed, GroupError.blobIDOrKeyMissing
    @discardableResult public func setPhoto(
        group: Group,
        imageData: Data,
        sentDate: Date,
        send: Bool
    ) -> Promise<Void> {
        guard let conversation = entityManager.entityFetcher.conversation(
            for: group.groupID,
            creator: group.groupCreatorIdentity
        ) else {
            return Promise(error: GroupError.groupConversationNotFound)
        }

        var imageDataSend: Data?
        
        // Check if this message is older than the last set date. This ensures that we're using
        // the latest image in case multiple images arrive for the same conversation in short succession.
        // Must do the check here (main thread) to avoid race condition.
        if let imageSetDate = conversation.groupImageSetDate,
           imageSetDate.compare(sentDate) == .orderedDescending {
            
            DDLogInfo("Ignoring older group set photo message")
            imageDataSend = conversation.groupImage?.data
        }
        else if let image = UIImage(data: imageData) {
            entityManager.performSyncBlockAndSafe {
                var dbImage: ImageData? = conversation.groupImage
                if dbImage == nil {
                    dbImage = self.entityManager.entityCreator.imageData()
                }
                dbImage?.data = imageData
                dbImage?.width = NSNumber(floatLiteral: Double(image.size.width))
                dbImage?.height = NSNumber(floatLiteral: Double(image.size.height))

                conversation.groupImageSetDate = sentDate
                conversation.groupImage = dbImage
            }

            imageDataSend = imageData
        }
        else {
            return Promise(error: GroupError.decodingFailed)
        }
        
        if send, group.isOwnGroup,
           let imageDataSend = imageDataSend {
            return sendPhoto(
                to: group,
                imageData: imageDataSend,
                toMembers: group.allActiveMemberIdentitiesWithoutCreator
            )
        }
        else {
            return Promise()
        }
    }
    
    /// Objective-c bridge
    @objc @discardableResult public func setPhotoObjc(
        groupID: Data,
        creator: String,
        imageData: Data,
        sentDate: Date,
        send: Bool
    ) -> AnyPromise {
        AnyPromise(setPhoto(groupID: groupID, creator: creator, imageData: imageData, sentDate: sentDate, send: send))
    }
    
    // MARK: - Delete photo
    
    /// Delete group photo and send group delete photo message (`GroupDeletePhotoMessage`) to members, if I'm the creator.
    ///
    /// - Parameters:
    ///   - groupID: ID (8 bytes) of the group, unique with creator
    ///   - creator: Creator (identity) of the group, unique with ID
    ///   - sentDate: Sent date of delete photo message
    ///   - send: True send group delete photo message if I'm the creator
    ///  - Throws: GroupError.groupNotFound, GroupError.groupConversationNotFound
    @discardableResult public func deletePhoto(
        groupID: Data,
        creator: String,
        sentDate: Date,
        send: Bool
    ) -> Promise<Void> {
        guard let grp = getGroup(groupID, creator: creator) else {
            return Promise(error: GroupError.groupNotFound)
        }

        var internalError: Error?
        entityManager.performSyncBlockAndSafe {
            guard let conversation = self.entityManager.entityFetcher.conversation(
                for: grp.groupID,
                creator: grp.groupCreatorIdentity
            ) else {
                internalError = GroupError.groupConversationNotFound
                return
            }
            conversation.groupImageSetDate = sentDate
            
            if let groupImage = conversation.groupImage {
                self.entityManager.entityDestroyer.deleteObject(object: groupImage)
                conversation.groupImageSetDate = sentDate
                conversation.groupImage = nil
            }
        }
        if let internalError = internalError {
            return Promise(error: internalError)
        }
        
        if send, grp.isOwnGroup {
            let task = createDeletePhotoTask(for: grp, to: grp.allActiveMemberIdentitiesWithoutCreator)
            return add(task: task)
        }
        else {
            return Promise()
        }
    }
    
    /// Objective-c bridge
    @objc public func deletePhotoObjc(groupID: Data, creator: String, sentDate: Date, send: Bool) -> AnyPromise {
        AnyPromise(deletePhoto(groupID: groupID, creator: creator, sentDate: sentDate, send: send))
    }
    
    // MARK: - Leave
    
    /// Send group leave and leave the group, admin of the group may not allowd to leave the group.
    ///
    /// - Parameters:
    ///   - groupID: ID (8 bytes) of the group, unique with creator
    ///   - creator: Creator (identity) of the group, unique with ID
    ///   - toMembers: Receivers of the group leave message, if nil send to all members of existing group
    ///   - systemMessageDate: Date for new system message
    @objc public func leave(groupID: Data, creator: String, toMembers: [String]?, systemMessageDate: Date) {
        guard creator != myIdentityStore.identity else {
            DDLogWarn("Group creator can't leave the group")
            return
        }

        var sendToMembers = [String]()
        if let toMembers = toMembers {
            sendToMembers = toMembers
        }
        else {
            if let conversation = getConversation(for: GroupIdentity(id: groupID, creator: creator)) {
                sendToMembers = conversation.members.map(\.identity)
            }
        }

        if sendToMembers.isEmpty {
            // Add Me as receiver to relflect group leave message
            sendToMembers.append(myIdentityStore.identity)
        }

        let task = TaskDefinitionSendGroupLeaveMessage(sendContactProfilePicture: false)
        task.groupID = groupID
        task.groupCreatorIdentity = creator
        task.fromMember = myIdentityStore.identity
        task.toMembers = sendToMembers
        taskManager.add(taskDefinition: task)

        leaveDB(
            groupID: groupID,
            creator: creator,
            member: myIdentityStore.identity,
            systemMessageDate: systemMessageDate
        )
    }
    
    /// Remove member from group in DB.
    ///
    /// - Parameters:
    ///   - groupID: ID (8 bytes) of the group, unique with creator
    ///   - creator: Creator (identity) of the group, unique with ID
    ///   - member: Member who left the group
    ///   - systemMessageDate: Date for new system message
    public func leaveDB(groupID: Data, creator: String, member: String, systemMessageDate: Date) {
        entityManager.performBlockAndWait {
            guard let grp = self.getGroup(groupID, creator: creator) else {
                DDLogWarn("Group not found")
                return
            }
            guard let groupEntity = self.entityManager.entityFetcher.groupEntity(
                for: groupID,
                with: creator != self.myIdentityStore.identity ? creator : nil
            )
            else {
                DDLogWarn("Group entity not found")
                return
            }
            guard let conversation = self.getConversation(for: GroupIdentity(id: groupID, creator: creator)) else {
                DDLogWarn("Conversation not found")
                return
            }

            DDLogInfo("Member \(member) left the group \(grp.groupID.hexString) \(creator)")

            if let contact = conversation.members.first(where: { contact -> Bool in
                contact.identity.elementsEqual(member)
            }) {
                self.entityManager.performSyncBlockAndSafe {
                    conversation.removeMembersObject(contact)
                }

                self.postSystemMessage(
                    in: conversation,
                    member: contact,
                    type: kSystemMessageGroupMemberLeave,
                    date: systemMessageDate
                )

                if creator.elementsEqual(self.myIdentityStore.identity),
                   grp.isNoteGroup {
                    self.postSystemMessage(
                        in: conversation,
                        type: kSystemMessageStartNoteGroupInfo,
                        arg: nil,
                        date: Date()
                    )
                }
                else if creator == member, !grp.isNoteGroup {
                    self.postSystemMessage(
                        in: conversation,
                        type: kSystemMessageGroupCreatorLeft,
                        arg: nil,
                        date: Date()
                    )
                }
            }
            else if member.elementsEqual(self.myIdentityStore.identity), !grp.didLeave {
                self.entityManager.performSyncBlockAndSafe {
                    groupEntity.state = NSNumber(value: GroupState.left.rawValue)
                    if !(conversation.groupMyIdentity?.elementsEqual(self.myIdentityStore.identity) ?? false) {
                        conversation.groupMyIdentity = self.myIdentityStore.identity
                    }
                }

                self.postSystemMessage(
                    in: conversation,
                    type: kSystemMessageGroupSelfLeft,
                    arg: nil,
                    date: systemMessageDate
                )
            }
        }
    }

    /// Send empty member list to every group member to dissolve the group and i left the group.
    ///
    /// - Parameters:
    ///   - groupID: Group ID to suspend (I'm the group creator)
    ///   - identities: Identities to send dissolve to, if `nil` all group members get the dissolve message
    @objc public func dissolve(
        groupID: Data,
        to identities: Set<String>?
    ) {
        entityManager.performBlockAndWait {
            if let group = self.getGroup(groupID, creator: self.myIdentityStore.identity) {
                guard group.isSelfCreator else {
                    return
                }

                // Group found, kick identities or all members except me, and left the group
                var removeMembers: Set<String>
                if let identities = identities {
                    removeMembers = identities.filter { $0 != self.myIdentityStore.identity }
                }
                else {
                    removeMembers = group.allMemberIdentities.filter { $0 != self.myIdentityStore.identity }
                }

                if !removeMembers.isEmpty {
                    self.taskManager.add(
                        taskDefinition: TaskDefinitionSendGroupCreateMessage(
                            group: group,
                            to: [],
                            removed: Array(removeMembers),
                            members: group.allMemberIdentities,
                            sendContactProfilePicture: false
                        )
                    )
                }

                if group.state == .active {
                    // I leave the group
                    self.leaveDB(
                        groupID: group.groupID,
                        creator: group.groupCreatorIdentity,
                        member: group.groupCreatorIdentity,
                        systemMessageDate: Date()
                    )
                }
            }
            else {
                // Group not found (means conversation was deleted), kick identities except me if I'm group creator and has left the group
                guard let groupEntity = self.entityManager.entityFetcher.groupEntity(
                    for: groupID,
                    with: nil
                ),
                    groupEntity.didLeave(),
                    let identities = identities
                else {
                    return
                }

                let removeMembers = identities.filter { $0 != self.myIdentityStore.identity }
                if !removeMembers.isEmpty {
                    self.taskManager.add(
                        taskDefinition: TaskDefinitionSendGroupCreateMessage(
                            groupID: groupID,
                            groupCreatorIdentity: self.myIdentityStore.identity,
                            groupName: nil,
                            allGroupMembers: nil,
                            isNoteGroup: nil,
                            to: [],
                            removed: Array(removeMembers),
                            members: Set<String>(),
                            sendContactProfilePicture: false
                        )
                    )
                }
            }
        }
    }
    
    // MARK: - Sync
    
    /// Sync group information to identities.
    ///
    /// Send group create, rename and set photo message to each identity that is a member. Send a group create to non-members with an empty
    /// members list.
    ///
    /// - Parameters:
    ///   - group: Group to sync
    ///   - identities: Identities to send sync to, if `nil` all group members get the sync messages
    ///   - withoutCreateMessage: Should the create message also be sent to group members?
    ///                             (This is useful to send all group information to recently added members.)
    public func sync(
        group: Group,
        to identities: Set<String>?,
        withoutCreateMessage: Bool
    ) -> Promise<Void> {
        // Ensure that we are the creator
        guard group.isOwnGroup else {
            return Promise(error: GroupError.notCreator)
        }
        
        guard let identities = identities else {
            // Sync to all members
            return sync(
                group: group,
                to: group.allActiveMemberIdentitiesWithoutCreator,
                withoutCreateMessage: withoutCreateMessage
            )
        }
        
        // If we have a list of receivers filter between members and non-members.
        var activeMembers = [String]()
        var removedMembers = [String]()
        for identity in identities {
            if group.allMemberIdentities.contains(identity) {
                activeMembers.append(identity)
            }
            else {
                removedMembers.append(identity)
            }
        }
        
        return when(
            fulfilled:
            sync(group: group, to: activeMembers, withoutCreateMessage: withoutCreateMessage),
            syncToRemovedMembers(group: group, to: removedMembers)
        )
    }
    
    @objc public func syncObjc(
        group: Group,
        to identities: Set<String>?,
        withoutCreateMessage: Bool
    ) -> AnyPromise {
        AnyPromise(sync(group: group, to: identities, withoutCreateMessage: withoutCreateMessage))
    }
    
    /// Send sync request for this group, is not already requested in the last 7 days (see `kGroupSyncRequestInterval`).
    ///
    /// - Parameters:
    ///   - groupID: ID 8 Bytes
    ///   - creator: Creator of group
    @objc public func sendSyncRequest(groupID: Data, creator: String) {
        
        let lastSyncRequestSince = Date(timeIntervalSinceNow: TimeInterval(-kGroupSyncRequestInterval))
        guard entityManager.entityFetcher.lastGroupSyncRequest(
            for: groupID,
            groupCreator: creator,
            since: lastSyncRequestSince
        ) == nil else {
            DDLogInfo(
                "Sync for Group ID \(groupID.hexString) (creator \(creator)) already requested in the last \(kGroupSyncRequestInterval) s."
            )
            return
        }
        
        DDLogWarn("Group ID \(groupID.hexString) (creator \(creator)) not found. Requesting sync from creator.")
        
        // Fetch creator first, contact could be missing
        contactStore.fetchPublicKey(for: creator, entityManager: entityManager, onCompletion: { _ in
            if self.entityManager.entityFetcher.contact(for: creator) != nil {
                self.recordSendSyncRequest(groupID, creator)
                self.sendGroupSyncRequest(groupID, creator)
            }
            else {
                DDLogError("Could not send group request sync, because of missing group creator \(creator) contact")
            }
        }) { _ in
            DDLogError("Could not fetch public key for \(creator)")
        }
    }
    
    /// Start periodic group sync if needed
    ///
    /// Sync tasks are guaranteed to be enqueued when this function returns, except of a potential set photo message
    ///
    /// - Parameter group: Group conversation to sync
    @objc public func periodicSyncIfNeeded(for group: Group) {
        // Check if we are the creator
        guard group.isOwnGroup else {
            return
        }
        
        // Check if sync is needed
        if let lastPeriodicSync = group.lastPeriodicSync {
            let timeSinceLastSync = lastPeriodicSync.timeIntervalSinceNow
            if timeSinceLastSync > TimeInterval(-kGroupPeriodicSyncInterval) {
                // Last sync is shorter than `kGroupPeriodicSyncInterval` in the past
                return
            }
        }

        let toMembers = group.allActiveMemberIdentitiesWithoutCreator
        
        // Do these step synchronously to ensure they are enqueued before a potential outgoing
        // message leading to this call.
        // We don't care if the task execution fails eventually as the likelihood is low.
                
        guard let conversation =
            getConversation(for: GroupIdentity(id: group.groupID, creator: group.groupCreatorIdentity)) else {
            DDLogWarn("Coversation not found")
            return
        }

        // 5. Send a group-setup message with the current group members, ...
        let createTask = createGroupCreateSyncTask(for: group, conversation: conversation, to: toMembers)
        taskManager.add(taskDefinition: createTask)
        
        // ...followed by a group-name message to the sender.
        let sendNameTask = createGroupRenameTask(for: group, to: toMembers)
        taskManager.add(taskDefinition: sendNameTask)
        
        // 7. If the group has no profile picture, send a `delete-profile-picture` group control message to the sender.
        if group.photo?.data == nil {
            let deletePhotoTask = createDeletePhotoTask(for: group, to: toMembers)
            taskManager.add(taskDefinition: deletePhotoTask)
        }
                
        entityManager.performSyncBlockAndSafe {
            if let groupEntity = self.entityManager.entityFetcher.groupEntity(
                for: group.groupID,
                with: group.groupCreatorIdentity != self.myIdentityStore.identity ? group
                    .groupCreatorIdentity : nil
            ) {
                groupEntity.lastPeriodicSync = Date()
            }
        }
        
        // As sending a profile picture might take a while to upload we do it asynchronously and
        // don't guarantee it to be sent out before the a group message is sent
        
        // 6. If the group has a profile picture, send a `set-profile-picture` group control message to the sender.
        if let photoData = group.photo?.data {
            sendPhoto(to: group, imageData: photoData, toMembers: toMembers)
                .catch { error in
                    // Note: This might never be called if the task was persisted at some point in
                    // the meantime
                    DDLogError("Periodic group sync photo sending failed: \(error)")
                    // Reset last periodic sync date if photo sending failed
                    self.entityManager.performSyncBlockAndSafe {
                        if let groupEntity = self.entityManager.entityFetcher.groupEntity(
                            for: group.groupID,
                            with: group.groupCreatorIdentity != self.myIdentityStore.identity ? group
                                .groupCreatorIdentity : nil
                        ) {
                            groupEntity.lastPeriodicSync = nil
                        }
                    }
                }
        }
    }
    
    // MARK: - Get group / conversation

    public func getConversation(for groupIdentity: GroupIdentity) -> Conversation? {
        entityManager.entityFetcher.conversation(for: groupIdentity.id, creator: groupIdentity.creator)
    }

    /// Loads group, conversation and LastGroupSyncRequest from DB.
    ///
    /// - Parameters:
    ///   - groupID: ID 8 Bytes
    ///   - creator: Creator of group
    /// - Returns: The group or nil
    @objc public func getGroup(_ groupID: Data, creator: String) -> Group? {
        var group: Group?

        entityManager.performBlockAndWait {
            guard let conversation = self.entityManager.entityFetcher.conversation(
                for: groupID,
                creator: creator
            ) else {
                return
            }
            guard let groupEntity = self.entityManager.entityFetcher.groupEntity(for: conversation) else {
                return
            }
            group = self.getGroup(groupEntity: groupEntity, conversation: conversation)
        }

        return group
    }
    
    /// Loads group for conversation.
    ///
    /// - Parameter conversation: Conversation for group
    /// - Returns: The group or nil
    @objc public func getGroup(conversation: Conversation) -> Group? {
        guard let groupEntity = entityManager.entityFetcher.groupEntity(for: conversation) else {
            return nil
        }
        
        return getGroup(groupEntity: groupEntity, conversation: conversation)
    }

    private func getGroup(groupEntity: GroupEntity, conversation: Conversation) -> Group {
        let creator: String = groupEntity.groupCreator ?? myIdentityStore.identity

        let lastSyncRequestSince = Date(timeIntervalSinceNow: TimeInterval(-kGroupSyncRequestInterval))
        let lastSyncRequest = entityManager.entityFetcher.lastGroupSyncRequest(
            for: groupEntity.groupID,
            groupCreator: creator,
            since: lastSyncRequestSince
        )

        return Group(
            myIdentityStore: myIdentityStore,
            userSettings: userSettings,
            groupEntity: groupEntity,
            conversation: conversation,
            lastSyncRequest: lastSyncRequest?.lastSyncRequest
        )
    }
    
    /// Get all members of existing group except me.
    ///
    /// - Parameters:
    ///   - groupID: ID 8 Bytes
    ///   - creator: Creator of group
    /// - Returns: Members of the group
    @objc func getGroupMembersForClone(_ groupID: Data, creator: String) -> Set<Contact>? {
        guard let conversation = getConversation(for: GroupIdentity(id: groupID, creator: creator)) else {
            DDLogError("Group conversation not found")
            return nil
        }
        
        return conversation.members.filter { member -> Bool in
            !member.identity.elementsEqual(myIdentityStore.identity)
        }
    }
    
    /// Show alert of unknown group, if after 5 sec. no group create message arrived.
    ///
    /// - Parameters:
    ///   - groupID: Group id of unknown group
    ///   - creator: Creator identity of unknown group
    @objc public func unknownGroup(groupID: Data, creator: String) {
        DispatchQueue.main.async {
            Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { _ in
                guard self.getGroup(groupID, creator: creator) == nil else {
                    return
                }
                
                var userInfo: [String: String]?
                if let contact = self.contactStore.contact(for: creator) {
                    userInfo = [kKeyContact: contact.displayName]
                }
                else {
                    userInfo = [kKeyContact: creator]
                }
                
                let unknownGroupAlertList = self.userSettings.unknownGroupAlertList!
                let groupDict: [String: AnyHashable] = ["groupid": groupID, "creator": creator]
                if !unknownGroupAlertList.contains(groupDict) {
                    NotificationCenter.default.post(
                        name: Notification.Name(rawValue: kNotificationErrorUnknownGroup),
                        object: nil,
                        userInfo: userInfo
                    )
                    unknownGroupAlertList.add(groupDict)
                    self.userSettings.unknownGroupAlertList = unknownGroupAlertList
                }
            }
        }
    }
    
    // MARK: - Private functions
    
    private func postSystemMessage(in conversation: Conversation, member: Contact, type: Int, date: Date) {
        postSystemMessage(in: conversation, type: type, arg: member.displayName.data(using: .utf8), date: date)
    }
    
    private func postSystemMessage(in conversation: Conversation, type: Int, arg: Data?, date: Date) {
        entityManager.performSyncBlockAndSafe {
            // Insert system message to document this change
            let sysMsg = self.entityManager.entityCreator.systemMessage(for: conversation)
            sysMsg?.type = NSNumber(integerLiteral: type)
            sysMsg?.arg = arg
            sysMsg?.remoteSentDate = date
            conversation.lastMessage = sysMsg
        }
    }
    
    // MARK: Sync
    
    private func sync(
        group: Group,
        to toMembers: [String],
        withoutCreateMessage: Bool
    ) -> Promise<Void> {
        guard !toMembers.isEmpty else {
            return Promise()
        }

        // Prepare sync tasks
    
        func runGroupCreateTask() -> Promise<Void> {
            guard !withoutCreateMessage else {
                return Promise()
            }
            
            guard let conversation =
                getConversation(for: GroupIdentity(id: group.groupID, creator: group.groupCreatorIdentity)) else {
                return Promise(error: GroupError.groupConversationNotFound)
            }

            // 5. Send a group-setup message with the current group members, ...
            let task = createGroupCreateSyncTask(for: group, conversation: conversation, to: toMembers)
            return add(task: task)
        }
        
        // ...followed by a group-name message to the sender.
        func runGroupNameTask() -> Promise<Void> {
            let task = createGroupRenameTask(for: group, to: toMembers)
            return add(task: task)
        }
        
        func runGroupPhotoTask() -> Promise<Void> {
            var photoData: Data?
            entityManager.performBlockAndWait {
                photoData = group.photo?.data
            }

            guard let data = photoData else {
                // 7. If the group has no profile picture, send a `delete-profile-picture` group
                // control message to the sender.
                let task = createDeletePhotoTask(for: group, to: toMembers)
                return add(task: task)
            }
            
            // 6. If the group has a profile picture, send a `set-profile-picture` group control
            // message to the sender.
            return sendPhoto(to: group, imageData: data, toMembers: toMembers)
        }
        
        return firstly {
            runGroupCreateTask()
        }
        .then {
            runGroupNameTask()
        }
        .then {
            runGroupPhotoTask()
        }
    }
    
    private func syncToRemovedMembers(
        group: Group,
        to removedMembers: [String]
    ) -> Promise<Void> {
        guard !removedMembers.isEmpty else {
            return Promise()
        }
        guard let conversation =
            getConversation(for: GroupIdentity(id: group.groupID, creator: group.groupCreatorIdentity)) else {
            return Promise()
        }
        
        let members = Set(conversation.members.map(\.identity))
        let emptyCreateTask = TaskDefinitionSendGroupCreateMessage(
            group: group,
            to: [],
            removed: removedMembers,
            members: members
        )
        
        return add(task: emptyCreateTask)
    }
    
    private func sendPhoto(
        to group: Group,
        imageData: Data,
        toMembers: [String]
    ) -> Promise<Void> {
        guard group.isOwnGroup else {
            return Promise(error: GroupError.notCreator)
        }

        // Core Data concurrency problem, store group infos for reloading group
        let groupID = group.groupID
        let groupCreatorIdentity = group.groupCreatorIdentity
        
        return Promise { seal in
            groupPhotoSender.start(
                withImageData: imageData,
                isNoteGroup: group.isNoteGroup
            ) { blobID, encryptionKey in
                guard let blobID = blobID, let encryptionKey = encryptionKey else {
                    seal.reject(GroupError.blobIDOrKeyMissing)
                    return
                }

                self.entityManager.performBlockAndWait {
                    let task = TaskDefinitionSendGroupSetPhotoMessage(
                        group: self.getGroup(groupID, creator: groupCreatorIdentity),
                        from: self.myIdentityStore.identity,
                        to: toMembers,
                        size: UInt32(imageData.count),
                        blobID: blobID,
                        encryptionKey: encryptionKey
                    )

                    seal.fulfill(task)
                }
            } onError: { _ in
                seal.reject(GroupError.photoUploadFailed)
            }
        }.then { task in
            self.add(task: task)
        }
    }
        
    private func createGroupCreateSyncTask(
        for group: Group,
        conversation: Conversation,
        to toMembers: [String]
    ) -> TaskDefinitionSendGroupCreateMessage {
        let members = Set(conversation.members.map(\.identity))
        
        return TaskDefinitionSendGroupCreateMessage(
            group: group,
            to: toMembers,
            members: members
        )
    }
    
    private func createGroupRenameTask(
        for group: Group,
        to toMembers: [String]
    ) -> TaskDefinitionSendGroupRenameMessage {
        TaskDefinitionSendGroupRenameMessage(
            group: group,
            from: myIdentityStore.identity,
            to: toMembers,
            newName: group.name
        )
    }
    
    private func createDeletePhotoTask(
        for group: Group,
        to toMembers: [String]
    ) -> TaskDefinitionSendGroupDeletePhotoMessage {
        TaskDefinitionSendGroupDeletePhotoMessage(
            group: group,
            from: myIdentityStore.identity,
            to: toMembers,
            sendContactProfilePicture: false
        )
    }
    
    private func add(task: TaskDefinitionProtocol) -> Promise<Void> {
        Promise { seal in
            taskManager.add(taskDefinition: task) { _, error in
                seal.resolve(error)
            }
        }
    }
    
    private func recordSendSyncRequest(_ groupID: Data, _ creator: String) {
        entityManager.performSyncBlockAndSafe {
            // Record this sync request
            let lastSyncRequest: LastGroupSyncRequest = self.entityManager.entityCreator.lastGroupSyncRequest()
            lastSyncRequest.groupID = groupID
            lastSyncRequest.groupCreator = creator
            lastSyncRequest.lastSyncRequest = Date()
        }
    }
    
    /// Caution: Use this only for testing!
    @objc public func deleteAllSyncRequestRecords() {
        if let entities = entityManager.entityFetcher.allLastGroupSyncRequests() {
            for entity in entities {
                if let entity = entity as? LastGroupSyncRequest {
                    entityManager.entityDestroyer.deleteObject(object: entity)
                }
            }
        }
    }
    
    /// Send not closed ballot messages to "new" members.
    ///
    /// - Parameters:
    ///   - group: Group with new members
    ///   - members: "New" members of group
    private func sendGroupBallotIsNotClosed(_ group: Group, _ members: Set<String>?) {
        // TODO: Check must be reflect ballot messages to new members???

        guard let conversation =
            getConversation(for: GroupIdentity(id: group.groupID, creator: group.groupCreatorIdentity)) else {
            return
        }
        
        guard let members = members,
              !members.isEmpty,
              let ballots = conversation.ballots else {
            return
        }
        
        // Get all open ballots if there are any
        
        let myOpenBallots = ballots.compactMap {
            $0 as? Ballot
        }.filter {
            $0.isOwn() && !$0.isClosed()
        }
        
        guard !myOpenBallots.isEmpty else {
            return
        }
        
        // Send ballots to new members
        for memberID in members {
            guard let contact = entityManager.entityFetcher.contact(for: memberID) else {
                continue
            }
            
            for ballot in myOpenBallots {
                sendGroupBallotCreateMessage(ballot, conversation, contact.identity)
                
                if ballot.isIntermediate() {
                    sendGroupBallotVoteMessage(ballot, conversation, contact.identity)
                }
            }
        }
    }
    
    private func sendGroupBallotCreateMessage(_ ballot: Ballot, _ conversation: Conversation, _ toMember: String) {
        let boxMsg = BallotMessageEncoder.encodeCreateMessage(for: ballot)
        boxMsg.messageID = AbstractMessage.randomMessageID()
        
        let msg = BallotMessageEncoder.groupBallotCreateMessage(from: boxMsg, for: conversation)
        msg.toIdentity = toMember
        
        let task = TaskDefinitionSendAbstractMessage(message: msg)
        taskManager.add(taskDefinition: task)
    }
    
    private func sendGroupBallotVoteMessage(_ ballot: Ballot, _ conversation: Conversation, _ toMember: String) {
        let boxMsg = BallotMessageEncoder.encodeVoteMessage(for: ballot)
        boxMsg.messageID = AbstractMessage.randomMessageID()
        
        let msg = BallotMessageEncoder.groupBallotVoteMessage(from: boxMsg, for: conversation)
        msg.toIdentity = toMember
        
        let task = TaskDefinitionSendAbstractMessage(message: msg)
        taskManager.add(taskDefinition: task)
    }
    
    private func sendGroupSyncRequest(_ groupID: Data, _ creator: String) {
        let msg = GroupRequestSyncMessage()
        msg.groupID = groupID
        msg.groupCreator = creator
        msg.toIdentity = creator
        
        let task = TaskDefinitionSendAbstractMessage(message: msg)
        taskManager.add(taskDefinition: task)
    }
    
    private func removeUnknownGroupFromAlertList(groupID: Data, creator: String) {
        let unknownGroupAlertList = userSettings.unknownGroupAlertList!
        let groupDict = ["groupid": groupID, "creator": creator] as [String: AnyHashable]
        if unknownGroupAlertList.map({ $0 as! [String: AnyHashable] == groupDict }).contains(true) {
            unknownGroupAlertList.remove(groupDict)
            userSettings.unknownGroupAlertList = unknownGroupAlertList
        }
    }
}
