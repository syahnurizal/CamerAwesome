//
//  CameraPicture.m
//  camerawesome
//
//  Created by Dimitri Dessus on 24/07/2020.
//

#import "CameraPictureController.h"
#import "ExifContainer.h"
#import "NSData+Exif.h"

@implementation CameraPictureController {
  CameraPictureController *selfReference;
}

- (instancetype)initWithPath:(NSString *)path
                     orientation:(NSInteger)orientation
                  sensorPosition:(PigeonSensorPosition)sensorPosition
                 saveGPSLocation:(bool)saveGPSLocation
               mirrorFrontCamera:(bool)mirrorFrontCamera
                     aspectRatio:(AspectRatio)aspectRatio
                      completion:(nonnull void (^)(NSNumber * _Nullable, FlutterError * _Nullable))completion
                        callback:(OnPictureTaken)callback {
  self = [super init];
  NSAssert(self, @"super init cannot be nil");
  _path = path;
  _completion = completion;
  _orientation = orientation;
  _completionBlock = callback;
  _sensorPosition = sensorPosition;
  _saveGPSLocation = saveGPSLocation;
  _aspectRatioType = aspectRatio;
  _mirrorFrontCamera = mirrorFrontCamera;
  
  if (aspectRatio == Ratio4_3) {
    _aspectRatio = 4.0/3.0;
  } else if(aspectRatio == Ratio16_9) {
    _aspectRatio = 16.0/9.0;
  } else {
    _aspectRatio = 1;
  }
  
  selfReference = self;
  return self;
}

- (NSData *)writeMetadataIntoImageData:(NSData *)imageData metadata:(NSMutableDictionary *)metadata {
  // create an imagesourceref
  CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef) imageData, NULL);
  
  // this is the type of image (e.g., public.jpeg)
  CFStringRef UTI = CGImageSourceGetType(source);
  
  // create a new data object and write the new image into it
  NSMutableData *dest_data = [NSMutableData data];
  CGImageDestinationRef destination = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)dest_data, UTI, 1, NULL);
  if (!destination) {
    NSLog(@"Error: Could not create image destination");
  }
  // add the image contained in the image source to the destination, overidding the old metadata with our modified metadata
  CGImageDestinationAddImageFromSource(destination, source, 0, (__bridge CFDictionaryRef) metadata);
  BOOL success = NO;
  success = CGImageDestinationFinalize(destination);
  if (!success) {
    NSLog(@"Error: Could not create data from image destination");
  }
  CFRelease(destination);
  CFRelease(source);
  return dest_data;
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-implementations"
- (void)captureOutput:(AVCapturePhotoOutput *)output
didFinishProcessingPhotoSampleBuffer:(CMSampleBufferRef)photoSampleBuffer
previewPhotoSampleBuffer:(CMSampleBufferRef)previewPhotoSampleBuffer
     resolvedSettings:(AVCaptureResolvedPhotoSettings *)resolvedSettings
      bracketSettings:(AVCaptureBracketedStillImageSettings *)bracketSettings
                error:(NSError *)error {
#pragma clang diagnostic pop
  
  selfReference = nil;
  if (error) {
    _completion(nil, [FlutterError errorWithCode:@"CAPTURE ERROR" message:error.description details:@""]);
    return;
  }
  
  // Add exif data
  ExifContainer *container = [[ExifContainer alloc] init];
  [container addCreationDate:[NSDate date]];
  
  // Save GPS location only if provided
  if (_saveGPSLocation) {
    CLLocationManager *locationManager = [CLLocationManager new];
    CLLocation *location = [locationManager location];
    [container addLocation:location];
  }
  
  // we ignore this error because plugin can only be installed on iOS 11+
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  NSData *data = [AVCapturePhotoOutput JPEGPhotoDataRepresentationForJPEGSampleBuffer:photoSampleBuffer
                                                             previewPhotoSampleBuffer:previewPhotoSampleBuffer];
#pragma clang diagnostic pop
  
  UIImage *image = [UIImage imageWithCGImage:[UIImage imageWithData:data].CGImage
                                       scale:1.0
                                 orientation:[self getJpegOrientation]];
  float originalWidth = image.size.width;
  float originalHeight = image.size.height;
  
  float originalImageAspectRatio = originalWidth / originalHeight;
  
  float outputWidth = originalWidth;
  float outputHeight = originalHeight;
  if (originalImageAspectRatio != _aspectRatio) {
    if (originalImageAspectRatio > _aspectRatio) {
      outputWidth = originalHeight * _aspectRatio;
    } else if (originalImageAspectRatio < _aspectRatio) {
      outputHeight = originalWidth / _aspectRatio;
    }
  }
  
  UIImage *imageConverted = [self imageByCroppingImage:image toSize:CGSizeMake(outputWidth, outputHeight)];
  
  image = [UIImage imageWithCGImage:[imageConverted CGImage] scale:0.0 orientation:[self getJpegOrientation]];

  NSData *imageWithExif = [UIImageJPEGRepresentation(image, 1.0) addExif:container];
  
  bool success = [imageWithExif writeToFile:_path atomically:YES];
  if (!success) {
    _completion(nil, [FlutterError errorWithCode:@"IOError" message:@"unable to write file" details:nil]);
    return;
  }
  _completionBlock();
  
}

- (UIImage *)imageByCroppingImage:(UIImage *)image toSize:(CGSize)size {
  // Center-crop the RAW sensor buffer to the configured aspect ratio.
  //
  // The original code mixed two coordinate spaces: it derived the crop rect from
  // `image.size` (orientation-adjusted — axes swapped for portrait) but applied
  // it to `[image CGImage]` (the raw, un-rotated pixel buffer). That offset the
  // captured frame versus the preview (the preview is a Flutter texture of the
  // full video buffer, shown with CameraPreviewFit.contain = full frame visible).
  // Operating purely on raw pixels keeps capture aligned with preview.
  // For 4:3 (the sensor's native ratio on iPhone) this is a no-op.
  CGImageRef sourceRef = [image CGImage];
  double rawWidth  = (double)CGImageGetWidth(sourceRef);
  double rawHeight = (double)CGImageGetHeight(sourceRef);

  // _aspectRatio is long-side / short-side (e.g. 4/3, 16/9, 1).
  double targetAspect  = (_aspectRatio > 0) ? _aspectRatio : (rawWidth / rawHeight);
  double currentAspect = rawWidth / rawHeight;

  double cropWidth  = rawWidth;
  double cropHeight = rawHeight;
  if (currentAspect > targetAspect) {
    // Buffer wider than target: trim width, keep full height.
    cropWidth = rawHeight * targetAspect;
  } else if (currentAspect < targetAspect) {
    // Buffer taller than target: trim height, keep full width.
    cropHeight = rawWidth / targetAspect;
  }

  CGRect cropRect = CGRectMake(
    round((rawWidth  - cropWidth)  / 2.0),
    round((rawHeight - cropHeight) / 2.0),
    round(cropWidth),
    round(cropHeight)
  );

  CGImageRef imageRef = CGImageCreateWithImageInRect(sourceRef, cropRect);
  UIImage *cropped = [UIImage imageWithCGImage:imageRef];
  CGImageRelease(imageRef);

  return cropped;
}

// Helper #1: map a “known” UIDeviceOrientation → UIImageOrientation
- (UIImageOrientation)imageOrientationFromDeviceOrientation:(UIDeviceOrientation)devOrient {
    switch (devOrient) {
        case UIDeviceOrientationPortrait:
            return (self.sensorPosition == PigeonSensorPositionFront && _mirrorFrontCamera)
                ? UIImageOrientationLeftMirrored
                : UIImageOrientationRight;
        case UIDeviceOrientationPortraitUpsideDown:
            return UIImageOrientationLeft;
        case UIDeviceOrientationLandscapeLeft:
            return (self.sensorPosition == PigeonSensorPositionBack)
                ? UIImageOrientationDown
                : UIImageOrientationUp;
        case UIDeviceOrientationLandscapeRight:
            return (self.sensorPosition == PigeonSensorPositionBack)
                ? UIImageOrientationUp
                : UIImageOrientationDown;
        default:
            return UIImageOrientationUp;
    }
}

// Helper #2: map a UIInterfaceOrientation → UIImageOrientation
- (UIImageOrientation)imageOrientationFromInterfaceOrientation:(UIInterfaceOrientation)uiOrient {
    switch (uiOrient) {
        case UIInterfaceOrientationPortrait:
            return (self.sensorPosition == PigeonSensorPositionFront && _mirrorFrontCamera)
                ? UIImageOrientationLeftMirrored
                : UIImageOrientationRight;
        case UIInterfaceOrientationPortraitUpsideDown:
            return UIImageOrientationLeft;
        case UIInterfaceOrientationLandscapeLeft:
            return (self.sensorPosition == PigeonSensorPositionBack)
                ? UIImageOrientationDown
                : UIImageOrientationUp;
        case UIInterfaceOrientationLandscapeRight:
            return (self.sensorPosition == PigeonSensorPositionBack)
                ? UIImageOrientationUp
                : UIImageOrientationDown;
        default:
            return UIImageOrientationUp;
    }
}

- (UIImageOrientation)getJpegOrientation {
    UIDeviceOrientation devOrient = _orientation;
    // Check if _orientation is one of the ones we handle directly
    if (devOrient != UIDeviceOrientationUnknown) {
        return [self imageOrientationFromDeviceOrientation:devOrient];
    }

    // Fallback: pull the UI orientation
    UIInterfaceOrientation uiOrient;
    if (@available(iOS 13.0, *)) {
        uiOrient = UIApplication.sharedApplication
                        .windows.firstObject.windowScene.interfaceOrientation;
    } else {
        uiOrient = UIApplication.sharedApplication.statusBarOrientation;
    }
    return [self imageOrientationFromInterfaceOrientation:uiOrient];
}

@end
