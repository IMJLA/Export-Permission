````
Export-Permission
  Get-Permission (foreach Folder)
    Get-FolderAccessList
      Get-FolderAce
    Resolve-AccessList (foreach AccessControlEntry)
      Resolve-PermissionIdentity
        Resolve-Ace
          Resolve-IdentityReference
      Get-PermissionPrincipal
        ConvertFrom-IdentityReferenceResolved
      Format-PermissionAccount
        Format-SecurityPrincipal
      Select-UniqueAccountPermission
      Format-FolderPermission

  Export-PermissionCsv
  Export-PermissionHtml
````

```mermaid
---
title: Functional Block Diagram (planned)
---
flowchart TB

subgraph Export-Permission
    ExportPermission["Create CSV, HTML, and XML reports of permissions"]:::description
    subgraph Resolve-PermissionTarget
    ResolvePermissionTarget["Resolve each target path to all of its associated UNC paths (including all DFS folder targets)"]:::description
    end
    subgraph Expand-Folder
        ExpandFolder["Expand each UNC path into the paths of its subfolders"]:::description
    end
    subgraph Get-Permission
        GetPermission["Get detailed info about permissions"]:::description
        subgraph Get-FolderAccessList
            GetFolderAccessList["Get an object for each effective permission on a folder"]:::description
            subgraph Get-FolderAce
                GetFolderAce["Get an object for each access control entry in the discretionary access control list"]:::description
            end
            subgraph Get-OwnerAce
                GetOwnerAce["Get an object simulating a FullControl access control entry for the folder owner"]:::description
            end
        end
        subgraph Resolve-AccessListIdentity
            ResolveAccessListIdentity["Resolve the identities in the access lists to the accounts they represent"]:::description
            subgraph Resolve-PermissionIdentity
                subgraph Resolve-Ace
                end
            end
            subgraph Get-PermissionPrincipal
                subgraph ConvertFrom-IdentityReferenceResolved
                end
            end
            subgraph Format-PermissionAccount
                subgraph Format-SecurityPrincipal
                end
            end
            subgraph Select-UniqueAccountPermission
            end
            subgraph Format-FolderPermission
            end
        end
    end
    subgraph Export-PermissionCsv
    end
    subgraph Export-PermissionHtml
    end
end

%% Element type definitions

classDef person fill:#08427b
classDef internalSystem fill:#1168bd
classDef externalSystem fill:#999999

classDef type stroke-width:0px, color:#fff, fill:transparent, font-size:12px
classDef description stroke-width:0px, fill:transparent, font-size:13px
```
