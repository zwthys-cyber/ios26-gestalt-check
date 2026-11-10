// SPDX-License-Identifier: GPL-3.0-only
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
typedef NS_ENUM(NSInteger, MGCheckFileState) {
    MGCheckFileStateUnknown,
    MGCheckFileStateWriteDenied,
    MGCheckFileStateAvailable
};
// Requests temporary access to one fixed directory. The inspector must not
// mutate files. Returns YES only after access AND subsequent revocation pass.
BOOL MGCheckContainerRoutes(void (^record)(NSString *message),
                            MGCheckFileState (^inspect)(NSString *phase));
NS_ASSUME_NONNULL_END
