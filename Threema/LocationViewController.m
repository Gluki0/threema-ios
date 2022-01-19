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

#import "LocationViewController.h"
#import "LocationMessage.h"
#import "Conversation.h"
#import "Contact.h"
#import "MyIdentityStore.h"
#import "UIImage+ColoredImage.h"

#ifdef DEBUG
  static const DDLogLevel ddLogLevel = DDLogLevelVerbose;
#else
  static const DDLogLevel ddLogLevel = DDLogLevelWarning;
#endif
@interface LocationViewController () <CLLocationManagerDelegate>
    @property CLLocationManager *locationManager;
@end

@implementation LocationViewController {
    NSInteger showInMapsButtonIndex;
    NSInteger calculateRouteButtonIndex;
    BOOL annotationSelected;
}

@synthesize locationMessage;

- (void)dealloc {
    self.mapView.delegate = nil;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.mapView.userTrackingMode = MKUserTrackingModeNone;
    self.mapView.showsUserLocation = YES;
    
    MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance(self.coordinate, 1000, 1000);
    [self.mapView setRegion:region animated:NO];

    [self setupColors];
}

- (void)setupColors {
    [self.view setBackgroundColor:[Colors backgroundLight]];
    [self.toolbar setTintColor:[Colors main]];
    [self.toolbar setBarTintColor:[Colors background]];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    [self checkPermissions];
    
    [self.mapView removeAnnotation:self];
    [self.mapView addAnnotation:self];
    
    [self.mapView removeOverlays:self.mapView.overlays];
    
    DDLogVerbose(@"accuracy: %f", self.locationMessage.accuracy.doubleValue);
    if (self.locationMessage.accuracy != nil && self.locationMessage.accuracy.doubleValue > 5.0) {
        MKCircle *accuracyCircle = [MKCircle circleWithCenterCoordinate:self.coordinate radius:self.locationMessage.accuracy.doubleValue];
        [self.mapView addOverlay:accuracyCircle];
    }
    
    MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance(self.coordinate, 1000, 1000);
    [self.mapView setRegion:region animated:NO];
}

- (void)viewDidDisappear:(BOOL)animated {
    /* must remove annotation or we will cause retain cycle */
    [self.mapView removeAnnotation:self];
    
    [super viewDidDisappear:animated];
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

- (CLLocationCoordinate2D)coordinate {
    return CLLocationCoordinate2DMake(self.locationMessage.latitude.doubleValue, self.locationMessage.longitude.doubleValue);
}

- (IBAction)actionButton:(id)sender {
    UIAlertController *actionSheet = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [actionSheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"show_in_maps", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
        [self showInMaps];
    }]];
    [actionSheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"calculate_route", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
        [self calculateRoute];
    }]];
    [actionSheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"cancel", nil) style:UIAlertActionStyleCancel handler:nil]];
    
    [self presentViewController:actionSheet animated:YES completion:nil];
}

- (IBAction)mapTypeChanged:(id)sender {
    switch (self.mapTypeControl.selectedSegmentIndex) {
        case 0:
            self.mapView.mapType = MKMapTypeStandard;
            break;
        case 1:
            self.mapView.mapType = MKMapTypeHybrid;
            break;
        case 2:
            self.mapView.mapType = MKMapTypeSatellite;
            break;
    }
}

- (IBAction)gotoUserLocationButtonTapped:(id)sender {
    MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance(self.mapView.userLocation.location.coordinate, 1000, 1000);
    [self.mapView setRegion:region animated:YES];
}

- (IBAction)gotoLocationButtonTapped:(id)sender {
    MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance(self.coordinate, 1000, 1000);
    [self.mapView setRegion:region animated:YES];
}

- (NSString *)title {
    if (self.locationMessage.isOwn.boolValue) {
        if ([MyIdentityStore sharedMyIdentityStore].pushFromName != nil)
            return [MyIdentityStore sharedMyIdentityStore].pushFromName;
        else
            return [MyIdentityStore sharedMyIdentityStore].identity;
    } else {
        if (self.locationMessage.sender != nil)
            return self.locationMessage.sender.displayName;
        else
            return self.locationMessage.conversation.contact.displayName;
    }
}

- (NSString *)subtitle {
    return [DateFormatter mediumStyleDateTime:self.locationMessage.remoteSentDate];
}

- (MKAnnotationView *)mapView:(MKMapView *)mapView viewForAnnotation:(id<MKAnnotation>)annotation {
    
    if (annotation == self) {
        if (@available(iOS 11.0, *)) {
            static NSString *markerAnnotationIdentifier = @"MarkerAnnotation";
            MKMarkerAnnotationView *markerAnnotation = (MKMarkerAnnotationView*)[mapView dequeueReusableAnnotationViewWithIdentifier:markerAnnotationIdentifier];
            if (markerAnnotation == nil) {
                markerAnnotation = [[MKMarkerAnnotationView alloc] initWithAnnotation:self reuseIdentifier:markerAnnotationIdentifier];
                markerAnnotation.canShowCallout = true;
                markerAnnotation.markerTintColor = [Colors main];
                markerAnnotation.animatesWhenAdded = true;
            }
            return markerAnnotation;
        } else {
            static NSString *pinAnnotationIdentifier = @"PinAnnotation";
            MKPinAnnotationView *pinAnnotation = (MKPinAnnotationView*)[mapView dequeueReusableAnnotationViewWithIdentifier:pinAnnotationIdentifier];
            if (pinAnnotation == nil) {
                pinAnnotation = [[MKPinAnnotationView alloc] initWithAnnotation:self reuseIdentifier:pinAnnotationIdentifier];
                pinAnnotation.canShowCallout = YES;
                pinAnnotation.pinTintColor = [Colors main];
                pinAnnotation.animatesDrop = true;
            }
            return pinAnnotation;
        }
    }
    
    return nil;
}

- (MKOverlayRenderer *)mapView:(MKMapView *)mapView rendererForOverlay:(id<MKOverlay>)overlay {
    if ([overlay isKindOfClass:[MKCircle class]]) {
        MKCircleRenderer *circelRenderer = [[MKCircleRenderer alloc] initWithCircle:overlay];
        circelRenderer.fillColor = [UIColor colorWithRed:0.48 green:0.86 blue:0.11 alpha:0.3];
        circelRenderer.strokeColor = [UIColor colorWithRed:0.48 green:0.86 blue:0.11 alpha:0.7];
        circelRenderer.lineWidth = 2.0 * [UIScreen mainScreen].scale;
        
        return circelRenderer;
    }
    
    return nil;
}

- (void)mapViewDidFinishLoadingMap:(MKMapView *)mapView {
    if (!annotationSelected) {
        [mapView selectAnnotation:self animated:YES];
        annotationSelected = YES;
    }
}

- (void)mapView:(MKMapView *)mapView didUpdateUserLocation:(MKUserLocation *)userLocation {
    /* do nothing */
}

- (void)showInMaps {
    
    Class itemClass = [MKMapItem class];
    if (itemClass && [itemClass respondsToSelector:@selector(openMapsWithItems:launchOptions:)]) {
        MKMapItem *mapItem = [[MKMapItem alloc] initWithPlacemark:[[MKPlacemark alloc] initWithCoordinate:self.coordinate addressDictionary:nil]];
        mapItem.name = self.title;
        [mapItem openInMapsWithLaunchOptions:nil];
    } else {
        /* IOS 5 */
        NSString *mapsUrl = [NSString stringWithFormat:@"http://maps.apple.com/maps?ll=%f,%f", self.coordinate.latitude, self.coordinate.longitude];
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:mapsUrl] options:@{} completionHandler:nil];
    }
}

- (void)calculateRoute {
    
    Class itemClass = [MKMapItem class];
    if (itemClass && [itemClass respondsToSelector:@selector(openMapsWithItems:launchOptions:)]) {
        MKMapItem *mapItem = [[MKMapItem alloc] initWithPlacemark:[[MKPlacemark alloc] initWithCoordinate:self.coordinate addressDictionary:nil]];
        mapItem.name = self.title;
        [mapItem openInMapsWithLaunchOptions:[NSDictionary dictionaryWithObject:MKLaunchOptionsDirectionsModeDriving forKey:MKLaunchOptionsDirectionsModeKey]];
    } else {
        /* IOS 5 */
        CLLocation *myLocation = self.mapView.userLocation.location;
        NSString *mapsUrl = [NSString stringWithFormat:@"http://maps.apple.com/maps?saddr=%f,%f&daddr=%f,%f",
                             myLocation.coordinate.latitude, myLocation.coordinate.longitude, self.coordinate.latitude, self.coordinate.longitude];
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:mapsUrl] options:@{} completionHandler:nil];
    }
}

- (void)checkPermissions {
    _locationManager = [[CLLocationManager alloc] init];
    [_locationManager requestWhenInUseAuthorization];
    _locationManager.delegate = self;
}

#pragma mark - CLLocationManagerDelegate

-(void)locationManager:(CLLocationManager *)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status {
    if (status == kCLAuthorizationStatusAuthorizedAlways || status == kCLAuthorizationStatusAuthorizedWhenInUse) {
        self.mapView.showsUserLocation = YES;
    } else {
        self.mapView.showsUserLocation = NO;
    }
}

@end
