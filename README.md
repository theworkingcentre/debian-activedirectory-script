This script is intended for a new Ubuntu/Debian machine that wants to join a 
Windows domain so you can log in to the linux machine with you Active Directory
credentials. By default, "Domain Admins" can SSH into the box and use sudo.

Because /etc/ssh/sshd_config is finicky, you can't use AllowUsers anymore to
specify which user accounts can log into this machine - instead use the
can-ssh group set up by this script.

The first time you log in with your Active Directory credentials, it will
create a directory at /home/<username> for you. This behaviour is configurable
so take a look at the script if you want to customize.

The following four configuration variables are required: the name of the
domain (short and long version), as well as the names of two domain
controllers. It would be possible to remove lines referencing AD_SERVER_2 and
still successfully use this script.

