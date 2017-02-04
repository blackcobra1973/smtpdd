#!/bin/bash

MSMTP="/usr/bin/msmtp"
TMPDIR="/var/tmp/smtpdd"
TMPFILENAME="mailqfile.$RANDOM.`date +%s`.$$"
LOCKFILE="$1/.smtpdd.lck"
RUNT=0

EX_TEMPFAIL=75

printUsage()
{
  echo "Usage: `basename $0` queue-directory sender recipient hostname|ip:port:mode [hostname|ip:port:mode ...]"
  echo "     : `basename $0` queue-directory qrun";
  echo "Where mode is q for queuing delivery, d for just drop it or o to just queue the mail - defaults to q"
}

attemptDelivery()
{
  qd=$1
  mail=$2
  host=`basename $1`

  from=`cat $mail|cut -f 1 -d " "`
  to=`cat $mail|cut -f 2 -d " "`

  hostname=`echo $host|cut -f 1 -d :`
  port=`echo $host|cut -f 2 -d :`

  if [ ! -f $mail.body ]
  then
    echo "Cannot delivery mail, mail body is missing"
    exit $EX_TEMPFAIL
  fi

  #echo "attmpting delivery of $2 from $1 as $from and $to to host $hostname with port $port"
  $MSMTP --host $hostname --port $port -f $from $to < $mail.body
  if [ $? == 0 ]
  then
    echo "Message delivered, deleting"
    rm -f $mail $mail.body
  else
    echo "Message delivery failed, leaving in place"
  fi
}

queueRun()
{
  for dirs in $1/*
  do
    if [ -d $dirs ]
    then
      old_pwd=$PWD
      cd $dirs
      for mail in *.qf
      do
        if [ -f $mail ]
        then
          attemptDelivery "$dirs" "$mail"
        fi
      done
      cd $old_pwd
    fi
  done
}

mainRun()
{
  if [ ! -d $TMPDIR ]
  then
    mkdir $TMPDIR
    if [ $? != 0 ]
    then
      echo "Tempdirectory configuration problem with $TMPDIR - cannot create directory"
      logger -p mail.error -t smtpdd "Temp directory configuration problem with $TMPDIR - cannot create directory"
      exit $EX_TEMPFAIL
    fi
  fi

  chmod 0700 $TMPDIR

  queuedir=$1
  from=$2
  to=$3

  if [[ $RUNT == 0 ]]
  then
    cat > $TMPDIR/$TMPFILENAME
    RUNT=1
  fi

  for host in ${@:4}
  do
    if [[ $host != *@* ]]
    then
      #echo "attempting $2 to $3 for $host"

      hostname=`echo $host|cut -f 1 -d :`
      port=`echo $host|cut -f 2 -d :`
      mode=`echo $host|cut -f 3 -d :`
      if [ "x$mode" == "x" ]
      then
              mode="q"
      fi

      queueit="no"

      logger -p mail.info -t smtpdd "Attempting delivery of mail from $2 to $3 for host $hostname on $port with mode of $mode"

      if [ "$mode" != "o" ]
      then
        # attempt real delivery
        $MSMTP --host $hostname --port $port -f $from $to < $TMPDIR/$TMPFILENAME > /dev/null 2>&1
        RET=$?
        if [ $RET != 0 ]
        then
          if [ $RET != "75" ]
          then
            logger -p mail.info -t smtpdd "Mail delivery for $3 has failed"
            echo "Mail delivery for $3 has failed (unknown user?)"
            break
          fi
          # we failed to deliver ....
          # in queue mode, we deliver to the queue
          if [ "$mode" == "q" ]
          then
            #echo "Delivery of mail to $hostname on $port from $from to $to has failed, but will be queued ($RET)"
            logger -p mail.warning -t smtpdd "Delivery of mail to $hostname on $port from $from to $to has failed, but will be queued ($RET)"
            queueit="yes"
          fi

          # delete mode
          if [ "$mode" == "d" ]
          then
            logger -p mail.info -t smtpdd "Delivery of mail to $hostname on $port from $from to $to has failed and will not be re-tried (delete mode)"
            randomtext="asdf"
          fi
        else
          logger -p mail.info -t smtpdd "Delivery of mail to $hostname on $port from $from to $to has succeeded"
          randomtext="asdf"
        fi
      else
        echo "In queue only mode, will queue"
        logger -p mail.info -t smtpdd "In queue-only mode, will queue mail until a queue run is performed"
        queueit="yes"
      fi

      if [ $queueit == "yes" ]
      then
        echo "queueing"
        mkdir -p $queuedir/$hostname:$port
        i=0
        while [ -f $queuedir/$hostname:$port/mailf.$$.$i.qf ]
        do
          i=$(( $i + 1 ))
        done
        cp $TMPDIR/$TMPFILENAME $queuedir/$hostname:$port/mailf.$$.$i.qf.body
        echo $from $to > $queuedir/$hostname:$port/mailf.$$.$i.qf
      fi
    fi
  done

}


if [ "x$1" == "x" ]
then
  printUsage
  exit $EX_TEMPFAIL
fi

if [ ! -d $1 ]
then
  echo "queue-directory specified, $1, must exist"
  exit $EX_TEMPFAIL
fi

if ! touch $1/.fml
then
  echo "queue-directory specified, $1, must exist and be writable"
  exit $EX_TEMPFAIL
else
  rm -f $1/.fml
fi

chmod 0700 $1

exec 8>> $LOCKFILE

if [ "x$2" == "xqrun" ]
then
  if flock -n -e 8
  then
    queueRun "$1"
    exit 0
  else
    logger -p mail.warning -t smtpdd "Queue directory locked, must exit from qrun"
    exit $EX_TEMPFAIL
  fi
fi

if [ "x$4" == "x" ]
then
  printUsage
  exit $EX_TEMPFAIL
fi

if flock -n -s 8
then
  logger -p mail.info -t smtpdd "${@}"
  rno=3
  for recip in ${@:3}
  do
    if [[ $recip == *@* ]]
    then
      mainRun $1 $2 $recip ${@:$rno}
      rno=$rno+1
    fi
  done
  rm -f $TMPDIR/$TMPFILENAME
else
  logger -p mail.warning -t smtpdd "Cannot obtain shared lock - will not deliver right now"
  rm -rf $LOCKFILE
  exit $EX_TEMPFAIL
fi

