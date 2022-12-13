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

#import "ChatMessageCell.h"

@interface ChatBlobMessageCell : ChatMessageCell

@property UIActivityIndicatorView *activityIndicator;
@property UIProgressView *progressBar;
@property UIButton *resendButton;

- (void)updateResendButton;

- (void)updateProgress;

- (void)messageTapped:(id)sender;

- (CALayer*)bubbleMaskForImageSize:(CGSize)imageSize;

- (CALayer*)bubbleMaskWithoutArrowForImageSize:(CGSize)imageSize;

- (BOOL)showActivityIndicator;

- (BOOL)showProgressBar;

+ (CGSize)scaleImageSizeToCell:(CGSize)size forTableWidth:(CGFloat)tableWidth isGroup:(BOOL)isGroup;

@end
