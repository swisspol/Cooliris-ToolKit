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

#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>

#import "TwitterFormViewController.h"
#import "TwitterComposeViewController.h"
#import "Keychain.h"
#import "Extensions_Foundation.h"
#import "Extensions_UIKit.h"
#import "Logging.h"

#define kRequestURL @"https://twitter.com/oauth/request_token"
#define kAuthorizeURL @"https://twitter.com/oauth/authorize"
#define kAccessURL @"https://twitter.com/oauth/access_token"

#define kKeychainAccount @"Twitter-Token"
#define kKeychainKey_AccessKey @"accessKey"
#define kKeychainKey_Secret @"secret"
#define kKeychainKey_SessionHandle @"sessionHandle"

#define kTwitterMaxCharacters 140
#define kImgLyMaxCharacters 20
#define kJPEGCompressionQuality 0.9
#define kPhotoMargin 10.0

// Work around Obj-C files containing only categories not being included into static libraries
#import "../ShareKit/Classes/ShareKit/Core/Helpers/OAuth/Categories/NSMutableURLRequest+Parameters.m"
#import "../ShareKit/Classes/ShareKit/Core/Helpers/OAuth/Categories/NSString+URLEncoding.m"
#import "../ShareKit/Classes/ShareKit/Core/Helpers/OAuth/Categories/NSURL+Base.m"

@implementation TwitterFormViewController

@synthesize textView=_textView, imageView=_imageView, label=_label;

+ (void) resetAuthentication {
  [[Keychain sharedKeychain] removePasswordForAccount:kKeychainAccount];
}

- (void) _cancel:(id)sender {
  TwitterComposeViewController* controller = (TwitterComposeViewController*)self.navigationController;
  if ([controller.twitterComposeDelegate respondsToSelector:@selector(twitterComposeViewControllerDidCancelPosting:)]) {
    [controller.twitterComposeDelegate twitterComposeViewControllerDidCancelPosting:controller];
  }
}

- (void) _post:(id)sender {
  [_textView resignFirstResponder];
  [self setStatus:_textView.text];
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

- (id) initWithTwitterConsumerKey:(NSString*)key consumerSecret:(NSString*)secret authorizeCallbackURL:(NSURL*)url {
  if ((self = [super initWithNibName:nil bundle:nil])) {
    _consumer = [[OAConsumer alloc] initWithKey:key secret:secret];
    CHECK(_consumer);
    _callbackURL = [url retain];
    
    NSDictionary* password = [[Keychain sharedKeychain] passwordForAccount:kKeychainAccount];
    if (password) {
      _accessToken = [[OAToken alloc] initWithKey:[password objectForKey:kKeychainKey_AccessKey]
                                           secret:[password objectForKey:kKeychainKey_Secret]];
      _accessToken.sessionHandle = [password objectForKey:kKeychainKey_SessionHandle];
    }
    
    self.title = NSLocalizedStringFromTable(@"TITLE", @"TwitterFormViewController", nil);
    self.navigationItem.leftBarButtonItem = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                                           target:self
                                                                                           action:@selector(_cancel:)] autorelease];
    self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithTitle:NSLocalizedStringFromTable(@"POST",
                                                                                     @"TwitterFormViewController", nil)
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
  
  [_status release];
  [_photoImage release];
  [_photoFile release];
  
  [_textView release];
  [_imageView release];
  [_label release];
  
  [_callbackURL release];
  [_consumer release];
  [_requestToken release];
  [_accessToken release];
  
  [super dealloc];
}

- (void) viewDidLoad {
  [super viewDidLoad];
  
  _textView.layer.cornerRadius = 5.0;
  
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
    contentView.layer.cornerRadius = 5.0;
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
  self.label = nil;
}

- (void) viewWillAppear:(BOOL)animated {
  [super viewWillAppear:animated];
  
  _textView.text = _status;
  [self textViewDidChange:nil];
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

- (void) textViewDidChange:(UITextView*)textView {
  NSInteger count = (_photoImage || _photoFile ? kTwitterMaxCharacters - kImgLyMaxCharacters
                                               : kTwitterMaxCharacters) - _textView.text.length;
  _label.text = [NSString stringWithFormat:@"%i", count];
  _label.textColor = count >= 0 ? [UIColor whiteColor] : [UIColor redColor];
  _label.shadowColor = count >=0 ? [UIColor darkGrayColor] : [UIColor whiteColor];
  _label.shadowOffset = CGSizeMake(0.0, count >=0 ? 1.0 : -1.0);
  self.navigationItem.rightBarButtonItem.enabled = (count > 0);
}

- (void) setStatus:(NSString*)status {
  if (status != _status) {
    [_status release];
    _status = [status copy];
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

// TODO: Handle "error" if not nil
- (void) _handlePostError:(NSError*)error {
  [[UIApplication sharedApplication] endIgnoringInteractionEvents];
  
  TwitterComposeViewController* controller = (TwitterComposeViewController*)self.navigationController;
  if ([controller.twitterComposeDelegate respondsToSelector:@selector(twitterComposeViewControllerDidFailPosting:withError:)]) {
    [controller.twitterComposeDelegate twitterComposeViewControllerDidFailPosting:controller withError:error];
  }
}

- (void) _sendStatusTicket:(OAServiceTicket*)ticket didFinishWithData:(NSData*)data {
  if (ticket.didSucceed) {
    [[UIApplication sharedApplication] endIgnoringInteractionEvents];
    
    TwitterComposeViewController* controller = (TwitterComposeViewController*)self.navigationController;
    if ([controller.twitterComposeDelegate respondsToSelector:@selector(twitterComposeViewControllerDidSucceedPosting:)]) {
      [controller.twitterComposeDelegate twitterComposeViewControllerDidSucceedPosting:controller];
    }
  } else {
    [self _handlePostError:nil];
  }
}

- (void) _sendStatusTicket:(OAServiceTicket*)ticket didFailWithError:(NSError*)error {
  [self _handlePostError:error];
}

- (void) _postStatus:(NSString*)status {
  NSURL* serviceURL = [NSURL URLWithString:@"http://api.twitter.com/1/statuses/update.json"];
  OAMutableURLRequest* request = [[OAMutableURLRequest alloc] initWithURL:serviceURL
                                                                 consumer:_consumer
                                                                    token:_accessToken
                                                                    realm:nil
                                                        signatureProvider:nil];  // Use the default method (HMAC-SHA1)
  [request setHTTPMethod:@"POST"];
  OARequestParameter* statusParameter = [[OARequestParameter alloc] initWithName:@"status" value:status];
  [request setParameters:[NSArray arrayWithObject:statusParameter]];
  [statusParameter release];
  
  OAAsynchronousDataFetcher* fetcher = [OAAsynchronousDataFetcher asynchronousFetcherWithRequest:request
                                                                                        delegate:self
                                                                               didFinishSelector:@selector(_sendStatusTicket:didFinishWithData:)
                                                                                 didFailSelector:@selector(_sendStatusTicket:didFailWithError:)];
  [fetcher start];
  [request release];
}

- (void) _sendImageTicket:(OAServiceTicket*)ticket didFinishWithData:(NSData*)data {
  if (ticket.didSucceed) {
    NSString* string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSRange startingRange = [string rangeOfString:@"<url>" options:NSCaseInsensitiveSearch];
    NSRange endingRange = [string rangeOfString:@"</url>" options:NSCaseInsensitiveSearch];
    if ((startingRange.location != NSNotFound) && (endingRange.location != NSNotFound)) {
      NSRange range = NSMakeRange(startingRange.location + startingRange.length,
                                  endingRange.location - (startingRange.location + startingRange.length));
      NSString* url = [string substringWithRange:range];
      NSString* status = objc_getAssociatedObject(ticket.request, [self class]);
      [self _postStatus:[NSString stringWithFormat:@"%@ %@", status, url]];
    } else {
      [self _handlePostError:nil];
    }
    [string release];
  } else {
    [self _handlePostError:nil];
  }
  
  objc_setAssociatedObject(ticket.request, [self class], nil, OBJC_ASSOCIATION_ASSIGN);
}

- (void) _sendImageTicket:(OAServiceTicket*)ticket didFailWithError:(NSError*)error {
  [self _handlePostError:error];
  
  objc_setAssociatedObject(ticket.request, [self class], nil, OBJC_ASSOCIATION_ASSIGN);
}

- (void) _postPhoto:(NSData*)data withStatus:(NSString*)status {
  NSURL* serviceURL = [NSURL URLWithString:@"https://api.twitter.com/1/account/verify_credentials.json"];
  OAMutableURLRequest* request = [[OAMutableURLRequest alloc] initWithURL:serviceURL
                                                                 consumer:_consumer
                                                                    token:_accessToken
                                                                    realm:@"http://api.twitter.com/"
                                                        signatureProvider:nil];  // Use the default method (HMAC-SHA1)
  [request setHTTPMethod:@"GET"];
  [request prepare];
  NSString* authorizationField = [[[[request allHTTPHeaderFields] valueForKey:@"Authorization"] retain] autorelease];
  [request release];
  
  serviceURL = [NSURL URLWithString:@"http://img.ly/api/2/upload.xml"];
  request = [[OAMutableURLRequest alloc] initWithURL:serviceURL
                                            consumer:_consumer
                                               token:_accessToken
                                               realm:@"http://api.twitter.com/"
                                   signatureProvider:nil];  // Use the default method (HMAC-SHA1)
  [request setHTTPMethod:@"POST"];
  [request setValue:@"https://api.twitter.com/1/account/verify_credentials.json" forHTTPHeaderField:@"X-Auth-Service-Provider"];
  [request setValue:authorizationField forHTTPHeaderField:@"X-Verify-Credentials-Authorization"];
  
  NSString* boundary = @"0xKhTmLbOuNdArY";
  [request setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary] forHTTPHeaderField:@"Content-Type"];
  NSMutableData* body = [[NSMutableData alloc] init];
  [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
  NSString* imageDisposition = @"Content-Disposition: form-data; name=\"media\"; filename=\"Image.jpg\"\r\n";
  [body appendData:[imageDisposition dataUsingEncoding:NSUTF8StringEncoding]];
  [body appendData:[@"Content-Type: image/jpg\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
  [body appendData:data];
  [body appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
  [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
  NSString* statusDisposition = @"Content-Disposition: form-data; name=\"message\"\r\n\r\n";
  [body appendData:[statusDisposition dataUsingEncoding:NSUTF8StringEncoding]];
  [body appendData:[status dataUsingEncoding:NSUTF8StringEncoding]];
  [body appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
  [body appendData:[[NSString stringWithFormat:@"--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
  [request setHTTPBody:body];
  [body release];
  
  objc_setAssociatedObject(request, [self class], status, OBJC_ASSOCIATION_RETAIN);
  OAAsynchronousDataFetcher* fetcher = [OAAsynchronousDataFetcher asynchronousFetcherWithRequest:request
                                                                                        delegate:self
                                                                               didFinishSelector:@selector(_sendImageTicket:didFinishWithData:)
                                                                                 didFailSelector:@selector(_sendImageTicket:didFailWithError:)];
  [fetcher start];
  [request release];
}

// TODO: Handle "error" if not nil
- (void) _handleAuthenticationError:(NSError*)error {
  TwitterComposeViewController* controller = (TwitterComposeViewController*)self.navigationController;
  if ([controller.twitterComposeDelegate respondsToSelector:@selector(twitterComposeViewControllerDidFailAuthenticating:withError:)]) {
    [controller.twitterComposeDelegate twitterComposeViewControllerDidFailAuthenticating:controller withError:error];
  }
}

- (void) _tokenAccessTicket:(OAServiceTicket*)ticket didFinishWithData:(NSData*)data {
  [_accessToken release];
  if (ticket.didSucceed) {
    NSString* responseBody = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    _accessToken = [[OAToken alloc] initWithHTTPResponseBody:responseBody];
    [responseBody release];
  } else {
    _accessToken = nil;
  }
  if (_accessToken) {
    NSMutableDictionary* password = [[NSMutableDictionary alloc] init];
    [password setObject:_accessToken.key forKey:kKeychainKey_AccessKey];
    [password setObject:_accessToken.secret forKey:kKeychainKey_Secret];
    [password setValue:_accessToken.sessionHandle forKey:kKeychainKey_SessionHandle];
    [[Keychain sharedKeychain] setPassword:password forAccount:kKeychainAccount];
    [password release];
    
    [self post];
  } else {
    [self _handleAuthenticationError:nil];
  }
}

- (void) _tokenAccessTicket:(OAServiceTicket*)ticket didFailWithError:(NSError*)error {
  [self _handleAuthenticationError:error];
}

- (void) _tokenAccess:(BOOL)refresh {
  OAMutableURLRequest* request = [[OAMutableURLRequest alloc] initWithURL:[NSURL URLWithString:kAccessURL]
                                                                 consumer:_consumer
                                                                    token:(refresh ? _accessToken : _requestToken)
                                                                    realm:nil   // Our service provider doesn't specify a realm
                                                        signatureProvider:nil];  // Use the default method (HMAC-SHA1)
  [request setHTTPMethod:@"POST"];
  
  OAAsynchronousDataFetcher* fetcher = [OAAsynchronousDataFetcher asynchronousFetcherWithRequest:request
                                                                                        delegate:self
                                                                               didFinishSelector:@selector(_tokenAccessTicket:didFinishWithData:)
                                                                                 didFailSelector:@selector(_tokenAccessTicket:didFailWithError:)];
  [fetcher start];
  [request release];
}

- (BOOL) webViewController:(WebViewController*)controller shouldLoadURL:(NSURL*)url {
  if ([[url absoluteString] hasPrefix:[_callbackURL absoluteString]]) {
    if (_webViewController) {
      [_webViewController autorelease];
      _webViewController = nil;
      [self dismissModalViewControllerAnimated:YES];
    } else {
      DNOT_REACHED();
    }
    
    // ACCEPT: http://callback_url/?oauth_token=XXX
    // DECLINE: http://callback_url/?done=
    if ([[url absoluteString] containsString:@"oauth_token="]) {
      [self _tokenAccess:NO];
    }
    
    return NO;
  }
  return YES;
}

- (void) webViewControllerDidFailLoading:(WebViewController*)controller withError:(NSError*)error {
  if (_webViewController) {
    [_webViewController autorelease];
    _webViewController = nil;
    [self dismissModalViewControllerAnimated:YES];
  } else {
    DNOT_REACHED();
  }
}

- (void) _tokenRequestTicket:(OAServiceTicket*)ticket didFinishWithData:(NSData*)data {
  [[UIApplication sharedApplication] endIgnoringInteractionEvents];
  
  [_requestToken release];
  if (ticket.didSucceed) {
    NSString* responseBody = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    _requestToken = [[OAToken alloc] initWithHTTPResponseBody:responseBody];
    [responseBody release];
  } else {
    _requestToken = nil;
  }
  if (_requestToken) {
    NSURL* url = [NSURL URLWithString:[NSString stringWithFormat:@"%@?oauth_token=%@", kAuthorizeURL, _requestToken.key]];
    _webViewController = [[WebViewController alloc] initWithURL:url
                                                 loadingMessage:NSLocalizedStringFromTable(@"WEB_LOADING",
                                                                @"TwitterFormViewController", nil)];
    _webViewController.delegate = self;
    _webViewController.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
    _webViewController.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentModalViewController:_webViewController animated:YES];
  } else {
    [self _handleAuthenticationError:nil];
  }
}

- (void) _tokenRequestTicket:(OAServiceTicket*)ticket didFailWithError:(NSError*)error {
  [[UIApplication sharedApplication] endIgnoringInteractionEvents];
  
  [self _handleAuthenticationError:error];
}

- (void) _promptAuthorization {
  OAMutableURLRequest* request = [[OAMutableURLRequest alloc] initWithURL:[NSURL URLWithString:kRequestURL]
                                                                 consumer:_consumer
                                                                    token:nil   // We don't have a token yet
                                                                    realm:nil   // Our service provider doesn't specify a realm
                                                        signatureProvider:nil];  // Use the default method (HMAC-SHA1)
  [request setHTTPMethod:@"POST"];

  OAAsynchronousDataFetcher* fetcher = [OAAsynchronousDataFetcher asynchronousFetcherWithRequest:request
                                                                                        delegate:self
                                                                               didFinishSelector:@selector(_tokenRequestTicket:didFinishWithData:)
                                                                                 didFailSelector:@selector(_tokenRequestTicket:didFailWithError:)];
  [fetcher start];
  [request release];
  
  [[UIApplication sharedApplication] beginIgnoringInteractionEvents];
}

- (void) _post {
  if (_photoFile || _photoImage) {
    NSData* data = _photoFile ? [NSData dataWithContentsOfFile:_photoFile]
                              : UIImageJPEGRepresentation(_photoImage, kJPEGCompressionQuality);
    if (data) {  // TODO: Check dimensions and size and handle orientation
      [self _postPhoto:data withStatus:_status];
    } else {
      [[UIApplication sharedApplication] endIgnoringInteractionEvents];
      
      TwitterComposeViewController* controller = (TwitterComposeViewController*)self.navigationController;
      if ([controller.twitterComposeDelegate respondsToSelector:@selector(twitterComposeViewControllerDidFailPosting:withError:)]) {
        [controller.twitterComposeDelegate twitterComposeViewControllerDidFailPosting:controller withError:nil];
      }
    }
  } else {
    [self _postStatus:_status];
  }
}

- (void) post {
  if (_accessToken == nil) {
    [self _promptAuthorization];
  } else {
    [[UIApplication sharedApplication] beginIgnoringInteractionEvents];
    
    TwitterComposeViewController* controller = (TwitterComposeViewController*)self.navigationController;
    if ([controller.twitterComposeDelegate respondsToSelector:@selector(twitterComposeViewControllerDidStartPosting:)]) {
      [controller.twitterComposeDelegate twitterComposeViewControllerDidStartPosting:controller];
    }
    
    [self performSelector:@selector(_post) withObject:nil afterDelay:0.0];
  }
}

@end
