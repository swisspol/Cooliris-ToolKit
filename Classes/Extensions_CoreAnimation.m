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

#import "Extensions_CoreAnimation.h"

@implementation CALayer (Extensions)

- (CGImageRef) renderAsCGImageWithBackgroundColor:(CGColorRef)color {
  CGRect bounds = self.bounds;
  NSUInteger width = bounds.size.width;
  NSUInteger height = bounds.size.height;
  CGColorSpaceRef colorspace = CGColorSpaceCreateDeviceRGB();
  CGImageAlphaInfo info = (color == NULL) || (CGColorGetAlpha(color) < 1.0) ? kCGImageAlphaPremultipliedFirst
                                                                            : kCGImageAlphaNoneSkipFirst;
  CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, 0, colorspace, info | kCGBitmapByteOrder32Host);
  CGColorSpaceRelease(colorspace);
  
  if (color) {
    CGContextSetFillColorWithColor(context, color);
    CGContextFillRect(context, CGRectMake(0, 0, width, height));
  } else {
    CGContextClearRect(context, CGRectMake(0, 0, width, height));
  }
  
  CGContextTranslateCTM(context, 0, height);
  CGContextScaleCTM(context, 1.0, -1.0);
  [self renderInContext:context];
  
  CGImageRef imageRef = CGBitmapContextCreateImage(context);
  CGContextRelease(context);
  return (CGImageRef)[(id)imageRef autorelease];
}

- (NSData*) renderAsPDF {
  CGRect bounds = self.bounds;
  NSMutableData* data = [NSMutableData data];
  CGDataConsumerRef consumer = CGDataConsumerCreateWithCFData((CFMutableDataRef)data);
  CGContextRef context = CGPDFContextCreate(consumer, &bounds, NULL);
  CGDataConsumerRelease(consumer);
  CGPDFContextBeginPage(context, NULL);
  
  CGContextTranslateCTM(context, 0, bounds.size.height);
  CGContextScaleCTM(context, 1.0, -1.0);
  [self renderInContext:context];
  
  CGPDFContextEndPage(context);
  CGPDFContextClose(context);
  CGContextRelease(context);
  return data;
}

@end
