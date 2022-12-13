//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2021-2022 Threema GmbH
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

struct AddThreemaChannelAction {
    
    private static let threemaChannelIdentity = "*THREEMA"
    
    static func run(in viewController: UIViewController) {
        if let contact = ContactStore.shared().contact(for: threemaChannelIdentity) {
            let info = notificationInfo(for: contact)
            showConversation(for: info)
            return
        }
        
        UIAlertTemplate.showAlert(
            owner: viewController,
            title: BundleUtil.localizedString(forKey: "threema_channel_intro"),
            message: BundleUtil.localizedString(forKey: "threema_channel_info"),
            titleOk: BundleUtil.localizedString(forKey: "add_button"),
            actionOk: { _ in
                addChannel(in: viewController)
            }
        )
    }
    
    private static func addChannel(in viewController: UIViewController) {
        ContactStore.shared().addContact(
            with: threemaChannelIdentity,
            verificationLevel: Int32(kVerificationLevelUnverified),
            onCompletion: { contact, _ in
                guard let contact = contact else {
                    UIAlertTemplate.showAlert(
                        owner: viewController,
                        title: BundleUtil.localizedString(forKey: "threema_channel_failed"),
                        message: nil
                    )
                    return
                }
                
                let info = notificationInfo(for: contact)
                showConversation(for: info)
                
                let initialMessages = createInitialMessages()
                dispatchInitialMessages(messages: initialMessages, with: info)
                
            }, onError: { error in
                UIAlertTemplate.showAlert(
                    owner: viewController,
                    title: BundleUtil.localizedString(forKey: "threema_channel_failed"),
                    message: error.localizedDescription
                )
            }
        )
    }
    
    private static func notificationInfo(for contact: Contact) -> [AnyHashable: Any] {
        [
            kKeyContact: contact,
            kKeyForceCompose: NSNumber(value: false),
        ]
    }
    
    private static func showConversation(for notificationInfo: [AnyHashable: Any]) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: NSNotification.Name(rawValue: kNotificationShowConversation),
                object: nil,
                userInfo: notificationInfo
            )
        }
    }
    
    private static func createInitialMessages() -> [String] {
        var initialMessages = [String]()
        
        if !(Bundle.main.preferredLocalizations[0].hasPrefix("de")) {
            initialMessages.append("en")
        }
        else {
            initialMessages.append("de")
        }
        initialMessages.append("Start News")
        initialMessages.append("Start iOS")
        initialMessages.append("Info")
        
        return initialMessages
    }
    
    private static func dispatchInitialMessages(messages: [String], with notificationInfo: [AnyHashable: Any]) {
        guard let conversation = Old_ChatViewControllerCache.getConversationForNotificationInfo(
            notificationInfo,
            createIfNotExisting: true
        ) else {
            return
        }
        
        for (index, message) in messages.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(index)) {
                MessageSender.sendMessage(
                    message,
                    in: conversation,
                    quickReply: false,
                    requestID: nil,
                    completion: nil
                )
            }
        }
    }
}