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

typedef enum {
  kCameraViewControllerResolution_Native = 0,
  kCameraViewControllerResolution_640x480
} CameraViewControllerResolution;

@class CameraViewController, CameraView, AVCaptureSession, AVCaptureStillImageOutput, AVCaptureConnection, CLLocation;

@protocol CameraViewControllerDelegate <NSObject>
@optional
- (void) cameraViewController:(CameraViewController*)controller didTakePhotoWithJPEGData:(NSData*)jpegData;
- (void) cameraViewController:(CameraViewController*)controller didTakePhotoWithUIImage:(UIImage*)image metadata:(NSDictionary*)metadata;
- (void) cameraViewController:(CameraViewController*)controller didFailTakingPhotoWithError:(NSError*)error;
@end

// The controller becomes automatically active when presented on screen
// If both front and back cameras are available, the back one will be used
// Use the "overlayView" property to add a custom UI
@interface CameraViewController : UIViewController {
@private
  id<CameraViewControllerDelegate> _delegate;
  BOOL _lowResolution;
  NSUInteger _photoSize;
  BOOL _squarePhotos;
  UIView* _overlayView;
  BOOL _active;
  CLLocation* _exifLocation;
  NSDate* _exifDate;
  NSString* _exifMake;
  NSString* _exifModel;
  NSString* _exifSoftware;
  
  AVCaptureSession* _captureSession;
  AVCaptureStillImageOutput* _stillImageOutput;
  AVCaptureConnection* _connection;
  CameraView* _cameraView;
  NSUInteger _takingPhoto;
}
+ (BOOL) isCameraAvailable;
@property(nonatomic, assign) id<CameraViewControllerDelegate> delegate;
@property(nonatomic, getter=isLowResolution) BOOL lowResolution;  // Use camera in 640x480 mode instead of full-resolution - Must be set before the controller becomes active
@property(nonatomic) NSUInteger photoSize;  // If non-zero, photos will be orientation-corrected and scaled UIImages instead of raw JPEG data - Must be set before the controller becomes active
@property(nonatomic) BOOL squarePhotos;  // Requires "photoSize" to be non-zero - Must be set before the controller becomes active
@property(nonatomic, retain) UIView* overlayView;  // Automatically reized - Must be set before the controller becomes active
@property(nonatomic, readonly, getter=isActive) BOOL active;
@property(nonatomic, retain) CLLocation* exifLocation;  // If not nil, corresponding GPS information will be inserted into the EXIF metadata
@property(nonatomic, retain) NSDate* exifDate;  // If nil, defaults to current date
@property(nonatomic, copy) NSString* exifMake;  // If nil, defaults to "Apple"
@property(nonatomic, copy) NSString* exifModel;  // If nil defaults to device model e.g. "iPad"
@property(nonatomic, copy) NSString* exifSoftware;  // If nil, defaults to iOS version e.g. "4.3"
@property(nonatomic, copy) NSString* exifCopyright;
@property(nonatomic, readonly, getter=isTakingPhoto) BOOL takingPhoto;
- (void) takePhoto;  // Only call if controller active
@end
