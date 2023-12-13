//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2020-2023 Threema GmbH
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

@objc class TaskDefinitionSendBaseMessage: TaskDefinitionSendMessage {
    override func create(
        frameworkInjector: FrameworkInjectorProtocol,
        taskContext: TaskContextProtocol
    ) -> TaskExecutionProtocol {
        TaskExecutionSendMessage(taskContext: taskContext, taskDefinition: self, frameworkInjector: frameworkInjector)
    }

    override func create(frameworkInjector: FrameworkInjectorProtocol) -> TaskExecutionProtocol {
        create(
            frameworkInjector: frameworkInjector,
            taskContext: TaskContext(
                logReflectMessageToMediator: .reflectOutgoingMessageToMediator,
                logReceiveMessageAckFromMediator: .receiveOutgoingMessageAckFromMediator,
                logSendMessageToChat: .sendOutgoingMessageToChat,
                logReceiveMessageAckFromChat: .receiveOutgoingMessageAckFromChat
            )
        )
    }
    
    override var description: String {
        "<\(type(of: self)) type: \(messageType ?? "unknown") id: \(messageID.hexString)>"
    }

    @objc let messageID: Data
    var messageType: String?

    private enum CodingKeys: String, CodingKey {
        case messageID, messageType
    }

    @objc init(
        messageID: Data,
        receiverIdentity: String?,
        group: Group?,
        sendContactProfilePicture: Bool
    ) {
        self.messageID = messageID
        super.init(
            receiverIdentity: receiverIdentity,
            group: group,
            sendContactProfilePicture: sendContactProfilePicture
        )
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.messageID = try container.decode(Data.self, forKey: .messageID)
        self.messageType = try container.decode(String?.self, forKey: .messageType)

        let superdecoder = try container.superDecoder()
        try super.init(from: superdecoder)
    }

    override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(messageID, forKey: .messageID)
        try container.encode(messageType, forKey: .messageType)

        let superencoder = container.superEncoder()
        try super.encode(to: superencoder)
    }
}
