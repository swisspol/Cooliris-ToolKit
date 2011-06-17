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
#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>
#import <CoreLocation/CoreLocation.h>

#import "CameraViewController.h"
#import "Logging.h"

// Rotations are clockwise
typedef enum {
  kEXIFOrientation_Normal = 1,  // UIImageOrientationUp (0)
  kEXIFOrientation_FlipHorizontally = 2,  // UIImageOrientationUpMirrored (4) - Mirror along vertical axis
  kEXIFOrientation_Rotate180 = 3,  // UIImageOrientationDown (1)
  kEXIFOrientation_FlipVertically = 4,  // UIImageOrientationDownMirrored (5) - Mirror along horizontal axis
  kEXIFOrientation_Rotate270FlipHorizontally = 5,  // UIImageOrientationRightMirrored (7)
  kEXIFOrientation_Rotate270 = 6,  // UIImageOrientationRight (3) - Rotate 90 degrees counter-clockwise
  kEXIFOrientation_Rotate90FlipHorizontally = 7,  // UIImageOrientationLeftMirrored (6)
  kEXIFOrientation_Rotate90 = 8  // UIImageOrientationLeft (2) - Rotate 90 degrees clockwise
} EXIFOrientation;

@interface CameraView : UIView {
@private
  BOOL _square;
  UIView* _previewView;
  AVCaptureVideoPreviewLayer* _previewLayer;
  UIInterfaceOrientation _orientation;
}
- (id) initWithCaptureSession:(AVCaptureSession*)session square:(BOOL)square;
- (void) updateInterfaceOrientation:(UIInterfaceOrientation)orientation;
@end

@implementation CameraView

- (id) initWithCaptureSession:(AVCaptureSession*)session square:(BOOL)square {
  if ((self = [super initWithFrame:CGRectZero])) {
    _square = square;
    
    _previewView = [[UIView alloc] init];
    [self addSubview:_previewView];
    
    _previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:session];
    _previewLayer.videoGravity = _square ? AVLayerVideoGravityResizeAspectFill : AVLayerVideoGravityResizeAspect;
    [_previewView.layer addSublayer:_previewLayer];
    
    _orientation = UIInterfaceOrientationPortrait;
    
    self.autoresizesSubviews = NO;
  }
  return self;
}

- (void) dealloc {
  [_previewLayer removeFromSuperlayer];
  [_previewLayer release];
  [_previewView removeFromSuperview];
  [_previewView release];
  
  [super dealloc];
}

- (void) layoutSubviews {
  CGRect bounds = self.bounds;
  _previewView.center = CGPointMake(bounds.size.width / 2.0, bounds.size.height / 2.0);
  if (_square) {
    CGFloat size = MIN(bounds.size.width, bounds.size.height);
    _previewView.bounds = CGRectMake(0, 0, size, size);
  } else {
    if (UIInterfaceOrientationIsLandscape(_orientation)) {
      _previewView.bounds = CGRectMake(0, 0, bounds.size.height, bounds.size.width);
    } else {
      _previewView.bounds = CGRectMake(0, 0, bounds.size.width, bounds.size.height);
    }
  }
  if (_orientation == UIInterfaceOrientationPortrait) {
    _previewView.transform = CGAffineTransformIdentity;
  } else if (_orientation == UIInterfaceOrientationPortraitUpsideDown) {
    _previewView.transform = CGAffineTransformMakeRotation(M_PI);
  } else if (_orientation == UIInterfaceOrientationLandscapeRight) {
    _previewView.transform = CGAffineTransformMakeRotation(M_PI * 1.5);
  } else if (_orientation == UIInterfaceOrientationLandscapeLeft) {
    _previewView.transform = CGAffineTransformMakeRotation(M_PI / 2.0);
  }
  
  _previewLayer.frame = _previewView.bounds;
}

- (void) updateInterfaceOrientation:(UIInterfaceOrientation)orientation {
  _orientation = orientation;
  [self layoutSubviews];
}

@end

@implementation CameraViewController

@synthesize delegate=_delegate, lowResolution=_lowResolution, photoSize=_photoSize, squarePhotos=_squarePhotos,
            overlayView=_overlayView, active=_active, exifLocation=_exifLocation, exifDate=_exifDate, exifMake=_exifMake,
            exifModel=_exifModel, exifSoftware=_exifSoftware, exifCopyright=_exifCopyright;

+ (BOOL) isCameraAvailable {
  return [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo] ? YES : NO;
}

- (void) dealloc {
  [_overlayView release];
  [_exifLocation release];
  [_exifDate release];
  [_exifMake release];
  [_exifModel release];
  [_exifSoftware release];
  [_exifCopyright release];
  
  [super dealloc];
}

- (void) viewDidLoad {
  [super viewDidLoad];
  
  self.view.backgroundColor = [UIColor blackColor];
}

- (BOOL) shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation {
  return YES;
}

- (void) willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration {
  [super willAnimateRotationToInterfaceOrientation:toInterfaceOrientation duration:duration];
  
  [_cameraView updateInterfaceOrientation:toInterfaceOrientation];
}

- (void) viewWillAppear:(BOOL)animated {
  [super viewWillAppear:animated];
  
  _captureSession = [[AVCaptureSession alloc] init];
  _captureSession.sessionPreset = _lowResolution ? AVCaptureSessionPreset640x480 : AVCaptureSessionPresetPhoto;
  
  NSError* error = nil;
  AVCaptureDevice* device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
#if 0
  if (device.hasFlash && [device isFlashModeSupported:AVCaptureFlashModeAuto]) {
    device.flashMode = AVCaptureFlashModeAuto;
  }
#endif
  AVCaptureDeviceInput* input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
  if (input) {
    [_captureSession addInput:input];
  } else {
    LOG_ERROR(@"Failed retrieving capture device input: %@", error);
  }
  
  _stillImageOutput = [[AVCaptureStillImageOutput alloc] init];
  if (_photoSize > 0) {
    _stillImageOutput.outputSettings = [NSDictionary dictionaryWithObject:[NSNumber numberWithInt:kCVPixelFormatType_32BGRA]
                                                                   forKey:(id)kCVPixelBufferPixelFormatTypeKey];
  } else {
    _stillImageOutput.outputSettings = [NSDictionary dictionaryWithObject:AVVideoCodecJPEG forKey:AVVideoCodecKey];
  }
  [_captureSession addOutput:_stillImageOutput];
  
  _connection = nil;
  for (AVCaptureConnection* connection in _stillImageOutput.connections) {
    for (AVCaptureInputPort* port in connection.inputPorts) {
      if ([port.mediaType isEqual:AVMediaTypeVideo]) {
        _connection = connection;
        break;
      }
    }
    if (_connection) {
      break;
    }
  }
  if (_connection == nil) {
    LOG_ERROR(@"Failed retrieving capture connection");
  }
  
  if (input && _connection) {
    _cameraView = [[CameraView alloc] initWithCaptureSession:_captureSession square:_squarePhotos];
    _cameraView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _cameraView.frame = self.view.bounds;
    [_cameraView updateInterfaceOrientation:self.interfaceOrientation];
    [self.view addSubview:_cameraView];
    
    [_captureSession addObserver:self forKeyPath:@"running" options:0 context:[CameraViewController class]];
    [_captureSession startRunning];
  }
  
  if (_overlayView) {
    _overlayView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _overlayView.frame = self.view.bounds;
    [self.view addSubview:_overlayView];
  }
}

- (void) observeValueForKeyPath:(NSString*)keyPath ofObject:(id)object change:(NSDictionary*)change context:(void*)context {
  if (context == [CameraViewController class]) {
    _active = _captureSession.running;
    LOG_VERBOSE(@"AVCaptureSession running state changed to %i", _active);
  } else {
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
  }
}

- (void) viewDidDisappear:(BOOL)animated {
  [super viewDidDisappear:animated];
  
  [_captureSession stopRunning];
  [_captureSession removeObserver:self forKeyPath:@"running"];
  
  [_overlayView removeFromSuperview];
  
  [_cameraView removeFromSuperview];
  [_cameraView release];
  _cameraView = nil;
  
  [_stillImageOutput release];
  _stillImageOutput = nil;
  [_captureSession release];
  _captureSession = nil;
}

- (BOOL) isTakingPhoto {
  return (_takingPhoto > 0);
}

- (void) _didTakePhoto:(id)result {
  _takingPhoto -= 1;
  
  if ([result isKindOfClass:[NSData class]]) {
    if ([_delegate respondsToSelector:@selector(cameraViewController:didTakePhotoWithJPEGData:)]) {
      [_delegate cameraViewController:self didTakePhotoWithJPEGData:result];
    }
  } else if ([result isKindOfClass:[NSArray class]]) {
    if ([_delegate respondsToSelector:@selector(cameraViewController:didTakePhotoWithUIImage:metadata:)]) {
      [_delegate cameraViewController:self didTakePhotoWithUIImage:[result objectAtIndex:0] metadata:[result objectAtIndex:1]];
    }
  } else {
    if ([_delegate respondsToSelector:@selector(cameraViewController:didFailTakingPhotoWithError:)]) {
      [_delegate cameraViewController:self didFailTakingPhotoWithError:result];
    }
  }
}

- (void) takePhoto {
  DCHECK(_active);
  _takingPhoto += 1;
  
  EXIFOrientation orientation;
  switch ([[UIDevice currentDevice] orientation]) {
    
    case UIDeviceOrientationPortrait:
      orientation = kEXIFOrientation_Rotate270;
      break;
    
    case UIDeviceOrientationPortraitUpsideDown:
      orientation = kEXIFOrientation_Rotate90;
      break;
    
    case UIDeviceOrientationLandscapeLeft:
      orientation = kEXIFOrientation_Normal;
      break;
    
    case UIDeviceOrientationLandscapeRight:
      orientation = kEXIFOrientation_Rotate180;
      break;
    
    default:
      orientation = kEXIFOrientation_Rotate270;
      break;
    
  }
  
  CLLocation* gpsLocation = [_exifLocation retain];
  
  NSMutableDictionary* tiffDictionary = [[NSMutableDictionary alloc] init];
  [tiffDictionary setObject:(_exifMake ? _exifMake : @"Apple") forKey:(id)kCGImagePropertyTIFFMake];
  [tiffDictionary setObject:(_exifModel ? _exifModel : [[UIDevice currentDevice] model]) forKey:(id)kCGImagePropertyTIFFModel];
  [tiffDictionary setObject:(_exifSoftware ? _exifSoftware : [[UIDevice currentDevice] systemVersion]) forKey:(id)kCGImagePropertyTIFFSoftware];
  [tiffDictionary setValue:_exifCopyright forKey:(id)kCGImagePropertyTIFFCopyright];
  NSDateFormatter* formatter = [[NSDateFormatter alloc] init];
  [formatter setDateFormat:@"yyyy:MM:dd' 'HH:mm:ss"];
  [tiffDictionary setObject:[formatter stringFromDate:(_exifDate ? _exifDate : [NSDate date])] forKey:(id)kCGImagePropertyTIFFDateTime];
  [formatter release];
  
  [_stillImageOutput captureStillImageAsynchronouslyFromConnection:_connection
                                                 completionHandler:^(CMSampleBufferRef imageDataSampleBuffer, NSError* error) {
    id result = nil;
    
    // Process sample buffer
    if (imageDataSampleBuffer) {
      // Override EXIF orientation
      CMSetAttachment(imageDataSampleBuffer, kCGImagePropertyOrientation,
                      [NSNumber numberWithInt:(_photoSize > 0 ? kEXIFOrientation_Normal : orientation)],
                      kCMAttachmentMode_ShouldPropagate);
      
      // Add TIFF info
      CMSetAttachment(imageDataSampleBuffer, kCGImagePropertyTIFFDictionary, tiffDictionary, kCMAttachmentMode_ShouldPropagate);
      
      // Add GPS info if necessary
      if (gpsLocation) {
        NSMutableDictionary* dictionary = [[NSMutableDictionary alloc] init];
        [dictionary setObject:@"2.2.0.0" forKey:(id)kCGImagePropertyGPSVersion];
        NSDateFormatter* formatter = [[NSDateFormatter alloc] init];
        [formatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
        [formatter setDateFormat:@"HH:mm:ss.SSSSSS"];
        [dictionary setObject:[formatter stringFromDate:gpsLocation.timestamp] forKey:(id)kCGImagePropertyGPSTimeStamp];
        [formatter setDateFormat:@"yyyy:MM:dd"];
        [dictionary setObject:[formatter stringFromDate:gpsLocation.timestamp] forKey:(id)kCGImagePropertyGPSDateStamp];
        [formatter release];
        CLLocationDegrees latitude = gpsLocation.coordinate.latitude;
        if (latitude < 0.0) {
          latitude = -latitude;
          [dictionary setObject:@"S" forKey:(id)kCGImagePropertyGPSLatitudeRef];
        } else {
          [dictionary setObject:@"N" forKey:(id)kCGImagePropertyGPSLatitudeRef];
        }
        [dictionary setObject:[NSNumber numberWithDouble:latitude] forKey:(id)kCGImagePropertyGPSLatitude];
        CLLocationDegrees longitude = gpsLocation.coordinate.longitude;
        if (longitude < 0) {
          longitude = -longitude;
          [dictionary setObject:@"W" forKey:(id)kCGImagePropertyGPSLongitudeRef];
        } else {
          [dictionary setObject:@"E" forKey:(id)kCGImagePropertyGPSLongitudeRef];
        }
        [dictionary setObject:[NSNumber numberWithDouble:longitude] forKey:(id)kCGImagePropertyGPSLongitude];
        CLLocationDistance altitude = gpsLocation.altitude;
        if (!isnan(altitude)){
          if (altitude < 0) {
            altitude = -altitude;
            [dictionary setObject:@"1" forKey:(id)kCGImagePropertyGPSAltitudeRef];
          } else {
            [dictionary setObject:@"0" forKey:(id)kCGImagePropertyGPSAltitudeRef];
          }
          [dictionary setObject:[NSNumber numberWithDouble:altitude] forKey:(id)kCGImagePropertyGPSAltitude];
        }
        CMSetAttachment(imageDataSampleBuffer, kCGImagePropertyGPSDictionary, dictionary, kCMAttachmentMode_ShouldPropagate);
        [dictionary release];
      }
      
      // Generate photo
      if (_photoSize > 0) {
        CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(imageDataSampleBuffer);
        if (imageBuffer && (CVPixelBufferLockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly) == kCVReturnSuccess)) {
          size_t width = CVPixelBufferGetWidth(imageBuffer);
          size_t height = CVPixelBufferGetHeight(imageBuffer);
          void* bytes = CVPixelBufferGetBaseAddress(imageBuffer);
          size_t length = CVPixelBufferGetDataSize(imageBuffer);
          size_t rowBytes = CVPixelBufferGetBytesPerRow(imageBuffer);
          CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, bytes, length, NULL);
          CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
          CGImageRef image = CGImageCreate(width, height, 8, 32, rowBytes, colorSpace, kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Host,
                                           provider, NULL, true, kCGRenderingIntentDefault);
          if (image) {
            size_t imageWidth = CGImageGetWidth(image);
            size_t imageHeight = CGImageGetHeight(image);
            if ((imageWidth > _photoSize) || (imageHeight > _photoSize)) {
              if (_squarePhotos) {
                if ((CGFloat)imageWidth / (CGFloat)_photoSize >= (CGFloat)imageHeight / (CGFloat)_photoSize) {
                  imageWidth = roundf((CGFloat)imageWidth / ((CGFloat)imageHeight / (CGFloat)_photoSize));
                  imageHeight = _photoSize;
                } else {
                  imageHeight = roundf((CGFloat)imageHeight / ((CGFloat)imageWidth / (CGFloat)_photoSize));
                  imageWidth = _photoSize;
                }
              } else {
                if ((CGFloat)imageWidth / (CGFloat)_photoSize >= (CGFloat)imageHeight / (CGFloat)_photoSize) {
                  imageHeight = roundf((CGFloat)imageHeight / ((CGFloat)imageWidth / (CGFloat)_photoSize));
                  imageWidth = _photoSize;
                } else {
                  imageWidth = roundf((CGFloat)imageWidth / ((CGFloat)imageHeight / (CGFloat)_photoSize));
                  imageHeight = _photoSize;
                }
              }
            }
            CGAffineTransform transform;
            switch (orientation) {
              
              case kEXIFOrientation_Normal:
                transform = CGAffineTransformIdentity;
                break;
              
              case kEXIFOrientation_Rotate180:
                transform = CGAffineTransformMakeTranslation(imageWidth, imageHeight);
                transform = CGAffineTransformRotate(transform, M_PI);
                break;
              
              case kEXIFOrientation_Rotate270:
                transform = CGAffineTransformMakeTranslation(0.0, imageWidth);
                transform = CGAffineTransformRotate(transform, 3.0 * M_PI / 2.0);
                break;
              
              case kEXIFOrientation_Rotate90:
                transform = CGAffineTransformMakeTranslation(imageHeight, 0.0);
                transform = CGAffineTransformRotate(transform, M_PI / 2.0);
                break;
              
              default:
                break;
              
            }
            size_t contextWidth = orientation >= 5 ? imageHeight : imageWidth;
            size_t contextHeight = orientation >= 5 ? imageWidth : imageHeight;
            CGFloat xOffset = 0.0;
            CGFloat yOffset = 0.0;
            if (_squarePhotos) {
              if (contextWidth > contextHeight) {
                xOffset = roundf(((CGFloat)contextHeight - (CGFloat)contextWidth) / 2.0);
                contextWidth = contextHeight;
              } else {
                yOffset = roundf(((CGFloat)contextWidth - (CGFloat)contextHeight) / 2.0);
                contextHeight = contextWidth;
              }
            }
            CGContextRef context = CGBitmapContextCreate(NULL, contextWidth, contextHeight, 8, 0, colorSpace,
                                                         kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Host);
            if (context) {
              CGContextSetBlendMode(context, kCGBlendModeCopy);
              if (xOffset || yOffset) {
                CGContextTranslateCTM(context, xOffset, yOffset);
              }
              CGContextConcatCTM(context, transform);
              CGContextDrawImage(context, CGRectMake(0, 0, imageWidth, imageHeight), image);
              CGImageRef imageRef = CGBitmapContextCreateImage(context);
              if (imageRef) {
                CFDictionaryRef dictionary = CMCopyDictionaryOfAttachments(kCFAllocatorDefault, imageDataSampleBuffer,
                                                                           kCMAttachmentMode_ShouldPropagate);
                result = [NSArray arrayWithObjects:[UIImage imageWithCGImage:imageRef], (id)dictionary, nil];
                if (dictionary) {
                  CFRelease(dictionary);
                }
                CGImageRelease(imageRef);
              }
              CGContextRelease(context);
            }
            CGImageRelease(image);
          }
          CGColorSpaceRelease(colorSpace);
          CGDataProviderRelease(provider);
          CVPixelBufferUnlockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly);
        }
      } else {
        result = [AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:imageDataSampleBuffer];
        DCHECK(result);
      }
    } else {
      result = error;
    }
    
    // Call delegate on main thread
    if ([NSThread isMainThread]) {
      [self _didTakePhoto:result];
    } else {
      [self performSelectorOnMainThread:@selector(_didTakePhoto:) withObject:result waitUntilDone:NO];
    }
    
    [tiffDictionary release];
    [gpsLocation release];
  }];
}

@end
