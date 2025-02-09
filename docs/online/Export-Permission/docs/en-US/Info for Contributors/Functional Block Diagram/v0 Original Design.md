# v0 Original Design

This original design was discarded in favor of a flatter code structure.

## Markdown

### Export-Permission

- Get-Permission
  - (foreach LiteralPath)
    - Resolve-PermissionSource
    - (foreach ResolvedLiteralPath)
      - Expand-PermissionSource
      - (foreach ExpandedResolvedLiteralPath)
        - Get-FolderAcl
          - Get-DirectorySecurity
          - Get-OwnerAce
        - Resolve-AccessControlList
          - Resolve-Acl
            - (foreach AccessControlEntry)
              - Resolve-Ace
                - Resolve-IdentityReferenceDomainDNS
                - Get-AdsiServer
                - Resolve-IdentityReference
              - Get-PermissionPrincipal
                - ConvertFrom-IdentityReferenceResolved
                  - Get-DirectoryEntry -or
                  - Get-WinNTGroupMember -or
                  - Search-Directory
                  - (foreach GroupMember)
                    - Get-AdsiGroupMember -or
                    - Get-WinNTGroupMember
              - Format-PermissionAccount
                - Format-SecurityPrincipal
              - Select-UniqueAccountPermission
              - Format-FolderPermission
- Export-PermissionCsv
- Export-PermissionHtml

## MermaidJS Client-Side Rendering

```mermaid
flowchart TB

subgraph Export-Permission
    ExportPermission["Create CSV, HTML, and XML reports of permissions"]:::description
    subgraph Resolve-PermissionSource
    ResolvePermissionSource["Resolve each Source path to all of its associated UNC paths (including all DFS folder targets)"]:::description
    end
    subgraph Expand-Folder
        ExpandFolder["Expand each UNC path into the paths of its subfolders"]:::description
    end
    subgraph Get-Permission
        GetPermission["Get detailed info about permissions and the accounts with them"]:::description
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
            ResolveAccessListIdentity["Resolve and expand the identities in the access lists to the accounts they represent"]:::description
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
