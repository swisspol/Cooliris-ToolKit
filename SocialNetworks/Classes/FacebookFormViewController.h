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
#import "FBConnect.h"

// DO NOT USE: This class is used internally by FacebookComposeViewControllerDelegate
@interface FacebookFormViewController : UIViewController <FBSessionDelegate, FBRequestDelegate> {
@private
  NSString* _bucket;
  NSString* _accessKeyID;
  NSString* _secretAccessKey;
  UITextView* _textView;
  AutoresizingView* _imageView;
  
  Facebook* _facebook;
  NSString* _message;
  UIImage* _photoImage;
  NSString* _photoFile;
  NSString* _photoName;
  NSString* _photoCaption;
  NSString* _photoDescription;
  NSURL* _photoURL;
  NSString* _linkTitle;
  NSURL* _linkURL;
  BOOL _inRotation;
}
@property(nonatomic, retain) IBOutlet UITextView* textView;
@property(nonatomic, retain) IBOutlet AutoresizingView* imageView;
+ (void) resetAuthentication;
- (id) initWithFacebookApplicationID:(NSString*)applicationID
                      amazonS3Bucket:(NSString*)bucket
                         accessKeyID:(NSString*)accessKeyID
                     secretAccessKey:(NSString*)secretAccessKey;
- (BOOL) handleOpenURL:(NSURL*)url;
- (void) setMessage:(NSString*)message;
- (void) setPhotoWithImage:(UIImage*)image;
- (void) setPhotoWithFile:(NSString*)file;
- (void) setPhotoName:(NSString*)name;
- (void) setPhotoCaption:(NSString*)caption;
- (void) setPhotoDescription:(NSString*)description;
- (void) setPhotoURL:(NSURL*)url;
- (void) setLinkTitle:(NSString*)title;
- (void) setLinkURL:(NSURL*)url;
- (void) post;
@end
