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

#import <Foundation/Foundation.h>
#if TARGET_OS_IPHONE
#import <CoreGraphics/CoreGraphics.h>
#else
#import <ApplicationServices/ApplicationServices.h>
#endif

typedef enum {
  kImageScalingMode_Resize,
  kImageScalingMode_AspectFill,
  kImageScalingMode_AspectFit
} ImageScalingMode;

#ifdef __cplusplus
extern "C" {
#endif
BOOL ImageHasAlpha(CGImageRef image);
CGImageRef CreateMaskImage(CGImageRef image);
CGImageRef CreateMonochromeImage(CGImageRef image, CGColorRef backgroundColor);  // Use luminance for conversion
CGImageRef CreateTintedImage(CGImageRef image, CGColorRef tintColor, CGColorRef backgroundColor);  // Pass no tint color for pure monochrome - Background color must be monochrome
CGImageRef CreateScaledImage(CGImageRef image, CGSize size, ImageScalingMode scaling, CGColorRef backgroundColor);
CGImageRef CreateFlippedImage(CGImageRef image, BOOL flipHorizontally, BOOL flipVertically, CGColorRef backgroundColor);
CGImageRef CreateRotatedImage(CGImageRef image, CGFloat angle, CGColorRef backgroundColor);  // Angle is in degrees
CGImageRef CreateMaskedImage(CGImageRef image, CGImageRef maskImage, BOOL resizeMask);  // Either "image" or "maskImage" is resized
CGFloat CompareImages(CGImageRef baseImage, CGImageRef image, CGImageRef* differenceImage, BOOL normalizeDifferenceImage);  // Returns [0,1] match or NAN on failure
CGImageRef CreateRenderedPDFPage(CGPDFPageRef page, CGSize size, ImageScalingMode scaling, CGColorRef backgroundColor);  // Pass zero size for original dimensions
CGColorRef CreateImagePatternColor(CGImageRef image);
#ifdef __cplusplus
}
#endif
