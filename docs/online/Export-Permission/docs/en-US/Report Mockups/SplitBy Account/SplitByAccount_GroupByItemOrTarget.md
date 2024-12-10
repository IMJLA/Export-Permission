# SplitBy Account & GroupBy Item/Target

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

## Account Details for TestPC\\Account1

| Account Name | Account Property 1 | Account Property 2 | etc. |
|--------------|-------------|-------------|-------------|
| TestPC\\Account1 | - | - | ... |

## Access for TestPC\\Account1

### Access to \\\\TestPC\\C$\\Folder1

Inherited permissions from the parent (C) are included. This folder can only be accessed by the accounts listed here:

| Access | Due to Membership In | Source of Access | Account Property 1 | Account Property 2 | etc. |
|--------|----------------------|------------------|------------------|------------------|------------------|
| ReadAndExecute, Synchronize this folder but not subfolders | TestPC\\Group1 | Discretionary ACL | - | - | ... |
