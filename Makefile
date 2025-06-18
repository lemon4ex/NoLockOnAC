THEOS_DEVICE_IP = localhost -o StrictHostKeyChecking=no
THEOS_DEVICE_PORT = 2222

ARCHS = arm64 arm64e

ifeq ($(THEOS_PACKAGE_SCHEME), rootless)
TARGET = iphone:clang:14.5:15.0 # theos includes the iOS 14.5 SDK by default, it's ok
else
TARGET = iphone:clang:14.5:9.0
endif

INSTALL_TARGET_PROCESSES = SpringBoard	# 会自动重启 SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = NoLockOnAC

NoLockOnAC_FILES = Tweak.x
NoLockOnAC_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
