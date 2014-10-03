#!/bin/bash
# Setting up Webconverger system as root user
. /etc/webc/functions.sh
. /etc/webc/webc.conf


sub_literal() {
  awk -v str="$1" -v rep="$2" '
  BEGIN {
    len = length(str);
  }

  (i = index($0, str)) {
    $0 = substr($0, 1, i-1) rep substr($0, i + len);
  }

  1'
}

# Make /.git available for debugging and development
mount_git () {
	GIT_REPO=/live/image/live/filesystem.git

	# Sanity checks
	[ -d "$GIT_REPO" ] || return
	[ -d /live/overlay ] || return
	[ -n "$current_git_revision" ] || return


	mkdir /.git
	mount --bind "$GIT_REPO" /.git

	# Try to make /.git read-write, by simply remounting it, or by
	# using a second aufs. Note that mount will return success even
	# if the filesystem is still ro, so we test for writeability
	# using touch.
	if ! (mount -o remount,rw /.git && touch /.git 2> /dev/null)
	then
		# Sanity check
		if ! grep aufs /proc/filesystems > /dev/null; then
			umount /.git
			return
		fi


		# Overlay a second aufs over /.git. Even though
		# changes will be lost on reboots, you can still make
		# a change and push it out before the reboot. We can't
		# include this in the main aufs mount, since aufs
		# doesn't handle (bind)mounts in subdirectories.
		mkdir /live/git-overlay
		mount -o rw,noatime,mode=755 -t tmpfs tmpfs /live/git-overlay
		umount /.git
		mount -t aufs -o noatime,dirs=/live/git-overlay=rw:$GIT_REPO=rr aufs "/.git"
	fi

	# Make sure that HEAD corresponds to the commit
	# mounted by git-fs
	#
	# We don't do a normal (--mixed) reset, since
	# that also scans the entire working copy to
	# update the cached info in the index (which is
	# slow on git-fs / aufs). Instead, we reset HEAD
	# and the index separately.
	git --git-dir "/.git" reset --soft "$current_git_revision"

	# Reset the index
	git --git-dir "/.git" read-tree HEAD

	# Make sure that aufs doesn't forget about filename to inode
	# mappings, since that confuses git. git-fs should also be
	# mounted with the noforget option.
	mount -o remount,xino=/live/overlay/.aufs.xino /
}

process_options()
{

cmdline_has timezone && /etc/webc/timezone # process timezone=

# Create a Webconverger preferences to store dynamic FF options
cat > "$prefs" <<EOF
// This file is autogenerated based on cmdline options by live-config.sh. Do
// not edit this file, your changes will be overwritten on the next reboot!

EOF

# If printing support is not installed, prevent printing dialogs from being
# shown
if ! dpkg -s cups 2>/dev/null >/dev/null; then
	echo '// Print support not included, disable print dialogs' >> "$prefs"
	echo 'pref("print.always_print_silent", true);' >> "$prefs"
	echo 'pref("print.show_print_progress", false);' >> "$prefs"
fi

// https://github.com/Webconverger/webconverger-addon/issues/17
if cmdline_has showprintbutton
then
	echo 'pref("extensions.webconverger.showprintbutton", true);' >> "$prefs"
fi

# uncomment for run firefox fullscreen
#fullscreen="/etc/webc/extensions/webcfullscreen"
#test -e "$link" && rm -f "$link"
#ln -s "$fullscreen" "$link"

# start gnome-terminal
/usr/bin/gnome-terminal &

#noaddress="/etc/webc/extensions/webcnoaddressbar"
#ln -s "$noaddress" "$link"

for x in $( cmdline ); do
	case $x in

	debug)
		echo "webc ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
		mount_git
		;;

	widescrollbars)
		ln -s /etc/webc/extensions/scrollbars@kaply.com /opt/firefox/browser/extensions/
		;;

	grabdrag)
		ln -s /etc/webc/extensions/grabdrag '/opt/firefox/browser/extensions/{477c4c36-24eb-11da-94d4-00e08161165f}'
		;;

	support)
		echo '*/5 * * * * root /sbin/support' > /etc/cron.d/webc-support
		;;

	chrome=*)
		chrome=${x#chrome=}
		dir="/etc/webc/extensions/${chrome}"
		test -d $dir && {
			test -e "$link" && rm -f "$link"
			logs "switching chrome to ${chrome}"
			ln -s "$dir" "$link"
		}
		;;

	printer=*)
		systemctl unmask cups.service
		/etc/init.d/cups start
		IFS=, read -ra P <<< "${x#printer=}"
		P[0]=$(/bin/busybox httpd -d ${P[0]})
		P[1]=$(/bin/busybox httpd -d ${P[1]})
		P[2]=$(/bin/busybox httpd -d ${P[2]})
		logs "Printer name: ${P[0]}"
		logs "Printer device URI: ${P[1]}"
		logs "Printer driver URI: ${P[2]}"
		if [[ "${P[2]}" = http:* ]] 
		then
			t=$(tempfile)
			if curl -L -f "${P[2]}" > $t
			then
				lpadmin -p "${P[0]}" -E -v "${P[1]}" -i "$t" &&
				logs "Setup printer with PPD: lpadmin -p ${P[0]} -E -v ${P[1]} -i $t"
			else
				logs "Failed to download ${P[2]}, using generic.ppd"
				lpadmin -p "${P[0]}" -E -v "${P[1]}" -m drv:///sample.drv/generic.ppd
			fi
		else
			lpadmin -p "${P[0]}" -E -v "${P[1]}" -m "${P[2]}" &&
			logs "Setup printer with ${P[2]}: lpadmin -p ${P[0]} -E -v ${P[1]} -m ${P[2]}"
		fi
		;;

	hosts=*)
		hosts="$( /bin/busybox httpd -d ${x#hosts=} )"
			wget --timeout=5 "${hosts}" -O /etc/hosts
			if echo $hosts | grep -q whitelist
			then
				: > /etc/resolv.conf
			fi
		;;

	filter=*)
		# Not to be used in conjuction with hosts=
		# dns= trumps filter
		filter="$( /bin/busybox httpd -d ${x#filter=} )"
		IFS=',' read -ra F <<< "$filter"
		test "${F[1]}" && IP="${F[1]}"
		if ! test "${F[0]}" -a "$IP"
		then
			logs "ERROR: filter URL failed to be specified: ${F[0]},$IP"
		else
			logs Setting up filter: ${F[0]} with $IP
			curl -s "${F[0]}" | xzcat | awk -v ip="$IP" '{ print "address=/" $1 "/" ip }' >> /etc/dnsmasq.conf
			mv /etc/resolv.conf /etc/resolv.dnsmasq.conf
			echo "nameserver 127.0.0.1" > /etc/resolv.conf
			systemctl start dnsmasq.service
		fi
		;;

	whitelist=*)
		whitelist="$( /bin/busybox httpd -d ${x#whitelist=} )"
		echo 'pref("extensions.webconverger.whitelist", "'$whitelist'");' >> "$prefs"
		logs "Set whitelist: $whitelist"
		;;

	prefs=*)
		prefs="$( /bin/busybox httpd -d ${x#prefs=} )"
		echo "pref(\"autoadmin.global_config_url\",\"$prefs\");" >> /opt/firefox/mozilla.cfg
		logs "Set autoconfig: $prefs"
		;;

	iptables=*)
		options=$( /bin/busybox httpd -d ${x#iptables=} )

		if iptables $options
		then
			logs "OK iptables: $options"
		else
			logs "NOK iptables: $options"
		fi

		;;

	log=*)
		log=${x#log=}
		echo "*.*          @${log}" >> /etc/rsyslog.conf
		logs "Logging to ${log}"
		systemctl restart rsyslog.service
		;;

	locale=*)
		locale=${x#locale=}
		for i in /opt/firefox/langpacks/langpack-$locale*; do ln -s $i /opt/firefox/browser/extensions/$(basename $i); done
		echo "pref(\"general.useragent.locale\", \"${locale}\");" >> "$prefs"
		echo "pref(\"intl.accept_languages\", \"data:text/plain,intl.accept_languages=${locale}, en\");" >> "$prefs"
		;;

	cron=*)
		cron="$( echo ${x#cron=} | sed 's,%20, ,g' )"
		cat <<EOC > /etc/cron.d/webc-$RANDOM
SHELL=/bin/bash
PATH=/sbin:/bin:/usr/sbin:/usr/bin
$cron
EOC
		;;

	homepage=*)
		homepage="$( echo ${x#homepage=} | sed 's,%20, ,g' )"
		echo "browser.startup.homepage=$(echo $homepage | awk '{print $1}')" > /opt/firefox/browser/defaults/preferences/homepage.properties
		;;
	esac
done

# Make sure /home has noexec and nodev, for extra security.
# First, just try to remount, in case /home is already a separate filesystem
# (when using persistence, for example).
mount -o remount,noexec,nodev /home 2>/dev/null || (
	# Turn /home into a tmpfs. We use a trick here: after the mount, this
	# subshell will still have the old /home as its current directory, so
	# we can still read the files in the original /home. By passing -C to
	# the second tar invocation, it does a chdir, which causes it to end
	# up in the new filesystem. This enables us to easily copy the
	# existing files from /home into the new tmpfs.
	cd /home
	mount -o noexec,nodev -t tmpfs tmpfs /home
	tar -c . | tar -x -C /home
)

stamp=$( git show $webc_version | grep '^Date' )

test -f ${link}/content/about.xhtml.bak || cp ${link}/content/about.xhtml ${link}/content/about.xhtml.bak
cat ${link}/content/about.xhtml.bak |
sub_literal 'OS not running' "${webc_version} ${stamp}" |
sub_literal 'var aboutwebc = "";' "var aboutwebc = \"$(echo ${install_qa_url} | sed 's,&,&amp;,g')\";" > ${link}/content/about.xhtml

if cmdline_has dns
then
cat /etc/resolv.conf | sed '/nameserver/d' > /etc/resolv.conf.tmp

for i in $(cmdline_get dns)
do
	IFS=,; for dns in $i
	do
		echo nameserver $dns
	done
done >> /etc/resolv.conf.tmp

mv -f /etc/resolv.conf /etc/resolv.conf.old
mv -f /etc/resolv.conf.tmp /etc/resolv.conf
chmod 644 /etc/resolv.conf
fi


} # end of process_options

update_cmdline() {

	# Update $device
	. "/etc/webc/webc.conf"

	if curl -f -o /etc/webc/cmdline.tmp --retry 3 "$config_url?V=$webc_version&D=$device&K=$kernel"
	then
		# curl has a bug where it doesn't write an empty file
		touch /etc/webc/cmdline.tmp
		# This file can be empty in the case of an invalidated configuration
		mv /etc/webc/cmdline.tmp "$config_runtime"
		logs "CONFIG: Download applied $(md5sum $config_runtime)"
	else
		logs "CONFIG: Failed to download from $config_url"
	fi
}

# If we have a "cached" version of the configuration on disk,
# copy that to /etc/webc, so we can compare the new version with
# it to detect changes and/or use it in case the new download
# fails.
if test -s "$config_cached"
then
	cp "$config_cached" "$config_runtime"
	logs "CONFIG: Applied cache $(md5sum $config_runtime)"
else
	touch "$config_runtime"
	logs "CONFIG: No cache"
fi

# If there is a local config we need to re-run wireless now we have config in right place
/etc/webc/wireless

wait_for $live_config_pipe 2>/dev/null

. "/etc/webc/webc.conf"

cmdline_has debug && set -x

chmod 777 /etc/X11/xinit/xinitrc >> /home/webc/log.txt 2>&1

# Try to make /live/image writable
mount -o remount,rw /live/image

cmdline_has noconfig || update_cmdline
process_options

echo ACK > $live_config_pipe

# if writable
if touch /live/image
then
	# Cache cmdline in case subsequent boots can't reach $config_url
	cp "$config_runtime" "$config_cached"
	logs "CONFIG: cached $(md5sum $config_cached) $(tr '\n' ' ' < $config_cached)"

	# Kicks off an upgrade
	mkfifo $upgrade_pipe
else
# /live/image could not be made writable (e.g. live version: booting
# from an iso fs), so just use the new config downloaded
# and skip all the other stuff below
	logs "CONFIG: Not a writable boot medium. Could not cache configuration nor upgrade."
fi

# live-config should restart via systemd and get blocked
# until $live_config_pipe is re-created
