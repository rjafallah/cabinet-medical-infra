data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_key_pair" "cabinet" {
  key_name   = "cabinet-medical-key"
  public_key = file(pathexpand("~/.ssh/blazing-key.pub"))
}

resource "aws_security_group" "cabinet" {
  name = "cabinet-medical-sg"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${var.my_ip}/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "cabinet" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "m7i-flex.large"
  key_name               = aws_key_pair.cabinet.key_name
  vpc_security_group_ids = [aws_security_group.cabinet.id]
  user_data              = file("bootstrap.sh")

  root_block_device {
    volume_size = 30
  }

  tags = { Name = "cabinet-medical-k8s" }
}
