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

import CocoaLumberjackSwift
import Foundation

class ConversationActions: NSObject {
    private let businessInjector: BusinessInjectorProtocol
    private let notificationManager: NotificationManagerProtocol

    init(
        businessInjector: BusinessInjectorProtocol,
        notificationManager: NotificationManagerProtocol
    ) {
        self.businessInjector = businessInjector
        self.notificationManager = notificationManager
    }

    convenience init(businessInjector: BusinessInjectorProtocol) {
        self.init(
            businessInjector: businessInjector,
            notificationManager: NotificationManager(
                businessInjector: businessInjector
            )
        )
    }
    
    @objc override convenience init() {
        self.init(businessInjector: BusinessInjector())
    }
    
    // MARK: - Reading
    
    /// Reads all unread messages of a conversation if read receipts are enabled, also updates the unread messages count
    /// - Parameters:
    ///   - conversation: Conversation to read messages
    ///   - isAppInBackground: If app is in background, default gets current status from AppDelegate
    @discardableResult
    func read(
        _ conversation: Conversation,
        isAppInBackground: Bool = AppDelegate.shared().isAppInBackground()
    ) -> Guarantee<Void> {
        Guarantee { seal in
            businessInjector.entityManager.performBlock {
                _ = self.businessInjector.unreadMessages.read(for: conversation, isAppInBackground: isAppInBackground)

                if conversation.unreadMessageCount == -1 {
                    self.businessInjector.entityManager.performSyncBlockAndSafe {
                        conversation.unreadMessageCount = 0
                    }
                }

                self.notificationManager.updateUnreadMessagesCount()

                seal(())
            }
        }
    }
    
    /// Marks the messages passed in from the argument as read
    /// This is a workaround implemented specifically for `ChatViewController`.
    /// - Parameters:
    ///   - conversationObjectID: The conversation to which the messages below
    ///   - messages: messages which will be marked as read
    /// - Returns: a promise which is fulfilled after all messages were marked as read containing the number of messages that were marked as read or 0 if none were marked as read.
    func read(
        _ conversationObjectID: NSManagedObjectID,
        messages: [BaseMessage]
    ) -> Guarantee<Int> {
        Guarantee { seal in
            businessInjector.entityManager.performBlock {
                let conversation = self.businessInjector.entityManager.entityFetcher
                    .getManagedObject(by: conversationObjectID) as! Conversation
                self.read(conversation, messages: messages)
                    .done { markedAsRead in
                        seal(markedAsRead)
                    }
            }
        }
    }
    
    private func read(
        _ conversation: Conversation,
        messages: [BaseMessage],
        isAppInBackground: Bool = AppDelegate.shared().isAppInBackground()
    ) -> Guarantee<Int> {
        Guarantee { seal in
            businessInjector.entityManager.performBlock {
                let markedAsRead = self.businessInjector.unreadMessages.read(
                    for: messages,
                    in: conversation,
                    isAppInBackground: isAppInBackground
                )

                self.businessInjector.entityManager.performBlockAndWait {
                    if conversation.unreadMessageCount == -1 {
                        self.businessInjector.entityManager.performSyncBlockAndSafe {
                            conversation.unreadMessageCount = 0
                        }
                    }
                }

                self.notificationManager.updateUnreadMessagesCount()

                seal(markedAsRead)
            }
        }
    }

    @objc
    @discardableResult
    func readObjc(
        _ conversation: Conversation,
        isAppInBackground: Bool = AppDelegate.shared().isAppInBackground()
    ) -> AnyPromise {
        AnyPromise(read(conversation, isAppInBackground: isAppInBackground))
    }

    func unread(_ conversation: Conversation) {

        let unreadMessagesCount = businessInjector.unreadMessages.count(for: conversation)
        guard unreadMessagesCount == 0 else {
            return
        }
        
        businessInjector.entityManager.performSyncBlockAndSafe {
            conversation.unreadMessageCount = -1
        }

        notificationManager.updateUnreadMessagesCount()
    }
    
    // MARK: - Archiving
    
    func archive(_ conversation: Conversation) {
        businessInjector.conversationStore.archive(conversation)
        notificationManager.updateUnreadMessagesCount()
    }
    
    @objc func unarchive(_ conversation: Conversation) {
        var doUpdateUnreadMessagesCount = false

        businessInjector.entityManager.performBlockAndWait {
            if conversation.conversationVisibility != .default {
                doUpdateUnreadMessagesCount = true
            }
        }

        businessInjector.conversationStore.unarchive(conversation)

        if doUpdateUnreadMessagesCount {
            notificationManager.updateUnreadMessagesCount()
        }
    }
}
