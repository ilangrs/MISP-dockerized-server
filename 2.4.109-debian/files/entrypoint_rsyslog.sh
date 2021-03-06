#!/bin/sh
set -eu

NC='\033[0m' # No Color
Light_Green='\033[1;32m'  
STARTMSG="[ENTRYPOINT_RSYSLOG]"
# Syslog is used remove the color options!
[ "${LOG_SYSLOG_ENABLED-}" = "no" ] && STARTMSG="${Light_Green}$STARTMSG${NC}"


ARCHIVE_YEAR="$(date +%Y)"
ARCHIVE_FOLDER="/var/www/MISP/app/files/DCSO/log_archive/$ARCHIVE_YEAR/"
TMP_ARCHIVE="$(date +%Y-%m-%d)"
ARCHIVE_FILE="/tmp/$TMP_ARCHIVE.tar"
# Functions
echo (){
    command echo "$STARTMSG $*"
}

func_archive_old_logs(){
    #echo "... ... Archive: $*"
    for i in "$@"
    do
        [ -f "$i" ] && tar -rf "$ARCHIVE_FILE" "$i" && rm -f "$i"
    done
    # Any is done
    sleep 0.1
}


#
#   MAIN
#


# delete old logs
DELETE_LOG=${LOGGING_DELETE_OLD_LOGS:-"yes"}
if [ "$DELETE_LOG" = "yes" ] 
then
    echo "Archive old logs..."
        # Archive Files
    func_archive_old_logs /var/www/MISP/app/tmp/logs/*
    func_archive_old_logs /var/log/apache2/*
        # End Target
    [ ! -d "$ARCHIVE_FOLDER" ] && mkdir -p "$ARCHIVE_FOLDER"
        # Move Archive
    [ -f "$ARCHIVE_FILE" ] && gzip "$ARCHIVE_FILE" 
    [ -f "$ARCHIVE_FILE.gz" ] && mv "$ARCHIVE_FILE.gz" "$ARCHIVE_FOLDER/"
    echo "Archive old logs...finished"
fi

# write supervisord configuration
cat << EOF > /etc/rsyslog.d/rsyslog_custom.conf
# https://www.slideshare.net/rainergerhards1/using-wildcards-with-rsyslogs-file-monitor-imfile
module(load="imfile" PollingInterval="10") #needs to be done just once


# Apache2
#input (type="imfile" Tag="apache.info" File="/var/log/apache2/access.log" Severity="info") # Reason: We got Access logs from NIGNX.
input (type="imfile" Tag="apache.info" File="/var/log/apache2/other_vhosts_access.log" Severity="info")
input (type="imfile" Tag="apache.error" File="/var/log/apache2/error.log" Severity="error")
# MISP
input (type="imfile" Tag="misp.error" File="/var/www/MISP/app/tmp/logs/error.log" Severity="error")
# Cake
input (type="imfile" Tag="worker.error" File="/var/www/MISP/app/tmp/logs/resque-worker-error.log" Severity="error")
input (type="imfile" Tag="scheduler.error" File="/var/www/MISP/app/tmp/logs/resque-scheduler-error.log" Severity="error")
input (type="imfile" Tag="resque.debug" File="/var/www/MISP/app/tmp/logs/resque-*.log" Severity="debug")
# ZeroMQ
input (type="imfile" Tag="mispzmq.info" File="/var/www/MISP/app/tmp/logs/mispzmq.log" Severity="info")
input (type="imfile" Tag="mispzmq.error" File="/var/www/MISP/app/tmp/logs/mispzmq.error.log" Severity="error")


if ( \$syslogtag contains 'error' or \$syslogtag contains 'emerg' ) then {
    action(type="omfile" file="/dev/stderr")
}

if ( \$syslogtag contains "info" or \$syslogtag contains "debug" or \$syslogtag contains '*' ) then {
    action(type="omfile" file="/dev/stdout")
}

EOF

# Start rsyslogd in debug mode in foreground
echo "Start rsyslogd" && rsyslogd -n
