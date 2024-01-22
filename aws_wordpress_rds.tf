provider "aws" {
    region = "us-east-1"
    access_key = ""
    secret_key = ""
}

resource "tls_private_key" "wpkey" {
    algorithm = "RSA"
    rsa_bits = 4096
}

resource "local_file" "localkey" {
    depends_on = [
        tls_private_key.wpkey,
    ]
    content = tls_private_key.wpkey.private_key_pem
    filename = "wpkey.pem"
}

resource "aws_key_pair" "awskey" {
    depends_on = [
        tls_private_key.wpkey,
    ]
    key_name = "wpkey"
    public_key = tls_private_key.wpkey.public_key_openssh
}

resource "aws_vpc" "wp_vpc" {
    cidr_block = "192.168.0.0/16"
    enable_dns_support = true
    enable_dns_hostnames = true
    tags = {
        "Name" = "wp-vpc"
    }
}

resource "aws_subnet" "wp_public" {
  depends_on = [
    aws_vpc.wp_vpc,
  ]
  cidr_block              = "192.168.0.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  vpc_id                  = aws_vpc.wp_vpc.id
  tags = {
    "Name" = "wp-public"
  }
}

#private subnets
resource "aws_subnet" "private1" {
    vpc_id     = aws_vpc.wp_vpc.id
    cidr_block = "192.168.1.0/24"
    availability_zone = "us-east-1a"

    tags = {
        Name = "upgrad-private-1"
  }
}
resource "aws_subnet" "private2" {
    vpc_id     = aws_vpc.wp_vpc.id
    cidr_block = "192.168.2.0/24"
    availability_zone = "us-east-1b"

    tags = {
        Name = "upgrad-private-2"
  }
}

resource "aws_internet_gateway" "wp_ig" {
    depends_on = [
        aws_vpc.wp_vpc,
    ]
    vpc_id = aws_vpc.wp_vpc.id
    tags = {
        "Name" = "wp-ig"
    }
}

resource "aws_eip" "wp_eip" {
    depends_on = [
        aws_internet_gateway.wp_ig,
    ]
    tags = {
        "Name" = "wp-eip"
    }
}

resource "aws_nat_gateway" "wp_ng" {
    depends_on = [
        aws_eip.wp_eip,
        aws_subnet.wp_public,
    ]
    allocation_id = aws_eip.wp_eip.id
    subnet_id = aws_subnet.wp_public.id
    tags = {
        "Name" = "wp-ng"
    }
}

resource "aws_route_table" "wp_rt" {
    depends_on = [
        aws_internet_gateway.wp_ig,
    ]
    vpc_id = aws_vpc.wp_vpc.id
    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.wp_ig.id
    }
    tags = {
        "Name" = "wp-rt"
    }
}

resource "aws_route_table_association" "wp_rta" {
    depends_on = [
        aws_subnet.wp_public,
        aws_route_table.wp_rt,
    ]
    subnet_id = aws_subnet.wp_public.id
    route_table_id = aws_route_table.wp_rt.id
}

resource "aws_default_route_table" "wp_drt" {
    depends_on = [
        aws_vpc.wp_vpc,
        aws_nat_gateway.wp_ng,
    ]
    default_route_table_id = aws_vpc.wp_vpc.main_route_table_id
    route {
        cidr_block = "0.0.0.0/0"
        nat_gateway_id = aws_nat_gateway.wp_ng.id
    }
    tags = {
        "Name" = "wp-drt"
    }
}

#private route table
resource "aws_route_table" "private" {
    vpc_id = aws_vpc.wp_vpc.id

    route {
        cidr_block     = "0.0.0.0/0"
        nat_gateway_id = aws_nat_gateway.wp_ng.id
  }

    tags = {
        Name = "private-rt"
  }
}

resource "aws_route_table_association" "private1" {
    subnet_id      = aws_subnet.private1.id
    route_table_id = aws_route_table.private.id
}
resource "aws_route_table_association" "private2" {
    subnet_id      = aws_subnet.private2.id
    route_table_id = aws_route_table.private.id
}

resource "aws_security_group" "wordpress_sg" {
    depends_on = [
        aws_route_table_association.wp_rta,
    ]
    name = "wordpress-sg"
    description = "Connection between client and Wordpress"
    vpc_id = aws_vpc.wp_vpc.id

    ingress {
        description = "ssh"
        from_port = 22
        to_port = 22
        protocol = "TCP"
        cidr_blocks = ["0.0.0.0/0"]

    }

    ingress {
        description = "httpd"
        from_port = 80
        to_port = 80
        protocol = "TCP"
        cidr_blocks = ["0.0.0.0/0"]

    }

    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]

    }
}


resource "aws_db_subnet_group" "rds_subnet_group" {
    name       = "rds-subnet-group"
    subnet_ids = [aws_subnet.private1.id, aws_subnet.private2.id]
}

resource "aws_security_group" "rds_security_group" {
    name        = "rds-security-group"
    description = "Security group for RDS instance"
    vpc_id      = aws_vpc.wp_vpc.id

    ingress {
        from_port   = 3306
        to_port     = 3306
        protocol    = "tcp"
        cidr_blocks = ["10.100.0.0/16"]
  }

    tags = {
        Name = "RDS Security Group"
  }
}

resource "aws_db_instance" "rds_instance" {
    engine                    = "mysql"
    engine_version            = "5.7"
    skip_final_snapshot       = true
    final_snapshot_identifier = "my-final-snapshot"
    instance_class            = "db.t2.micro"
    allocated_storage         = 20
    identifier                = "my-rds-instance"
    db_name                   = "NAME"
    username                  = "USER"
    password                  = "PASSWORD"
    db_subnet_group_name      = aws_db_subnet_group.rds_subnet_group.name
    vpc_security_group_ids    = [aws_security_group.rds_security_group.id]

    tags = {
        Name = "RDS Instance"
  }
}

resource "aws_instance" "Wordpress" {
    depends_on = [
        aws_security_group.wordpress_sg,
    ]

    ami = "ami-0005e0cfe09cc9050"
    instance_type = "t2.micro"
    key_name = "wpkey"
    vpc_security_group_ids = [aws_security_group.wordpress_sg.id]
    subnet_id = aws_subnet.wp_public.id

    tags = {
        "Name" = "WPServer"
    }
}
