# ============================================================
# CEA Lab 03 - Modernizing to PaaS & Securing Secrets
# Load with:  . .\set-vars.ps1   (dot-space-dot so vars stay in your session)
# No passwords live in this file. The SQL password goes straight into Key Vault.
# ============================================================

# ---- Names ----
$YOURNAME    = "giovanni"                      # same string you used in Lab 02
$RG          = "rg-lab03-$YOURNAME"            # Lab 03 resource group (SQL + Key Vault)
$RG_WEB      = "rg-lab02-$YOURNAME"            # Lab 02 resource group (vm-web-01 lives here)
$LOCATION    = "westus3"                       # keep SQL and Key Vault in the same region

# ---- Azure SQL ----
$SQL_SERVER  = "sql-server-$YOURNAME"          # must be globally unique, lowercase
$SQL_DB      = "sqldb-app"
$SQL_ADMIN   = "sqladmin"
$SQL_FQDN    = "$SQL_SERVER.database.windows.net"

# ---- Key Vault ----
$KV_NAME     = "kv-lab03-$YOURNAME"            # 3-24 chars, globally unique
$SECRET_NAME = "SqlAdminPassword"

# ---- Web VM from Lab 02 ----
$VM_NAME     = "vm-web-01"
$OLD_DB_VM   = "vm-db-01"

# ---- Your public IP (for the SQL firewall rule) ----
$MY_IP       = (Invoke-RestMethod -Uri "https://api.ipify.org")

# ---- Confirmation ----
Write-Host ""
Write-Host "CEA Lab 03 variables loaded" -ForegroundColor Cyan
Write-Host "  RG          : $RG"
Write-Host "  RG_WEB      : $RG_WEB"
Write-Host "  LOCATION    : $LOCATION"
Write-Host "  SQL_SERVER  : $SQL_SERVER"
Write-Host "  SQL_DB      : $SQL_DB"
Write-Host "  SQL_ADMIN   : $SQL_ADMIN"
Write-Host "  SQL_FQDN    : $SQL_FQDN"
Write-Host "  KV_NAME     : $KV_NAME"
Write-Host "  SECRET_NAME : $SECRET_NAME"
Write-Host "  VM_NAME     : $VM_NAME"
Write-Host "  OLD_DB_VM   : $OLD_DB_VM"
Write-Host "  MY_IP       : $MY_IP"
Write-Host ""
