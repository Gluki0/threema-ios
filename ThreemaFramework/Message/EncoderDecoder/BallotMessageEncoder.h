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

#import <Foundation/Foundation.h>
#import "BoxBallotCreateMessage.h"
#import "BoxBallotVoteMessage.h"
#import "GroupBallotCreateMessage.h"
#import "GroupBallotVoteMessage.h"

#import "Ballot.h"

NS_ASSUME_NONNULL_BEGIN

@interface BallotMessageEncoder : NSObject

+ (BoxBallotCreateMessage *)encodeCreateMessageForBallot:(Ballot *)ballot;

+ (BoxBallotVoteMessage *)encodeVoteMessageForBallot:(Ballot *)ballot;

+ (GroupBallotCreateMessage *)groupBallotCreateMessageFrom:(BoxBallotCreateMessage *)boxBallotMessage forConversation:(Conversation *)conversation;

+ (GroupBallotVoteMessage *)groupBallotVoteMessageFrom:(BoxBallotVoteMessage *)boxBallotMessage forConversation:(Conversation *)conversation;

+ (BOOL)passesSanityCheck:(nullable Ballot *) ballot;

@end

NS_ASSUME_NONNULL_END