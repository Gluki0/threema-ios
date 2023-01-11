//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2014-2022 Threema GmbH
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

#import "GroupAudioMessage.h"
#import "ProtocolDefines.h"

@implementation GroupAudioMessage

@synthesize duration;
@synthesize audioBlobId;
@synthesize audioSize;
@synthesize encryptionKey;

- (uint8_t)type {
    return MSGTYPE_GROUP_AUDIO;
}

- (NSData *)body {
    NSMutableData *body = [NSMutableData dataWithData:[self.groupCreator dataUsingEncoding:NSASCIIStringEncoding]];
    [body appendData:self.groupId];
    [body appendBytes:&duration length:sizeof(uint16_t)];
    [body appendData:audioBlobId];
    [body appendBytes:&audioSize length:sizeof(uint32_t)];
    [body appendData:encryptionKey];
    
    return body;
}

- (BOOL)flagShouldPush {
    return YES;
}

-(BOOL)isContentValid {
    if (audioSize == 0) {
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
        self.duration = (uint16_t)[decoder decodeIntegerForKey:@"duration"];
        self.audioBlobId = [decoder decodeObjectForKey:@"audioBlobId"];
        self.audioSize = (uint32_t)[decoder decodeIntegerForKey:@"audioSize"];
        self.encryptionKey = [decoder decodeObjectForKey:@"encryptionKey"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)encoder {
    [super encodeWithCoder:encoder];
    [encoder encodeInt:self.duration forKey:@"duration"];
    [encoder encodeObject:self.audioBlobId forKey:@"audioBlobId"];
    [encoder encodeInt:self.audioSize forKey:@"audioSize"];
    [encoder encodeObject:self.encryptionKey forKey:@"encryptionKey"];
}

@end
