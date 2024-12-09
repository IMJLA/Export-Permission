# SplitBy Item & GroupBy Account

## Item

| Path | Inheritance |
|------|-------------|
| \\\\TestPC\\C$\\Folder1 | True/False |

## Accounts with Access

| Account Name | Account Property 1 | Account Property 2 | etc. |
|--------------|-------------|-------------|-------------|
| TestPC\\Account1 | - | - | ... |
| TestPC\\Account2 | - | - | ... |

## Access for Each Account

### TestPC\\Account1

| Access | Due to Membership In | Source of Access |
|--------|----------------------|------------------|
| ReadAndExecute, Synchronize this folder but not subfolders | TestPC\\Group1 | Discretionary ACL |
| -1610612736 this folder, subfolders, and files | | Discretionary ACL |

### TestPC\\Account2

| Access | Due to Membership In | Source of Access |
|--------|----------------------|------------------|
| FullControl this folder, subfolders, and files | | Ownership |
