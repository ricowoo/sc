#!/bin/sh
#
# Script to start CPU limit daemon
#
set -e

case "$1" in
start)
if [ $(ps -eo pid,args | gawk '$3=="/root/cpulimit_daemon.sh"  {print $1}' | wc -l) -eq 0 ]; then
    nohup /root/cpulimit_daemon.sh >/dev/null 2>&1 &
    ps -eo pid,args | gawk '$3=="/root/cpulimit_daemon.sh"  {print}' | wc -l | gawk '{ if ($1 == 1) print " * cpulimit daemon started successfully"; else print " * cpulimit daemon can not be started" }'
else
    echo " * cpulimit daemon can't be started, because it is already running"
fi
;;
stop)
CPULIMIT_DAEMON=$(ps -eo pid,args | gawk '$3=="/root/cpulimit_daemon.sh"  {print $1}' | wc -l)
CPULIMIT_INSTANCE=$(ps -eo pid,args | gawk '$2=="cpulimit" {print $1}' | wc -l)
CPULIMIT_ALL=$((CPULIMIT_DAEMON + CPULIMIT_INSTANCE))
if [ $CPULIMIT_ALL -gt 0 ]; then
    if [ $CPULIMIT_DAEMON -gt 0 ]; then
        ps -eo pid,args | gawk '$3=="/root/cpulimit_daemon.sh"  {print $1}' | xargs kill -9   # kill cpulimit daemon
    fi

    if [ $CPULIMIT_INSTANCE -gt 0 ]; then
        ps -eo pid,args | gawk '$2=="cpulimit" {print $1}' | xargs kill -9                    # release cpulimited process to normal priority
    fi
    ps -eo pid,args | gawk '$3=="/root/cpulimit_daemon.sh"  {print}' | wc -l | gawk '{ if ($1 == 1) print " * cpulimit daemon can not be stopped"; else print " * cpulimit daemon stopped successfully" }'
else
    echo " * cpulimit daemon can't be stopped, because it is not running"
fi
;;
restart)
$0 stop
sleep 3
$0 start
;;
status)
ps -eo pid,args | gawk '$3=="/root/cpulimit_daemon.sh"  {print}' | wc -l | gawk '{ if ($1 == 1) print " * cpulimit daemon is running"; else print " * cpulimit daemon is not running" }'
;;
esac
exit 0
