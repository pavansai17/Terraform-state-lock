resource "aws_instance" "ins" {
  ami           = "ami-0b6d9d3d33ba97d99"
  instance_type = "t3.micro"

  tags = {
    Name = "instance-01"
  }
}