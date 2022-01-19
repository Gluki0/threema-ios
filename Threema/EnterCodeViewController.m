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

#import "EnterCodeViewController.h"
#import "MyIdentityStore.h"
#import "ServerAPIConnector.h"
#import <MBProgressHUD/MBProgressHUD.h>
#import "PhoneNumberNormalizer.h"
#import "BundleUtil.h"
#import "UIImage+ColoredImage.h"
#import "ThreemaFramework/ThreemaFramework-swift.h"

#define kCallWaitTime 600

@interface EnterCodeViewController ()

@end

@implementation EnterCodeViewController {
    NSTimer *updateTimer;
    BOOL callEnabled;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [Colors updateKeyboardAppearanceFor:self.codeTextField];
    UIImage *image = nil;
    switch ([Colors getTheme]) {
        case ColorThemeDark:
        case ColorThemeDarkWork:
            image = [BundleUtil imageNamed:@"Phone"];
            _phoneImageView.image = [image imageWithTint:[Colors fontNormal]];
            break;
        case ColorThemeLight:
        case ColorThemeLightWork:
        case ColorThemeUndefined:
            break;
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    updateTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(updateView) userInfo:nil repeats:YES];
    [self updateView];
    
    [self.codeTextField becomeFirstResponder];
}

- (void)viewWillDisappear:(BOOL)animated {
    [updateTimer invalidate];
    updateTimer = nil;
    
    [super viewWillDisappear:animated];
}

- (void)updateView {
    
    if ([MyIdentityStore sharedMyIdentityStore].linkMobileNoStartDate != nil) {
        int secondsSinceStart = -[[MyIdentityStore sharedMyIdentityStore].linkMobileNoStartDate timeIntervalSinceNow];
        
        int waitRemainingSecs = kCallWaitTime - secondsSinceStart;
        if (waitRemainingSecs < 0)
            waitRemainingSecs = 0;
        int mins = waitRemainingSecs / 60;
        int secs = waitRemainingSecs - mins * 60;
        
        self.callMeCell.detailTextLabel.text = [NSString stringWithFormat:@"%02d:%02d", mins, secs];
        
        if (waitRemainingSecs == 0) {
            self.callMeCell.detailTextLabel.hidden = YES;
            self.callMeCell.textLabel.enabled = YES;
            self.callMeCell.imageView.alpha = 1.0;
            self.callMeCell.selectionStyle = UITableViewCellSelectionStyleBlue;
            callEnabled = YES;
        } else {
            self.callMeCell.detailTextLabel.hidden = NO;
            self.callMeCell.textLabel.enabled = NO;
            self.callMeCell.imageView.alpha = 0.5;
            self.callMeCell.selectionStyle = UITableViewCellSelectionStyleNone;
            callEnabled = NO;
        }
    } else {
        self.callMeCell.detailTextLabel.hidden = YES;
        self.callMeCell.textLabel.enabled = YES;
        self.callMeCell.imageView.alpha = 1.0;
        self.callMeCell.selectionStyle = UITableViewCellSelectionStyleBlue;
        callEnabled = YES;
    }
}

- (BOOL)shouldAutorotate {
    return YES;
}

-(UIInterfaceOrientationMask)supportedInterfaceOrientations {
    if (SYSTEM_IS_IPAD) {
        return UIInterfaceOrientationMaskAll;
    }
    
    return UIInterfaceOrientationMaskAllButUpsideDown;
}

- (IBAction)cancelAction:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (IBAction)doneAction:(id)sender {
    if (self.codeTextField.text.length == 0)
        return;
    
    self.navigationItem.rightBarButtonItem.enabled = NO;
    [self.codeTextField resignFirstResponder];
    [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    
    ServerAPIConnector *conn = [[ServerAPIConnector alloc] init];
    [conn linkMobileNoWithStore:[MyIdentityStore sharedMyIdentityStore] code:self.codeTextField.text onCompletion:^(BOOL linked) {
        [MBProgressHUD hideHUDForView:self.view animated:YES];
        [self dismissViewControllerAnimated:YES completion:nil];
    } onError:^(NSError *error) {
        [MBProgressHUD hideHUDForView:self.view animated:YES];
        self.navigationItem.rightBarButtonItem.enabled = YES;
        [UIAlertTemplate showAlertWithOwner:self title:error.localizedDescription message:error.localizedFailureReason actionOk:nil];
    }];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 1 && indexPath.row == 0) {
        /* call me */
        if (!callEnabled) {
            [self.tableView deselectRowAtIndexPath:indexPath animated:NO];
            return;
        }
        
        [self.codeTextField resignFirstResponder];
        
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"call_me_title", nil) message:NSLocalizedString(@"call_me_message", nil) preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"ok", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [self.tableView deselectRowAtIndexPath:[self.tableView indexPathForSelectedRow] animated:YES];
            
            [MBProgressHUD showHUDAddedTo:self.view animated:YES];
            
            ServerAPIConnector *connector = [[ServerAPIConnector alloc] init];
            
            [connector linkMobileNoRequestCallWithStore:[MyIdentityStore sharedMyIdentityStore] onCompletion:^{
                [MBProgressHUD hideHUDForView:self.view animated:YES];
            } onError:^(NSError *error) {
                [MBProgressHUD hideHUDForView:self.view animated:YES];
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:error.localizedDescription message:error.localizedFailureReason preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"ok", nil) style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
            }];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"cancel", nil) style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
            [self.tableView deselectRowAtIndexPath:[self.tableView indexPathForSelectedRow] animated:YES];
        }]];
        if (SYSTEM_IS_IPAD == YES) {
            UIPopoverPresentationController *popOver = alert.popoverPresentationController;
            alert.popoverPresentationController.sourceView = _callMeCell;
            alert.popoverPresentationController.sourceRect = _callMeCell.bounds;
            alert.popoverPresentationController.permittedArrowDirections = UIPopoverArrowDirectionAny;
        }
        [self presentViewController:alert animated:YES completion:nil];
    } else if (indexPath.section == 1 && indexPath.row == 1) {
        /* abort verification */

        [self.codeTextField resignFirstResponder];
        
        UIAlertController *actionSheet = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"abort_verification_message", nil) message:nil preferredStyle:UIAlertControllerStyleActionSheet];
        [actionSheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"abort_verification", nil) style:UIAlertActionStyleDestructive handler:^(UIAlertAction * action) {
            [self.tableView deselectRowAtIndexPath:[self.tableView indexPathForSelectedRow] animated:YES];
            [MyIdentityStore sharedMyIdentityStore].linkMobileNoPending = NO;
            [MyIdentityStore sharedMyIdentityStore].linkMobileNoStartDate = nil;
            [MyIdentityStore sharedMyIdentityStore].linkMobileNoVerificationId = nil;
            [MyIdentityStore sharedMyIdentityStore].linkedMobileNo = nil;
            [self dismissViewControllerAnimated:YES completion:nil];
        }]];
        [actionSheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"cancel", nil) style:UIAlertActionStyleCancel handler:^(UIAlertAction * action) {
            [self.tableView deselectRowAtIndexPath:[self.tableView indexPathForSelectedRow] animated:YES];
        }]];
        if (SYSTEM_IS_IPAD == YES) {
            UIPopoverPresentationController *popOver = actionSheet.popoverPresentationController;
            actionSheet.popoverPresentationController.sourceView = _abortCell;
            actionSheet.popoverPresentationController.sourceRect = _abortCell.bounds;
            actionSheet.popoverPresentationController.permittedArrowDirections = UIPopoverArrowDirectionAny;
        }
        [self presentViewController:actionSheet animated:YES completion:nil];
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) {
        if ([MyIdentityStore sharedMyIdentityStore].linkedMobileNo == nil)
            return nil;
        
        /* get linked number, format it and return it */
        PhoneNumberNormalizer *normalizer = [PhoneNumberNormalizer sharedInstance];
        NSString *intlMobileNo = [NSString stringWithFormat:@"+%@", [MyIdentityStore sharedMyIdentityStore].linkedMobileNo];
        NSString *prettyMobileNo = nil;
        [normalizer phoneNumberToE164:intlMobileNo withDefaultRegion:[PhoneNumberNormalizer userRegion] prettyFormat:&prettyMobileNo];
        
        return [NSString stringWithFormat:@"%@: %@", NSLocalizedString(@"number", nil), prettyMobileNo];
    }
    
    return nil;
}

@end
