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

import Foundation
import ThreemaProtocols

/// Protocol that allows delegation from the `GroupCallActor` to the `GroupCallManager`
protocol GroupCallActorManagerDelegate: AnyObject {
    /// Used to provide `GroupCallBannerButtonUpdate`s to the UI-elements via the `GroupCallManager`
    /// - Parameter groupCallBannerButtonUpdate: `GroupCallBannerButtonUpdate` containing the update info
    func updateGroupCallButtonsAndBanners(groupCallBannerButtonUpdate: GroupCallBannerButtonUpdate) async
    
    /// Handles the given `WrappedGroupCallStartMessage`
    /// - Parameter wrappedMessage: `WrappedGroupCallStartMessage`
    func sendStartCallMessage(_ wrappedMessage: WrappedGroupCallStartMessage) async throws
    
    /// Adds an `GroupCallActor` to the currently running group calls
    /// - Parameter groupCall: `GroupCallActor` to keep track off
    func addToRunningGroupCalls(groupCall: GroupCallActor) async
    
    /// Removes an `GroupCallActor` from the currently running group calls
    /// - Parameter groupCall: `GroupCallActor` to remove
    func removeFromRunningGroupCalls(groupCall: GroupCallActor) async
    
    /// Starts and runs the refresh steps
    func startRefreshSteps() async
}