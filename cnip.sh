#!/bin/bash
rm -f delegated-apnic-latest blackcn_`date +%F`.conf && wget http://ftp.apnic.net/apnic/stats/apnic/delegated-apnic-latest

awk -F\| '/CN\|ipv4/ { printf("%s %s/%d%s\n","allow",$4, 32-log($5)/log(2), ";") }' delegated-apnic-latest > blackcn_`date +%F`.conf && \
rm -f /root/blackcn.conf && \
ln -s $PWD/blackcn_`date +%F`.conf /root/blackcn.conf
