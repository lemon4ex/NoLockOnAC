#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#import <Foundation/NSUserDefaults+Private.h>
#import <dlfcn.h>

#define XLOG(log, ...)	NSLog(@"[NoLockOnAC] " log, ##__VA_ARGS__)

@interface MCProfileConnection : NSObject
+ (instancetype)sharedConnection;
- (NSDictionary *)effectiveParametersForValueSetting:(NSString *)arg1;
- (void)setValue:(id)arg1 forSetting:(NSString *)arg2;
@end

@interface SBUIController : NSObject
+ (id)sharedInstanceIfExists;
+ (id)sharedInstance;
- (void)ACPowerChanged; // 交流电源(插入USB)状态改变通知
- (_Bool)isOnAC; // 是否已连接电源(插入USB)，状态改变时候可使用此方法获取当前状态
-(int)batteryCapacityAsPercentage;
@end

@interface BBAction : NSObject
+ (id)actionWithLaunchBundleID:(id)arg1 callblock:(id)arg2;
@end

@interface BBBulletin : NSObject
@property(nonatomic, copy)NSString* sectionID;
@property(nonatomic, copy)NSString* recordID;
@property(nonatomic, copy)NSString* publisherBulletinID;
@property(nonatomic, copy)NSString* title;
@property(nonatomic, copy)NSString* message;
@property(nonatomic, retain)NSDate* date;
@property(assign, nonatomic) BOOL clearable;
@property(nonatomic)BOOL showsMessagePreview;
@property(nonatomic, copy)BBAction* defaultAction;
@property(nonatomic, copy)NSString* bulletinID;
@property(nonatomic, retain)NSDate* lastInterruptDate;
@property(nonatomic, retain)NSDate* publicationDate;
@property (nonatomic,retain) NSDate * expirationDate; 
@property(nonatomic) BOOL preventAutomaticRemovalFromLockScreen;
@end

@interface BBServer : NSObject
- (void)publishBulletin:(BBBulletin *)arg1 destinations:(NSUInteger)arg2 alwaysToLockScreen:(BOOL)arg3;
- (void)publishBulletin:(id)arg1 destinations:(unsigned long long)arg2;
@end

static NSString * nsDomainString = @"com.byteage.nolockonac";
static NSString * nsNotificationString = @"com.byteage.nolockonac/preferences.changed";
static BOOL enabled;
static BOOL notice;
static int origMaxInactivity = 30; ///< 默认的锁屏时间
static BBServer* bbServer = nil;

static void notificationCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
	NSNumber * enabledValue = (NSNumber *)[[NSUserDefaults standardUserDefaults] objectForKey:@"enabled" inDomain:nsDomainString];
	enabled = (enabledValue)? [enabledValue boolValue] : YES;

    NSNumber * noticeValue = (NSNumber *)[[NSUserDefaults standardUserDefaults] objectForKey:@"notice" inDomain:nsDomainString];
	notice = (noticeValue)? [noticeValue boolValue] : YES;
}

static dispatch_queue_t getBBServerQueue() {

    static dispatch_queue_t queue;
    static dispatch_once_t predicate;

    dispatch_once(&predicate, ^{
    void* handle = dlopen(NULL, RTLD_GLOBAL);
        if (handle) {
            dispatch_queue_t __weak *pointer = (__weak dispatch_queue_t *) dlsym(handle, "__BBServerQueue");
            if (pointer) queue = *pointer;
            dlclose(handle);
        }
    });

    return queue;
}

static void publishNotification(NSString *sectionID, NSDate *date, NSString *message, bool banner) {
    
	BBBulletin* bulletin = [[%c(BBBulletin) alloc] init];

	bulletin.title = @"NoLockOnAC";
    bulletin.message = message;
    bulletin.sectionID = sectionID;
    bulletin.bulletinID = [[NSProcessInfo processInfo] globallyUniqueString];
    bulletin.recordID = [[NSProcessInfo processInfo] globallyUniqueString];
    bulletin.publisherBulletinID = [[NSProcessInfo processInfo] globallyUniqueString];
    bulletin.date = date;
    bulletin.defaultAction = [%c(BBAction) actionWithLaunchBundleID:sectionID callblock:nil];
    bulletin.clearable = YES;
    bulletin.showsMessagePreview = YES;
    bulletin.publicationDate = date;
    bulletin.lastInterruptDate = date;
    bulletin.expirationDate = [date dateByAddingTimeInterval:5]; // 设置过期时间，避免通知一直存在

    if (banner) {
        if ([bbServer respondsToSelector:@selector(publishBulletin:destinations:)]) {
            dispatch_sync(getBBServerQueue(), ^{
				// 4 = to lockscreen
                // 15 = banner and vibration things
                [bbServer publishBulletin:bulletin destinations:15];
            });
        }
    } else {
        if ([bbServer respondsToSelector:@selector(publishBulletin:destinations:alwaysToLockScreen:)]) {
            dispatch_sync(getBBServerQueue(), ^{
                [bbServer publishBulletin:bulletin destinations:4 alwaysToLockScreen:YES];
            });
        } else if ([bbServer respondsToSelector:@selector(publishBulletin:destinations:)]) {
            dispatch_sync(getBBServerQueue(), ^{
                [bbServer publishBulletin:bulletin destinations:4];
            });
        }
    }

}

%hook BBServer

- (id)initWithQueue:(id)arg1 {

    bbServer = %orig;
    
    return bbServer;

}

- (id)initWithQueue:(id)arg1 dataProviderManager:(id)arg2 syncService:(id)arg3 dismissalSyncCache:(id)arg4 observerListener:(id)arg5 utilitiesListener:(id)arg6 conduitListener:(id)arg7 systemStateListener:(id)arg8 settingsListener:(id)arg9 {
    
    bbServer = %orig;

    return bbServer;

}

- (void)dealloc {

    if (bbServer == self) bbServer = nil;

    %orig;

}

%end

%hook SBUIController
- (void)ACPowerChanged {
	%orig;
    if(enabled){
        MCProfileConnection *profileConn = [objc_getClass("MCProfileConnection") sharedConnection];
        int maxInactivityValue = INT32_MAX;
        NSString *message = nil;
        if([self isOnAC]){
            NSDictionary *params = [profileConn effectiveParametersForValueSetting:@"maxInactivity"];
            int maxInactivity = [params[@"value"] intValue];
            if(maxInactivity != INT32_MAX){
                origMaxInactivity = maxInactivity;
            }
            maxInactivityValue = INT32_MAX;
            message = @"自动锁屏已禁用";
        }else{
            maxInactivityValue = origMaxInactivity;
            message = @"自动锁屏已启用";
        }

        if(maxInactivityValue > 0){
            [profileConn setValue:[NSNumber numberWithInt:maxInactivityValue] forSetting:@"maxInactivity"];
            if(notice) {
                publishNotification(@"com.apple.Preferences", [NSDate date], message, true);
            }
        }
	}
}
%end

%ctor {
	XLOG(@"loaded in %s (%d)", getprogname(), getpid());

	// Set variables on start up
	notificationCallback(NULL, NULL, NULL, NULL, NULL);

	// Register for 'PostNotification' notifications
	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, notificationCallback, (CFStringRef)nsNotificationString, NULL, CFNotificationSuspensionBehaviorCoalesce);

	// Add any personal initializations
	%init();
}
