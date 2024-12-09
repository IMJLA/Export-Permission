# SplitBy None & GroupBy Account

## Target Paths

- C:\Folder1
- C:\Folder2

Includes all subfolders with unique permissions

## Network Paths

Local target paths were resolved to UNC paths, and UNC target paths were resolved to DFS folder targets

| Path | Inheritance |
|------|-------------|
| \\\\TestPC\\C$\\Folder1 | True/False |
| \\\\TestPC\\C$\\Folder2 | True/False |

## Accounts with Access

| Account Name | Account Property 1 | Account Property 2 | etc. |
|--------------|-------------|-------------|-------------|
| TestPC\\Account1 | - | - | ... |
| TestPC\\Account2 | - | - | ... |
| TestPC\\Account3 | - | - | ... |

## Access for Each Account

### TestPC\\Account1

| Path | Access | Due to Membership In | Source of Access |
|------|--------|----------------------|------------------|
| \\\\TestPC\\C$\\Folder1 | ReadAndExecute, Synchronize this folder but not subfolders | TestPC\\Group1 | Discretionary ACL |
| \\\\TestPC\\C$\\Folder1 | -1610612736 this folder, subfolders, and files | | Discretionary ACL |

### TestPC\\Account2

| Path | Access | Due to Membership In | Source of Access |
|------|--------|----------------------|------------------|
| \\\\TestPC\\C$\\Folder1 | FullControl this folder, subfolders, and files | | Ownership |

### TestPC\\Account3

| Path | Access | Due to Membership In | Source of Access |
|------|--------|----------------------|------------------|
| \\\\TestPC\\C$\\Folder2 | FullControl this folder, subfolders, and files | | Discretionary ACL |
