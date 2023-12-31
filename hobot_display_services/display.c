#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <getopt.h>
#include <malloc.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "lt8618_ioctl.h"
#include <argp.h>
#include <asm/types.h>
#include <dlfcn.h>
#include <linux/fb.h>
#include <pthread.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/types.h>
#include "hb_vot.h"
// #include "iar_interface.h"
#include "iar_interface.h"
#include "hb_vio_interface.h"
#include <signal.h>
int log_level = 0;
#define LOG(fmt, ...)                                \
    do                                               \
    {                                                \
        if (log_level == 1)                          \
        {                                            \
            printf("LOG: " fmt "\n", ##__VA_ARGS__); \
        }                                            \
    } while (0)
void findAndWriteMode(const char *modesPath, const char *modePath, int width, int height, int rate);
#define MODES_FILE "/sys/class/graphics/fb0/modes"
#define MODE_FILE "/sys/class/graphics/fb0/mode"
char modeline[128] = {0};
struct DisplayMode
{
    char type;
    int width;
    int height;
    int rate;
};
void custom_signal_handler(int signo)
{
    int ret = 0;
    // ret = HB_VOT_DisableChn(0, 0);
    ret = HB_VOT_DisableChn(0, 2);
    if (ret)
        printf("HB_VOT_DisableChn failed.\n");

    ret = HB_VOT_DisableVideoLayer(0);
    if (ret)
        printf("HB_VOT_DisableVideoLayer failed.\n");

    ret = HB_VOT_Disable(0);
    if (ret)
        printf("HB_VOT_Disable failed.\n");
    printf("================test end====================\n");
}

struct arguments
{
    int mode;
    int edid_auto_detect;
    int hact;
    int vact;
    int hfp;
    int hbp;
    int vfp;
    int vbp;
    int hs;
    int vs;
    int clk_mhz;
    int server;
    int fb_width;
    int fb_height;
    int refresh_rate;
};

static char doc[] = "Userspace display service -- An service of display init";
static struct argp_option options[] = {
    {"mode", 'm', "MODE", 0, "0: HDMI(BT1120), 1: MIPI_DSI"},
    {"auto", 'a', "0/1", 0, "0: Display timing manually specified; 1: Display timing automatically obtained through EDID"},
    {"hact", 'h', "WIDTH", 0, "Screen Width"},
    {"vact", 'v', "HEIGHT", 0, "Screen Height"},
    {"hfp", 0x80, "DURATION", 0, "Horizontal Front Porch"},
    {"hbp", 0x81, "DURATION", 0, "Horizontal Back Porch"},
    {"hs", 0x82, "DURATION", 0, "Horizontal Sync Pulse"},
    {"vfp", 0x83, "DURATION", 0, "Vertical Front Porch"},
    {"vbp", 0x84, "DURATION", 0, "Vertical Back Porch"},
    {"vs", 0x85, "DURATION", 0, "Vertical Sync Pulse"},
    {"clk", 'c', "MHZ", 0, "Pixel Mhz"},
    {"server", 's', "VALUE", 0, "Whether it is a server environment"},
    {"log", 'l', "LEVEL", 0, "Log level,set 1 to print more infomation"},
    {"fb_width", 0x87, "WIDTH", 0, "fb width"},
    {"fb_height", 0x86, "HEIGHT", 0, "fb height"},
    {"refresh_rate", 'r', "HZ", 0, "fb fresh rate"},
    {0}};
static error_t parse_opt(int key, char *arg, struct argp_state *state)
{

    struct arguments *args = state->input;
    switch (key)
    {
    case 'm':
        args->mode = atoi(arg);
        break;
    case 'a':
        args->edid_auto_detect = atoi(arg);
        break;
    case 'h':
        args->hact = atoi(arg);
        break;
    case 'v':
        args->vact = atoi(arg);
        break;
    case 0x80:
        args->hfp = atoi(arg);
        break;
    case 0x81:
        args->hbp = atoi(arg);
        break;
    case 0x82:
        args->hs = atoi(arg);
        break;
    case 0x83:
        args->vfp = atoi(arg);
        break;
    case 0x84:
        args->vbp = atoi(arg);
        break;
    case 0x85:
        args->vs = atoi(arg);
        break;
    case 'c':
        args->clk_mhz = atoi(arg);
        break;
    case 's':
        args->server = atoi(arg);
        break;
    case 'l':
        log_level = atoi(arg);
        break;
    case 0x86:
        args->fb_height = atoi(arg);
        break;
    case 0x87:
        args->fb_width = atoi(arg);
        break;
    case 'r':
        args->refresh_rate = atoi(arg);
        break;
    default:
    {
        // argp_state_help(state, stdout, ARGP_HELP_STD_HELP);
        return ARGP_ERR_UNKNOWN;
    }
    }
    return 0;
}
static struct argp argp = {options, parse_opt, 0, doc};
int main(int argc, char **argv)
{
    if (signal(SIGINT, custom_signal_handler) == SIG_ERR)
    {
        perror("Unable register signal handler\n");
        return 1;
    }
    struct arguments args;

    int ret;
    int i = 0;
    hdmi_timing_t iar_timing = {0};

    VOT_VIDEO_LAYER_ATTR_S stLayerAttr;
    VOT_CHN_ATTR_S stChnAttr;
    VOT_CROP_INFO_S cropAttrs;
    VOT_PUB_ATTR_S devAttr;
    VOT_CHN_ATTR_EX_S stChnAttrEx = {};
    hdmi_timing_t hdmi_timing;
    memset(&args, 0, sizeof(args));
    argp_parse(&argp, argc, argv, 0, 0, &args);
    if (args.mode == 0)
    {
        lt8618_ioctl_init();
        memset(&hdmi_timing, 0, sizeof(hdmi_timing));

        if (args.edid_auto_detect == 1)
        {
            ret = lt8618_get_edid_resolution_ratio((hdmi_timing_t *)&hdmi_timing);
            LOG("main ret = %d, data.hfp = %d,data.hs=%d,data.hbp = %d,data.hact=%d,data.htotal = %d,data.vfp=%d,data.vs = %d,data.vbp=%d,data.vact=%d,data.vtotal=%d,data.vic=%d,data.pic_ratio=%d,data.clk=%d\n",
                ret, hdmi_timing.hfp, hdmi_timing.hs, hdmi_timing.hbp, hdmi_timing.hact, hdmi_timing.htotal, hdmi_timing.vfp, hdmi_timing.vs, hdmi_timing.vbp, hdmi_timing.vact, hdmi_timing.vtotal, hdmi_timing.vic, hdmi_timing.pic_ratio, hdmi_timing.clk);

            hdmi_timing.auto_detect = 1;
        }
        else
        {
            hdmi_timing.auto_detect = 0;
            hdmi_timing.hact = args.hact;
            hdmi_timing.vact = args.vact;
            hdmi_timing.hfp = args.hfp;
            hdmi_timing.hbp = args.hbp;
            hdmi_timing.vfp = args.vfp;
            hdmi_timing.vbp = args.vbp;
            hdmi_timing.hs = args.hs;
            hdmi_timing.vs = args.vs;
            hdmi_timing.htotal = hdmi_timing.hfp + hdmi_timing.hact + hdmi_timing.hs + hdmi_timing.hbp;
            hdmi_timing.vtotal = hdmi_timing.vfp + hdmi_timing.vact + hdmi_timing.vs + hdmi_timing.vbp;
            hdmi_timing.clk = args.clk_mhz;
            hdmi_timing.vic = 0;
            hdmi_timing.pic_ratio = 0;
        }

        devAttr.enIntfSync = VO_OUTPUT_USER;
        devAttr.u32BgColor = 16744328;
        devAttr.enOutputMode = HB_VOT_OUTPUT_BT1120;
        memset(&iar_timing, 0, sizeof(iar_timing));
        if (args.fb_width != 0 && args.fb_height != 0 && args.refresh_rate != 0)
        {
            findAndWriteMode(MODES_FILE, MODE_FILE, args.fb_width, args.fb_height, args.refresh_rate);
            int fb_fd = open("/dev/fb0", O_RDWR);

            if (fb_fd == -1)
            {
                perror("Error opening framebuffer device");
                exit(EXIT_FAILURE);
            }

            struct fb_var_screeninfo var;

            if (ioctl(fb_fd, FBIOGET_VSCREENINFO, &var))
            {
                perror("Error reading variable information");
                close(fb_fd);
                exit(EXIT_FAILURE);
            }
            iar_timing.hfp = var.right_margin;
            iar_timing.hbp = var.left_margin;
            iar_timing.vfp = var.lower_margin;
            iar_timing.vbp = var.upper_margin;
            iar_timing.hs = var.hsync_len;
            iar_timing.vs = var.vsync_len;
            iar_timing.clk = 100000000 / var.pixclock;
            iar_timing.hact = var.xres;
            iar_timing.vact = var.yres;
        }
        else
            memcpy(&iar_timing, &hdmi_timing, sizeof(hdmi_timing_t));
    }
    else
    {
        /**
         * TODO: Add mipi dsi
         *
         */
        ;
    }
    devAttr.stSyncInfo.pixel_clk = iar_timing.clk * 10000;
    devAttr.stSyncInfo.hbp = iar_timing.hbp;
    devAttr.stSyncInfo.hfp = iar_timing.hfp;
    devAttr.stSyncInfo.hs = iar_timing.hs;
    devAttr.stSyncInfo.vbp = iar_timing.vbp;
    devAttr.stSyncInfo.vfp = iar_timing.vfp;
    devAttr.stSyncInfo.vs = iar_timing.vs;
    devAttr.stSyncInfo.width = iar_timing.hact;
    devAttr.stSyncInfo.height = iar_timing.vact;
    ret = HB_VOT_SetPubAttr(0, &devAttr);
    if (ret)
    {
        printf("HB_VOT_SetPubAttr failed\n");

        return -1;
    }
    ret = HB_VOT_Enable(0);
    if (ret)
        printf("HB_VOT_Enable failed.\n");
    memset(&stLayerAttr, 0, sizeof(stLayerAttr));
    // json output
    stLayerAttr.stImageSize.u32Width = iar_timing.hact;
    stLayerAttr.stImageSize.u32Height = iar_timing.vact;

    stLayerAttr.panel_type = 1;
    stLayerAttr.rotate = 0;
    stLayerAttr.dithering_flag = 0;
    stLayerAttr.dithering_en = 0;
    stLayerAttr.gamma_en = 0;
    stLayerAttr.hue_en = 0;
    stLayerAttr.sat_en = 0;
    stLayerAttr.con_en = 0;
    stLayerAttr.bright_en = 0;
    stLayerAttr.theta_sign = 0;
    stLayerAttr.contrast = 0;
    stLayerAttr.theta_abs = 0;
    stLayerAttr.display_addr_type = 3;
    stLayerAttr.saturation = 0;
    stLayerAttr.off_contrast = 0;
    stLayerAttr.off_bright = 0;
    stLayerAttr.user_control_disp = 1;
    stLayerAttr.big_endian = 0;
    LOG("main ret = %d, data.hfp = %d,data.hs=%d,data.hbp = %d,data.hact=%d,data.htotal = %d,data.vfp=%d,data.vs = %d,data.vbp=%d,data.vact=%d,data.vtotal=%d,data.vic=%d,data.pic_ratio=%d,data.clk=%d\n",
        ret, iar_timing.hfp, iar_timing.hs, iar_timing.hbp, iar_timing.hact, iar_timing.htotal, iar_timing.vfp, iar_timing.vs, iar_timing.vbp, iar_timing.vact, iar_timing.vtotal, iar_timing.vic, iar_timing.pic_ratio, iar_timing.clk);
    ret = HB_VOT_SetVideoLayerAttr(0, &stLayerAttr);
    if (ret)
        printf("HB_VOT_SetVideoLayerAttr failed.\n");

    ret = HB_VOT_EnableVideoLayer(0);
    if (ret)
        printf("HB_VOT_EnableVideoLayer failed.\n");

    /**
     * NOTE: It seems that the width needs to be aligned by 8, the height must be aligned by 2, and rounded up.
     *
     */
    stChnAttr.u32Priority = 0;
    stChnAttr.s32X = 0;
    stChnAttr.s32Y = 0;
    stChnAttr.u32SrcWidth = iar_timing.hact; // aligned by 8, rounded up
    stChnAttr.u32SrcHeight = iar_timing.vact;
    stChnAttr.u32DstWidth = iar_timing.hact;
    stChnAttr.u32DstHeight = iar_timing.vact;
    ret = HB_VOT_SetChnAttr(0, 2, &stChnAttr);
    stChnAttr.u32Priority = 2;
    stChnAttr.u32SrcWidth = iar_timing.hact;
    stChnAttr.u32SrcHeight = iar_timing.vact;
    stChnAttr.u32DstWidth = iar_timing.hact;
    stChnAttr.u32DstHeight = iar_timing.vact;
    ret |= HB_VOT_SetChnAttr(0, 0, &stChnAttr);
    printf("HB_VOT_SetChnAttr 0: %d\n", ret);

    cropAttrs.u32Width = iar_timing.hact;
    cropAttrs.u32Height = iar_timing.vact;
    ret = HB_VOT_SetChnCrop(0, 0, &cropAttrs);
    ret |= HB_VOT_SetChnCrop(0, 2, &cropAttrs);
    printf("HB_VOT_SetChnCrop: %d\n", ret);

    stChnAttrEx.alpha_en = 1;
    stChnAttrEx.alpha_sel = 0;
    stChnAttrEx.alpha = 255;
    stChnAttrEx.format = 3; // NOTE
    ret = HB_VOT_SetChnAttrEx(0, 2, &stChnAttrEx);

    ret = HB_VOT_EnableChn(0, 2);
    // if (args.server == 0)
    ret |= HB_VOT_EnableChn(0, 0);

    printf("HB_VOT_EnableChn: %d\n", ret);

    if (args.server == 1)
    {
        hdmi_timing.auto_detect = 0;
        hdmi_timing.clk *= 10000;
        if (args.fb_width != 0 && args.fb_height != 0 && args.refresh_rate != 0)
        {
            ;
            ;
        }
        else
        {
            ret = lt8618_set_hdmi_timing(&hdmi_timing);
            if (ret)
            {
                printf("lt8618_set_hdmi_timing failed!,ret:%d\n", ret);
            }
        }
    }
    if (args.mode == 0)
    {
        lt8618_ioctl_deinit();
    }
    if (args.fb_width != 0 && args.fb_height != 0 && args.refresh_rate != 0)
    {
        system(modeline);
    }
    if(args.server != 1){
        LOG("retarting...\n");
        system("systemctl --quiet restart lightdm.service");
    }
    pause();

    return 0;
}

void findAndWriteMode(const char *modesPath, const char *modePath, int width, int height, int rate)
{
    FILE *modesFile = fopen(modesPath, "r");
    FILE *modeFile = fopen(modePath, "w");

    if (modesFile == NULL || modeFile == NULL)
    {
        perror("Error opening files");
        exit(EXIT_FAILURE);
    }
    if (width == 0 || height == 0 || rate == 0)
        return;
    char line[256];
    struct DisplayMode displayMode;

    while (fgets(line, sizeof(line), modesFile) != NULL)
    {

        if (sscanf(line, "%c:%dx%dp-%d", &displayMode.type, &displayMode.width, &displayMode.height, &displayMode.rate) == 4)
        {

            if (displayMode.width == width && displayMode.height == height && displayMode.rate == rate)
            {

                fprintf(modeFile, "%c:%dx%dp-%d\n", displayMode.type, displayMode.width, displayMode.height, displayMode.rate);
                snprintf(modeline, sizeof(modeline), "echo %c:%dx%dp-%d > /sys/class/graphics/fb0/mode", displayMode.type, displayMode.width, displayMode.height, displayMode.rate);
                break;
            }
        }
    }

    fclose(modesFile);
    fclose(modeFile);
}