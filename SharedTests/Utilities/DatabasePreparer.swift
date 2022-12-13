//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2019-2021 Threema GmbH
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

class DatabasePreparer {
    private let objCnx: NSManagedObjectContext
    
    required init(context: NSManagedObjectContext) {
        self.objCnx = context
    }
    
    /// Save data modifications on DB.
    ///
    /// - Parameters:
    ///    - dbModificationAction: Closure with data modifications
    func save(dbModificationAction: () -> Void) {
        do {
            dbModificationAction()
            
            try objCnx.save()
        }
        catch {
            print(error)
            XCTFail("Could not generate test data: \(error)")
        }
    }
    
    @discardableResult func createBallotMessage(conversation: Conversation, ballotID: Data) -> Ballot {
        let ballotMessage = createEntity(objectType: Ballot.self)
        ballotMessage.conversation = conversation
        ballotMessage.id = ballotID
        return ballotMessage
    }
    
    @discardableResult func createContact(publicKey: Data, identity: String, verificationLevel: Int) -> Contact {
        let contact = createEntity(objectType: Contact.self)
        contact.publicKey = publicKey
        contact.identity = identity
        contact.verificationLevel = NSNumber(integerLiteral: verificationLevel)
        return contact
    }
    
    @discardableResult func createConversation(
        marked: Bool,
        typing: Bool,
        unreadMessageCount: Int,
        complete: ((Conversation) -> Void)?
    ) -> Conversation {
        let conversation = createEntity(objectType: Conversation.self)
        conversation.marked = NSNumber(booleanLiteral: marked)
        conversation.typing = NSNumber(booleanLiteral: typing)
        conversation.unreadMessageCount = NSNumber(integerLiteral: unreadMessageCount)
        if let complete = complete {
            complete(conversation)
        }
        return conversation
    }
    
    @discardableResult func createConversation(
        marked: Bool,
        typing: Bool,
        unreadMessageCount: Int,
        category: ConversationCategory,
        visibility: ConversationVisibility,
        complete: ((Conversation) -> Void)?
    ) -> Conversation {
        let conversation = createEntity(objectType: Conversation.self)
        conversation.marked = NSNumber(booleanLiteral: marked)
        conversation.typing = NSNumber(booleanLiteral: typing)
        conversation.unreadMessageCount = NSNumber(integerLiteral: unreadMessageCount)
        conversation.conversationCategory = category
        conversation.conversationVisibility = visibility
 
        complete?(conversation)
        
        return conversation
    }
    
    @discardableResult func createGroupEntity(groupID: Data, groupCreator: String?) -> GroupEntity {
        let groupEntity = createEntity(objectType: GroupEntity.self)
        groupEntity.groupID = groupID
        groupEntity.groupCreator = groupCreator
        groupEntity.state = NSNumber(integerLiteral: 0)
        return groupEntity
    }
    
    @discardableResult func createImageData(data: Data, height: Int, width: Int) -> ImageData {
        let imageData = createEntity(objectType: ImageData.self)
        imageData.data = data
        imageData.height = NSNumber(integerLiteral: height)
        imageData.width = NSNumber(integerLiteral: width)
        return imageData
    }
    
    @discardableResult func createAudioData(data: Data?) -> AudioData {
        let audioData = createEntity(objectType: AudioData.self)
        audioData.data = data
        return audioData
    }
    
    @discardableResult func createVideoData(data: Data) -> VideoData {
        let videoData = createEntity(objectType: VideoData.self)
        videoData.data = data
        return videoData
    }
    
    @discardableResult func createFileData(data: Data) -> FileData {
        let fileData = createEntity(objectType: FileData.self)
        fileData.data = data
        return fileData
    }
    
    @discardableResult func createAudioMessageEntity(
        conversation: Conversation,
        duration: Int,
        complete: ((AudioMessageEntity) -> Void)?
    ) -> AudioMessageEntity {
        let audioMessage = createEntity(objectType: AudioMessageEntity.self)
        audioMessage.conversation = conversation
        audioMessage.duration = NSNumber(integerLiteral: duration)
        audioMessage.date = Date()
        audioMessage.delivered = NSNumber(booleanLiteral: true)
        audioMessage.read = NSNumber(booleanLiteral: false)
        if let complete = complete {
            complete(audioMessage)
        }
        return audioMessage
    }
    
    @discardableResult func createLocationMessage(
        conversation: Conversation,
        accuracy: Double,
        latitude: Double,
        longitude: Double,
        poiName: String?,
        id: Data,
        sender: Contact
    ) -> LocationMessage {
        let locationMessage = createEntity(objectType: LocationMessage.self)
        locationMessage.conversation = conversation
        locationMessage.accuracy = NSNumber(value: accuracy)
        locationMessage.latitude = NSNumber(value: latitude)
        locationMessage.longitude = NSNumber(value: longitude)
        locationMessage.poiName = poiName
        locationMessage.id = id
        locationMessage.date = Date()
        locationMessage.delivered = NSNumber(booleanLiteral: true)
        locationMessage.isOwn = NSNumber(booleanLiteral: true)
        locationMessage.read = NSNumber(booleanLiteral: false)
        locationMessage.sent = NSNumber(booleanLiteral: true)
        locationMessage.userack = NSNumber(booleanLiteral: false)
        locationMessage.sender = sender
        return locationMessage
    }
    
    @discardableResult func createTextMessage(
        conversation: Conversation,
        text: String,
        date: Date,
        delivered: Bool,
        id: Data,
        isOwn: Bool,
        read: Bool,
        sent: Bool,
        userack: Bool,
        sender: Contact?,
        remoteSentDate: Date? = nil
    ) -> TextMessage {
        let textMessage = createEntity(objectType: TextMessage.self)
        textMessage.conversation = conversation
        textMessage.text = text
        textMessage.date = date
        textMessage.delivered = NSNumber(booleanLiteral: delivered)
        textMessage.id = id
        textMessage.isOwn = NSNumber(booleanLiteral: isOwn)
        textMessage.read = NSNumber(booleanLiteral: read)
        textMessage.sent = NSNumber(booleanLiteral: sent)
        textMessage.userack = NSNumber(booleanLiteral: userack)
        textMessage.sender = sender
        textMessage.remoteSentDate = remoteSentDate
        return textMessage
    }
    
    @discardableResult func createVideoMessageEntity(
        conversation: Conversation,
        thumbnail: ImageData,
        videoData: VideoData?,
        date: Date?,
        complete: ((VideoMessageEntity) -> Void)?
    ) -> VideoMessageEntity {
        let videoMessage = createEntity(objectType: VideoMessageEntity.self)
        videoMessage.date = date
        videoMessage.conversation = conversation
        videoMessage.thumbnail = thumbnail
        videoMessage.video = videoData
        if let complete = complete {
            complete(videoMessage)
        }
        return videoMessage
    }
    
    @discardableResult func createFileMessageEntity(
        conversation: Conversation,
        encryptionKey: Data? = nil,
        blobID: Data? = nil,
        blobThumbnailID: Data? = nil,
        progress: NSNumber? = nil,
        data: FileData? = nil,
        thumbnail: ImageData? = nil,
        messageID: Data = BytesUtility.generateRandomBytes(length: ThreemaProtocol.messageIDLength)!,
        date: Date = Date(),
        isOwn: Bool = false,
        sent: Bool = true,
        delivered: Bool = false,
        read: Bool = false,
        userack: Bool = false,
        complete: ((FileMessageEntity) -> Void)? = nil
    ) -> FileMessageEntity {
        let fileMessage = createEntity(objectType: FileMessageEntity.self)
        
        fileMessage.conversation = conversation
        fileMessage.encryptionKey = encryptionKey
        fileMessage.blobID = blobID
        fileMessage.blobThumbnailID = blobThumbnailID
        fileMessage.progress = progress
        fileMessage.data = data
        fileMessage.thumbnail = thumbnail
        
        // Required by Core Data values
        fileMessage.id = messageID
        fileMessage.date = date
        fileMessage.isOwn = NSNumber(booleanLiteral: isOwn)
        fileMessage.sent = NSNumber(booleanLiteral: sent)
        fileMessage.delivered = NSNumber(booleanLiteral: delivered)
        fileMessage.read = NSNumber(booleanLiteral: read)
        fileMessage.userack = NSNumber(booleanLiteral: userack)
        
        complete?(fileMessage)
        
        return fileMessage
    }
    
    private func createEntity<T: NSManagedObject>(objectType: T.Type) -> T {
        var entityName: String
        
        if objectType is Contact.Type {
            entityName = "Contact"
        }
        else if objectType is Conversation.Type {
            entityName = "Conversation"
        }
        else if objectType is GroupEntity.Type {
            entityName = "Group"
        }
        else if objectType is ImageData.Type {
            entityName = "ImageData"
        }
        else if objectType is AudioData.Type {
            entityName = "AudioData"
        }
        else if objectType is VideoData.Type {
            entityName = "VideoData"
        }
        else if objectType is FileData.Type {
            entityName = "FileData"
        }
        else if objectType is Ballot.Type {
            entityName = "Ballot"
        }
        else if objectType is TextMessage.Type {
            entityName = "TextMessage"
        }
        else if objectType is AudioMessageEntity.Type {
            entityName = "AudioMessage"
        }
        else if objectType is LocationMessage.Type {
            entityName = "LocationMessage"
        }
        else if objectType is VideoMessageEntity.Type {
            entityName = "VideoMessage"
        }
        else if objectType is FileMessageEntity.Type {
            entityName = "FileMessage"
        }
        else {
            fatalError("objects type not defined")
        }
        
        return NSEntityDescription.insertNewObject(forEntityName: entityName, into: objCnx) as! T
    }
}