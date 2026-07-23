//
//  CameraQualities.h
//  camerawesome
//
//  Created by Dimitri Dessus on 24/07/2020.
//

#import <AVFoundation/AVFoundation.h>
#import "Pigeon.h"

NS_ASSUME_NONNULL_BEGIN

@interface CameraQualities : NSObject

+ (AVCaptureSessionPreset)selectVideoCapturePreset:(CGSize)size session:(AVCaptureSession *)session device:(AVCaptureDevice *)device;
+ (AVCaptureSessionPreset)selectVideoCapturePreset:(AVCaptureSession *)session device:(AVCaptureDevice *)device;
+ (CGSize)getSizeForPreset:(NSString *)preset;
+ (NSArray *)captureFormatsForDevice:(AVCaptureDevice *)device;

/// Canonical VideoRecordingQuality -> target size table (landscape).
///
/// This is the single source of truth for the quality->size mapping, shared by the
/// preview's session-preset selection and the recorder's output sizing. It is a pure
/// table: device-capability fallbacks (e.g. 4K support) and any clamping to the active
/// capture size are the caller's responsibility.
+ (CGSize)targetSizeForQuality:(VideoRecordingQuality)quality;

@end

NS_ASSUME_NONNULL_END
