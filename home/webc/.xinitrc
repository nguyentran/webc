. /etc/webc/functions.sh
. /etc/webc/webc.conf

if cmdline_has debug
then
	/etc/webc/logbot.sh bash -x /etc/webc/webc.sh
else
	bash /etc/webc/webc.sh
fi
