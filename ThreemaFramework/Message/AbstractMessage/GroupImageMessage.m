//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2013-2022 Threema GmbH
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

#import "GroupImageMessage.h"
#import "ProtocolDefines.h"

@implementation GroupImageMessage

@synthesize blobId;
@synthesize size;
@synthesize encryptionKey;

- (uint8_t)type {
    return MSGTYPE_GROUP_IMAGE;
}

- (NSData *)body {
    NSMutableData *body = [NSMutableData dataWithData:[self.groupCreator dataUsingEncoding:NSASCIIStringEncoding]];
    [body appendData:self.groupId];
    [body appendData:blobId];
    [body appendBytes:&size length:sizeof(uint32_t)];
    [body appendData:encryptionKey];
    
    return body;
}

- (BOOL)flagShouldPush {
    return YES;
}

-(BOOL)isContentValid {
    if (size == 0) {
        return NO;
    }
    
    return YES;
}

- (BOOL)allowSendingProfile {
    return YES;
}

#pragma mark - NSCoding

- (id)initWithCoder:(NSCoder *)decoder {
    if (self = [super initWithCoder:decoder]) {
        self.blobId = [decoder decodeObjectForKey:@"blobId"];
        self.size = (uint32_t)[decoder decodeIntegerForKey:@"size"];
        self.encryptionKey = [decoder decodeObjectForKey:@"encryptionKey"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)encoder {
    [super encodeWithCoder:encoder];
    [encoder encodeObject:self.blobId forKey:@"blobId"];
    [encoder encodeInt:self.size forKey:@"size"];
    [encoder encodeObject:self.encryptionKey forKey:@"encryptionKey"];
}

@end
