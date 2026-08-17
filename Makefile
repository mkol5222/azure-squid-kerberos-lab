.PHONY: up down init plan fmt validate go2dc go2proxy go2client

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
