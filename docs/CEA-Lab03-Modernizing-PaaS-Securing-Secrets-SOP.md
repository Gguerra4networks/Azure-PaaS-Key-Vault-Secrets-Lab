# CEA Lab 03 SOP - Modernizing to PaaS & Securing Secrets

Azure SQL Database, Azure Key Vault, Managed Identity, RBAC, Azure Monitor

This SOP gives both paths for each phase: the Azure Portal clicks, and the Azure CLI commands that do the same thing. Pick one per phase. Every phase ends with a verification command.

---

## Before You Open VS Code

- Make sure you completed Lab 02, and vm-web-01 exists in rg-lab02-[yourname].
- In the portal, open vm-web-01. If Status says **Stopped (deallocated)**, click **Start** and wait for **Running**.
- Note the VM's **Primary NIC public IP**. If it changed since Lab 02, update `HostName` for `lab02-web` in your SSH config.
- Have a password manager or a notepad ready for the SQL admin password. You will type it twice, then it lives only in Key Vault.

**NOTE:** Use the same `[yourname]` string as Lab 02. In this build it is `giovanni`.

---

## Step 0 - Save Your Variables First

Loading all names from one file stops typos and means nothing is hardcoded in the commands below.

**VS CODE:** Local window, not Remote SSH.

**PATH:** PowerShell terminal in your lab folder, for example `C:\Users\<you>\Documents\CEA LABS\Azure-PaaS-Key-Vault-Secrets-Lab`.

Load the variables:

```powershell
. .\set-vars.ps1
```

Sign in to Azure if you have not already:

```powershell
az login
```

**Verify:** the script prints every variable in cyan, and this shows your subscription:

```powershell
az account show --query "{name:name, id:id}" -o table
```

---

## Phase 1 - Decommission the Old Database VM

A stopped VM still bills for its disk. Real decommissioning means deleting the VM, its OS disk, and its NIC.

**Portal:** Resource groups > rg-lab02-[yourname] > tick vm-db-01, its `_OsDisk_` disk, and its NIC > **Delete** > type `delete` > **Delete**.

**CLI:** Save the disk and NIC IDs before deleting the VM, because you cannot look them up after.

```powershell
$OLD_DISK = az vm show -g $RG_WEB -n $OLD_DB_VM --query "storageProfile.osDisk.managedDisk.id" -o tsv
```

```powershell
$OLD_NIC = az vm show -g $RG_WEB -n $OLD_DB_VM --query "networkProfile.networkInterfaces[0].id" -o tsv
```

```powershell
az vm delete -g $RG_WEB -n $OLD_DB_VM --yes
```

```powershell
az disk delete --ids $OLD_DISK --yes
```

```powershell
az network nic delete --ids $OLD_NIC
```

**NOTE:** Do not delete the resource group or vm-web-01. The leftover `nsg-db-01` is harmless and free.

**Verify:** vm-db-01 is gone and vm-web-01 is still there.

```powershell
az vm list -g $RG_WEB --query "[].name" -o tsv
```

---

## Phase 2 - Deploy Azure SQL Database

The SQL server is a logical container (admin login, firewall, region). The database lives inside it.

**Portal:** Search **SQL databases** > **+ Create** dropdown > **SQL database**.

- Resource group: **Create new** > `rg-lab03-[yourname]`
- Database name: `sqldb-app` (clear the auto-filled name)
- Server: **Create new** > `sql-server-[yourname]`, region **West US 3** (or your region), **Use SQL authentication**, login `sqladmin`, strong password
- Workload environment: **Development**
- Compute + storage: Basic DTU if the free offer is removed, or the free serverless offer with **Auto-pause the database until next month**
- Backup storage redundancy: **Locally-redundant**
- Networking tab: **Public endpoint**, Allow Azure services **Yes**, Add current client IP **Yes**
- Security tab: Microsoft Defender for SQL **Not now**

**NOTE:** In this build the free offer was applied, so the database landed on **General Purpose Serverless**. That is fine. Do not switch tiers from Compute + storage afterward. Some vCore options there cost hundreds per month.

**CLI:** Create the resource group.

```powershell
az group create --name $RG --location $LOCATION
```

Type the admin password once, masked. It is never saved to a file.

```powershell
$SQL_PW = Read-Host "SQL admin password" -MaskInput
```

Create the server.

```powershell
az sql server create -g $RG -n $SQL_SERVER -l $LOCATION `
  --admin-user $SQL_ADMIN --admin-password $SQL_PW `
  --minimal-tls-version 1.2
```

Create the database on the free serverless offer.

```powershell
az sql db create -g $RG -s $SQL_SERVER -n $SQL_DB `
  --edition GeneralPurpose --compute-model Serverless --family Gen5 --capacity 1 `
  --use-free-limit --free-limit-exhaustion-behavior AutoPause `
  --backup-storage-redundancy Local
```

**SECURITY:** Keep `$SQL_PW` in this session until Phase 5, then remove it.

**Verify:** status is Online (or Paused, which is normal for serverless).

```powershell
az sql db show -g $RG -s $SQL_SERVER -n $SQL_DB --query "{name:name, status:status, sku:currentSku.name}" -o table
```

---

## Phase 3 - Open the SQL Firewall (the fix)

In this build the server came out with **Public network access: Disabled**. Nothing could connect, not the Query editor and not the VM. Check this before you need it.

**Portal:** sql-server-[yourname] > **Security** > **Networking** > **Selected networks** > **+ Add your client IPv4 address** > tick **Allow Azure services and resources to access this server** > **Save**.

**CLI:** Turn public access on.

```powershell
az sql server update -g $RG -n $SQL_SERVER --enable-public-network true
```

Allow your own IP.

```powershell
az sql server firewall-rule create -g $RG -s $SQL_SERVER -n AllowMyIP `
  --start-ip-address $MY_IP --end-ip-address $MY_IP
```

Allow Azure services, which is what lets vm-web-01 connect.

```powershell
az sql server firewall-rule create -g $RG -s $SQL_SERVER -n AllowAllWindowsAzureIps `
  --start-ip-address 0.0.0.0 --end-ip-address 0.0.0.0
```

**SECURITY:** The 0.0.0.0 rule allows Azure resources from any tenant, not only yours. It is fine for a lab. In production use a private endpoint or a VNet rule on the web subnet.

**FIX:** Public network access changed from Disabled to Selected networks.

**Verify:**

```powershell
az sql server show -g $RG -n $SQL_SERVER --query publicNetworkAccess -o tsv
```

```powershell
az sql server firewall-rule list -g $RG -s $SQL_SERVER -o table
```

Expected: `Enabled`, and two rules listed.

---

## Phase 4 - Deploy Azure Key Vault and Grant Yourself Access

Key Vault stores the password so it never sits in code or config. With RBAC, nobody has access by default, including you.

**Portal:** Search **Key vaults** > **+ Create**. Resource group `rg-lab03-[yourname]`, name `kv-lab03-[yourname]`, same region as SQL, **Standard**, purge protection **disabled**. Access configuration: **Azure role-based access control**. Networking: defaults. **Review + create** > **Create**.

Then on the vault: **Access control (IAM)** > **+ Add** > **Add role assignment** > **Key Vault Administrator** > **User, group, or service principal** > select your account > **Review + assign** twice.

**CLI:** Create the vault with RBAC.

```powershell
az keyvault create -n $KV_NAME -g $RG -l $LOCATION --enable-rbac-authorization true --sku standard
```

Save the vault's resource ID for role scopes.

```powershell
$KV_ID = az keyvault show -n $KV_NAME --query id -o tsv
```

Get your own object ID.

```powershell
$ME = az ad signed-in-user show --query id -o tsv
```

Assign yourself Key Vault Administrator on this vault only.

```powershell
az role assignment create --assignee-object-id $ME --assignee-principal-type User `
  --role "Key Vault Administrator" --scope $KV_ID
```

**NOTE:** Wait 1 to 2 minutes for the role to take effect before Phase 5.

**Verify:**

```powershell
az role assignment list --scope $KV_ID --query "[].{who:principalName, role:roleDefinitionName}" -o table
```

---

## Phase 5 - Store the SQL Password as a Secret

**Portal:** Key vault > **Objects** > **Secrets** > **+ Generate/Import**. Name `SqlAdminPassword`, value = the SQL admin password, leave dates unchecked, Enabled **Yes** > **Create**.

**CLI:** Store the secret from the masked variable in Phase 2.

```powershell
az keyvault secret set --vault-name $KV_NAME --name $SECRET_NAME --value $SQL_PW --output none
```

Remove the password from your laptop session.

```powershell
Remove-Variable SQL_PW
```

**SECURITY:** `--output none` stops the CLI from printing the secret value back to your terminal.

**NOTE:** Lost the password? Reset it first: sql-server-[yourname] > Overview > **Reset password**, or run `az sql server update -g $RG -n $SQL_SERVER --admin-password (Read-Host -MaskInput)`, then store the new one.

**Verify:** shows the secret name and `True`, never the value.

```powershell
az keyvault secret show --vault-name $KV_NAME --name $SECRET_NAME --query "{name:name, enabled:attributes.enabled}" -o table
```

---

## Phase 6 - Enable Managed Identity and Grant Read Access

The VM gets its own Entra ID identity, then a read-only role on the vault.

**Portal, Part A:** vm-web-01 > **Security** > **Identity** > System assigned **On** > **Save** > **Yes**. Copy the **Object (principal) ID**.

**Portal, Part B:** kv-lab03-[yourname] > **Access control (IAM)** > **+ Add** > **Add role assignment** > **Key Vault Secrets User** > **Managed identity** > **+ Select members** > Managed identity: **Virtual machine** > vm-web-01 > **Select** > **Review + assign** twice.

**NOTE:** The second **Review + assign** click is the one that saves. In this build it was missed the first time and the VM did not show up in Role assignments.

**CLI:** Turn on the identity and capture its principal ID.

```powershell
$VM_PRINCIPAL = az vm identity assign -g $RG_WEB -n $VM_NAME --query systemAssignedIdentity -o tsv
```

Grant Key Vault Secrets User, scoped to this vault only.

```powershell
az role assignment create --assignee-object-id $VM_PRINCIPAL --assignee-principal-type ServicePrincipal `
  --role "Key Vault Secrets User" --scope $KV_ID
```

**SECURITY:** Key Vault Secrets User can read secret values. It cannot create, update, or delete. Scoping to the vault, not the resource group, keeps the blast radius small.

**Verify:** both your admin role and the VM's read role are listed.

```powershell
az role assignment list --scope $KV_ID --query "[].{who:principalName, type:principalType, role:roleDefinitionName}" -o table
```

---

## Phase 7 - Validate With Azure Monitor

Metrics prove the database is alive and being watched.

**Portal:** sqldb-app > **Monitoring** > **Metrics**. Metric **CPU percentage**, aggregation **Max** (use **DTU percentage** on the Basic tier). Then **+ Add metric** > **Successful Connections**, aggregation **Sum**. Time range **Last 4 hours**.

**NOTE:** Both metrics share one axis. A spike to "2" on Successful Connections is 2 connections, not 2 percent.

**CLI:**

```powershell
$DB_ID = az sql db show -g $RG -s $SQL_SERVER -n $SQL_DB --query id -o tsv
```

**Verify:**

```powershell
az monitor metrics list --resource $DB_ID --metric connection_successful --aggregation Total --interval PT1H -o table
```

---

## Phase 8 - End-to-End Test From vm-web-01

Every earlier check proved a piece exists. This proves the VM can actually get the secret and use it.

**VS CODE:** Remote window. Click the `><` icon bottom-left > **Connect to Host** > **lab02-web**. Open a terminal with Ctrl + backtick.

**PATH:** Bash on the VM. Prompt reads `azureuser@vm-web-01:~$`. The Windows variables from set-vars.ps1 do not exist here, so names are written out.

Install the Azure CLI on the VM (one time).

```bash
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
```

Log in as the VM's managed identity. No password.

```bash
az login --identity
```

Pull the secret into memory and print only its length.

```bash
SQL_PASSWORD=$(az keyvault secret show \
  --vault-name kv-lab03-giovanni \
  --name SqlAdminPassword \
  --query value -o tsv)
echo "Retrieved a password ${#SQL_PASSWORD} characters long"
```

**SECURITY:** Never `echo "$SQL_PASSWORD"`. The point of the lab is that no human sees it again.

Add the Microsoft package key (one time).

```bash
curl https://packages.microsoft.com/keys/microsoft.asc | sudo tee /etc/apt/trusted.gpg.d/microsoft.asc
```

Add the Microsoft package repo (one time).

```bash
curl https://packages.microsoft.com/config/ubuntu/22.04/prod.list | sudo tee /etc/apt/sources.list.d/mssql-release.list
```

Install sqlcmd. `ACCEPT_EULA=Y` stops apt from hanging on a license prompt.

```bash
sudo apt update -y && sudo ACCEPT_EULA=Y apt install -y mssql-tools18 unixodbc-dev
```

Put sqlcmd on your PATH.

```bash
echo 'export PATH="$PATH:/opt/mssql-tools18/bin"' >> ~/.bashrc && source ~/.bashrc
```

**Verify:** query the database with the secret from Key Vault.

```bash
sqlcmd -S sql-server-giovanni.database.windows.net -d sqldb-app \
  -U sqladmin -P "$SQL_PASSWORD" -C \
  -Q "SELECT @@VERSION;"
```

Expected: `Microsoft SQL Azure (RTM) - 12.0.2000.8` and `(1 rows affected)`.

Clear the secret from the session.

```bash
unset SQL_PASSWORD
```

**FIX:** Full chain confirmed: managed identity > Key Vault > Azure SQL.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| VS Code Remote SSH: "connection timed out" | vm-web-01 is Stopped (deallocated), or its public IP changed | Start the VM. Update `HostName` in the SSH config if the IP changed. Confirm the Allow-SSH-MyIP NSG rule matches your current IP. |
| Query editor: "Database sqldb-app ... is not currently available" (40613) | Serverless database is auto-paused and waking up | Wait about 60 seconds and retry. This error says nothing about your password. |
| Query editor: "Login failed for user 'sqladmin'" | Wrong password | Reset it on the SQL server Overview page, then update the Key Vault secret. |
| Nothing can connect to SQL | Public network access is Disabled | Phase 3: Selected networks, client IP rule, Allow Azure services. |
| Secrets page: "not authorized by RBAC" | Your user has no role on the vault | Assign yourself Key Vault Administrator. Wait 1 to 2 minutes. |
| vm-web-01 missing from Role assignments | Final **Review + assign** click was skipped, or identity not saved | Redo Phase 6 Part B. Confirm Identity shows an Object ID. |
| `az login --identity` fails: no identity found | Managed identity off or not propagated | Phase 6 Part A. Wait 1 to 2 minutes. |
| `az keyvault secret show` returns Forbidden or length 0 | Key Vault Secrets User role missing | Check the vault's Role assignments for vm-web-01. |
| apt install hangs | `ACCEPT_EULA=Y` missing | Ctrl+C, rerun with `ACCEPT_EULA=Y`. |
| sqlcmd TLS or certificate error | Missing `-C`, or firewall blocking Azure services | Add `-C`. Check Phase 3. |
| Metrics chart empty | No metric selected, or database paused the whole window | Pick a metric. Widen the time range. Wait 5 minutes and refresh. |
| DTU percentage not in the list | Database is on serverless, not Basic | Use CPU percentage. |

---

## Clean Up

Delete the Lab 03 resource group. This removes the SQL server, database, and Key Vault.

```powershell
az group delete --name $RG --yes --no-wait
```

Stop the web VM so it stops billing compute.

```powershell
az vm deallocate -g $RG_WEB -n $VM_NAME
```

**NOTE:** Key Vault is soft-deleted for 90 days. To reuse the same name right away, purge it:

```powershell
az keyvault purge --name $KV_NAME
```

Keep rg-lab02-[yourname] if later labs use vm-web-01.

**Verify:**

```powershell
az group exists --name $RG
```

Expected: `false`.

---

## What You Built

| Resource | Name | Purpose |
|---|---|---|
| Resource group | rg-lab03-giovanni | Holds the PaaS and secrets resources |
| Azure SQL logical server | sql-server-giovanni | Admin login, firewall, TLS 1.2 |
| Azure SQL Database | sqldb-app | Managed database replacing vm-db-01 |
| SQL firewall | Selected networks, client IP, Azure services | Controls who can reach the server |
| Key Vault | kv-lab03-giovanni | RBAC-protected secret store |
| Secret | SqlAdminPassword | The only place the SQL password lives |
| Managed identity | vm-web-01 (system-assigned) | Passwordless identity for the VM |
| Role assignment | Key Vault Secrets User on the vault | Least-privilege read for the VM |
| Role assignment | Key Vault Administrator on the vault | Management for the operator |
| Monitoring | CPU percentage + Successful Connections | Proof the database is live and observed |
| Decommissioned | vm-db-01, disk, NIC | Old IaaS database removed |
