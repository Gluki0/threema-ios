//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2015-2022 Threema GmbH
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

#import "PickerContactCell.h"
#import "AvatarMaker.h"
#import "BundleUtil.h"
#import "UserSettings.h"
#import "Utils.h"

@implementation PickerContactCell

- (void)awakeFromNib {
    [super awakeFromNib];
    _nameLabel.font = [UIFont boldSystemFontOfSize: _nameLabel.font.pointSize];
    
    _threemaTypeIcon.image = [Utils threemaTypeIcon];
}

- (void)setContact:(Contact *)contact {
    if (_contact != contact) {
        _contact = contact;
        
        _nameLabel.contact = contact;
        _identityLabel.text = contact.identity;
        _verificationLevelImage.image = [contact verificationLevelImageSmall];
        
        _avatarImage.image = [BundleUtil imageNamed:@"Unknown"];
        [[AvatarMaker sharedAvatarMaker] avatarForContact:contact size:_avatarImage.frame.size.width masked:NO onCompletion:^(UIImage *avatarImage) {
            dispatch_async(dispatch_get_main_queue(), ^{
                _avatarImage.image = avatarImage;
            });
        }];
        
        
        _avatarImage.layer.cornerRadius = _avatarImage.frame.size.height /2;
        _avatarImage.layer.masksToBounds = YES;
        [self updateState];
        
        _nameLabel.highlightedTextColor = _nameLabel.textColor;
        
        _threemaTypeIcon.hidden = [Utils hideThreemaTypeIconForContact:self.contact];
    }
}

- (void)updateState {
    if ([_contact isActive]) {
        _verificationLevelImage.alpha = 1.0;
        _avatarImage.alpha = 1.0;
        _threemaTypeIcon.alpha = 1.0;
        self.userInteractionEnabled = YES;
    } else {
        _verificationLevelImage.alpha = 0.5;
        _avatarImage.alpha = 0.5;
        _threemaTypeIcon.alpha = 0.5;
        self.userInteractionEnabled = YES;
    }
}

@end

