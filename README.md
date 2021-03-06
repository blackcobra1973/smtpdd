# How To

## Get the script
```bash
cd /usr/local/src
git clone https://github.com/blackcobra1973/smtpdd.git
cd /usr/local/bin
ln -s /usr/local/src/smtpdd/smtpdd.sh
```

## Create the user
```bash
useradd -c "Dual Delivery smtp user" -u 1025 -d /var/spool/smtpdd -s /bin/bash -m smtpdd
```

## Provide sudo access to user smtpdd for the logger command (To show the correct tag )
```bash
smtpdd   ALL = NOPASSWD: /usr/bin/logger
```

## Update master.cfg
```bash
dualdelivery unix - n n - 5 pipe
    user=smtpdd argv=/usr/local/bin/smtpdd.sh /var/spool/smtpdd/ ${sender} ${recipient} realmailserver:25:q testmailserver:25:d othertestserver:25:o
```
* The line realmailserver:25:q means "deliver to realmailserver on port 25 (smtp) and queue if you fail"
* The line testmailserver:25:d means "deliver to testmailserver on port 25 and delete if you fail"
* The line othertestserver:25:o means "deliver to othertestserver on port 25 and only queue the mail" - this means that mail is just thrown straight into the smtpdd queue and wont be delivered until the qrun cronjob is executed.

## Lastly, a cron entry for smtpdd user to delivery queue'd email (crontab -e -u smtpdd)
```bash
0 * * * * /usr/local/bin/smtpdd.sh  /var/spool/smtpdd/ qrun > /dev/null 2>&1
```
