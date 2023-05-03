//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2013-2023 Threema GmbH
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

#import "GroupTextMessage.h"
#import "ProtocolDefines.h"
#import "QuoteUtil.h"

@implementation GroupTextMessage

@synthesize text;
@synthesize quotedMessageId;

- (uint8_t)type {
    return MSGTYPE_GROUP_TEXT;
}

- (NSData *)body {
    NSMutableData *body = [NSMutableData dataWithData:[self.groupCreator dataUsingEncoding:NSASCIIStringEncoding]];
    
    [body appendData:self.groupId];
    [body appendData:[text dataUsingEncoding:NSUTF8StringEncoding]];
    
    return body;
}

- (BOOL)flagShouldPush {
    return YES;
}

-(BOOL)isContentValid {
    if (text.length == 0) {
        return NO;
    }
    
    return YES;
}

- (BOOL)allowSendingProfile {
    return YES;
}

- (NSData *)quotedBody {
    NSString *quotedText = self.quotedMessageId != nil ? [QuoteUtil generateText:self.text quotedId:self.quotedMessageId] : self.text;

    NSMutableData *body = [NSMutableData dataWithData:[self.groupCreator dataUsingEncoding:NSASCIIStringEncoding]];
    [body appendData:self.groupId];
    [body appendData:[quotedText dataUsingEncoding:NSUTF8StringEncoding]];
    return body;
}

#pragma mark - NSCoding

- (id)initWithCoder:(NSCoder *)decoder {
    if (self = [super initWithCoder:decoder]) {
        self.text = [decoder decodeObjectForKey:@"text"];
        self.quotedMessageId = [decoder decodeObjectForKey:@"quotedMessageId"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)encoder {
    [super encodeWithCoder:encoder];
    [encoder encodeObject:self.text forKey:@"text"];
    [encoder encodeObject:self.quotedMessageId forKey:@"quotedMessageId"];
}

@end
