#!/bin/bash

#
# install-active-directory.sh - v. 1.1
#
# This is intended for a new Ubuntu/Debian machine that wants to join a Windows
# domain so you can log in to the linux machine with you Active Directory
# credentials. By default, "Domain Admins" can SSH into the box and use sudo.
#
# Because /etc/ssh/sshd_config is finicky, you can't use AllowUsers anymore to
# specify which user accounts can log into this machine - instead use the 
# can-ssh group set up by this script.
#
# The first time you log in with your Active Directory credentials, it will
# create a directory at /home/<username> for you. This behaviour is configurable
# so take a look at the script if you want to customize.
#
# The following four configuration variables are required: the name of the
# domain (short and long version), as well as the names of two domain
# controllers. It would be possible to remove lines referencing AD_SERVER_2 and
# still successfully use this script.
#

DOMAIN_SHORTNAME=TWC
DOMAIN_LONGNAME=theworkingcentre.org
AD_SERVER_1=ldap-ad  #any domain controller - this is a CNAME I made
AD_SERVER_2=ldap-ad2 #any other domain controller

#We need uppercase versions of some variables for /etc/krb5.conf
DOMAIN_LONGNAME_UPPERCASE=$(echo "$DOMAIN_LONGNAME" | tr '[:upper:]' '[:lower:]')
AD_SERVER_1_UPPERCASE=$(echo "$AD_SERVER_1" | tr '[:upper:]' '[:lower:]')
AD_SERVER_2_UPPERCASE=$(echo "$AD_SERVER_2" | tr '[:upper:]' '[:lower:]')

echo "install-active-directory.sh - a Devin Howard production"
echo "Run this script to set up active directory login, ssh, and sudo"
echo "This script has been tested for Debian wheezy and Ubuntu trusty"
echo "Limitations so far:"
echo " - if your computer name is longer than 15 chars it fails to join domain"
echo "If this script fails at any point - DO NOT RUN AGAIN. It is NOT idempotent"
echo "You'll have to use the commands in the script to recover manually"
echo "Enter to continue, Ctrl+C to end"
read

if [ "$UID" != 0 ]; then
  echo "Sorry, you need to be root. Try running sudo $0"
  exit 0
fi

echo "Installing ntp"
apt-get install ntp

/etc/init.d/ntp restart
date
echo "Is the above time correct? If so, hit Enter to proceed to installing samba and winbind. If not, Ctrl+C"
read

# Debian Wheezy - no need for libnss-windbind package
# Ubuntu Trusty - needs libnss-winbind
# Ubuntu 12.04 - needs libpam-windbind. 
   #
   # Needed to add a dummy /etc/init.d/samba with the following contents:
   # 
   # #!/bin/bash
   # ### BEGIN INIT INFO
   # # Provides: samba
   # # Required-Start: $remote_fs $syslog
   # # Required-Stop: $remote_fs $syslog
   # # Default-Start: 2 3 4 5
   # # Default-Stop: 0 1 6
   # # Short-Description: Start samba at boot time
   # # Description: Enable service provided by daemon.
   # ### END INIT INF
   # 
   # service smbd $*
   # service nmbd $*
   # 
   # exit 0
   #
# Debian Squeeze - seems to be able to use samba 3.6.
apt-get --assume-yes install samba smbclient samba-common winbind libnss-winbind
/etc/init.d/samba restart
update-rc.d samba enable
echo "Installed!"
echo ""

echo "OK, now I want to install kerberos and replace /etc/krb5.conf with a minimal setup. Enter to proceed, Ctrl+C to abort"
read
apt-get install krb5-user libpam-krb5
cp -p /etc/krb5.conf /etc/krb5.conf.orig
cat > /etc/krb5.conf << EOF
[logging]
  Default = FILE:/var/log/krb5.log
[libdefaults]
  default_realm = ${DOMAIN_LONGNAME_UPPERCASE}
  dns_lookup_realm = false
  dns_lookup_kdc = false
  ticket_lifetime = 24h
  renew_lifetime = 7d
  forwardable = true
[realms]
  ${DOMAIN_LONGNAME_UPPERCASE} = {
    kdc = ${AD_SERVER_1_UPPERCASE}.${DOMAIN_LONGNAME_UPPERCASE}
    kdc = ${AD_SERVER_2_UPPERCASE}2.${DOMAIN_LONGNAME_UPPERCASE}
    admin_server = ${AD_SERVER_1_UPPERCASE}.${DOMAIN_LONGNAME_UPPERCASE}
    default_domain = ${DOMAIN_LONGNAME_UPPERCASE}
  }
[domain_realm]
  .${DOMAIN_LONGNAME} = ${DOMAIN_LONGNAME_UPPERCASE}
  ${DOMAIN_LONGNAME} = ${DOMAIN_LONGNAME_UPPERCASE}
EOF

read -p "First, what's your domain admin username? It should be something like adminsmith; I'll add the ${DOMAIN_LONGNAME_UPPERCASE}: " ADMIN_NAME
echo ""
echo "OK great! Now I'm going to run kdestroy and klist. You should see no credentials. Then I'll run kinit ${ADMIN_NAME}@${DOMAIN_LONGNAME_UPPERCASE}, and then klist again and you should see expiry dates for your kerberos ticket."
echo "If that doesn't work, you'll want to exit and figure out what went wrong"
echo "Ready? Enter to proceed"
read
kdestroy
klist
kinit ${ADMIN_NAME}@${DOMAIN_LONGNAME_UPPERCASE}
klist

echo ""
echo "OK, if everything worked out hit Enter. Otherwise Ctrl+C and do this manually. Check out http://www.digitalllama.net/2013/05/join-debian-wheezy-to-windows-active.html if you want to try it manually"
read

echo "setting up /etc/samba/smb.conf, I hope this works. Enter to continue"
read

#grab everything before the workgroup = WORKGROUP line, and everything after
#then get rid of the workgroup = WORKGROUP line so we can replace it 
#with some custom settings (below)
PATT='workgroup = WORKGROUP'
grep --before-context=10000 --max-count=1 "$PATT" /etc/samba/smb.conf | grep -v "$PATT" > /tmp/setupad-smbconf-beginning.txt
grep --after-context=10000 --max-count=1 "$PATT" /etc/samba/smb.conf | grep -v "$PATT" > /tmp/setupad-smbconf-end.txt
cat > /tmp/setupad-smbconf-middle.txt << EOF
workgroup = ${DOMAIN_SHORTNAME}
security = ads
realm = ${DOMAIN_LONGNAME}
password server = ${AD_SERVER_1}.${DOMAIN_LONGNAME}
domain logons = no
template homedir = /home/%U
template shell = /bin/bash
winbind enum groups = yes
winbind enum users = yes
winbind use default domain = yes
winbind refresh tickets = yes
domain master = no
local master = no
prefered master = no
os level = 0
idmap config *:backend = tdb
idmap config *:range = 11000-20000
idmap config ${DOMAIN_SHORTNAME}:backend = rid
idmap config ${DOMAIN_SHORTNAME}:range=10000000-19000000
EOF
cp /etc/samba/smb.conf /etc/samba/smb.conf.orig
cat /tmp/setupad-smbconf-beginning.txt /tmp/setupad-smbconf-middle.txt /tmp/setupad-smbconf-end.txt > /etc/samba/smb.conf
rm /tmp/setupad-smbconf-*.txt
echo "I hope that worked! OK, now I'll restart the winbind and samba services. Enter to continue"
read

/etc/init.d/winbind stop
/etc/init.d/samba restart
/etc/init.d/winbind start

echo ""
read -p "Done. OK, now I want to join the domain. Pick a domain controller [${AD_SERVER_1}]: " DC_NAME
if [ -z "$DC_NAME" ]; then
  DC_NAME="${AD_SERVER_1}"
fi

echo "OK, joining the domain. username is $ADMIN_NAME and domain controller is $DC_NAME. Ready?"
read

net join -S $DC_NAME -U $ADMIN_NAME
net ads testjoin
net ads info
/etc/init.d/winbind restart

echo ""
echo "OK now I'm going to run wbinfo -u; wbinfo -g. You should users THEN groups."
read

wbinfo -u
wbinfo -g
echo ""
echo "Does everything check out? You should now see users and groups from active directory above."
read

echo "OK, now I'm adding "winbind" to the passwd and group lines of /etc/nsswitch.conf. After you hit enter, I'll do getent passwd and getent group - you should see domain groups and users. Ready when you are"
read

cp /etc/nsswitch.conf /etc/nsswitch.conf.orig
sed -i -e '/passwd.*compat/s/$/ winbind/' /etc/nsswitch.conf
sed -i -e '/group.*compat/s/$/ winbind/' /etc/nsswitch.conf
getent passwd
getent group

echo "Did that work? You should see domain groups and users"
read

echo "Adding 'session required pam_mkhomedir.so umask=0022 skel=/etc/skel' to /etc/pam.d/common-session"
echo 'session required pam_mkhomedir.so umask=0022 skel=/etc/skel' >> /etc/pam.d/common-session
echo ""

echo "Adding 'AllowGroups domain?admins can-ssh' to /etc/ssh/sshd_config and restarting ssh"
echo "Also turning off root login if it's allowed"
echo 'AllowGroups domain?admins can-ssh' >> /etc/ssh/sshd_config
sed -i -e 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i -e 's/PermitRootLogin without-password/PermitRootLogin no/' /etc/ssh/sshd_config
/etc/init.d/ssh restart
groupadd can-ssh
adduser localadmin can-ssh
echo ""

echo "Your next step is to add the following to /etc/sudoers via visudo"
cat << EOF
# User alias specification 
User_Alias      DOMAINADMINS = %domain\x20admins 
User_Alias      DOMAINUSERS = %domain\x20users 

DOMAINADMINS ALL=(ALL) ALL 
DOMAINUSERS ALL=NOPASSWD: /sbin/mount.cifs,/bin/umount
EOF
