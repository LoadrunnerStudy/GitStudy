#!/bin/bash
. /etc/rc.d/init.d/functions
#set -e

hytmp=hy_test.txt
#echo_red() {
#	stty erase '^H'
#	echo -n -e "\033[31m$1\033[0m"
#}

#echo_red_enter() {
#	echo -e "\033[31m$1\033[0m"
#}

#echo_green() {
#	stty erase '^H'
#	echo -n -e "\033[32m$1\033[0m"
#}

#echo_green_enter() {
#	echo -e "\033[32m$1\033[0m"
#}

function clean_buffer(){

	echo 3 > /proc/sys/vm/drop_caches
}

function warning
{
	if [[ $# = 2 ]];then
		[[ "$1" = 0 ]] && action "$2" /bin/true || action "$2" /bin/false
	elif [[ $# = 1 ]];then
		icontent=$(cat $ERROR_LOG)
		if [[ -n "$icontent" ]];then
			action "$1" /bin/false && cat $ERROR_LOG >> $LOG && rm -rf $ERROR_LOG && exit
		else  
			action "$1" /bin/true
		fi
	fi
}

logdir=/tmp/hybrid_audit
mkdir -p $logdir
##网卡检测

#speed=`ethtool em1 | grep -i speed | awk '{print $2}'`
#num=${speed%M*}
#if [ $num != 1000 ]
#then
#	echo_red_enter "网卡不达标"
#	echo  "网卡速率: $speed"
	#exit 1
#fi
#echo "网卡速率: $speed"

##安装需要的测试工具
function pre_test {
	echo "安装相关测试工具: fio ncftp bc dig bind-utils wget " > $hytmp
	yum install fio ncftp bc dig bind-utils wget -y > /dev/null 2>&1
}

##系统检测
function os_version {
	os_version=`cat /etc/redhat-release`
	echo ${os_version} | grep -Ei "centos.*6.[0-9]|centos.*7.2" > /dev/null
	#warning $? "os version:         ${os_version}" 
	echo "os version(标准7.2):         ${os_version}" >> $hytmp	
}

##内核检测
function kernel_version {
	kernel_version=`uname -r`
	#warning $? "kernel version:     ${kernel_version}"
	echo  "kernel version:     ${kernel_version}"  >> $hytmp
}

##CPU检测
function cpu_audit {
	core_num=`cat /proc/cpuinfo  | grep "physical id" | wc -l`
	physical_num=`cat /proc/cpuinfo  | grep "physical id"  | awk '{print $4}' | sort | uniq | wc -l`
#	warning $? "cpu core_num:       ${core_num}"
#	warning $? "cpu physical_num:   ${physical_num}"
	echo "cpu core_num:       ${core_num}"  >> $hytmp
	echo "cpu physical_num:   ${physical_num}"  >> $hytmp
}

##内存检测
function mem_audit {
	MemTotal=`cat /proc/meminfo  | grep -i memtotal | awk '{print $2}'`
	MemTotal_MB=`echo ${MemTotal}/1024|bc`"MB"
	#warning $? "MemTotal:           ${MemTotal_MB}"
	echo "MemTotal:           ${MemTotal_MB}"	>> $hytmp

}

##网卡检测
function network_card {
	#if [[ `ip addr | awk '/inet/ && $2 ~ /\/24/{if($8 ~/^$/){print $7}else{print $8}}' | wc -l` == 1 ]];then
    #    Nic=`ip addr | awk '/inet/ && $2 ~ /\/24/{if($8 ~/^$/){print $7}else{print $8}}'`
    #    echo -e  "\033[32m测试的网卡设备名:\033[0m$Nic"
    #else
    #    echo_green_enter "网卡设备信息如下:"
    #    ip addr | awk '/inet/ && $2 ~ /\/24/{if($8 ~/^$/){printf("%-15s%s\n", $7, $2)}else{printf("%-15s%s\n", $8, $2)}}'
    #    echo_green "输入需要测试的网卡设备名:"
    #    read Nic
    #fi
	#[[ `ip a | grep  em1` ]] && Nic="em1" || Nic="eth0"
    Nic=`ip route | awk '/default/{print $5}'`
    echo -e  "测试的网卡设备名: $Nic"	>> $hytmp
	Duplex=`ethtool $Nic | grep Duplex  | awk '{print $2}'`
	Speed=`ethtool $Nic | grep Speed  | awk '{print $2}'`

	[[ $Duplex -eq 'Full' ]] && [[ `echo $Speed | awk -F'Mb/s' '{print $1}'` -ge 1000 ]]
	#warning $? "network card:       Duplex:${Duplex} Speed:${Speed}"
	echo "network card:       Duplex:${Duplex} Speed:${Speed}"	>> $hytmp


}

##网络质量检测
function network_quality {
	ping -c 10 -q 121.196.215.237 > ${logdir}/network_quality.log
	packet_loss=`cat ${logdir}/network_quality.log | awk 'NR==4 {print $6}'|sed 's/%//g'`
	rtt=`cat ${logdir}/network_quality.log  | awk -F"/| " 'NR==5 {if($11 ~/ms/) print $8}'`

	[[ ${packet_loss} -lt 30 ]] && [[ $(echo "$rtt < 200"|bc) -eq 1 ]]
#	warning $? "packet_loss,rtt:    ${packet_loss}% ${rtt}ms"
	echo "packet_loss,rtt:    ${packet_loss}% ${rtt}ms"	>> $hytmp

}

##DNS解析检测
function dns_resolver {
	dig www.fangcloud.com > ${logdir}/dns_resolver.log
	answer=`cat ${logdir}/dns_resolver.log | grep "ANSWER SECTION"`
	query_time=`cat ${logdir}/dns_resolver.log | grep "Query time" | awk '{print $4}'`

	#[[ $answer && ${query_time} -lt 100 ]]
	#warning $? "dns resolver:       ${query_time}msec"
	echo "dns resolver:       ${query_time}msec"	>> $hytmp

}

##wget下行速度测试
function web_download {
	echo ""	>> $hytmp
	echo "http下行速度测试:"	>> $hytmp
	url='http://121.40.206.120/hybrid_package/test.tar.gz'
	#url='http://speed.189.cn/upload/BSSAClientSetup9.exe'
	wget -o ${logdir}/web_download.log -O test.tar.gz $url
	tail -n 2 ${logdir}/web_download.log | awk 'NR==1 {print}'
	#download_speed=`tail -n 2 ${logdir}/web_download.log | awk -F" " '{print $3$4}'`
	#warning $? "下行速度:           ${download_speed}"
}

##ftp下行速度测试
function ftp_download {
	echo ""	>> $hytmp
	echo "ftp下行速度测试:"	>> $hytmp
	#ftp_address='121.196.215.237'
	ncftpget -u hybirdcloud -p jmWZ9T2pvd8LaY83 -P 10021 121.196.215.237 ./ test.tar.gz	>> $hytmp
}

##ftp上行速度测试
function ftp_upload {
	echo ""	>> $hytmp
	echo "ftp上行速度测试:"	>> $hytmp
	#ftp_address='121.196.215.237'
	begin=$(date +%s)
	date1=$(date)
	ncftpput -u hybirdcloud -p jmWZ9T2pvd8LaY83 -P 10021 121.196.215.237 / test.tar.gz
	end=$(date +%s)
	spend=$(expr $end - $begin)
	tar=330
	speed=`expr $tar / $spend`
	echo "$date1    put---test.tar.gz(330MB)  speed: $speed (MB/S)"	>> $hytmp

}

##磁盘吞吐量
function disk_throughput {
	echo ""	
	echo "磁盘吞吐量测试:"	
	echo "输入测试的设备对应的挂载点(默认:/srv/node/sdb1):"
	read devices
    echo "" >> $hytmp
    echo "磁盘吞吐量测试:"  >> $hytmp
    echo "输入测试的设备对应的挂载点(默认:/srv/node/sdb1):$device"	>>$hytmp

	[ $devices ] || devices=/srv/node/sdb1
 	export devices
	clean_buffer
	#i=2
	count=2
	printf '%-20s%-20s%s\n' "块大小" "时间" "写入速度"
	printf '%-20s%-20s%s\n' "块大小" "时间" "写入速度" >> $hytmp
	while [ 1 ]
	do
		#((j=1024/$i))
		((count=count+1))
		dd oflag=direct if=/dev/zero of=${devices}/test.log bs=64K count=65536 > ${logdir}/disk_rw.log 2>&1
		#cat /tmp/disk_rw.log
		second=`awk -F',| ' 'NR==3{print $7$8}' ${logdir}/disk_rw.log` 
		rw=`awk -F',| ' 'NR==3{print $10$11}' ${logdir}/disk_rw.log`
		printf '%-17s%-19s%s\n'     "64K" "$second"    "$rw"
		printf '%-17s%-19s%s\n'     "64K" "$second"    "$rw" >> $hytmp
		clean_buffer
		#((i=$i*2))
		if [ ${count} -ge 2 ]
		then
			break
		fi
		sleep 2
	done
	clean_buffer
}

##磁盘IOPS性能测试
function disk_iops {
	echo ""
	echo "磁盘IO测试:"
	echo "输入需要测试的block大小（默认:64K):"
    echo "" >> $hytmp
    echo "磁盘IO测试:" >> $hytmp
    echo "输入需要测试的block大小（默认:64K):" >> $hytmp

	read in_block
	[ $in_block ] || in_block=64K
	touch ${devices}/test.out1
	touch ${devices}/test.out2
	touch ${devices}/test.out3
	touch ${devices}/test.out4
	#fio -filename=/srv/node/sdb/fio.test -direct=1 -iodepth 1 -thread -rw=randrw -ioengine=psync -bs=64k -size=1G -numjobs=10 -runtime=1000 -group_reporting -name=mytest 
	#fio -filename=${devices}/fio1.test -direct=1 -rw=randrw -bs=4k -size=10g -numjobs=4 -runtime=1200 -group_reporting -name=test1
	echo "顺序读测试中......请等待"
	fio -filename=${devices}/test.out1 -direct=1 -rw=read -bs=${in_block} -size=1g -numjobs=4 -runtime=1200 -group_reporting -name=test1 >> ${logdir}/fio1.log
	block1=`grep 'bs=' ${logdir}/fio1.log | awk -F'=|-' 'NR==1{print $4}'`
	bw1=`cat ${logdir}/fio1.log | grep -E "^\s+read" | awk -F",|=" '{print $4}'`
	iops1=`cat ${logdir}/fio1.log | grep -E "^\s+read" | awk -F",|=" '{print $6}'`
	printf '%-15s%-15s%-15s%s\n' "block" "mode"   "bw"       "iops"
	printf '%-15s%-15s%-15s%s\n' "${block1}"    "read"   "${bw1}"   "${iops1}"
    printf '%-15s%-15s%-15s%s\n' "block" "mode"   "bw"       "iops"  >> $hytmp
    printf '%-15s%-15s%-15s%s\n' "${block1}"    "read"   "${bw1}"   "${iops1}"  >> $hytmp


	echo "顺序写测试中......请等待"
	fio -filename=${devices}/test.out2 -direct=1 -rw=write -bs=${in_block} -size=1g -numjobs=4 -runtime=1200 -group_reporting -name=test2 >> ${logdir}/fio2.log
	block2=`grep 'bs=' ${logdir}/fio2.log | awk -F'=|-' 'NR==1{print $4}'`
	bw2=`cat ${logdir}/fio2.log | grep -E "^\s+write" | awk -F",|=" '{print $4}'`
	iops2=`cat ${logdir}/fio2.log | grep -E "^\s+write" | awk -F",|=" '{print $6}'`
	printf '%-15s%-15s%-15s%s\n' "${block2}"    "write"   "${bw2}"   "${iops2}"
	printf '%-15s%-15s%-15s%s\n' "${block2}"    "write"   "${bw2}"   "${iops2}" >> $hytmp

	echo "随机读测试中......请等待"
	fio -filename=${devices}/test.out3 -direct=1 -rw=randread -bs=${in_block} -size=1g -numjobs=4 -runtime=1200 -group_reporting -name=test3 >> ${logdir}/fio3.log
	block3=`grep 'bs=' ${logdir}/fio3.log | awk -F'=|-' 'NR==1{print $4}'`
	bw3=`cat ${logdir}/fio3.log | grep -E "^\s+read" | awk -F",|=" '{print $4}'`
	iops3=`cat ${logdir}/fio3.log | grep -E "^\s+read" | awk -F",|=" '{print $6}'`
	printf '%-15s%-15s%-15s%s\n' "${block3}"    "randread"   "${bw3}"   "${iops3}"
    printf '%-15s%-15s%-15s%s\n' "${block3}"    "randread"   "${bw3}"   "${iops3}" >> $hytmp



	echo "随机写测试中......请等待"
	fio -filename=${devices}/test.out4 -direct=1 -rw=randwrite -bs=${in_block} -size=1g -numjobs=4 -runtime=1200 -group_reporting -name=test4 >> ${logdir}/fio4.log
	block4=`grep 'bs=' ${logdir}/fio4.log | awk -F'=|-' 'NR==1{print $4}'`
	bw4=`cat ${logdir}/fio4.log | grep -E "^\s+write" | awk -F",|=" '{print $4}'`
	iops4=`cat ${logdir}/fio4.log | grep -E "^\s+write" | awk -F",|=" '{print $6}'`
	printf '%-15s%-15s%-15s%s\n' "${block4}"    "randwrite"   "${bw4}"   "${iops4}"
    printf '%-15s%-15s%-15s%s\n' "${block4}"    "randwrite"   "${bw4}"   "${iops4}" >> $hytmp

	echo "最终结果:"
	printf '%-15s%-15s%-15s%s\n' "block" "mode"   "bw"       "iops"
	printf '%-15s%-15s%-15s%s\n' "${block1}"    "read"   "${bw1}"   "${iops1}"	 >> $hytmp
	printf '%-15s%-15s%-15s%s\n' "${block2}"    "write"   "${bw2}"   "${iops2}"		 >> $hytmp
	printf '%-15s%-15s%-15s%s\n' "${block3}"    "randread"   "${bw3}"   "${iops3}"	 >> $hytmp
	printf '%-15s%-15s%-15s%s\n' "${block4}"    "randwrite"   "${bw4}"   "${iops4}"		 >> $hytmp


}

function delete_test_file {
	[ -f test.tar.gz ] && rm -f test.tar.gz
	[ -f ${devices}/test.log ] && rm -f ${devices}/test.log
	[ -f ${devices}/test.out1 ] && rm -f ${devices}/test.out1
	[ -f ${devices}/test.out2 ] && rm -f ${devices}/test.out2
	[ -f ${devices}/test.out3 ] && rm -f ${devices}/test.out3
	[ -f ${devices}/test.out4 ] && rm -f ${devices}/test.out4
	rm -rf ${logdir}
	echo "测试完成！"
}

pre_test
os_version
kernel_version   
cpu_audit  
mem_audit  
network_card  
network_quality  
dns_resolver  
web_download  
ftp_upload
disk_throughput
disk_iops
delete_test_file
