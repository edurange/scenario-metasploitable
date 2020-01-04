/* NAT, Subnets, and Security Groups */

resource "aws_vpc" "metasploitable" {
  cidr_block = "10.0.0.0/16"
  tags = merge(local.common_tags, { Name = "metasploitable" })
}

resource "aws_internet_gateway" "metasploitable" {
  vpc_id = aws_vpc.metasploitable.id
  tags = merge(local.common_tags, { Name = "metasploitable" })
}

resource "aws_subnet" "meta_nat" {
  vpc_id      = aws_vpc.metasploitable.id
  cidr_block  = "10.0.37.0/24"
  tags = merge(local.common_tags, { Name = "metasploitable/nat"})
}

resource "aws_eip" "nat" {
  vpc                       = true
  associate_with_private_ip = "10.0.37.6"
  depends_on                = [aws_internet_gateway.metasploitable]
  tags = merge(local.common_tags, { Name = "metasploitable/nat" })
}

resource "aws_nat_gateway" "nat" {
  allocation_id = "${aws_eip.nat.id}"
  subnet_id     = "${aws_subnet.meta_nat.id}"
  tags = merge(local.common_tags, { Name = "metasploitable/nat"})
}

resource "aws_route_table" "to_internet" {
  vpc_id = aws_vpc.metasploitable.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.metasploitable.id
  }
}

resource "aws_route_table" "through_nat" {
  vpc_id = aws_vpc.metasploitable.id
  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
  tags = merge(local.common_tags, { Name = "metasploitable"})
}

resource "aws_route_table_association" "meta_nat" {
  subnet_id      = aws_subnet.meta_nat.id
  route_table_id = aws_route_table.to_internet.id
}

resource "aws_security_group" "allow_all_internal" {
  vpc_id = aws_vpc.metasploitable.id
  name   = "metasploitable/allow_all_internal"
  egress {
    self        = true
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
  }

  ingress {
    self        = true
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
  }
  tags = merge(local.common_tags, {
    Name = "metasploitable/allow_all_internal"
  })
}

resource "aws_security_group" "ssh_ingress_from_world" {
  vpc_id = aws_vpc.metasploitable.id
  name   = "metasploitable/ssh_ingress_from_world"
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(local.common_tags, {
    Name = "metasploitable/ssh_ingress_from_world"
  })
}

resource "aws_security_group" "http_egress_to_world" {
  vpc_id = aws_vpc.metasploitable.id
  name   = "metasploitable/http_egress_to_world"

  egress {
    cidr_blocks = ["0.0.0.0/0"]
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
  }

  egress {
    cidr_blocks = ["0.0.0.0/0"]
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
  }

  tags = merge(local.common_tags, {
    Name = "metasploitable/http_egress_to_world"
  })
}

resource "aws_subnet" "meta_target" {
  vpc_id     = aws_vpc.metasploitable.id
  cidr_block = "10.0.20.0/27"
  tags = merge(local.common_tags, { Name = "metasploitable/meta_target" })
}

resource "aws_route_table_association" "meta_target" {
  subnet_id      = aws_subnet.meta_target.id
  route_table_id = aws_route_table.through_nat.id
}

resource "aws_subnet" "telnet_target" {
  vpc_id     = aws_vpc.metasploitable.id
  cidr_block = "10.0.192.0/27"
  tags = merge(local.common_tags, { Name = "metasploitable/telnet_target" })
}

resource "aws_route_table_association" "telnet_target" {
  subnet_id      = aws_subnet.telnet_target.id
  route_table_id = aws_route_table.through_nat.id
}
