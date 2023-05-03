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
import Photos

// MARK: - FileMessageProvider

/// Set of supported file message types
public enum FileMessageType {
    /// An image (not animated)
    case image(ImageMessage)
    /// A sticker (not animated)
    case sticker(StickerMessage)
    /// An animated image
    case animatedImage(ImageMessage)
    /// An animated sticker
    case animatedSticker(StickerMessage)
    /// A video
    case video(VideoMessage)
    /// A voice message
    case voice(VoiceMessage)
    /// A file/document
    case file(FileMessage)
    
    /// Name of the belonging SFSymbol
    public var symbolName: String {
        switch self {
        case .image, .sticker:
            return "photo.fill"
        case .animatedImage, .animatedSticker:
            return "photo.artframe"
        case .video:
            // Own icon used because SFSymbols is reserved
            return "threema.video.fill"
        case .voice:
            return "mic.fill"
        case .file:
            return "doc.fill"
        }
    }
    
    public var defaultInteractionSymbolName: String? {
        switch self {
        case .animatedImage, .animatedSticker, .video:
            return "play.fill"
        case .image, .sticker, .voice, .file:
            return nil
        }
    }
    
    /// Localized description of the type
    public var localizedDescription: String {
        switch self {
        case .image:
            return BundleUtil.localizedString(forKey: "file_message_image")
        case .sticker, .animatedSticker:
            return BundleUtil.localizedString(forKey: "file_message_sticker")
        case .animatedImage:
            return BundleUtil.localizedString(forKey: "file_message_animated_image")
        case .video:
            return BundleUtil.localizedString(forKey: "file_message_video")
        case .voice:
            return BundleUtil.localizedString(forKey: "file_message_voice")
        case .file:
            return BundleUtil.localizedString(forKey: "file_message_file")
        }
    }
}

/// This message can be represented as a `FileMessageType`
///
/// A definition for the abstraction interface of any message that contains blob data (e.g. `FileMessage`, `ImageMessage`, ...)
public protocol FileMessageProvider: BlobData {
    /// File message type representation of this object with a blob
    var fileMessageType: FileMessageType { get }
    
    // TODO: Remove after debugging
    var thumbnailState: BlobState { get }
    var dataState: BlobState { get }
}

// MARK: - CommonFileMessageMetadata

/// Common metadata of all `FileMessageType`s
public protocol CommonFileMessageMetadata: BlobData {
    /// Blob display state of this message
    var blobDisplayState: BlobDisplayState { get }
    /// Blob file size
    var dataBlobFileSize: Measurement<UnitInformationStorage> { get }
    
    /// Caption of file message if it has any
    var caption: String? { get }
    /// When this message is displayed should it try to inline the date and state with the thumbnail?
    var showDateAndStateInline: Bool { get }
    
    /// Creates a new temporary URL to the blob data
    ///
    /// Please remove the data if it is no longer needed.
    func temporaryBlobDataURL() -> URL?
}

public extension CommonFileMessageMetadata {
    // We normally inline date and state if there is no caption
    var showDateAndStateInline: Bool {
        caption == nil
    }
}

// MARK: - ThumbnailDisplayMessage

/// General display message for message types that use a thumbnail
public protocol ThumbnailDisplayMessage: BaseMessage & FileMessageProvider & CommonFileMessageMetadata {
    /// Thumbnail representing this message
    var thumbnailImage: UIImage? { get }
    /// Aspect ratio of (thumbnail) image (heigh/width)
    var heightToWidthAspectRatio: Double { get }
    
    /// Creates a `SaveMediaItem` that can be saved to photos using `AlbumManager`
    /// - Parameter forAutosave: If the created item is used to auto save
    /// - Returns: `SaveMediaItem` to be used in AlbumManager`
    func createSaveMediaItem(forAutosave: Bool) -> AlbumManager.SaveMediaItem?
}

public extension ThumbnailDisplayMessage {
    var readableFileName: String {
        
        let mimeType = UTIConverter.mimeType(fromUTI: blobGetUTI())
        let ext = UTIConverter.preferredFileExtension(forMimeType: mimeType)
        
        return "\(ThreemaApp.currentName.replacingOccurrences(of: " ", with: "_"))_\(DateFormatter.getDateForExport(date)).\(ext ?? "")"
    }
    
    func createSaveMediaItem() -> AlbumManager.SaveMediaItem? {
        createSaveMediaItem(forAutosave: false)
    }
}

// MARK: - ImageMessage

/// A blob message that is an image. The image might be animated.
public protocol ImageMessage: ThumbnailDisplayMessage { }

// MARK: - StickerMessage

/// A blob message that is a sticker. The sticker might be animated.
public protocol StickerMessage: ThumbnailDisplayMessage { }

// MARK: - VideoMessage

public protocol VideoMessage: ThumbnailDisplayMessage {
    var durationTimeInterval: TimeInterval? { get }
}

// MARK: - VoiceMessage

public protocol VoiceMessage: BaseMessage & FileMessageProvider & CommonFileMessageMetadata {
    var durationTimeInterval: TimeInterval? { get }
}

// MARK: - FileMessage

public protocol FileMessage: BaseMessage & FileMessageProvider & CommonFileMessageMetadata {
    /// Name of file
    var name: String { get }
    /// File extension
    var `extension`: String { get }
}
