# 编译器和编译选项
ifeq ($(CROSS_COMPILE),)
CROSS_COMPILE = /opt/gcc-ubuntu-9.3.0-2020.03-x86_64-aarch64-linux-gnu/bin/aarch64-linux-gnu-
export LD_LIBRARY_PATH=/opt/gcc-ubuntu-9.3.0-2020.03-x86_64-aarch64-linux-gnu/lib/x86_64-linux-gnu
endif

ifeq ($(TARGET_MODE),)
TARGET_MODE = release
endif

CC = ${CROSS_COMPILE}gcc
CXX = ${CROSS_COMPILE}g++
AR = ${CROSS_COMPILE}ar
AS = ${CROSS_COMPILE}as
LD = ${CROSS_COMPILE}ld
STRIP = ${CROSS_COMPILE}strip
RANLIB = ${CROSS_COMPILE}ranlib
OBJCOPY = ${CROSS_COMPILE}objcopy
OBJDUMP = ${CROSS_COMPILE}objdump
READELF = ${CROSS_COMPILE}readelf
NM = ${CROSS_COMPILE}nm

CFLAGS = -Wall -O2

# 目标文件名和依赖文件
TARGET_DISPLAY = display
TARGET_GET_EDID_RAW = get_edid_raw_data
TARGET_GET_HDMI_RES = get_hdmi_res
TARGET_PARSE_STD_TIMING = hobot_parse_std_timing

SRCS_DISPLAY = display.c lt8618_ioctl.c
SRCS_GET_EDID_RAW = get_edid.c
SRCS_GET_HDMI_RES = get_hdmi_res.c
SRCS_PARSE_STD_TIMING = hobot_parse_std_timing.c

OBJS_DISPLAY = $(SRCS_DISPLAY:.c=.o)
OBJS_GET_EDID_RAW = $(SRCS_GET_EDID_RAW:.c=.o)
OBJS_GET_HDMI_RES = $(SRCS_GET_HDMI_RES:.c=.o)
OBJS_PARSE_STD_TIMING = $(SRCS_PARSE_STD_TIMING:.c=.o)

# 共享库文件名
LIBLT8618 = liblt8618.so
# 第三方库和头文件路径
export SYSROOT_DIR=$(realpath ../../../deploy)/rootfs
LIB_DIR = -L../lib/ -L../lib/hbmedia -L../lib/aarch64-linux-gnu  -Wl,-rpath-link=../lib/ -L./
INCLUDE_DIR = -I../include/iar/ -I../include/vio/
LIB_DIR += -L${SYSROOT_DIR}/usr/lib/aarch64-linux-gnu -Wl,-rpath-link=${SYSROOT_DIR}/usr/lib/aarch64-linux-gnu/ --sysroot=${SYSROOT_DIR}

# 第三方库文件名
LIBS = -lhbmedia -lmultimedia -lisp -lisp_algo -liar -lvio -ltinyalsa -lm -lcjson

# 默认目标，编译可执行文件、共享库和 get_edid_raw_data
all: $(TARGET_DISPLAY) $(LIBLT8618) $(TARGET_GET_EDID_RAW) $(TARGET_GET_HDMI_RES) $(TARGET_PARSE_STD_TIMING)

# 编译规则
$(TARGET_DISPLAY): $(OBJS_DISPLAY)
	$(CC) $(CFLAGS) -o $@ $(OBJS_DISPLAY) $(LIB_DIR) $(LIBS)

$(LIBLT8618): lt8618_ioctl.o
	$(CC) $(CFLAGS) -shared -o $@ $<

$(TARGET_GET_EDID_RAW): $(OBJS_GET_EDID_RAW) lt8618_ioctl.o
	$(CC) $(CFLAGS) -o $@ $(OBJS_GET_EDID_RAW)  $(LIB_DIR) -llt8618

$(TARGET_GET_HDMI_RES): $(OBJS_GET_HDMI_RES) lt8618_ioctl.o
	$(CC) $(CFLAGS) -o $@ $(OBJS_GET_HDMI_RES)  $(LIB_DIR) -llt8618

$(TARGET_PARSE_STD_TIMING): $(OBJS_PARSE_STD_TIMING) lt8618_ioctl.o
	$(CC) $(CFLAGS) -o $@ $(OBJS_PARSE_STD_TIMING)  $(LIB_DIR) -llt8618

# 生成目标文件
%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $< $(INCLUDE_DIR)

# 清理生成的文件
clean:
	rm -f $(OBJS_DISPLAY) $(TARGET_DISPLAY) $(LIBLT8618) $(OBJS_GET_EDID_RAW) $(TARGET_GET_EDID_RAW) $(TARGET_GET_HDMI_RES) $(OBJS_PARSE_STD_TIMING) $(TARGET_GET_HDMI_RES) $(TARGET_PARSE_STD_TIMING)
