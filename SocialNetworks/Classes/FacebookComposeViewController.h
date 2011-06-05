// Copyright 2011 Cooliris, Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

/* The application's Info.plist must contain an entry as such:
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeRole</key>
      <string>Viewer</string>
      <key>CFBundleURLName</key>
      <string>com.cooliris.${PRODUCT_NAME:rfc1034identifier}.facebook</string>
      <key>CFBundleURLSchemes</key>
      <array>
        <string>fb{APPLICATION_ID}</string>
      </array>
    </dict>
  </array>
*/

#import <UIKit/UIKit.h>

@class FacebookComposeViewController;

@protocol FacebookComposeViewControllerDelegate <NSObject>
@optional
- (void) facebookComposeViewControllerDidFailAuthenticating:(FacebookComposeViewController*)controller withError:(NSError*)error;  // Error may be nil
- (void) facebookComposeViewControllerDidStartPosting:(FacebookComposeViewController*)controller;
- (void) facebookComposeViewControllerDidSucceedPosting:(FacebookComposeViewController*)controller;
- (void) facebookComposeViewControllerDidFailPosting:(FacebookComposeViewController*)controller withError:(NSError*)error;  // Error may be nil
- (void) facebookComposeViewControllerDidCancelPosting:(FacebookComposeViewController*)controller;
@end

@interface FacebookComposeViewController : UINavigationController {
@private
  id<FacebookComposeViewControllerDelegate> _facebookDelegate;
}
@property(nonatomic, assign) id<FacebookComposeViewControllerDelegate> facebookComposeDelegate;
+ (void) resetAuthentication;
- (BOOL) handleOpenURL:(NSURL*)url;  // To be called from -application:handleOpenURL:
@end

@interface FacebookWallComposeViewController : FacebookComposeViewController
- (id) initWithFacebookApplicationID:(NSString*)applicationID
                      amazonS3Bucket:(NSString*)bucket
                         accessKeyID:(NSString*)accessKeyID
                     secretAccessKey:(NSString*)secretAccessKey;
- (void) setMessage:(NSString*)message;  // To be called prior to display
- (void) setPhotoWithImage:(UIImage*)image;  // To be called prior to display
- (void) setPhotoWithFile:(NSString*)file;  // To be called prior to display
- (void) setPhotoName:(NSString*)name;  // To be called prior to display - Not user editable - Ignored
- (void) setPhotoCaption:(NSString*)caption;  // To be called prior to display - Not user editable
- (void) setPhotoDescription:(NSString*)description;  // To be called prior to display - Not user editable
- (void) setPhotoURL:(NSURL*)url;  // To be called prior to display - Not user editable
- (void) setLinkTitle:(NSString*)title;  // To be called prior to display - Not user editable
- (void) setLinkURL:(NSURL*)url;  // To be called prior to display - Not user editable
@end

@interface FacebookAlbumComposeViewController : FacebookComposeViewController
- (id) initWithFacebookApplicationID:(NSString*)applicationID;
- (void) setPhotoWithImage:(UIImage*)image;  // To be called prior to display
- (void) setPhotoWithFile:(NSString*)file;  // To be called prior to display
- (void) setPhotoCaption:(NSString*)caption;  // To be called prior to display - Not user editable
@end
