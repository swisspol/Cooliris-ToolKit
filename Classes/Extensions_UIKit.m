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

#import <arpa/inet.h>
#import <ifaddrs.h>
#import <netdb.h>
#import <netinet/in.h>

#import "Extensions_UIKit.h"
#import "Extensions_Foundation.h"
#import "Extensions_CoreAnimation.h"
#import "ImageUtilities.h"
#import "Logging.h"

// UIKit +colorWithPatternImage maintains a cache of recent conversions through the SetCachedPatternColor() SPI which can grow out of control
// Creating patterns using CG API directly bypasses this cache but relies on the client caching created colors as necessary
#define __USE_UIKIT_FOR_COLOR_PATTERNS__ 0

#define kRawHeaderVersion 1
#define kRawHeaderSize 4096  // Page size
#define kRowBytesAlignment 16

typedef struct {
  size_t version;
  size_t width;
  size_t height;
  size_t rowBytes;
  CGBitmapInfo bitmapInfo;
} RawHeader;  // Must be <= kRawHeaderSize

NSString* NSStringFromUIColor(UIColor* color) {
  NSString* string = nil;
  CGColorRef cgColor = [color CGColor];
  if (cgColor) {
    const CGFloat* components = CGColorGetComponents(cgColor);
    switch (CGColorGetNumberOfComponents(cgColor)) {
      
      case 2:
        if (components[1] < 1.0) {
          string = [NSString stringWithFormat:@"%g %g", components[0], components[1]];
        } else {
          string = [NSString stringWithFormat:@"%g", components[0]];
        }
        break;
        
      case 4:
        if (components[3] < 1.0) {
          string = [NSString stringWithFormat:@"%g %g %g %g", components[0], components[1], components[2], components[3]];
        } else {
          string = [NSString stringWithFormat:@"%g %g %g", components[0], components[1], components[2]];
        }
        break;
        
      default:
        DNOT_REACHED();
        break;
      
    }
  }
  return string;
}

UIColor* UIColorFromString(NSString* string) {
  UIColor* color = nil;
  if (string.length) {
    NSArray* array = [string componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    switch (array.count) {
      
      case 1:
        color = [UIColor colorWithWhite:[[array objectAtIndex:0] floatValue] alpha:1.0];
        break;
      
      case 2:
        color = [UIColor colorWithWhite:[[array objectAtIndex:0] floatValue] alpha:[[array objectAtIndex:1] floatValue]];
        break;
      
      case 3:
        color = [UIColor colorWithRed:[[array objectAtIndex:0] floatValue]
                                green:[[array objectAtIndex:1] floatValue]
                                 blue:[[array objectAtIndex:2] floatValue]
                                alpha:1.0];
        break;
      
      case 4:
        color = [UIColor colorWithRed:[[array objectAtIndex:0] floatValue]
                                green:[[array objectAtIndex:1] floatValue]
                                 blue:[[array objectAtIndex:2] floatValue]
                                alpha:[[array objectAtIndex:3] floatValue]];
        break;
      
    }
  }
  return color;
}

@implementation UIColor (Extensions)

+ (UIColor*) backgroundColorWithPatternImage:(UIImage*)image {
#if __USE_UIKIT_FOR_COLOR_PATTERNS__
  if (image && (kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_4_0)) {
    CGImageRef imageRef = CreateFlippedImage([image CGImage], NO, YES, NULL);
    if (imageRef) {
      image = [UIImage imageWithCGImage:imageRef];
      CGImageRelease(imageRef);
    } else {
      image = nil;
    }
  }
  return image ? [UIColor colorWithPatternImage:image] : nil;
#else
  UIColor* color = nil;
  if (image) {
    CGColorRef cgColor = CreateImagePatternColor([image CGImage]);
    if (cgColor) {
      color = [UIColor colorWithCGColor:cgColor];
      CGColorRelease(cgColor);
    }
  }
  return color;
#endif
}

@end

@implementation UIImage (Extensions)

+ (UIImage*) imageWithName:(NSString*)name {
  NSString* path = [[NSBundle mainBundle] pathForResource:name ofType:nil];
  return path ? [UIImage imageWithContentsOfFile:path] : nil;
}

+ (UIImage*) imageWithContentsOfRawFile:(NSString*)path {
  return [[[UIImage alloc] initWithContentsOfRawFile:path] autorelease];
}

static void _ReleaseDataCallback(void* info, const void* data, size_t size) {
  [(NSData*)info release];
}

- (id) initWithContentsOfRawFile:(NSString*)path {
  CGImageRef image = NULL;
#if 0
  NSData* data = [[NSData alloc] initWithContentsOfMappedFile:path];
#else
  NSData* data = [[NSData alloc] initWithContentsOfFile:path];
#endif
  if (data) {
    RawHeader* header = (RawHeader*)data.bytes;
    if (header->version == kRawHeaderVersion) {
      CGDataProviderRef provider = CGDataProviderCreateWithData(data, (char*)data.bytes + kRawHeaderSize, data.length - kRawHeaderSize,
                                                                _ReleaseDataCallback);
      if (provider) {
        CGColorSpaceRef colorspace = CGColorSpaceCreateDeviceRGB();
        image = CGImageCreate(header->width, header->height, 8, 32, header->rowBytes, colorspace, header->bitmapInfo, provider,
                              NULL, true, kCGRenderingIntentDefault);
        CGColorSpaceRelease(colorspace);
        CGDataProviderRelease(provider);
      } else {
        [data release];
      }
    } else {
      [data release];
    }
  }
  if (image) {
    self = [self initWithCGImage:image];
    CGImageRelease(image);
  } else {
    [self release];
    self = nil;
  }
  return self;
}

- (BOOL) writeRawFile:(NSString*)path atomically:(BOOL)atomically {
  BOOL success = NO;
  CGImageRef image = [self CGImage];
  size_t width = CGImageGetWidth(image);
  size_t height = CGImageGetHeight(image);
  size_t rowBytes = width * 4;
  if (rowBytes % kRowBytesAlignment) {
    rowBytes = (rowBytes / kRowBytesAlignment + 1) * kRowBytesAlignment;
  }
  CGBitmapInfo info = (ImageHasAlpha(image) ? kCGImageAlphaPremultipliedFirst : kCGImageAlphaNoneSkipFirst)
                      | kCGBitmapByteOrder32Host;
  
  NSMutableData* data = [[NSMutableData alloc] initWithLength:(kRawHeaderSize + height * rowBytes)];
  if (data) {
    RawHeader* header = (RawHeader*)data.mutableBytes;
    header->version = kRawHeaderVersion;
    header->width = width;
    header->height = height;
    header->rowBytes = rowBytes;
    header->bitmapInfo = info;
    
    CGColorSpaceRef colorspace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate((char*)data.mutableBytes + kRawHeaderSize, width, height, 8, rowBytes, colorspace,
                                                 info);
    CGContextSetBlendMode(context, kCGBlendModeCopy);
    CGContextDrawImage(context, CGRectMake(0.0, 0.0, width, height), image);
    CGContextRelease(context);
    CGColorSpaceRelease(colorspace);
    success = [data writeToFile:path atomically:atomically];
    
    [data release];
  }
  return success;
}

@end

@implementation UIApplication (Extensions)

static NSInteger _networkIndicatorVisible = 0;

- (void) showNetworkActivityIndicator {
  ++_networkIndicatorVisible;
  [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:(_networkIndicatorVisible > 0)];
}

- (void) hideNetworkActivityIndicator {
  --_networkIndicatorVisible;
  [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:(_networkIndicatorVisible > 0)];
}

@end

@implementation UITableView (Extensions)

- (void) clearSelectedRow {
  NSIndexPath* path = [self indexPathForSelectedRow];
  if (path) {
    [self deselectRowAtIndexPath:path animated:NO];
  }
}

@end

@implementation UIView (Extensions)

- (UIImage*) renderAsImage {
  return [UIImage imageWithCGImage:[self.layer renderAsCGImageWithBackgroundColor:NULL]];
}

- (UIImage*) renderAsImageWithBackgroundColor:(UIColor*)color {
  return [UIImage imageWithCGImage:[self.layer renderAsCGImageWithBackgroundColor:[color CGColor]]];
}

- (NSData*) renderAsPDF {
  return [self.layer renderAsPDF];
}

@end

@implementation  UINavigationController (Extensions)

- (UIViewController*) rootViewController {
  return [self.viewControllers firstObject];
}

@end

@implementation UIDevice (Extensions)

- (NSString*) currentWiFiAddress {
  NSString* string = nil;
  struct ifaddrs* list;
  if (getifaddrs(&list) >= 0) {
    for (struct ifaddrs* ifap = list; ifap; ifap = ifap->ifa_next) {
#if TARGET_IPHONE_SIMULATOR
      if (strcmp(ifap->ifa_name, "en0") && strcmp(ifap->ifa_name, "en1"))  // Assume en0 is Ethernet and en1 is WiFi
#else
      if (strcmp(ifap->ifa_name, "en0"))  // Assume en0 is WiFi
#endif
      {
        continue;
      }
      
      if (ifap->ifa_addr->sa_family == AF_INET) {  // AF_INET6
        const struct sockaddr* address = ifap->ifa_addr;
        char buffer[NI_MAXHOST] = {0};
        if (getnameinfo(address, address->sa_len, buffer, NI_MAXHOST, NULL, 0, NI_NUMERICHOST | NI_NUMERICSERV | NI_NOFQDN) >= 0) {
          string = [NSString stringWithUTF8String:buffer];
        }
        break;
      }
    }
    freeifaddrs(list);
  }
  return string;
}

@end
