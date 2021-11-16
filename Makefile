TARGET := iphone:clang:latest:9
INSTALL_TARGET_PROCESSES = SpringBoard

THEOS_DEVICE_IP=192.168.1.5


include $(THEOS)/makefiles/common.mk

TWEAK_NAME = TTtest

TTtest_FILES = Tweak.x
TTtest_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
