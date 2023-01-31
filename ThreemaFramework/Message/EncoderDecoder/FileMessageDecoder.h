//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2015-2023 Threema GmbH
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

#import <Foundation/Foundation.h>
#import "BoxFileMessage.h"
#import "GroupFileMessage.h"
#import "Conversation.h"

@interface FileMessageDecoder : NSObject

+ (void)decodeMessageFromBox:(BoxFileMessage *)message forConversation:conversation isReflectedMessage:(BOOL)isReflected timeoutDownloadThumbnail:(int)timeout entityManager:(nonnull NSObject *)entityManagerObject onCompletion:(void(^)(BaseMessage *message))onCompletion onError:(void(^)(NSError *err))onError;

+ (void)decodeGroupMessageFromBox:(GroupFileMessage *)message forConversation:conversation isReflectedMessage:(BOOL)isReflected timeoutDownloadThumbnail:(int)timeout entityManager:(nonnull NSObject *)entityManagerObject onCompletion:(void(^)(BaseMessage *message))onCompletion onError:(void(^)(NSError *err))onError;

+ (nullable NSString *)decodeFilenameFromBox:(nonnull BoxFileMessage *)message;

+ (nullable NSString *)decodeGroupFilenameFromBox:(nonnull GroupFileMessage *)message;

+ (nullable NSString *)decodeFileCaptionFromBox:(nonnull BoxFileMessage *)message;

+ (nullable NSString *)decodeGroupFileCaptionFromBox:(nonnull GroupFileMessage *)message;

@end
