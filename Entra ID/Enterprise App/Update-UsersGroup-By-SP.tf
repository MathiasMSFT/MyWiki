terraform {
  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.1.0"
    }
  }
}

provider "azuread" {
  tenant_id = "ee942b75-82c7-42bc-9585-ccc5628492d9"
}

# Variables (replace with your actual values or use variables)
locals {
  group_id    = "8853c9a7-6042-4c1c-9f6f-6b5d31914166"
  sp_id       = "9e068cca-daeb-4a9a-bcba-9879550a1bc5"
  app_role_id = "3b879099-9bc7-41e5-b49d-3b33bca31a5a"
}

# Data sources to fetch group and service principal
data "azuread_group" "target" {
  object_id = local.group_id
}

data "azuread_service_principal" "target" {
  object_id = local.sp_id
}

# Assign the group to the app role
resource "azuread_app_role_assignment" "group_assignment" {
  principal_object_id = data.azuread_group.target.object_id
  resource_object_id  = data.azuread_service_principal.target.object_id
  app_role_id         = local.app_role_id
}