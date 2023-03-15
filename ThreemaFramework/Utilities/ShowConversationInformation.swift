//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2023 Threema GmbH
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

public class ShowConversationInformation: NSObject {
    @objc public let conversation: Conversation
    @objc public let forceCompose: Bool
    @objc public let precomposedText: String?
    @objc public let image: UIImage?

    init(conversation: Conversation, forceCompose: Bool = true, precomposedText: String? = nil, image: UIImage? = nil) {
        self.conversation = conversation
        self.forceCompose = forceCompose
        self.precomposedText = precomposedText
        self.image = image
    }
    
    @objc static func createInfo(for notification: NSNotification) -> ShowConversationInformation? {
        guard let info = notification.userInfo else {
            return nil
        }
        
        var resolvedConversation: Conversation?

        if let conversation = info[kKeyConversation] as? Conversation {
            resolvedConversation = conversation
        }
        else if let contact = info[kKeyContact] as? ContactEntity {
            let em = EntityManager()
            em.performBlockAndWait {
                resolvedConversation = em.conversation(for: contact.identity, createIfNotExisting: true)
            }
        }
        else {
            assertionFailure("Could not create ShowConversationInformation for notification.")
            return nil
        }
        
        guard let resolvedConversation else {
            assertionFailure("Could not create ShowConversationInformation for notification.")
            return nil
        }
        
        let forceCompose: Bool = info[kKeyForceCompose] as? Bool ?? true
        let text = info[kKeyText] as? String
        let image = info[kKeyImage] as? UIImage
        
        return ShowConversationInformation(
            conversation: resolvedConversation,
            forceCompose: forceCompose,
            precomposedText: text,
            image: image
        )
    }
}
