#!/bin/bash

Xvnc :1 -desktop debian:1 -auth /root/.Xauthority -g
eometry 1024x768 -depth 16 -rfbwait 30000 -rfbauth /root/.vnc/passwd -rfbport 59
01 -pn -fp /usr/X11R6/lib/X11/fonts/Type1/,/usr/X11R6/lib/X11/fonts/Speedo/,/usr
/X11R6/lib/X11/fonts/misc/,/usr/X11R6/lib/X11/fonts/75dpi/,/usr/X11R6/lib/X11/fo
nts/100dpi/,/usr/share/fonts/X11/misc/,/usr/share/fonts/X11/Type1/,/usr/share/fo
nts/X11/75dpi/,/usr/share/fonts/X11/100dpi/ -co /etc/X11/rgb

