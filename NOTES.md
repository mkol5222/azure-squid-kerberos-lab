```bash

# deploy

```bash
time make up
```

# access proxy vm via bastion

```shell
SUB_ID=$(az account show --query id -o tsv)
BASTION_NAME=$(az network bastion list --resource-group rg-squid-kerberos-lab --query "[0].name" -o tsv)
az network bastion ssh --name "$BASTION_NAME" --resource-group rg-squid-kerberos-lab \
  --target-resource-id /subscriptions/$SUB_ID/resourceGroups/rg-squid-kerberos-lab/providers/Microsoft.Compute/virtualMachines/vm-proxy \
  --auth-type ssh-key --username azlabadmin \
  --ssh-key ~/.ssh/m4.pub -- -o IdentitiesOnly=yes
```

or
```shell
SSH_KEY=~/.ssh/m4.pub make ssh-proxy
```

# azlabadmin@lab.contoso.local 

```shell
SUB_ID=$(az account show --query id -o tsv)
BASTION_NAME=$(az network bastion list --resource-group rg-squid-kerberos-lab --query "[0].name" -o tsv)
az network bastion tunnel --name "$BASTION_NAME" --resource-group rg-squid-kerberos-lab \
  --target-resource-id /subscriptions/$SUB_ID/resourceGroups/rg-squid-kerberos-lab/providers/Microsoft.Compute/virtualMachines/vm-client1 \
  --resource-port 3389 --port 33388
```

| Field        | Value                        |
|--------------|------------------------------|
| AD username  | azlabadmin@lab.contoso.local |


In Makefile
```shell

SSH_KEY=~/.ssh/m4.pub make ssh-proxy

LOCAL_RDP_PORT=23338 make rdp-client

```
