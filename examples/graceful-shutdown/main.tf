terraform {
  required_version = "0.11.11"

  backend "s3" {
    key            = "terraform-modules/development/terraform-aws-ecs/graceful-shutdown.tfstate"
    bucket         = "<test-account-id>-terraform-state"
    dynamodb_table = "<test-account-id>-terraform-state"
    acl            = "bucket-owner-full-control"
    encrypt        = "true"
    kms_key_id     = "<kms-key-id>"
    region         = "eu-west-1"
  }
}

provider "aws" {
  version             = "1.52.0"
  region              = "eu-west-1"
  allowed_account_ids = ["<test-account-id>"]
}

data "aws_vpc" "main" {
  default = true
}

data "aws_subnet_ids" "main" {
  vpc_id = "${data.aws_vpc.main.id}"
}

data "aws_region" "current" {}

module "alb" {
  source  = "telia-oss/loadbalancer/aws"
  version = "0.1.0"

  name_prefix = "example"
  vpc_id      = "${data.aws_vpc.main.id}"
  subnet_ids  = ["${data.aws_subnet_ids.main.ids}"]
  type        = "application"

  tags {
    environment = "prod"
    terraform   = "True"
  }
}

# ------------------------------------------------------------------------------
# ecs/cluster
# ------------------------------------------------------------------------------
data "aws_ami" "ecs" {
  owners      = ["amazon"]
  most_recent = true

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "name"
    values = ["amzn-ami*amazon-ecs-optimized"]
  }
}

module "cluster" {
  source = "../../modules/cluster"

  name_prefix         = "example"
  vpc_id              = "${data.aws_vpc.main.id}"
  subnet_ids          = ["${data.aws_subnet_ids.main.ids}"]
  instance_ami        = "${data.aws_ami.ecs.id}"
  load_balancers      = ["${module.alb.security_group_id}"]
  load_balancer_count = 1

  tags {
    environment = "prod"
    terraform   = "True"
  }
}

module "graceful-shutdown" {
  source = "github.com/itsdalmo/tf_aws_ecs_instance_draining_on_scale_in.git?ref=b87f60f"

  name_prefix            = "example"
  autoscaling_group_name = "${module.cluster.asg_id}"
}