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

#import "WebViewController.h"
#import "Logging.h"

@implementation WebViewController

@synthesize delegate=_delegate, backButton=_backButton, forwardButton=_forwardButton;

- (void) _done:(id)sender {
  [(UIWebView*)self.view stopLoading];
  if ([_delegate respondsToSelector:@selector(webViewControllerDidClose:)]) {
    [_delegate webViewControllerDidClose:self];
  }
}

- (id) initWithURL:(NSURL*)url loadingMessage:(NSString*)message {
  return [self initWithURLRequest:(url ? [NSURLRequest requestWithURL:url] : nil) loadingMessage:message];
}

- (id) initWithURLRequest:(NSURLRequest*)request loadingMessage:(NSString*)message {
  if ((self = [super init])) {
    _request = [request retain];
    _message = [message copy];
    
    UIWebView* webView = [[UIWebView alloc] init];
    webView.delegate = self;
    webView.scalesPageToFit = YES;
    self.view = webView;
    [webView release];
    
    UIView* buttonView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 60, 19)];
    _backButton = [[UIButton alloc] initWithFrame:CGRectMake(5, 0, 15, 19)];
    _backButton.enabled = NO;
    _backButton.showsTouchWhenHighlighted = YES;
    [_backButton setImage:[UIImage imageNamed:@"WebViewController-Back.png"] forState:UIControlStateNormal];
    [_backButton addTarget:webView action:@selector(goBack) forControlEvents:UIControlEventTouchUpInside];
    [buttonView addSubview:_backButton];
    _forwardButton = [[UIButton alloc] initWithFrame:CGRectMake(45, 0, 15, 19)];
    _forwardButton.enabled = NO;
    _forwardButton.showsTouchWhenHighlighted = YES;
    [_forwardButton setImage:[UIImage imageNamed:@"WebViewController-Forward.png"] forState:UIControlStateNormal];
    [_forwardButton addTarget:webView action:@selector(goForward) forControlEvents:UIControlEventTouchUpInside];
    [buttonView addSubview:_forwardButton];
    self.navigationItem.leftBarButtonItem = [[[UIBarButtonItem alloc] initWithCustomView:buttonView] autorelease];
    [buttonView release];
    
    self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                                            target:self
                                                                                            action:@selector(_done:)] autorelease];
  }
  return self;
}

- (void) dealloc {
  [_request release];
  [_message release];
  [_backButton release];
  [_forwardButton release];
  
  [super dealloc];
}

- (void) viewWillAppear:(BOOL)animated {
  [super viewWillAppear:animated];
  
  if (_request) {
    LOG_VERBOSE(@"UIWebView loading initial URL \"%@\"", [_request URL]);
    [(UIWebView*)self.view loadRequest:_request];
  }
}

- (void) viewWillDisappear:(BOOL)animated {
  [(UIWebView*)self.view stopLoading];

  [super viewWillDisappear:animated];
}

- (BOOL) shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
  return YES;
}

- (BOOL) webView:(UIWebView*)webView
         shouldStartLoadWithRequest:(NSURLRequest*)request
         navigationType:(UIWebViewNavigationType)navigationType {
  if ([_delegate respondsToSelector:@selector(webViewController:shouldLoadURL:)]) {
    return [_delegate webViewController:self shouldLoadURL:[request URL]];
  }
  return YES;
}

- (void) webViewDidStartLoad:(UIWebView*)webView {
  self.navigationItem.title = _message;
  
  if ([_delegate respondsToSelector:@selector(webViewControllerDidStartLoading:)]) {
    [_delegate webViewControllerDidStartLoading:self];
  }
}

- (void) webViewDidFinishLoad:(UIWebView*)webView {
  self.navigationItem.title = [(UIWebView*)self.view stringByEvaluatingJavaScriptFromString:@"document.title"];
  _backButton.enabled = [(UIWebView*)self.view canGoBack];
  _forwardButton.enabled = [(UIWebView*)self.view canGoForward];
  
  if ([_delegate respondsToSelector:@selector(webViewControllerDidFinishLoading:)]) {
    [_delegate webViewControllerDidFinishLoading:self];
  }
}

- (void) webView:(UIWebView*)webView didFailLoadWithError:(NSError*)error {
  self.navigationItem.title = nil;
  _backButton.enabled = [(UIWebView*)self.view canGoBack];
  _forwardButton.enabled = [(UIWebView*)self.view canGoForward];
  
  if ([_delegate respondsToSelector:@selector(webViewControllerDidFailLoading:withError:)]) {
    [_delegate webViewControllerDidFailLoading:self withError:error];
  }
}

@end
