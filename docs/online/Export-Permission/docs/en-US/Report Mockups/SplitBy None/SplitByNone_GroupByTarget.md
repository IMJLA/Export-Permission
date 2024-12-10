# SplitBy None & GroupBy Target

## Target Paths

- C:\Folder1
- C:\Folder2

Includes all subfolders with unique permissions

## Target Path C:\\Folder1

### Network Paths to C:\\Folder1

Local target paths were resolved to UNC paths, and UNC target paths were resolved to DFS folder targets

| Path | Inheritance |
|------|-------------|
| \\\\TestPC\\C$\\Folder1 | True/False |

### Permissions in C:\\Folder1

Inherited permissions from the parent (C) are included. This folder can only be accessed by the accounts listed here:

| Item | Account | Access | Due to Membership In | Source of Access | Account Property 1 | Account Property 2 | etc. |
|------|--------|----------------------|------------------|------------------|------------------|------------------|------------------|
| \\\\TestPC\\C$\\Folder1 | TestPC\\Account1 | ReadAndExecute, Synchronize this folder but not subfolders | TestPC\\Group1 | Discretionary ACL | - | - | ... |
| \\\\TestPC\\C$\\Folder1 | TestPC\\Account2 | FullControl this folder, subfolders, and files | | Ownership | - | - | ... |

## Target Path C:\\Folder2

### Network Paths to C:\\Folder2

Local target paths were resolved to UNC paths, and UNC target paths were resolved to DFS folder targets

| Path | Inheritance |
|------|-------------|
| \\\\TestPC\\C$\\Folder1 | True/False |

### Permissions in C:\\Folder2

| Item | Account | Access | Due to Membership In | Source of Access | Account Property 1 | Account Property 2 | etc. |
|------|--------|----------------------|------------------|------------------|------------------|------------------|------------------|
| \\\\TestPC\\C$\\Folder2 | TestPC\\Account3 | FullControl this folder, subfolders, and files | | Discretionary ACL | - | - | ... |
