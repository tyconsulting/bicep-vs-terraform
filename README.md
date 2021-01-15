# Bicep Vs Terraform

Sample Code for the Bicep vs. Terraform YouTube video

This is a sample pattern that deploys the following resources:

1. Resource Group
2. Key Vault
    * various secrets
3. Storage Account (only in Bicep)
4. Windows Server VM with SQL Server
5. SQL Virtual Machine
    * SQL license and edition
    * SQL port
    * SQL login (user name and password)
    * Automated Backup (only in Bicep)
    * Drive configuration
6. SQL VM Disk extension (only in Bicep)
