// SPDX-License-Identifier: GPL-3.0-only
// Mock only the private container API; run the production query/cleanup logic.
// Does not request any real sandbox extensions or access real system files.
#import "../Erosion/Tweaks/MobileGestalt/MGContainerAccessCheck.m"
#import <assert.h>
#import <stdio.h>
#import <string.h>

typedef NS_ENUM(int, Scenario) {
    Success, SecondRoute, QueryDenied, NoToken, EmptyToken, WrongPath,
    ActivationDenied, FileStillDenied, LeakedLease, UnknownAfterRelease,
    CopyFailed, CreateFailed
};
static Scenario scenario;
static int created, queryFreed, objects, objectFreed, activations, tokens, active;
static uint64_t currentClass;
static int queryStorage, objectStorage;
static void *Create(void) {
    created++;
    return scenario == CreateFailed ? NULL : &queryStorage;
}
static void SetClass(void *query, uint64_t value) {
    assert(query == &queryStorage && (value == 12 || value == 13));
    currentClass = value;
}
static void SetIdentifiers(void *query, xpc_object_t value) {
    assert(query == &queryStorage && currentClass == 12);
    assert(strcmp(xpc_string_get_string_ptr(value), "com.apple.geod") == 0);
}
static void SetGroups(void *query, xpc_object_t value) {
    assert(query == &queryStorage && currentClass == 13);
    assert(strcmp(xpc_string_get_string_ptr(value), "systemgroup.com.apple.mobilegestaltcache") == 0);
}
static void SetFlags(void *query, uint64_t value) {
    assert(query == &queryStorage && value == UINT64_C(0x8100000000));
}
static void SetPart(void *query, uint64_t value) {
    assert(query == &queryStorage && value == 3);
}
static void SetDomain(void *query, const char *value) {
    assert(query == &queryStorage && currentClass == 12);
    assert(strcmp(value, "../../../../../../containers/Shared/SystemGroup/"
        "systemgroup.com.apple.mobilegestaltcache/Library/Caches") == 0);
}
static void *Result(void *query) {
    assert(query == &queryStorage);
    if (scenario == QueryDenied || (scenario == SecondRoute && currentClass == 12)) return NULL;
    return &objectStorage;
}
static void FreeQuery(void *query) { assert(query == &queryStorage); queryFreed++; }
static void *Copy(void *object) {
    assert(object == &objectStorage);
    if (scenario == CopyFailed) return NULL;
    objects++;
    return object;
}
static void FreeObject(void *object) {
    assert(object == &objectStorage);
    objectFreed++;
    if (scenario != LeakedLease) active = 0;
}
static const char *Path(void *object) {
    assert(object == &objectStorage);
    if (scenario == WrongPath) return "/private/var/mobile/secret-path-must-not-be-logged";
    if (currentClass == 12) return "/private/var/containers/Data/System/com.apple.geod/Library/Caches/"
        "../../../../../../containers/Shared/SystemGroup/"
        "systemgroup.com.apple.mobilegestaltcache/Library/Caches";
    return "/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches";
}
static char *Token(void *object) {
    assert(object == &objectStorage);
    tokens++;
    if (scenario == NoToken) return NULL;
    return strdup(scenario == EmptyToken ? "" : "secret-token-must-not-be-logged");
}
static bool Activate(void *object, bool unused) {
    assert(object == &objectStorage && !unused);
    activations++;
    if (scenario == ActivationDenied) return false;
    active = 1;
    return true;
}
static MGCheckAPI API(void) {
    return (MGCheckAPI){Create, SetClass, SetIdentifiers, SetGroups, SetFlags,
        SetPart, SetDomain, Result, FreeQuery, Copy, FreeObject, Path, Token, Activate};
}
static void Reset(Scenario value) {
    scenario = value;
    created = queryFreed = objects = objectFreed = activations = tokens = active = 0;
}
static MGCheckFileState Inspect(NSString *phase) {
    if ([phase containsString:@"释放"] && scenario == UnknownAfterRelease) return MGCheckFileStateUnknown;
    return active && scenario != FileStillDenied ? MGCheckFileStateAvailable : MGCheckFileStateWriteDenied;
}
static void Record(NSString *message) {
    assert(![message containsString:@"secret-token"] && ![message containsString:@"secret-path"]);
}

int main(void) {
    @autoreleasepool {
        Scenario cases[] = {Success, SecondRoute, QueryDenied, NoToken, EmptyToken,
            WrongPath, ActivationDenied, FileStillDenied, LeakedLease,
            UnknownAfterRelease, CopyFailed, CreateFailed};
        for (NSUInteger i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
            Reset(cases[i]);
            BOOL result = MGCheckUsingAPI(API(), ^(NSString *s) { Record(s); },
                ^MGCheckFileState(NSString *s) { return Inspect(s); });
            assert(result == (scenario == Success || scenario == SecondRoute));
            assert(queryFreed == (scenario == CreateFailed ? 0 : created));
            assert(objectFreed == objects);
            if (scenario == WrongPath) assert(tokens == 0 && activations == 0);
            if (scenario == NoToken || scenario == EmptyToken) assert(activations == 0);
            if (scenario == LeakedLease || scenario == UnknownAfterRelease) assert(created == 1);
            if (scenario == Success) assert(created == 1 && active == 0);
            if (scenario == SecondRoute) assert(created == 2 && currentClass == 13 && active == 0);
            printf("PASS: container API scenario %lu\n", (unsigned long)i);
        }
        Reset(Success);
        MGCheckAPI missing = API();
        missing.freeObject = NULL;
        assert(!MGCheckUsingAPI(missing, ^(NSString *s) { Record(s); },
            ^MGCheckFileState(NSString *s) { return Inspect(s); }));
        assert(created == 0);
        puts("PASS: missing cleanup API prevents queries");

        Reset(Success);
        missing = API();
        missing.setPartDomain = NULL;
        assert(MGCheckUsingAPI(missing, ^(NSString *s) { Record(s); },
            ^MGCheckFileState(NSString *s) { return Inspect(s); }));
        assert(created == 1 && currentClass == 13 && active == 0);
        puts("PASS: unavailable geod API does not prevent independent class-13 check");

        for (NSInteger baseline = MGCheckFileStateUnknown; baseline <= MGCheckFileStateAvailable; baseline++) {
            if (baseline == MGCheckFileStateWriteDenied) continue;
            Reset(Success);
            assert(!MGCheckUsingAPI(API(), ^(NSString *s) { Record(s); },
                ^MGCheckFileState(NSString *s) { return (MGCheckFileState)baseline; }));
            assert(created == 0);
        }
        puts("PASS: unknown or already-writable baseline cannot verify a new route");
        puts("Mock tests do not establish iOS compatibility or Apple Intelligence activation.");
    }
    return 0;
}
