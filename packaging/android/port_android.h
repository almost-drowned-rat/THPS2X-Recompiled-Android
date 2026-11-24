/* SPDX-License-Identifier: GPL-3.0-or-later
 * port_android.h - THPS 2X Recompiled's names for the option-c Android template (templates/android;
 * 2026-11-24). Next to it the build script writes port_icon.h (assets/icon_64.bmp as a BMP array). */
#ifndef PORT_ANDROID_H
#define PORT_ANDROID_H

#define PORT_TAG              "THPS2X"
#define PORT_TITLE            "THPS 2X Recomp"
#define PORT_GAME_LIB         "libTHPS2X_game.so"
#define PORT_GAME_MAIN        "thps2x_game_main"      /* src/main.c on Android */
#define PORT_GAME_NAME        "THPS2X"
#define PORT_CONFIG_PKG       "thps2x_config"         /* only the dev lift test (loader.c LIFTTEST) */
#define PORT_MEDIA_ENV        "THPS_MEDIA_DIR"        /* src/main.c: the boot animation + the soundtracks */
#define PORT_TOUCH_NAME       "THPS 2X touch controls"
/* the lifted units are big (--split 1000): 3 parallel compiles on 8 GB phones */
#define PORT_LAUNCHER_JOBS    "3"

#define PORT_LAUNCHER_GAME    "THPS 2X"
#define PORT_LAUNCHER_DISC    "THPS 2X (USA)"           /* as the desktop launcher (launcher/main.c) */
#define PORT_TITLE_ID         0x41560001u
#define PORT_VERSIONS         { "USA", "469818E015AED2730641C0BDCBD2557D8A6B8BB4" },

#endif
