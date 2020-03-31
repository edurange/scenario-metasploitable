#cloud-config (basis)
repo_update: true
repo_upgrade: all
ssh_pwauth: yes
hostname: ${hostname}
packages:
%{ for package in packages ~}
- ${package}
%{ endfor ~}
users:
- default
%{ for player in players ~}
- name: ${player.login}
  passwd: ${player.password.hash}
  lock_passwd: false
  shell: /bin/bash
  sudo: ALL=(ALL) NOPASSWD:ALL
%{ endfor ~}
write_files:
- path: /etc/motd
  encoding: b64
  content: ${base64encode(motd)}
runcmd:
- set -eu
- chmod -x /etc/update-motd.d/*
- hostname ${hostname}
- service ssh restart
%{ for player in players ~}
- cp -r /home/ubuntu/gobuster /home/${player.login}/
- echo "${player.login}  memory  memlimit/" | tee -a /etc/cgrules.conf
%{ endfor ~}
