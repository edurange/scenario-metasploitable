#cloud-config (basis)
ssh_pwauth: yes
hostname: ${hostname}
packages:
%{ for package in packages ~}
- ${package}
%{ endfor ~}
write_files:
- path: /etc/motd
  encoding: b64
  content: ${base64encode(motd)}
runcmd:
- set -eu
- chmod -x /etc/update-motd.d/*
- rm /etc/legal
- hostname ${hostname}
- service ssh restart
