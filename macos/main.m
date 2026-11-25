#import <AppKit/AppKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreVideo/CoreVideo.h>
#import <ImageIO/ImageIO.h>
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

// Registers the CC BY-SA host filters shipped with this app (Assets/host-filters/luts/*.png, attribution in
// Assets/host-filters/NOTICE.md). The 8-bit RGB PNGs are read without colour management and passed as opaque RGBA8.
static BOOL RegisterHostFilters(xm_desktop_engine *engine, NSString *assets) {
    NSString *folder = [assets stringByAppendingPathComponent:@"host-filters/luts"];
    for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:folder error:nil]) {
        if (![name.pathExtension isEqualToString:@"png"]) continue;
        NSURL *url = [NSURL fileURLWithPath:[folder stringByAppendingPathComponent:name]];
        CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
        CGImageRef image = source ? CGImageSourceCreateImageAtIndex(source, 0, NULL) : NULL;
        if (source) CFRelease(source);
        if (!image) return NO;
        const size_t width = CGImageGetWidth(image), height = CGImageGetHeight(image);
        const size_t bits = CGImageGetBitsPerPixel(image), stride = CGImageGetBytesPerRow(image);
        BOOL ok = CGImageGetBitsPerComponent(image) == 8 && (bits == 24 || bits == 32);
        if (ok) {
            CFDataRef data = CGDataProviderCopyData(CGImageGetDataProvider(image));
            const uint8_t *pixels = CFDataGetBytePtr(data);
            NSMutableData *rgba = [NSMutableData dataWithLength:width * height * 4];
            uint8_t *out = rgba.mutableBytes;
            for (size_t y = 0; y < height; ++y) for (size_t x = 0; x < width; ++x) {
                const uint8_t *s = pixels + y * stride + x * (bits / 8); uint8_t *d = out + (y * width + x) * 4;
                d[0] = s[0]; d[1] = s[1]; d[2] = s[2]; d[3] = 255;
            }
            CFRelease(data);
            ok = xm_desktop_engine_register_filter(engine, name.stringByDeletingPathExtension.UTF8String, out,
                                                   (int32_t)width, (int32_t)height) == XM_OK;
            if (!ok) NSLog(@"SnapBeauty host filter %@: %s", name, xm_desktop_last_error(engine));
        }
        CGImageRelease(image);
        if (!ok) return NO;
    }
    return YES;
}

static const float lipColors[6][4] = {{0,0,0,0}, {.611f,.352f,.352f,.500f}, {.752f,.267f,.231f,.543f},
    {.713f,.374f,.409f,.517f}, {.786f,.326f,.252f,.629f}, {.476f,.018f,.025f,.777f}};
static BOOL ApplyParameters(xm_desktop_engine *engine, BOOL malePreset, NSDictionary *style, NSInteger lipstick, float strength) {
    float values[XM_PARAM_COUNT];
    xm_params_neutral(values); // Neutral start: zero-filling would push the twelve bidirectional face controls (neutral 0.5) to one extreme.
    if (malePreset) {
        values[XM_PARAM_SMOOTHING] = 3.9f;
        values[XM_PARAM_BRIGHTENING] = 0.38f;
        values[XM_PARAM_ROSINESS] = 0.12f;
        values[XM_PARAM_SHAPE_FACE_SLIMMING] = 0.24f;
        values[XM_PARAM_SHAPE_FACE_V_TAPER] = 0.16f;
        values[XM_PARAM_SHAPE_FACE_SHRINKING] = 0.15f;
        values[XM_PARAM_SHAPE_EYE_SCALE] = 0.18f;
        values[XM_PARAM_SHAPE_NOSE_WIDTH] = 0.14f;
        values[XM_PARAM_SKIN_SHARPNESS] = 0.22f;
        values[XM_PARAM_SKIN_TEXTURE] = 0.06f;
        values[XM_PARAM_SKIN_BLEMISH_REMOVAL] = 0.48f;
        values[XM_PARAM_SKIN_EYE_BRIGHTENING] = 0.28f;
        values[XM_PARAM_SKIN_UNDEREYE_BAGS] = 0.55f;
        values[XM_PARAM_SKIN_SMILE_LINES] = 0.35f;
        values[XM_PARAM_SKIN_FACE_CONTOUR] = 0.18f;
#if XM_PARAM_COUNT >= 46
        values[XM_PARAM_SKIN_AEGYO_SAL] = 0.25f;
#endif
    } else {
        values[XM_PARAM_SMOOTHING] = 3.6f;
        values[XM_PARAM_BRIGHTENING] = 0.48f;
        values[XM_PARAM_ROSINESS] = 0.10f;
        values[XM_PARAM_SKIN_TEXTURE] = 0.12f;
        values[XM_PARAM_SKIN_BLEMISH_REMOVAL] = 0.38f;
        values[XM_PARAM_SKIN_EYE_BRIGHTENING] = 0.28f;
        values[XM_PARAM_SKIN_UNDEREYE_BAGS] = 0.45f;
        values[XM_PARAM_SKIN_SMILE_LINES] = 0.35f;
        values[XM_PARAM_SKIN_FACE_CONTOUR] = 0.28f;
#if XM_PARAM_COUNT >= 46
        values[XM_PARAM_SKIN_AEGYO_SAL] = 0.58f;
#endif
    }
    float intensity = style ? 0.6f : 0.0f;
    values[XM_PARAM_MAKEUP_INTENSITY] = intensity;
    values[XM_PARAM_FILTER_INTENSITY] = intensity;
    values[XM_PARAM_LIPSTICK_R] = lipColors[lipstick][0]; values[XM_PARAM_LIPSTICK_G] = lipColors[lipstick][1];
    values[XM_PARAM_LIPSTICK_B] = lipColors[lipstick][2]; values[XM_PARAM_LIPSTICK_A] = lipColors[lipstick][3];
    values[XM_PARAM_LIPSTICK_STRENGTH] = lipstick ? strength : 0;
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
    NSSegmentedControl *_genderSwitch;
    NSVisualEffectView *_bottomBar;
    NSButton *_toggleBarBtn;
    NSButton *_compareBtn;
    NSPopUpButton *_makeupPicker;
    NSPopUpButton *_lipPicker;
    NSSlider *_lipSlider;
    NSDictionary *_dawnStyle;
    float _lipLevels[6];
    BOOL _malePreset;
    BOOL _barCollapsed;
    BOOL _showOriginal;
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
    _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 820, 520)
                                          styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                    NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable
                                            backing:NSBackingStoreBuffered defer:NO];
    _window.title = @"SnapBeauty macOS Samples";
    _window.minSize = NSMakeSize(480, 300);
    _window.releasedWhenClosed = NO;

    NSView *content = _window.contentView;
    content.wantsLayer = YES;
    content.layer.backgroundColor = [NSColor colorWithRed:0.063 green:0.075 blue:0.067 alpha:1.0].CGColor;

    _preview = [[NSImageView alloc] init];
    _preview.imageScaling = NSImageScaleProportionallyUpOrDown;
    NSClickGestureRecognizer *tap = [[NSClickGestureRecognizer alloc] initWithTarget:self action:@selector(toggleBottomBar:)];
    [_preview addGestureRecognizer:tap];

    NSVisualEffectView *statusPill = [[NSVisualEffectView alloc] init];
    statusPill.material = NSVisualEffectMaterialHUDWindow;
    statusPill.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    statusPill.state = NSVisualEffectStateActive;
    statusPill.wantsLayer = YES; statusPill.layer.cornerRadius = 13; statusPill.layer.masksToBounds = YES;
    _status = [NSTextField labelWithString:@"Opening camera…"];
    _status.font = [NSFont systemFontOfSize:11];
    _status.textColor = [NSColor whiteColor];
    _status.translatesAutoresizingMaskIntoConstraints = NO;
    [statusPill addSubview:_status];

    _genderSwitch = [NSSegmentedControl segmentedControlWithLabels:@[@"女生", @"男生"] trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(switchGender:)];
    _genderSwitch.selectedSegment = 0;
    _genderSwitch.controlSize = NSControlSizeSmall;
    _genderSwitch.accessibilityLabel = @"男女预设切换";

    _toggleBarBtn = [NSButton buttonWithTitle:@"收起 ↓" target:self action:@selector(toggleBottomBar:)];
    _toggleBarBtn.bezelStyle = NSBezelStyleInline;
    _toggleBarBtn.controlSize = NSControlSizeSmall;

    _compareBtn = [NSButton buttonWithTitle:@"原图对比" target:self action:@selector(toggleOriginal:)];
    _compareBtn.bezelStyle = NSBezelStyleInline;
    _compareBtn.buttonType = NSButtonTypePushOnPushOff;
    _compareBtn.controlSize = NSControlSizeSmall;

    _bottomBar = [[NSVisualEffectView alloc] init];
    _bottomBar.material = NSVisualEffectMaterialHUDWindow;
    _bottomBar.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    _bottomBar.state = NSVisualEffectStateActive;
    _bottomBar.wantsLayer = YES; _bottomBar.layer.cornerRadius = 16; _bottomBar.layer.masksToBounds = YES;

    _makeupPicker = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _makeupPicker.controlSize = NSControlSizeSmall;
    [_makeupPicker addItemWithTitle:@"无妆"];
    _makeupPicker.accessibilityLabel = @"妆容";
    _makeupPicker.target = self;
    _makeupPicker.action = @selector(selectMakeup:);
    _makeupPicker.enabled = NO;
    for (int i = 0; i < 6; ++i) _lipLevels[i] = 0.6f;
    _lipPicker = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _lipPicker.controlSize = NSControlSizeSmall;
    [_lipPicker addItemsWithTitles:@[@"无口红", @"珊瑚色", @"西柚色", @"豆沙粉", @"元气橘", @"复古红"]];
    _lipPicker.target = self; _lipPicker.action = @selector(selectLipstick:); _lipPicker.accessibilityLabel = @"口红";
    _lipPicker.enabled = NO;
    _lipSlider = [NSSlider sliderWithValue:0.6 minValue:0 maxValue:1 target:self action:@selector(changeLipstick:)];
    _lipSlider.controlSize = NSControlSizeSmall;
    _lipSlider.accessibilityLabel = @"口红强度"; _lipSlider.enabled = NO;

    for (NSView *view in @[_makeupPicker, _lipPicker, _lipSlider, _compareBtn]) {
        view.translatesAutoresizingMaskIntoConstraints = NO;
        [_bottomBar addSubview:view];
    }
    for (NSView *view in @[_preview, statusPill, _genderSwitch, _toggleBarBtn, _bottomBar]) {
        view.translatesAutoresizingMaskIntoConstraints = NO;
        [content addSubview:view];
    }
    [NSLayoutConstraint activateConstraints:@[
        [_preview.topAnchor constraintEqualToAnchor:content.topAnchor],
        [_preview.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [_preview.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [_preview.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],

        [statusPill.topAnchor constraintEqualToAnchor:content.topAnchor constant:12],
        [statusPill.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:12],
        [_status.topAnchor constraintEqualToAnchor:statusPill.topAnchor constant:5],
        [_status.bottomAnchor constraintEqualToAnchor:statusPill.bottomAnchor constant:-5],
        [_status.leadingAnchor constraintEqualToAnchor:statusPill.leadingAnchor constant:10],
        [_status.trailingAnchor constraintEqualToAnchor:statusPill.trailingAnchor constant:-10],

        [_genderSwitch.topAnchor constraintEqualToAnchor:content.topAnchor constant:12],
        [_genderSwitch.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-12],

        [_toggleBarBtn.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-14],
        [_toggleBarBtn.bottomAnchor constraintEqualToAnchor:_bottomBar.topAnchor constant:-6],

        [_bottomBar.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:12],
        [_bottomBar.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-12],
        [_bottomBar.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-10],
        [_bottomBar.heightAnchor constraintEqualToConstant:40],

        [_makeupPicker.leadingAnchor constraintEqualToAnchor:_bottomBar.leadingAnchor constant:12],
        [_makeupPicker.centerYAnchor constraintEqualToAnchor:_bottomBar.centerYAnchor],
        [_lipPicker.leadingAnchor constraintEqualToAnchor:_makeupPicker.trailingAnchor constant:10],
        [_lipPicker.centerYAnchor constraintEqualToAnchor:_bottomBar.centerYAnchor],
        [_lipSlider.leadingAnchor constraintEqualToAnchor:_lipPicker.trailingAnchor constant:8],
        [_lipSlider.centerYAnchor constraintEqualToAnchor:_bottomBar.centerYAnchor],
        [_lipSlider.widthAnchor constraintEqualToConstant:110],
        [_compareBtn.trailingAnchor constraintEqualToAnchor:_bottomBar.trailingAnchor constant:-12],
        [_compareBtn.centerYAnchor constraintEqualToAnchor:_bottomBar.centerYAnchor]
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
                self->_engineReady = RegisterHostFilters(self->_engine, [NSString stringWithUTF8String:assets]) &&
                    ApplyParameters(self->_engine, NO, nil, 0, 0);
            } else {
                NSLog(@"SnapBeauty engine: %s", xm_desktop_last_error(NULL));
            }
        }
        NSArray<NSDictionary *> *styles = self->_engineReady ?
            LoadMakeupStyles([NSString stringWithUTF8String:assets]) : @[];
        NSDictionary *dawn = nil;
        for (NSDictionary *style in styles) {
            if ([style[@"key"] isEqualToString:@"dawn"]) { dawn = style; break; }
        }
        self->_dawnStyle = dawn;
        if (dawn) self->_engineReady = ApplyParameters(self->_engine, NO, dawn, 0, 0);
        dispatch_async(dispatch_get_main_queue(), ^{
            for (NSDictionary *style in styles) {
                [self->_makeupPicker addItemWithTitle:style[@"name"]];
                self->_makeupPicker.itemArray.lastObject.representedObject = style;
            }
            self->_makeupPicker.enabled = styles.count > 0;
            self->_lipPicker.enabled = self->_engineReady;
            if (dawn) [self->_makeupPicker selectItemWithTitle:dawn[@"name"]];
            [self requestCamera];
        });
    });
}

- (void)toggleBottomBar:(id)sender {
    (void)sender;
    _barCollapsed = !_barCollapsed;
    _bottomBar.hidden = _barCollapsed;
    _toggleBarBtn.title = _barCollapsed ? @"展开美颜 ↑" : @"收起 ↓";
}

- (void)toggleOriginal:(NSButton *)sender {
    BOOL orig = sender.state == NSControlStateValueOn;
    dispatch_async(_captureQueue, ^{ self->_showOriginal = orig; });
}

- (void)switchGender:(NSSegmentedControl *)sender {
    _malePreset = sender.selectedSegment == 1;
    if (_malePreset) {
        [_makeupPicker selectItemAtIndex:0];
        [_lipPicker selectItemAtIndex:1];
        _lipLevels[1] = 0.26f;
        _lipSlider.enabled = YES; _lipSlider.floatValue = 0.26f;
    } else {
        if (_dawnStyle) [_makeupPicker selectItemWithTitle:_dawnStyle[@"name"]];
        [_lipPicker selectItemAtIndex:0];
        _lipSlider.enabled = NO; _lipSlider.floatValue = 0.6f;
    }
    [self selectMakeup:_makeupPicker];
}

- (void)selectMakeup:(NSPopUpButton *)sender {
    NSDictionary *style = sender.selectedItem.representedObject;
    NSInteger lip = _lipPicker.indexOfSelectedItem; float strength = _lipLevels[lip];
    BOOL male = _malePreset;
    dispatch_async(_captureQueue, ^{ self->_engineReady = ApplyParameters(self->_engine, male, style, lip, strength); });
}

- (void)selectLipstick:(NSPopUpButton *)sender {
    NSInteger lip = sender.indexOfSelectedItem;
    _lipSlider.enabled = lip > 0; _lipSlider.floatValue = _lipLevels[lip];
    [self selectMakeup:_makeupPicker];
}

- (void)changeLipstick:(NSSlider *)sender {
    _lipLevels[_lipPicker.indexOfSelectedItem] = sender.floatValue;
    [self selectMakeup:_makeupPicker];
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
        BOOL processed = !_showOriginal && _engineReady && xm_desktop_process(_engine, &frame, NULL) == XM_OK;
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
