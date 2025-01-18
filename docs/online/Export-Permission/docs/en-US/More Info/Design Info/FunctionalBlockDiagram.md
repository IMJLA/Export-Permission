# Functional Block Diagram

This page contains functional block diagrams representing the script and the functions it calls

## As-Built

### Markdown

#### Export-Permission

- 1
  - 1.1 **New-DatedSubfolder** Create a 3-tier folder structure with a folder for the current year, month, and timestamp.
  - 1.2 **Initialize-PermissionCache** Create an in-process cache to reduce calls to other processes, disk, or network, and to store repetitive parameters for better readability of code and logs.
- 2
  - 2.1 **Write-LogMsg** Prepend a prefix to a log message, write the message to an output stream, and write the message to a text file.
  - 2.2 **ConvertTo-PermissionFqdn** Get the FQDN of the computer running the script.
  - 2.3 **Get-PermissionTrustedDomain** Discover any domains trusted by the domain of the computer running the script.
  - 2.4 **Resolve-PermissionSource** Resolve source paths to network paths such as UNC paths (including all DFS folder targets).
  - 2.5 **Expand-PermissionSource** Expand parent paths into the paths of their children.
  - 2.6 **Find-ServerFqdn** Get the FQDN of this computer, each trusted domain, and each server in the paths.
  - 2.7 **Get-AccessControlList** Get the ACL of each path.
  - 2.8 **Optimize-PermissionCache** Query each FQDN to pre-populate caches, avoiding redundant ADSI and CIM queries.
  - 2.9 **Resolve-AccessControlList** Resolve each identity reference (from the ACLs) to its SID and NTAccount name.
  - 2.10 **Get-CurrentDomain** Get the current domain.
  - 2.11 **Get-PermissionPrincipal** Use ADSI and CIM to get details about each resolved identity reference.
  - 2.12 **Expand-Permission** Join access rules with their associated accounts.
  - 2.13 **Select-PermissionPrincipal** Hide domain names and include/exclude accounts as specified in the report parameters.
  - 2.14 **Invoke-PermissionAnalyzer** Analyze the permissions aginst established best practices.
  - 2.15 **Format-Permission** Format the permissions.
  - 2.16 **Out-PermissionFile** Export the report files.
- 3
  - 3.1 **Send-PrtgXmlSensorOutput** Send the results to a PRTG Custom XML Push Sensor for monitoring.
- 4
  - 4.1 **Out-Permission** Output the results to the pipeline.
  - 4.2 **Remove-CachedCimSession** Cleanup CIM sessions.
- 5
  - 5.1 **Export-LogCsv** Export the buffered log messages to a CSV file.

### Draw.IO XML Rendered as SVG

![As-Built](/img/FunctionalBlockDiagram_AsBuilt.svg)

## Original Design

This original design was discarded in favor of a flatter code structure.

### Markdown

#### Export-Permission

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

### MermaidJS Client-Side Rendering

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
