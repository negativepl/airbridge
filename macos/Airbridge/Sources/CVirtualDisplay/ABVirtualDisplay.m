#import "ABVirtualDisplay.h"
#import <unistd.h>

// MARK: - Private CGVirtualDisplay API (reverse-engineered; stable since 10.15)
//
// We declare the interfaces only so the compiler knows the selectors; every
// instance is created via NSClassFromString and messaged through these
// declarations, so there are NO undefined link-time symbols (the classes live
// in CoreGraphics and resolve at runtime).

@interface CGVirtualDisplayDescriptor : NSObject
@property (retain) dispatch_queue_t queue;
@property (copy) NSString *name;
@property uint32_t maxPixelsWide;
@property uint32_t maxPixelsHigh;
@property CGSize sizeInMillimeters;
@property uint32_t productID;
@property uint32_t vendorID;
@property uint32_t serialNum;
@property (copy) void (^terminationHandler)(id a, id b);
@property CGPoint redPrimary;
@property CGPoint greenPrimary;
@property CGPoint bluePrimary;
@property CGPoint whitePoint;
@end

@interface CGVirtualDisplayMode : NSObject
- (instancetype)initWithWidth:(uint32_t)width height:(uint32_t)height refreshRate:(double)refreshRate;
@property (readonly) uint32_t width;
@property (readonly) uint32_t height;
@property (readonly) double refreshRate;
@end

@interface CGVirtualDisplaySettings : NSObject
@property uint32_t hiDPI;
@property (retain) NSArray<CGVirtualDisplayMode *> *modes;
@end

@interface CGVirtualDisplay : NSObject
- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;
@property (readonly) uint32_t displayID;
@end

// MARK: - Wrapper

@implementation ABVirtualDisplay {
    id _display;  // strong ref keeps the display alive
}

- (nullable instancetype)initWithWidth:(uint32_t)width
                                height:(uint32_t)height
                                 hiDPI:(BOOL)hiDPI
                                  name:(NSString *)name {
    self = [super init];
    if (!self) return nil;

    Class descClass = NSClassFromString(@"CGVirtualDisplayDescriptor");
    Class dispClass = NSClassFromString(@"CGVirtualDisplay");
    Class setClass  = NSClassFromString(@"CGVirtualDisplaySettings");
    Class modeClass = NSClassFromString(@"CGVirtualDisplayMode");
    if (!descClass || !dispClass || !setClass || !modeClass) {
        _failureReason = @"CGVirtualDisplay classes unavailable";
        return self;
    }

    CGVirtualDisplayDescriptor *desc = [[descClass alloc] init];
    desc.queue = dispatch_get_main_queue();
    desc.name = name;
    desc.maxPixelsWide = width;
    desc.maxPixelsHigh = height;
    // ~150 dpi physical size so the OS picks sane default scaling.
    desc.sizeInMillimeters = CGSizeMake(width / 150.0 * 25.4, height / 150.0 * 25.4);
    desc.productID = 0x1234;
    desc.vendorID = 0x3456;
    desc.serialNum = 0x0001;
    desc.terminationHandler = ^(id a, id b) {};
    desc.redPrimary   = CGPointMake(0.640, 0.330);
    desc.greenPrimary = CGPointMake(0.300, 0.600);
    desc.bluePrimary  = CGPointMake(0.150, 0.060);
    desc.whitePoint   = CGPointMake(0.3127, 0.3290);

    CGVirtualDisplay *display = [[dispClass alloc] initWithDescriptor:desc];
    if (!display) {
        _failureReason = @"initWithDescriptor returned nil";
        return self;
    }

    CGVirtualDisplaySettings *settings = [[setClass alloc] init];
    settings.hiDPI = hiDPI ? 1 : 0;
    // A mode is declared in POINTS. With hiDPI set, the WindowServer backs it
    // with 2x pixels, so the Retina mode is half the pixel size; declaring the
    // full pixel size here would ask for a 2x backing twice as large as
    // maxPixelsWide allows, and the display would fall back to 1x.
    uint32_t modeW = hiDPI ? width / 2 : width;
    uint32_t modeH = hiDPI ? height / 2 : height;
    CGVirtualDisplayMode *mode = [[modeClass alloc] initWithWidth:modeW height:modeH refreshRate:60.0];
    settings.modes = @[mode];

    if (![display applySettings:settings]) {
        _failureReason = @"applySettings failed";
        return self;
    }

    _display = display;
    _displayID = display.displayID;

    // macOS may auto-join a new display into a mirror set (cloning the main
    // screen and forcing a shared resolution) and/or pick a scaled-down default
    // mode. Force it standalone (extended) at its highest 1:1 resolution.
    [self configureDisplay:display.displayID pixelWidth:width pixelHeight:height];

    return self;
}

- (void)invalidate {
    // Releasing the CGVirtualDisplay removes it from the WindowServer. Do it
    // explicitly (not just via ARC dealloc) so a hung caller can't leave the
    // display alive.
    _display = nil;
    _displayID = 0;
}

- (void)dealloc {
    [self invalidate];
}

/// Wait for the display to register, then break it out of any mirror set and
/// select the mode that matches the requested backing size exactly.
- (void)configureDisplay:(CGDirectDisplayID)displayID
              pixelWidth:(uint32_t)width
             pixelHeight:(uint32_t)height {
    for (int i = 0; i < 40; i++) {
        uint32_t count = 0;
        CGDirectDisplayID ids[32];
        if (CGGetActiveDisplayList(32, ids, &count) == kCGErrorSuccess) {
            BOOL found = NO;
            for (uint32_t j = 0; j < count; j++) if (ids[j] == displayID) { found = YES; break; }
            if (found) break;
        }
        usleep(50000);  // 50 ms
    }

    // Without this option CoreGraphics hides the HiDPI ("looks like") modes,
    // so the Retina mode would never be found and the display would stay 1x.
    // A display that has only just registered can still report no modes
    // (logged 2026-10-10: "offered" empty, the display stayed at 800x600), so
    // wait for the list to fill.
    CFDictionaryRef opts = (__bridge CFDictionaryRef)@{ (__bridge NSString *)kCGDisplayShowDuplicateLowResolutionModes: @YES };
    CFArrayRef modes = NULL;
    for (int i = 0; i < 40; i++) {
        modes = CGDisplayCopyAllDisplayModes(displayID, opts);
        if (modes && CFArrayGetCount(modes) > 0) break;
        if (modes) { CFRelease(modes); modes = NULL; }
        usleep(50000);  // 50 ms
    }

    // The WindowServer adds stock modes (800x600 @ 1600x1200, 640x480, ...) next
    // to the declared one, so "the widest backing" is not the requested display:
    // for a portrait or 21:9 panel it picked the 4:3 800x600 mode and the
    // desktop arrived letterboxed. Match the requested backing size instead:
    // first the 2x Retina mode, then any mode of that pixel size.
    CGDisplayModeRef best = NULL;
    if (modes) {
        for (int pass = 0; pass < 2 && !best; pass++) {
            for (CFIndex i = 0; i < CFArrayGetCount(modes); i++) {
                CGDisplayModeRef m = (CGDisplayModeRef)CFArrayGetValueAtIndex(modes, i);
                if (CGDisplayModeGetPixelWidth(m) != width || CGDisplayModeGetPixelHeight(m) != height) continue;
                if (!CGDisplayModeIsUsableForDesktopGUI(m)) continue;
                size_t w = CGDisplayModeGetWidth(m);
                if (pass == 0 && w * 2 != width) continue;
                best = m; break;
            }
        }
    }

    // Every mode the display offers, as "points@pixels", for the diagnostics log.
    NSMutableArray<NSString *> *offered = [NSMutableArray array];
    if (modes) {
        for (CFIndex i = 0; i < CFArrayGetCount(modes); i++) {
            CGDisplayModeRef m = (CGDisplayModeRef)CFArrayGetValueAtIndex(modes, i);
            [offered addObject:[NSString stringWithFormat:@"%zux%zu@%zux%zu",
                                (size_t)CGDisplayModeGetWidth(m), (size_t)CGDisplayModeGetHeight(m),
                                (size_t)CGDisplayModeGetPixelWidth(m), (size_t)CGDisplayModeGetPixelHeight(m)]];
        }
    }
    if (best) {
        _selectedMode = [NSString stringWithFormat:@"looksLike %zux%zu @ %zux%zu px; offered %@",
                         (size_t)CGDisplayModeGetWidth(best), (size_t)CGDisplayModeGetHeight(best),
                         (size_t)CGDisplayModeGetPixelWidth(best), (size_t)CGDisplayModeGetPixelHeight(best),
                         [offered componentsJoinedByString:@","]];
    } else {
        _selectedMode = [NSString stringWithFormat:@"no usable mode of the requested size; offered %@",
                         [offered componentsJoinedByString:@","]];
    }

    CGDisplayConfigRef cfg = NULL;
    if (CGBeginDisplayConfiguration(&cfg) == kCGErrorSuccess && cfg) {
        CGConfigureDisplayMirrorOfDisplay(cfg, displayID, kCGNullDirectDisplay);
        if (best) CGConfigureDisplayWithDisplayMode(cfg, displayID, best, NULL);
        CGCompleteDisplayConfiguration(cfg, kCGConfigurePermanently);
    }
    if (modes) CFRelease(modes);
    // What the WindowServer settled on, points vs pixels, after the configuration.
    CGRect bounds = CGDisplayBounds(displayID);
    _selectedMode = [NSString stringWithFormat:@"%@; now %.0fx%.0f pt @ %zux%zu px", _selectedMode,
                     bounds.size.width, bounds.size.height, CGDisplayPixelsWide(displayID), CGDisplayPixelsHigh(displayID)];
}

@end
