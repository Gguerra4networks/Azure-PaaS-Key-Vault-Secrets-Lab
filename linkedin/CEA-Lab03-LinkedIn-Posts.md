# CEA Lab 03 - LinkedIn Post Series
# Modernizing to PaaS & Securing Secrets

Posting notes:
- Space the posts 2 to 3 days apart: Loom first, then GitHub, then Learned, then Different.
- Attach the matching thumbnail. LinkedIn does not accept SVG, so use the ready-made PNGs in `assets/thumbnails/png/`.
- Want something bolder with less text? Use the generic set in `assets/thumbnails/generic/png/` (g1 to g4 match posts 1 to 4).
- Post 3 and Post 4 land better with a real screenshot as a second image: `assets/screenshots/02-sqlcmd-end-to-end-success.png` or `05-monitor-successful-connections.png`.
- Put the Loom and GitHub links in the post body, not the first comment.
- Reply to every comment in the first hour.

---

## Post 1 - Loom Video

Thumbnail: `assets/thumbnails/png/post1-loom.png`  |  Generic: `assets/thumbnails/generic/png/g1-watch.png`

My web server just read a database password it was never given.

No config file. No hardcoded connection string. No password typed on the VM.

In Lab 03 of the Cloud Engineering Accelerator I retired a self-managed database VM and moved to Azure SQL Database. Then I locked the admin password inside Azure Key Vault and gave my Ubuntu web server a system-assigned managed identity.

Here is the flow. The VM proves who it is to Azure. Key Vault checks its RBAC role. The role is Key Vault Secrets User, which is read only. Key Vault hands back the secret and the VM uses it to connect.

Then I proved it live from the VM with three commands: az login --identity, az keyvault secret show, and a sqlcmd query against sqldb-app.

The SQL Azure version string came back. Full chain working.

In the video I walk through the finished build, the networking problem I ran into, and the live end-to-end test. About five minutes.

Watch it here: https://www.loom.com/share/f93414169d60403398382f7679b8b142

#Azure #AzureSQL #KeyVault #ManagedIdentity #CloudSecurity #CloudEngineering #LeastPrivilege #HomeLab #CareerChange #CEA

---

## Post 2 - GitHub Repo

Thumbnail: `assets/thumbnails/png/post2-github.png`  |  Generic: `assets/thumbnails/generic/png/g2-github.png`

Lab 03 is on GitHub. Everything you need to rebuild it is in one repo.

What is inside:

- A full SOP, from deleting the old database VM to the live sqlcmd test
- An architecture diagram showing the VM, Key Vault, and Azure SQL
- Azure CLI commands for every portal step
- A set-vars.ps1 file so nothing is hardcoded
- A troubleshooting table built from the real errors I hit
- A .gitignore that keeps keys, secrets, and state files out of Git

The stack: Azure SQL Database on the serverless tier, Azure Key Vault with RBAC, a system-assigned managed identity, Azure Monitor, VS Code Remote SSH, and sqlcmd.

Cost: close to $0 on the Azure SQL free offer plus a few cents of Key Vault calls. Stop the VM when you are done.

Time: 60 to 75 minutes.

If you are learning Azure security or getting ready for AZ-500, this is a solid hands-on rep. If it helps you, a star helps me.

github.com/Gguerra4networks/Azure-PaaS-Key-Vault-Secrets-Lab

#GitHub #Azure #AzureSQL #KeyVault #CloudSecurity #DevSecOps #CloudEngineering #AZ500 #PortfolioProject #CEA

---

## Post 3 - One Thing I Learned

Thumbnail: `assets/thumbnails/png/post3-learned.png`  |  Generic: `assets/thumbnails/generic/png/g3-learned.png`

The error said my database was unavailable. The real problem was my password.

While testing in the Azure SQL Query editor I got this: "Database sqldb-app on server sql-server-giovanni is not currently available."

My first thought was networking or a broken deployment. It was neither.

The database was on the serverless tier, and serverless auto-pauses when it sits idle. My login attempt woke it up. Until the resume finishes, Azure rejects every connection with that same message. It never gets far enough to check your credentials.

I waited a minute, clicked Connect again, and got the answer that mattered: Login failed for user sqladmin. I had lost the password. I reset it and stored the new one straight into Key Vault.

The lesson: on serverless Azure SQL, "not currently available" (error 40613) tells you nothing about authentication. Retry once before you troubleshoot anything else.

The same thing bites apps. If your code connects after an idle period, build in a retry.

Has an error message ever sent you down the wrong troubleshooting path even though it was technically true?

#AzureSQL #Serverless #Troubleshooting #Azure #CloudEngineering #KeyVault #DatabaseOps #HomeLab #CareerChange #CEA

---

## Post 4 - What I'd Do Differently

Thumbnail: `assets/thumbnails/png/post4-different.png`  |  Generic: `assets/thumbnails/generic/png/g4-different.png`

What I would do differently in Lab 03: check the SQL firewall before I need it.

After deploying Azure SQL through the portal, public network access on my server was set to Disabled. Every deployment check was green. Nothing could connect. Not the portal Query editor, not my VM.

I only found it at test time. Then I clicked through Networking, switched to Selected networks, added my client IP, and turned on Allow Azure services.

Next time I would set it and verify it with the CLI right after deployment:

az sql server update -g $RG -n $SQL_SERVER --enable-public-network true

az sql server firewall-rule create -g $RG -s $SQL_SERVER -n AllowAzureServices --start-ip-address 0.0.0.0 --end-ip-address 0.0.0.0

az sql server show -g $RG -n $SQL_SERVER --query publicNetworkAccess

Two minutes, and that last line gives you proof instead of hope.

One caveat. Allow Azure services opens the server to resources in any Azure tenant, not just mine. In production I would use a private endpoint or a VNet rule for the web subnet instead.

What is the first setting you check after a portal deployment?

#AzureSQL #AzureCLI #CloudSecurity #NetworkSecurity #Azure #CloudEngineering #LessonsLearned #HomeLab #DevOps #CEA
