#!/bin/bash
# Usage:
#  bash <(curl -s https://raw.githubusercontent.com/mixool/script/master/wget.sh)
#  wget --no-check-certificate https://raw.githubusercontent.com/mixool/script/master/wget.sh && chmod +x wget.sh && ./wget.sh
#  Total download depends on MBlimit, precision depends on url, speed depends on Url, use parameters or change them if necessary. 

# Set MBlimit Alicdn url Url default
MBlimit=1024
url=https://speedtest.lv.buyvm.net/1000MB.test
Url=https://speedtest.ny.buyvm.net/1000MB.test

# User-Agent
UA="Mozilla/5.0 (Linux; Android 9; Nokia X6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/72.0.3626.121 Mobile Safari/537.36"

# Pre-processing MBlimit|via
MBlimit=$(awk 'BEGIN{printf "%.f\n",('$MBlimit'*1024*1024)}')
via="Alicdn"

#Set [MBlimit|Url|url] by parameters. Usage: bash wget.sh 512 yd
while [[ $# > 0 ]];do
	if grep '^[1-9][0-9]*$' <<< "$1" >/dev/null;then
		MBlimit=$(awk 'BEGIN{printf "%.f\n",('$1'*1024*1024)}')
		shift
	fi
	case $1 in
	lt|cu|LT|CU)
		#China Unicom url Url
		url=http://partner.iread.wo.com.cn/wonderfulapp/10118/apps/yuexianghui.apk
		Url=http://iread.wo.com.cn/download/channelclient/113/624/woreader_28000000.apk
		via="China Unicom"
	;;
	yd|cm|YD|CM)
		#China Mobile url Url
		url=http://dlrcs.fetion-portal.com/mobile/RCS_V6.2.8.0129_20190130.apk
		Url=http://wlanwm.12530.com/newcms/quku/fbpt_rsync_apps/local/signed/MobileMusic671/MobileMusic671_014000D.apk
		via="China Mobile"
	;;
	dx|ct|DX|CT)
		#China Telecom url Url
		url=http://189newestmailclient.oos-sh.ctyunapi.cn/189mail.apk
		Url=http://www.189.cn/down/CtClientL.ap
		via="China Telecom"
	;;
    	esac
    	shift
done

main(){
	length=$(wget --spider -U "$UA"  -T 3 -t 3 $url -SO- /dev/null 2>&1 | grep -oE "Content-Length: [0-9]+" | grep -oE "[0-9]+")
	Length=$(wget --spider -U "$UA"  -T 3 -t 3 $Url -SO- /dev/null 2>&1 | grep -oE "Content-Length: [0-9]+" | grep -oE "[0-9]+")
	if [ $length -gt 100000 -a $Length -gt 100000 ] >/dev/null 2>&1; then
		t=$(awk 'BEGIN{printf int('$MBlimit'%'$Length'/'$length')}')
		T=$(awk 'BEGIN{printf int('$MBlimit'/'$Length')}')
	else
	echo Error...
	echo `wget --spider -U "$UA" -T 3 -t 1 $url`
	echo `wget --spider -U "$UA" -T 3 -t 1 $Url`
	exit 1
	fi

	echo $(date) Mission $(awk 'BEGIN{printf "%.f\n",('$MBlimit'/1024/1024)}') MB via $via. Starting \($t  $T\) ...

	if [ "$t" -gt 0 ]; then
		echo $(date) $(echo $url | awk -F"/" '{print $NF}') - $(awk 'BEGIN{printf "%.1f\n",('$length'/1024/1024)}') MB will be downloaded $t times...
		for((i = 1; i <= t; i++))
		do
			s=$(wget -U "$UA" -SO- $url 2>&1 >/dev/null | grep -E "written to stdout" | awk -F"[written]" '{print $1}')
			echo $s $i - $(awk 'BEGIN{printf "%.1f\n",('$i'*'$length'/1024/1024)}') MB
		done
	fi

	if [ "$T" -gt 0 ]; then
		echo $(date) $(echo $Url | awk -F"/" '{print $NF}') - $(awk 'BEGIN{printf "%.1f\n",('$Length'/1024/1024)}') MB will be downloaded $T times...
		for((j = 1; j <= T; j++))
		do
			S=$(wget -U "$UA" -SO- $Url 2>&1 >/dev/null | grep -E "written to stdout" | awk -F"[written]" '{print $1}')
			echo $S $j - $(awk 'BEGIN{printf "%.1f\n",('$j'*'$Length'/1024/1024)}') MB
		done
	fi
	
	FMB=$(awk 'BEGIN{printf "%.2f\n",(('$MBlimit'-('$MBlimit'%'$Length'%'$length'))/1024/1024)}')
	FGB=$(awk 'BEGIN{printf "%.3f\n",(('$MBlimit'-('$MBlimit'%'$Length'%'$length'))/1024/1024/1024)}')
	echo $(date) Mission $(awk 'BEGIN{printf "%.f\n",('$MBlimit'/1024/1024)}') MB. Accomplished $FMB MB \($FGB GB\). Thanks!
}

main
