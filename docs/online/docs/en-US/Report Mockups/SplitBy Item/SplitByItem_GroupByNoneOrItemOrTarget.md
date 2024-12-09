# SplitBy Item & GroupBy None/Item/Target

## Item

| Path | Inheritance |
|------|-------------|
| \\\\TestPC\\C$\\Folder1 | True/False |

### Permissions in \\\\TestPC\\C$\\Folder1

| Account | Access | Due to Membership In | Source of Access | Account Property 1 | Account Property 2 | etc. |
|--------|----------------------|------------------|------------------|------------------|------------------|------------------|
| TestPC\\Account1 | ReadAndExecute, Synchronize this folder but not subfolders | TestPC\\Group1 | Discretionary ACL | - | - | ... |
| TestPC\\Account2 | FullControl this folder, subfolders, and files | | Ownership | - | - | ... |
