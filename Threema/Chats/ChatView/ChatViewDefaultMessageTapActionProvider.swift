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

import CocoaLumberjackSwift
import Foundation

/// Default interaction for messages
///
/// Depending on the message type different things might happen: e.g. a video playing inline or a photo shown in the photo browser
class ChatViewDefaultMessageTapActionProvider: NSObject {
    
    private weak var chatViewController: ChatViewController?
    private let entityManager: EntityManager
    var fileMessagePreview: FileMessagePreview?

    private lazy var photoBrowserWrapper = MWPhotoBrowserWrapper(
        for: chatViewController!.conversation,
        in: chatViewController,
        entityManager: entityManager
    )
    
    /// Temporary file that might have ben used to show/play the cell content and should be deleted when it is not shown anymore
    private var temporaryFileToCleanUp: URL?
    
    // MARK: - Lifecycle
    
    /// Create a new copy that uses the provided ChatViewController to show details on
    /// - Parameters:
    ///   - chatViewController: ChatViewController to show details on
    ///   - entityManager: Entity Manager used for fetching any related data
    init(
        chatViewController: ChatViewController?,
        entityManager: EntityManager
    ) {
        self.chatViewController = chatViewController
        self.entityManager = entityManager
    }
    
    // MARK: - Run
    
    /// Run default action depending on the provided message
    /// - Parameter message: Message to run default action for
    func run(for message: BaseMessage, customDefaultAction: (() -> Void)? = nil) {
        switch message {
        
        case let fileMessageProvider as FileMessageProvider:
            switch fileMessageProvider.blobDisplayState {
            case .remote, .pending:
                syncBlobsAction(objectID: message.objectID)
                
            case .processed, .uploaded:
                switch fileMessageProvider.fileMessageType {
                case let .file(fileMessage):
                    guard let fileMessageEntity = fileMessage as? FileMessageEntity else {
                        return
                    }
                    
                    fileMessagePreview = FileMessagePreview(for: fileMessageEntity)
                    fileMessagePreview?.show(on: chatViewController?.navigationController)
                    
                case let .video(videoMessage):
                    play(videoMessage: videoMessage)
                case .animatedImage, .animatedSticker:
                    customDefaultAction?()
                default:
                    photoBrowserWrapper.openPhotoBrowser(for: message)
                }
            case .downloading, .uploading:
                cancelBlobSyncAction(objectID: message.objectID)
            case .dataDeleted, .fileNotFound:
                return
            }
            
        case let locationMessage as LocationMessage:
            showLocationDetails(locationMessage: locationMessage)
        
        case let ballotMessage as BallotMessage:
            showBallot(ballotMessage: ballotMessage)
        
        case let systemMessage as SystemMessage:
            switch systemMessage.systemMessageType {
            case .callMessage:
                startVoIPCall(callMessage: systemMessage)
            case .systemMessage, .workConsumerInfo:
                return
            }
        
        default:
            assertionFailure("[ChatViewDefaultMessageTapActionProvider] no action for this cell available.")
            DDLogError("[ChatViewDefaultMessageTapActionProvider] no action for this cell available.")
        }
    }
    
    // MARK: - Actions
    
    private func play(videoMessage: VideoMessage) {
        // This plays a video directly using the default UI.
        // This should be revised when a more coherent interface for file cell interactions is implemented
        // (e.g. a replacement of the current MWPhotoBrowser (IOS-559))
        guard let temporaryBlobDataURL = videoMessage.temporaryBlobDataURL else {
            DDLogError("Unable to play video")
            NotificationPresenterWrapper.shared.present(type: .playingError)
            return
        }
        
        temporaryFileToCleanUp = temporaryBlobDataURL
        
        let player = AVPlayer(url: temporaryBlobDataURL)
        let playerViewController = AVPlayerViewController()
        playerViewController.player = player
        playerViewController.delegate = self

        chatViewController?.present(playerViewController, animated: true) {
            player.play()
        }
    }
    
    private func showLocationDetails(locationMessage: LocationMessage) {
        // Opens the location of a location message in a modal
        guard let locationVC = LocationViewController(locationMessage: locationMessage) else {
            return
        }
        let modalNavController = ModalNavigationController(rootViewController: locationVC)
        modalNavController.showLeftDoneButton = true
        chatViewController?.present(modalNavController, animated: true)
    }
    
    private func showBallot(ballotMessage: BallotMessage) {
        // Opens the ballot of a ballot message in a modal
        BallotDispatcher.showViewController(for: ballotMessage.ballot, on: chatViewController?.navigationController)
    }
    
    private func startVoIPCall(callMessage: SystemMessage) {
        // Starts a VoIP Call if contact supports it
        if UserSettings.shared()?.enableThreemaCall == true,
           let contact = callMessage.conversation?.contact {
            let contactSet = Set<Contact>([contact])

            FeatureMask.check(Int(FEATURE_MASK_VOIP), forContacts: contactSet) { unsupportedContacts in
                if unsupportedContacts?.isEmpty == true {
                    self.chatViewController?.startVoIPCall()
                }
                // TODO: (IOS-3058) Show error to user
            }
        }
    }
    
    private func syncBlobsAction(objectID: NSManagedObjectID) {
        Task {
            await BlobManager.shared.syncBlobs(for: objectID)
        }
    }
    
    private func cancelBlobSyncAction(objectID: NSManagedObjectID) {
        Task {
            await BlobManager.shared.cancelBlobsSync(for: objectID)
        }
    }
}

// MARK: - AVPlayerViewControllerDelegate

extension ChatViewDefaultMessageTapActionProvider: AVPlayerViewControllerDelegate {
    func playerViewControllerDidEndDismissalTransition(_ playerViewController: AVPlayerViewController) {
        // Delete temporary file that was played if there was any
        FileUtility.delete(at: temporaryFileToCleanUp)
    }
}
