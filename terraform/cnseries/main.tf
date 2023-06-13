############################################################################################
# Copyright 2020 Palo Alto Networks.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
############################################################################################


terraform {
  required_version = ">= 0.13"
  required_providers {
    aws = {
      version = ">= 2.28.1"
    }
    random = {
      version = "~> 2.1"
    }
    null = {
      version = "~> 2.1"
    }
    template = {
      version = "~> 2.1"
    }
    tls = {
      version = "~> 3.3"
    }
  }
}

provider "aws" {
  region = var.region
}

module "management-vpc" {
  source          = "../modules/vpc"
  vpc             = var.management-vpc
  prefix-name-tag = var.prefix-name-tag
  subnets         = var.management-vpc-subnets
  route-tables    = var.management-vpc-route-tables
  security-groups = var.management-vpc-security-groups
  global_tags     = var.global_tags
}

resource "aws_network_interface" "private" {
  subnet_id       = module.management-vpc.subnet_ids["${module.management-vpc.vpc_name}-${var.panorama.subnet_name}"]
  private_ips     = var.panorama.private_ips
  security_groups = [module.management-vpc.security_groups["${var.prefix-name-tag}${var.panorama.security_group}"]]
  tags = merge({ Name = "${var.prefix-name-tag}${var.panorama.name}-primary-interface" }, var.global_tags)
}

resource "aws_instance" "this" {
  ami                         = var.panorama.ami
  instance_type               = var.panorama.instance_type
  key_name                    = module.management-vpc.ssh_key_name
  network_interface {
    network_interface_id = aws_network_interface.private.id
    device_index = 0
  }

  tags = merge({ Name = "${var.prefix-name-tag}${var.panorama.name}" }, var.global_tags)
}

resource "aws_eip" "elasticip" {}

resource "aws_eip_association" "eip_assoc" {
  allocation_id = aws_eip.elasticip.id
  network_interface_id = aws_network_interface.private.id
}

locals {
  vpcs = {
    "${module.management-vpc.vpc_details.name}"  : module.management-vpc.vpc_details
  }
}

module "vpc-routes" {
  source          = "../modules/vpc_routes"
  vpc-routes      = var.management-vpc-routes
  vpcs            = local.vpcs
  prefix-name-tag = var.prefix-name-tag
}
