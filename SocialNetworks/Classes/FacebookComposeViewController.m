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

#import "FacebookComposeViewController.h"
#import "FacebookFormViewController.h"
#import "Extensions_UIKit.h"
#import "Logging.h"

@implementation FacebookComposeViewController

@synthesize facebookComposeDelegate=_facebookDelegate;

+ (void) resetAuthentication {
  [FacebookFormViewController resetAuthentication];
}

- (BOOL) handleOpenURL:(NSURL*)url {
  return [(FacebookFormViewController*)self.rootViewController handleOpenURL:url];
}

- (BOOL) shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
  return YES;
}

@end

@implementation FacebookWallComposeViewController

- (id) initWithRootViewController:(UIViewController*)rootViewController {
  [self doesNotRecognizeSelector:_cmd];
  return nil;
}

- (id) initWithFacebookApplicationID:(NSString*)applicationID
                      amazonS3Bucket:(NSString*)bucket
                         accessKeyID:(NSString*)accessKeyID
                     secretAccessKey:(NSString*)secretAccessKey {
  CHECK(applicationID);
  CHECK(bucket);
  CHECK(accessKeyID);
  CHECK(secretAccessKey);
  FacebookFormViewController* controller = [[FacebookFormViewController alloc] initWithFacebookApplicationID:applicationID
                                                                                              amazonS3Bucket:bucket
                                                                                                 accessKeyID:accessKeyID
                                                                                             secretAccessKey:secretAccessKey];
  self = [super initWithRootViewController:controller];
  [controller release];
  return self;
}

- (void) setMessage:(NSString*)message {
  [(FacebookFormViewController*)self.rootViewController setMessage:message];
}

- (void) setPhotoWithImage:(UIImage*)image {
  [(FacebookFormViewController*)self.rootViewController setPhotoWithImage:image];
}

- (void) setPhotoWithFile:(NSString*)file {
  [(FacebookFormViewController*)self.rootViewController setPhotoWithFile:file];
}

- (void) setPhotoName:(NSString*)name {
  [(FacebookFormViewController*)self.rootViewController setPhotoName:name];
}

- (void) setPhotoCaption:(NSString*)caption {
  [(FacebookFormViewController*)self.rootViewController setPhotoCaption:caption];
}

- (void) setPhotoDescription:(NSString*)description {
  [(FacebookFormViewController*)self.rootViewController setPhotoDescription:description];
}

- (void) setPhotoURL:(NSURL*)url {
  [(FacebookFormViewController*)self.rootViewController setPhotoURL:url];
}

- (void) setLinkTitle:(NSString*)title {
  [(FacebookFormViewController*)self.rootViewController setLinkTitle:title];
}

- (void) setLinkURL:(NSURL*)url {
  [(FacebookFormViewController*)self.rootViewController setLinkURL:url];
}

@end

@implementation FacebookAlbumComposeViewController

- (id) initWithRootViewController:(UIViewController*)rootViewController {
  [self doesNotRecognizeSelector:_cmd];
  return nil;
}

- (id) initWithFacebookApplicationID:(NSString*)applicationID {
  CHECK(applicationID);
  FacebookFormViewController* controller = [[FacebookFormViewController alloc] initWithFacebookApplicationID:applicationID
                                                                                              amazonS3Bucket:nil
                                                                                                 accessKeyID:nil
                                                                                             secretAccessKey:nil];
  self = [super initWithRootViewController:controller];
  [controller release];
  return self;
}

- (void) setPhotoWithImage:(UIImage*)image {
  [(FacebookFormViewController*)self.rootViewController setPhotoWithImage:image];
}

- (void) setPhotoWithFile:(NSString*)file {
  [(FacebookFormViewController*)self.rootViewController setPhotoWithFile:file];
}

- (void) setPhotoCaption:(NSString*)caption {
  [(FacebookFormViewController*)self.rootViewController setPhotoCaption:caption];
}

@end
