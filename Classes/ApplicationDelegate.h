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

#import <MessageUI/MessageUI.h>

#define kApplicationBundleInfoKey_DefaultConfiguration @"defaultConfiguration"
#define kApplicationConfigurationKey_ReportEmail @"reportEmail"  // For report commands
#define kApplicationBundleInfoKey_RemoteConfigurations @"remoteConfigurations"

#define kApplicationUserDefaultKey_ConfigurationURL @"configurationURL"
#define kApplicationUserDefaultKey_LoggingServerEnabled @"loggingServerEnabled"
#if __DAVSERVER_SUPPORT__
#define kApplicationUserDefaultKey_WebDAVServerEnabled @"webDAVServerEnabled"
#endif

#define kApplicationLoggingHistoryFile @"Logging.db"
#ifdef NDEBUG
#define kApplicationLoggingHistoryAge (7.0 * 24.0 * 60.0 * 60.0) // 7 days
#else
#define kApplicationLoggingHistoryAge (60.0 * 60.0)  // 1 hour
#endif
#define kApplicationRemoteLoggingPort 2323

typedef NSUInteger ApplicationMessageIdentifier;

@class ApplicationWindow;
#if __DAVSERVER_SUPPORT__
@class DAVServer;
#endif

// When the application terminates, any pending or executing tasks on the shared TaskQueue get cancelled synchronously
// When the application enters background, a background task is automatically created and kept alive until all tasks on the shared TaskQueue have completed
@interface ApplicationDelegate : NSObject <UIApplicationDelegate> {
@private
  UIWindow* _window;
  UIViewController* _viewController;
  
  ApplicationWindow* _overlayWindow;
  
  UIAlertView* _alertView;
  id _alertDelegate;
  SEL _alertConfirmSelector;
  SEL _alertCancelSelector;
  id _alertArgument;
  UIAlertView* _authenticationView;
  id _authenticationDelegate;
  SEL _authenticationAuthenticateSelector;
  SEL _authenticationCancelSelector;
  UITextField* _authenticationUsernameField;
  UITextField* _authenticationPasswordField;
  NSMutableArray* _messageViews;
  UIView* _spinnerView;
  
#if __DAVSERVER_SUPPORT__
  DAVServer* _webdavServer;
#endif
  BOOL _loggingServer;
#ifdef NSFoundationVersionNumber_iOS_4_0
  UIBackgroundTaskIdentifier _queueTask;
#endif
  
  UITextView* _loggingOverlayView;
  NSTimer* _loggingOverlayTimer;
}
@property(nonatomic, retain) IBOutlet UIWindow* window;
@property(nonatomic, retain) IBOutlet UIViewController* viewController;
+ (id) sharedInstance;
+ (void) setOverlaysOpacity:(CGFloat)opacity;  // Default is 0.75
+ (BOOL) checkCompatibilityWithMinimumOSVersion:(NSString*)minOSVersion minimumApplicationVersion:(NSString*)minAppVersion;  // Pass nil to skip check
- (void) showLogViewControllerWithTitle:(NSString*)title;  // Displayed modally on the view controller
- (BOOL) processCommandString:(NSString*)string;
- (void) saveState;  // Called when app terminates or is suspended - Default implementation does nothing
- (BOOL) shouldRotateOverlayWindowToInterfaceOrientation:(UIInterfaceOrientation)orientation;  // Default implementation returns YES
@end

@interface ApplicationDelegate (Configuration)
+ (NSURL*) configurationSourceURL;  // Returns nil if configuration is default
+ (id) objectForConfigurationKey:(NSString*)key;  // Returned object is guaranteed not to be nil
+ (void) updateConfigurationInBackgroundWithDelegate:(id)delegate;  // -configurationDidUpdate:(NSURL*)sourceURL
+ (BOOL) isUpdatingConfiguration;
@end

// If alert is dismissed, cancel selector is called on delegate
// Any existing alert or authentication is automatically dismissed when new one is shown
// Alert is automatically dismissed when going to the background
@interface ApplicationDelegate (Alerts)
- (BOOL) isAlertVisible;
- (void) showAlertWithTitle:(NSString*)title message:(NSString*)message button:(NSString*)button;
- (void) showAlertWithTitle:(NSString*)title  // Cannot be nil
                    message:(NSString*)message
                     button:(NSString*)button  // Cannot be nil
                   delegate:(id)delegate
                   selector:(SEL)selector
                   argument:(id)argument;
- (void) showAlertWithTitle:(NSString*)title  // Cannot be nil
                    message:(NSString*)message
              confirmButton:(NSString*)confirmButton  // Cannot be nil
               cancelButton:(NSString*)cancelButton
                   delegate:(id)delegate
            confirmSelector:(SEL)confirmSelector  // -didConfirm:(id)argument
             cancelSelector:(SEL)cancelSelector  // -didCancel:(id)argument
                   argument:(id)argument;
- (void) dismissAlert:(BOOL)animated;  // Does nothing if alert is not visible
@end

// If authentication is dismissed, cancel selector is called on delegate
// Any existing authentication or alert is automatically dismissed when new one is shown
// Authentication is automatically dismissed when going to the background
@interface ApplicationDelegate (Authentication)
- (BOOL) isAuthenticationVisible;
- (void) showAuthenticationWithTitle:(NSString*)title  // Cannot be nil
                 usernamePlaceholder:(NSString*)usernamePlaceholder
                 passwordPlaceholder:(NSString*)passwordPlaceholder
                  authenticateButton:(NSString*)authenticateButton  // Cannot be nil
                        cancelButton:(NSString*)cancelButton  // Cannot be nil
                            delegate:(id)delegate
                authenticateSelector:(SEL)confirmSelector  // -didAuthenticateWithUsername:(NSString*)username password:(NSString*)password
                      cancelSelector:(SEL)cancelSelector;  // -didCancel
- (void) dismissAuthentication:(BOOL)animated;  // Does nothing if authentication is not visible
@end

// Messages are shown in the current top view controller
@interface ApplicationDelegate (Messages)
- (BOOL) areMessagesVisible;
- (BOOL) isMessageVisible:(ApplicationMessageIdentifier)identifier;
- (ApplicationMessageIdentifier) showMessageWithView:(UIView*)view animated:(BOOL)animated;
- (ApplicationMessageIdentifier) showMessageWithView:(UIView*)view
                                               delay:(NSTimeInterval)delay
                                            duration:(NSTimeInterval)duration
                                            animated:(BOOL)animated;
- (ApplicationMessageIdentifier) showMessageWithString:(NSString*)message animated:(BOOL)animated;
- (ApplicationMessageIdentifier) showMessageWithString:(NSString*)message
                                                 delay:(NSTimeInterval)delay
                                              duration:(NSTimeInterval)duration
                                              animated:(BOOL)animated;
- (void) dismissMessage:(ApplicationMessageIdentifier)identifier animated:(BOOL)animated;
- (void) dismissAllMessages:(BOOL)animated;
@end

// Spinner is shown in the current top view controller
@interface ApplicationDelegate (Spinner)
- (BOOL) isSpinnerVisible;
- (void) showSpinnerWithMessage:(NSString*)message animated:(BOOL)animated;  // Message may be nil
- (void) hideSpinner:(BOOL)animated;
@end

// Enables a transparent overlay view that automatically appears when logging messages arrive
// This functionality uses LoggingSetCallback()
@interface ApplicationDelegate (LogOverlay)
- (void) setLoggingOverlayEnabled:(BOOL)flag;
- (BOOL) isLoggingOverlayEnabled;
@end

// If overriding any of these delegate methods, make sure to call super
@interface ApplicationDelegate (UIApplicationDelegate)
- (BOOL) application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)launchOptions;
- (void) applicationWillTerminate:(UIApplication*)application;
#ifdef NSFoundationVersionNumber_iOS_4_0
- (void) applicationWillEnterForeground:(UIApplication*)application;
- (void) applicationDidEnterBackground:(UIApplication*)application;
#endif
@end
