# Cache Options

## What is Cached?

### Cached Caches

| Cache Name                       | Value Type                                | Value Description       | Key Type   | Key Description | Cache Purpose |
|----------------------------------|-------------------------------------------|-------------------------|------------|-----------------|---------------|
| **AceByGUID**                    | `[Object]`                                | Access Control Entry | `[String]` | GUID created in Resolve-Ace during this instance of report execution | Reduce random disk read operations |
| **AceGuidByID**                  | `[List[Guid]]`                            | List of ACE GUIDs     | `[String]` | Resolved NTAccount caption | Reduce random disk read operations |
| **AceGuidByPath**                | `[List[Guid]]`                            | List of ACE GUIDs     | `[String]` | Path of the item whose ACL contains the ACE | Reduce random disk read operations |
| **AclByPath**                    | `[PSCustomObject]`                        | Access Control List  | `[String]` | Path of the item associated with the ACL | Reduce random disk read operations |
| **CimCache**                     | `[PSReference]`                           | Nested cache of CIM sessions, instances, and query results. | `[String]` | CIM Server Name | Reduce CIM connections and queries |
| **DirectoryEntryByPath**         | `[Object]`                                | LDAP or WinNT security principal | `[String]` | ADSI path | Reduce ADSI queries |
| **DomainBySID**                  | `[Object]`                                | ADSI server | `[String]` | Server SID | Reduce ADSI and CIM queries |
| **DomainByNetbios**              | `[Object]`                                | ADSI server | `[String]` | Server NetBIOS name | Reduce ADSI and CIM queries |
| **DomainByFqdn**                 | `[Object]`                                | ADSI server | `[String]` | Server FQDN | Reduce ADSI and CIM queries |
| **ErrorByItemPath_Enumeration**  | `[String]`                                | Error during item enumeration | `[String]` | Path of the item associated with the error | Aggregate data during report instance execution |
| **ErrorByItemPath_AclRetrieval** | `[String]`                                | Error during ACL retrieval | `[String]` | Path of the item associated with the error | Aggregate data during report instance execution |
| **IdByShortName**                | `[List[String]]`                          | List of resolved NTAccount captions | `[String]` | Account name with the domain removed by the -IgnoreDomain parameter. | Aggregate data during report instance execution |
| **ParentBySourcePath**           | `String[]`                                | Array of Network Paths | `[System.IO.DirectoryInfo]` | Associated path from the -SourcePath parameter | Aggregate data during report instance execution |
| **PrincipalByID**                | `[PSCustomObject]`                        | Accounts | `[String]` | Resolved NTAccount caption | Reduce ADSI and CIM queries |
| **ShortNameByID**                | `[String]`                                | Account names with their domain removed by the -IgnoreDomain parameter | `[String]` | Resolved NTAccount caption | Aggregate data during report instance execution |

### Other Cached Values

| Cache Name | Cache Description | Cache Purpose |
|------------|-------------------|------------|
| **Culture** | *Get-Culture* | Reduce calls to Get-Culture |
| **ExcludeAccountFilterContents** | *Accounts excluded by the -ExcludeAccount parameter* | Aggregate data during report instance execution |
| **ExcludeClassFilterContents** | *Accounts excluded by the -ExcludeClass parameter* | Aggregate data during report instance execution |
| **IncludeAccountFilterContents** | *Accounts excluded by the -IncludeAccount parameter* | Aggregate data during report instance execution |
| **InheritanceFlagResolved** | *String translations indexed by value in the [System.Security.AccessControl.InheritanceFlags] enum* | This should become proper i8n later |
| **Log** | *Splat for Write-LogMsg* | Improve code readability |
| **LogBuffer** | *A cache of log messages, each message stored as an OrderedDictionary in a ConcurrentQueue* | Reduce random disk write operations |
| **LogEmptyMap** | *Splat for Write-LogMsg* | Improve code readability |
| **LogCacheMap** | *Splat for Write-LogMsg* | Improve code readability |
| **LogAnalysisMap** | *Splat for Write-LogMsg* | Improve code readability |
| **LogSourcePathMap** | *Splat for Write-LogMsg* | Improve code readability |
| **LogFormattedMap** | *Splat for Write-LogMsg* | Improve code readability |
| **LogStopWatchMap** | *Splat for Write-LogMsg* | Improve code readability |
| **LogCimMap** | *Splat for Write-LogMsg* | Improve code readability |
| **LogDirEntryMap** | *Splat for Write-LogMsg* | Improve code readability |
| **LogWellKnownMap** | *Splat for Write-LogMsg* | Improve code readability |
| **LogType** | *Splat for Write-LogMsg* | Share script parameters with dependencies |
| **ParamStringMap** | *Splat for Write-LogMsg* | Improve code readability |
| **ProgressParentId** | *Used for Write-Progress* | Share script execution information with dependencies |
| **ThisFqdn** | *[System.Net.Dns]::GetHostByName((hostname.exe)).HostName* | Reduce .Net method calls |
| **ThisHostname** | *hostname.exe* | Reduce calls to external processes |
| **ThreadCount** | *Export-Permission -ThreadCount parameter* | Share script parameters with dependencies |
| **WellKnownSidByCaption** | *A cache of known accounts local to an ADSI server* | Resolve unresolveable accounts as well as reduce queries to ADSI and CIM |
| **WellKnownSidByName** | *A cache of known accounts local to an ADSI server* | Resolve unresolveable accounts as well as reduce queries to ADSI and CIM |
| **WellKnownSidBySid** | *A cache of known accounts local to an ADSI server* | Resolve unresolveable accounts as well as reduce queries to ADSI and CIM |
| **WhoAmI** | *whoami.exe* | Reduce calls to external processes |

## CimCache

ToDo: Explain its structure

## PLANS

### Cache on Disk

Export-Permission > EFPosh > Entity Framework Core > Database Provider

[DotNet Core CLI](https://learn.microsoft.com/en-us/ef/core/providers/?tabs=dotnet-core-cli)

[EFPosh](https://github.com/Ryan2065/EFPosh)

#### First Level Cache

In-Memory, maintained by the EF DbContext

#### Second Level Cache

External Cache, distributed

Export-Permission > EFPosh > Entity Framework Core > EntityFrameworkCore.Cacheable > Memcached

[EntityFrameworkCore.Cacheable](https://github.com/SteffenMangold/EntityFrameworkCore.Cacheable)

### $PSCache: PowerShell-Only In-Process Caches

Used for things that can't be stored on disk like PSSessions and CIM Sessions.
