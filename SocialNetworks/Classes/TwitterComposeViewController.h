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

#import <UIKit/UIKit.h>

@class TwitterComposeViewController;

@protocol TwitterComposeViewControllerDelegate <NSObject>
@optional
- (void) twitterComposeViewControllerDidFailAuthenticating:(TwitterComposeViewController*)controller withError:(NSError*)error;  // Error may be nil
- (void) twitterComposeViewControllerDidStartPosting:(TwitterComposeViewController*)controller;
- (void) twitterComposeViewControllerDidSucceedPosting:(TwitterComposeViewController*)controller;
- (void) twitterComposeViewControllerDidFailPosting:(TwitterComposeViewController*)controller withError:(NSError*)error;  // Error may be nil
- (void) twitterComposeViewControllerDidCancelPosting:(TwitterComposeViewController*)controller;
@end

// Uses img.ly for photo hosting
@interface TwitterComposeViewController : UINavigationController {
@private
  id<TwitterComposeViewControllerDelegate> _twitterDelegate;
}
@property(nonatomic, assign) id<TwitterComposeViewControllerDelegate> twitterComposeDelegate;
+ (void) resetAuthentication;
- (id) initWithTwitterConsumerKey:(NSString*)key consumerSecret:(NSString*)secret authorizeCallbackURL:(NSURL*)url;
- (void) setStatus:(NSString*)status;  // To be called prior to display
- (void) setPhotoWithImage:(UIImage*)image;  // To be called prior to display
- (void) setPhotoWithFile:(NSString*)file;  // To be called prior to display
@end
