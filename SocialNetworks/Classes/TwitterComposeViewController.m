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

#import "TwitterComposeViewController.h"
#import "TwitterFormViewController.h"
#import "Extensions_UIKit.h"
#import "Logging.h"

@implementation TwitterComposeViewController

@synthesize twitterComposeDelegate=_twitterDelegate;

+ (void) resetAuthentication {
  [TwitterFormViewController resetAuthentication];
}

- (id) initWithRootViewController:(UIViewController*)rootViewController {
  [self doesNotRecognizeSelector:_cmd];
  return nil;
}

- (id) initWithTwitterConsumerKey:(NSString*)key consumerSecret:(NSString*)secret authorizeCallbackURL:(NSURL*)url {
  CHECK(key);
  CHECK(secret);
  CHECK(url);
  TwitterFormViewController* controller = [[TwitterFormViewController alloc] initWithTwitterConsumerKey:key
                                                                                         consumerSecret:secret
                                                                                   authorizeCallbackURL:url];
  self = [super initWithRootViewController:controller];
  [controller release];
  return self;
}

- (void) setStatus:(NSString*)status {
  [(TwitterFormViewController*)self.rootViewController setStatus:status];
}

- (void) setPhotoWithImage:(UIImage*)image {
  [(TwitterFormViewController*)self.rootViewController setPhotoWithImage:image];
}

- (void) setPhotoWithFile:(NSString*)file {
  [(TwitterFormViewController*)self.rootViewController setPhotoWithFile:file];
}

- (BOOL) shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
  return YES;
}

@end
