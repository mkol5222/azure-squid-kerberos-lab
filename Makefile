.PHONY: sp-login up down init plan fmt validate go2dc go2proxy go2client ssh-proxy rdp-client vms-stop vms-start bastion-down bastion-up

SSH_KEY ?= ~/.ssh/id_ed25519
LOCAL_RDP_PORT ?= 33388
RESOURCE_GROUP ?= rg-squid-kerberos-lab
PROXY_VM_NAME ?= vm-proxy
ADMIN_USERNAME ?= azlabadmin

sp-login:
	@echo "Logging into Azure..."
	./sp-login.sh

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

# Standalone reproduction of NOTES.md's manual bastion ssh walkthrough --
# looks up the bastion and builds the target VM's resource ID itself
# rather than going through terraform output like go2proxy does.
ssh-proxy:
	sub_id=$$(az account show --query id -o tsv); \
	bastion_name=$$(az network bastion list --resource-group $(RESOURCE_GROUP) --query "[0].name" -o tsv); \
	az network bastion ssh --name "$$bastion_name" --resource-group $(RESOURCE_GROUP) \
	  --target-resource-id "/subscriptions/$$sub_id/resourceGroups/$(RESOURCE_GROUP)/providers/Microsoft.Compute/virtualMachines/$(PROXY_VM_NAME)" \
	  --auth-type ssh-key --username $(ADMIN_USERNAME) \
	  --ssh-key $(SSH_KEY) -- -o IdentitiesOnly=yes

# Opens a local port-forward to vm-client1:3389 via Bastion (see NOTES.md)
# instead of go2client's "az network bastion rdp", which launches the RDP
# client itself. Point an RDP client at localhost:$(LOCAL_RDP_PORT) once
# this is running; it blocks in the foreground until interrupted.
rdp-client:
	vm_id=$$(terraform output -json connect_via_bastion | jq -r '.rdp_to_client' | sed -E 's/.*--target-resource-id ([^ ]+).*/\1/'); \
	az network bastion tunnel --name "$$(terraform output -raw bastion_name)" \
	  --resource-group "$$(terraform output -raw resource_group_name)" \
	  --target-resource-id "$$vm_id" \
	  --resource-port 3389 --port $(LOCAL_RDP_PORT)

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
