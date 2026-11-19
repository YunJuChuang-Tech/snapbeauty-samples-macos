#import <AppKit/AppKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreVideo/CoreVideo.h>
#include "../examples/sample_license.h"
#include <time.h>

static NSArray<NSDictionary *> *LoadMakeupStyles(NSString *assets) {
    NSString *nested = [assets stringByAppendingPathComponent:@"Assets"];
    if ([NSFileManager.defaultManager fileExistsAtPath:nested]) assets = nested;
    NSString *path = [assets stringByAppendingPathComponent:@"sample_makeup/manifest.json"];
    NSData *data = [NSData dataWithContentsOfFile:path];
    id manifest = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    if (![manifest isKindOfClass:NSDictionary.class] ||
        ![manifest[@"schema"] isEqual:@1] || ![manifest[@"styles"] isKindOfClass:NSArray.class]) return @[];

    NSMutableArray<NSDictionary *> *styles = [NSMutableArray array];
    for (id style in manifest[@"styles"]) {
        if (![style isKindOfClass:NSDictionary.class] ||
            ![style[@"name"] isKindOfClass:NSString.class] || ![style[@"name"] length] ||
            ![style[@"key"] isKindOfClass:NSString.class] || ![style[@"key"] length] ||
            ![style[@"filter"] isKindOfClass:NSString.class] ||
            ![style[@"files"] isKindOfClass:NSArray.class] || ![style[@"files"] count]) continue;
        BOOL complete = YES;
        for (id file in style[@"files"]) {
            if (![file isKindOfClass:NSString.class] || ![file hasPrefix:@"makeup/"] ||
                [[file pathComponents] containsObject:@".."] ||
                ![NSFileManager.defaultManager isReadableFileAtPath:[assets stringByAppendingPathComponent:file]]) {
                complete = NO;
                break;
            }
        }
        if (complete) [styles addObject:style];
    }
    return styles;
}

static BOOL ApplyParameters(xm_desktop_engine *engine, NSDictionary *style) {
    float values[XM_PARAM_COUNT] = {0};
    /* Neutral start: zero-filling is not "no effect". These twelve bidirectional face controls are neutral at 0.5;
     * 0 pushes each one to an extreme and visibly reshapes the face. Everything else is neutral at 0. */
    values[XM_PARAM_SHAPE_CHIN_LENGTH] = values[XM_PARAM_SHAPE_FOREHEAD_HEIGHT] = values[XM_PARAM_SHAPE_MOUTH_SIZE] = 0.5f;
    values[XM_PARAM_SHAPE_LIP_FULLNESS] = values[XM_PARAM_SHAPE_EYE_POSITION] = values[XM_PARAM_SHAPE_EYE_DISTANCE] = 0.5f;
    values[XM_PARAM_SHAPE_EYE_TILT] = values[XM_PARAM_SHAPE_NOSE_LENGTH] = values[XM_PARAM_SHAPE_PHILTRUM_LENGTH] = 0.5f;
    values[XM_PARAM_SHAPE_BROW_POSITION] = values[XM_PARAM_SHAPE_BROW_DISTANCE] = values[XM_PARAM_SHAPE_BROW_THICKNESS] = 0.5f;
    values[XM_PARAM_SMOOTHING] = 4.2f;
    values[XM_PARAM_BRIGHTENING] = 0.3f;
    float intensity = style ? 0.4f : 0.0f;
    values[XM_PARAM_MAKEUP_INTENSITY] = intensity;
    values[XM_PARAM_FILTER_INTENSITY] = intensity;
    xm_params params = {sizeof(params), values, XM_PARAM_COUNT,
                       [style[@"key"] UTF8String], [style[@"filter"] UTF8String]};
    if (xm_desktop_engine_set_params(engine, &params) == XM_OK) return YES;
    NSLog(@"SnapBeauty parameters: %s", xm_desktop_last_error(engine));
    return NO;
}

@interface CameraPreview : NSObject <NSApplicationDelegate, AVCaptureVideoDataOutputSampleBufferDelegate>
@end

@implementation CameraPreview {
    NSWindow *_window;
    NSImageView *_preview;
    NSTextField *_status;
    NSPopUpButton *_makeupPicker;
    AVCaptureSession *_session;
    dispatch_queue_t _captureQueue;
    dispatch_semaphore_t _presentationSlot;
    xm_desktop_engine *_engine;
    BOOL _engineReady;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    _captureQueue = dispatch_queue_create("ai.snapbeauty.samples.camera", DISPATCH_QUEUE_SERIAL);
    _presentationSlot = dispatch_semaphore_create(1);
    _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 800, 500)
                                          styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                    NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable
                                            backing:NSBackingStoreBuffered defer:NO];
    _window.title = @"SnapBeauty macOS Samples";
    _window.minSize = NSMakeSize(420, 260);
    _window.releasedWhenClosed = NO;

    _preview = [[NSImageView alloc] init];
    _preview.imageScaling = NSImageScaleProportionallyUpOrDown;
    _status = [NSTextField labelWithString:@"Opening camera…"];
    _makeupPicker = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_makeupPicker addItemWithTitle:@"不使用妆容"];
    _makeupPicker.accessibilityLabel = @"妆容";
    _makeupPicker.target = self;
    _makeupPicker.action = @selector(selectMakeup:);
    _makeupPicker.enabled = NO;
    for (NSView *view in @[_preview, _status, _makeupPicker]) {
        view.translatesAutoresizingMaskIntoConstraints = NO;
        [_window.contentView addSubview:view];
    }
    NSView *content = _window.contentView;
    [NSLayoutConstraint activateConstraints:@[
        [_preview.topAnchor constraintEqualToAnchor:content.topAnchor],
        [_preview.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [_preview.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [_preview.bottomAnchor constraintEqualToAnchor:_status.topAnchor constant:-8],
        [_status.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:12],
        [_status.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-12],
        [_status.trailingAnchor constraintLessThanOrEqualToAnchor:_makeupPicker.leadingAnchor constant:-12],
        [_makeupPicker.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-12],
        [_makeupPicker.centerYAnchor constraintEqualToAnchor:_status.centerYAnchor]
    ]];
    [_window center];
    [_window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];

    dispatch_async(_captureQueue, ^{
        const char *assets = getenv("SNAPBEAUTY_ASSETS");
        NSString *bundledAssets = [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"Assets"];
        if (!assets || !*assets) assets = bundledAssets.fileSystemRepresentation;
        NSString *bundledLicense = [NSBundle.mainBundle pathForResource:@"snapbeauty" ofType:@"license"];
        if (initialize_license(NULL, bundledLicense.fileSystemRepresentation)) {
            xm_desktop_options options = {sizeof(options), assets};
            if (xm_desktop_engine_create(&options, &self->_engine) == XM_OK) {
                self->_engineReady = ApplyParameters(self->_engine, nil);
            } else {
                NSLog(@"SnapBeauty engine: %s", xm_desktop_last_error(NULL));
            }
        }
        NSArray<NSDictionary *> *styles = self->_engineReady ?
            LoadMakeupStyles([NSString stringWithUTF8String:assets]) : @[];
        dispatch_async(dispatch_get_main_queue(), ^{
            for (NSDictionary *style in styles) {
                [self->_makeupPicker addItemWithTitle:style[@"name"]];
                self->_makeupPicker.itemArray.lastObject.representedObject = style;
            }
            self->_makeupPicker.enabled = styles.count > 0;
            [self requestCamera];
        });
    });
}

- (void)selectMakeup:(NSPopUpButton *)sender {
    NSDictionary *style = sender.selectedItem.representedObject;
    dispatch_async(_captureQueue, ^{
        self->_engineReady = ApplyParameters(self->_engine, style);
    });
}

- (void)requestCamera {
    AVAuthorizationStatus access = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if (access == AVAuthorizationStatusAuthorized) {
        dispatch_async(_captureQueue, ^{ [self startCamera]; });
    } else if (access == AVAuthorizationStatusNotDetermined) {
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
            if (granted) {
                dispatch_async(self->_captureQueue, ^{ [self startCamera]; });
            } else {
                [self showStatus:@"Allow camera access in System Settings."];
            }
        }];
    } else {
        [self showStatus:@"Allow camera access in System Settings."];
    }
}

- (void)showStatus:(NSString *)text {
    dispatch_async(dispatch_get_main_queue(), ^{ self->_status.stringValue = text; });
}

- (void)startCamera {
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    if (!device) {
        [self showStatus:@"No camera found."];
        return;
    }
    NSError *error = nil;
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
    AVCaptureSession *session = [[AVCaptureSession alloc] init];
    AVCaptureVideoDataOutput *output = [[AVCaptureVideoDataOutput alloc] init];
    if (!input || ![session canAddInput:input] || ![session canAddOutput:output]) {
        [self showStatus:@"Cannot open the camera."];
        if (error) NSLog(@"Camera: %@", error.localizedDescription);
        return;
    }
    if ([session canSetSessionPreset:AVCaptureSessionPreset1280x720]) {
        session.sessionPreset = AVCaptureSessionPreset1280x720;
    }
    output.videoSettings = @{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)};
    output.alwaysDiscardsLateVideoFrames = YES;
    [output setSampleBufferDelegate:self queue:_captureQueue];
    [session addInput:input];
    [session addOutput:output];
    _session = session;
    [_session startRunning];
    [self showStatus:!_session.running ? @"Cannot start the camera." :
        (_engineReady ? @"Camera preview" : @"Camera preview · SDK unavailable")];
}

- (void)captureOutput:(AVCaptureOutput *)capture didOutputSampleBuffer:(CMSampleBufferRef)sample
       fromConnection:(AVCaptureConnection *)connection {
    (void)capture;
    (void)connection;
    CVPixelBufferRef buffer = CMSampleBufferGetImageBuffer(sample);
    if (!buffer || dispatch_semaphore_wait(_presentationSlot, DISPATCH_TIME_NOW) != 0) return;
    if (CVPixelBufferLockBaseAddress(buffer, kCVPixelBufferLock_ReadOnly) != kCVReturnSuccess) {
        dispatch_semaphore_signal(_presentationSlot);
        return;
    }

    size_t width = CVPixelBufferGetWidth(buffer);
    size_t height = CVPixelBufferGetHeight(buffer);
    size_t stride = CVPixelBufferGetBytesPerRow(buffer);
    const uint8_t *input = CVPixelBufferGetBaseAddress(buffer);
    CGImageRef image = NULL;
    if (input && width && height && width <= 4096 && height <= 4096 && stride >= width * 4 && stride <= INT32_MAX) {
        NSMutableData *output = [NSMutableData dataWithLength:width * height * 4];
        int64_t timestamp = (int64_t)clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
        xm_desktop_frame frame = {sizeof(frame), input, (int32_t)width, (int32_t)height, (int32_t)stride,
                                  XM_PIXEL_BGRA8, timestamp, output.mutableBytes, (int32_t)(width * 4)};
        BOOL processed = _engineReady && xm_desktop_process(_engine, &frame, NULL) == XM_OK;
        CFDataRef data = processed ? CFBridgingRetain(output) : CFDataCreate(NULL, input, (CFIndex)(stride * height));
        CGDataProviderRef provider = CGDataProviderCreateWithCFData(data);
        CGColorSpaceRef color = CGColorSpaceCreateDeviceRGB();
        image = CGImageCreate(width, height, 8, 32, processed ? width * 4 : stride, color,
                             kCGBitmapByteOrder32Little | kCGImageAlphaNoneSkipFirst, provider, NULL,
                             true, kCGRenderingIntentDefault);
        CGColorSpaceRelease(color);
        CGDataProviderRelease(provider);
        CFRelease(data);
    }
    CVPixelBufferUnlockBaseAddress(buffer, kCVPixelBufferLock_ReadOnly);

    dispatch_async(dispatch_get_main_queue(), ^{
        if (image) {
            self->_preview.image = [[NSImage alloc] initWithCGImage:image size:NSZeroSize];
            CGImageRelease(image);
        }
        dispatch_semaphore_signal(self->_presentationSlot);
    });
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    (void)sender;
    return YES;
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    (void)notification;
    dispatch_sync(_captureQueue, ^{
        [self->_session stopRunning];
        self->_engineReady = NO;
        xm_desktop_engine_destroy(self->_engine);
        self->_engine = NULL;
        xm_desktop_shutdown();
    });
}
@end

int main(void) {
    @autoreleasepool {
        NSApplication *app = NSApplication.sharedApplication;
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        CameraPreview *delegate = [[CameraPreview alloc] init];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
