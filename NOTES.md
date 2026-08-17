```bash

az network bastion ssh --name bastion-squidkrb-usspv --resource-group rg-squid-kerberos-lab \
  --target-resource-id <vm-proxy-id> --auth-type ssh-key --username azlabadmin \
  --ssh-key ~/.ssh/id_ed25519 -- -o IdentitiesOnly=yes


az network bastion ssh --name bastion-squidkrb-usspv --resource-group rg-squid-kerberos-lab \
  --target-resource-id /subscriptions/f4ad5e85-ec75-4321-8854-ed7eb611f61d/resourceGroups/rg-squid-kerberos-lab/providers/Microsoft.Compute/virtualMachines/vm-proxy \
  --auth-type ssh-key --username azlabadmin \
  --ssh-key ~/.ssh/id_ed25519 -- -o IdentitiesOnly=yes


# WORKING

az network bastion ssh --name bastion-squidkrb-usspv --resource-group rg-squid-kerberos-lab \
  --target-resource-id /subscriptions/f4ad5e85-ec75-4321-8854-ed7eb611f61d/resourceGroups/rg-squid-kerberos-lab/providers/Microsoft.Compute/virtualMachines/vm-proxy \
  --auth-type ssh-key --username azlabadmin \
  --ssh-key ~/.ssh/m4.pub -- -o IdentitiesOnly=yes

KV=$(terraform output -raw key_vault_name)
az keyvault secret show --vault-name "$KV" --name client-local-admin-password --query value -o tsv

az keyvault secret show --vault-name "$KV" --name dc-local-admin-password --query value -o tsv

# azlabadmin@lab.contoso.local 

az network bastion tunnel --name bastion-squidkrb-usspv --resource-group rg-squid-kerberos-lab \
  --target-resource-id /subscriptions/f4ad5e85-ec75-4321-8854-ed7eb611f61d/resourceGroups/rg-squid-kerberos-lab/providers/Microsoft.Compute/virtualMachines/vm-client1 \
  --resource-port 3389 --port 13388

azlabadmin@lab.contoso.local 
  ...
