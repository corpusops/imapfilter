#!/usr/bin/env bash
# run all lua configs in configs, suitable for cron use
# apt-get install libpcre3-dev  liblua5.2-dev  liblua5.2
# make
if [ "x${CRON_DEBUG}" != "x" ];then
    set -x
fi
cd "$(dirname ${0})"
cwd=${PWD}
lock=${cwd}/.filter_lock
remote_lock=""
older_than="$((60*10))"
is_lxc() {
    echo  "$(cat -e /proc/1/environ |grep container=lxc|wc -l|sed -e "s/ //g")"
}

filter_host_pids() {
    if [ "x$(is_lxc)" != "x0" ];then
        echo "${@}"
    else
        for pid in ${@};do
            if [ "x$(grep -q lxc /proc/${pid}/cgroup 2>/dev/null;echo "${?}")" != "x0" ];then
                 echo ${pid}
             fi
         done
    fi
}

log() {
    echo "${@}" >&2
}
ps_etime() {
    ps -eo pid,comm,etime,args | perl -ane '@t=reverse(split(/[:-]/, $F[2])); $s=$t[0]+$t[1]*60+$t[2]*3600+$t[3]*86400;$cmd=join(" ", @F[3..$#F]);print "$F[0]\t$s\t$F[1]\t$F[2]\t$cmd\n"'
}

kill_old_crons() {
    # kill all stale synchronnise code jobs
    ps_etime|sort -n -k2|grep -E "imapfilter"|grep -v grep|while read psline;
    do
        seconds="$(echo "$psline"|awk '{print $2}')"
        pid="$(filter_host_pids $(echo $psline|awk '{print $1}'))"
        # 8 minutes
        if [ "x${pid}" != "x" ] && [ "${seconds}" -gt "${older_than}" ];then
            log "Something was wrong with last imapfilter crons, killing old sync processes: $pid"
            log "${psline}"
            kill -9 "${pid}"
        fi
    done
}

touch -d "-${older_than} seconds" "${lock}.time"
if [ -f ${lock} ];then
    oldlock=$(find "${lock}" \! -cnewer "${lock}.time" 2>/dev/null)
    if [ -e "${oldlock}" ];then
        remote_lock="1"
    fi
    numbers=$(filter_host_pids $(ps aux|grep imapfilter_cron.sh|grep -v grep|awk '{print $2}')|wc -l|awk '{print $1}')
    echo "$numbers"
    if [ "${numbers}" -lt "5" ];then
        remote_lock="1"
    fi
    if [ "x${remote_lock}" != "x" ];then
        kill_old_crons
        rm -f "${lock}"
    fi
fi
if [ -f ${lock} ];then
    log "${lock} existing, program locked out for new execution"
else
    touch "${lock}"
    cd $cwd/..
    while read config; do
        if [ "x${DEBUG}" != "x" ];then
            set -x
            ./src/imapfilter -c "${config}"
            set +x
        else
            ./src/imapfilter -c "${config}" >/dev/null 2>&1
        fi
    done < <( find -L configs \( -type f -or -type l \) -and -name "*.lua" )
    rm -f "${lock}"
fi
# vim:set et sts=4 ts=4 tw=80:
