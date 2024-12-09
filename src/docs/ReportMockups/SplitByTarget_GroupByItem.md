# Permissions Report Mockup for -SplitBy 'target' -GroupBy 'item'

## Target Paths

- C:\Folder1

Includes all subfolders with unique permissions

## Network Paths

Local target paths were resolved to UNC paths, and UNC target paths were resolved to DFS folder targets

| Path | Inheritance |
|------|-------------|
| \\\\TestPC\\C$\\Folder1 | True/False |

## Items in Those Paths with Unique Permissions

| Path | Inheritance |
|------|-------------|
| \\\\TestPC\\C$\\Folder1 | True/False |

## Accounts Included in Those Permissions

### Accounts with Access to \\\\TestPC\\C$\\Folder1

Inherited permissions from the parent (C) are included. This folder can only be accessed by the accounts listed here:

| Account | Access | Due to Membership In | Source of Access | Account Property 1 | Account Property 2 | etc. |
|------|--------|----------------------|------------------|------------------|------------------|------------------|
| TestPC\\Account1 | ReadAndExecute, Synchronize this folder but not subfolders | TestPC\\Group1 | Discretionary ACL | - | - | ... |
| TestPC\\Account2 | FullControl this folder, subfolders, and files | | Ownership | - | - | ... |
