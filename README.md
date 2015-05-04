Role Name
=========

A brief description of the role goes here.

Requirements
------------

Any pre-requisites that may not be covered by Ansible itself or the role should be mentioned here. For instance, if the role uses the EC2 module, it may be a good idea to mention in this section that the boto package is required.

Role Variables
--------------

A description of the settable variables for this role should go here, including any variables that are in defaults/main.yml, vars/main.yml, and any variables that can/should be set via parameters to the role. Any variables that are read from other roles and/or the global scope (ie. hostvars, group vars, etc.) should be mentioned here as well.

Dependencies
------------

A list of other roles hosted on Galaxy should go here, plus any details in regards to parameters that may need to be set for other roles, or variables that are used from other roles.

Example Playbook
----------------

Including an example of how to use your role (for instance, with variables passed in as parameters) is always nice for users too:

    - hosts: servers
      roles:
         - { role: username.rolename, x: 42 }

License
-------

BSD

Author Information
------------------

An optional section for the role authors to include contact information, or a website (HTML is not allowed).


Ugly cut-n-paste of Carl's documentation
========================================

On 10/23 04:04 , Bob Tanner wrote:
Carl can you give me a task list of how to install and configure the backuppc client stuff?

Here's a doc I wrote a few years ago. It's a bit more basic than you need,
but should have sufficient detail. beware that in the course of pasting it
into this mail some confusing line breaks may have crept in.

-=Introduction=-

Here's a quick & dirty explanation of how to set up a client machine to be
backed up with rsync, using sudo and restricted command rights to give some
protection against unauthorized writes. If you are logging in as root on the
hosts to be backed up, then someone cracking the backup server could easily
get access to modify files on the machines being backed up. If you set your
clients up this way, it provides a couple of layers of restriction which
prevent the backup process from being able to modify files.

For purposes of this explanation, I'm going to use 'rsyncbackup' as the
user. It actually doesn't matter what the remote user's name is, so long as
it's unique. (It shouldn't collide with any other username).

--==Setup==--

If you do not have a DSA key pair for passwordless authentication with ssh,
you will need to create one. Otherwise backups would require someone
manually typing in the password every time the backup is run. This is done
with the ssh-keygen command, and you should use the 'dsa' type (instead of
the obsolete rsa type). If you need to create a key, become root and type
the following command:

ssh-keygen -t dsa

If it asks you for a passphrase, just hit <enter>, to avoid putting one in.
Otherwise we're back at the original problem of having to put a password in
whenever a backup should be run.

This will create a pair of files in ~root/.ssh/ called id_dsa and
id_dsa.pub. The id_dsa file is the private side of the keypair, and should
be kept secret. The id_dsa.pub file is the public side of the keypair, and
shoud be put on any remote machine you wish to log into without a password.

-=On the Client Machine to be Backed Up=-
First, create the 'rsyncbackup' user on the intended client machine. Make
the home directory /var/lib/rsyncbackup. This will be the user that we log
in as, and then use sudo to run the actual rsync commands. The actual
command to run is likely to be something resembling:

useradd -r -m -d /var/lib/rsyncbackup -c "Backuppc User" rsyncbackup

Note that the '-r' option is a RedHat-ism (though I believe it applies to
SuSE as well). It creates a 'system' (low-UID) account. On other
distributions (like Debian), just manually assign an unallocated low UID
number. 

Once the rsyncbackup user has been created, you will need to create a .ssh
directory to hold the public side of the keypair that the backup user will
log in with.

- First, change to the backup user's home directory.
cd ~rsyncbackup

- Next, make a .ssh directory
mkdir .ssh

- Transfer the public side of the keypair to the client machine by some
 mechanism (scp is a good one). You can upload it to /var/tmp/,
temporarily. (You should not be transferring files in as root, so you
wouldn't be able to upload directly to ~rsyncbackup/.ssh). We then transfer
it from there to the ~rsyncbackup/.ssh/authorized_keys file. Note that it is
possible to have multiple keys in the authorized_keys file; but since this
is a brand-new account, we will just move the file into place.
mv /var/tmp/id_dsa.pub ~rsyncbackup/.ssh/authorized_keys

- Next we need to make sure the ownership and permissions on the key file
 and directory is correct; otherwise it will not authorize correctly.
chown -R rsyncbackup:users ~rsyncbackup/.ssh
chmod 700 ~rsyncbackup/.ssh


Now edit /etc/sudoers with the 'visudo' command and add some lines to allow
the rsyncbackup user to run the rsync command as root, thereby giving them
access to the whole filesystem. (Without allowing other commands to be run
with access to the whole filesystem).
# allow backup user to run rsync as root
rsyncbackup ALL= NOPASSWD: /usr/bin/rsync 

(One should run the 'which rsync' command to verify that rsync is indeed
installed, and what its actual path is. /usr/bin/rsync is just a common
place to find it).

On the backuppc server, su to backuppc ( su - backuppc -s /bin/bash); then
try to ssh to rsyncbackup@client. Make sure that works without a password
being entered. if not, check that the permissions and ownership on the
~rsyncbackup/.ssh directory are correct.
Doing this also adds the host to backuppc's list of known_hosts; so it won't
hang waiting for confirmation that the host's key is acceptable.

Make sure when you ssh to the client, that you refer to it by the name you
call it in the backuppc configuration files (so if you will list the machine
in /etc/backuppc/hosts as foo.example.tld, ssh to it as
rsyncbackup@foo.example.tld instead of rsyncbackup@foo). Otherwise the key
caching will not work, and backups will fail because ssh prompts for
acceptance of the host key.

Now add the rsync/sudo restrictions to the authorized_keys file. Here is a
starting example of what a key might look like (of course, the ...AAA..
section should be replaced with your actual DSA public key). The 'ssh-dss'
is where the automatically-generated part of the key begins. Everything
before that is additional restrictions on what can be done after logging in
with this key.

no-port-forwarding,no-X11-forwarding,no-agent-forwarding,command="sudo /usr/bin/rsync --server --sender -logDtpr --exclude='/proc/*' --exclude='/sys/*' --exclude='/tmp/*' --exclude='/mnt/*' --exclude='/staff/*' --delete --numeric-ids --block-size=2048 . /" ssh-dss AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=root@backupserver.example.tld

-=On the Server=-
Become root on the server again; then go to /etc/backuppc.
Copy one of the other per-host configuration files and edit the options
therein, if necessary.

Add the host to the /etc/backuppc/hosts file, and specify which users should
have authority over it.

You will likely need to restart/rehup the backuppc process, before it will
resolve the hostname of the new box. So run:

/etc/init.d/backuppc reload

Go to the web interface, choose your new host to be backed up from the Host
Summary page by clicking on its link, and click on the 'start full backup'
button for that host.

Check the running processes on the client and server; see if there is an
rsync running on both of them. (Use the 'ps ax' command).
if not, go to the debugging section.

--==Removing Clients==--

If you wish to stop backups of a client; don't remove them from the list of
hosts.
just add the following lines to their config file:

#Going to disable backups for the near-term. Setting FullPeriod=-2 means 
#it will never be backed up, and EMailNotifyMinDays=365 means it won't
notify
#about the lack of backups for a year.
$Conf{FullPeriod} = -2;
$Conf{EMailNotifyMinDays} = 365;


--==Debugging==--

In some cases, it may be necessary to put a password on the 'rsyncbackup'
account before DSA logins will be accepted. 
you'll see an error in syslog like:
"User rsyncbackup not allowed because account is locked"
Just generate a long string up characters with md5sum against some file, or
the like, and use that as a password. (you'll never need to know it).

If DSA-keyed logins still don't work; make sure the authorized_keys file
hasn't become corrupt. (often happens when you copy-and-paste the key,
you'll miss the first character, or put an extraneous line break in).

On older SSH implementations:
- it's authorized_keys2 instead of authorized_keys
- the authorized_keys2 file must be chmod'ed 600 or 400; even if the
 directory is already.

To get more debugging information out of the rsync transfers, in the
per-host configuration file, add the line:
$Conf{RsyncLogLevel} = 6;

Better yet, become backuppc, and try running the BackupPC_dump command by
hand, and look at the output. 99% of the time, this will tell you what's
wrong.
# su - backuppc -s /bin/bash
$ /usr/share/backuppc/bin/BackupPC_dump -v -f berzerker


Note that rsync-2.5.5 is supposedly needed for backuppc-2.0.2 and later.
(tho it looks like rsync-2.4.6 [protocol v24] works anyway).

Rsync protocols >26 should work (maybe lower, don't know); I think protocol
v28 is the current one. the protocol version is apparent when you run
backuppc_dump by hand. if there is a protocol mismatch; the connections will
open, and the rsync process start; but nothing will be transferred.
