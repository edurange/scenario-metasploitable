# The "interface" with edurange-server is defined by variables and outputs.
variable "students" {
  type = list(object({
    login              = string,
    password           = object({ plaintext = string, hash = string }),
  }))
  description = "list of players in students group"
  
  default = []
}

variable "aws_access_key_id" {
  type = string
}
variable "aws_secret_access_key" {
  type = string
}
variable "aws_region" {
  type = string
}

variable "scenario_id" {
  type        = string
  description = "identifier for instance of this scenario"
}

variable "env" {
  type        = string
  description = "For example testing/development/production"
  default     = "development"
}

variable "owner" {
  type        = string
  default     = "unknown"
}

output "instances" {
  value = [
    {
      name = "meta_nat"
      ip_address_public  = aws_instance.meta_nat.public_ip
      ip_address_private = aws_instance.meta_nat.private_ip
    },
    {
      name = "metasploitable"
      ip_address_private = aws_instance.metasploitable.private_ip
    },
    {
      name = "telnet_target"
      ip_address_private = aws_instance.telnet_target.private_ip
    }
  ]
}

# To be a good citizen scenario authors should tag all resources with these
# common tags and a Name tag.

locals {
  common_tags = {
    scenario_id = var.scenario_id
    scenario_name = "metasploitable"
    env         = var.env
    owner       = var.owner
    Name        = "metasploitable"
  }
  net_tools   = ["nmap", "tshark", "iputils-ping", "net-tools"]
}

provider "local" {
  version    = "~> 1"
}

provider "template" {
  version = "~> 2"
}

provider "tls" {
  version = "~> 2"
}

provider "aws" {
  version    = "~> 2"
  profile    = "default"
  region     = "us-west-1"
  access_key = var.aws_access_key_id
  secret_key = var.aws_secret_access_key
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-bionic-18.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

# create ssh key pair
resource "tls_private_key" "key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# save the private key locally for debugging
resource "local_file" "id_rsa" {
  sensitive_content  = tls_private_key.key.private_key_pem
  filename           = "${path.cwd}/id_rsa"
  provisioner "local-exec" {
    command = "chmod 600 ${path.cwd}/id_rsa"
  }
}

# upload the public key to aws
resource "aws_key_pair" "key" {
  key_name   = "metasploitable/${var.scenario_id}"
  public_key = tls_private_key.key.public_key_openssh
}


data "template_cloudinit_config" "meta_nat" {
  gzip          = true
  base64_encode = true

  part {
    filename     = "bash_history.cfg"
    content_type = "text/cloud-config"
    merge_type   = "list(append)+dict(recurse_list)"
    content = templatefile("${path.module}/bash_history.yml.tpl", {
      aws_key_id  = var.aws_access_key_id
      aws_sec_key = var.aws_secret_access_key
      scenario_id = var.scenario_id
      players     = var.students
    })
  }

  part {
    filename     = "init.cfg"
    content_type = "text/cloud-config"
    merge_type   = "list(append)+dict(recurse_list)"
    content = templatefile("${path.module}/cloud-init-nat.yml.tpl", {
      players  = var.students
      motd     = file("${path.module}/motd_nat")
      packages = setunion(local.net_tools, ["telnetd"])
      hostname = "meta-nat"
    })
  }
}

resource "aws_instance" "meta_nat" {
  ami                            = "ami-007f91a5a5f5102f1"
  instance_type                  = "t2.micro"
  private_ip                     = "10.0.37.6"
  associate_public_ip_address    = true
  subnet_id                      = aws_subnet.meta_nat.id
  user_data_base64               = data.template_cloudinit_config.meta_nat.rendered
  key_name                       = aws_key_pair.key.key_name
  vpc_security_group_ids         = [
    aws_security_group.allow_all_internal.id,
    aws_security_group.ssh_ingress_from_world.id,
    aws_security_group.http_egress_to_world.id
  ]

  tags = merge(local.common_tags, { Name = "metasploitable/meta_nat" })

  connection {
    host        = self.public_ip
    user        = "ubuntu"
    private_key = tls_private_key.key.private_key_pem
  }

  provisioner "file" {
    source = "${path.module}/iptables_setup"
    destination = "/home/ubuntu/iptables_setup"
  }

  provisioner "remote-exec" {
    inline = [
      "set -eux",
      "cloud-init status --wait --long",
      "cd /home/ubuntu/",
      "sudo chmod +x iptables_setup",
      "sudo ./iptables_setup"
    ]
  }
}

data "template_cloudinit_config" "telnet_target" {
  gzip          = true
  base64_encode = true

  part {
    filename     = "bash_history.cfg"
    content_type = "text/cloud-config"
    merge_type   = "list(append)+dict(recurse_list)"
    content = templatefile("${path.module}/bash_history.yml.tpl", {
      aws_key_id  = var.aws_access_key_id
      aws_sec_key = var.aws_secret_access_key
      scenario_id = var.scenario_id
      players     = var.students
    })
  }

  part {
    filename     = "init.cfg"
    content_type = "text/cloud-config"
    merge_type   = "list(append)+dict(recurse_list)"
    content = templatefile("${path.module}/cloud-init.yml.tpl", {
      players  = var.students
      motd     = file("${path.module}/motd")
      packages = setunion(local.net_tools, ["telnetd"])
      hostname = "telnet-target"
    })
  }
}

resource "aws_instance" "telnet_target" {
  subnet_id                   = aws_subnet.telnet_target.id
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t2.nano"
  private_ip                  = "10.0.192.4"
  key_name                    = aws_key_pair.key.key_name
  vpc_security_group_ids      = [
    aws_security_group.allow_all_internal.id,
    aws_security_group.http_egress_to_world.id
  ]
  user_data_base64            = data.template_cloudinit_config.telnet_target.rendered

  tags = merge(local.common_tags, {
    Name = "metasploitable/telnet_target"
  })
  connection {
    bastion_host        = aws_instance.meta_nat.public_ip
    bastion_port        = 22
    host                = self.private_ip
    port                = 22
    user                = "ubuntu"
    private_key         = tls_private_key.key.private_key_pem
  }

  provisioner "file" {
    source = "${path.module}/telnet_setup"
    destination = "/home/ubuntu/telnet_setup"
  }

  provisioner "remote-exec" {
    inline = [
      "set -eux",
      "cloud-init status --wait --long",
      "cd /home/ubuntu/",
      "sudo chmod +x telnet_setup",
      "sudo ./telnet_setup"
    ]
  }
}

data "template_cloudinit_config" "metasploitable" {
  gzip          = true
  base64_encode = true

  part {
    filename     = "bash_history.cfg"
    content_type = "text/cloud-config"
    merge_type   = "list(append)+dict(recurse_list)"
    content = templatefile("${path.module}/bash_history.yml.tpl", {
      aws_key_id  = var.aws_access_key_id
      aws_sec_key = var.aws_secret_access_key
      scenario_id = var.scenario_id
      players     = var.students
    })
  }

  part {
    filename     = "init.cfg"
    content_type = "text/cloud-config"
    merge_type   = "list(append)+dict(recurse_list)"
    content = templatefile("${path.module}/cloud-init-meta.yml.tpl", {
      players  = var.students
      motd     = file("${path.module}/motd_meta")
      packages = local.net_tools
      hostname = "metasploitable"
    })
  }
}
resource "aws_instance" "metasploitable" {
  subnet_id                   = aws_subnet.meta_target.id
  ami                         = "ami-02acef1290732478f"
  instance_type               = "t2.nano"
  private_ip                  = "10.0.20.4"
  key_name                    = aws_key_pair.key.key_name
  vpc_security_group_ids      = [
    aws_security_group.allow_all_internal.id,
    aws_security_group.http_egress_to_world.id
  ]
  user_data_base64            = data.template_cloudinit_config.metasploitable.rendered
  connection {
    bastion_host = aws_instance.meta_nat.public_ip
    bastion_port = 22
    bastion_user = "ubuntu"
    bastion_private_key = tls_private_key.key.private_key_pem
    host = self.private_ip
    user = "vagrant"
    password = "vagrant"
  }
  tags = merge(local.common_tags, {
    Name = "metasploitable/metasploitable"
  })
  #provisioner "file" {
  #  source = "${path.module}/ttylog"
  #  destination = "/home/vagrant"
  #}

  #provisioner "file" {
  #  source = "${path.module}/tty_setup_meta"
  #  destination = "/home/vagrant/tty_setup"
  #}

  provisioner "file" {
    source = "${path.module}/telnetscr.sh"
    destination = "/home/vagrant/telnetscr.sh"
  }

  provisioner "file" {
    source = "${path.module}/crontab_entry"
    destination = "/home/vagrant/crontab_entry"
  }

  provisioner "remote-exec" {
    inline = [
      "set -eux",
      "cd /home/vagrant",
      "sudo chmod +x telnetscr.sh",
      "sudo crontab crontab_entry"
    ]
  }
}
