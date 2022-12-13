//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2012-2022 Threema GmbH
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

#import <CoreData/CoreData.h>
#import "MessageProcessor.h"
#import "MessageDecoder.h"
#import "BoxTextMessage.h"
#import "BoxImageMessage.h"
#import "BoxVideoMessage.h"
#import "BoxLocationMessage.h"
#import "BoxAudioMessage.h"
#import "BoxedMessage.h"
#import "BoxVoIPCallOfferMessage.h"
#import "BoxVoIPCallAnswerMessage.h"
#import "DeliveryReceiptMessage.h"
#import "TypingIndicatorMessage.h"
#import "GroupCreateMessage.h"
#import "GroupLeaveMessage.h"
#import "GroupRenameMessage.h"
#import "GroupTextMessage.h"
#import "GroupLocationMessage.h"
#import "GroupVideoMessage.h"
#import "GroupImageMessage.h"
#import "GroupAudioMessage.h"
#import "GroupSetPhotoMessage.h"
#import "LocationMessage.h"
#import "TextMessage.h"
#import "ImageMessageEntity.h"
#import "VideoMessageEntity.h"
#import "AudioMessageEntity.h"
#import "BoxFileMessage.h"
#import "GroupFileMessage.h"
#import "ContactSetPhotoMessage.h"
#import "ContactDeletePhotoMessage.h"
#import "ContactRequestPhotoMessage.h"
#import "GroupDeletePhotoMessage.h"
#import "UnknownTypeMessage.h"
#import "Contact.h"
#import "ContactStore.h"
#import "Conversation.h"
#import "ImageData.h"
#import "ThreemaUtilityObjC.h"
#import "ProtocolDefines.h"
#import "UserSettings.h"
#import "MyIdentityStore.h"
#import "AnimGifMessageLoader.h"
#import "ContactGroupPhotoLoader.h"
#import "ValidationLogger.h"
#import "BallotMessageDecoder.h"
#import "MessageSender.h"
#import "GroupMessageProcessor.h"
#import "ThreemaError.h"
#import "DatabaseManager.h"
#import "FileMessageDecoder.h"
#import "UTIConverter.h"
#import "BoxVoIPCallIceCandidatesMessage.h"
#import "BoxVoIPCallHangupMessage.h"
#import "BoxVoIPCallRingingMessage.h"
#import "NonceHasher.h"
#import "ServerConnector.h"
#import <PromiseKit/PromiseKit.h>
#import "ThreemaFramework/ThreemaFramework-Swift.h"
#import "NSString+Hex.h"

#ifdef DEBUG
  static const DDLogLevel ddLogLevel = DDLogLevelVerbose;
#else
  static const DDLogLevel ddLogLevel = DDLogLevelWarning;
#endif

@implementation MessageProcessor {
    id<MessageProcessorDelegate> messageProcessorDelegate;
    int maxBytesToDecrypt;
    int timeoutDownloadThumbnail;
    EntityManager *entityManager;
}

static dispatch_queue_t pendingGroupMessagesQueue;
static NSMutableOrderedSet *pendingGroupMessages;

- (instancetype)initWith:(id<MessageProcessorDelegate>)messageProcessorDelegate entityManager:(NSObject *)entityManagerObject {
    NSAssert([entityManagerObject isKindOfClass:[EntityManager class]], @"Object must be type of EntityManager");

    self = [super init];
    if (self) {
        self->messageProcessorDelegate = messageProcessorDelegate;
        self->maxBytesToDecrypt = 0;
        self->timeoutDownloadThumbnail = 0;
        self->entityManager = (EntityManager*)entityManagerObject;

        if (pendingGroupMessages == nil) {
            pendingGroupMessagesQueue = dispatch_queue_create("ch.threema.ServerConnector.pendingGroupMessagesQueue", NULL);
            pendingGroupMessages = [[NSMutableOrderedSet alloc] init];
        }
    }
    return self;
}

- (AnyPromise *)processIncomingMessage:(BoxedMessage*)boxmsg receivedAfterInitialQueueSend:(BOOL)receivedAfterInitialQueueSend maxBytesToDecrypt:(int)maxBytesToDecrypt timeoutDownloadThumbnail:(int)timeoutDownloadThumbnail {

    self->maxBytesToDecrypt = maxBytesToDecrypt;
    self->timeoutDownloadThumbnail = timeoutDownloadThumbnail;

    return [AnyPromise promiseWithAdapterBlock:^(PMKAdapter  _Nonnull adapter) {
        [messageProcessorDelegate beforeDecode];

        [[ContactStore sharedContactStore] fetchPublicKeyForIdentity:boxmsg.fromIdentity entityManager:entityManager onCompletion:^(NSData *publicKey) {
            NSAssert(!([NSThread isMainThread] == YES), @"Should not running in main thread");

            [entityManager performBlock:^{
                AbstractMessage *amsg = [MessageDecoder decodeFromBoxed:boxmsg withPublicKey:publicKey];
                if (amsg == nil) {
                    // Can't process message at this time, try it later
                    [messageProcessorDelegate incomingMessageFailed:boxmsg];
                    adapter(nil, [ThreemaError threemaError:@"Bad message format or decryption error" withCode:kBadMessageErrorCode]);
                    return;
                }

                if ([amsg isKindOfClass: [UnknownTypeMessage class]]) {
                    // Can't process message at this time, try it later
                    [messageProcessorDelegate incomingMessageFailed:boxmsg];
                    adapter(nil, [ThreemaError threemaError:@"Unknown message type" withCode:kUnknownMessageTypeErrorCode]);
                    return;
                }

                /* blacklisted? */
                if ([self isBlacklisted:amsg]) {
                    DDLogWarn(@"Ignoring message from blocked ID %@", boxmsg.fromIdentity);

                    // Do not process message, send server ack
                    [messageProcessorDelegate incomingMessageFailed:boxmsg];
                    adapter(nil, nil);
                    return;
                }

                // Validation logging
                if ([amsg isContentValid] == NO) {
                    NSString *errorDescription = @"Ignore invalid content";
                    if ([amsg isKindOfClass:[BoxTextMessage class]] || [amsg isKindOfClass:[GroupTextMessage class]]) {
                        [[ValidationLogger sharedValidationLogger] logBoxedMessage:boxmsg isIncoming:YES description:errorDescription];
                    } else {
                        [[ValidationLogger sharedValidationLogger] logSimpleMessage:amsg isIncoming:YES description:errorDescription];
                    }

                    // Do not process message, send server ack
                    [messageProcessorDelegate incomingMessageFailed:boxmsg];
                    adapter(nil, nil);
                    return;
                } else {
                    if ([entityManager.entityFetcher isMessageAlreadyInDb:amsg]) {
                        NSString *errorDescription = @"Message already in database";
                        if ([amsg isKindOfClass:[BoxTextMessage class]] || [amsg isKindOfClass:[GroupTextMessage class]]) {
                            [[ValidationLogger sharedValidationLogger] logBoxedMessage:boxmsg isIncoming:YES description:errorDescription];
                        } else {
                            [[ValidationLogger sharedValidationLogger] logSimpleMessage:amsg isIncoming:YES description:errorDescription];
                        }

                        // Do not process message, send server ack
                        [messageProcessorDelegate incomingMessageFailed:boxmsg];
                        adapter(nil, nil);
                        return;
                    } else {
                        if ([entityManager.entityFetcher isNonceAlreadyInDb:amsg]) {
                            NSString *errorDescription = @"Nonce already in database";
                            if ([amsg isKindOfClass:[BoxTextMessage class]] || [amsg isKindOfClass:[GroupTextMessage class]]) {
                                [[ValidationLogger sharedValidationLogger] logBoxedMessage:boxmsg isIncoming:YES description:errorDescription];
                            } else {
                                [[ValidationLogger sharedValidationLogger] logSimpleMessage:amsg isIncoming:YES description:errorDescription];
                            }

                            // Do not process message, send server ack
                            [messageProcessorDelegate incomingMessageFailed:boxmsg];
                            adapter(nil, nil);
                            return;
                        } else {
                            if ([amsg isKindOfClass:[BoxTextMessage class]] || [amsg isKindOfClass:[GroupTextMessage class]]) {
                                [[ValidationLogger sharedValidationLogger] logBoxedMessage:boxmsg isIncoming:YES description:nil];
                            } else {
                                [[ValidationLogger sharedValidationLogger] logSimpleMessage:amsg isIncoming:YES description:nil];
                            }
                        }
                    }
                }

                amsg.receivedAfterInitialQueueSend = receivedAfterInitialQueueSend;

                [self processIncomingAbstractMessage:amsg onCompletion:^(AbstractMessage *processedMsg) {
                    // Message successfully processed
                    adapter(processedMsg, nil);
                } onError:^(NSError *error) {
                    // Failed to process message, try it later
                    adapter(nil, error);
                }];
            }];
        } onError:^(NSError *error) {
            [[ValidationLogger sharedValidationLogger] logBoxedMessage:boxmsg isIncoming:YES description:@"PublicKey from Threema-ID not found"];
            // Failed to process message, try it later
            adapter(nil, error);
        }];
    }];
}

- (void)processIncomingAbstractMessage:(AbstractMessage*)amsg onCompletion:(void(^)(AbstractMessage *processedMsg))onCompletion onError:(void(^)(NSError *err))onError {
    
    if ([amsg isContentValid] == NO) {
        DDLogInfo(@"Ignore invalid content, message ID %@ from %@", amsg.messageId, amsg.fromIdentity);
        onCompletion(nil);
        return;
    }
    
    if ([entityManager.entityFetcher isMessageAlreadyInDb:amsg]) {
        DDLogInfo(@"Message ID %@ from %@ already in database", amsg.messageId, amsg.fromIdentity);
        onCompletion(nil);
        return;
    }
    
    if ([entityManager.entityFetcher isNonceAlreadyInDb:amsg]) {
        DDLogInfo(@"Message nonce from %@ already in database", amsg.fromIdentity);
        onCompletion(nil);
        return;
    }
    
    /* Find contact for message */
    if ([[ContactStore sharedContactStore] contactForIdentity:amsg.fromIdentity] == nil) {
        /* This should never happen, as without an entry in the contacts database, we wouldn't have
         been able to decrypt this message in the first place (no sender public key) */
        DDLogWarn(@"Identity %@ not in local contacts database - cannot process message", amsg.fromIdentity);
        NSError *error = [ThreemaError threemaError:[NSString stringWithFormat:@"Identity %@ not in local contacts database - cannot process message", amsg.fromIdentity]];
        onError(error);
        return;
    }
    
    /* Update public nickname in contact, if necessary */
    [[ContactStore sharedContactStore] updateNickname:amsg.fromIdentity nickname:amsg.pushFromName shouldReflect:YES];

    DDLogVerbose(@"Process incoming message: %@", amsg);
    
    [messageProcessorDelegate incomingMessageStarted:amsg];
    
    @try {
        if ([amsg isKindOfClass:[AbstractGroupMessage class]]) {
            [self processIncomingGroupMessage:(AbstractGroupMessage *)amsg onCompletion:^{
                [entityManager performSyncBlockAndSafe:^{
                    [entityManager.entityCreator nonceWithData:[NonceHasher hashedNonce:amsg.nonce]];
                }];
                
                [messageProcessorDelegate incomingMessageFinished:amsg isPendingGroup:false];
                onCompletion(amsg);
            } onError:^(NSError *error) {
                [messageProcessorDelegate incomingMessageFinished:amsg isPendingGroup:[pendingGroupMessages containsObject:amsg] == true];
                onError(error);
            }];
        } else  {
            [self processIncomingMessage:(AbstractMessage *)amsg onCompletion:^(id<MessageProcessorDelegate> _Nullable delegate) {
                if (!amsg.immediate) {
                    [entityManager performSyncBlockAndSafe:^{
                        [entityManager.entityCreator nonceWithData:[NonceHasher hashedNonce:amsg.nonce]];
                    }];
                }

                if (delegate) {
                    [delegate incomingMessageFinished:amsg isPendingGroup:false];
                }
                else {
                    [messageProcessorDelegate incomingMessageFinished:amsg isPendingGroup:false];
                }
                onCompletion(amsg);
            } onError:^(NSError *error) {
                [messageProcessorDelegate incomingMessageFinished:amsg isPendingGroup:false];
                onError(error);
            }];
        }
    } @catch (NSException *exception) {
        NSError *error = [ThreemaError threemaError:exception.description withCode:kMessageProcessingErrorCode];
        onError(error);
    } @catch (NSError *error) {
        onError(error);
    }
}

/**
Process incoming message.

@param amsg: Incoming Abstract Message
@param onCompletion: Completion handler with MessageProcessorDelegate, use it when call MessageProcessorDelegate in completion block of processVoIPCall, to prevet blocking of dispatch queue 'ServerConnector.registerMessageProcessorDelegateQueue')
@param onError: Error handler
*/
- (void)processIncomingMessage:(AbstractMessage*)amsg onCompletion:(void(^ _Nonnull)(id<MessageProcessorDelegate> _Nullable delegate))onCompletion onError:(void(^ _Nonnull)(NSError *err))onError {
    
    Conversation *conversation = [self preprocessStorableMessage:amsg];
    if ([amsg needsConversation] && conversation == nil) {
        onCompletion(nil);
        return;
    }
    
    if ([amsg isKindOfClass:[BoxTextMessage class]]) {
        TextMessage *message = [entityManager.entityCreator textMessageFromBox: amsg];
        [self finalizeMessage:message inConversation:conversation fromBoxMessage:amsg onCompletion:^{
            onCompletion(nil);
        }];
    } else if ([amsg isKindOfClass:[BoxImageMessage class]]) {
        [self processIncomingImageMessage:(BoxImageMessage *)amsg conversation:conversation onCompletion:^{
            onCompletion(nil);
        } onError:onError];
    } else if ([amsg isKindOfClass:[BoxVideoMessage class]]) {
        [self processIncomingVideoMessage:(BoxVideoMessage*)amsg conversation:conversation onCompletion:^{
            onCompletion(nil);
        } onError:onError];
    } else if ([amsg isKindOfClass:[BoxLocationMessage class]]) {
        LocationMessage *message = [entityManager.entityCreator locationMessageFromBox:(BoxLocationMessage*)amsg];
        [self resolveAddressFor:message]
        .thenInBackground(^{
            [self finalizeMessage:message inConversation:conversation fromBoxMessage:amsg onCompletion:^{
                onCompletion(nil);
            }];
        });
    } else if ([amsg isKindOfClass:[BoxAudioMessage class]]) {
        AudioMessageEntity *message = [entityManager.entityCreator audioMessageEntityFromBox:(BoxAudioMessage*) amsg];
        [self finalizeMessage:message inConversation:conversation fromBoxMessage:amsg onCompletion:^{
            onCompletion(nil);
        }];
    } else if ([amsg isKindOfClass:[DeliveryReceiptMessage class]]) {
        [self processIncomingDeliveryReceipt:(DeliveryReceiptMessage*)amsg onCompletion:^{
            onCompletion(nil);
        }];
    } else if ([amsg isKindOfClass:[TypingIndicatorMessage class]]) {
        [self processIncomingTypingIndicator:(TypingIndicatorMessage*)amsg];
        onCompletion(nil);
    } else if ([amsg isKindOfClass:[BoxBallotCreateMessage class]]) {
        BallotMessageDecoder *decoder = [[BallotMessageDecoder alloc] initWith:entityManager];
        BallotMessage *ballotMessage = [decoder decodeCreateBallotFromBox:(BoxBallotCreateMessage *)amsg forConversation:conversation];
        if (ballotMessage == nil) {
            NSError *error = [ThreemaError threemaError:@"Error parsing json for ballot create"];
            onError(error);
            return;
        }

        [self finalizeMessage:ballotMessage inConversation:conversation fromBoxMessage:amsg onCompletion:^{
            onCompletion(nil);
        }];
    } else if ([amsg isKindOfClass:[BoxBallotVoteMessage class]]) {
        [self processIncomingBallotVoteMessage:(BoxBallotVoteMessage*)amsg onCompletion:^{
            onCompletion(nil);
        } onError:onError];
    } else if ([amsg isKindOfClass:[BoxFileMessage class]]) {
        [FileMessageDecoder decodeMessageFromBox:(BoxFileMessage *)amsg forConversation:conversation timeoutDownloadThumbnail:timeoutDownloadThumbnail entityManager:entityManager onCompletion:^(BaseMessage *message) {
            // Do not download blob when message will processed via Notification Extension,
            // to keep notifications fast and because option automatically save to photos gallery
            // dosen't work within Notification Extension
            if ([AppGroup getActiveType] != AppGroupTypeNotificationExtension) {
                [self conditionallyStartLoadingFileFromMessage:(FileMessageEntity *)message];
            }
            [self finalizeMessage:message inConversation:conversation fromBoxMessage:amsg onCompletion:^{
                onCompletion(nil);
            }];
        } onError:onError];
    } else if ([amsg isKindOfClass:[ContactSetPhotoMessage class]]) {
        [self processIncomingContactSetPhotoMessage:(ContactSetPhotoMessage *)amsg onCompletion:^{
            onCompletion(nil);
        } onError:onError];
    } else if ([amsg isKindOfClass:[ContactDeletePhotoMessage class]]) {
        [self processIncomingContactDeletePhotoMessage:(ContactDeletePhotoMessage *)amsg onCompletion:^{
            onCompletion(nil);
        } onError:onError];
    } else if ([amsg isKindOfClass:[ContactRequestPhotoMessage class]]) {
        [self processIncomingContactRequestPhotoMessage:(ContactRequestPhotoMessage *)amsg onCompletion:^{
            onCompletion(nil);
        }];
    } else if ([amsg isKindOfClass:[BoxVoIPCallOfferMessage class]]) {
        [self processIncomingVoIPCallOfferMessage:(BoxVoIPCallOfferMessage *)amsg onCompletion:onCompletion onError:onError];
    } else if ([amsg isKindOfClass:[BoxVoIPCallAnswerMessage class]]) {
        [self processIncomingVoIPCallAnswerMessage:(BoxVoIPCallAnswerMessage *)amsg onCompletion:onCompletion onError:onError];
    } else if ([amsg isKindOfClass:[BoxVoIPCallIceCandidatesMessage class]]) {
        [self processIncomingVoIPCallIceCandidatesMessage:(BoxVoIPCallIceCandidatesMessage *)amsg onCompletion:onCompletion onError:onError];
    } else if ([amsg isKindOfClass:[BoxVoIPCallHangupMessage class]]) {
        [self processIncomingVoIPCallHangupMessage:(BoxVoIPCallHangupMessage *)amsg onCompletion:onCompletion onError:onError];
    } else if ([amsg isKindOfClass:[BoxVoIPCallRingingMessage class]]) {
        [self processIncomingVoipCallRingingMessage:(BoxVoIPCallRingingMessage *)amsg onCompletion:onCompletion onError:onError];
    }
    else {
        // Do not Ack message, try process this message later because of protocol changes
        onError([ThreemaError threemaError:@"Invalid message class"]);
    }
}

- (Conversation*)preprocessStorableMessage:(AbstractMessage*)msg {
    Contact *contact = [entityManager.entityFetcher contactForId: msg.fromIdentity];
    
    /* Try to find an existing Conversation for the same contact */
    // check if type allow to create the conversation
    Conversation *conversation = [entityManager conversationForContact: contact createIfNotExisting:[msg canCreateConversation]];
    
    return conversation;
}


- (void)processIncomingGroupMessage:(AbstractGroupMessage * _Nonnull)amsg onCompletion:(void(^ _Nonnull)(void))onCompletion onError:(void(^ _Nonnull)(NSError * error))onError {
    
    GroupManager *groupManager = [[GroupManager alloc] initWithEntityManager:entityManager];
    GroupMessageProcessor *groupProcessor = [[GroupMessageProcessor alloc] initWithMessage:amsg myIdentityStore:[MyIdentityStore sharedMyIdentityStore] userSettings:[UserSettings sharedUserSettings] groupManager:groupManager entityManager:entityManager];
    [groupProcessor handleMessageOnCompletion:^(BOOL didHandleMessage) {
        if (didHandleMessage) {
            if (groupProcessor.addToPendingMessages) {
                dispatch_sync(pendingGroupMessagesQueue, ^{
                    BOOL exists = NO;
                    for (AbstractGroupMessage *item in pendingGroupMessages) {
                        if ([item.messageId isEqualToData:amsg.messageId] && item.fromIdentity == amsg.fromIdentity) {
                            exists = YES;
                            break;
                        }
                    }
                    if (exists == NO) {
                        DDLogInfo(@"Pending group message add %@ %@", amsg.messageId, amsg.description);
                        [pendingGroupMessages addObject:amsg];
                    }
                });
                [messageProcessorDelegate pendingGroup:amsg];
                onError([ThreemaError threemaError:[NSString stringWithFormat:@"Group not found for this message %@", amsg.messageId]  withCode:kPendingGroupMessageErrorCode]);
                return;
            } else {
                if ([amsg isKindOfClass:[GroupCreateMessage class]]) {
                    /* process any pending group messages that could not be processed before this create */
                    [self processPendingGroupMessages:(GroupCreateMessage *)amsg];
                }
            }
            onCompletion();
            return;
        }
        // messages not handled by GroupProcessor, e.g. messages that can be processed after delayed group create
        Conversation *conversation = groupProcessor.conversation;

        if (conversation == nil) {
            onCompletion();
            return;
        }
        
        Contact *sender = [entityManager.entityFetcher contactForId: amsg.fromIdentity];
        
        if ([amsg isKindOfClass:[GroupRenameMessage class]]) {
            GroupManager *groupManager = [[GroupManager alloc] initWithEntityManager:entityManager];
            [groupManager setNameObjcWithGroupID:amsg.groupId creator:amsg.groupCreator name:((GroupRenameMessage *)amsg).name systemMessageDate:amsg.date send:YES]
                .thenInBackground(^{
                    [self changedConversationAndGroupEntityWithGroupID:amsg.groupId groupCreatorIdentity:amsg.groupCreator];
                    onCompletion();
                }).catch(^(NSError *error){
                    onError(error);
                });
        } else if ([amsg isKindOfClass:[GroupSetPhotoMessage class]]) {
            [self processIncomingGroupSetPhotoMessage:(GroupSetPhotoMessage*)amsg onCompletion:onCompletion onError:onError];
        } else if ([amsg isKindOfClass:[GroupDeletePhotoMessage class]]) {
            GroupManager *groupManager = [[GroupManager alloc] initWithEntityManager:entityManager];
            [groupManager deletePhotoObjcWithGroupID:amsg.groupId creator:amsg.groupCreator sentDate:[amsg date] send:NO]
                .thenInBackground(^{
                    [self changedConversationAndGroupEntityWithGroupID:amsg.groupId groupCreatorIdentity:amsg.groupCreator];
                    onCompletion();
                })
                .catch(^(NSError *error){
                    onError(error);
                });
        } else if ([amsg isKindOfClass:[GroupTextMessage class]]) {
            TextMessage *message = [entityManager.entityCreator textMessageFromGroupBox: (GroupTextMessage *)amsg];
            [self finalizeGroupMessage:message inConversation:conversation fromBoxMessage:amsg sender:sender onCompletion:onCompletion];
        } else if ([amsg isKindOfClass:[GroupLocationMessage class]]) {
            LocationMessage *message = [entityManager.entityCreator locationMessageFromGroupBox:(GroupLocationMessage *)amsg];
            [self resolveAddressFor:message]
            .thenInBackground(^{
                [entityManager performBlockAndWait:^{
                    BaseMessage *dbMessage = [[entityManager entityFetcher] existingObjectWithID:message.objectID];
                    Conversation *dbConversation = [[entityManager entityFetcher] existingObjectWithID:conversation.objectID];
                    Contact *dbSender = [[entityManager entityFetcher] existingObjectWithID:sender.objectID];
                    if (dbMessage == nil || dbConversation == nil || dbSender == nil) {
                        NSError *error = [ThreemaError threemaError:@"Could not complete reversing geocoding"];
                        onError(error);
                        return;
                    }

                    [self finalizeGroupMessage:dbMessage inConversation:dbConversation fromBoxMessage:amsg sender:dbSender onCompletion:onCompletion];
                }];
            });
        } else if ([amsg isKindOfClass:[GroupImageMessage class]]) {
            [self processIncomingImageMessage:(GroupImageMessage *)amsg conversation:conversation onCompletion:onCompletion onError:onError];
        } else if ([amsg isKindOfClass:[GroupVideoMessage class]]) {
            [self processIncomingVideoMessage:(GroupVideoMessage*)amsg conversation:conversation onCompletion:onCompletion onError:onError];
        } else if ([amsg isKindOfClass:[GroupAudioMessage class]]) {
            AudioMessageEntity *message = [entityManager.entityCreator audioMessageEntityFromGroupBox:(GroupAudioMessage *)amsg];
            [self finalizeGroupMessage:message inConversation:conversation fromBoxMessage:amsg sender:sender onCompletion:onCompletion];
        } else if ([amsg isKindOfClass:[GroupBallotCreateMessage class]]) {
            BallotMessageDecoder *decoder = [[BallotMessageDecoder alloc] initWith:entityManager];
            BallotMessage *message = [decoder decodeCreateBallotFromGroupBox:(GroupBallotCreateMessage *)amsg forConversation:conversation];
            if (message == nil) {
                NSError *error = [ThreemaError threemaError:@"Error parsing json for ballot create"];
                onError(error);
                return;
            }
            
            [self finalizeGroupMessage:message inConversation:conversation fromBoxMessage:amsg sender:sender onCompletion:onCompletion];
        } else if ([amsg isKindOfClass:[GroupBallotVoteMessage class]]) {
            [self processIncomingGroupBallotVoteMessage:(GroupBallotVoteMessage*)amsg onCompletion:onCompletion onError:onError];
        } else if ([amsg isKindOfClass:[GroupFileMessage class]]) {
            [FileMessageDecoder decodeGroupMessageFromBox:(GroupFileMessage *)amsg forConversation:conversation timeoutDownloadThumbnail:timeoutDownloadThumbnail entityManager:entityManager onCompletion:^(BaseMessage *message) {
                [self finalizeGroupMessage:message inConversation:conversation fromBoxMessage:amsg sender:sender onCompletion:onCompletion];
            } onError:^(NSError *err) {
                onError(err);
            }];
        } else {
            onError([ThreemaError threemaError:@"Invalid message class"]);
        }
    } onError:^(NSError *error) {
        onError(error);
    }];
}

- (void)appendNewMessage:(BaseMessage *)message toConversation:(Conversation *)conversation {
    [entityManager performSyncBlockAndSafe:^{
        message.conversation = conversation;
        if (message != nil) {
            conversation.lastMessage = message;
            conversation.lastUpdate = [NSDate date];
        }
        conversation.conversationVisibility = ConversationVisibilityDefault;
    }];

    // Refault managed object to release memory, because Core Data loads `Conversation.messages` of conversation when assign conversation
    [conversation.managedObjectContext refreshObject:conversation mergeChanges:NO];
}

- (void)finalizeMessage:(BaseMessage*)message inConversation:(Conversation*)conversation fromBoxMessage:(AbstractMessage*)boxMessage onCompletion:(void(^_Nonnull)(void))onCompletion {
    [self appendNewMessage:message toConversation:conversation];
    [messageProcessorDelegate incomingMessageChanged:message fromIdentity:boxMessage.fromIdentity];
    onCompletion();
}

- (void)finalizeGroupMessage:(BaseMessage*)message inConversation:(Conversation*)conversation fromBoxMessage:(AbstractGroupMessage*)boxMessage sender:(Contact *)sender onCompletion:(void(^_Nonnull)(void))onCompletion {
    message.sender = sender;
    [self appendNewMessage:message toConversation:conversation];

    // Refault managed object to release memory, because Core Data loads `Contact.messages` of sender when assign sender
    [sender.managedObjectContext refreshObject:sender mergeChanges:NO];

    [messageProcessorDelegate incomingMessageChanged:message fromIdentity:boxMessage.fromIdentity];
    onCompletion();
}

- (void)conditionallyStartLoadingFileFromMessage:(FileMessageEntity*)message {
    if ([UTIConverter isGifMimeType:message.mimeType] == YES) {
        // only load if not too big
        if (message.fileSize.floatValue > 1*1024*1024) {
            return;
        }
        
        AnimGifMessageLoader *loader = [[AnimGifMessageLoader alloc] init];
        [loader startWithMessage:message onCompletion:^(BaseMessage *message) {
            DDLogInfo(@"File message blob load completed");
        } onError:^(NSError *error) {
            DDLogError(@"File message blob load failed with error: %@", error);
        }];
    } else {
        if ([message renderFileImageMessage] == true || [message renderFileAudioMessage] == true) {
            BlobMessageLoader *loader = [[BlobMessageLoader alloc] init];
            [loader startWithMessage:message onCompletion:^(BaseMessage *message) {
                DDLogInfo(@"File message blob load completed");
            } onError:^(NSError *error) {
                DDLogError(@"File message blob load failed with error: %@", error);
            }];            
        }
    }
}

- (void)processIncomingImageMessage:(AbstractMessage *)amsg conversation:(Conversation *)conversation onCompletion:(void(^ _Nonnull)(void))onCompletion onError:(void(^ _Nonnull)(NSError *err))onError {
    
    assert([amsg isKindOfClass:[BoxImageMessage class]] || [amsg isKindOfClass:[GroupImageMessage class]]);
    
    if ([amsg isKindOfClass:[BoxImageMessage class]] == NO && [amsg isKindOfClass:[GroupImageMessage class]] == NO) {
        onError([ThreemaError threemaError:@"Wrong message type, must be BoxImageMessage or GroupImageMessage"]);
        return;
    }
    
    if (conversation == nil) {
        onError([ThreemaError threemaError:@"Parameter 'conversation' should be not nil"]);
        return;
    }
    
    BOOL isGroupMessage = [amsg isKindOfClass:[GroupImageMessage class]];

    Contact *sender = isGroupMessage == NO ? [conversation contact] : [entityManager.entityFetcher contactForId:amsg.fromIdentity];
    if (sender == nil) {
        onError([ThreemaError threemaError:@"Could not process image message, sender is missing"]);
        return;
    }
    
    __block ImageMessageEntity *msg;
    [entityManager performSyncBlockAndSafe:^{
        if (isGroupMessage == NO) {
            msg = [[entityManager entityCreator] imageMessageEntityFromBox:(BoxImageMessage *)amsg];
        }
        else {
            msg = [[entityManager entityCreator] imageMessageEntityFromGroupBox:(GroupImageMessage *)amsg];
            msg.sender = sender;
        }
        msg.conversation = conversation;
    }];
     
    if (msg != nil) {
        [messageProcessorDelegate incomingMessageChanged:msg fromIdentity:[sender identity]];

        dispatch_queue_t downloadQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);

        // An ImageMessage never has a local blob because all note group cabable devices send everything as FileMessage
        BlobURL *blobUrl = [[BlobURL alloc] initWithServerConnector:[ServerConnector sharedServerConnector] userSettings:[UserSettings sharedUserSettings] localOrigin:false queue:downloadQueue];
        BlobDownloader *blobDownloader = [[BlobDownloader alloc] initWithBlobURL:blobUrl queue:downloadQueue];
        ImageMessageProcessor *processor = [[ImageMessageProcessor alloc] initWithBlobDownloader:blobDownloader myIdentityStore:[MyIdentityStore sharedMyIdentityStore] userSettings:[UserSettings sharedUserSettings] entityManager:entityManager];
        [processor downloadImageWithImageMessageID:msg.id imageBlobID:msg.imageBlobId imageBlobEncryptionKey:msg.encryptionKey imageBlobNonce:msg.imageNonce senderPublicKey:sender.publicKey maxBytesToDecrypt:self->maxBytesToDecrypt timeoutDownloadThumbnail:timeoutDownloadThumbnail completion:^(NSError *error) {

            if (error != nil) {
                DDLogError(@"Could not process image message %@", error);
            }

            if (isGroupMessage == NO) {
                [self finalizeMessage:msg inConversation:conversation fromBoxMessage:amsg onCompletion:onCompletion];
            }
            else {
                [self finalizeGroupMessage:msg inConversation:conversation fromBoxMessage:(AbstractGroupMessage *)amsg sender:sender onCompletion:onCompletion];
            }
        }];
    }
    else {
        onError([ThreemaError threemaError:@"Could not process image message"]);
        return;
    }
}

- (void)processIncomingVideoMessage:(AbstractMessage *)amsg conversation:(Conversation *)conversation onCompletion:(void(^ _Nonnull)(void))onCompletion onError:(void(^ _Nonnull)(NSError *err))onError {
    
    assert([amsg isKindOfClass:[BoxVideoMessage class]] || [amsg isKindOfClass:[GroupVideoMessage class]]);
    
    if ([amsg isKindOfClass:[BoxVideoMessage class]] == NO && [amsg isKindOfClass:[GroupVideoMessage class]] == NO) {
        onError([ThreemaError threemaError:@"Wrong message type, must be BoxVideoMessage or GroupVideoMessage"]);
        return;
    }
    
    if (conversation == nil) {
        onError([ThreemaError threemaError:@"Parameter 'conversation' should be not nil"]);
        return;
    }
    
    BOOL isGroupMessage = [amsg isKindOfClass:[GroupVideoMessage class]];
    
    Contact *sender = isGroupMessage == NO ? [conversation contact] : [entityManager.entityFetcher contactForId: amsg.fromIdentity];
    if (sender == nil) {
        onError([ThreemaError threemaError:@"Could not process video message, sender is missing"]);
        return;
    }

    __block VideoMessageEntity *msg;
    __block NSData *thumbnailBlobId;
    [entityManager performSyncBlockAndSafe:^{
        if (isGroupMessage == NO) {
            BoxVideoMessage *videoMessage = (BoxVideoMessage *)amsg;
            thumbnailBlobId = [videoMessage thumbnailBlobId];
            msg = [[entityManager entityCreator] videoMessageEntityFromBox:videoMessage];
        }
        else {
            GroupVideoMessage *videoMessage = (GroupVideoMessage *)amsg;
            thumbnailBlobId = [videoMessage thumbnailBlobId];
            msg = [[entityManager entityCreator] videoMessageEntityFromGroupBox:videoMessage];
            msg.sender = sender;
        }
        msg.conversation = conversation;
        
        UIImage *thumbnailImage = [UIImage imageNamed:@"Video"];
        ImageData *thumbnail = [entityManager.entityCreator imageData];
        thumbnail.data = UIImageJPEGRepresentation(thumbnailImage, kJPEGCompressionQualityLow);
        thumbnail.width = [NSNumber numberWithInt:thumbnailImage.size.width];
        thumbnail.height = [NSNumber numberWithInt:thumbnailImage.size.height];
        msg.thumbnail = thumbnail;
    }];
     
    if (msg != nil) {
        [messageProcessorDelegate incomingMessageChanged:msg fromIdentity:[sender identity]];

        dispatch_queue_t downloadQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);

        // A VideoMessage never has a local blob because all note group cabable devices send everything as FileMessage
        BlobURL *blobUrl = [[BlobURL alloc] initWithServerConnector:[ServerConnector sharedServerConnector] userSettings:[UserSettings sharedUserSettings] localOrigin:false queue:downloadQueue];
        BlobDownloader *blobDownloader = [[BlobDownloader alloc] initWithBlobURL:blobUrl queue:downloadQueue];
        VideoMessageProcessor *processor = [[VideoMessageProcessor alloc] initWithBlobDownloader:blobDownloader entityManager:entityManager];
        [processor downloadVideoThumbnailWithVideoMessageID:msg.id thumbnailBlobID:thumbnailBlobId maxBytesToDecrypt:self->maxBytesToDecrypt timeoutDownloadThumbnail:self->timeoutDownloadThumbnail completion:^(NSError *error) {

            if (error != nil) {
                DDLogError(@"Error while downloading video thumbnail: %@", error);
            }
            
            if (isGroupMessage == NO) {
                [self finalizeMessage:msg inConversation:conversation fromBoxMessage:amsg onCompletion:onCompletion];
            }
            else {
                [self finalizeGroupMessage:msg inConversation:conversation fromBoxMessage:(AbstractGroupMessage *)amsg sender:sender onCompletion:onCompletion];
            }
        }];
    }
    else {
        onError([ThreemaError threemaError:@"Could not process video message"]);
        return;
    }
}

- (AnyPromise *)resolveAddressFor:(LocationMessage*)message {
    return [AnyPromise promiseWithResolverBlock:^(PMKResolver _Nonnull resolve) {
        /* Reverse geocoding (only necessary if there is no POI adress) */
        if (message.poiAddress == nil) {
            double latitude = message.latitude.doubleValue;
            double longitude = message.longitude.doubleValue;
            double accuracy = message.accuracy.doubleValue;
            
            // It should not result in a different address if we initialize the location with accuracies or not
            CLLocation *location = [[CLLocation alloc] initWithCoordinate:CLLocationCoordinate2DMake(latitude, longitude) altitude:0 horizontalAccuracy:accuracy verticalAccuracy:-1 timestamp:[NSDate date]];
            
            [ThreemaUtility fetchAddressFor:location completion:^(NSString *label){
                if ([message wasDeleted]) {
                    resolve(nil);
                    return;
                }
                
                [entityManager performSyncBlockAndSafe:^{
                    message.poiAddress = label;
                }];

                resolve(nil);
            } onError:^(NSError *error) {
                DDLogWarn(@"Reverse geocoding failed: %@", error);
                if ([message wasDeleted]) {
                    resolve(nil);
                    return;
                }
                
                [entityManager performSyncBlockAndSafe:^{
                    message.poiAddress = [NSString stringWithFormat:@"%.5f°, %.5f°", latitude, longitude];
                }];

                resolve(nil);
            }];
        }
        resolve(nil);
    }];
}


- (void)processIncomingDeliveryReceipt:(DeliveryReceiptMessage*)msg onCompletion:(void(^ _Nonnull)(void))onCompletion {
    [entityManager performAsyncBlockAndSafe:^{
        for (NSData *receiptMessageId in msg.receiptMessageIds) {
            /* Fetch message from DB */
            BaseMessage *dbmsg = [entityManager.entityFetcher ownMessageWithId: receiptMessageId];
            if (dbmsg == nil) {
                /* This can happen if the user deletes the message before the receipt comes in */
                DDLogWarn(@"Cannot find message ID %@ (delivery receipt from %@)", receiptMessageId, msg.fromIdentity);
                continue;
            }
            
            if (msg.receiptType == DELIVERYRECEIPT_MSGRECEIVED) {
                DDLogWarn(@"Message ID %@ has been received by recipient", [NSString stringWithHexData:receiptMessageId]);
                dbmsg.deliveryDate = msg.date;
                dbmsg.delivered = [NSNumber numberWithBool:YES];
            } else if (msg.receiptType == DELIVERYRECEIPT_MSGREAD) {
                DDLogWarn(@"Message ID %@ has been read by recipient", [NSString stringWithHexData:receiptMessageId]);
                if (!dbmsg.delivered)
                    dbmsg.delivered = [NSNumber numberWithBool:YES];
                dbmsg.readDate = msg.date;
                dbmsg.read = [NSNumber numberWithBool:YES];
            } else if (msg.receiptType == DELIVERYRECEIPT_MSGUSERACK) {
                DDLogWarn(@"Message ID %@ has been user acknowledged by recipient", [NSString stringWithHexData:receiptMessageId]);
                dbmsg.userackDate = msg.date;
                dbmsg.userack = [NSNumber numberWithBool:YES];
            } else if (msg.receiptType == DELIVERYRECEIPT_MSGUSERDECLINE) {
                DDLogWarn(@"Message ID %@ has been user declined by recipient", [NSString stringWithHexData:receiptMessageId]);
                dbmsg.userackDate = msg.date;
                dbmsg.userack = [NSNumber numberWithBool:NO];
            } else {
                DDLogWarn(@"Unknown delivery receipt type %d with message ID %@", msg.receiptType, [NSString stringWithHexData:receiptMessageId]);
            }

            [messageProcessorDelegate changedManagedObjectID:dbmsg.objectID];
        }
        
        onCompletion();
    }];
}

- (void)processIncomingTypingIndicator:(TypingIndicatorMessage*)msg {
    [messageProcessorDelegate processTypingIndicator:msg]; 
}

- (void)processIncomingGroupSetPhotoMessage:(GroupSetPhotoMessage*)msg onCompletion:(void(^)(void))onCompletion onError:(void(^)(NSError *err))onError {
    
    GroupManager *groupManager = [[GroupManager alloc] initWithEntityManager:entityManager];
    Group *group = [groupManager getGroup:msg.groupId creator:msg.groupCreator];
    if (group == nil) {
        DDLogInfo(@"Group ID %@ from %@ not found", msg.groupId, msg.groupCreator);
        onCompletion();
        return;
    } else {
        /* Start loading image */
        ContactGroupPhotoLoader *loader = [[ContactGroupPhotoLoader alloc] init];
        [loader startWithBlobId:msg.blobId encryptionKey:msg.encryptionKey onCompletion:^(NSData *imageData) {
            DDLogInfo(@"Group photo blob load completed");

            // Initialize new GroupManager with EntityManager on main context, becaus this completion handler runs on main queue
            GroupManager *grpManager = [[GroupManager alloc] initWithEntityManager:[[EntityManager alloc] init]];
            [grpManager setPhotoObjcWithGroupID:msg.groupId creator:msg.groupCreator imageData:imageData sentDate:msg.date send:NO]
                .thenInBackground(^{
                    [self changedConversationAndGroupEntityWithGroupID:msg.groupId groupCreatorIdentity:msg.groupCreator];
                    onCompletion();
                }).catch(^(NSError *error){
                    onError(error);
            });
        } onError:^(NSError *err) {
            DDLogError(@"Group photo blob load failed with error: %@", err);
            onError(err);
        }];
    }
}

- (void)processIncomingGroupBallotVoteMessage:(GroupBallotVoteMessage*)msg onCompletion:(void(^)(void))onCompletion onError:(void(^)(NSError *err))onError {
    
    /* Create Message in DB */
    BallotMessageDecoder *decoder = [[BallotMessageDecoder alloc] initWith:entityManager];
    if ([decoder decodeVoteFromGroupBox: msg] == NO) {
        onError([ThreemaError threemaError:@"Error processing ballot vote"]);
        return;
    }
    
    //persist decoded data
    [entityManager performAsyncBlockAndSafe:nil];
    
    [self changedBallotWithID:msg.ballotId];

    onCompletion();
}

- (void)processIncomingBallotVoteMessage:(BoxBallotVoteMessage*)msg onCompletion:(void(^)(void))onCompletion onError:(void(^)(NSError *err))onError {
    
    /* Create Message in DB */
    BallotMessageDecoder *decoder = [[BallotMessageDecoder alloc] initWith:entityManager];
    if ([decoder decodeVoteFromBox: msg] == NO) {
        onError([ThreemaError threemaError:@"Error parsing json for ballot vote"]);
        return;
    }
    
    //persist decoded data
    [entityManager performSyncBlockAndSafe:nil];

    [self changedBallotWithID:msg.ballotId];

    onCompletion();
}

- (void)processPendingGroupMessages:(GroupCreateMessage *)groupCreateMessage {
    DDLogVerbose(@"Processing pending group messages");
    __block NSArray *messages;

    dispatch_sync(pendingGroupMessagesQueue, ^{
        messages = [pendingGroupMessages array];
    });

    if (messages != nil) {
        DDLogInfo(@"[Push] Pending group count: %lu", [messages count]);

        for (AbstractGroupMessage *msg in messages) {
            if ([msg.groupId isEqualToData:groupCreateMessage.groupId] && [msg.groupCreator isEqualToString:groupCreateMessage.groupCreator]) {
                if ([[groupCreateMessage groupMembers] containsObject:[[MyIdentityStore sharedMyIdentityStore] identity]]) {
                    DDLogInfo(@"[Push] Pending group message process %@ %@", msg.messageId, msg.description);
                    [self processIncomingAbstractMessage:msg onCompletion:^(AbstractMessage *amsg) {
                        if (amsg != nil) {
                            // Successfully processed ack message
                            [[ServerConnector sharedServerConnector] completedProcessingAbstractMessage:amsg];
                        }

                        dispatch_sync(pendingGroupMessagesQueue, ^{
                            DDLogInfo(@"[Push] Pending group message remove %@ %@", msg.messageId, msg.description);
                            [pendingGroupMessages removeObject:msg];
                        });
                    } onError:^(NSError *err) {
                        DDLogWarn(@"Processing pending group message failed: %@", err);
                    }];
                }
                else {
                    // I am not in the group ack message
                    [[ServerConnector sharedServerConnector] completedProcessingAbstractMessage:msg];

                    dispatch_sync(pendingGroupMessagesQueue, ^{
                        DDLogInfo(@"[Push] Pending group message remove %@ %@", msg.messageId, msg.description);
                        [pendingGroupMessages removeObject:msg];
                    });
                }
            }
        }
    }
}

- (void)processIncomingContactSetPhotoMessage:(ContactSetPhotoMessage *)msg onCompletion:(void(^ _Nonnull)(void))onCompletion onError:(void(^ _Nonnull)(NSError *err))onError {
    /* Start loading image */
    ContactGroupPhotoLoader *loader = [[ContactGroupPhotoLoader alloc] init];
    
    [loader startWithBlobId:msg.blobId encryptionKey:msg.encryptionKey onCompletion:^(NSData *imageData) {
        DDLogInfo(@"contact photo blob load completed");

        // TODO call completion handler if async update profile pic is finished
        NSError *error;
        [[ContactStore sharedContactStore] updateProfilePicture:msg.fromIdentity imageData:imageData shouldReflect:YES didFailWithError:&error];
        
        if (error != nil) {
            onError(error);
            return;
        }

        [self changedContactWithIdentity:msg.fromIdentity];

        onCompletion();
    } onError:^(NSError *err) {
        DDLogError(@"Contact photo blob load failed with error: %@", err);
        if (err.code == 404)
            onCompletion();
        onError(err);
    }];
}

- (void)processIncomingContactDeletePhotoMessage:(ContactDeletePhotoMessage *)msg onCompletion:(void(^ _Nonnull)(void))onCompletion onError:(void(^ _Nonnull)(NSError *err))onError {
    [[ContactStore sharedContactStore] deleteProfilePicture:msg.fromIdentity shouldReflect:NO];
    [self changedContactWithIdentity:msg.fromIdentity];
    onCompletion();
}

- (void)processIncomingContactRequestPhotoMessage:(ContactRequestPhotoMessage *)msg onCompletion:(void(^ _Nonnull)(void))onCompletion {
    [[ContactStore sharedContactStore] removeProfilePictureFlagForIdentity:msg.fromIdentity];
    onCompletion();
}


- (void)processIncomingVoIPCallOfferMessage:(BoxVoIPCallOfferMessage *)msg onCompletion:(void(^ _Nonnull)(id<MessageProcessorDelegate> _Nullable delegate))onCompletion onError:(void(^ _Nonnull)(NSError *err))onError {
    VoIPCallOfferMessage *message = [VoIPCallMessageDecoder decodeVoIPCallOfferFrom:msg];
    if (message == nil) {
        onError([ThreemaError threemaError:@"Error parsing json for voip call offer"]);
        return;
    }
    
    [messageProcessorDelegate processVoIPCall:message identity:msg.fromIdentity onCompletion:^(id<MessageProcessorDelegate>  _Nonnull delegate) {
        onCompletion(delegate);
    }];
}

- (void)processIncomingVoIPCallAnswerMessage:(BoxVoIPCallAnswerMessage *)msg onCompletion:(void(^ _Nonnull)(id<MessageProcessorDelegate> _Nullable delegate))onCompletion onError:(void(^ _Nonnull)(NSError *err))onError {
    VoIPCallAnswerMessage *message = [VoIPCallMessageDecoder decodeVoIPCallAnswerFrom:msg];
    if (message == nil) {
        onError([ThreemaError threemaError:@"Error parsing json for ballot vote"]);
        return;
    }

    [messageProcessorDelegate processVoIPCall:message identity:msg.fromIdentity onCompletion:^(id<MessageProcessorDelegate>  _Nonnull delegate) {
        onCompletion(delegate);
    }];
}

- (void)processIncomingVoIPCallIceCandidatesMessage:(BoxVoIPCallIceCandidatesMessage *)msg onCompletion:(void(^ _Nonnull)(id<MessageProcessorDelegate> _Nullable delegate))onCompletion onError:(void(^ _Nonnull)(NSError *err))onError {
    VoIPCallIceCandidatesMessage *message = [VoIPCallMessageDecoder decodeVoIPCallIceCandidatesFrom:msg];
    if (message == nil) {
        onError([ThreemaError threemaError:@"Error parsing json for ice candidates"]);
        return;
    }

    [messageProcessorDelegate processVoIPCall:message identity:msg.fromIdentity onCompletion:^(id<MessageProcessorDelegate>  _Nonnull delegate) {
        onCompletion(delegate);
    }];
}

- (void)processIncomingVoIPCallHangupMessage:(BoxVoIPCallHangupMessage *)msg onCompletion:(void(^ _Nonnull)(id<MessageProcessorDelegate> _Nullable delegate))onCompletion onError:(void(^ _Nonnull)(NSError *err))onError {
    VoIPCallHangupMessage *message = [VoIPCallMessageDecoder decodeVoIPCallHangupFrom:msg contactIdentity:msg.fromIdentity];
    
    if (message == nil) {
        onError([ThreemaError threemaError:@"Error parsing json for hangup"]);
        return;
    }
    
    [messageProcessorDelegate processVoIPCall:message identity:nil onCompletion:^(id<MessageProcessorDelegate>  _Nullable delegate) {
        onCompletion(delegate);
    }];
}

- (void)processIncomingVoipCallRingingMessage:(BoxVoIPCallRingingMessage *)msg onCompletion:(void(^ _Nonnull)(id<MessageProcessorDelegate> _Nullable delegate))onCompletion onError:(void(^ _Nonnull)(NSError *err))onError {
    VoIPCallRingingMessage *message = [VoIPCallMessageDecoder decodeVoIPCallRingingFrom:msg contactIdentity:msg.fromIdentity];

    if (message == nil) {
        onError([ThreemaError threemaError:@"Error parsing json for ringing"]);
        return;
    }
    
    [messageProcessorDelegate processVoIPCall:message identity:nil onCompletion:^(id<MessageProcessorDelegate>  _Nonnull delegate) {
        onCompletion(delegate);
    }];
}


#pragma private methods

/// Check is the sender in the black list. If it's a group control message and the sender is on the black list, we will process the message if the group is still active on the receiver side
/// @param amsg Decoded abstract message
- (BOOL)isBlacklisted:(AbstractMessage *)amsg {
    if ([[UserSettings sharedUserSettings].blacklist containsObject:amsg.fromIdentity]) {
        if ([amsg isKindOfClass:[AbstractGroupMessage class]]) {
            AbstractGroupMessage *groupMessage = (AbstractGroupMessage *)amsg;
            GroupManager *groupManager = [[GroupManager alloc] initWithEntityManager:entityManager];
            Group *group = [groupManager getGroup:groupMessage.groupId creator:groupMessage.groupCreator];
            
            // If this group is active and the message is a group control message (create, leave, requestSync, Rename, SetPhoto, DeletePhoto)
            if (group.isSelfMember && [groupMessage isGroupControlMessage]) {
                    return false;
            }
        }
        
        return true;
    }
    return false;
}

-  (void)changedBallotWithID:(NSData * _Nonnull)ID {
    [entityManager performBlockAndWait:^{
        Ballot *ballot = [[entityManager entityFetcher] ballotForBallotId:ID];
        if (ballot) {
            [messageProcessorDelegate changedManagedObjectID:ballot.objectID];
        }
    }];
}

- (void)changedContactWithIdentity:(NSString * _Nonnull)identity {
    [entityManager performBlockAndWait:^{
        Contact *contact = [entityManager.entityFetcher contactForId:identity];
        if (contact) {
            [messageProcessorDelegate changedManagedObjectID:contact.objectID];
        }
    }];
}

- (void)changedConversationAndGroupEntityWithGroupID:(NSData * _Nonnull)groupID groupCreatorIdentity:(NSString * _Nonnull)groupCreatorIdentity {
    [entityManager performBlockAndWait:^{
        Conversation *conversation = [entityManager.entityFetcher conversationForGroupId:groupID creator:groupCreatorIdentity];
        if (conversation) {
            [messageProcessorDelegate changedManagedObjectID:conversation.objectID];

            GroupEntity *groupEntity = [[entityManager entityFetcher] groupEntityForConversation:conversation];
            if (groupEntity) {
                [messageProcessorDelegate changedManagedObjectID:groupEntity.objectID];
            }
        }
    }];
}

@end