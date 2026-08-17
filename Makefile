.PHONY: up down init plan fmt validate go2dc go2proxy go2client vms-stop vms-start bastion-down bastion-up

SSH_KEY ?= ~/.ssh/id_ed25519

init:
	terraform init

fmt:
	terraform fmt -recursive

validate: fmt
	terraform validate

plan: init
	terraform plan

up: init
	terraform apply -auto-approve

down:
	terraform destroy -auto-approve

go2dc:
	terraform output -json connect_via_bastion | jq -r '.rdp_to_dc' | sh

go2proxy:
	terraform output -json connect_via_bastion | jq -r '.ssh_to_proxy' | sed 's#<path-to-your-private-key>#$(SSH_KEY)#' | sh

go2client:
	terraform output -json connect_via_bastion | jq -r '.rdp_to_client' | sh

# Deallocate/start every VM in the lab's resource group (billing stops for
# deallocated compute, unlike a mere OS shutdown). Queries the live VM list
# from Azure rather than hardcoding names, so it covers vm-client1 whether
# or not deploy_test_client is enabled.
vms-stop:
	az vm deallocate --ids $$(az vm list --resource-group "$$(terraform output -raw resource_group_name)" --query "[].id" -o tsv)

vms-start:
	az vm start --ids $$(az vm list --resource-group "$$(terraform output -raw resource_group_name)" --query "[].id" -o tsv)

# Unlike VMs, Bastion has no stop/deallocate state -- it's billed hourly for
# as long as it exists. -var overrides terraform.tfvars' deploy_bastion for
# just this apply, so the file itself still reflects your steady-state
# preference. Destroys/recreates the bastion host, its NSG, subnet
# association, and public IP (all count = var.deploy_bastion ? 1 : 0);
# every other resource is untouched.
bastion-down:
	terraform apply -auto-approve -var deploy_bastion=false

bastion-up:
	terraform apply -auto-approve -var deploy_bastion=true
