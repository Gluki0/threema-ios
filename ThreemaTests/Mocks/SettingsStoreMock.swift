//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2022 Threema GmbH
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
@testable import ThreemaFramework

class SettingsStoreMock: SettingsStoreProtocol, SettingsStoreInternalProtocol {

    var syncContacts = true
    
    var blacklist = Set<String>()
    
    var syncExclusionList = [String]()
    
    var blockUnknown = true
    
    var allowOutgoingDonations = false

    var sendReadReceipts = true
    
    var sendTypingIndicator = true
    
    var choosePOI = true
    
    var hidePrivateChats = true
    
    var enableMasterDnd = false
    
    var masterDndWorkingDays: Set<Int> = []
    
    var masterDndStartTime: String?
    
    var masterDndEndTime: String?
    
    var notificationType: ThreemaFramework.NotificationType = .restrictive

    var pushShowPreview = false
    
    var wallpaperStore = WallpaperStore.shared
    
    var useBigEmojis = false
    
    var sendMessageFeedback = false
    
    var enableThreemaCall = true
    
    var alwaysRelayCalls = false
    
    func updateSettingsStore(with syncSettings: Sync_Settings) {
        // Noop
    }
}
