provider "aws" {
  region = "ap-south-1"
}


//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// Creating The VPC 

resource "aws_vpc" "vpc" {
  cidr_block = "172.31.0.0/16"
  instance_tenancy = "default"
  
  tags = {
    Name = "Tasks_vpc"
  }
}

//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// Creating the Public Subnet

resource "aws_subnet" "Public_subnet" {
  vpc_id     = aws_vpc.vpc.id
  cidr_block = "172.31.32.0/20"
  map_public_ip_on_launch = true
  availability_zone = "ap-south-1a"
  

  tags = {
    Name = "Tasks_Public_subnet"
  }
}

//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// Creating the Private Subnet

resource "aws_subnet" "Private_subnet" {
  vpc_id     = aws_vpc.vpc.id
  cidr_block = "172.31.0.0/20"
  map_public_ip_on_launch = false
  availability_zone = "ap-south-1a"
  

  tags = {
    Name = "Tasks_Private_subnet"
  }
}

//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// Creating the Internet Gateway

resource "aws_internet_gateway" "gw" {
  depends_on = [
    aws_vpc.vpc
  ]
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "Tasks_IG"
  }
}

//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// Creating The Route Table

resource "aws_route_table" "rtable" {

  depends_on = [
    aws_internet_gateway.gw
    
  ]
  
  vpc_id = aws_vpc.vpc.id
  route {
    gateway_id = aws_internet_gateway.gw.id
    cidr_block = "0.0.0.0/0"
  }

  tags = {
    Name = "Tasks_Rtable-for-Public"
  }
}

//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// Assosiating Route Table To Public_subnet_RTable

resource "aws_route_table_association" "Public_subnet_RTable" {
  depends_on = [
    aws_route_table.rtable
  ]
  subnet_id      = aws_subnet.Public_subnet.id
  route_table_id = aws_route_table.rtable.id
}

//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// Creating the security group for Wordpress

resource "aws_security_group" "Wordpress-sec" {

    depends_on = [
        aws_vpc.vpc
    ]
  name        = "Allowing SSH and HTTP and MySQL port"
  description = "Allow ssh & http connections"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description = "Allowing Connection for SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "Allowing Connection For HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Tasks_Wordpress_Security"
  }
}

//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// Creating the Security group for MySQL

resource "aws_security_group" "MySQL-sec" {

    depends_on = [
        aws_vpc.vpc
    ]
  name        = "MySQL_Security_Group"
  description = "Allow 3306 Port connections"
  vpc_id      = aws_vpc.vpc.id
 
  ingress {
    description = "Allow Wordpress"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [aws_subnet.Public_subnet.cidr_block]
    security_groups = [aws_security_group.Wordpress-sec.id]
  }
   ingress {
    description = "Allow Wordpress-SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [aws_subnet.Public_subnet.cidr_block]
    security_groups = [aws_security_group.Wordpress-sec.id]
  }



  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Tasks_MySQL_Security"
  }
}

//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
//Creating The Key and Saving them on The Disk

resource "tls_private_key" "mykey"{
	algorithm = "RSA"
}

resource "aws_key_pair" "key1" {
  key_name   = "key3"
  public_key = tls_private_key.mykey.public_key_openssh
}
 
resource "local_file" "key_pair_save"{
   content = tls_private_key.mykey.private_key_pem
   filename = "key.pem"
}

//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// Launching the Instance Of Wordpress

    resource "aws_instance" "WordPress" {

        depends_on = [
            tls_private_key.mykey,
            aws_key_pair.key1,
            local_file.key_pair_save,
            aws_security_group.Wordpress-sec,
            aws_vpc.vpc,
            aws_instance.MySQL
        ]
        ami = "ami-0ec00d0dbf5b00645"
        instance_type = "t2.micro"
        key_name = "key3"
        availability_zone = "ap-south-1a"
        subnet_id = aws_subnet.Public_subnet.id
        vpc_security_group_ids  = [aws_security_group.Wordpress-sec.id]
        tags = {
        Name = "Wordpress"
              }
    }

//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// Resource Group
  resource "null_resource" "null1"{
      depends_on = [
        aws_instance.WordPress
      ]
    
        connection {
            type = "ssh"
            user = "ubuntu"
            private_key = tls_private_key.mykey.private_key_pem
            host = aws_instance.WordPress.public_ip
        }

        provisioner "remote-exec" {
            inline = [
               "cd /var/www/wordpress/",
               "sudo sed -i 's/hosyt/${aws_instance.MySQL.private_ip}/g' wp-config.php",
            ]
        
        }
    }

//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// Launching the Instance Of MySQL

  resource "aws_instance" "MySQL"{

    depends_on = [
       tls_private_key.mykey,
            aws_key_pair.key1,
            local_file.key_pair_save,
            aws_security_group.MySQL-sec,
            aws_vpc.vpc
    ]
    ami = "ami-02f2f988defde3c2f"
        instance_type = "t2.micro"
        key_name = "key3"
        availability_zone = "ap-south-1a"
        subnet_id = aws_subnet.Private_subnet.id
        vpc_security_group_ids  = [aws_security_group.MySQL-sec.id]
        tags = {
        Name = "Database-Server"
              }

  }

//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

resource "null_resource" "null2" {
  depends_on =  [
           null_resource.null1,
  ]
 provisioner "local-exec" {
    command = "chrome ${aws_instance.WordPress.public_ip}"
  }
}
