#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
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

static NSString * nsDomainString = @"com.byteage.nolockonac";
static NSString * nsNotificationString = @"com.byteage.nolockonac/preferences.changed";
static BOOL enabled;
static int origMaxInactivity = 30; ///< 默认的锁屏时间

static void notificationCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
	NSNumber * enabledValue = (NSNumber *)[[NSUserDefaults standardUserDefaults] objectForKey:@"enabled" inDomain:nsDomainString];
	enabled = (enabledValue)? [enabledValue boolValue] : YES;
}

%hook SBUIController
- (void)ACPowerChanged {
	%orig;
    if(enabled){
        MCProfileConnection *profileConn = [objc_getClass("MCProfileConnection") sharedConnection];
        int maxInactivityValue = INT32_MAX;
        if([self isOnAC]){
            NSDictionary *params = [profileConn effectiveParametersForValueSetting:@"maxInactivity"];
            int maxInactivity = [params[@"value"] intValue];
            if(maxInactivity != INT32_MAX){
                origMaxInactivity = maxInactivity;
            }
            maxInactivityValue = INT32_MAX;
        }else{
            maxInactivityValue = origMaxInactivity;
        }

        if(maxInactivityValue > 0){
            [profileConn setValue:[NSNumber numberWithInt:maxInactivityValue] forSetting:@"maxInactivity"];
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
