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

#import <QuartzCore/QuartzCore.h>

#import "FacebookFormViewController.h"
#import "FacebookComposeViewController.h"
#import "Keychain.h"
#import "HTTPURLConnection.h"
#import "Extensions_AmazonS3.h"
#import "Logging.h"
#import "JSON.h"

#define kKeychainAccount @"Facebook-Token"
#define kKeychainKey_AccessToken @"accessToken"
#define kKeychainKey_ExpirationDate @"expirationDate"

#define kJPEGCompressionQuality 0.9
#define kPhotoMargin 10.0

@implementation FacebookFormViewController

@synthesize textView=_textView, imageView=_imageView;

+ (void) resetAuthentication {
  [[Keychain sharedKeychain] removePasswordForAccount:kKeychainAccount];
}

- (void) _cancel:(id)sender {
  FacebookComposeViewController* controller = (FacebookComposeViewController*)self.navigationController;
  if ([controller.facebookComposeDelegate respondsToSelector:@selector(facebookComposeViewControllerDidCancelPosting:)]) {
    [controller.facebookComposeDelegate facebookComposeViewControllerDidCancelPosting:controller];
  }
}

- (void) _post:(id)sender {
  [_textView resignFirstResponder];
  if (_bucket) {
    [self setMessage:(_textView.text.length ? _textView.text : nil)];
  } else {
    [self setPhotoCaption:(_textView.text.length ? _textView.text : nil)];
  }
  [self post];
}

- (void) _updateKeyboard:(NSNotification*)notification {
  CGRect fromFrame = [[notification.userInfo objectForKey:UIKeyboardFrameBeginUserInfoKey] CGRectValue];
  CGRect fromRect = [self.view convertRect:[self.view.window convertRect:fromFrame fromWindow:nil] fromView:nil];
  CGRect toFrame = [[notification.userInfo objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
  CGRect toRect = [self.view convertRect:[self.view.window convertRect:toFrame fromWindow:nil] fromView:nil];
  
  if (_inRotation == NO) {
    [UIView beginAnimations:nil context:NULL];
    [UIView setAnimationDuration:[[notification.userInfo objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue]];
    [UIView setAnimationCurve:[[notification.userInfo objectForKey:UIKeyboardAnimationCurveUserInfoKey] integerValue]];
  }
  
  CGRect frame = _imageView.frame;
  frame.size.height += toRect.origin.y - fromRect.origin.y;
  _imageView.frame = frame;
  
  if (_inRotation == NO) {
    [_imageView layoutIfNeeded];  // Force layout to be animated
    [UIView commitAnimations];
  }
}

- (id) initWithFacebookApplicationID:(NSString*)applicationID
                      amazonS3Bucket:(NSString*)bucket
                         accessKeyID:(NSString*)accessKeyID
                     secretAccessKey:(NSString*)secretAccessKey {
  if ((self = [super initWithNibName:nil bundle:nil])) {
    _bucket = [bucket copy];
    _accessKeyID = [accessKeyID copy];
    _secretAccessKey = [secretAccessKey copy];
    
    _facebook = [[Facebook alloc] initWithAppId:applicationID];
    CHECK(_facebook);
    NSDictionary* password = [[Keychain sharedKeychain] passwordForAccount:kKeychainAccount];
    if (password) {
      _facebook.accessToken = [password objectForKey:kKeychainKey_AccessToken];
      _facebook.expirationDate = [password objectForKey:kKeychainKey_ExpirationDate];
    }
    
    self.title = NSLocalizedStringFromTable(_bucket ? @"TITLE_WALL" : @"TITLE_ALBUM", @"FacebookFormViewController", nil);
    self.navigationItem.leftBarButtonItem = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                                           target:self
                                                                                           action:@selector(_cancel:)] autorelease];
    self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithTitle:NSLocalizedStringFromTable(_bucket ? @"POST_WALL"
                                                                                                                        : @"POST_ALBUM",
                                                                                     @"FacebookFormViewController", nil)
                                                                               style:UIBarButtonItemStyleDone
                                                                               target:self
                                                                               action:@selector(_post:)] autorelease];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_updateKeyboard:)
                                                 name:UIKeyboardWillShowNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_updateKeyboard:)
                                                 name:UIKeyboardWillHideNotification
                                               object:nil];
  }
  return self;
}

- (void) dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillHideNotification object:nil];
  [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillShowNotification object:nil];
  
  [_facebook release];
  [_message release];
  [_photoImage release];
  [_photoFile release];
  [_photoName release];
  [_photoCaption release];
  [_photoDescription release];
  [_photoURL release];
  [_linkTitle release];
  [_linkURL release];
  
  [_textView release];
  [_imageView release];
  
  [_bucket release];
  [_accessKeyID release];
  [_secretAccessKey release];
  
  [super dealloc];
}

- (BOOL) handleOpenURL:(NSURL*)url {
  return [_facebook handleOpenURL:url];
}

- (void) setMessage:(NSString*)message {
  if (message != _message) {
    [_message release];
    _message = [message copy];
  }
}

- (void) setPhotoWithImage:(UIImage*)image {
  if (image != _photoImage) {
    [_photoImage release];
    _photoImage = [image retain];
    [_photoFile release];
    _photoFile = nil;
  }
}

- (void) setPhotoWithFile:(NSString*)file {
  if (file != _photoFile) {
    [_photoFile release];
    _photoFile = [file copy];
    [_photoImage release];
    _photoImage = nil;
  }
}

- (void) setPhotoName:(NSString*)name {
  if (name != _photoName) {
    [_photoName release];
    _photoName = [name copy];
  }
}

- (void) setPhotoCaption:(NSString*)caption {
  if (caption != _photoCaption) {
    [_photoCaption release];
    _photoCaption = [caption copy];
  }
}

- (void) setPhotoDescription:(NSString*)description {
  if (description != _photoDescription) {
    [_photoDescription release];
    _photoDescription = [description copy];
  }
}

- (void) setPhotoURL:(NSURL*)url {
  if (url != _photoURL) {
    [_photoURL release];
    _photoURL = [url retain];
  }
}

- (void) setLinkTitle:(NSString*)title {
  if (title != _linkTitle) {
    [_linkTitle release];
    _linkTitle = [title copy];
  }
}

- (void) setLinkURL:(NSURL*)url {
  if (url != _linkURL) {
    [_linkURL release];
    _linkURL = [url retain];
  }
}

- (void) viewDidLoad {
  [super viewDidLoad];
  
  _textView.layer.borderWidth = 5.0;
  _textView.layer.borderColor = [[UIColor colorWithRed:0.72 green:0.76 blue:0.85 alpha:1.0] CGColor];
  
  UIImage* photo = nil;
  if (_photoImage) {
    photo = _photoImage;
  } else if (_photoFile) {
    photo = [UIImage imageWithContentsOfFile:_photoFile];
  }
  if (photo) {
    CGSize size = photo.size;
    _imageView.backgroundColor = nil;
    UIImageView* imageView = [[UIImageView alloc] initWithFrame:CGRectMake(kPhotoMargin, kPhotoMargin, size.width, size.height)];
    imageView.image = photo;
    imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    UIView* contentView = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, size.width + 2.0 * kPhotoMargin, size.height + 2.0 * kPhotoMargin)];
    contentView.backgroundColor = [UIColor whiteColor];
    contentView.layer.borderWidth = 5.0;
    contentView.layer.borderColor = [[UIColor colorWithRed:0.72 green:0.76 blue:0.85 alpha:1.0] CGColor];
    [contentView addSubview:imageView];
    _imageView.contentView = contentView;
    [contentView release];
    [imageView release];
    _imageView.contentSize = contentView.frame.size;
    _imageView.autoresizingMode = kAutoresizingViewMode_AspectFit;
  } else {
    _imageView.hidden = YES;
  }
}

- (void) viewDidUnload {
  [super viewDidUnload];
  
  self.textView = nil;
  self.imageView = nil;
}

- (void) viewWillAppear:(BOOL)animated {
  [super viewWillAppear:animated];
  
  _textView.text = _bucket ? _message : _photoCaption;
}

- (BOOL) shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
  return YES;
}

- (void) willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration {
  [super willRotateToInterfaceOrientation:toInterfaceOrientation duration:duration];
  
  _inRotation = YES;
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation {
  [super didRotateFromInterfaceOrientation:fromInterfaceOrientation];
  
  _inRotation = NO;
}

- (void) request:(FBRequest*)request didLoad:(id)result {
  [[UIApplication sharedApplication] endIgnoringInteractionEvents];
  
  FacebookComposeViewController* controller = (FacebookComposeViewController*)self.navigationController;
  if ([controller.facebookComposeDelegate respondsToSelector:@selector(facebookComposeViewControllerDidSucceedPosting:)]) {
    [controller.facebookComposeDelegate facebookComposeViewControllerDidSucceedPosting:controller];
  }
}

- (void) request:(FBRequest*)request didFailWithError:(NSError*)error {
  [[UIApplication sharedApplication] endIgnoringInteractionEvents];
  
  FacebookComposeViewController* controller = (FacebookComposeViewController*)self.navigationController;
  if ([controller.facebookComposeDelegate respondsToSelector:@selector(facebookComposeViewControllerDidFailPosting:withError:)]) {
    [controller.facebookComposeDelegate facebookComposeViewControllerDidFailPosting:controller withError:error];
  }
}

// http://developers.facebook.com/docs/reference/rest/stream.publish
// http://developers.facebook.com/docs/reference/rest/photos.upload
- (void) _post {
  if (_bucket) {
    NSString* photoLink = nil;
    if (_photoFile || _photoImage) {
      NSData* data = _photoFile ? [NSData dataWithContentsOfFile:_photoFile]
                                : UIImageJPEGRepresentation(_photoImage, kJPEGCompressionQuality);
      if (data) {  // TODO: Check dimensions and size and handle orientation
        photoLink = [NSString stringWithFormat:@"http://%@.s3.amazonaws.com/%@.jpg", _bucket,
                                               [[NSProcessInfo processInfo] globallyUniqueString]];
        NSMutableURLRequest* request = [HTTPURLConnection HTTPRequestWithURL:[NSURL URLWithString:photoLink]
                                                                      method:@"PUT"
                                                                   userAgent:nil
                                                               handleCookies:NO];
        [request setValue:@"public-read" forHTTPHeaderField:@"x-amz-acl"];
        [request setValue:@"REDUCED_REDUNDANCY" forHTTPHeaderField:@"x-amz-storage-class"];
        [request setAmazonS3AuthorizationWithAccessKeyID:_accessKeyID secretAccessKey:_secretAccessKey];
        [request setHTTPBody:data];
        if (![HTTPURLConnection downloadHeaderFieldsForHTTPRequest:request delegate:nil]) {  // TODO: Handle cancellation
          data = nil;
        }
      }
      if (data == nil) {
        [[UIApplication sharedApplication] endIgnoringInteractionEvents];
        
        FacebookComposeViewController* controller = (FacebookComposeViewController*)self.navigationController;
        if ([controller.facebookComposeDelegate respondsToSelector:@selector(facebookComposeViewControllerDidFailPosting:withError:)]) {
          [controller.facebookComposeDelegate facebookComposeViewControllerDidFailPosting:controller withError:nil];
        }
        return;
      }
    }

    NSMutableDictionary* parameters = [[NSMutableDictionary alloc] init];
    [parameters setObject:_message forKey:@"message"];
    NSDictionary* media = [NSDictionary dictionaryWithObjectsAndKeys:
                            @"image", @"type",
                            photoLink, @"src",
                            photoLink, @"href",
                          nil];
    NSMutableDictionary* attachment = [NSMutableDictionary dictionary];
    [attachment setObject:[NSArray arrayWithObject:media] forKey:@"media"];
    if (_photoName) {
      [attachment setObject:_photoName forKey:@"name"];
    }
    if (_photoCaption) {
      [attachment setObject:_photoCaption forKey:@"caption"];
    }
    if (_photoDescription) {
      [attachment setObject:_photoDescription forKey:@"description"];
    }
    if (_photoURL) {
      [attachment setObject:[_photoURL absoluteString] forKey:@"href"];
    }
    [parameters setObject:[attachment JSONRepresentation] forKey:@"attachment"];
    if (_linkTitle && _linkURL) {
      NSDictionary* actionLinks = [NSArray arrayWithObject:[NSDictionary dictionaryWithObjectsAndKeys:
                                    _linkTitle, @"text",
                                    [_linkURL absoluteString], @"href",
                                  nil]];
      [parameters setObject:[actionLinks JSONRepresentation] forKey:@"action_links"];
    }
    [_facebook requestWithMethodName:@"stream.publish" andParams:parameters andHttpMethod:@"POST" andDelegate:self];
    [parameters release];
  } else {
    NSData* data = _photoFile ? [NSData dataWithContentsOfFile:_photoFile]
                              : UIImageJPEGRepresentation(_photoImage, kJPEGCompressionQuality);
    if (data) {  // TODO: Check dimensions and size and handle orientation
      NSMutableDictionary* parameters = [[NSMutableDictionary alloc] init];
      [parameters setObject:data forKey:@"picture"];
      if (_photoCaption) {
        [parameters setObject:_photoCaption forKey:@"caption"];
      }
      [_facebook requestWithMethodName:@"photos.upload" andParams:parameters andHttpMethod:@"POST" andDelegate:self];
      [parameters release];
    } else {
      [[UIApplication sharedApplication] endIgnoringInteractionEvents];
      
      FacebookComposeViewController* controller = (FacebookComposeViewController*)self.navigationController;
      if ([controller.facebookComposeDelegate respondsToSelector:@selector(facebookComposeViewControllerDidFailPosting:withError:)]) {
        [controller.facebookComposeDelegate facebookComposeViewControllerDidFailPosting:controller withError:nil];
      }
    }
  }
}

- (void) fbDidLogin {
  NSMutableDictionary* password = [[NSMutableDictionary alloc] init];
  [password setObject:_facebook.accessToken forKey:kKeychainKey_AccessToken];
  [password setObject:_facebook.expirationDate forKey:kKeychainKey_ExpirationDate];
  [[Keychain sharedKeychain] setPassword:password forAccount:kKeychainAccount];
  [password release];
  
  [self post];
}

- (void) fbDidNotLogin:(BOOL)cancelled {
  FacebookComposeViewController* controller = (FacebookComposeViewController*)self.navigationController;
  if ([controller.facebookComposeDelegate respondsToSelector:@selector(facebookComposeViewControllerDidFailAuthenticating:withError:)]) {
    [controller.facebookComposeDelegate facebookComposeViewControllerDidFailAuthenticating:controller withError:nil];
  }
}

// http://developers.facebook.com/docs/authentication/permissions
- (void) post {
  if (![_facebook isSessionValid]) {
    NSArray* permissions = [NSArray arrayWithObjects:@"offline_access", @"publish_stream", nil];  // Asking for "publish_stream" when uploading photos allows to skip the "pending" state
    [_facebook authorize:permissions delegate:self];
  } else {
    [[UIApplication sharedApplication] beginIgnoringInteractionEvents];
    
    FacebookComposeViewController* controller = (FacebookComposeViewController*)self.navigationController;
    if ([controller.facebookComposeDelegate respondsToSelector:@selector(facebookComposeViewControllerDidStartPosting:)]) {
      [controller.facebookComposeDelegate facebookComposeViewControllerDidStartPosting:controller];
    }
    
    [self performSelector:@selector(_post) withObject:nil afterDelay:0.0];
  }
}

@end
