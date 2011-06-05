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

#define kUIImageRawExtension @"raw"

#ifdef __cplusplus
extern "C" {
#endif
UIColor* UIColorFromString(NSString* string);
NSString* NSStringFromUIColor(UIColor* color);
#ifdef __cplusplus
}
#endif

@interface UIColor (Extensions)
+ (UIColor*) backgroundColorWithPatternImage:(UIImage*)image;  // Use instead of +colorWithPatternImage: to create CGColors for -[CALayer backgroundColor] as it works around radr://8639612 on iOS 4.2
@end

@interface UIImage (Extensions)
+ (UIImage*) imageWithName:(NSString*)name;  // Like +imageNamed: but thread-safe and doesn't cache
+ (UIImage*) imageWithContentsOfRawFile:(NSString*)path;
- (id) initWithContentsOfRawFile:(NSString*)path;
- (BOOL) writeRawFile:(NSString*)path atomically:(BOOL)atomically;
@end

@interface UIApplication (Extensions)
- (void) showNetworkActivityIndicator;  // Use instead of "networkActivityIndicatorVisible" (nestable)
- (void) hideNetworkActivityIndicator;  // Use instead of "networkActivityIndicatorVisible" (nestable)
@end

@interface UITableView (Extensions)
- (void) clearSelectedRow;
@end

@interface UIView (Extensions)
- (UIImage*) renderAsImage;  // Transparent background
- (UIImage*) renderAsImageWithBackgroundColor:(UIColor*)color;
- (NSData*) renderAsPDF;
@end

@interface  UINavigationController (Extensions)
@property(nonatomic, readonly) UIViewController* rootViewController;
@end

@interface UIDevice (Extensions)
- (NSString*) currentWiFiAddress;
@end
