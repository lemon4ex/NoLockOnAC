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

@interface _CDBatterySaver : NSObject
+(id)sharedInstance;
+(id)batterySaver;
-(long long)setMode:(long long)arg1 ;
-(void)setPowerMode:(long long)arg1 fromSource:(id)arg2 withCompletion:(/*^block*/id)arg3 ;
-(void)setPowerMode:(long long)arg1 withCompletion:(/*^block*/id)arg2;
-(BOOL)setPowerMode:(long long)arg1 error:(id*)arg2 ;
-(long long)getPowerMode;
-(BOOL)setPowerMode:(long long)arg1 fromSource:(id)arg2 ;
@end

@interface JBBulletinManager : NSObject
+(id)sharedInstance;
-(id)showBulletinWithTitle:(NSString *)title message:(NSString *)message bundleID:(NSString *)bundleID;
-(id)showBulletinWithTitle:(NSString *)title message:(NSString *)message bundleID:(NSString *)bundleID soundPath:(NSString *)soundPath;
-(id)showBulletinWithTitle:(NSString *)title message:(NSString *)message bundleID:(NSString *)bundleID soundID:(int)inSoundID;
-(id)showBulletinWithTitle:(NSString *)title message:(NSString *)message overrideBundleImage:(UIImage *)overridBundleImage;
-(id)showBulletinWithTitle:(NSString *)title message:(NSString *)message overrideBundleImage:(UIImage *)overridBundleImage soundPath:(NSString *)soundPath;
-(id)showBulletinWithTitle:(NSString *)title message:(NSString *)message overridBundleImage:(UIImage *)overridBundleImage soundID:(int)inSoundID;
-(id)showBulletinWithTitle:(NSString *)title message:(NSString *)message bundleID:(NSString *)bundleID hasSound:(BOOL)hasSound soundID:(int)soundID vibrateMode:(int)vibrate soundPath:(NSString *)soundPath attachmentImage:(UIImage *)attachmentImage overrideBundleImage:(UIImage *)overrideBundleImage;
@end

static NSString * nsDomainString = @"com.byteage.nolockonac";
static NSString * nsNotificationString = @"com.byteage.nolockonac/preferences.changed";
static BOOL enabled;
static BOOL notice;
static int origMaxInactivity = 30; ///< 默认的锁屏时间
static BOOL saverMode = 0;

static void notificationCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
	NSNumber * enabledValue = (NSNumber *)[[NSUserDefaults standardUserDefaults] objectForKey:@"enabled" inDomain:nsDomainString];
	enabled = (enabledValue)? [enabledValue boolValue] : YES;

    NSNumber * noticeValue = (NSNumber *)[[NSUserDefaults standardUserDefaults] objectForKey:@"notice" inDomain:nsDomainString];
	notice = (noticeValue)? [noticeValue boolValue] : YES;
}

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
            // 充电时关闭省电模式
            _CDBatterySaver *saver = [objc_getClass("_CDBatterySaver") batterySaver];
            saverMode = [saver getPowerMode];
            [saver setMode:0];
        }else{
            maxInactivityValue = origMaxInactivity;
            message = @"自动锁屏已启用";
            _CDBatterySaver *saver = [objc_getClass("_CDBatterySaver") batterySaver];
            [saver setMode:saverMode];
        }

        if(maxInactivityValue > 0){
            [profileConn setValue:[NSNumber numberWithInt:maxInactivityValue] forSetting:@"maxInactivity"];
            if(notice) {
                [[objc_getClass("JBBulletinManager") sharedInstance] showBulletinWithTitle:@"NoLockOnAC" message:message bundleID:@"com.apple.Preferences"];
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
