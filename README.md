# Role Name #
A brief description of the role goes here.

## Requirements ##
Any pre-requisites that may not be covered by Ansible itself or the role should be mentioned here. For instance, if the role uses the EC2 module, it may be a good idea to mention in this section that the boto package is required.

## Role Variables ##
A description of the settable variables for this role should go here, including any variables that are in defaults/main.yml, vars/main.yml, and any variables that can/should be set via parameters to the role. Any variables that are read from other roles and/or the global scope (ie. hostvars, group vars, etc.) should be mentioned here as well.

Available variable are listed below:
```
backuppc_client:
    - username: ''
      home: ''
      shell: '/bin/bash'
      comment: 'BackupPC User'
      authorized_keys: ''
      key_options: 'command=\"sudo /usr/bin/rsync --server --sender -logDtpr --delete --numeric-ids --block-size=2048
          --exclude=''/proc/*'' 
          --exclude=''/sys/*'' 
          --exclude=''/mnt/*'' 
          --exclude=''/tmp/*'' 
          --exclude=''/var/tmp/*'' 
          --exclude=''/var/cache/apt/archives/*'' 
          --exclude=''/var/log/*/*'' 
          --exclude=''/var/log/*.*'' 
          --exclude=''*.iso'' 
          --exclude=''*.ova'' . /\",
          no-port-forwarding,no-X11-forwarding,no-agent-forwarding'
```
## Dependencies ##
A list of other roles hosted on Galaxy should go here, plus any details in regards to parameters that may need to be set for other roles, or variables that are used from other roles.

## Example Playbook ##
```
- hosts: servers
  roles:
    - { role: backuppc-client, sudo: yes }
```

## License ##
BSD

## Author Information ##
[Real Time Enterprises Inc.](http://www.real-time.com), 
[Bob Tanner](https://github.com/basictheprogram)