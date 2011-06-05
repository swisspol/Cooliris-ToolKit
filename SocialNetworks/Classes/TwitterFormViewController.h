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

#import "AutoresizingView.h"
#import "WebViewController.h"
#import "OAuthConsumer.h"

// DO NOT USE: This class is used internally by TwitterComposeViewController
@interface TwitterFormViewController : UIViewController <UITextViewDelegate, WebViewControllerDelegate> {
@private
  NSURL* _callbackURL;
  UITextView* _textView;
  AutoresizingView* _imageView;
  UILabel* _label;
  
  NSString* _status;
  UIImage* _photoImage;
  NSString* _photoFile;
  OAConsumer* _consumer;
  OAToken* _requestToken;
  OAToken* _accessToken;
  BOOL _inRotation;
  WebViewController* _webViewController;
}
@property(nonatomic, retain) IBOutlet UITextView* textView;
@property(nonatomic, retain) IBOutlet AutoresizingView* imageView;
@property(nonatomic, retain) IBOutlet UILabel* label;
+ (void) resetAuthentication;
- (id) initWithTwitterConsumerKey:(NSString*)key consumerSecret:(NSString*)secret authorizeCallbackURL:(NSURL*)url;
- (void) setStatus:(NSString*)status;
- (void) setPhotoWithImage:(UIImage*)image;
- (void) setPhotoWithFile:(NSString*)file;
- (void) post;
@end
