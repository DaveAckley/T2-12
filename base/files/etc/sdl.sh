#!/bin/bash
export SDL_VIDEODRIVER=fbcon
export SDL_FBDEV=/dev/fb0
if [[ -e /dev/input/touchscreen ]]; then
	export SDL_MOUSEDRV=TSLIB
	export SDL_MOUSEDEV=/dev/input/touchscreen
fi
