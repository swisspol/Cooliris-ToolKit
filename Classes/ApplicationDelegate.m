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
#import <objc/runtime.h>

#import "ApplicationDelegate.h"
#import "Task.h"
#import "HTTPURLConnection.h"
#import "Logging.h"
#import "Extensions_Foundation.h"
#import "Extensions_UIKit.h"
#if __DAVSERVER_SUPPORT__
#import "DAVServer.h"
#endif

#define kConfigurationKeySourceURL @"__sourceURL__"

#define kMessageBorderWidth 10.0
#define kMessageSpacing 20.0
#define kMessageViewAnimationDuration 0.5
#define kMessageMaxDimension 700.0

#define kSpinnerBorderWidth 15.0
#define kSpinnerSpacing 6.0
#define kSpinnerViewAnimationDuration 0.5

#define kTagFlag_New (1 << 0)
#define kTagFlag_Transient (1 << 1)
#define kTagFlag_Animated (1 << 2)

#define kRemoteLoggingMessageDelay 0.5
#define kRemoteLoggingMessageDuration 10.0
#if __DAVSERVER_SUPPORT__
#define kWebDAVServerMessageDelay 0.5
#define kWebDAVServerMessageDuration 10.0
#endif

#define kConfigurationCacheFile @"Configuration.data"
#define kConfigurationLocalDownloadTimeOut 5.0

#define kLoggingFontName @"Courier"
#define kLoggingFontSize 13.0

#define kLoggingOverlayDisplayDuration 5.0
#define kDeviceRotationAnimationDuration 0.4

@interface ApplicationWindow : UIWindow {
@private
  UIDeviceOrientation _lastDeviceOrientation;
}
- (id) initWithScreen:(UIScreen*)screen;
- (void) presentView:(UIView*)view;
- (void) dismissView:(UIView*)view;
@end

@interface LogViewController : UIViewController
- (id) initWithText:(NSString*)text target:(id)target action:(SEL)action;
@end

@interface ConfigurationDownloader : Task {
@private
  NSArray* _urls;
  NSMutableDictionary* _configuration;
  NSURL* _url;
}
@property(nonatomic, readonly) NSDictionary* configuration;
@property(nonatomic, readonly) NSURL* url;
- (id) initWithURLs:(NSArray*)urls;
@end

@interface ApplicationDelegate (Internal)
- (void) _dismissAlertWithButtonIndex:(NSInteger)index;
- (void) _dismissAuthenticationWithButtonIndex:(NSInteger)index;
@end

static ApplicationDelegate* _sharedInstance = nil;
static IMP _exceptionInitializerIMP = NULL;
static NSMutableDictionary* _configurationDictionary = nil;
static Task* _configurationTask = nil;
static CGFloat _overlaysOpacity = 0.75;

static void _exceptionInitializer(id self, SEL cmd, NSString* name, NSString* reason, NSDictionary* userInfo) {
  _exceptionInitializerIMP(self, cmd, name, reason, userInfo);
  
  LOG_EXCEPTION(self);
}

static void _UncaughtExceptionHandler(NSException* exception) {
  LOG_EXCEPTION(exception);
}

@implementation ConfigurationDownloader

@synthesize configuration=_configuration, url=_url;

- (id) initWithURLs:(NSArray*)urls {
  if ((self = [super init])) {
    _urls = [urls retain];
  }
  return self;
}

- (void) dealloc {
  [_urls release];
  [_configuration release];
  [_url release];
  
  [super dealloc];
}

- (BOOL) execute {
  for (NSURL* url in _urls) {
    NSMutableURLRequest* request = [HTTPURLConnection HTTPRequestWithURL:url method:@"GET" userAgent:nil handleCookies:NO];
    if ([url.host containsString:@"10.0."] || [url.host containsString:@"172.16."] || [url.host containsString:@"192.168."] ||
      [url.host hasSuffix:@".local"]) {
      [request setTimeoutInterval:kConfigurationLocalDownloadTimeOut];
    }
    NSData* data = [HTTPURLConnection downloadHTTPRequestToMemory:request delegate:(id)self headerFields:NULL];
    if (data) {
      NSString* error = nil;
      _configuration = [[NSPropertyListSerialization propertyListFromData:data
                                                         mutabilityOption:NSPropertyListMutableContainers
                                                                   format:NULL
                                                         errorDescription:&error] retain];
      if (_configuration) {
        [_configuration setObject:[url absoluteString] forKey:kConfigurationKeySourceURL];
        _url = [url retain];
        return YES;
      }
      LOG_ERROR(@"Failed parsing configuration patch: %@", error);
    }
  }
  return NO;
}

@end

@implementation LogViewController

- (id) initWithText:(NSString*)text target:(id)target action:(SEL)action {
  if ((self = [super init])) {
    self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                                            target:target
                                                                                            action:action] autorelease];
    UITextView* view = [[UITextView alloc] init];
    view.text = text;
    view.textColor = [UIColor darkGrayColor];
    view.font = [UIFont fontWithName:kLoggingFontName size:kLoggingFontSize];
    view.editable = NO;
    view.dataDetectorTypes = UIDataDetectorTypeNone;
    self.view = view;
    [view release];
  }
  return self;
}

- (BOOL) shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
  return YES;
}

@end

@implementation ApplicationWindow

- (void) _deviceRotationDidChange:(NSNotification*)notification {
  UIDeviceOrientation orientation = [[UIDevice currentDevice] orientation];
  if (UIDeviceOrientationIsValidInterfaceOrientation(orientation)) {
    BOOL shouldAnimate = YES;
    if (!UIDeviceOrientationIsValidInterfaceOrientation(_lastDeviceOrientation)) {  // Independently of device orientation, applications always launch in portrait mode
      _lastDeviceOrientation = UIDeviceOrientationPortrait;
      shouldAnimate = NO;
    }
    if ((orientation != _lastDeviceOrientation) &&
      [[ApplicationDelegate sharedInstance] shouldRotateOverlayWindowToInterfaceOrientation:orientation]) {
      if (shouldAnimate) {
        [UIView beginAnimations:nil context:self];
        [UIView setAnimationBeginsFromCurrentState:YES];
        [UIView setAnimationDuration:kDeviceRotationAnimationDuration];
      }
      
      if (orientation == UIInterfaceOrientationPortrait) {
        self.transform = CGAffineTransformMakeRotation(0.0);
      } else if (orientation == UIInterfaceOrientationPortraitUpsideDown) {
        self.transform = CGAffineTransformMakeRotation(M_PI);
      } else if (orientation == UIInterfaceOrientationLandscapeRight) {
        self.transform = CGAffineTransformMakeRotation(M_PI / 2.0);
      } else if (orientation == UIInterfaceOrientationLandscapeLeft) {
        self.transform = CGAffineTransformMakeRotation(M_PI * 1.5);
      }
      
      if ((UIDeviceOrientationIsPortrait(_lastDeviceOrientation) && UIDeviceOrientationIsLandscape(orientation))
          || (UIDeviceOrientationIsLandscape(_lastDeviceOrientation) && UIDeviceOrientationIsPortrait(orientation))) {
        CGRect bounds = self.bounds;
        bounds.size = CGSizeMake(bounds.size.height, bounds.size.width);
        self.bounds = bounds;
      } else if ((UIDeviceOrientationIsLandscape(_lastDeviceOrientation) && UIDeviceOrientationIsLandscape(orientation))
                 || (UIDeviceOrientationIsPortrait(_lastDeviceOrientation) && UIDeviceOrientationIsPortrait(orientation))) {
        [UIView setAnimationDuration:(2.0 * kDeviceRotationAnimationDuration)];
      }
      
      if (shouldAnimate) {
        [UIView commitAnimations];
      }
    }
    _lastDeviceOrientation = orientation;
  }
}

- (id) initWithScreen:(UIScreen*)screen {
  if ((self = [super initWithFrame:screen.bounds])) {
    _lastDeviceOrientation = UIDeviceOrientationUnknown;
    
    self.userInteractionEnabled = NO;
    self.windowLevel = 100.0;  // UIWindowLevelNormal = 0.0 & UIWindowLevelStatusBar = 1000.0
    self.screen = screen;
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_deviceRotationDidChange:)
                                                 name:UIDeviceOrientationDidChangeNotification
                                               object:[UIDevice currentDevice]];
  }
  return self;
}

- (void) dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self name:UIDeviceOrientationDidChangeNotification object:[UIDevice currentDevice]];
  
  [super dealloc];
}

- (void) presentView:(UIView*)view {
  DCHECK(view.superview == nil);
  [self addSubview:view];
  
  self.hidden = NO;
}

- (void) dismissView:(UIView*)view {
  DCHECK(view.superview == self);
  [view removeFromSuperview];
  
  if (self.subviews.count == 0) {
    self.hidden = YES;
  }
}

@end

@implementation ApplicationDelegate

@synthesize window=_window, viewController=_viewController;

+ (id) alloc {
  DCHECK(_sharedInstance == nil);
  _sharedInstance = [super alloc];
  return _sharedInstance;
}

+ (id) sharedInstance {
  return _sharedInstance;
}

+ (void) setOverlaysOpacity:(CGFloat)opacity {
  _overlaysOpacity = opacity;
}

+ (BOOL) checkCompatibilityWithMinimumOSVersion:(NSString*)minOSVersion minimumApplicationVersion:(NSString*)minAppVersion {
  if (minOSVersion && ([[[UIDevice currentDevice] systemVersion] compare:minOSVersion options:NSNumericSearch] == NSOrderedAscending)) {
    return NO;
  }
  if (minAppVersion && ([[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] compare:minAppVersion
                                                                                                          options:NSNumericSearch] == NSOrderedAscending)) {
    return NO;
  }
  return YES;
}

- (void) __alertView:(UIAlertView*)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex {
  if (alertView == _alertView) {
    [self _dismissAlertWithButtonIndex:buttonIndex];
  } else if (alertView == _authenticationView) {
    [self _dismissAuthenticationWithButtonIndex:buttonIndex];
  } else {
    DNOT_REACHED();
  }
}

+ (void) alertView:(UIAlertView*)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex {
  [[ApplicationDelegate sharedInstance] __alertView:alertView didDismissWithButtonIndex:buttonIndex];
}

- (void) _startServices {
  // Setup logging remote access
  if ([[NSUserDefaults standardUserDefaults] boolForKey:kApplicationUserDefaultKey_LoggingServerEnabled]) {
    NSString* ipAddress = [[UIDevice currentDevice] currentWiFiAddress];
    if (ipAddress) {
      _loggingServer = YES;
    }
    if (_loggingServer && LoggingEnableRemoteAccess(kApplicationRemoteLoggingPort)) {
      LoggingSetMinimumLevel(kLogLevel_Verbose);
      NSString* string = [NSString stringWithFormat:@"Remote Logging @ %@:%i", ipAddress, kApplicationRemoteLoggingPort];
      [self showMessageWithString:string
                            delay:kRemoteLoggingMessageDelay
                         duration:kRemoteLoggingMessageDuration
                         animated:YES];
    } else {
      [self showMessageWithString:@"Remote Logging Not Available"
                            delay:kRemoteLoggingMessageDelay
                         duration:kRemoteLoggingMessageDuration
                         animated:YES];
    }
  }
  
#if __DAVSERVER_SUPPORT__
  // Start WebDAV server if necessary
  if ([[NSUserDefaults standardUserDefaults] boolForKey:kApplicationUserDefaultKey_WebDAVServerEnabled]) {
    NSString* ipAddress = [[UIDevice currentDevice] currentWiFiAddress];
    if (ipAddress) {
      NSString* documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
      _webdavServer = [[DAVServer alloc] initWithRootDirectory:[documentsPath stringByDeletingLastPathComponent]];
    }
    if ([_webdavServer start]) {
      NSString* string = [NSString stringWithFormat:@"WebDAV Server @ %@:%i", ipAddress, _webdavServer.port];
      [self showMessageWithString:string
                            delay:kWebDAVServerMessageDelay
                         duration:kWebDAVServerMessageDuration
                         animated:YES];
    } else {
      [self showMessageWithString:@"WebDAV Server Not Available"
                            delay:kWebDAVServerMessageDelay
                         duration:kWebDAVServerMessageDuration
                         animated:YES];
    }
  }
#endif
}

- (BOOL) application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)launchOptions {
#ifdef NSFoundationVersionNumber_iOS_4_0
  if (&UIBackgroundTaskInvalid != NULL) {
    _queueTask = UIBackgroundTaskInvalid;
  }
#endif
  
#ifdef NDEBUG
  // Setup minimum logging level
  if ([[NSProcessInfo processInfo] isDebuggerAttached]) {
    LoggingSetMinimumLevel(kLogLevel_Verbose);
    LOG_WARNING(@"Debugger is attached: verbose logging active");
  } else {
    LoggingSetMinimumLevel(kLogLevel_Warning);
  }
#endif
  
  // Setup logging history
  NSString* cachesPath = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) lastObject];
  LoggingEnableHistory([cachesPath stringByAppendingPathComponent:kApplicationLoggingHistoryFile],
                       [[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"] integerValue]);
  
  // We cannot patch @throw but we can patch the designated initializer of NSException
  _exceptionInitializerIMP = method_setImplementation(class_getInstanceMethod([NSException class],
                                                                              @selector(initWithName:reason:userInfo:)),
                                                      (IMP)&_exceptionInitializer);
  
  // Install uncaught exception handler
  NSSetUncaughtExceptionHandler(&_UncaughtExceptionHandler);
  
  // Initialize overlay window
  _overlayWindow = [[ApplicationWindow alloc] initWithScreen:[UIScreen mainScreen]];
  
  // Defer services start
  [self performSelector:@selector(_startServices) withObject:nil afterDelay:0.0];
  
  return NO;
}

- (void) _shutdownTaskQueue {
  LOG_VERBOSE(@"Waiting for TaskQueue to shutdown...");
  
  // Make sure no new task can be executed
  [[TaskQueue sharedTaskQueue] suspend];
  
  // Cancel all tasks already in queue
  [[TaskQueue sharedTaskQueue] cancelAllTasksExecution];
  
  // Wait until done
  [[TaskQueue sharedTaskQueue] waitUntilIdle];
  
  LOG_VERBOSE(@"TaskQueue has shutdown");
}

#ifdef NSFoundationVersionNumber_iOS_4_0

- (void) _endTaskQueueBackgroundTask {
  [[NSNotificationCenter defaultCenter] removeObserver:self name:TaskQueueDidBecomeIdleNotification object:nil];
  [[UIApplication sharedApplication] endBackgroundTask:_queueTask];
  _queueTask = UIBackgroundTaskInvalid;
  LOG_VERBOSE(@"TaskQueue background task ended");
}

- (void) _taskQueueDidBecomeIdle:(NSNotification*)notification {
  if ([[TaskQueue sharedTaskQueue] numberOfQueuedTasks] == 0) {
    [[TaskQueue sharedTaskQueue] suspend];
    [self saveState];
    [self _endTaskQueueBackgroundTask];
  }
}

- (void) applicationDidEnterBackground:(UIApplication*)application {
  // Dismiss alert views
  [self dismissAuthentication:NO];
  [self dismissAlert:NO];
  
#if __DAVSERVER_SUPPORT__
  // Suspend DAVServer
  [_webdavServer stop:YES];
#endif
  
  // Stop remote logging
  if (_loggingServer) {
    LoggingDisableRemoteAccess(YES);
  }
  
  // Purge history
  LoggingPurgeHistory(kApplicationLoggingHistoryAge);
  
  // Start TaskQueue background task if necessary - TODO: There can be race conditions if tasks aren't scheduled from main thread
  if ([TaskQueue wasCreated]) {
    if ([[TaskQueue sharedTaskQueue] isIdle] && ![[TaskQueue sharedTaskQueue] numberOfQueuedTasks]) {
      [[TaskQueue sharedTaskQueue] suspend];
      [self saveState];
    } else {
      [[NSNotificationCenter defaultCenter] addObserver:self
                                               selector:@selector(_taskQueueDidBecomeIdle:)
                                                   name:TaskQueueDidBecomeIdleNotification
                                                 object:nil];
      _queueTask = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
        [self _shutdownTaskQueue];
        [self saveState];
        [self _endTaskQueueBackgroundTask];
      }];
      LOG_VERBOSE(@"TaskQueue background task started (%.0f seconds remaining)",
                  [[UIApplication sharedApplication] backgroundTimeRemaining]);
    }
  }
  
  // Make sure user defaults are synchronized
  [[NSUserDefaults standardUserDefaults] synchronize];
  
  LOG_VERBOSE(@"Application did enter background");
}

- (void) applicationWillEnterForeground:(UIApplication*)application {
  LOG_VERBOSE(@"Application will enter foreground");
  
  // Make sure user defaults are synchronized
  [[NSUserDefaults standardUserDefaults] synchronize];
  
  // Finish TaskQueue background task
  if (_queueTask != UIBackgroundTaskInvalid) {
    [[TaskQueue sharedTaskQueue] suspend];
    [self _endTaskQueueBackgroundTask];
  }
  
  // Resume TaskQueue
  if ([TaskQueue wasCreated]) {
    [[TaskQueue sharedTaskQueue] resume];
  }
  
  // Restart logging remote access
  if (_loggingServer) {
    LoggingEnableRemoteAccess(kApplicationRemoteLoggingPort);
  }
  
#if __DAVSERVER_SUPPORT__
  // Restart WebDAV server
  [_webdavServer start];
#endif
}

#endif

- (void) applicationWillTerminate:(UIApplication*)application {
  // Dismiss alert views
  [self dismissAuthentication:NO];
  [self dismissAlert:NO];
  
  // Shutdown TaskQueue
  if ([TaskQueue wasCreated]) {
    [self _shutdownTaskQueue];
  }
  
  // Save state
  [self saveState];
  
#if __DAVSERVER_SUPPORT__
  // Stop DAVServer
  [_webdavServer stop:NO];
#endif
  
  // Stop remote logging
  if (_loggingServer) {
    LoggingDisableRemoteAccess(NO);
  }
  
  // Purge history
  LoggingPurgeHistory(kApplicationLoggingHistoryAge);
  
  // Make sure user defaults are synchronized
  [[NSUserDefaults standardUserDefaults] synchronize];
}

static void _HistoryLogCallback(NSUInteger appVersion, NSTimeInterval timestamp, LogLevel level, NSString* message, void* context) {
  NSString* date = [[NSDate dateWithTimeIntervalSinceReferenceDate:timestamp] stringWithCachedFormat:@"yyyy-MM-dd HH:mm:ss.SSS"
                                                                                     localIdentifier:@"en_US"];
  [(NSMutableString*)context appendFormat:@"[r%i | %@ | %s] %@\n", appVersion, date, LoggingGetLevelName(level), message];
}

- (void) _logViewControllerDone:(id)sender {
  [_viewController dismissModalViewControllerAnimated:YES];
}

- (void) showLogViewControllerWithTitle:(NSString*)title {
  NSMutableString* log = [NSMutableString string];
  LoggingReplayHistory(_HistoryLogCallback, log, YES);
  LogViewController* viewController = [[LogViewController alloc] initWithText:log target:self action:@selector(_logViewControllerDone:)];
  viewController.navigationItem.title = title;
  UINavigationController* navigationController = [[UINavigationController alloc] initWithRootViewController:viewController];
  [_viewController presentModalViewController:navigationController animated:YES];
  [navigationController release];
  [viewController release];
}

- (BOOL) processCommandString:(NSString*)string {
  NSScanner* scanner = [NSScanner scannerWithString:string];
  [scanner setCharactersToBeSkipped:nil];
  NSString* command = nil;
  [scanner scanUpToCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:&command];
  [scanner scanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:NULL];
  NSString* argument = nil;
  [scanner scanUpToCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:&argument];
  SEL selector = NSSelectorFromString([NSString stringWithFormat:@"command_%@:", command]);
  if ([self respondsToSelector:selector]) {
    NSString* string = [self performSelector:selector withObject:argument];
    if (string) {
      [self showAlertWithTitle:command message:string button:@"Continue"];
    }
    return YES;
  } else {
    [self showAlertWithTitle:(command ? command : @"") message:@"This command is invalid" button:@"Continue"];
  }
  return NO;
}

- (void) saveState {
  ;
}

- (BOOL) shouldRotateOverlayWindowToInterfaceOrientation:(UIInterfaceOrientation)orientation {
  return YES;
}

@end

@implementation ApplicationDelegate (Configuration)

+ (void) initialize {
  if (_configurationDictionary == nil) {
    NSDictionary* configuration = [[NSBundle mainBundle] objectForInfoDictionaryKey:kApplicationBundleInfoKey_DefaultConfiguration];
    if (configuration) {
      _configurationDictionary = [[NSMutableDictionary alloc] initWithDictionary:configuration];
      NSString* cachesPath = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) lastObject];
      NSString* path = [cachesPath stringByAppendingPathComponent:kConfigurationCacheFile];
      if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        configuration = [[NSDictionary alloc] initWithContentsOfFile:path];
        if (configuration) {
          [_configurationDictionary addEntriesFromDictionary:configuration];
          [configuration release];
        } else {
          NSLog(@"Failed reading cached configuration file");  // Don't use LOG() at this point
        }
      }
    }
  }
}

+ (NSURL*) configurationSourceURL {
  NSString* string = [_configurationDictionary objectForKey:kConfigurationKeySourceURL];
  return string ? [NSURL URLWithString:string] : nil;
}

+ (id) objectForConfigurationKey:(NSString*)key {
  return [_configurationDictionary objectForKey:key];
}

+ (void) _didFinishDownloadingConfiguration:(ConfigurationDownloader*)task {
  if (task.configuration) {
    [_configurationDictionary release];
    NSDictionary* configuration = [[NSBundle mainBundle] objectForInfoDictionaryKey:kApplicationBundleInfoKey_DefaultConfiguration];
    _configurationDictionary = [[NSMutableDictionary alloc] initWithDictionary:configuration];
    [_configurationDictionary addEntriesFromDictionary:task.configuration];
    
    NSString* cachesPath = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) lastObject];
    NSString* path = [cachesPath stringByAppendingPathComponent:kConfigurationCacheFile];
    if (![task.configuration writeToFile:path atomically:YES]) {
      LOG_ERROR(@"Failed writing cached configuration file");
    }
  }
  
  [_configurationTask release];
  _configurationTask = nil;
  
  LOG_VERBOSE(@"Configuration updating completed");
  
  [task.userInfo performSelector:@selector(configurationDidUpdate:) withObject:task.url];
}

+ (void) updateConfigurationInBackgroundWithDelegate:(id)delegate {
  CHECK(_configurationTask == nil);
  LOG_VERBOSE(@"Configuration updating started");
  NSMutableArray* array = [[NSMutableArray alloc] init];
  NSURL* url = [NSURL URLWithString:[[NSUserDefaults standardUserDefaults] stringForKey:kApplicationUserDefaultKey_ConfigurationURL]];
  if ([url host]) {
    [array addObject:url];
  } else {
    for (NSString* string in [[NSBundle mainBundle] objectForInfoDictionaryKey:kApplicationBundleInfoKey_RemoteConfigurations]) {
      [array addObject:[NSURL URLWithString:string]];
    }
  }
  _configurationTask = [[ConfigurationDownloader alloc] initWithURLs:array];
  _configurationTask.delegate = self;
  _configurationTask.didFinishSelector = @selector(_didFinishDownloadingConfiguration:);
  _configurationTask.userInfo = delegate;
  [[TaskQueue sharedTaskQueue] scheduleTaskForExecution:_configurationTask];
  [array release];
}

+ (BOOL) isUpdatingConfiguration {
  return _configurationTask ? YES : NO;
}

@end

@implementation ApplicationDelegate (Alerts)

- (BOOL) isAlertVisible {
  return _alertView ? YES : NO;
}

- (void) _dismissAlertWithButtonIndex:(NSInteger)index {
  if (index == _alertView.cancelButtonIndex) {
    if (_alertDelegate && _alertCancelSelector) {
      [_alertDelegate performSelector:_alertCancelSelector withObject:_alertArgument];
    }
  } else {
    if (_alertDelegate && _alertConfirmSelector) {
      [_alertDelegate performSelector:_alertConfirmSelector withObject:_alertArgument];
    }
  }
  [_alertArgument release];
  [_alertDelegate release];
  [_alertView release];
  _alertView = nil;
}

- (void) showAlertWithTitle:(NSString*)title message:(NSString*)message button:(NSString*)button {
  [self showAlertWithTitle:title message:message button:button delegate:nil selector:NULL argument:nil];
}

- (void) showAlertWithTitle:(NSString*)title
                    message:(NSString*)message
                     button:(NSString*)button
                   delegate:(id)delegate
                   selector:(SEL)selector
                   argument:(id)argument {
  [self showAlertWithTitle:title
                   message:message
             confirmButton:button
              cancelButton:nil
                  delegate:delegate
           confirmSelector:selector
            cancelSelector:nil
                  argument:argument];
}

- (void) showAlertWithTitle:(NSString*)title
                    message:(NSString*)message
              confirmButton:(NSString*)confirmButton
               cancelButton:(NSString*)cancelButton
                   delegate:(id)delegate
            confirmSelector:(SEL)confirmSelector
             cancelSelector:(SEL)cancelSelector
                   argument:(id)argument {
  CHECK(title);
  CHECK(confirmButton);
  [self dismissAuthentication:NO];
  [self dismissAlert:NO];
  _alertView = [[UIAlertView alloc] initWithTitle:title
                                          message:message
                                         delegate:[ApplicationDelegate class]
                                cancelButtonTitle:cancelButton
                                otherButtonTitles:confirmButton, nil];
  _alertDelegate = [delegate retain];
  _alertConfirmSelector = confirmSelector;
  _alertCancelSelector = cancelSelector;
  _alertArgument = [argument retain];
  [_alertView show];
}

- (void) dismissAlert:(BOOL)animated {
  if (_alertView) {
    [_alertView dismissWithClickedButtonIndex:_alertView.cancelButtonIndex animated:animated];  // Doesn't call delegate on 4.2?
    if (_alertView) {
      [self _dismissAlertWithButtonIndex:_alertView.cancelButtonIndex];
    }
  }
}

@end

@implementation ApplicationDelegate (Authentication)

- (BOOL) isAuthenticationVisible {
  return _authenticationView ? YES : NO;
}

- (void) _dismissAuthenticationWithButtonIndex:(NSInteger)index {
  if (index == _authenticationView.cancelButtonIndex) {
    if (_authenticationDelegate && _authenticationCancelSelector) {
      [_authenticationDelegate performSelector:_authenticationCancelSelector];
    }
  } else {
    if (_authenticationDelegate && _authenticationAuthenticateSelector) {
      [_authenticationDelegate performSelector:_authenticationAuthenticateSelector
                                    withObject:_authenticationUsernameField.text
                                    withObject:_authenticationPasswordField.text];
    }
  }
  [_authenticationUsernameField release];
  _authenticationUsernameField = nil;
  [_authenticationPasswordField release];
  _authenticationPasswordField = nil;
  [_authenticationDelegate release];
  [_authenticationView release];
  _authenticationView = nil;
}

- (void) showAuthenticationWithTitle:(NSString*)title
                 usernamePlaceholder:(NSString*)usernamePlaceholder
                 passwordPlaceholder:(NSString*)passwordPlaceholder
                  authenticateButton:(NSString*)authenticateButton
                        cancelButton:(NSString*)cancelButton
                            delegate:(id)delegate
                authenticateSelector:(SEL)confirmSelector
                      cancelSelector:(SEL)cancelSelector {
  CHECK(title);
  CHECK(authenticateButton);
  CHECK(cancelButton);
  [self dismissAlert:NO];
  [self dismissAuthentication:NO];
  _authenticationView = [[UIAlertView alloc] initWithTitle:title
                                                   message:@"\n\n\n"
                                                  delegate:[ApplicationDelegate class]
                                         cancelButtonTitle:cancelButton
                                         otherButtonTitles:authenticateButton, nil];
  _authenticationDelegate = [delegate retain];
  _authenticationAuthenticateSelector = confirmSelector;
  _authenticationCancelSelector = cancelSelector;
  _authenticationUsernameField = [[UITextField alloc] initWithFrame:CGRectMake(12.0, 50.0, 260.0, 25.0)];
  _authenticationUsernameField.keyboardType = UIKeyboardTypeASCIICapable;
  _authenticationUsernameField.autocorrectionType = UITextAutocorrectionTypeNo;
  _authenticationUsernameField.autocapitalizationType = UITextAutocapitalizationTypeNone;
  _authenticationUsernameField.backgroundColor = [UIColor whiteColor];
  _authenticationUsernameField.placeholder = usernamePlaceholder;
  [_authenticationView addSubview:_authenticationUsernameField];
  _authenticationPasswordField = [[UITextField alloc] initWithFrame:CGRectMake(12.0, 85.0, 260.0, 25.0)];
  _authenticationPasswordField.secureTextEntry = YES;
  _authenticationPasswordField.keyboardType = UIKeyboardTypeASCIICapable;
  _authenticationPasswordField.autocorrectionType = UITextAutocorrectionTypeNo;
  _authenticationPasswordField.autocapitalizationType = UITextAutocapitalizationTypeNone;
  _authenticationPasswordField.backgroundColor = [UIColor whiteColor];
  _authenticationPasswordField.placeholder = passwordPlaceholder;
  [_authenticationView addSubview:_authenticationPasswordField];
  [_authenticationView show];
  [_authenticationUsernameField becomeFirstResponder];
}

- (void) dismissAuthentication:(BOOL)animated {
  if (_authenticationView) {
    [_authenticationView dismissWithClickedButtonIndex:_authenticationView.cancelButtonIndex animated:animated];  // Doesn't call delegate on 4.2?
    if (_authenticationView) {
      [self _dismissAuthenticationWithButtonIndex:_authenticationView.cancelButtonIndex];
    }
  }
}

@end

@implementation ApplicationDelegate (Messages)

- (void) _updateMessageLayout {
  CGRect bounds = _overlayWindow.bounds;
  CGPoint center = CGPointMake(bounds.size.width / 2.0, bounds.size.height * 1.0 / 3.0);
  for (UIView* messageView in _messageViews) {
    if (messageView.tag & kTagFlag_Transient) {
      continue;
    }
    CGSize size = messageView.bounds.size;
    center.y += size.height / 2.0;
    if (!(messageView.tag & kTagFlag_New)) {
      [UIView beginAnimations:nil context:NULL];
      [UIView setAnimationCurve:UIViewAnimationCurveEaseInOut];
      [UIView setAnimationDuration:kMessageViewAnimationDuration];
    }
    CGRect frame = messageView.frame;
    frame.origin.x = roundf(center.x - frame.size.width / 2.0);
    frame.origin.y = roundf(center.y - frame.size.height / 2.0);
    messageView.frame = frame;
    if (!(messageView.tag & kTagFlag_New)) {
      [UIView commitAnimations];
    } else {
      messageView.tag &= ~kTagFlag_New;
    }
    center.y += size.height / 2.0 + kMessageSpacing;
  }
}

- (void) _presentMessage:(UIView*)messageView animated:(BOOL)animated {
  [_overlayWindow presentView:messageView];
  if (animated) {
    messageView.alpha = 0.0;
    [UIView beginAnimations:nil context:NULL];
    [UIView setAnimationCurve:UIViewAnimationCurveEaseOut];
    [UIView setAnimationDuration:kMessageViewAnimationDuration];
    messageView.alpha = 1.0;
    [UIView commitAnimations];
  }
  messageView.tag &= ~kTagFlag_Transient;
}

- (void) _messageAnimationDidStop:(NSString*)animationID finished:(NSNumber*)finished context:(void*)context {
  [_overlayWindow dismissView:(UIView*)context];
  [(UIView*)context release];
}

- (void) _dismissMessage:(UIView*)messageView animated:(BOOL)animated {
  if (animated) {
    messageView.tag |= kTagFlag_Transient;
    [UIView beginAnimations:nil context:[messageView retain]];
    [UIView setAnimationDelegate:self];
    [UIView setAnimationDidStopSelector:@selector(_messageAnimationDidStop:finished:context:)];
    [UIView setAnimationCurve:UIViewAnimationCurveEaseIn];
    [UIView setAnimationDuration:kMessageViewAnimationDuration];
    messageView.alpha = 0.0;
    [UIView commitAnimations];
  } else {
    [_overlayWindow dismissView:messageView];
  }
}

- (void) _showMessage:(UIView*)view {
  if ([_messageViews containsObject:view]) {
    [self _presentMessage:view animated:(view.tag & kTagFlag_Animated)];
    [self _updateMessageLayout];
  }
}

- (void) _hideMessage:(UIView*)view {
  if ([_messageViews containsObject:view]) {
    [self _dismissMessage:view animated:(view.tag & kTagFlag_Animated)];
    [_messageViews removeObject:view];
    [self _updateMessageLayout];
  }
}

- (BOOL) areMessagesVisible {
  return _messageViews.count ? YES : NO;
}

- (BOOL) isMessageVisible:(ApplicationMessageIdentifier)identifier {
  for (UIView* messageView in _messageViews) {
    if ((ApplicationMessageIdentifier)messageView == identifier) {
      return YES;
    }
  }
  return NO;
}

- (ApplicationMessageIdentifier) showMessageWithView:(UIView*)view animated:(BOOL)animated {
  return [self showMessageWithView:view delay:0.0 duration:0.0 animated:animated];
}

- (ApplicationMessageIdentifier) showMessageWithView:(UIView*)view
                                               delay:(NSTimeInterval)delay
                                            duration:(NSTimeInterval)duration
                                            animated:(BOOL)animated {
  view.frame = CGRectOffset(view.frame, kMessageBorderWidth, kMessageBorderWidth);
  UIView* messageView = [[UIView alloc] initWithFrame:CGRectInset(view.bounds, -kMessageBorderWidth, -kMessageBorderWidth)];
  messageView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin |
                                 UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
  messageView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:_overlaysOpacity];
  messageView.layer.cornerRadius = 10.0;
  messageView.tag = kTagFlag_New;
  if (animated) {
    messageView.tag |= kTagFlag_Animated;
  }
  [messageView addSubview:view];
  if (_messageViews == nil) {
    _messageViews = [[NSMutableArray alloc] init];
  }
  [_messageViews addObject:messageView];
  [messageView release];
  
  if (delay > 0.0) {
    messageView.tag |= kTagFlag_Transient;
    [self performSelector:@selector(_showMessage:) withObject:messageView afterDelay:delay];
  } else {
    [self _showMessage:messageView];
  }
  
  if (duration > 0.0) {
    [self performSelector:@selector(_hideMessage:)
               withObject:messageView
               afterDelay:(animated ? kMessageViewAnimationDuration + delay + duration : delay + duration)];
  }
  return (ApplicationMessageIdentifier)messageView;
}

- (ApplicationMessageIdentifier) showMessageWithString:(NSString*)message animated:(BOOL)animated {
  return [self showMessageWithString:message delay:0.0 duration:0.0 animated:YES];
}

- (ApplicationMessageIdentifier) showMessageWithString:(NSString*)message
                                                 delay:(NSTimeInterval)delay
                                              duration:(NSTimeInterval)duration
                                              animated:(BOOL)animated {
  UILabel* label = [[UILabel alloc] init];
  label.backgroundColor = nil;
  label.opaque = NO;
  if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
    label.font = [UIFont boldSystemFontOfSize:28.0];
  } else {
    label.font = [UIFont boldSystemFontOfSize:14.0];
  }
  label.textColor = [UIColor whiteColor];
  label.textAlignment = UITextAlignmentCenter;
  label.numberOfLines = 0;
  label.text = message;
  CGSize size = [label sizeThatFits:CGSizeMake(kMessageMaxDimension, kMessageMaxDimension)];
  label.frame = CGRectMake(0.0, 0.0, size.width, size.height);
  ApplicationMessageIdentifier identifier = [self showMessageWithView:label delay:delay duration:duration animated:animated];
  [label release];
  return identifier;
}

- (void) dismissMessage:(ApplicationMessageIdentifier)identifier animated:(BOOL)animated {
  for (NSUInteger i = 0; i < _messageViews.count; ++i) {
    UIView* messageView = [_messageViews objectAtIndex:i];
    if ((ApplicationMessageIdentifier)messageView == identifier) {
      [self _dismissMessage:messageView animated:animated];
      [_messageViews removeObjectAtIndex:i];
      return;
    }
  }
}

- (void) dismissAllMessages:(BOOL)animated {
  for (UIView* messageView in _messageViews) {
    [self _dismissMessage:messageView animated:animated];
  }
  [_messageViews removeAllObjects];
}

@end

@implementation ApplicationDelegate (Spinner)

- (BOOL) isSpinnerVisible {
  return _spinnerView ? YES : NO;
}

- (void) showSpinnerWithMessage:(NSString*)message animated:(BOOL)animated {
  CGRect frame;
  
  [self hideSpinner:NO];
  
  UIActivityIndicatorView* indicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
  indicator.frame = CGRectOffset(indicator.frame, kSpinnerBorderWidth, kSpinnerBorderWidth);
  indicator.hidesWhenStopped = NO;
  [indicator autorelease];
  CGSize size = indicator.frame.size;
  frame.size.width = size.width + 2.0 * kSpinnerBorderWidth;
  frame.size.height = size.height + 2.0 * kSpinnerBorderWidth;
  
  UILabel* label = nil;
  if (message) {
    label = [[UILabel alloc] init];
    label.backgroundColor = nil;
    label.opaque = NO;
    label.font = [UIFont boldSystemFontOfSize:22.0];
    label.textColor = [UIColor whiteColor];
    label.textAlignment = UITextAlignmentCenter;
    label.numberOfLines = 0;
    label.text = message;
    [label sizeToFit];
    [label autorelease];
    CGRect rect = label.frame;
    rect.origin.x = kSpinnerBorderWidth;
    rect.origin.y = frame.size.height - kSpinnerBorderWidth + kSpinnerSpacing;
    label.frame = rect;
    frame.size.width += rect.size.width - size.width;
    frame.size.height += rect.size.height + kSpinnerSpacing;
    CGRect temp = indicator.frame;
    temp.origin.x = roundf(temp.origin.x - temp.size.width / 2.0 + rect.size.width / 2.0);
    indicator.frame = temp;
  }

  CGRect bounds = _overlayWindow.bounds;
  frame.origin.x = roundf(bounds.size.width / 2.0 - frame.size.width / 2.0);
  frame.origin.y = roundf(bounds.size.height / 2.0 - frame.size.height / 2.0);
  _spinnerView = [[UIView alloc] initWithFrame:frame];
  _spinnerView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin |
                                 UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
  _spinnerView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:_overlaysOpacity];
  _spinnerView.layer.cornerRadius = 10.0;
  [_spinnerView addSubview:indicator];
  if (label) {
    [_spinnerView addSubview:label];
  }
  [_overlayWindow presentView:_spinnerView];
  if (animated) {
    _spinnerView.alpha = 0.0;
    [UIView beginAnimations:nil context:NULL];
    [UIView setAnimationCurve:UIViewAnimationCurveEaseOut];
    [UIView setAnimationDuration:kSpinnerViewAnimationDuration];
    _spinnerView.alpha = 1.0;
    [UIView commitAnimations];
  }
  
  [indicator startAnimating];
}

- (void) _spinnerAnimationDidStop:(NSString*)animationID finished:(NSNumber*)finished context:(void*)context {
  [_overlayWindow dismissView:(UIView*)context];
  [(UIView*)context release];
}

- (void) hideSpinner:(BOOL)animated {
  if (_spinnerView) {
    if (animated) {
      [UIView beginAnimations:nil context:[_spinnerView retain]];
      [UIView setAnimationDelegate:self];
      [UIView setAnimationDidStopSelector:@selector(_spinnerAnimationDidStop:finished:context:)];
      [UIView setAnimationCurve:UIViewAnimationCurveEaseIn];
      [UIView setAnimationDuration:kSpinnerViewAnimationDuration];
      _spinnerView.alpha = 0.0;
      [UIView commitAnimations];
    } else {
      [_overlayWindow dismissView:_spinnerView];
    }
    [_spinnerView release];
    _spinnerView = nil;
  }
}

@end

@implementation ApplicationDelegate (Commands)

- (NSString*) command_commands:(id)argument {
  NSMutableArray* array = [NSMutableArray array];
  Class class = [self class];
  do {
    unsigned int count;
    Method* methods = class_copyMethodList(class, &count);
    for (unsigned int i = 0; i < count; ++i) {
      SEL method = method_getName(methods[i]);
      if (strncmp(sel_getName(method), "command_", 8) == 0) {
        NSString* command = [NSString stringWithUTF8String:sel_getName(method)];
        [array addObject:[command substringWithRange:NSMakeRange(8, command.length - 8 - 1)]];
      }
    }
    free(methods);
    class = [class superclass];
  } while (class);
  return [[array sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)] componentsJoinedByString:@"\n"];
}

- (NSString*) command_currentConfiguration:(id)argument {
  if (_configurationDictionary) {
    NSString* string = [_configurationDictionary objectForKey:kConfigurationKeySourceURL];
    if (string) {
      return [NSString stringWithFormat:@"Current configuration loaded from:\n%@", string];
    }
    return @"Current configuration loaded from application";
  }
  return @"No configuration available";
}

- (NSString*) command_forceConfigurationURL:(id)argument {
  NSURL* url = [argument length] ? [NSURL URLWithString:argument] : nil;
  if (url) {
    [[NSUserDefaults standardUserDefaults] setObject:[url absoluteString] forKey:kApplicationUserDefaultKey_ConfigurationURL];
  } else {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kApplicationUserDefaultKey_ConfigurationURL];
  }
  return [NSString stringWithFormat:@"Configuration URL overriden to %@", url];
}

- (NSString*) command_enableRemoteLogging:(id)argument {
  [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kApplicationUserDefaultKey_LoggingServerEnabled];
  return @"Remote logging access will be enabled at next launch";
}

- (NSString*) command_disableRemoteLogging:(id)argument {
  [[NSUserDefaults standardUserDefaults] removeObjectForKey:kApplicationUserDefaultKey_LoggingServerEnabled];
  return @"Remote logging access will be disabled at next launch";
}

#if __DAVSERVER_SUPPORT__

- (NSString*) command_enableWebDAV:(id)argument {
  [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kApplicationUserDefaultKey_WebDAVServerEnabled];
  return @"WebDAV server will be enabled at next launch";
}

- (NSString*) command_disableWebDAV:(id)argument {
  [[NSUserDefaults standardUserDefaults] removeObjectForKey:kApplicationUserDefaultKey_WebDAVServerEnabled];
  return @"WebDAV server will be disabled at next launch";
}

#endif

- (NSString*) command_showIP:(id)argument {
  NSString* address = [[UIDevice currentDevice] currentWiFiAddress];
  return address ? [NSString stringWithFormat:@"Current WiFi IP address:\n%@", address] : @"No WiFi IP address available";
}

- (NSString*) command_clearLog:(id)argument {
  LoggingPurgeHistory(0.0);
  return @"Log has been cleared";
}

- (NSString*) command_showLog:(id)argument {
  DCHECK(_viewController);
  [self showLogViewControllerWithTitle:@"Log Contents"];
  return nil;
}

- (void) mailComposeController:(MFMailComposeViewController*)controller
           didFinishWithResult:(MFMailComposeResult)result
                         error:(NSError*)error {
  [_viewController dismissModalViewControllerAnimated:YES];
}

static void _HistoryErrorsCallback(NSUInteger appVersion, NSTimeInterval timestamp, LogLevel level, NSString* message, void* context) {
  if (level >= kLogLevel_Warning) {
    NSString* date = [[NSDate dateWithTimeIntervalSinceReferenceDate:timestamp] stringWithCachedFormat:@"yyyy-MM-dd HH:mm:ss.SSS"
                                                                                       localIdentifier:@"en_US"];
    [(NSMutableString*)context appendFormat:@"[r%i | %@ | %s] %@\n", appVersion, date, LoggingGetLevelName(level), message];
  }
}

- (NSString*) command_reportErrors:(id)argument {
  DCHECK(_viewController);
  if (![NSClassFromString(@"MFMailComposeViewController") canSendMail]) {
    return @"Device is not configured to send email";
  }
  
  NSMutableString* log = [NSMutableString string];
  LoggingReplayHistory(_HistoryErrorsCallback, log, NO);
  
  MFMailComposeViewController* controller = [[NSClassFromString(@"MFMailComposeViewController") alloc] init];
  controller.mailComposeDelegate = (id<MFMailComposeViewControllerDelegate>)self;
  [controller setSubject:[NSString stringWithFormat:@"Error Log for %@ %@ (%@)",
                                                    [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"],
                                                    [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"],
                                                    [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"]]];
  NSString* email = [ApplicationDelegate objectForConfigurationKey:kApplicationConfigurationKey_ReportEmail];
  [controller setToRecipients:[NSArray arrayWithObject:email]];
  [controller setMessageBody:[NSString stringWithFormat:@"%@\n\n%@", @"<Enter any relevant information here>", log]
                      isHTML:NO];
  [_viewController presentModalViewController:controller animated:YES];
  [controller release];
  return nil;
}

- (NSString*) command_enableOverlayLogging:(id)argument {
  [self setLoggingOverlayEnabled:YES];
  return @"Logging overlay is enabled";
}

- (NSString*) command_disableOverlayLogging:(id)argument {
  [self setLoggingOverlayEnabled:NO];
  return @"Logging overlay is disabled";
}

- (NSString*) command_enableVerboseLogging:(id)argument {
  LoggingSetMinimumLevel(kLogLevel_Verbose);
  return @"Verbose logging is enabled";
}

- (NSString*) command_disableVerboseLogging:(id)argument {
  LoggingSetMinimumLevel(kLogLevel_Warning);
  return @"Verbose logging is disabled";
}

@end

@implementation ApplicationDelegate (LoggingOverlay)

// Called from arbitrary threads
static void _LoggingCallback(LogLevel level, NSString* message) {
  message = [NSString stringWithFormat:@"[%s] %@\n", LoggingGetLevelName(level), message];
  [[TaskQueue sharedTaskQueue] performSelectorOnMainThread:@selector(_loggedMessage:)
                                              withArgument:message
                                               usingTarget:[ApplicationDelegate sharedInstance]];
}

- (void) _showLoggingOverlay {
  if (_loggingOverlayView.superview == nil) {
    _loggingOverlayView.frame = CGRectInset(_overlayWindow.bounds, 25.0, 25.0);
    _loggingOverlayView.alpha = 0.0;
    [_overlayWindow presentView:_loggingOverlayView];
  }
  
  [UIView beginAnimations:nil context:NULL];
  [UIView setAnimationBeginsFromCurrentState:YES];
  _loggingOverlayView.alpha = 1.0;
  [UIView commitAnimations];
}

- (void) _loggingOverlayHideAnimationDidStop:(NSString*)animationID finished:(NSNumber*)finished context:(void*)context {
  [_overlayWindow dismissView:_loggingOverlayView];
  _loggingOverlayView.text = @"";
}

- (void) _hideLoggingOverlay {
  [UIView beginAnimations:nil context:_loggingOverlayView];
  [UIView setAnimationBeginsFromCurrentState:YES];
  [UIView setAnimationDelegate:self];
  [UIView setAnimationDidStopSelector:@selector(_loggingOverlayHideAnimationDidStop:finished:context:)];
  _loggingOverlayView.alpha = 0.0;
  [UIView commitAnimations];
}

- (void) _loggedMessage:(NSString*)message {
  if (_loggingOverlayView) {
    _loggingOverlayView.text = [_loggingOverlayView.text stringByAppendingString:message];
    if (_loggingOverlayView.text.length > 2) {
      [_loggingOverlayView scrollRangeToVisible:NSMakeRange(_loggingOverlayView.text.length - 2, 2)];
    }
    
    [self _showLoggingOverlay];
    [_loggingOverlayTimer setFireDate:[NSDate dateWithTimeIntervalSinceNow:kLoggingOverlayDisplayDuration]];
  }
}

- (void) setLoggingOverlayEnabled:(BOOL)flag {
  if (flag && !_loggingOverlayView) {
    [TaskQueue sharedTaskQueue]; // Make sure TaskQueue exists
    
    _loggingOverlayView = [[UITextView alloc] init];
    _loggingOverlayView.layer.cornerRadius = 6.0;
    _loggingOverlayView.opaque = NO;
    _loggingOverlayView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:_overlaysOpacity];
    _loggingOverlayView.textColor = [UIColor whiteColor];
    _loggingOverlayView.font = [UIFont fontWithName:kLoggingFontName size:kLoggingFontSize];
    _loggingOverlayView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    
    _loggingOverlayTimer = [[NSTimer alloc] initWithFireDate:[NSDate distantFuture]
                                                    interval:HUGE_VAL
                                                      target:self
                                                    selector:@selector(_hideLoggingOverlay)
                                                    userInfo:nil repeats:YES];
    [[NSRunLoop currentRunLoop] addTimer:_loggingOverlayTimer forMode:NSRunLoopCommonModes];
    LoggingSetCallback(_LoggingCallback);
  } else if (!flag && _loggingOverlayView) {
    LoggingSetCallback(NULL);
    [_loggingOverlayTimer invalidate];
    [_loggingOverlayTimer release];
    _loggingOverlayTimer = nil;
    [_loggingOverlayView release];
    _loggingOverlayView = nil;
  }
}

- (BOOL) isLoggingOverlayEnabled {
  return (_loggingOverlayView != nil);
}

@end
