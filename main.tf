provider "aws" {
  region = "eu-west-3"
}

terraform {
  backend "s3" {
    bucket = "nazim-huseynov-gitlab-project-terraform-state"
    key = "dev/nodeapp/terraform.tfstate"
    region = "eu-west-3"
  }
}

resource "aws_key_pair" "gitlab_runner_key" {
  key_name   = "gitlab_runner_key"
  public_key = file("id_rsa.pub")
}

resource "aws_security_group" "ssg" {
  name        = "ssg"
  description = "Allow SSH access"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 4000
    to_port     = 4000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "ec2_gitlab_runner" {
  ami           = "ami-0ca5ef73451e16dc1" # Amazon Linux 2 LTS
  instance_type = "t2.micro"
  key_name      = aws_key_pair.gitlab_runner_key.key_name
  vpc_security_group_ids = [aws_security_group.ssg.id]

  tags = {
    Name = "gitlab_runner"
  }

  user_data = <<-EOF
    #!/bin/bash
    sudo su -
    curl -L https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.rpm.sh | bash
    yum install -y gitlab-runner nodejs docker jq
    systemctl start gitlab-runner
    systemctl enable gitlab-runner
    gitlab-runner start
    gitlab-runner register --non-interactive --url "https://gitlab.com/" --registration-token "GR1348941z4SruD6496wzsvyVbXXe" --executor "shell" --description "shell, remote, nodeapp" --tag-list "nodeapp, shell, remote"
    curl -sL https://rpm.nodesource.com/setup_14.x | sudo bash -
    systemctl start docker
    systemctl enable --now docker
    usermod -aG docker gitlab-runner
    usermod -aG docker ec2-user
    gitlab-runner register --non-interactive --url "https://gitlab.com/" --registration-token "GR1348941z4SruD6496wzsvyVbXXe" --executor "docker" --docker-image "alpine:3.17" --description "nodeapp docker" --tag-list "nodeapp, docker, remote"
  EOF
}

resource "aws_instance" "deploy-server" {
  ami           = "ami-0ca5ef73451e16dc1" # Amazon Linux 2 LTS
  instance_type = "t2.micro"
  key_name      = aws_key_pair.gitlab_runner_key.key_name
  vpc_security_group_ids = [aws_security_group.ssg.id]

  tags = {
    Name = "dev-server"
  }
  user_data = <<-EOF
    #!/bin/bash
    sudo su -
    yum install -y docker
    systemctl start docker
    systemctl enable --now docker
    usermod -aG docker ec2-user 
    curl -L https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m) -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
  EOF
}

output "public_ip_of_gitlab_runner" {
  value = aws_instance.ec2_gitlab_runner.public_ip
}

output "public_ip_of_dev_server" {
  value = aws_instance.dev-server.public_ip
}

output "sg_id" {
  value = aws_security_group.ssg.id
}