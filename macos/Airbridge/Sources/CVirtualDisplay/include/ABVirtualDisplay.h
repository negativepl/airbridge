#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

/// Thin wrapper over the private CGVirtualDisplay API. Creates an extra display
/// of an arbitrary resolution (so the phone can act as a perfectly-shaped second
/// monitor); ScreenCaptureKit then captures it by `displayID`. The created
/// display lives as long as this object is retained — release it to remove it.
@interface ABVirtualDisplay : NSObject

- (nullable instancetype)initWithWidth:(uint32_t)width
                                height:(uint32_t)height
                                 hiDPI:(BOOL)hiDPI
                                  name:(NSString *)name;

/// CGDirectDisplayID of the created display, or 0 if creation failed.
@property (nonatomic, readonly) uint32_t displayID;

/// Human-readable reason when creation failed (nil on success).
@property (nonatomic, readonly, nullable) NSString *failureReason;

/// Diagnostic: which display mode was selected (logical + backing pixels).
@property (nonatomic, readonly, nullable) NSString *selectedMode;

@end

NS_ASSUME_NONNULL_END
