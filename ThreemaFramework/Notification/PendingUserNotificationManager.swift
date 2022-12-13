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

import CocoaLumberjackSwift
import Foundation
import PromiseKit

public enum UserNotificationStage: String, CaseIterable {
    case initial
    case abstract
    case base
    case final
}

public protocol PendingUserNotificationManagerProtocol {
    func pendingUserNotification(for threemaPushNotification: ThreemaPushNotification, stage: UserNotificationStage)
        -> PendingUserNotification?
    func pendingUserNotification(
        for abstractMessage: AbstractMessage,
        stage: UserNotificationStage,
        isPendingGroup: Bool
    ) -> PendingUserNotification?
    func pendingUserNotification(for baseMessage: BaseMessage, fromIdentity: String, stage: UserNotificationStage)
        -> PendingUserNotification?
    func pendingUserNotification(for boxedMessage: BoxedMessage, stage: UserNotificationStage)
        -> PendingUserNotification?
    func startTimedUserNotification(pendingUserNotification: PendingUserNotification) -> Guarantee<Bool>
    func startTestUserNotification(payload: [AnyHashable: Any], completion: @escaping () -> Void)
    func editThreemaWebNotification(
        payload: [AnyHashable: Any],
        completion: @escaping (_ content: UNMutableNotificationContent) -> Void
    )
    func removeAllTimedUserNotifications(pendingUserNotification: PendingUserNotification)
    func addAsProcessed(pendingUserNotification: PendingUserNotification)
    func isProcessed(pendingUserNotification: PendingUserNotification) -> Bool
    func pendingUserNotificationsAreNotPending() -> [PendingUserNotification]?
    func hasPendingGroupUserNotifications() -> Bool
    func isValid(pendingUserNotification: PendingUserNotification) -> Bool
    func loadAll()
}

public class PendingUserNotificationManager: NSObject, PendingUserNotificationManagerProtocol {

    private let userNotificationManager: UserNotificationManagerProtocol
    private let userNotificationCenterManager: UserNotificationCenterManagerProtocol
    private let entityManager: EntityManager

    private static var pendingUserNotifications: [PendingUserNotification]?
    public static let pendingQueue = DispatchQueue(label: "ch.threema.PendingUserNotificationManager.pendingQueue")

    private static var processedUserNotifications: [String]?
    private static let processedQueue = DispatchQueue(label: "ch.threema.PendingUserNotificationManager.processedQueue")

    required init(
        _ userNotificationManager: UserNotificationManagerProtocol,
        _ userNotificationCenterManager: UserNotificationCenterManagerProtocol,
        _ entityManager: EntityManager
    ) {
        self.userNotificationManager = userNotificationManager
        self.userNotificationCenterManager = userNotificationCenterManager
        self.entityManager = entityManager
        super.init()

        loadAll()
    }
    
    public convenience init(
        _ userNotificationManager: UserNotificationManagerProtocol,
        _ entityManager: EntityManager
    ) {
        self.init(userNotificationManager, UserNotificationCenterManager(), entityManager)
    }
    
    /// Create or update pending user notification for threema push.
    /// - Parameters:
    ///     - for: Threema push
    ///     - stage: Stage for the notification, usually is 'initial'
    /// - Returns: Pending user notification or nil
    public func pendingUserNotification(
        for threemaPushNotification: ThreemaPushNotification,
        stage: UserNotificationStage
    ) -> PendingUserNotification? {
        var pendingUserNotification: PendingUserNotification?
        if let key = key(threemaPush: threemaPushNotification) {
            PendingUserNotificationManager.pendingQueue.sync {
                pendingUserNotification = getPendingUserNotification(key: key)
                pendingUserNotification?.threemaPushNotification = threemaPushNotification
                pendingUserNotification?.stage = stage
                PendingUserNotificationManager.savePendingUserNotifications()
            }
        }
        return pendingUserNotification
    }
    
    /// Create or update pending user notification for abstract message.
    /// - Parameters:
    ///     - for: Abstract message
    ///     - stage: Stage for the notification
    ///     - isPendingGroup: Set to true group was not found for this message
    /// - Returns: Pending user notification or nil, usually is 'abstract'
    public func pendingUserNotification(
        for abstractMessage: AbstractMessage,
        stage: UserNotificationStage,
        isPendingGroup: Bool
    ) -> PendingUserNotification? {
        var pendingUserNotification: PendingUserNotification?
        if let key = key(abstractMessage: abstractMessage) {
            PendingUserNotificationManager.pendingQueue.sync {
                pendingUserNotification = getPendingUserNotification(key: key)
                pendingUserNotification?.abstractMessage = abstractMessage
                pendingUserNotification?.stage = stage
                pendingUserNotification?.isPendingGroup = isPendingGroup
                PendingUserNotificationManager.savePendingUserNotifications()
            }
        }
        return pendingUserNotification
    }

    /// Create or update pending user notification for base message.
    /// - Parameters:
    ///     - for: Abstract message
    ///     - stage: Stage for the notification, usually is 'base' or 'final'
    /// - Returns: Pending user notification or nil
    public func pendingUserNotification(
        for baseMessage: BaseMessage,
        fromIdentity: String,
        stage: UserNotificationStage
    ) -> PendingUserNotification? {
        var pendingUserNotification: PendingUserNotification?
        if let key = key(fromIdentity, baseMessage.id) {
            PendingUserNotificationManager.pendingQueue.sync {
                pendingUserNotification = getPendingUserNotification(key: key)
                pendingUserNotification?.baseMessage = baseMessage
                pendingUserNotification?.stage = stage
                pendingUserNotification?.isPendingGroup = false
                PendingUserNotificationManager.savePendingUserNotifications()
            }
        }
        return pendingUserNotification
    }
    
    public func pendingUserNotification(
        for boxedMessage: BoxedMessage,
        stage: UserNotificationStage
    ) -> PendingUserNotification? {
        var pendingUserNotification: PendingUserNotification?
        if let key = key(boxedMessage.fromIdentity, boxedMessage.messageID) {
            PendingUserNotificationManager.pendingQueue.sync {
                pendingUserNotification = getPendingUserNotification(key: key)
                pendingUserNotification?.stage = stage
                pendingUserNotification?.isPendingGroup = false
                PendingUserNotificationManager.savePendingUserNotifications()
            }
        }
        return pendingUserNotification
    }

    /// Start timed notification for incoming message.
    /// - Parameter pendingUserNotification: Informations about incoming message
    /// - Returns: True pending user notification successfully processed, showed or suppressed notification
    @discardableResult public func startTimedUserNotification(pendingUserNotification: PendingUserNotification)
        -> Guarantee<Bool> {
        Guarantee { seal in
            guard isValid(pendingUserNotification: pendingUserNotification) else {
                DDLogWarn("[Push] Pending user notification is not valid")
                seal(false)
                return
            }
            
            guard !pendingUserNotification.isPendingGroup,
                  !isProcessed(pendingUserNotification: pendingUserNotification) else {
                userNotificationCenterManager.remove(key: pendingUserNotification.key, exceptStage: nil)
                seal(true)
                return
            }
            
            // Get notification content
            if let userNotificationContent = userNotificationManager.userNotificationContent(pendingUserNotification) {
                // Add notification or suppress it
                var suppress = false
                var silent = false
                if let pushSetting = userNotificationContent.pushSetting {
                    suppress = (!userNotificationContent.isGroupMessage && !pushSetting.canSendPush()) ||
                        (
                            userNotificationContent.isGroupMessage && !pushSetting
                                .canSendPush(for: userNotificationContent.baseMessage)
                        )
                    silent = pushSetting.silent
                }

                if !suppress {
                    var notification = UNMutableNotificationContent()
                    userNotificationManager.applyContent(
                        userNotificationContent,
                        &notification,
                        silent,
                        pendingUserNotification.baseMessage
                    )

                    self.userNotificationCenterManager.add(
                        key: pendingUserNotification.key,
                        stage: pendingUserNotification.stage,
                        notification: notification
                    )
                    .done { (fireDate: Date?) in
                        PendingUserNotificationManager.pendingQueue.sync {
                            pendingUserNotification.fireDate = fireDate
                            PendingUserNotificationManager.savePendingUserNotifications()
                        }
                            
                        seal(true)
                    }
                    .catch { error in
                        DDLogError(
                            "[Push] Adding notification to knotification center failed: \(error.localizedDescription)"
                        )
                        seal(false)
                    }
                }
                else {
                    userNotificationCenterManager.remove(key: pendingUserNotification.key, exceptStage: nil)
                    seal(false)
                }
            }
            else {
                userNotificationCenterManager.remove(key: pendingUserNotification.key, exceptStage: nil)
                seal(false)
            }
        }
    }
    
    /// Start test notification (necessary for customer support).
    /// - Parameters:
    ///     - payload: Information about test push
    ///     - completion: Notification's completion handler
    public func startTestUserNotification(payload: [AnyHashable: Any], completion: @escaping () -> Void) {
        let notificationContent = userNotificationManager.testNotificationContent(payload: payload)

        let notificationRequest = UNNotificationRequest(
            identifier: "PushTest",
            content: notificationContent,
            trigger: nil
        )
        let center = UNUserNotificationCenter.current()
        center.add(notificationRequest) { error in
            if let err = error {
                DDLogNotice("Error while adding test push notification: \(err)")
            }
            completion()
        }
    }
    
    /// Edit threema web notification content.
    /// - Parameters:
    ///     - payload: Information about threema web push
    ///     - completion: Notification's completion handler
    public func editThreemaWebNotification(
        payload: [AnyHashable: Any],
        completion: @escaping (_ content: UNMutableNotificationContent) -> Void
    ) {
        let notificationContent = userNotificationManager.threemaWebNotificationContent(payload: payload)
        completion(notificationContent)
    }

    /// Remove all timed user notifications from notification center for pending user notification.
    /// - Parameter pendingUserNotification: Remove all timed notifications for this pending user notification
    public func removeAllTimedUserNotifications(pendingUserNotification: PendingUserNotification) {
        userNotificationCenterManager.remove(key: pendingUserNotification.key, exceptStage: nil)
    }
    
    /// Add pending user notification as processed.
    /// - Parameter pendingUserNotification: Adding pending user notification as processed
    public func addAsProcessed(pendingUserNotification: PendingUserNotification) {
        PendingUserNotificationManager.processedQueue.sync {
            if PendingUserNotificationManager.processedUserNotifications == nil {
                PendingUserNotificationManager.processedUserNotifications = [String]()
            }
            if !(
                PendingUserNotificationManager.processedUserNotifications?
                    .contains(pendingUserNotification.key) ?? false
            ) {
                PendingUserNotificationManager.processedUserNotifications?.append(pendingUserNotification.key)
            }
            PendingUserNotificationManager.saveProcessedUserNotifications()
        }
    }
    
    /// Check is pending user notification processed.
    /// - Returns:True if pending user notification processed otherwise false
    public func isProcessed(pendingUserNotification: PendingUserNotification) -> Bool {
        var isProcessed = isProcessed(key: pendingUserNotification.key)
        if !isProcessed,
           (pendingUserNotification.stage == .final && pendingUserNotification.fireDate == nil)
           || (pendingUserNotification.fireDate != nil && pendingUserNotification.fireDate! < Date()) {

            addAsProcessed(pendingUserNotification: pendingUserNotification)

            isProcessed = true
        }
        return isProcessed
    }

    private func isProcessed(key: String) -> Bool {
        PendingUserNotificationManager.processedQueue.sync {
            PendingUserNotificationManager.processedUserNotifications?.filter { $0 == key }.count ?? 0 > 0
        }
    }
    
    /// Get a list of pending user notifications are not pending in notification center.
    /// - Returns: Pending user notifications or nil
    public func pendingUserNotificationsAreNotPending() -> [PendingUserNotification]? {
        guard let pendingUserNotifications = PendingUserNotificationManager.pendingUserNotifications,
              !pendingUserNotifications.isEmpty else {
            return nil
        }
        
        var pendingUserNotificationsAreNotPending: [PendingUserNotification]?
        
        for pendingUserNotification in pendingUserNotifications {
            if !userNotificationCenterManager.isPending(
                key: pendingUserNotification.key,
                stage: pendingUserNotification.stage
            ) {
                if pendingUserNotificationsAreNotPending == nil {
                    pendingUserNotificationsAreNotPending = [PendingUserNotification]()
                }
                pendingUserNotificationsAreNotPending?.append(pendingUserNotification)
            }
        }
        
        return pendingUserNotificationsAreNotPending
    }
    
    public func hasPendingGroupUserNotifications() -> Bool {
        var count = 0
        PendingUserNotificationManager.pendingQueue.sync {
            count = PendingUserNotificationManager.pendingUserNotifications?.filter(\.isPendingGroup).count ?? 0
        }
        return count > 0
    }

    public func isValid(pendingUserNotification: PendingUserNotification) -> Bool {
        guard pendingUserNotification.isGroupMessage != nil, pendingUserNotification.messageID != nil,
              pendingUserNotification.senderIdentity != nil else {
            return false
        }
        return true
    }

    /// Loads the lists of pending and processed user notifications.
    public func loadAll() {
        if FileManager.default.fileExists(atPath: PendingUserNotificationManager.pathProcessedUserNotifications) {
            PendingUserNotificationManager.processedQueue.sync {
                if var savedProcessedUserNotifications = NSKeyedUnarchiver
                    .unarchiveObject(
                        withFile: PendingUserNotificationManager
                            .pathProcessedUserNotifications
                    ) as? [String] {

                    var isChanged = false

                    if savedProcessedUserNotifications.count > 300 {
                        isChanged = true

                        for _ in 0...savedProcessedUserNotifications.count - 300 {
                            savedProcessedUserNotifications.remove(at: 0)
                        }
                    }

                    PendingUserNotificationManager.processedUserNotifications = savedProcessedUserNotifications

                    if isChanged {
                        PendingUserNotificationManager.saveProcessedUserNotifications()
                    }
                }
            }
        }

        if FileManager.default.fileExists(atPath: PendingUserNotificationManager.pathPendingUserNotifications) {
            PendingUserNotificationManager.pendingQueue.sync {
                if let savedPendingUserNotifications = NSKeyedUnarchiver
                    .unarchiveObject(
                        withFile: PendingUserNotificationManager
                            .pathPendingUserNotifications
                    ) as? [PendingUserNotification] {

                    guard PendingUserNotificationManager.pendingUserNotifications == nil else {
                        return
                    }
                    PendingUserNotificationManager.pendingUserNotifications = [PendingUserNotification]()

                    for pendingUserNotification in savedPendingUserNotifications {
                        if isProcessed(pendingUserNotification: pendingUserNotification) {
                            continue
                        }

                        if let exists = PendingUserNotificationManager.pendingUserNotifications?
                            .contains(where: { $0.key == pendingUserNotification.key }), exists {
                            DDLogWarn("[Push] PendingUserNotification duplicate")
                        }
                        else {
                            if pendingUserNotification.baseMessage == nil,
                               let baseMessageID = pendingUserNotification.baseMessageID {
                                pendingUserNotification.baseMessage = self.entityManager
                                    .entityFetcher.message(with: baseMessageID)
                            }
                            PendingUserNotificationManager.pendingUserNotifications?.append(pendingUserNotification)
                        }
                    }

                    PendingUserNotificationManager.savePendingUserNotifications()
                }
            }
        }
    }

    /// Caution: This function is only for unit testing!
    static func clear() {
        PendingUserNotificationManager.pendingUserNotifications = nil
        PendingUserNotificationManager.processedUserNotifications = nil
    }
    
    fileprivate static func savePendingUserNotifications() {
        do {
            if FileManager.default.fileExists(atPath: pathPendingUserNotifications) {
                try FileManager.default.removeItem(atPath: pathPendingUserNotifications)
            }
        }
        catch {
            DDLogError("[Push] Unable to delete \(pathPendingUserNotifications) file: \(error.localizedDescription)")
        }
        
        if let pendingUserNotifications = PendingUserNotificationManager.pendingUserNotifications,
           !pendingUserNotifications.isEmpty {
            _ = NSKeyedArchiver.archiveRootObject(pendingUserNotifications, toFile: pathPendingUserNotifications)
        }
    }
    
    private static func saveProcessedUserNotifications() {
        do {
            if FileManager.default.fileExists(atPath: pathProcessedUserNotifications) {
                try FileManager.default.removeItem(atPath: pathProcessedUserNotifications)
            }
        }
        catch {
            DDLogError("[Push] Unable to delete \(pathProcessedUserNotifications) file: \(error.localizedDescription)")
        }
        
        if let processedUserNotifications = PendingUserNotificationManager.processedUserNotifications,
           !processedUserNotifications.isEmpty {
            NSKeyedArchiver.archiveRootObject(processedUserNotifications, toFile: pathProcessedUserNotifications)
        }
    }
    
    static var pathPendingUserNotifications: String {
        var path: String?
        if path == nil {
            path = FileUtility.appDataDirectory!.appendingPathComponent("PendingUserNotifications").path
        }
        return path!
    }
    
    static var pathProcessedUserNotifications: String {
        var path: String?
        if path == nil {
            path = FileUtility.appDataDirectory!.appendingPathComponent("ProcessedUserNotifications").path
        }
        return path!
    }

    private func getPendingUserNotification(key: String) -> PendingUserNotification? {
        guard !isProcessed(key: key) else {
            return nil
        }
        
        var pendingUserNotification: PendingUserNotification?
        
        if PendingUserNotificationManager.pendingUserNotifications == nil {
            PendingUserNotificationManager.pendingUserNotifications = [PendingUserNotification]()
        }
    
        pendingUserNotification = PendingUserNotificationManager.pendingUserNotifications?
            .first(where: { $0.key == key })
        if pendingUserNotification == nil {
            pendingUserNotification = PendingUserNotification(key: key)
            PendingUserNotificationManager.pendingUserNotifications?.append(pendingUserNotification!)
        }
        
        return pendingUserNotification
    }

    private func key(threemaPush: ThreemaPushNotification) -> String? {
        threemaPush.from + threemaPush.messageID
    }
    
    private func key(abstractMessage: AbstractMessage) -> String? {
        key(abstractMessage.fromIdentity, abstractMessage.messageID)
    }

    // TODO: sender is nil, when MessageProcessorDelegate.finished is called?!?
//    private func key(baseMessage: BaseMessage) -> String? {
//        return key(baseMessage.sender.identity, baseMessage.id)
//    }
    
    private func key(_ fromIdentity: String?, _ messageID: Data?) -> String? {
        guard let fromIdentity = fromIdentity, let messageID = messageID else {
            return nil
        }
        
        return fromIdentity + messageID.hexString
    }
}