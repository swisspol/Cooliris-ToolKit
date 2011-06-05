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

@class WebViewController;

@protocol WebViewControllerDelegate <NSObject>
@optional
- (void) webViewControllerDidClose:(WebViewController*)controller;
- (BOOL) webViewController:(WebViewController*)controller shouldLoadURL:(NSURL*)url;
- (void) webViewControllerDidStartLoading:(WebViewController*)controller;
- (void) webViewControllerDidFinishLoading:(WebViewController*)controller;
- (void) webViewControllerDidFailLoading:(WebViewController*)controller withError:(NSError*)error;
@end

// The left navigation item is initialized to a Backward / Forward set of buttons
// The right navigation item is initialized to the "Done" button
// The title is either the loading message or the current web page title
@interface WebViewController : UIViewController <UIWebViewDelegate> {
@private
  NSURLRequest* _request;
  NSString* _message;
  id<WebViewControllerDelegate> _delegate;
  UIButton* _backButton;
  UIButton* _forwardButton;
}
@property(nonatomic, assign) id<WebViewControllerDelegate> delegate;
@property(nonatomic, readonly) UIButton* backButton;
@property(nonatomic, readonly) UIButton* forwardButton;
- (id) initWithURL:(NSURL*)url loadingMessage:(NSString*)message;
- (id) initWithURLRequest:(NSURLRequest*)request loadingMessage:(NSString*)message;
@end
