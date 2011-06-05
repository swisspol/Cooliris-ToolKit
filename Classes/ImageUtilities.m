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

#import "ImageUtilities.h"

#define kRowBytesAlignment 32
#define kEpsilon 0.001

BOOL ImageHasAlpha(CGImageRef image) {
  switch (CGImageGetAlphaInfo(image)) {
    
    case kCGImageAlphaPremultipliedLast:
    case kCGImageAlphaPremultipliedFirst:
    case kCGImageAlphaLast:
    case kCGImageAlphaFirst:
      return YES;
    
    default:
      return NO;
    
  }
}

CGImageRef CreateMaskImage(CGImageRef image) {
  size_t width = CGImageGetWidth(image);
  size_t height = CGImageGetHeight(image);
  size_t rowBytes = width;
  if (rowBytes % kRowBytesAlignment) {
    rowBytes = (rowBytes / kRowBytesAlignment + 1) * kRowBytesAlignment;
  }
  
  void* inBuffer = valloc(height * rowBytes);
  CGColorSpaceRef colorspace = CGColorSpaceCreateDeviceGray();
  CGContextRef context = CGBitmapContextCreate(inBuffer, width, height, 8, rowBytes, colorspace, kCGImageAlphaNone);
  CGColorSpaceRelease(colorspace);
  CGContextDrawImage(context, CGRectMake(0.0, 0.0, width, height), image);
  CGContextRelease(context);
  
  void* outBuffer = valloc(height * rowBytes);
  context = CGBitmapContextCreate(outBuffer, width, height, 8, rowBytes, NULL, kCGImageAlphaOnly);
  bcopy(inBuffer, outBuffer, height * rowBytes);
  image = CGBitmapContextCreateImage(context);  // We assume this copies the underlying buffer immediately
  CGContextRelease(context);
  
  free(outBuffer);
  free(inBuffer);
  
  return image;
}

CGImageRef CreateMonochromeImage(CGImageRef image, CGColorRef backgroundColor) {
  size_t width = CGImageGetWidth(image);
  size_t height = CGImageGetHeight(image);
  
  CGColorSpaceRef colorspace = CGColorSpaceCreateDeviceGray();
  CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, 0, colorspace, kCGImageAlphaNone);
  CGColorSpaceRelease(colorspace);
  if (backgroundColor) {
    CGContextSetFillColorWithColor(context, backgroundColor);
    CGContextFillRect(context, CGRectMake(0.0, 0.0, width, height));
  }
  CGContextDrawImage(context, CGRectMake(0.0, 0.0, width, height), image);
  image = CGBitmapContextCreateImage(context);
  CGContextRelease(context);
  
  return image;
}

static void _ReleaseDataCallback(void* info, const void* data, size_t size) {
  free(info);
}

CGImageRef CreateTintedImage(CGImageRef image, CGColorRef tintColor, CGColorRef backgroundColor) {
  size_t width = CGImageGetWidth(image);
  size_t height = CGImageGetHeight(image);
  size_t rowBytes = 4 * width;
  if (rowBytes % kRowBytesAlignment) {
    rowBytes = (rowBytes / kRowBytesAlignment + 1) * kRowBytesAlignment;
  }
  void* data = valloc(height * rowBytes);
  
  CGColorSpaceRef colorspace = CGColorSpaceCreateDeviceRGB();
  
  CGImageAlphaInfo info = (backgroundColor ? CGColorGetAlpha(backgroundColor) < 1.0 : ImageHasAlpha(image))
    ? kCGImageAlphaPremultipliedFirst : kCGImageAlphaNoneSkipFirst;
  CGContextRef context = CGBitmapContextCreate(data, width, height, 8, rowBytes, colorspace, info | kCGBitmapByteOrder32Host);
  if (backgroundColor) {
    CGContextSetFillColorWithColor(context, backgroundColor);
    CGContextFillRect(context, CGRectMake(0.0, 0.0, width, height));
  } else {
    CGContextSetBlendMode(context, kCGBlendModeCopy);
  }
  CGContextDrawImage(context, CGRectMake(0.0, 0.0, width, height), image);
  CGContextRelease(context);
  
  // Bitmap byte order is ARGB
  size_t count = tintColor ? CGColorGetNumberOfComponents(tintColor) : 0;
  if (count == 4) {
    const CGFloat* components = CGColorGetComponents(tintColor);
    uint32_t tr = components[0] * 255.0;
    uint32_t tg = components[1] * 255.0;
    uint32_t tb = components[2] * 255.0;
    uint32_t ta = components[3] * 255.0;
    
    void* baseAddress = data;
    for (size_t i = 0; i < height; ++i) {
      uint32_t* pixel = baseAddress;
      for (size_t j = 0; j < width; ++j) {
        uint32_t a = (*pixel >> 24) & 0xFF;
        uint32_t r = (*pixel >> 16) & 0xFF;
        uint32_t g = (*pixel >> 8) & 0xFF;
        uint32_t b = (*pixel >> 0) & 0xFF;
        uint32_t i = (r + g + b) / 3;
        a = ((a * ta) / 255) & 0xFF;
        r = ((i * tr) / 255) & 0xFF;
        g = ((i * tg) / 255) & 0xFF;
        b = ((i * tb) / 255) & 0xFF;
        *pixel = (a << 24) | (r << 16) | (g << 8) | (b << 0);
        ++pixel;
      }
      baseAddress += rowBytes;
    }
  } else {
    void* baseAddress = data;
    for (size_t i = 0; i < height; ++i) {
      uint32_t* pixel = baseAddress;
      for (size_t j = 0; j < width; ++j) {
        uint32_t a = (*pixel >> 24) & 0xFF;
        uint32_t r = (*pixel >> 16) & 0xFF;
        uint32_t g = (*pixel >> 8) & 0xFF;
        uint32_t b = (*pixel >> 0) & 0xFF;
        uint32_t i = (r + g + b) / 3;
        *pixel = (a << 24) | (i << 16) | (i << 8) | (i << 0);
        ++pixel;
      }
      baseAddress += rowBytes;
    }
  }
  
  CGDataProviderRef provider = CGDataProviderCreateWithData(data, data, height * rowBytes, _ReleaseDataCallback);
  image = CGImageCreate(width, height, 8, 32, rowBytes, colorspace, info | kCGBitmapByteOrder32Host, provider, NULL, true,
                        kCGRenderingIntentDefault);
  CGDataProviderRelease(provider);
  
  CGColorSpaceRelease(colorspace);
  
  return image;
}

// This assumes color matching is disabled on the iPhone OS
CGImageRef CreateScaledImage(CGImageRef image, CGSize size, ImageScalingMode scaling, CGColorRef backgroundColor) {
  size_t contextWidth;
  size_t contextHeight;
  CGRect rect;
  switch (scaling) {
    
    case kImageScalingMode_Resize: {
      contextWidth = size.width;
      contextHeight = size.height;
      rect = CGRectMake(0.0, 0.0, contextWidth, contextHeight);
      break;
    }
    
    case kImageScalingMode_AspectFill: {
      contextWidth = size.width;
      contextHeight = size.height;
      CGFloat imageWidth = CGImageGetWidth(image);
      CGFloat imageHeight = CGImageGetHeight(image);
      if (imageWidth / size.width >= imageHeight / size.height) {
        CGFloat width = (CGFloat)contextHeight * imageWidth / imageHeight;
        rect = CGRectMake(((CGFloat)contextWidth - width) / 2.0, 0.0, width, contextHeight);
      } else {
        CGFloat height = (CGFloat)contextWidth * imageHeight / imageWidth;
        rect = CGRectMake(0.0, ((CGFloat)contextHeight - height) / 2.0, contextWidth, height);
      }
      break;
    }
    
    case kImageScalingMode_AspectFit: {
      CGFloat imageWidth = CGImageGetWidth(image);
      CGFloat imageHeight = CGImageGetHeight(image);
      if (imageWidth / size.width >= imageHeight / size.height) {
        contextHeight = (CGFloat)imageHeight / ((CGFloat)imageWidth / size.width);
        contextWidth = size.width;
      } else {
        contextWidth = (CGFloat)imageWidth / ((CGFloat)imageHeight / size.height);
        contextHeight = size.height;
      }
      rect = CGRectMake(0.0, 0.0, contextWidth, contextHeight);
      break;
    }
    
  }
  CGColorSpaceRef colorspace = CGColorSpaceCreateDeviceRGB();
  CGImageAlphaInfo info = (backgroundColor ? CGColorGetAlpha(backgroundColor) < 1.0 : ImageHasAlpha(image))
    ? kCGImageAlphaPremultipliedFirst : kCGImageAlphaNoneSkipFirst;
  CGContextRef context = CGBitmapContextCreate(NULL, contextWidth, contextHeight, 8, 0, colorspace, info | kCGBitmapByteOrder32Host);
  CGColorSpaceRelease(colorspace);
  if (backgroundColor) {
    CGContextSetFillColorWithColor(context, backgroundColor);
    CGContextFillRect(context, CGRectMake(0.0, 0.0, contextWidth, contextHeight));
  }
  CGContextDrawImage(context, rect, image);
  image = CGBitmapContextCreateImage(context);
  CGContextRelease(context);
  return image;
}

// This assumes color matching is disabled on the iPhone OS
CGImageRef CreateFlippedImage(CGImageRef image, BOOL flipHorizontally, BOOL flipVertically, CGColorRef backgroundColor) {
  size_t width = CGImageGetWidth(image);
  size_t height = CGImageGetHeight(image);
  
  CGColorSpaceRef colorspace = CGColorSpaceCreateDeviceRGB();
  CGImageAlphaInfo info = (backgroundColor ? CGColorGetAlpha(backgroundColor) < 1.0 : ImageHasAlpha(image))
    ? kCGImageAlphaPremultipliedFirst : kCGImageAlphaNoneSkipFirst;
  CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, 0, colorspace, info | kCGBitmapByteOrder32Host);
  CGColorSpaceRelease(colorspace);
  if (backgroundColor) {
    CGContextSetFillColorWithColor(context, backgroundColor);
    CGContextFillRect(context, CGRectMake(0.0, 0.0, width, height));
  }
  if (flipHorizontally) {
    CGContextTranslateCTM(context, width, 0.0);
    CGContextScaleCTM(context, -1.0, 1.0);
  }
  if (flipVertically) {
    CGContextTranslateCTM(context, 0.0, height);
    CGContextScaleCTM(context, 1.0, -1.0);
  }
  CGContextDrawImage(context, CGRectMake(0.0, 0.0, width, height), image);
  image = CGBitmapContextCreateImage(context);
  CGContextRelease(context);
  
  return image;
}

// This assumes color matching is disabled on the iPhone OS
CGImageRef CreateRotatedImage(CGImageRef image, CGFloat angle, CGColorRef backgroundColor) {
  size_t width = CGImageGetWidth(image);
  size_t height = CGImageGetHeight(image);
  CGRect inRect = CGRectMake(0.0, 0.0, width, height);
  CGAffineTransform transform = CGAffineTransformMakeRotation(angle / 180.0 * M_PI);
  CGRect outRect = CGRectIntegral(CGRectApplyAffineTransform(inRect, transform));
  width = outRect.size.width;
  height = outRect.size.height;
  
  CGColorSpaceRef colorspace = CGColorSpaceCreateDeviceRGB();
  CGImageAlphaInfo info = !backgroundColor || (CGColorGetAlpha(backgroundColor) < 1.0)
    ? kCGImageAlphaPremultipliedFirst : kCGImageAlphaNoneSkipFirst;
  CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, 0, colorspace, info | kCGBitmapByteOrder32Host);
  CGColorSpaceRelease(colorspace);
  if (backgroundColor) {
    CGContextSetFillColorWithColor(context, backgroundColor);
    CGContextFillRect(context, CGRectMake(0.0, 0.0, width, height));
  } else {
    CGContextClearRect(context, CGRectMake(0.0, 0.0, width, height));
  }
  CGContextTranslateCTM(context, -outRect.origin.x, -outRect.origin.y);
  CGContextConcatCTM(context, transform);
  CGContextDrawImage(context, inRect, image);
  image = CGBitmapContextCreateImage(context);
  CGContextRelease(context);
  return image;
}

// This assumes color matching is disabled on the iPhone OS
CGImageRef CreateMaskedImage(CGImageRef image, CGImageRef maskImage, BOOL resizeMask) {
  size_t width = resizeMask ? CGImageGetWidth(image) : CGImageGetWidth(maskImage);
  size_t height = resizeMask ? CGImageGetHeight(image) : CGImageGetHeight(maskImage);
  
  CGColorSpaceRef colorspace = CGColorSpaceCreateDeviceRGB();
  CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, 0, colorspace,
                                               kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host);
  CGColorSpaceRelease(colorspace);
  CGContextClearRect(context, CGRectMake(0.0, 0.0, width, height));
  CGContextClipToMask(context, CGRectMake(0.0, 0.0, width, height), maskImage);
  CGContextDrawImage(context, CGRectMake(0.0, 0.0, width, height), image);
  image = CGBitmapContextCreateImage(context);
  CGContextRelease(context);
  
  return image;
}

static void _ReleaseBuffer(void* info, const void* data, size_t size) {
  free((void*)data);
}

CGFloat CompareImages(CGImageRef baseImage, CGImageRef image, CGImageRef* differenceImage, BOOL normalizeDifferenceImage) {
  CGFloat result = NAN;
  CGColorSpaceRef colorspace = CGImageGetColorSpace(baseImage);
  size_t width = CGImageGetWidth(baseImage);
  size_t height = CGImageGetHeight(baseImage);
  if ((width == CGImageGetWidth(image)) && (height == CGImageGetHeight(image)) &&
    (CGColorSpaceGetModel(colorspace) == CGColorSpaceGetModel(CGImageGetColorSpace(image))) &&
    (ImageHasAlpha(baseImage) == ImageHasAlpha(image))) {
    CGBitmapInfo info = CGImageGetBitmapInfo(baseImage);
    
    size_t componentsPerPixel;
    if ((CGColorSpaceGetModel(colorspace) == kCGColorSpaceModelMonochrome) &&
      (((info & kCGBitmapAlphaInfoMask) == kCGImageAlphaNone) || ((info & kCGBitmapAlphaInfoMask) == kCGImageAlphaOnly))) {
      componentsPerPixel = 1;
    } else {
      componentsPerPixel = 4;
      
      if ((info & kCGBitmapAlphaInfoMask) == kCGImageAlphaNone) {
        info = (info & ~kCGBitmapAlphaInfoMask) | kCGImageAlphaPremultipliedFirst;
      } else {
        if (((info & kCGBitmapAlphaInfoMask) == kCGImageAlphaPremultipliedFirst) ||
          ((info & kCGBitmapAlphaInfoMask) == kCGImageAlphaFirst) ||
          ((info & kCGBitmapAlphaInfoMask) == kCGImageAlphaNoneSkipFirst)) {
          info = (info & ~kCGBitmapAlphaInfoMask) | kCGImageAlphaPremultipliedFirst;
        } else {
          info = (info & ~kCGBitmapAlphaInfoMask) | kCGImageAlphaPremultipliedLast;
        }
      }
    }
    
    size_t bitsPerComponent;
    if (info & kCGBitmapFloatComponents) {
      bitsPerComponent = 32;
    } else {
      bitsPerComponent = 8;
    }
    
    size_t rowBytes = width * bitsPerComponent / 8 * componentsPerPixel;
    void* baseBuffer = calloc(height, rowBytes);
    void* buffer = calloc(height, rowBytes);
    CGContextRef baseContext =
      (baseBuffer ? CGBitmapContextCreate(baseBuffer, width, height, bitsPerComponent, rowBytes, colorspace, info) : NULL);
    CGContextRef context =
      (buffer ? CGBitmapContextCreate(buffer, width, height, bitsPerComponent, rowBytes, colorspace, info) : NULL);
    
    if (baseContext && context) {
      result = 0.0;
      
      CGContextDrawImage(baseContext, CGRectMake(0, 0, width, height), baseImage);
      CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
      
      CGDataProviderRef provider = NULL;
      void* diffBuffer = NULL;
      if (differenceImage) {
        diffBuffer = malloc(width * height);
        if (diffBuffer) {
          provider = CGDataProviderCreateWithData(NULL, diffBuffer, width * height, _ReleaseBuffer);
          if (provider == NULL) {
            free(diffBuffer);
            diffBuffer = NULL;
          }
        }
      }
      
      CGFloat count = 0.0;
      CGFloat max = 0.0;
      unsigned char* basePixel = (unsigned char*)baseBuffer;
      unsigned char* pixel = (unsigned char*)buffer;
      unsigned char* diff = (unsigned char*)diffBuffer;
      if (bitsPerComponent == 8) {
        if (componentsPerPixel == 1) {  // I8
          for (size_t y = 0; y < height; ++y) {
            for (size_t x = 0; x < width; ++x) {
              CGFloat value;
              if (*pixel >= *basePixel) {
                value = ((CGFloat)*pixel - (CGFloat)*basePixel) / 255.0;
              } else {
                value = ((CGFloat)*basePixel - (CGFloat)*pixel) / 255.0;
              }
              result += value;
              
              if (value >= kEpsilon) {
                count += 1.0;
              }
              
              if (provider) {
                if (value > max) {
                  max = value;
                }
                *diff++ = (*pixel >= *basePixel ? *pixel - *basePixel : *basePixel - *pixel);
              }
              
              basePixel += 1;
              pixel += 1;
            }
          }
        }
        else {  // ARGB8
          for (size_t y = 0; y < height; ++y) {
            for (size_t x = 0; x < width; ++x) {
              CGFloat value = ((CGFloat)pixel[0] - (CGFloat)basePixel[0]) * ((CGFloat)pixel[0] - (CGFloat)basePixel[0]);
              value += ((CGFloat)pixel[1] - (CGFloat)basePixel[1]) * ((CGFloat)pixel[1] - (CGFloat)basePixel[1]);
              value += ((CGFloat)pixel[2] - (CGFloat)basePixel[2]) * ((CGFloat)pixel[2] - (CGFloat)basePixel[2]);
              value += ((CGFloat)pixel[3] - (CGFloat)basePixel[3]) * ((CGFloat)pixel[3] - (CGFloat)basePixel[3]);
              value = sqrtf(value) / 255.0;
              result += value;
              
              if (value >= kEpsilon) {
                count += 1.0;
              }
              
              if (provider) {
                if (value > max) {
                  max = value;
                }
                *diff++ = (value < 0.0 ? 0 : (value > 1.0 ? 255 : (unsigned char)(value * 255.0)));
              }
              
              basePixel += 4;
              pixel += 4;
            }
          }
        }
      } else {
        if (componentsPerPixel == 1) {  // If
          for (size_t y = 0; y < height; ++y) {
            for (size_t x = 0; x < width; ++x) {
              CGFloat value;
              if (*(float*)pixel >= *(float*)basePixel) {
                value = *(float*)pixel - *(float*)basePixel;
              } else {
                value = *(float*)basePixel - *(float*)pixel;
              }
              value = MAX(MIN(value, 1.0), 0.0);
              result += value;
              
              if (value >= kEpsilon) {
                count += 1.0;
              }
              
              if (provider) {
                if (value > max) {
                  max = value;
                }
                *diff++ = (value < 0.0 ? 0 : (value > 1.0 ? 255 : (unsigned char)(value * 255.0)));
              }
              
              basePixel += 4;
              pixel += 4;
            }
          }
        } else {  // RGBAf
          for (size_t y = 0; y < height; ++y) {
            for (size_t x = 0; x < width; ++x) {
              CGFloat value = (((float*)pixel)[0] - ((float*)basePixel)[0]) * (((float*)pixel)[0] - ((float*)basePixel)[0]);
              value += (((float*)pixel)[1] - ((float*)basePixel)[1]) * (((float*)pixel)[1] - ((float*)basePixel)[1]);
              value += (((float*)pixel)[2] - ((float*)basePixel)[2]) * (((float*)pixel)[2] - ((float*)basePixel)[2]);
              value += (((float*)pixel)[3] - ((float*)basePixel)[3]) * (((float*)pixel)[3] - ((float*)basePixel)[3]);
              value = MAX(MIN(sqrtf(value), 1.0), 0.0);
              result += value;
              
              if (value >= kEpsilon) {
                count += 1.0;
              }
              
              if (provider) {
                if (value > max) {
                  max = value;
                }
                *diff++ = (value < 0.0 ? 0 : (value > 1.0 ? 255 : (unsigned char)(value * 255.0)));
              }
              
              basePixel += 16;
              pixel += 16;
            }
          }
        }
      }
      
      if (count > 0.0) {
        result = 1.0 - ((result / count) * powf((count / ((CGFloat)width * (CGFloat)height)), 2.0));
      } else {
        result = 1.0;
      }
      
      if (provider) {
        if (normalizeDifferenceImage && (max < 1.0)) {
          unsigned char* diff = (unsigned char*)diffBuffer;
          for (size_t x = 0; x < height * width; ++x, ++diff) {
            *diff = (CGFloat)*diff / max;
          }
        }
        
        colorspace = CGColorSpaceCreateDeviceGray();
        *differenceImage = CGImageCreate(width, height, 8, 8, width, colorspace, 0, provider, NULL, false, kCGRenderingIntentDefault);
        CGColorSpaceRelease(colorspace);
        
        CGDataProviderRelease(provider);
      }
    }
    
    if (baseContext) {
      CGContextRelease(baseContext);
    }
    if (context) {
      CGContextRelease(context);
    }
    if (baseBuffer) {
      free(baseBuffer);
    }
    if (buffer) {
      free(buffer);
    }
  }
  return result;
}

CGImageRef CreateRenderedPDFPage(CGPDFPageRef page, CGSize size, ImageScalingMode scaling, CGColorRef backgroundColor) {
  CGRect rect = CGPDFPageGetBoxRect(page, kCGPDFMediaBox);
  size_t contextWidth;
  size_t contextHeight;
  CGAffineTransform transform;
  if ((size.width > 0.0) && (size.height > 0.0)) {
    switch (scaling) {
      
      case kImageScalingMode_Resize: {
        contextWidth = size.width;
        contextHeight = size.height;
        transform = CGAffineTransformMakeScale(size.width / rect.size.width, size.height / rect.size.height);
        break;
      }
      
      case kImageScalingMode_AspectFill: {
        contextWidth = size.width;
        contextHeight = size.height;
        if (rect.size.width / size.width >= rect.size.height / size.height) {
          CGFloat width = size.height * rect.size.width / rect.size.height;
          transform = CGAffineTransformTranslate(CGAffineTransformMakeScale(width / rect.size.width, size.height / rect.size.height),
                                                 (size.width - width) / 2.0, 0.0);
        } else {
          CGFloat height = size.width * rect.size.height / rect.size.width;
          transform = CGAffineTransformTranslate(CGAffineTransformMakeScale(size.width / rect.size.width, height / rect.size.height),
                                                 0.0, (size.height - height) / 2.0);
        }
        break;
      }
      
      case kImageScalingMode_AspectFit: {
        if (rect.size.width / size.width >= rect.size.height / size.height) {
          CGFloat height = rect.size.height / (rect.size.width / size.width);
          contextWidth = size.width;
          contextHeight = height;
          transform = CGAffineTransformMakeScale(size.width / rect.size.width, height / rect.size.height);
        } else {
          CGFloat width = rect.size.width / (rect.size.height / size.height);
          contextWidth = width;
          contextHeight = size.height;
          transform = CGAffineTransformMakeScale(width / rect.size.width, size.height / rect.size.height);
        }
        break;
      }
      
    }
  } else {
    contextWidth = rect.size.width;
    contextHeight = rect.size.height;
    transform = CGAffineTransformIdentity;
  }
  CGColorSpaceRef colorspace = CGColorSpaceCreateDeviceRGB();
  CGContextRef context = CGBitmapContextCreate(NULL, contextWidth, contextHeight, 8, 0, colorspace,
                                               kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host);
  if (backgroundColor) {
    CGContextSetFillColorWithColor(context, backgroundColor);
    CGContextFillRect(context, CGRectMake(0, 0, contextWidth, contextHeight));
  }
  CGContextConcatCTM(context, transform);
  CGContextTranslateCTM(context, -rect.origin.x, -rect.origin.y);
  CGContextDrawPDFPage(context, page);
  CGImageRef imageRef = CGBitmapContextCreateImage(context);
  CGContextRelease(context);
  CGColorSpaceRelease(colorspace);
  return imageRef;
}

static void __DrawPattern(void* info, CGContextRef context) {
#if TARGET_OS_IPHONE
  BOOL shouldFlip = kCFCoreFoundationVersionNumber < kCFCoreFoundationVersionNumber_iOS_4_0;
  if (shouldFlip) {
    CGContextSaveGState(context);
    CGContextTranslateCTM(context, 0.0, CGImageGetHeight(info));
    CGContextScaleCTM(context, 1.0, -1.0);
  }
#endif
  CGContextDrawImage(context, CGRectMake(0, 0, CGImageGetWidth(info), CGImageGetHeight(info)), info);
#if TARGET_OS_IPHONE
  if (shouldFlip) {
    CGContextRestoreGState(context);
  }
#endif
}

static void __ReleasePattern(void* info) {
  CGImageRelease(info);
}

CGColorRef CreateImagePatternColor(CGImageRef image) {
  size_t width = CGImageGetWidth(image);
  size_t height = CGImageGetHeight(image);
  CGPatternCallbacks callbacks = {0, __DrawPattern, __ReleasePattern};
  CGPatternRef pattern = CGPatternCreate(CGImageRetain(image), CGRectMake(0.0, 0.0, width, height), CGAffineTransformIdentity,
                                         width, height, kCGPatternTilingConstantSpacing, true, &callbacks);
  CGColorSpaceRef colorSpace = CGColorSpaceCreatePattern(NULL);
  CGFloat components[] = {1.0};
  CGColorRef color = CGColorCreateWithPattern(colorSpace, pattern, components);
  CGColorSpaceRelease(colorSpace);
  CGPatternRelease(pattern);
  return color;
}
