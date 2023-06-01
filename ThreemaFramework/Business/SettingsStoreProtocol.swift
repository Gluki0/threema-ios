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

import Foundation

public protocol SettingsStoreProtocol {
    
    // Privacy
    var syncContacts: Bool { get set }
    var blacklist: Set<String> { get set }
    var syncExclusionList: [String] { get set }
    var blockUnknown: Bool { get set }
    var allowOutgoingDonations: Bool { get set }
    var sendReadReceipts: Bool { get set }
    var sendTypingIndicator: Bool { get set }
    var choosePOI: Bool { get set }
    var hidePrivateChats: Bool { get set }
    
    // Notifications
    var enableMasterDnd: Bool { get set }
    var masterDndWorkingDays: Set<Int> { get set }
    var masterDndStartTime: String? { get set }
    var masterDndEndTime: String? { get set }
    var notificationType: NotificationType { get set }
    var pushShowPreview: Bool { get set }
    
    // Chat
    var wallpaperStore: WallpaperStore { get }
    var useBigEmojis: Bool { get set }
    var sendMessageFeedback: Bool { get set }

    // Calls
    var enableThreemaCall: Bool { get set }
    var alwaysRelayCalls: Bool { get set }
}

protocol SettingsStoreInternalProtocol {
    func updateSettingsStore(with syncSettings: Sync_Settings)
}
