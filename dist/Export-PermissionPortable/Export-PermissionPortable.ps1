<#PSScriptInfo

.VERSION 0.0.361

.GUID c7308309-badf-44ea-8717-28e5f5beffd5

.AUTHOR Jeremy La Camera

.COMPANYNAME Jeremy La Camera

.COPYRIGHT (c) Jeremy La Camera. All rights reserved.

.TAGS adsi ldap winnt ntfs acl

.LICENSEURI https://github.com/IMJLA/Export-Permission/blob/main/LICENSE

.PROJECTURI https://github.com/IMJLA/Export-Permission

.ICONURI

.EXTERNALMODULEDEPENDENCIES 

.REQUIREDSCRIPTS

.EXTERNALSCRIPTDEPENDENCIES

.RELEASENOTES
update psrunspace module

.PRIVATEDATA

#>

<# 

.DESCRIPTION 
 Present complex nested permissions and group memberships in a report that is easy to read
Provide additional information about each account such as Name, Department, Title
Multithreaded with caching for fast results
Works as a scheduled task
Works as a custom sensor script for Paessler PRTG Network Monitor (Push sensor recommended due to execution time)

Supports:
- Local folder paths
- UNC folder paths
- DFS folder paths
- Mapped network drives
- Active Directory domain trusts
- Unresolved SIDs for deleted accounts
- Group memberships via the Primary Group as well as the memberOf property

Does not support these scenarios:
- ACL Owners or Groups (ToDo enhancement; for now only the DACL is reported)
- File permissions (ToDo enhancement; for now only folder permissions are reported)
- Share permissions (ToDo enhancement; for now only NTFS permissions are reported)

Behavior:
- Resolves each path in the TargetPath parameter
  - Local paths become UNC paths using the administrative shares, so the computer name is shown in reports
  - DFS paths become all of their UNC folder targets, including disabled ones
  - Mapped network drives become their UNC paths
- Gets all permissions for the resolved paths
- Gets non-inherited permissions for subfolders (if specified)
- Exports the permissions to a .csv file
- Uses ADSI to get information about the accounts and groups listed in the permissions
- Exports information about the accounts and groups to a .csv file
- Uses ADSI to recursively retrieve group members
  - Retrieves group members using both the memberOf and primaryGroupId attributes
  - Members of nested groups are retrieved as members of the group listed in the permissions.
      - Their hierarchy of nested group memberships is not retrieved (for performance reasons).
- Exports information about all accounts with access to a .csv file
- Exports information about all accounts with access to a report generated as a .html file
- Outputs an XML-formatted list of common misconfigurations for use in Paessler PRTG Network Monitor as a custom XML sensor 

#>
param (
    [Parameter(ValueFromPipeline)]
    [ValidateScript({ Test-Path $_ })]
    [System.IO.DirectoryInfo[]]$TargetPath,
    [string[]]$ExcludeAccount = 'SYSTEM',
    [string[]]$IncludeAccount,
    [string[]]$ExcludeClass = @('group', 'computer'),
    [string[]]$IgnoreDomain,
    [string]$OutputDir = "$env:AppData\Export-Permission",
    [switch]$NoMembers,
    [int]$RecurseDepth = -1,
    [string]$Title = 'Permissions Report',
    [scriptblock]$AccountConvention = { $true },
    [uint16]$ThreadCount = (Get-CimInstance -ClassName CIM_Processor | Measure-Object -Sum -Property NumberOfLogicalProcessors).Sum,
    [switch]$Interactive,
    [string]$PrtgProbe,
    [string]$PrtgProtocol,
    [uint16]$PrtgPort,
    [string]$PrtgToken,
    [ValidateSet('account', 'item', 'none', 'target')]
    [string[]]$SplitBy = 'target',
    [ValidateSet('account', 'item', 'none', 'target')]
    [string]$GroupBy = 'item',
    [ValidateSet('csv', 'html', 'js', 'json', 'prtgxml', 'xml')]
    [string[]]$FileFormat = 'js',
    [ValidateSet('passthru', 'none', 'csv', 'html', 'js', 'json', 'prtgxml', 'xml')]
    [string]$OutputFormat = 'passthru',
    [int[]]$Detail = 10,
    [string[]]$InheritanceFlagResolved = @('this folder but not subfolders', 'this folder and subfolders', 'this folder and files, but not subfolders', 'this folder, subfolders, and files'),
    [switch]$NoProgress
)
begin {
    if ($NoProgress) {
        $ProgressPreference = 'Ignore'
    }
    $Progress = @{
        Activity = 'Export-Permission'
        Id       = 0
    }
    $ProgressUpdate = @{
        CurrentOperation = 'Initializing'
        PercentComplete  = 0
        Status           = '0% (step 1 of 20)'
    }
    Write-Progress @Progress @ProgressUpdate
Function Get-DfsNetInfo {
    [CmdletBinding()]
    Param (
        [PSCredential]$Credentials,
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateScript({
                Test-Path -LiteralPath $_ -PathType Container
            })]
        [String[]]$FolderPath
    )
    Process {
        foreach ($ThisFolderPath in $FolderPath) {
            $Split = $ThisFolderPath -split '\\'
            $ServerOrDomain = $Split[0]
            $DfsNamespace = $Split[1]
            $DfsLink = ""
            $Remainder = ""
            [NetApi32Dll]::NetDfsGetInfo($ThisFolderPath)
        }
    }
}
function Get-FileShareInfo {
    param (
        [Parameter(ValueFromPipeline)]
        [psobject[]]$ServerAndShare
    )
    process {
        ForEach ($DFS in $ServerAndShare) {
            $SessionParams = @{
                ComputerName  = $DFS.ServerName
                SessionOption = New-CimSessionOption -Protocol Dcom
            }
            $CimParams = @{
                CimSession = New-CimSession @SessionParams
                ClassName  = 'Win32_Share'
            }
            $ShareName = ($DFS.ShareName -split '\\')[0]
            $ShareLocalPath = Get-CimInstance @CimParams |
            Where-Object Name -EQ $ShareName
            $LocalPath = $DFS.ShareName -replace [regex]::Escape("$ShareName\"), $ShareLocalPath.Path
            $DFS | Add-Member -PassThru -NotePropertyMembers @{
                FolderTarget = "$($DFS.ServerName)\$($DFS.ShareName)\$($DFS.DfsPath -replace [regex]::Escape($DFS.ShareName))"
                LocalPath    = $LocalPath
            }
        }
    }
}
Function Get-NetDfsEnum {
    [CmdletBinding()]
    Param (
        [PSCredential]$Credentials,
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateScript({
                Test-Path -LiteralPath $_ -PathType Container
            })]
        [String[]]$FolderPath
    )
    Process {
        foreach ($ThisFolderPath in $FolderPath) {
            $Split = $ThisFolderPath -split '\\'
            $ServerOrDomain = $Split[0]
            $DfsNamespace = $Split[1]
            $DfsLink = ""
            $Remainder = ""
            [NetApi32Dll]::NetDfsEnum($ThisFolderPath)
        }
    }
}
if (([System.Management.Automation.PSTypeName]'NetApi32Dll').Type) {
Write-Verbose 'TYPE_ALREADY_EXISTS NetApi32Dll.  It is possible that the most recent version is not loaded.  Restart PowerShell to be certain.'
} else {
Add-Type -ErrorAction Stop -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Management.Automation;
using System.Runtime.InteropServices;
public class NetApi32Dll
{
    [DllImport("netapi32.dll", SetLastError = true)]
    private static extern int NetApiBufferFree
    (
        IntPtr buffer
    );
    [DllImport("netapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern int NetDfsEnum
    (
        [MarshalAs(UnmanagedType.LPWStr)] string DfsName,
        int Level,
        int PrefMaxLen,
        out IntPtr Buffer,
        [MarshalAs(UnmanagedType.I4)] out int EntriesRead,
        [MarshalAs(UnmanagedType.I4)] ref int ResumeHandle
    );
    [DllImport("netapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern int NetDfsGetClientInfo
    (
        [MarshalAs(UnmanagedType.LPWStr)] string EntryPath,
        [MarshalAs(UnmanagedType.LPWStr)] string ServerName,
        [MarshalAs(UnmanagedType.LPWStr)] string ShareName,
        int Level,
        ref IntPtr Buffer
    );
    [DllImport("netapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern int NetDfsGetInfo
    (
        [MarshalAs(UnmanagedType.LPWStr)] string EntryPath,
        [MarshalAs(UnmanagedType.LPWStr)] string ServerName,
        [MarshalAs(UnmanagedType.LPWStr)] string ShareName,
        int Level,
        ref IntPtr Buffer
    );
    public struct DFS_INFO_3
    {
        [MarshalAs(UnmanagedType.LPWStr)] public string EntryPath;
        [MarshalAs(UnmanagedType.LPWStr)] public string Comment;
        public UInt32 State;
        public UInt32 NumberOfStorages;
        public IntPtr Storages;
    }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DFS_INFO_6
    {
        [MarshalAs(UnmanagedType.LPWStr)] public string EntryPath;
        [MarshalAs(UnmanagedType.LPWStr)] public string Comment;
        public UInt32 State;
        public UInt64 Timeout;
        public Guid Guid;
        public UInt32 NumberOfStorages;
        public UInt64 MetadataSize;
        public UInt64 PropertyFlags;
        public IntPtr Storages;
    }
    public struct DFS_STORAGE_INFO
    {
        public Int32 State;
        [MarshalAs(UnmanagedType.LPWStr)] public string ServerName;
        [MarshalAs(UnmanagedType.LPWStr)] public string ShareName;
    }
    public struct DFS_STORAGE_INFO_1
    {
        public DFS_STORAGE_STATE State;
        [MarshalAs(UnmanagedType.LPWStr)] public string ServerName;
        [MarshalAs(UnmanagedType.LPWStr)] public string ShareName;
        public DFS_TARGET_PRIORITY TargetPriority;
    }
    public struct DFS_TARGET_PRIORITY
    {
        public DFS_TARGET_PRIORITY_CLASS TargetPriorityClass;
        public UInt16 TargetPriorityRank;
        public UInt16 Reserved;
    }
    public enum DFS_TARGET_PRIORITY_CLASS
    {
        DfsInvalidPriorityClass = -1,
        DfsSiteCostNormalPriorityClass = 0,
        DfsGlobalHighPriorityClass = 1,
        DfsSiteCostHighPriorityClass = 2,
        DfsSiteCostLowPriorityClass = 3,
        DfsGlobalLowPriorityClass = 4
    }
    public enum DFS_STORAGE_STATE
    {
        DFS_STORAGE_STATE_OFFLINE = 1,
        DFS_STORAGE_STATE_ONLINE = 2,
        DFS_STORAGE_STATE_ACTIVE = 4,
        DFS_STORAGE_STATES = 0xF,
    }
    public static List<PSObject> NetDfsEnum(string DfsName)
    {
        IntPtr buffer = new IntPtr();
        int EntriesRead = 0;
        int ResumeHere = 0;
        List<PSObject> returnList = new List<PSObject>();
        const int MAX_PREFERRED_LENGTH = 0xFFFFFFF;
        const int NERR_Success = 0;
        try
        {
            int result = NetDfsEnum(DfsName, 3, MAX_PREFERRED_LENGTH, out buffer, out EntriesRead, ref ResumeHere);
            if (result != NERR_Success)
            {
                string errorMessage = new Win32Exception(Marshal.GetLastWin32Error()).Message;
                throw (new SystemException("NetDfsEnum error. System Error Code: " + result + " - " + errorMessage));
            }
            else
            {
                for (int n = 0; n < EntriesRead; n++)
                {
                    IntPtr DfsPtr = new IntPtr(buffer.ToInt64() + n * Marshal.SizeOf(typeof(DFS_INFO_3)));
                    object dfsObject = Marshal.PtrToStructure(DfsPtr, typeof(DFS_INFO_3));
                    DFS_INFO_3 dfsInfo = (DFS_INFO_3)dfsObject;
                    for (int i = 0; i < dfsInfo.NumberOfStorages; i++)
                    {
                        IntPtr storage = new IntPtr(dfsInfo.Storages.ToInt64() + i * Marshal.SizeOf(typeof(DFS_STORAGE_INFO)));
                        DFS_STORAGE_INFO storageInfo = (DFS_STORAGE_INFO)Marshal.PtrToStructure(storage, typeof(DFS_STORAGE_INFO));
                        PSObject psObject = new PSObject();
                        psObject.Properties.Add(new PSNoteProperty("FullOriginalQueryPath", DfsName));
                        psObject.Properties.Add(new PSNoteProperty("DfsEntryPath", dfsInfo.EntryPath));
                        psObject.Properties.Add(new PSNoteProperty("DfsTarget", System.IO.Path.Combine(new string[] { @"\\", storageInfo.ServerName, storageInfo.ShareName })));
                        psObject.Properties.Add(new PSNoteProperty("DfsTargetState", storageInfo.State));
                        psObject.Properties.Add(new PSNoteProperty("TargetServerName", storageInfo.ServerName));
                        psObject.Properties.Add(new PSNoteProperty("TargetShareName", storageInfo.ShareName));
                        returnList.Add(psObject);
                    }
                }
            }
        }
        finally
        {
            NetApiBufferFree(buffer);
        }
        return returnList;
    }
    public static List<PSObject> NetDfsEnum6(string DfsName)
    {
        IntPtr buffer = new IntPtr();
        int EntriesRead = 0;
        int ResumeHere = 0;
        List<PSObject> returnList = new List<PSObject>();
        const int MAX_PREFERRED_LENGTH = 0xFFFFFFF;
        const int NERR_Success = 0;
        const int Level = 6;
        try
        {
            int result = NetDfsEnum(DfsName, Level, MAX_PREFERRED_LENGTH, out buffer, out EntriesRead, ref ResumeHere);
            if (result != NERR_Success)
            {
                string errorMessage = new Win32Exception(Marshal.GetLastWin32Error()).Message;
                string customErrorMessage = "NetDfsEnum error for '" + DfsName + "'. System Error Code: " + result + " - " + errorMessage;
                throw (new SystemException(customErrorMessage));
            }
            else
            {
                Int64 dfsStart = buffer.ToInt64();
                Type dfsType = typeof(DFS_INFO_6);
                Int64 dfsSize = Marshal.SizeOf(dfsType);
                for (int n = 0; n < EntriesRead; n++)
                {
                    IntPtr dfsPtr = new IntPtr(dfsStart + n * dfsSize);
                    object dfsObject = Marshal.PtrToStructure(dfsPtr, dfsType);
                    DFS_INFO_6 dfsInfo = (DFS_INFO_6)dfsObject;
                    //if (dfsInfo.EntryPath == DfsName) {   // skip link for namespace
                    //    continue;
                    //}
                    Int64 storagesStart = dfsInfo.Storages.ToInt64();
                    Type storageType = typeof(DFS_STORAGE_INFO_1);
                    Int64 storageSize = Marshal.SizeOf(storageType);
                    for (int i = 0; i < dfsInfo.NumberOfStorages; i++)
                    {
                        //Attempted some different properties in case they were mis-mapped the same way that NumberofStorages was
                        //Int64 StartPoint = Convert.ToInt64(dfsInfo.MetadataSize); //System.AccessViolationException
                        //Int64 StartPoint = Convert.ToInt64(dfsInfo.PropertyFlags); //System.AccessViolationException
                        //Int64 StartPoint = Convert.ToInt64(dfsInfo.Timeout); //System.AccessViolationException
                        //IntPtr storagePtr = new IntPtr(StartPoint);
                        IntPtr storagePtr = new IntPtr(storagesStart + i * storageSize);
                        object storageObject = Marshal.PtrToStructure(storagePtr, storageType); //System.NullReferenceException
                        DFS_STORAGE_INFO_1 storageInfo = (DFS_STORAGE_INFO_1)storageObject;
                        PSObject psObject = new PSObject();
                        psObject.Properties.Add(new PSNoteProperty("FullOriginalQueryPath", DfsName));
                        psObject.Properties.Add(new PSNoteProperty("DfsEntryPath", dfsInfo.EntryPath));
                        psObject.Properties.Add(new PSNoteProperty("DfsTarget", System.IO.Path.Combine(new string[] { @"", storageInfo.ServerName, storageInfo.ShareName })));
                        psObject.Properties.Add(new PSNoteProperty("DfsTargetState", storageInfo.State));
                        psObject.Properties.Add(new PSNoteProperty("TargetServerName", storageInfo.ServerName));
                        psObject.Properties.Add(new PSNoteProperty("TargetShareName", storageInfo.ShareName));
                        returnList.Add(psObject);
                    }
                }
            }
        }
        finally
        {
            NetApiBufferFree(buffer);
        }
        return returnList;
    }
    public static List<PSObject> NetDfsGetInfo(string DfsEntryPath)
    {
        IntPtr buffer = new IntPtr();
        List<PSObject> returnList = new List<PSObject>();
        try
        {
            int result = NetDfsGetInfo(DfsEntryPath, null, null, 3, ref buffer);
            if (result != 0)
            {
                throw (new SystemException("Error getting DFS information"));
            }
            else
            {
                DFS_INFO_3 dfsInfo = (DFS_INFO_3)Marshal.PtrToStructure(buffer, typeof(DFS_INFO_3));
                for (int i = 0; i < dfsInfo.NumberOfStorages; i++)
                {
                    IntPtr storage = new IntPtr(dfsInfo.Storages.ToInt64() + i * Marshal.SizeOf(typeof(DFS_STORAGE_INFO)));
                    DFS_STORAGE_INFO storageInfo = (DFS_STORAGE_INFO)Marshal.PtrToStructure(storage, typeof(DFS_STORAGE_INFO));
                    PSObject psObject = new PSObject();
                    psObject.Properties.Add(new PSNoteProperty("State", storageInfo.State));
                    psObject.Properties.Add(new PSNoteProperty("ServerName", storageInfo.ServerName));
                    psObject.Properties.Add(new PSNoteProperty("ShareName", storageInfo.ShareName));
                    returnList.Add(psObject);
                }
            }
        }
        finally
        {
            NetApiBufferFree(buffer);
        }
        return returnList;
    }
    public static List<PSObject> NetDfsGetClientInfo(string DfsPath)
    {
        IntPtr buffer = new IntPtr();
        List<PSObject> returnList = new List<PSObject>();
        try
        {
            int result = NetDfsGetClientInfo(DfsPath, null, null, 3, ref buffer);
            if (result != 0)
            {
                throw (new SystemException("Error getting DFS information"));
            }
            else
            {
                DFS_INFO_3 dfsInfo = (DFS_INFO_3)Marshal.PtrToStructure(buffer, typeof(DFS_INFO_3));
                for (int i = 0; i < dfsInfo.NumberOfStorages; i++)
                {
                    IntPtr storage = new IntPtr(dfsInfo.Storages.ToInt64() + i * Marshal.SizeOf(typeof(DFS_STORAGE_INFO)));
                    DFS_STORAGE_INFO storageInfo = (DFS_STORAGE_INFO)Marshal.PtrToStructure(storage, typeof(DFS_STORAGE_INFO));
                    PSObject psObject = new PSObject();
                    psObject.Properties.Add(new PSNoteProperty("State", storageInfo.State));
                    psObject.Properties.Add(new PSNoteProperty("ServerName", storageInfo.ServerName));
                    psObject.Properties.Add(new PSNoteProperty("ShareName", storageInfo.ShareName));
                    returnList.Add(psObject);
                }
            }
        }
        finally
        {
            NetApiBufferFree(buffer);
        }
        return returnList;
    }
}
"@
}
class FakeDirectoryEntry {
    [string]$Name
    [string]$Parent
    [string]$Path
    [type]$SchemaEntry
    [byte[]]$objectSid
    [string]$Description
    [hashtable]$Properties
    [string]$SchemaClassName
    FakeDirectoryEntry (
        [string]$DirectoryPath
    ) {
        $LastSlashIndex = $DirectoryPath.LastIndexOf('/')
        $StartIndex = $LastSlashIndex + 1
        $This.Name = $DirectoryPath.Substring($StartIndex, $DirectoryPath.Length - $StartIndex)
        $This.Parent = $DirectoryPath.Substring(0, $LastSlashIndex)
        $This.Path = $DirectoryPath
        $This.SchemaEntry = [System.DirectoryServices.DirectoryEntry]
        switch -regex ($DirectoryPath) {
            'CREATOR OWNER$' {
                $This.objectSid = ConvertTo-SidByteArray -SidString 'S-1-3-0'
                $This.Description = 'A SID to be replaced by the SID of the user who creates a new object. This SID is used in inheritable ACEs.'
                $This.SchemaClassName = 'user'
            }
            'SYSTEM$' {
                $This.objectSid = ConvertTo-SidByteArray -SidString 'S-1-5-18'
                $This.Description = 'By default, the SYSTEM account is granted Full Control permissions to all files on an NTFS volume'
                $This.SchemaClassName = 'user'
            }
            'INTERACTIVE$' {
                $This.objectSid = ConvertTo-SidByteArray -SidString 'S-1-5-4'
                $This.Description = 'Users who log on for interactive operation. This is a group identifier added to the token of a process when it was logged on interactively.'
                $This.SchemaClassName = 'group'
            }
            'Authenticated Users$' {
                $This.objectSid = ConvertTo-SidByteArray -SidString 'S-1-5-11'
                $This.Description = 'Any user who accesses the system through a sign-in process has the Authenticated Users identity.'
                $This.SchemaClassName = 'group'
            }
            'TrustedInstaller$' {
                $This.objectSid = ConvertTo-SidByteArray -SidString 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464'
                $This.Description = 'Most of the operating system files are owned by the TrustedInstaller security identifier (SID)'
                $This.SchemaClassName = 'user'
            }
            'ALL APPLICATION PACKAGES$' {
                $This.objectSid = ConvertTo-SidByteArray -SidString 'S-1-15-2-1'
                $This.Description = 'All applications running in an app package context. SECURITY_BUILTIN_PACKAGE_ANY_PACKAGE'
                $This.SchemaClassName = 'group'
            }
            'ALL RESTRICTED APPLICATION PACKAGES$' {
                $This.objectSid = ConvertTo-SidByteArray -SidString 'S-1-15-2-2'
                $This.Description = 'SECURITY_BUILTIN_PACKAGE_ANY_RESTRICTED_PACKAGE'
                $This.SchemaClassName = 'group'
            }
            'Everyone$' {
                $This.objectSid = ConvertTo-SidByteArray -SidString 'S-1-1-0'
                $This.Description = "A group that includes all users; aka 'World'."
                $This.SchemaClassName = 'group'
            }
            'LOCAL SERVICE$' {
                $This.objectSid = ConvertTo-SidByteArray -SidString 'S-1-5-19'
                $This.Description = 'A local service account'
                $This.SchemaClassName = 'user'
            }
            'NETWORK SERVICE$' {
                $This.objectSid = ConvertTo-SidByteArray -SidString 'S-1-5-20'
                $This.Description = 'A network service account'
                $This.SchemaClassName = 'user'
            }
        }
        $This.Properties = @{
            Name            = $This.Name
            Description     = $This.Description
            objectSid       = $This.objectSid
            SchemaClassName = $This.SchemaClassName
        }
    }
    [void]RefreshCache([string[]]$Nonsense) {}
    [void]Invoke([string]$Nonsense) {}
}
function Add-DomainFqdnToLdapPath {
    [OutputType([System.String])]
    param (
        [Parameter(ValueFromPipeline)]
        [string[]]$DirectoryPath,
        [string]$ThisHostName = (HOSTNAME.EXE),
        [string]$ThisFqdn = ([System.Net.Dns]::GetHostByName((HOSTNAME.EXE)).HostName),
        [string]$WhoAmI = (whoami.EXE),
        [hashtable]$LogBuffer = ([hashtable]::Synchronized(@{})),
        [hashtable]$CimCache = ([hashtable]::Synchronized(@{})),
        [ValidateSet('Silent', 'Quiet', 'Success', 'Debug', 'Verbose', 'Output', 'Host', 'Warning', 'Error', 'Information', $null)]
        [string]$DebugOutputStream = 'Debug'
    )
    begin {
        $LoggingParams = @{
            ThisHostname = $ThisHostname
            LogBuffer  = $LogBuffer
            WhoAmI       = $WhoAmI
        }
        $PathRegEx = '(?<Path>LDAP:\/\/[^\/]*)'
        $DomainRegEx = '(?i)DC=\w{1,}?\b'
    }
    process {
        ForEach ($ThisPath in $DirectoryPath) {
            if ($ThisPath -match $PathRegEx) {
                $RegExMatches = $null
                $RegExMatches = [regex]::Matches($ThisPath, $DomainRegEx)
                if ($RegExMatches) {
                    $DomainDN = $null
                    $DomainFqdn = $null
                    $RegExMatches = $RegExMatches |
                    ForEach-Object { $_.Value }
                    $DomainDN = $RegExMatches -join ','
                    $DomainFqdn = ConvertTo-Fqdn -DistinguishedName $DomainDN -ThisFqdn $ThisFqdn -CimCache $CimCache @LoggingParams
                    if ($ThisPath -match "LDAP:\/\/$DomainFqdn\/") {
                        $ThisPath
                    } else {
                        $ThisPath -replace 'LDAP:\/\/', "LDAP://$DomainFqdn/"
                    }
                } else {
                    $ThisPath
                }
            } else {
                $ThisPath
            }
        }
    }
}
function Add-SidInfo {
    [OutputType([System.DirectoryServices.DirectoryEntry[]], [PSCustomObject[]])]
    param (
        [Parameter(ValueFromPipeline)]
        $InputObject,
        [hashtable]$DomainsBySid = ([hashtable]::Synchronized(@{})),
        [string]$ThisHostName = (HOSTNAME.EXE),
        [string]$WhoAmI = (whoami.EXE),
        [hashtable]$LogBuffer = ([hashtable]::Synchronized(@{})),
        [ValidateSet('Silent', 'Quiet', 'Success', 'Debug', 'Verbose', 'Output', 'Host', 'Warning', 'Error', 'Information', $null)]
        [string]$DebugOutputStream = 'Debug'
    )
    begin {
        $LogParams = @{
            ThisHostname = $ThisHostname
            Type         = $DebugOutputStream
            Buffer = $LogBuffer
            WhoAmI       = $WhoAmI
        }
    }
    process {
        ForEach ($Object in $InputObject) {
            $SID = $null
            $SamAccountName = $null
            $DomainObject = $null
            if ($null -eq $Object) {
                continue
            } elseif ($Object.objectSid.Value ) {
                if ( $Object.objectSid.Value.GetType().FullName -ne 'System.Management.Automation.PSMethod' ) {
                    [string]$SID = [System.Security.Principal.SecurityIdentifier]::new([byte[]]$Object.objectSid.Value, 0)
                }
            } elseif ($Object.objectSid) {
                if ($Object.objectSid.GetType().FullName -ne 'System.Management.Automation.PSMethod') {
                    [string]$SID = [System.Security.Principal.SecurityIdentifier]::new([byte[]]$Object.objectSid, 0)
                }
            } elseif ($Object.Properties) {
                if ($Object.Properties['objectSid'].Value) {
                    [string]$SID = [System.Security.Principal.SecurityIdentifier]::new([byte[]]$Object.Properties['objectSid'].Value, 0)
                } elseif ($Object.Properties['objectSid']) {
                    [string]$SID = [System.Security.Principal.SecurityIdentifier]::new([byte[]]($Object.Properties['objectSid'] | ForEach-Object { $_ }), 0)
                }
                if ($Object.Properties['samaccountname']) {
                    $SamAccountName = $Object.Properties['samaccountname']
                } else {
                    $SamAccountName = $Object.Properties['name']
                }
            } elseif ($Object.objectSid) {
                [string]$SID = [System.Security.Principal.SecurityIdentifier]::new([byte[]]$Object.objectSid, 0)
            }
            if ($Object.Domain.Sid) {
                if ($null -eq $SID) {
                    [string]$SID = $Object.Domain.Sid
                }
                $DomainObject = $Object.Domain
            }
            if (-not $DomainObject) {
                $DomainSid = $SID.Substring(0, $Sid.LastIndexOf("-"))
                $DomainObject = $DomainsBySid[$DomainSid]
            }
            Add-Member -InputObject $Object -PassThru -Force @{
                SidString      = $SID
                Domain         = $DomainObject
                SamAccountName = $SamAccountName
            }
        }
    }
}
function ConvertFrom-DirectoryEntry {
    param (
        [Parameter(
            Position = 0
        )]
        [System.DirectoryServices.DirectoryEntry[]]$DirectoryEntry
    )
    ForEach ($ThisDirectoryEntry in $DirectoryEntry) {
        $OutputObject = @{}
        ForEach ($Prop in ($ThisDirectoryEntry | Get-Member -View All -MemberType Property, NoteProperty).Name) {
            $null = ConvertTo-SimpleProperty -InputObject $ThisDirectoryEntry -Property $Prop -PropertyDictionary $OutputObject
        }
        [PSCustomObject]$OutputObject
    }
}
function ConvertFrom-IdentityReferenceResolved {
    [OutputType([void])]
    param (
        [Parameter(ValueFromPipeline)]
        [string]$IdentityReference,
        [switch]$NoGroupMembers,
        [hashtable]$ACEsByResolvedID = ([hashtable]::Synchronized(@{})),
        [hashtable]$PrincipalsByResolvedID = ([hashtable]::Synchronized(@{})),
        [ValidateSet('Silent', 'Quiet', 'Success', 'Debug', 'Verbose', 'Output', 'Host', 'Warning', 'Error', 'Information', $null)]
        [string]$DebugOutputStream = 'Debug',
        [hashtable]$CimCache = ([hashtable]::Synchronized(@{})),
        [hashtable]$DirectoryEntryCache = ([hashtable]::Synchronized(@{})),
        [hashtable]$DomainsByNetbios = ([hashtable]::Synchronized(@{})),
        [hashtable]$DomainsBySid = ([hashtable]::Synchronized(@{})),
        [hashtable]$DomainsByFqdn = ([hashtable]::Synchronized(@{})),
        [string]$ThisHostName = (HOSTNAME.EXE),
        [string]$ThisFqdn = ([System.Net.Dns]::GetHostByName((HOSTNAME.EXE)).HostName),
        [string]$WhoAmI = (whoami.EXE),
        [hashtable]$LogBuffer = ([hashtable]::Synchronized(@{})),
        [string]$CurrentDomain = (Get-CurrentDomain)
    )
    $LogParams = @{
        ThisHostname = $ThisHostname
        Type         = $DebugOutputStream
        Buffer = $LogBuffer
        WhoAmI       = $WhoAmI
    }
    $LoggingParams = @{
        ThisHostname = $ThisHostname
        LogBuffer    = $LogBuffer
        WhoAmI       = $WhoAmI
    }
    $AccessControlEntries = $ACEsByResolvedID[$IdentityReference]
    if ($null -eq $PrincipalsByResolvedID[$IdentityReference]) {
        Write-LogMsg @LogParams -Text " # ADSI Principal cache miss for '$IdentityReference'"
        $GetDirectoryEntryParams = @{
            DirectoryEntryCache = $DirectoryEntryCache
            DomainsByNetbios    = $DomainsByNetbios
            ThisFqdn            = $ThisFqdn
            CimCache            = $CimCache
            DebugOutputStream   = $DebugOutputStream
        }
        $SearchDirectoryParams = @{
            CimCache            = $CimCache
            DebugOutputStream   = $DebugOutputStream
            DirectoryEntryCache = $DirectoryEntryCache
            DomainsByNetbios    = $DomainsByNetbios
            ThisFqdn            = $ThisFqdn
        }
        $split = $IdentityReference.Split('\')
        $DomainNetBIOS = $split[0]
        $SamaccountnameOrSid = $split[1]
        if (
            $null -ne $SamaccountnameOrSid -and
            @($AccessControlEntries.AdsiProvider)[0] -eq 'LDAP'
        ) {
            Write-LogMsg @LogParams -Text " # '$IdentityReference' is a domain security principal"
            $DomainNetbiosCacheResult = $DomainsByNetbios[$DomainNetBIOS]
            if ($DomainNetbiosCacheResult) {
                Write-LogMsg @LogParams -Text " # Domain NetBIOS cache hit for '$DomainNetBIOS' for '$IdentityReference'"
                $DomainDn = $DomainNetbiosCacheResult.DistinguishedName
                $SearchDirectoryParams['DirectoryPath'] = "LDAP://$($DomainNetbiosCacheResult.Dns)/$DomainDn"
            } else {
                Write-LogMsg @LogParams -Text " # Domain NetBIOS cache miss for '$DomainNetBIOS' for '$IdentityReference'"
                if ( -not [string]::IsNullOrEmpty($DomainNetBIOS) ) {
                    $DomainDn = ConvertTo-DistinguishedName -Domain $DomainNetBIOS -DomainsByNetbios $DomainsByNetbios @LoggingParams
                }
                $SearchDirectoryParams['DirectoryPath'] = Add-DomainFqdnToLdapPath -DirectoryPath "LDAP://$DomainNetBIOS" -ThisFqdn $ThisFqdn -CimCache $CimCache @LogParams
            }
            $SearchDirectoryParams['Filter'] = "(samaccountname=$SamaccountnameOrSid)"
            $SearchDirectoryParams['PropertiesToLoad'] = @(
                'objectClass',
                'objectSid',
                'samAccountName',
                'distinguishedName',
                'name',
                'grouptype',
                'description',
                'managedby',
                'member',
                'Department',
                'Title',
                'primaryGroupToken'
            )
            $Params = $SearchDirectoryParams.Keys | ForEach-Object {
                "-$_ '$($SearchDirectoryParams[$_])'"
            }
            Write-LogMsg @LogParams -Text "Search-Directory $($Params -join ' ')"
            try {
                $DirectoryEntry = Search-Directory @SearchDirectoryParams @LoggingParams
            } catch {
                $LogParams['Type'] = 'Warning' 
                Write-LogMsg @LogParams -Text " # '$IdentityReference' could not be resolved against its directory: $($_.Exception.Message)"
                $LogParams['Type'] = $DebugOutputStream
            }
        } elseif (
            $IdentityReference.Substring(0, $IdentityReference.LastIndexOf('-') + 1) -eq $CurrentDomain.SIDString
        ) {
            Write-LogMsg @LogParams -Text " # '$IdentityReference' is an unresolved SID from the current domain"
            $DomainDN = $CurrentDomain.distinguishedName.Value
            $DomainFQDN = ConvertTo-Fqdn -DistinguishedName $DomainDN -ThisFqdn $ThisFqdn -CimCache $CimCache @LoggingParams
            $SearchDirectoryParams['DirectoryPath'] = "LDAP://$DomainFQDN/cn=partitions,cn=configuration,$DomainDn"
            $SearchDirectoryParams['Filter'] = "(&(objectcategory=crossref)(dnsroot=$DomainFQDN)(netbiosname=*))"
            $SearchDirectoryParams['PropertiesToLoad'] = 'netbiosname'
            $Params = $SearchDirectoryParams.Keys | ForEach-Object {
                "-$_ '$($SearchDirectoryParams[$_])'"
            }
            Write-LogMsg @LogParams -Text "Search-Directory $($Params -join ' ')"
            $DomainCrossReference = Search-Directory @SearchDirectoryParams @LoggingParams
            if ($DomainCrossReference.Properties ) {
                Write-LogMsg @LogParams -Text " # The domain '$DomainFQDN' is online for '$IdentityReference'"
                [string]$DomainNetBIOS = $DomainCrossReference.Properties['netbiosname']
            }
            $SidObject = [System.Security.Principal.SecurityIdentifier]::new($IdentityReference)
            $SidBytes = [byte[]]::new($SidObject.BinaryLength)
            $null = $SidObject.GetBinaryForm($SidBytes, 0)
            $ObjectSid = ConvertTo-HexStringRepresentationForLDAPFilterString -SIDByteArray $SidBytes
            $SearchDirectoryParams['DirectoryPath'] = "LDAP://$DomainFQDN/$DomainDn"
            $SearchDirectoryParams['Filter'] = "(objectsid=$ObjectSid)"
            $SearchDirectoryParams['PropertiesToLoad'] = @(
                'objectClass',
                'objectSid',
                'samAccountName',
                'distinguishedName',
                'name',
                'grouptype',
                'description',
                'managedby',
                'member',
                'Department',
                'Title',
                'primaryGroupToken'
            )
            $Params = $SearchDirectoryParams.Keys | ForEach-Object {
                "-$_ '$($SearchDirectoryParams[$_])'"
            }
            Write-LogMsg @LogParams -Text "Search-Directory $($Params -join ' ')"
            try {
                $DirectoryEntry = Search-Directory @SearchDirectoryParams @LoggingParams
            } catch {
                $LogParams['Type'] = 'Warning' 
                Write-LogMsg @LogParams -Text " # '$IdentityReference' could not be resolved against its directory. Error: $($_.Exception.Message.Trim())"
                $LogParams['Type'] = $DebugOutputStream
            }
        } else {
            Write-LogMsg @LogParams -Text " # '$IdentityReference' is a local security principal or unresolved SID"
            if ($null -eq $SamaccountnameOrSid) { $SamaccountnameOrSid = $IdentityReference }
            if ($SamaccountnameOrSid -like "S-1-*") {
                Write-LogMsg @LogParams -Text "$($IdentityReference) is an unresolved SID"
                $DomainSid = $SamaccountnameOrSid.Substring(0, $SamaccountnameOrSid.LastIndexOf("-"))
                if ($DomainSid -eq $CurrentDomain.SIDString) {
                    Write-LogMsg @LogParams -Text "$($IdentityReference) belongs to the current domain.  Could be a deleted user.  ?possibly a foreign security principal corresponding to an offline trusted domain or deleted user in the trusted domain?"
                } else {
                    Write-LogMsg @LogParams -Text "$($IdentityReference) does not belong to the current domain. Could be a local security principal or belong to an unresolvable domain."
                }
                $DomainObject = $DomainsBySID[$DomainSid]
                if ($DomainObject) {
                    $GetDirectoryEntryParams['DirectoryPath'] = "WinNT://$($DomainObject.Dns)/Users,group"
                    $DomainNetBIOS = $DomainObject.Netbios
                    $DomainDN = $DomainObject.DistinguishedName
                } else {
                    $GetDirectoryEntryParams['DirectoryPath'] = "WinNT://$DomainNetBIOS/Users,group"
                    $DomainDn = ConvertTo-DistinguishedName -Domain $DomainNetBIOS -DomainsByNetbios $DomainsByNetbios @LoggingParams
                }
                $Params = $GetDirectoryEntryParams.Keys | ForEach-Object {
                    "-$_ '$($GetDirectoryEntryParams[$_])'"
                }
                Write-LogMsg @LogParams -Text "Get-DirectoryEntry $($Params -join ' ')"
                try {
                    $UsersGroup = Get-DirectoryEntry @GetDirectoryEntryParams @LoggingParams
                } catch {
                    $LogParams['Type'] = 'Warning' 
                    Write-LogMsg @LogParams -Text "Could not get '$($GetDirectoryEntryParams['DirectoryPath'])' using PSRemoting. Error: $_"
                    $LogParams['Type'] = $DebugOutputStream
                }
                $MembersOfUsersGroup = Get-WinNTGroupMember -DirectoryEntry $UsersGroup -DirectoryEntryCache $DirectoryEntryCache -DomainsByFqdn $DomainsByFqdn -DomainsByNetbios $DomainsByNetbios -DomainsBySid $DomainsBySid -ThisFqdn $ThisFqdn @LoggingParams
                $DirectoryEntry = $MembersOfUsersGroup |
                Where-Object -FilterScript { ($SamaccountnameOrSid -eq [System.Security.Principal.SecurityIdentifier]::new([byte[]]$_.Properties['objectSid'].Value, 0)) }
            } else {
                Write-LogMsg @LogParams -Text " # '$IdentityReference' is a local security principal"
                $DomainNetbiosCacheResult = $DomainsByNetbios[$DomainNetBIOS]
                if ($DomainNetbiosCacheResult) {
                    $GetDirectoryEntryParams['DirectoryPath'] = "WinNT://$($DomainNetbiosCacheResult.Dns)/$SamaccountnameOrSid"
                } else {
                    $GetDirectoryEntryParams['DirectoryPath'] = "WinNT://$DomainNetBIOS/$SamaccountnameOrSid"
                }
                $GetDirectoryEntryParams['PropertiesToLoad'] = @(
                    'members',
                    'objectClass',
                    'objectSid',
                    'samAccountName',
                    'distinguishedName',
                    'name',
                    'grouptype',
                    'description',
                    'managedby',
                    'member',
                    'Department',
                    'Title',
                    'primaryGroupToken'
                )
                $Params = $GetDirectoryEntryParams.Keys | ForEach-Object {
                    "-$_ $($GetDirectoryEntryParams[$_])"
                }
                Write-LogMsg @LogParams -Text "Get-DirectoryEntry $($Params -join ' ')"
                try {
                    $DirectoryEntry = Get-DirectoryEntry @GetDirectoryEntryParams @LoggingParams
                } catch {
                    $LogParams['Type'] = 'Warning' 
                    Write-LogMsg @LogParams -Text " # '$($GetDirectoryEntryParams['DirectoryPath'])' could not be resolved for '$IdentityReference'. Error: $($_.Exception.Message.Trim())"
                    $LogParams['Type'] = $DebugOutputStream
                }
            }
        }
        $PropertiesToAdd = @{
            DomainDn      = $DomainDn
            DomainNetbios = $DomainNetBIOS
        }
        if ($null -ne $DirectoryEntry) {
            ForEach ($Prop in ($DirectoryEntry | Get-Member -View All -MemberType Property, NoteProperty).Name) {
                $null = ConvertTo-SimpleProperty -InputObject $DirectoryEntry -Property $Prop -PropertyDictionary $PropertiesToAdd
            }
            if ($DirectoryEntry.Name) {
                $AccountName = $DirectoryEntry.Name
            } else {
                if ($DirectoryEntry.Properties) {
                    if ($DirectoryEntry.Properties['name'].Value) {
                        $AccountName = $DirectoryEntry.Properties['name'].Value
                    } else {
                        $AccountName = $DirectoryEntry.Properties['name']
                    }
                }
            }
            $PropertiesToAdd['ResolvedAccountName'] = "$DomainNetBIOS\$AccountName"
            if (-not $DirectoryEntry.SchemaClassName) {
                $PropertiesToAdd['SchemaClassName'] = @($DirectoryEntry.Properties['objectClass'])[-1] 
            }
            if ($NoGroupMembers -eq $false) {
                if (
                    $PropertiesToAdd.ContainsKey('objectClass')
                ) {
                    Write-LogMsg @LogParams -Text " # '$($DirectoryEntry.Path)' is an LDAP security principal for '$IdentityReference'"
                    $Members = (Get-AdsiGroupMember -Group $DirectoryEntry -CimCache $CimCache -DirectoryEntryCache $DirectoryEntryCache -DomainsByFqdn $DomainsByFqdn -DomainsByNetbios $DomainsByNetbios -DomainsBySid $DomainsBySid -ThisFqdn $ThisFqdn @LoggingParams).FullMembers
                } else {
                    Write-LogMsg @LogParams -Text " # '$($DirectoryEntry.Path)' is a WinNT security principal for '$IdentityReference'"
                    if ( $DirectoryEntry.SchemaClassName -eq 'group') {
                        Write-LogMsg @LogParams -Text " # '$($DirectoryEntry.Path)' is a WinNT group for '$IdentityReference'"
                        $Members = Get-WinNTGroupMember -DirectoryEntry $DirectoryEntry -CimCache $CimCache -DirectoryEntryCache $DirectoryEntryCache -DomainsByFqdn $DomainsByFqdn -DomainsByNetbios $DomainsByNetbios -DomainsBySid $DomainsBySid -ThisFqdn $ThisFqdn @LoggingParams
                    }
                }
                if ($Members) {
                    $GroupMembers = ForEach ($ThisMember in $Members) {
                        if ($ThisMember.Domain) {
                            $OutputProperties = @{}
                        } else {
                            $OutputProperties = @{
                                Domain = [pscustomobject]@{
                                    Dns     = $DomainNetBIOS
                                    Netbios = $DomainNetBIOS
                                    Sid     = @($SamaccountnameOrSid -split '-')[-1]
                                }
                            }
                        }
                        $InputProperties = (Get-Member -InputObject $ThisMember -MemberType Property, CodeProperty, ScriptProperty, NoteProperty).Name
                        ForEach ($ThisProperty in $InputProperties) {
                            $null = ConvertTo-SimpleProperty -InputObject $ThisMember -Property $ThisProperty -PropertyDictionary $OutputProperties
                        }
                        if ($ThisMember.sAmAccountName) {
                            $ResolvedAccountName = "$($OutputProperties['Domain'].Netbios)\$($ThisMember.sAmAccountName)"
                        } else {
                            $ResolvedAccountName = "$($OutputProperties['Domain'].Netbios)\$($ThisMember.Name)"
                        }
                        $OutputProperties['ResolvedAccountName'] = $ResolvedAccountName
                        $PrincipalsByResolvedID[$ResolvedAccountName] = [PSCustomObject]$OutputProperties
                        $ACEsByResolvedID[$ResolvedAccountName] = $AccessControlEntries
                        $ResolvedAccountName
                    }
                }
            }
            $PropertiesToAdd['Members'] = $GroupMembers
            Write-LogMsg @LogParams -Text " # '$($DirectoryEntry.Path)' has $(($Members | Measure-Object).Count) members for '$IdentityReference'"
        } else {
            $LogParams['Type'] = 'Warning' 
            Write-LogMsg @LogParams -Text " # '$IdentityReference' could not be matched to a DirectoryEntry"
            $LogParams['Type'] = $DebugOutputStream
        }
        $PrincipalsByResolvedID[$IdentityReference] = [PSCustomObject]$PropertiesToAdd
    }
}
function ConvertFrom-PropertyValueCollectionToString {
    param (
        [System.DirectoryServices.PropertyValueCollection]$PropertyValueCollection
    )
    $SubType = & { $PropertyValueCollection.Value.GetType().FullName } 2>$null
    switch ($SubType) {
        'System.Byte[]' { ConvertTo-DecStringRepresentation -ByteArray $PropertyValueCollection.Value }
        default { "$($PropertyValueCollection.Value)" }
    }
}
function ConvertFrom-ResultPropertyValueCollectionToString {
    param (
        [System.DirectoryServices.ResultPropertyValueCollection]$ResultPropertyValueCollection
    )
    $SubType = & { $ResultPropertyValueCollection.Value.GetType().FullName } 2>$null
    switch ($SubType) {
        'System.Byte[]' { ConvertTo-DecStringRepresentation -ByteArray $ResultPropertyValueCollection.Value }
        default { "$($ResultPropertyValueCollection.Value)" }
    }
}
function ConvertFrom-SearchResult {
    param (
        [Parameter(
            Position = 0,
            ValueFromPipeline
        )]
        [System.DirectoryServices.SearchResult[]]$SearchResult
    )
    process {
        ForEach ($ThisSearchResult in $SearchResult) {
            #
            #
            #
            #
            #
            $OutputObject = @{}
            ForEach ($ThisProperty in $ThisSearchResult.Properties.Keys) {
                $null = ConvertTo-SimpleProperty -InputObject $ThisSearchResult.Properties -Property $ThisProperty -PropertyDictionary $ThisObject
            }
            ForEach ($ThisProperty in ($ThisSearchResult | Get-Member -View All -MemberType Property, NoteProperty).Name) {
                $null = ConvertTo-SimpleProperty -InputObject $ThisSearchResult -Property $ThisProperty -PropertyDictionary $OutputObject
            }
            [PSCustomObject]$OutputObject
        }
    }
}
function ConvertFrom-SidString {
    param (
        [string]$SID,
        [ValidateSet('Silent', 'Quiet', 'Success', 'Debug', 'Verbose', 'Output', 'Host', 'Warning', 'Error', 'Information', $null)]
        [string]$DebugOutputStream = 'Debug',
        [hashtable]$CimCache = ([hashtable]::Synchronized(@{})),
        [hashtable]$DirectoryEntryCache = ([hashtable]::Synchronized(@{})),
        [hashtable]$DomainsByNetbios = ([hashtable]::Synchronized(@{})),
        [hashtable]$DomainsBySid = ([hashtable]::Synchronized(@{})),
        [hashtable]$DomainsByFqdn = ([hashtable]::Synchronized(@{})),
        [string]$ThisHostName = (HOSTNAME.EXE),
        [string]$ThisFqdn = ([System.Net.Dns]::GetHostByName((HOSTNAME.EXE)).HostName),
        [string]$WhoAmI = (whoami.EXE),
        [hashtable]$LogBuffer = ([hashtable]::Synchronized(@{}))
    )
    $GetDirectoryEntryParams = @{
        DirectoryEntryCache = $DirectoryEntryCache
        DomainsByNetbios    = $DomainsByNetbios
        ThisFqdn            = $ThisFqdn
        ThisHostname        = $ThisHostname
        CimCache            = $CimCache
        LogBuffer         = $LogBuffer
        WhoAmI              = $WhoAmI
        DebugOutputStream   = $DebugOutputStream
    }
    Get-DirectoryEntry -DirectoryPath "LDAP://<SID=$SID>" @GetDirectoryEntryParams
}
function ConvertTo-DecStringRepresentation {
    [OutputType([System.String])]
    param (
        [byte[]]$ByteArray
    )
    $ByteArray |
    ForEach-Object {
        '{0}' -f $_
    }
}
function ConvertTo-DistinguishedName {
    [OutputType([System.String])]
    param (
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'NetBIOS')]
        [string[]]$Domain,
        [Parameter(ParameterSetName = 'NetBIOS')]
        [hashtable]$DomainsByNetbios = ([hashtable]::Synchronized(@{})),
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'FQDN')]
        [string[]]$DomainFQDN,
        [string]$InitType = 'ADS_NAME_INITTYPE_GC',
        [string]$InputType = 'ADS_NAME_TYPE_NT4',
        [string]$OutputType = 'ADS_NAME_TYPE_1779',
        [string]$AdsiProvider,
        [string]$ThisHostName = (HOSTNAME.EXE),
        [string]$WhoAmI = (whoami.EXE),
        [hashtable]$LogBuffer = ([hashtable]::Synchronized(@{})),
        [ValidateSet('Silent', 'Quiet', 'Success', 'Debug', 'Verbose', 'Output', 'Host', 'Warning', 'Error', 'Information', $null)]
        [string]$DebugOutputStream = 'Debug'
    )
    begin {
        $LogParams = @{
            ThisHostname = $ThisHostname
            Type         = $DebugOutputStream
            Buffer = $LogBuffer
            WhoAmI       = $WhoAmI
        }
        $LoggingParams = @{
            ThisHostname = $ThisHostname
            LogBuffer    = $LogBuffer
            WhoAmI       = $WhoAmI
        }
        $ADS_NAME_INITTYPE_dict = @{
            ADS_NAME_INITTYPE_DOMAIN = 1 
            ADS_NAME_INITTYPE_SERVER = 2 
            ADS_NAME_INITTYPE_GC     = 3 
        }
        $ADS_NAME_TYPE_dict = @{
            ADS_NAME_TYPE_1779                    = 1 
            ADS_NAME_TYPE_CANONICAL               = 2 
            ADS_NAME_TYPE_NT4                     = 3 
            ADS_NAME_TYPE_DISPLAY                 = 4 
            ADS_NAME_TYPE_DOMAIN_SIMPLE           = 5 
            ADS_NAME_TYPE_ENTERPRISE_SIMPLE       = 6 
            ADS_NAME_TYPE_GUID                    = 7 
            ADS_NAME_TYPE_UNKNOWN                 = 8 
            ADS_NAME_TYPE_USER_PRINCIPAL_NAME     = 9 
            ADS_NAME_TYPE_CANONICAL_EX            = 10 
            ADS_NAME_TYPE_SERVICE_PRINCIPAL_NAME  = 11 
            ADS_NAME_TYPE_SID_OR_SID_HISTORY_NAME = 12 
        }
        $ChosenInitType = $ADS_NAME_INITTYPE_dict[$InitType]
        $ChosenInputType = $ADS_NAME_TYPE_dict[$InputType]
        $ChosenOutputType = $ADS_NAME_TYPE_dict[$OutputType]
    }
    process {
        ForEach ($ThisDomain in $Domain) {
            $DomainCacheResult = $DomainsByNetbios[$ThisDomain]
            if ($DomainCacheResult) {
                Write-LogMsg @LogParams -Text " # Domain NetBIOS cache hit for '$ThisDomain'"
                $DomainCacheResult.DistinguishedName
            } else {
                Write-LogMsg @LogParams -Text " # Domain NetBIOS cache miss for '$ThisDomain'. Available keys: $($DomainsByNetBios.Keys -join ',')"
                Write-LogMsg @LogParams -Text "`$IADsNameTranslateComObject = New-Object -comObject 'NameTranslate' # For '$ThisDomain'"
                $IADsNameTranslateComObject = New-Object -comObject "NameTranslate"
                Write-LogMsg @LogParams -Text "`$IADsNameTranslateInterface = `$IADsNameTranslateComObject.GetType() # For '$ThisDomain'"
                $IADsNameTranslateInterface = $IADsNameTranslateComObject.GetType()
                Write-LogMsg @LogParams -Text "`$null = `$IADsNameTranslateInterface.InvokeMember('Init', 'InvokeMethod', `$Null, `$IADsNameTranslateComObject, ($ChosenInitType, `$Null)) # For '$ThisDomain'"
                $null = $IADsNameTranslateInterface.InvokeMember("Init", "InvokeMethod", $Null, $IADsNameTranslateComObject, ($ChosenInitType, $Null))
                Write-LogMsg @LogParams -Text "`$null = `$IADsNameTranslateInterface.InvokeMember('Set', 'InvokeMethod', `$Null, `$IADsNameTranslateComObject, ($ChosenInputType, '$ThisDomain\')) # For '$ThisDomain'"
                $null = { $IADsNameTranslateInterface.InvokeMember("Set", "InvokeMethod", $Null, $IADsNameTranslateComObject, ($ChosenInputType, "$ThisDomain\")) } 2>$null
                Write-LogMsg @LogParams -Text "`$IADsNameTranslateInterface.InvokeMember('Get', 'InvokeMethod', `$Null, `$IADsNameTranslateComObject, $ChosenOutputType) # For '$ThisDomain'"
                $null = { $null = { $IADsNameTranslateInterface.InvokeMember("Get", "InvokeMethod", $Null, $IADsNameTranslateComObject, $ChosenOutputType) } 2>$null } 2>$null
            }
        }
        ForEach ($ThisDomain in $DomainFQDN) {
            $DomainCacheResult = $DomainsByFqdn[$ThisDomain]
            if ($DomainCacheResult) {
                Write-LogMsg @LogParams -Text " # Domain FQDN cache hit for '$ThisDomain'"
                $DomainCacheResult.DistinguishedName
            } else {
                Write-LogMsg @LogParams -Text " # Domain FQDN cache miss for '$ThisDomain'"
                if (-not $PSBoundParameters.ContainsKey('AdsiProvider')) {
                    $AdsiProvider = Find-AdsiProvider -AdsiServer $ThisDomain @LoggingParams
                }
                if ($AdsiProvider -ne 'WinNT') {
                    "dc=$($ThisDomain -replace '\.',',dc=')"
                }
            }
        }
    }
}
function ConvertTo-DomainNetBIOS {
    param (
        [string]$DomainFQDN,
        [string]$AdsiProvider,
        [hashtable]$CimCache = ([hashtable]::Synchronized(@{})),
        [hashtable]$DirectoryEntryCache = ([hashtable]::Synchronized(@{})),
        [hashtable]$DomainsByNetbios = ([hashtable]::Synchronized(@{})),
        [hashtable]$DomainsBySid = ([hashtable]::Synchronized(@{})),
        [hashtable]$DomainsByFqdn = ([hashtable]::Synchronized(@{})),
        [string]$ThisFqdn = ([System.Net.Dns]::GetHostByName((HOSTNAME.EXE)).HostName),
        [string]$ThisHostName = (HOSTNAME.EXE),
        [string]$WhoAmI = (whoami.EXE),
        [hashtable]$LogBuffer = ([hashtable]::Synchronized(@{})),
        [ValidateSet('Silent', 'Quiet', 'Success', 'Debug', 'Verbose', 'Output', 'Host', 'Warning', 'Error', 'Information', $null)]
        [string]$DebugOutputStream = 'Debug'
    )
    $LogParams = @{
        ThisHostname = $ThisHostname
        Type         = $DebugOutputStream
        Buffer = $LogBuffer
        WhoAmI       = $WhoAmI
    }
    $DomainCacheResult = $DomainsByFqdn[$DomainFQDN]
    if ($DomainCacheResult) {
        Write-LogMsg @LogParams -Text " # Domain FQDN cache hit for '$DomainFQDN'"
        return $DomainCacheResult.Netbios
    }
    Write-LogMsg @LogParams -Text " # Domain FQDN cache miss for '$DomainFQDN'"
    if ($AdsiProvider -eq 'LDAP') {
        $GetDirectoryEntryParams = @{
            DirectoryEntryCache = $DirectoryEntryCache
            DomainsByNetbios    = $DomainsByNetbios
            DomainsBySid        = $DomainsBySid
            ThisFqdn            = $ThisFqdn
            ThisHostname        = $ThisHostname
            CimCache            = $CimCache
            LogBuffer           = $LogBuffer
            WhoAmI              = $WhoAmI
            DebugOutputStream   = $DebugOutputStream
        }
        $RootDSE = Get-DirectoryEntry -DirectoryPath "LDAP://$DomainFQDN/rootDSE" @GetDirectoryEntryParams
        Write-LogMsg @LogParams -Text "`$RootDSE.InvokeGet('defaultNamingContext')"
        $DomainDistinguishedName = $RootDSE.InvokeGet("defaultNamingContext")
        Write-LogMsg @LogParams -Text "`$RootDSE.InvokeGet('configurationNamingContext')"
        $ConfigurationDN = $rootDSE.InvokeGet("configurationNamingContext")
        $partitions = Get-DirectoryEntry -DirectoryPath "LDAP://$DomainFQDN/cn=partitions,$ConfigurationDN" @GetDirectoryEntryParams
        ForEach ($Child In $Partitions.Children) {
            If ($Child.nCName -contains $DomainDistinguishedName) {
                return $Child.nETBIOSName
            }
        }
    } else {
        $LengthOfNetBIOSName = $DomainFQDN.IndexOf('.')
        if ($LengthOfNetBIOSName -eq -1) {
            $DomainFQDN
        } else {
            $DomainFQDN.Substring(0, $LengthOfNetBIOSName)
        }
    }
}
function ConvertTo-DomainSidString {
    param (
        [Parameter(Mandatory)]
        [string]$DomainDnsName,
        [hashtable]$DirectoryEntryCache = ([hashtable]::Synchronized(@{})),
        [hashtable]$DomainsByNetbios = ([hashtable]::Synchronized(@{})),
        [hashtable]$DomainsBySid = ([hashtable]::Synchronized(@{})),
        [hashtable]$DomainsByFqdn = ([hashtable]::Synchronized(@{})),
        [string]$AdsiProvider,
        [hashtable]$CimCache = ([hashtable]::Synchronized(@{})),
        [string]$ThisHostName = (HOSTNAME.EXE),
        [string]$ThisFqdn = ([System.Net.Dns]::GetHostByName((HOSTNAME.EXE)).HostName),
        [string]$WhoAmI = (whoami.EXE),
        [hashtable]$LogBuffer = ([hashtable]::Synchronized(@{})),
        [ValidateSet('Silent', 'Quiet', 'Success', 'Debug', 'Verbose', 'Output', 'Host', 'Warning', 'Error', 'Information', $null)]
        [string]$DebugOutputStream = 'Debug'
    )
    $LogParams = @{
        ThisHostname = $ThisHostname
        Type         = $DebugOutputStream
        Buffer = $LogBuffer
        WhoAmI       = $WhoAmI
    }
    $LoggingParams = @{
        ThisHostname = $ThisHostname
        LogBuffer    = $LogBuffer
        WhoAmI       = $WhoAmI
    }
    $CacheResult = $DomainsByFqdn[$DomainDnsName]
    if ($CacheResult) {
        Write-LogMsg @LogParams -Text " # Domain FQDN cache hit for '$DomainDnsName'"
        return $CacheResult.Sid
    }
    Write-LogMsg @LogParams -Text " # Domain FQDN cache miss for '$DomainDnsName'"
    if (
        -not $AdsiProvider -or
        $AdsiProvider -eq 'LDAP'
    ) {
        $GetDirectoryEntryParams = @{
            DirectoryEntryCache = $DirectoryEntryCache
            DomainsByNetbios    = $DomainsByNetbios
            DomainsBySid        = $DomainsBySid
            ThisFqdn            = $ThisFqdn
            CimCache            = $CimCache
            DebugOutputStream   = $DebugOutputStream
        }
        $DomainDirectoryEntry = Get-DirectoryEntry -DirectoryPath "LDAP://$DomainDnsName" @GetDirectoryEntryParams @LoggingParams
        try {
            $null = $DomainDirectoryEntry.RefreshCache('objectSid')
        } catch {
            Write-LogMsg @LogParams -Text " # LDAP connection failed to '$DomainDnsName' - $($_.Exception.Message)"
            Write-LogMsg @LogParams -Text "Find-LocalAdsiServerSid -ComputerName '$DomainDnsName'"
            $DomainSid = Find-LocalAdsiServerSid -ComputerName $DomainDnsName -ThisFqdn $ThisFqdn -CimCache $CimCache @LoggingParams
            return $DomainSid
        }
    } else {
        Write-LogMsg @LogParams -Text "Find-LocalAdsiServerSid -ComputerName '$DomainDnsName'"
        $DomainSid = Find-LocalAdsiServerSid -ComputerName $DomainDnsName -ThisFqdn $ThisFqdn -CimCache $CimCache @LoggingParams
        return $DomainSid
    }
    $DomainSid = $null
    if ($DomainDirectoryEntry.Properties) {
        $objectSIDProperty = $DomainDirectoryEntry.Properties['objectSid']
        if ($objectSIDProperty.Value) {
            $SidByteArray = [byte[]]$objectSIDProperty.Value
        } else {
            $SidByteArray = [byte[]]$objectSIDProperty
        }
    } else {
        $SidByteArray = [byte[]]$DomainDirectoryEntry.objectSid
    }
    Write-LogMsg @LogParams -Text "[System.Security.Principal.SecurityIdentifier]::new([byte[]]@($($SidByteArray -join ',')), 0).ToString()"
    $DomainSid = [System.Security.Principal.SecurityIdentifier]::new($SidByteArray, 0).ToString()
    if ($DomainSid) {
        return $DomainSid
    } else {
        $LogParams['Type'] = 'Warning' 
        Write-LogMsg @LogParams -Text " # LDAP Domain: '$DomainDnsName' has an invalid SID - $($_.Exception.Message)"
        $LogParams['Type'] = $DebugOutputStream
    }
}
function ConvertTo-Fqdn {
    [OutputType([System.String])]
    param (
        [Parameter(
            ParameterSetName = 'DistinguishedName',
            ValueFromPipeline
        )]
        [string[]]$DistinguishedName,
        [Parameter(
            ParameterSetName = 'NetBIOS',
            ValueFromPipeline
        )]
        [string[]]$NetBIOS,
        [hashtable]$DirectoryEntryCache = ([hashtable]::Synchronized(@{})),
        [hashtable]$DomainsByNetbios = ([hashtable]::Synchronized(@{})),
        [hashtable]$DomainsBySid = ([hashtable]::Synchronized(@{})),
        [hashtable]$DomainsByFqdn = ([hashtable]::Synchronized(@{})),
        [string]$ThisHostName = (HOSTNAME.EXE),
        [string]$ThisFqdn = ([System.Net.Dns]::GetHostByName((HOSTNAME.EXE)).HostName),
        [string]$WhoAmI = (whoami.EXE),
        [hashtable]$LogBuffer = ([hashtable]::Synchronized(@{})),
        [hashtable]$CimCache = ([hashtable]::Synchronized(@{})),
        [ValidateSet('Silent', 'Quiet', 'Success', 'Debug', 'Verbose', 'Output', 'Host', 'Warning', 'Error', 'Information', $null)]
        [string]$DebugOutputStream = 'Debug'
    )
    begin {
        $LogParams = @{
            ThisHostname = $ThisHostname
            Type         = $DebugOutputStream
            Buffer = $LogBuffer
            WhoAmI       = $WhoAmI
        }
        $LoggingParams = @{
            ThisHostname = $ThisHostname
            LogBuffer    = $LogBuffer
            WhoAmI       = $WhoAmI
        }
    }
    process {
        ForEach ($DN in $DistinguishedName) {
            $DN -replace ',DC=', '.' -replace 'DC=', ''
        }
        ForEach ($ThisNetBios in $NetBIOS) {
            $DomainObject = $DomainsByNetbios[$DomainNetBIOS]
            if (
                -not $DomainObject -and
                -not [string]::IsNullOrEmpty($DomainNetBIOS)
            ) {
                Write-LogMsg @LogParams -Text " # Domain NetBIOS cache miss for '$DomainNetBIOS'"
                $DomainObject = Get-AdsiServer -Netbios $DomainNetBIOS -CimCache $CimCache -DirectoryEntryCache $DirectoryEntryCache -DomainsByFqdn $DomainsByFqdn -DomainsByNetbios $DomainsByNetbios -DomainsBySid $DomainsBySid -ThisFqdn $ThisFqdn @LoggingParams
                $DomainsByNetbios[$DomainNetBIOS] = $DomainObject
            }
            $DomainObject.Dns
        }
    }
}
function ConvertTo-HexStringRepresentation {
    [OutputType([System.String[]])]
    param (
        [byte[]]$SIDByteArray
    )
    $SIDHexString = $SIDByteArray |
    ForEach-Object {
        '{0:X}' -f $_
    }
    return $SIDHexString
}
function ConvertTo-HexStringRepresentationForLDAPFilterString {
    [OutputType([System.String])]
    param (
        [byte[]]$SIDByteArray
    )
    $Hexes = $SIDByteArray |
    ForEach-Object {
        '{0:X}' -f $_
    } |
    ForEach-Object {
        if ($_.Length -eq 2) {
            $_
        } else {
            "0$_"
        }
    }
    "\$($Hexes -join '\')"
}
function ConvertTo-SidByteArray {
    [OutputType([System.Byte[]])]
    param (
        [Parameter(ValueFromPipeline)]
        [string[]]$SidString
    )
    process {
        ForEach ($ThisSID in $SidString) {
            $SID = [System.Security.Principal.SecurityIdentifier]::new($ThisSID)
            [byte[]]$Bytes = [byte[]]::new($SID.BinaryLength)
            $SID.GetBinaryForm($Bytes, 0)
            $Bytes
        }
    }
}
function Expand-AdsiGroupMember {
    [OutputType([System.DirectoryServices.DirectoryEntry])]
    param (
        [parameter(ValueFromPipeline)]
        $DirectoryEntry,
        [string[]]$PropertiesToLoad = (@('Department', 'description', 'distinguishedName', 'grouptype', 'managedby', 'member', 'name', 'objectClass', 'objectSid', 'operatingSystem', 'primaryGroupToken', 'samAccountName', 'Title')),
        [hashtable]$DirectoryEntryCache = ([hashtable]::Synchronized(@{})),
        [hashtable]$DomainsByNetbios = ([hashtable]::Synchronized(@{})),
        [hashtable]$DomainsBySid,
        [hashtable]$DomainsByFqdn = ([hashtable]::Synchronized(@{})),
        [string]$ThisHostName = (HOSTNAME.EXE),
        [string]$ThisFqdn = ([System.Net.Dns]::GetHostByName((HOSTNAME.EXE)).HostName),
        [string]$WhoAmI = (whoami.EXE),
        [hashtable]$LogBuffer = ([hashtable]::Synchronized(@{})),
        [hashtable]$CimCache = ([hashtable]::Synchronized(@{})),
        [ValidateSet('Silent', 'Quiet', 'Success', 'Debug', 'Verbose', 'Output', 'Host', 'Warning', 'Error', 'Information', $null)]
        [string]$DebugOutputStream = 'Debug'
    )
    begin {
        $LogParams = @{
            ThisHostname = $ThisHostname
            Type         = $DebugOutputStream
            Buffer       = $LogBuffer
            WhoAmI       = $WhoAmI
        }
        $LoggingParams = @{
            ThisHostname = $ThisHostname
            LogBuffer    = $LogBuffer
            WhoAmI       = $WhoAmI
        }
        if ( $DomainsBySid.Keys.Count -lt 1 ) {
            Write-LogMsg @LogParams -Text "# No valid DomainsBySid cache found"
            $DomainsBySid = ([hashtable]::Synchronized(@{}))
            $GetAdsiServerParams = @{
                DirectoryEntryCache = $DirectoryEntryCache
                DomainsByNetbios    = $DomainsByNetbios
                DomainsBySid        = $DomainsBySid
                DomainsByFqdn       = $DomainsByFqdn
                ThisFqdn            = $ThisFqdn
                CimCache            = $CimCache
            }
            Get-TrustedDomain |
            ForEach-Object {
                Write-LogMsg @LogParams -Text "Get-AdsiServer -Fqdn $($_.DomainFqdn)"
                $null = Get-AdsiServer -Fqdn $_.DomainFqdn @GetAdsiServerParams @LoggingParams
            }
        } else {
            Write-LogMsg @LogParams -Text "# Valid DomainsBySid cache found"
        }
        $CacheParams = @{
            DirectoryEntryCache = $DirectoryEntryCache
            DomainsByNetbios    = $DomainsByNetbios
            DomainsBySid        = $DomainsBySid
        }
        $i = 0
    }
    process {
        ForEach ($Entry in $DirectoryEntry) {
            $i++
            $Principal = $null
            if ($Entry.objectClass -contains 'foreignSecurityPrincipal') {
                if ($Entry.distinguishedName.Value -match '(?>^CN=)(?<SID>[^,]*)') {
                    [string]$SID = $Matches.SID
                    $DomainSid = $SID.Substring(0, $Sid.LastIndexOf("-"))
                    $Domain = $DomainsBySid[$DomainSid]
                    $GetDirectoryEntryParams = @{
                        ThisFqdn          = $ThisFqdn
                        CimCache          = $CimCache
                        DebugOutputStream = $DebugOutputStream
                    }
                    $Principal = Get-DirectoryEntry -DirectoryPath "LDAP://$($Domain.Dns)/<SID=$SID>" @GetDirectoryEntryParams @CacheParams @LoggingParams
                    try {
                        $null = $Principal.RefreshCache($PropertiesToLoad)
                    } catch {
                        $Principal = $Entry
                        Write-LogMsg @LogParams -Text "  '$SID' could not be retrieved from domain '$Domain'"
                    }
                    if ($Principal.properties['objectClass'].Value -contains 'group') {
                        Write-LogMsg @LogParams -Text "'$($Principal.properties['name'])' is a group in '$Domain'"
                        $AdsiGroupWithMembers = Get-AdsiGroupMember -Group $Principal -CimCache $CimCache -DomainsByFqdn $DomainsByFqdn -ThisFqdn $ThisFqdn @CacheParams @LoggingParams
                        $Principal = Expand-AdsiGroupMember -DirectoryEntry $AdsiGroupWithMembers.FullMembers -CimCache $CimCache -DomainsByFqdn $DomainsByFqdn -ThisFqdn $ThisFqdn -ThisHostName $ThisHostName @CacheParams
                    }
                }
            } else {
                $Principal = $Entry
            }
            Add-SidInfo -InputObject $Principal -DomainsBySid $DomainsBySid @LoggingParams
        }
    }
}
function Expand-WinNTGroupMember {
    [OutputType([System.DirectoryServices.DirectoryEntry])]
    param (
        [Parameter(ValueFromPipeline)]
        $DirectoryEntry,
        [hashtable]$CimCache = ([hashtable]::Synchronized(@{})),
        [hashtable]$DirectoryEntryCache = ([hashtable]::Synchronized(@{})),
        [hashtable]$DomainsByNetbios = ([hashtable]::Synchronized(@{})),
        [hashtable]$DomainsBySid = ([hashtable]::Synchronized(@{})),
        [hashtable]$DomainsByFqdn = ([hashtable]::Synchronized(@{})),
        [string]$ThisHostName = (HOSTNAME.EXE),
        [string]$ThisFqdn = ([System.Net.Dns]::GetHostByName((HOSTNAME.EXE)).HostName),
        [string]$WhoAmI = (whoami.EXE),
        [hashtable]$LogBuffer = ([hashtable]::Synchronized(@{})),
        [ValidateSet('Silent', 'Quiet', 'Success', 'Debug', 'Verbose', 'Output', 'Host', 'Warning', 'Error', 'Information', $null)]
        [string]$DebugOutputStream = 'Debug'
    )
    begin {
        $LogParams = @{
            ThisHostname = $ThisHostname
            Type         = $DebugOutputStream
            Buffer       = $LogBuffer
            WhoAmI       = $WhoAmI
        }
        $LoggingParams = @{
            ThisHostname = $ThisHostname
            LogBuffer    = $LogBuffer
            WhoAmI       = $WhoAmI
        }
    }
    process {
        ForEach ($ThisEntry in $DirectoryEntry) {
            if (!($ThisEntry.Properties)) {
                $LogParams['Type'] = 'Warning' 
                Write-LogMsg @LogParams -Text "'$ThisEntry' has no properties"
                $LogParams['Type'] = $DebugOutputStream
            } elseif ($ThisEntry.Properties['objectClass'] -contains 'group') {
                Write-LogMsg @LogParams -Text "'$($ThisEntry.Path)' is an ADSI group"
                $AdsiGroup = Get-AdsiGroup -CimCache $CimCache -DirectoryEntryCache $DirectoryEntryCache -DirectoryPath $ThisEntry.Path -DomainsByFqdn $DomainsByFqdn -DomainsByNetbios $DomainsByNetbios -DomainsBySid $DomainsBySid -ThisFqdn $ThisFqdn @LoggingParams
                Add-SidInfo -InputObject $AdsiGroup.FullMembers -DomainsBySid $DomainsBySid @LoggingParams
            } else {
                if ($ThisEntry.SchemaClassName -eq 'group') {
                    Write-LogMsg @LogParams -Text "'$($ThisEntry.Path)' is a WinNT group"
                    if ($ThisEntry.GetType().FullName -eq 'System.Collections.Hashtable') {
                        Write-LogMsg @LogParams -Text "$($ThisEntry.Path)' is a special group with no direct memberships"
                        Add-SidInfo -InputObject $ThisEntry -DomainsBySid $DomainsBySid @LoggingParams
                    } else {
                        Get-WinNTGroupMember -DirectoryEntry $ThisEntry -CimCache $CimCache -DirectoryEntryCache $DirectoryEntryCache -DomainsByFqdn $DomainsByFqdn -DomainsByNetbios $DomainsByNetbios -DomainsBySid $DomainsBySid -ThisFqdn $ThisFqdn @LoggingParams
                    }
                } else {
                    Write-LogMsg @LogParams -Text "$($ThisEntry.Path)' is a user account"
                    Add-SidInfo -InputObject $ThisEntry -DomainsBySid $DomainsBySid @LoggingParams
                }
            }
        }
    }
}
function Find-AdsiProvider {
    [OutputType([System.String])]
    param (
        [string]$AdsiServer,
        [string]$ThisFqdn = ([System.Net.Dns]::GetHostByName((HOSTNAME.EXE)).HostName),
        [string]$ThisHostName = (HOSTNAME.EXE),
        [string]$WhoAmI = (whoami.EXE),
        [hashtable]$LogBuffer = ([hashtable]::Synchronized(@{})),
        [hashtable]$CimCache = ([hashtable]::Synchronized(@{})),
        [ValidateSet('Silent', 'Quiet', 'Success', 'Debug', 'Verbose', 'Output', 'Host', 'Warning', 'Error', 'Information', $null)]
        [string]$DebugOutputStream = 'Debug'
    )
    $Log = @{
        ThisHostname = $ThisHostname
        Type         = $DebugOutputStream
        Buffer       = $LogBuffer
        WhoAmI       = $WhoAmI
    }
    $AdsiProvider = $null
    $CommandParameters = @{
        ComputerName      = $AdsiServer
        Namespace         = 'ROOT/StandardCimv2'
        Query             = 'Select * From MSFT_NetTCPConnection Where LocalPort = 389'
        KeyProperty       = 'LocalPort'
        CimCache          = $CimCache
        DebugOutputStream = $DebugOutputStream
        ErrorAction       = 'Ignore'
        LogBuffer         = $LogBuffer
        ThisFqdn          = $ThisFqdn
        ThisHostname      = $ThisHostname
        WhoAmI            = $WhoAmI
    }
    Write-LogMsg @Log -Text 'Get-CachedCimInstance' -Expand $CommandParameters
    if (Get-CachedCimInstance @CommandParameters) {
        $AdsiProvider = 'LDAP'
    }
    if (!$AdsiProvider) {
        $AdsiProvider = 'WinNT'
    }
    return $AdsiProvider
}
function Find-LocalAdsiServerSid {
    param (
        [string]$ComputerName,
        [hashtable]$CimCache = ([hashtable]::Synchronized(@{})),
        [string]$ThisHostName = (HOSTNAME.EXE),
        [string]$ThisFqdn = ([System.Net.Dns]::GetHostByName((HOSTNAME.EXE)).HostName),
        [string]$WhoAmI = (whoami.EXE),
        [hashtable]$LogBuffer = ([hashtable]::Synchronized(@{})),
        [ValidateSet('Silent', 'Quiet', 'Success', 'Debug', 'Verbose', 'Output', 'Host', 'Warning', 'Error', 'Information', $null)]
        [string]$DebugOutputStream = 'Debug'
    )
    $LogParams = @{
        ThisHostname = $ThisHostname
        Type         = $DebugOutputStream
        Buffer       = $LogBuffer
        WhoAmI       = $WhoAmI
    }
    $CimParams = @{
        CimCache          = $CimCache
        ComputerName      = $ThisHostName
        DebugOutputStream = $DebugOutputStream
        LogBuffer         = $LogBuffer
        ThisFqdn          = $ThisFqdn
        ThisHostname      = $ThisHostname
        WhoAmI            = $WhoAmI
    }
    Write-LogMsg @LogParams -Text "Get-CachedCimInstance -ComputerName '$ComputerName' -Query `"SELECT SID FROM Win32_UserAccount WHERE LocalAccount = 'True' AND SID LIKE 'S-1-5-21-%-500'`""
    $LocalAdminAccount = Get-CachedCimInstance -Query "SELECT SID FROM Win32_UserAccount WHERE LocalAccount = 'True' AND SID LIKE 'S-1-5-21-%-500'" -KeyProperty SID @CimParams
    if (-not $LocalAdminAccount) {
        return
    }
    return $LocalAdminAccount.SID.Substring(0, $LocalAdminAccount.SID.LastIndexOf("-"))
}
function Get-AdsiGroup {
    [OutputType([System.DirectoryServices.DirectoryEntry])]
    param (
        [string]$DirectoryPath = (([System.DirectoryServices.DirectorySearcher]::new()).SearchRoot.Path),
        [string]$GroupName,
        [string[]]$PropertiesToLoad = (@('Department', 'description', 'distinguishedName', 'grouptype', 'managedby', 'member', 'name', 'objectClass', 'objectSid', 'operatingSystem', 'primaryGroupToken', 'samAccountName', 'Title')),
        [hashtable]$CimCache = ([hashtable]::Synchronized(@{})),
        [hashtable]$DirectoryEntryCache = ([hashtable]::Synchronized(@{})),
        [hashtable]$DomainsByNetbios = ([hashtable]::Synchronized(@{})),
        [hashtable]$DomainsBySid = ([hashtable]::Synchronized(@{})),
        [hashtable]$DomainsByFqdn = ([hashtable]::Synchronized(@{})),
        [string]$ThisHostName = (HOSTNAME.EXE),
        [string]$ThisFqdn = ([System.Net.Dns]::GetHostByName((HOSTNAME.EXE)).HostName),
        [string]$WhoAmI = (whoami.EXE),
        [hashtable]$LogBuffer = ([hashtable]::Synchronized(@{}))
    )
    $GroupParams = @{
        DirectoryPath       = $DirectoryPath
        PropertiesToLoad    = $PropertiesToLoad
        DirectoryEntryCache = $DirectoryEntryCache
        DomainsByFqdn       = $DomainsByFqdn
        DomainsByNetbios    = $DomainsByNetbios
        DomainsBySid        = $DomainsBySid
        ThisHostname        = $ThisHostname
        LogBuffer           = $LogBuffer
        WhoAmI              = $WhoAmI
        ThisFqdn            = $ThisFqdn
        CimCache            = $CimCache
        DebugOutputStream   = $DebugOutputStream
    }
    $GroupMemberParams = @{
        PropertiesToLoad    = $PropertiesToLoad
        DirectoryEntryCache = $DirectoryEntryCache
        DomainsByFqdn       = $DomainsByFqdn
        DomainsByNetbios    = $DomainsByNetbios
        DomainsBySid        = $DomainsBySid
        ThisHostName        = $ThisHostName
        ThisFqdn            = $ThisFqdn
        LogBuffer           = $LogBuffer
        CimCache            = $CimCache
        WhoAmI              = $WhoAmI
    }
    switch -Regex ($DirectoryPath) {
        '^WinNT' {
            $GroupParams['DirectoryPath'] = "$DirectoryPath/$GroupName"
            $GroupMemberParams['DirectoryEntry'] = Get-DirectoryEntry @GroupParams
            $FullMembers = Get-WinNTGroupMember @GroupMemberParams
        }
        '^$' {
            $GroupParams['DirectoryPath'] = "WinNT://localhost/$GroupName"
            $GroupMemberParams['DirectoryEntry'] = Get-DirectoryEntry @GroupParams
            $FullMembers = Get-WinNTGroupMember @GroupMemberParams
        }
        default {
            if ($GroupName) {
                $GroupParams['Filter'] = "(&(objectClass=group)(cn=$GroupName))"
            } else {
                $GroupParams['Filter'] = '(objectClass=group)'
            }
            $GroupMemberParams['Group'] = Search-Directory @GroupParams
            $FullMembers = Get-AdsiGroupMember @GroupMemberParams
        }
    }
    $FullMembers
}
function Get-AdsiGroupMember {
    [OutputType([System.DirectoryServices.DirectoryEntry])]
    param (
        [Parameter(ValueFromPipeline)]
        $Group,
        [string[]]$PropertiesToLoad,
        [hashtable]$DirectoryEntryCache = ([hashtable]::Synchronized(@{})),
        [hashtable]$DomainsByNetbios = ([hashtable]::Synchronized(@{})),
        [hashtable]$DomainsBySid = ([hashtable]::Synchronized(@{})),
        [hashtable]$DomainsByFqdn = ([hashtable]::Synchronized(@{})),
        [string]$ThisHostName = (HOSTNAME.EXE),
        [string]$ThisFqdn = ([System.Net.Dns]::GetHostByName((HOSTNAME.EXE)).HostName),
        [string]$WhoAmI = (whoami.EXE),
        [hashtable]$LogBuffer = ([hashtable]::Synchronized(@{})),
        [hashtable]$CimCache = ([hashtable]::Synchronized(@{})),
        [switch]$NoRecurse,
        [switch]$PrimaryGroupOnly,
        [ValidateSet('Silent', 'Quiet', 'Success', 'Debug', 'Verbose', 'Output', 'Host', 'Warning', 'Error', 'Information', $null)]
        [string]$DebugOutputStream = 'Debug'
    )
    begin {
        $LogParams = @{
            ThisHostname = $ThisHostname
            Type         = $DebugOutputStream
            Buffer       = $LogBuffer
            WhoAmI       = $WhoAmI
        }
        $LoggingParams = @{
            ThisHostname = $ThisHostname
            LogBuffer    = $LogBuffer
            WhoAmI       = $WhoAmI
        }
        $PathRegEx = '(?<Path>LDAP:\/\/[^\/]*)'
        $DomainRegEx = '(?i)DC=\w{1,}?\b'
        $PropertiesToLoad += 'primaryGroupToken', 'objectSid', 'objectClass'
        $PropertiesToLoad = $PropertiesToLoad |
        Sort-Object -Unique
        $SearchParameters = @{
            PropertiesToLoad    = $PropertiesToLoad
            DirectoryEntryCache = $DirectoryEntryCache
            DomainsByNetbios    = $DomainsByNetbios
            CimCache            = $CimCache
            ThisFqdn            = $ThisFqdn
        }
        $CacheParams = @{
            DirectoryEntryCache = $DirectoryEntryCache
            DomainsByNetbios    = $DomainsByNetbios
            DomainsBySid        = $DomainsBySid
        }
    }
    process {
        foreach ($ThisGroup in $Group) {
            if (-not $ThisGroup.Properties['primaryGroupToken']) {
                $ThisGroup.RefreshCache('primaryGroupToken')
            }
            $primaryGroupIdFilter = "(primaryGroupId=$($ThisGroup.Properties['primaryGroupToken']))"
            if ($PrimaryGroupOnly) {
                $SearchParameters['Filter'] = $primaryGroupIdFilter
            } else {
                if ($NoRecurse) {
                    $MemberOfFilter = "(memberOf=$($ThisGroup.Properties['distinguishedname']))"
                } else {
                    $MemberOfFilter = "(memberOf:1.2.840.113556.1.4.1941:=$($ThisGroup.Properties['distinguishedname']))"
                }
                $SearchParameters['Filter'] = "(|$MemberOfFilter$primaryGroupIdFilter)"
            }
            if ($ThisGroup.Path -match $PathRegEx) {
                $SearchParameters['DirectoryPath'] = Add-DomainFqdnToLdapPath -DirectoryPath $Matches.Path -ThisFqdn $ThisFqdn -CimCache $CimCache @LoggingParams
                if ($ThisGroup.Path -match $DomainRegEx) {
                    $Domain = ([regex]::Matches($ThisGroup.Path, $DomainRegEx) | ForEach-Object { $_.Value }) -join ','
                    $SearchParameters['DirectoryPath'] = Add-DomainFqdnToLdapPath -DirectoryPath "LDAP://$Domain" -ThisFqdn $ThisFqdn -CimCache $CimCache @LoggingParams
                } else {
                    $SearchParameters['DirectoryPath'] = Add-DomainFqdnToLdapPath -DirectoryPath $ThisGroup.Path -ThisFqdn $ThisFqdn -CimCache $CimCache @LoggingParams
                }
            } else {
                $SearchParameters['DirectoryPath'] = Add-DomainFqdnToLdapPath -DirectoryPath $ThisGroup.Path -ThisFqdn $ThisFqdn -CimCache $CimCache @LoggingParams
            }
            Write-LogMsg @LogParams -Text "Search-Directory -DirectoryPath '$($SearchParameters['DirectoryPath'])' -Filter '$($SearchParameters['Filter'])'"
            $GroupMemberSearch = Search-Directory @SearchParameters
            Write-LogMsg @LogParams -Text " # '$($GroupMemberSearch.Count)' results for Search-Directory -DirectoryPath '$($SearchParameters['DirectoryPath'])' -Filter '$($SearchParameters['Filter'])'"
            if ($GroupMemberSearch.Count -gt 0) {
                $DirectoryEntryParams = @{
                    PropertiesToLoad  = $PropertiesToLoad
                    DomainsByFqdn     = $DomainsByFqdn
                    ThisFqdn          = $ThisFqdn
                    CimCache          = $CimCache
                    DebugOutputStream = $DebugOutputStream
                }
                $CurrentADGroupMembers = [System.Collections.Generic.List[System.DirectoryServices.DirectoryEntry]]::new()
                $MembersThatAreGroups = $GroupMemberSearch |
                Where-Object -FilterScript { $_.Properties['objectClass'] -contains 'group' }
                $DirectoryEntryParams = @{
                    PropertiesToLoad  = $PropertiesToLoad
                    DomainsByFqdn     = $DomainsByFqdn
                    ThisFqdn          = $ThisFqdn
                    CimCache          = $CimCache
                    DebugOutputStream = $DebugOutputStream
                }
                if ($MembersThatAreGroups.Count -gt 0) {
                    $FilterBuilder = [System.Text.StringBuilder]::new("(|")
                    ForEach ($ThisMember in $MembersThatAreGroups) {
                        $null = $FilterBuilder.Append("(primaryGroupId=$($ThisMember.Properties['primaryGroupToken'])))")
                    }
                    $null = $FilterBuilder.Append(")")
                    $PrimaryGroupFilter = $FilterBuilder.ToString()
                    $SearchParameters['Filter'] = $PrimaryGroupFilter
                    Write-LogMsg @LogParams -Text "Search-Directory -DirectoryPath '$($SearchParameters['DirectoryPath'])' -Filter '$($SearchParameters['Filter'])'"
                    $PrimaryGroupMembers = Search-Directory @SearchParameters
                    ForEach ($ThisMember in $PrimaryGroupMembers) {
                        $FQDNPath = Add-DomainFqdnToLdapPath -DirectoryPath $ThisMember.Path -ThisFqdn $ThisFqdn -CimCache $CimCache @LoggingParams
                        $DirectoryEntry = $null
                        Write-LogMsg @LogParams -Text "Get-DirectoryEntry -DirectoryPath '$FQDNPath'"
                        $DirectoryEntry = Get-DirectoryEntry -DirectoryPath $FQDNPath @DirectoryEntryParams @CacheParams @LoggingParams
                        if ($DirectoryEntry) {
                            $null = $CurrentADGroupMembers.Add($DirectoryEntry)
                        }
                    }
                }
                ForEach ($ThisMember in $GroupMemberSearch) {
                    $FQDNPath = Add-DomainFqdnToLdapPath -DirectoryPath $ThisMember.Path -ThisFqdn $ThisFqdn -CimCache $CimCache @LoggingParams
                    $DirectoryEntry = $null
                    Write-LogMsg @LogParams -Text "Get-DirectoryEntry -DirectoryPath '$FQDNPath'"
                    $DirectoryEntry = Get-DirectoryEntry -DirectoryPath $FQDNPath @DirectoryEntryParams @CacheParams @LoggingParams
                    if ($DirectoryEntry) {
                        $null = $CurrentADGroupMembers.Add($DirectoryEntry)
                    }
                }
            } else {
                $CurrentADGroupMembers = $null
            }
            Write-LogMsg @LogParams -Text "$($ThisGroup.Properties.name) has $(($CurrentADGroupMembers | Measure-Object).Count) members"
            $ProcessedGroupMembers = Expand-AdsiGroupMember -DirectoryEntry $CurrentADGroupMembers -CimCache $CimCache -DomainsByFqdn $DomainsByFqdn -ThisFqdn $ThisFqdn @CacheParams @LoggingParams
            Add-Member -InputObject $ThisGroup -MemberType NoteProperty -Name FullMembers -Value $ProcessedGroupMembers -Force -PassThru
        }
    }
}
function Get-AdsiServer {
    [OutputType([System.String])]
    param (
        [Parameter(ValueFromPipeline)]
        [string[]]$Fqdn,
        [string[]]$Netbios,
        [hashtable]$CimCache = ([hashtable]::Synchronized(@{})),
        [hashtable]$DirectoryEntryCache = ([hashtable]::Synchronized(@{})),
        [hashtable]$DomainsByNetbios = ([hashtable]::Synchronized(@{})),
        [hashtable]$DomainsBySid = ([hashtable]::Synchronized(@{})),
        [hashtable]$DomainsByFqdn = ([hashtable]::Synchronized(@{})),
        [string]$ThisHostName = (HOSTNAME.EXE),
        [string]$ThisFqdn = ([System.Net.Dns]::GetHostByName((HOSTNAME.EXE)).HostName),
        [string]$WhoAmI = (whoami.EXE),
        [hashtable]$LogBuffer = ([hashtable]::Synchronized(@{})),
        [ValidateSet('Silent', 'Quiet', 'Success', 'Debug', 'Verbose', 'Output', 'Host', 'Warning', 'Error', 'Information', $null)]
        [string]$DebugOutputStream = 'Debug',
        [switch]$RemoveCimSession
    )
    begin {
        $LogParams = @{
            ThisHostname = $ThisHostname
            Type         = $DebugOutputStream
            Buffer       = $LogBuffer
            WhoAmI       = $WhoAmI
        }
        $LoggingParams = @{
            ThisHostname = $ThisHostname
            LogBuffer    = $LogBuffer
            WhoAmI       = $WhoAmI
        }
        $CacheParams = @{
            DirectoryEntryCache = $DirectoryEntryCache
            DomainsByFqdn       = $DomainsByFqdn
            DomainsByNetbios    = $DomainsByNetbios
            DomainsBySid        = $DomainsBySid
        }
        $CimParams = @{
            CimCache          = $CimCache
            ComputerName      = $ThisFqdn
            DebugOutputStream = $DebugOutputStream
            ThisFqdn          = $ThisFqdn
        }
    }
    process {
        ForEach ($DomainFqdn in $Fqdn) {
            $OutputObject = $DomainsByFqdn[$DomainFqdn]
            if ($OutputObject) {
                Write-LogMsg @LogParams -Text " # Domain FQDN cache hit for '$DomainFqdn'"
                $OutputObject
                continue
            }
            Write-LogMsg @LogParams -Text "Find-AdsiProvider -AdsiServer '$DomainFqdn' # Domain FQDN cache miss for '$DomainFqdn'"
            $AdsiProvider = Find-AdsiProvider -AdsiServer $DomainFqdn -CimCache $CimCache -ThisFqdn $ThisFqdn @LoggingParams
            $CacheParams['AdsiProvider'] = $AdsiProvider
            Write-LogMsg @LogParams -Text "ConvertTo-DistinguishedName -DomainFQDN '$DomainFqdn' -AdsiProvider '$AdsiProvider'"
            $DomainDn = ConvertTo-DistinguishedName -DomainFQDN $DomainFqdn -AdsiProvider $AdsiProvider @LoggingParams
            Write-LogMsg @LogParams -Text "ConvertTo-DomainSidString -DomainDnsName '$DomainFqdn' -ThisFqdn '$ThisFqdn'"
            $DomainSid = ConvertTo-DomainSidString -DomainDnsName $DomainFqdn -ThisFqdn $ThisFqdn -CimCache $CimCache @CacheParams @LoggingParams
            Write-LogMsg @LogParams -Text "ConvertTo-DomainNetBIOS -DomainFQDN '$DomainFqdn'"
            $DomainNetBIOS = ConvertTo-DomainNetBIOS -DomainFQDN $DomainFqdn -ThisFqdn $ThisFqdn -CimCache $CimCache @CacheParams @LoggingParams
            Write-LogMsg @LogParams -Text "Get-CachedCimInstance -ComputerName '$DomainFqdn' -ClassName 'Win32_Account'"
            $Win32Accounts = Get-CachedCimInstance -ComputerName $DomainFqdn -ClassName 'Win32_Account' -KeyProperty Caption -CacheByProperty @('Caption', 'SID') @CimParams @LoggingParams
            $OutputObject = [PSCustomObject]@{
                DistinguishedName = $DomainDn
                Dns               = $DomainFqdn
                Sid               = $DomainSid
                Netbios           = $DomainNetBIOS
                AdsiProvider      = $AdsiProvider
                Win32Accounts     = $Win32Accounts
            }
            $DomainsBySid[$OutputObject.Sid] = $OutputObject
            $DomainsByNetbios[$OutputObject.Netbios] = $OutputObject
            $DomainsByFqdn[$DomainFqdn] = $OutputObject
            $OutputObject
        }
        ForEach ($DomainNetbios in $Netbios) {
            $OutputObject = $DomainsByNetbios[$DomainNetbios]
            if ($OutputObject) {
                Write-LogMsg @LogParams -Text " # Domain NetBIOS cache hit for '$DomainNetbios'"
                $OutputObject
                continue
            }
            Write-LogMsg @LogParams -Text "Get-CachedCimSession -ComputerName '$DomainNetbios' # Domain NetBIOS cache hit for '$DomainNetbios'"
            $CimSession = Get-CachedCimSession -ComputerName $DomainNetbios -ThisFqdn $ThisFqdn -CimCache $CimCache @LoggingParams
            Write-LogMsg @LogParams -Text "Find-AdsiProvider -AdsiServer '$DomainDnsName' # for '$DomainNetbios'"
            $AdsiProvider = Find-AdsiProvider -AdsiServer $DomainDnsName -CimCache $CimCache -ThisFqdn $ThisFqdn @LoggingParams
            $CacheParams['AdsiProvider'] = $AdsiProvider
            Write-LogMsg @LogParams -Text "ConvertTo-DistinguishedName -Domain '$DomainNetBIOS'"
            $DomainDn = ConvertTo-DistinguishedName -Domain $DomainNetBIOS -DomainsByNetbios $DomainsByNetbios @LoggingParams
            if ($DomainDn) {
                Write-LogMsg @LogParams -Text "ConvertTo-Fqdn -DistinguishedName '$DomainDn' # for '$DomainNetbios'"
                $DomainDnsName = ConvertTo-Fqdn -DistinguishedName $DomainDn -ThisFqdn $ThisFqdn -CimCache $CimCache @LoggingParams
            } else {
                $ParentDomainDnsName = Get-ParentDomainDnsName -DomainsByNetbios $DomainNetBIOS -CimSession $CimSession -ThisFqdn $ThisFqdn -CimCache $CimCache @LoggingParams
                $DomainDnsName = "$DomainNetBIOS.$ParentDomainDnsName"
            }
            Write-LogMsg @LogParams -Text "ConvertTo-DomainSidString -DomainDnsName '$DomainFqdn' -AdsiProvider '$AdsiProvider' -ThisFqdn '$ThisFqdn' # for '$DomainNetbios'"
            $DomainSid = ConvertTo-DomainSidString -DomainDnsName $DomainDnsName -ThisFqdn $ThisFqdn -CimCache $CimCache @CacheParams @LoggingParams
            Write-LogMsg @LogParams -Text "Get-CachedCimInstance -ComputerName '$DomainDnsName' -ClassName 'Win32_Account' # for '$DomainNetbios'"
            $Win32Accounts = Get-CachedCimInstance -ComputerName $DomainFqdn -ClassName 'Win32_Account' -KeyProperty Caption -CacheByProperty @('Caption', 'SID') @CimParams @LoggingParams
            if ($RemoveCimSession) {
                Remove-CimSession -CimSession $CimSession
            }
            $OutputObject = [PSCustomObject]@{
                DistinguishedName = $DomainDn
                Dns               = $DomainDnsName
                Sid               = $DomainSid
                Netbios           = $DomainNetBIOS
                AdsiProvider      = $AdsiProvider
                Win32Accounts     = $Win32Accounts
            }
            $DomainsBySid[$OutputObject.Sid] = $OutputObject
            $DomainsByNetbios[$OutputObject.Netbios] = $OutputObject
            $DomainsByFqdn[$OutputObject.Dns] = $OutputObject
            $OutputObject
        }
    }
}
function Get-CurrentDomain {
    [OutputType([System.DirectoryServices.DirectoryEntry])]
    param (
        [string]$ComputerName,
        [hashtable]$CimCache = ([hashtable]::Synchronized(@{})),
        [string]$ThisHostName = (HOSTNAME.EXE),
        [string]$ThisFqdn = ([System.Net.Dns]::GetHostByName((HOSTNAME.EXE)).HostName),
        [string]$WhoAmI = (whoami.EXE),
        [hashtable]$LogBuffer = ([hashtable]::Synchronized(@{})),
        [ValidateSet('Silent', 'Quiet', 'Success', 'Debug', 'Verbose', 'Output', 'Host', 'Warning', 'Error', 'Information', $null)]
        [string]$DebugOutputStream = 'Debug'
    )
    $CimParams = @{
        CimCache          = $CimCache
        ComputerName      = $ComputerName
        DebugOutputStream = $DebugOutputStream
        LogBuffer       = $LogBuffer
        ThisFqdn          = $ThisFqdn
        ThisHostname      = $ThisHostname
        WhoAmI            = $WhoAmI
    }
    $Comp = Get-CachedCimInstance -ClassName Win32_ComputerSystem -KeyProperty Name @CimParams
    if ($Comp.Domain -eq 'WORKGROUP') {
        $SIDString = Find-LocalAdsiServerSid @CimParams
        $SID = $SIDString | ConvertTo-SidByteArray
        $OutputProperties = @{
            SIDString         = $SIDString
            ObjectSid         = [PSCustomObject]@{
                Value = $Sid
            }
            DistinguishedName = [PSCustomObject]@{
                Value = "DC=$ComputerName"
            }
        }
    } else {
        $CurrentDomain = [adsi]::new()
        $null = $CurrentDomain.RefreshCache('objectSid')
        Write-LogMsg @LogParams -Text '[System.Security.Principal.SecurityIdentifier]::new([byte[]]$CurrentDomain.objectSid.Value, 0)'
        $OutputProperties = @{
            SIDString = & { [System.Security.Principal.SecurityIdentifier]::new([byte[]]$CurrentDomain.objectSid.Value, 0) } 2>$null
        }
        $InputProperties = (Get-Member -InputObject $CurrentDomain[0] -MemberType Property, CodeProperty, ScriptProperty, NoteProperty).Name
        ForEach ($ThisProperty in $InputProperties) {
            $OutputProperties[$ThisProperty] = $ThisPrincipal.$ThisProperty
        }
    }
    return [PSCustomObject]$OutputProperties
}
function Get-DirectoryEntry {
    [OutputType([System.DirectoryServices.DirectoryEntry], [PSCustomObject])]
    [CmdletBinding()]
    param (
        [string]$DirectoryPath = (([System.DirectoryServices.DirectorySearcher]::new()).SearchRoot.Path),
        [pscredential]$Credential,
        [string[]]$PropertiesToLoad,
        [hashtable]$CimCache = ([hashtable]::Synchronized(@{})),
        [hashtable]$DirectoryEntryCache = ([hashtable]::Synchronized(@{})),
        [hashtable]$DomainsByFqdn = ([hashtable]::Synchronized(@{})),
        [hashtable]$DomainsByNetbios = ([hashtable]::Synchronized(@{})),
        [hashtable]$DomainsBySid = ([hashtable]::Synchronized(@{})),
        [string]$ThisHostName = (HOSTNAME.EXE),
        [string]$ThisFqdn = ([System.Net.Dns]::GetHostByName((HOSTNAME.EXE)).HostName),
        [string]$WhoAmI = (whoami.EXE),
        [hashtable]$LogBuffer = ([hashtable]::Synchronized(@{})),
        [ValidateSet('Silent', 'Quiet', 'Success', 'Debug', 'Verbose', 'Output', 'Host', 'Warning', 'Error', 'Information', $null)]
        [string]$DebugOutputStream = 'Debug'
    )
    $LogParams = @{
        ThisHostname = $ThisHostname
        Type         = $DebugOutputStream
        Buffer       = $LogBuffer
        WhoAmI       = $WhoAmI
    }
    $LoggingParams = @{
        ThisHostname = $ThisHostname
        LogBuffer    = $LogBuffer
        WhoAmI       = $WhoAmI
    }
    $DirectoryEntry = $null
    if ($null -eq $DirectoryEntryCache[$DirectoryPath]) {
        switch -regex ($DirectoryPath) {
            '^WinNT:\/\/.*\/CREATOR OWNER$' {
                $DirectoryEntry = New-FakeDirectoryEntry -DirectoryPath $DirectoryPath
            }
            '^WinNT:\/\/.*\/SYSTEM$' {
                $DirectoryEntry = New-FakeDirectoryEntry -DirectoryPath $DirectoryPath
            }
            '^WinNT:\/\/.*\/INTERACTIVE$' {
                $DirectoryEntry = New-FakeDirectoryEntry -DirectoryPath $DirectoryPath
            }
            '^WinNT:\/\/.*\/Authenticated Users$' {
                $DirectoryEntry = New-FakeDirectoryEntry -DirectoryPath $DirectoryPath
            }
            '^WinNT:\/\/.*\/TrustedInstaller$' {
                $DirectoryEntry = New-FakeDirectoryEntry -DirectoryPath $DirectoryPath
            }
            '^WinNT:\/\/.*\/ALL APPLICATION PACKAGES$' {
                $DirectoryEntry = New-FakeDirectoryEntry -DirectoryPath $DirectoryPath
            }
            '^WinNT:\/\/.*\/ALL RESTRICTED APPLICATION PACKAGES$' {
                $DirectoryEntry = New-FakeDirectoryEntry -DirectoryPath $DirectoryPath
            }
            '^WinNT:\/\/.*\/Everyone$' {
                $DirectoryEntry = New-FakeDirectoryEntry -DirectoryPath $DirectoryPath
            }
            '^WinNT:\/\/.*\/LOCAL SERVICE$' {
                $DirectoryEntry = New-FakeDirectoryEntry -DirectoryPath $DirectoryPath
            }
            '^WinNT:\/\/.*\/NETWORK SERVICE$' {
                $DirectoryEntry = New-FakeDirectoryEntry -DirectoryPath $DirectoryPath
            }
            '^$' {
                Write-LogMsg @LogParams -Text "'$ThisHostname' does not seem to be domain-joined since the SearchRoot Path is empty. Defaulting to WinNT provider for localhost instead."
                $CimParams = @{
                    CimCache          = $CimCache
                    ComputerName      = $ThisFqdn
                    DebugOutputStream = $DebugOutputStream
                    ThisFqdn          = $ThisFqdn
                }
                $Workgroup = (Get-CachedCimInstance -ClassName 'Win32_ComputerSystem' -KeyProperty Name @CimParams @LoggingParams).Workgroup
                $DirectoryPath = "WinNT://$Workgroup/$ThisHostname"
                Write-LogMsg @LogParams -Text "[System.DirectoryServices.DirectoryEntry]::new('$DirectoryPath')"
                if ($Credential) {
                    $DirectoryEntry = [System.DirectoryServices.DirectoryEntry]::new($DirectoryPath, $($Credential.UserName), $($Credential.GetNetworkCredential().password))
                } else {
                    $DirectoryEntry = [System.DirectoryServices.DirectoryEntry]::new($DirectoryPath)
                }
                $SampleUser = @($DirectoryEntry.PSBase.Children |
                    Where-Object -FilterScript { $_.schemaclassname -eq 'user' })[0] |
                Add-SidInfo -DomainsBySid $DomainsBySid @LoggingParams
                $DirectoryEntry |
                Add-Member -MemberType NoteProperty -Name 'Domain' -Value $SampleUser.Domain -Force
            }
            default {
                Write-LogMsg @LogParams -Text "[System.DirectoryServices.DirectoryEntry]::new('$DirectoryPath')"
                if ($Credential) {
                    $DirectoryEntry = [System.DirectoryServices.DirectoryEntry]::new($DirectoryPath, $($Credential.UserName), $($Credential.GetNetworkCredential().password))
                } else {
                    $DirectoryEntry = [System.DirectoryServices.DirectoryEntry]::new($DirectoryPath)
                }
            }
        }
        $DirectoryEntryCache[$DirectoryPath] = $DirectoryEntry
    } else {
        $DirectoryEntry = $DirectoryEntryCache[$DirectoryPath]
    }
    if ($PropertiesToLoad) {
        try {
            $null = $DirectoryEntry.RefreshCache($PropertiesToLoad)
        } catch {
            $LogParams['Type'] = 'Warning' 
            Write-LogMsg @LogParams -Text "'$DirectoryPath' could not be retrieved. Error: $($_.Exception.Message.Trim() -replace '\s"',' "')"
            return
        }
    }
    return $DirectoryEntry
}
function Get-ParentDomainDnsName {
    param (
        [string]$DomainNetbios,
        [hashtable]$CimCache = ([hashtable]::Synchronized(@{})),
        [string]$ThisHostName = (HOSTNAME.EXE),
        [string]$ThisFqdn = ([System.Net.Dns]::GetHostByName((HOSTNAME.EXE)).HostName),
        [string]$WhoAmI = (whoami.EXE),
        [hashtable]$LogBuffer = ([hashtable]::Synchronized(@{})),
        [CimSession]$CimSession,
        [ValidateSet('Silent', 'Quiet', 'Success', 'Debug', 'Verbose', 'Output', 'Host', 'Warning', 'Error', 'Information', $null)]
        [string]$DebugOutputStream = 'Debug',
        [switch]$RemoveCimSession
    )
    $LogParams = @{
        ThisHostname = $ThisHostname
        Type         = $DebugOutputStream
        Buffer = $LogBuffer
        WhoAmI       = $WhoAmI
    }
    if (-not $CimSession) {
        Write-LogMsg @LogParams -Text "Get-CachedCimSession -ComputerName '$DomainNetbios'"
        $CimSession = Get-CachedCimSession -ComputerName $DomainNetbios -ThisFqdn $ThisFqdn -CimCache $CimCache @LoggingParams
    }
    Write-LogMsg @LogParams -Text "((Get-CachedCimInstance -ComputerName '$DomainNetbios' -ClassName CIM_ComputerSystem -ThisFqdn '$ThisFqdn').domain # for '$DomainNetbios'"
    $ParentDomainDnsName = (Get-CachedCimInstance -ComputerName $DomainNetbios -ClassName CIM_ComputerSystem -ThisFqdn $ThisFqdn -KeyProperty Name -CimCache $CimCache @LoggingParams).domain
    if ($ParentDomainDnsName -eq 'WORKGROUP' -or $null -eq $ParentDomainDnsName) {
        Write-LogMsg @LogParams -Text "(Get-DnsClientGlobalSetting -CimSession `$CimSession).SuffixSearchList[0] # for '$DomainNetbios'"
        $ParentDomainDnsName = (Get-DnsClientGlobalSetting -CimSession $CimSession).SuffixSearchList[0]
    }
    if ($RemoveCimSession) {
        Remove-CimSession -CimSession $CimSession
    }
    return $ParentDomainDnsName
}
function Get-TrustedDomain {
    [OutputType([PSCustomObject])]
    param (
        $ThisHostname = (HOSTNAME.EXE),
        [string]$WhoAmI = (whoami.EXE),
        [hashtable]$LogBuffer = ([hashtable]::Synchronized(@{})),
        [ValidateSet('Silent', 'Quiet', 'Success', 'Debug', 'Verbose', 'Output', 'Host', 'Warning', 'Error', 'Information', $null)]
        [string]$DebugOutputStream = 'Debug'
    )
    $LogParams = @{
        ThisHostname = $ThisHostname
        Type         = $DebugOutputStream
        Buffer       = $LogBuffer
        WhoAmI       = $WhoAmI
    }
    Write-LogMsg @LogParams -Text "$('& nltest /domain_trusts 2>&1')"
    $nltestresults = & nltest /domain_trusts 2>&1
    $RegExForEachTrust = '(?<index>[\d]*): (?<netbios>\S*) (?<dns>\S*).*'
    ForEach ($Result in $nltestresults) {
        if ($Result.GetType() -eq [string]) {
            if ($Result -match $RegExForEachTrust) {
                [PSCustomObject]@{
                    DomainFqdn    = $Matches.dns
                    DomainNetbios = $Matches.netbios
                }
            }
        }
    }
}
function Get-WinNTGroupMember {
    [OutputType([System.DirectoryServices.DirectoryEntry])]
    param (
        [Parameter(ValueFromPipeline)]
        $DirectoryEntry,
        [string[]]$PropertiesToLoad,
        [hashtable]$DirectoryEntryCache = ([hashtable]::Synchronized(@{})),
        [hashtable]$DomainsByNetbios = ([hashtable]::Synchronized(@{})),
        [hashtable]$DomainsBySid = ([hashtable]::Synchronized(@{})),
        [hashtable]$DomainsByFqdn = ([hashtable]::Synchronized(@{})),
        [string]$ThisHostName = (HOSTNAME.EXE),
        [string]$ThisFqdn = ([System.Net.Dns]::GetHostByName((HOSTNAME.EXE)).HostName),
        [string]$WhoAmI = (whoami.EXE),
        [hashtable]$LogBuffer = ([hashtable]::Synchronized(@{})),
        [hashtable]$CimCache = ([hashtable]::Synchronized(@{})),
        [ValidateSet('Silent', 'Quiet', 'Success', 'Debug', 'Verbose', 'Output', 'Host', 'Warning', 'Error', 'Information', $null)]
        [string]$DebugOutputStream = 'Debug'
    )
    begin {
        $LogParams = @{
            ThisHostname = $ThisHostname
            Type         = $DebugOutputStream
            Buffer       = $LogBuffer
            WhoAmI       = $WhoAmI
        }
        $LoggingParams = @{
            ThisHostname = $ThisHostname
            LogBuffer    = $LogBuffer
            WhoAmI       = $WhoAmI
        }
        $PropertiesToLoad += 'Department',
        'description',
        'distinguishedName',
        'grouptype',
        'managedby',
        'member',
        'name',
        'objectClass',
        'objectSid',
        'operatingSystem',
        'primaryGroupToken',
        'samAccountName',
        'Title'
        $PropertiesToLoad = $PropertiesToLoad |
        Sort-Object -Unique
    }
    process {
        ForEach ($ThisDirEntry in $DirectoryEntry) {
            $SourceDomain = $ThisDirEntry.Path | Split-Path -Parent | Split-Path -Leaf
            if ($null -ne $ThisDirEntry.Properties['groupType'] -or $ThisDirEntry.schemaclassname -eq 'group') {
                $DirectoryMembers = & { $ThisDirEntry.Invoke('Members') } 2>$null
                Write-LogMsg @LogParams -Text " # '$($ThisDirEntry.Path)' has $(($DirectoryMembers | Measure-Object).Count) members # For $($ThisDirEntry.Path)"
                $MembersToGet = @{
                    'WinNTMembers' = @()
                }
                $MemberParams = @{
                    DirectoryEntryCache = $DirectoryEntryCache
                    PropertiesToLoad    = $PropertiesToLoad
                    DomainsByNetbios    = $DomainsByNetbios
                    LogBuffer           = $LogBuffer
                    WhoAmI              = $WhoAmI
                    CimCache            = $CimCache
                    ThisFqdn            = $ThisFqdn
                }
                ForEach ($DirectoryMember in $DirectoryMembers) {
                    $DirectoryPath = Invoke-ComObject -ComObject $DirectoryMember -Property 'ADsPath'
                    $MemberDomainDn = $null
                    if ($DirectoryPath -match 'WinNT:\/\/(?<Domain>[^\/]*)\/(?<Acct>.*$)') {
                        Write-LogMsg @LogParams -Text " # '$DirectoryPath' has a domain of '$($Matches.Domain)' and an account name of '$($Matches.Acct)'"
                        $MemberName = $Matches.Acct
                        $MemberDomainNetbios = $Matches.Domain
                        $DomainCacheResult = $DomainsByNetbios[$MemberDomainNetbios]
                        if ($DomainCacheResult) {
                            Write-LogMsg @LogParams -Text " # Domain NetBIOS cache hit for '$MemberDomainNetBios'"
                            if ( "WinNT:\\$MemberDomainNetbios" -ne $SourceDomain ) {
                                $MemberDomainDn = $DomainCacheResult.DistinguishedName
                            }
                        } else {
                            Write-LogMsg @LogParams -Text " # Domain NetBIOS cache miss for '$MemberDomainNetBios'. Available keys: $($DomainsByNetBios.Keys -join ',')"
                        }
                        if ($DirectoryPath -match 'WinNT:\/\/(?<Domain>[^\/]*)\/(?<Middle>[^\/]*)\/(?<Acct>.*$)') {
                            Write-LogMsg @LogParams -Text " # '$DirectoryPath' is named '$($Matches.Acct)' and is on ADSI server '$($Matches.Middle)' joined to the domain '$($Matches.Domain)'"
                            if ($Matches.Middle -eq ($ThisDirEntry.Path | Split-Path -Parent | Split-Path -Leaf)) {
                                $MemberDomainDn = $null
                            }
                        }
                    } else {
                        Write-LogMsg @LogParams -Text " # '$DirectoryPath' does not match 'WinNT:\/\/(?<Domain>[^\/]*)\/(?<Acct>.*$)'"
                    }
                    if ($MemberDomainDn) {
                        Write-LogMsg @LogParams -Text " # '$MemberName' is a domain security principal"
                        $MembersToGet["LDAP://$MemberDomainDn"] += "(samaccountname=$MemberName)"
                    } else {
                        Write-LogMsg @LogParams -Text " # '$DirectoryPath' is a local security principal"
                        $MembersToGet['WinNTMembers'] += $DirectoryPath
                    }
                }
                ForEach ($ThisMember in $MembersToGet['WinNTMembers']) {
                    $MemberParams['DirectoryPath'] = $ThisMember
                    Write-LogMsg @LogParams -Text "Get-DirectoryEntry -DirectoryPath '$DirectoryPath'"
                    $MemberDirectoryEntry = Get-DirectoryEntry @MemberParams
                    Expand-WinNTGroupMember -DirectoryEntry $MemberDirectoryEntry -CimCache $CimCache -DirectoryEntryCache $DirectoryEntryCache -DomainsByFqdn $DomainsByFqdn -DomainsByNetbios $DomainsByNetbios -DomainsBySid $DomainsBySid -ThisFqdn $ThisFqdn @LoggingParams
                }
                $MembersToGet.Remove('WinNTMembers')
                $MembersToGet.Keys |
                ForEach-Object {
                    $MemberParams['DirectoryPath'] = $_
                    $MemberParams['Filter'] = "(|$($MembersToGet[$_]))"
                    $MemberDirectoryEntries = Search-Directory @MemberParams
                    Expand-WinNTGroupMember -DirectoryEntry $MemberDirectoryEntries -CimCache $CimCache -DirectoryEntryCache $DirectoryEntryCache -DomainsByFqdn $DomainsByFqdn -DomainsByNetbios $DomainsByNetbios -DomainsBySid $DomainsBySid -ThisFqdn $ThisFqdn @LoggingParams
                }
            } else {
                Write-LogMsg @LogParams -Text " # '$($ThisDirEntry.Path)' is not a group"
            }
        }
    }
}
function Invoke-ComObject {
    param (
        [Parameter(Mandatory)]
        $ComObject,
        [Parameter(Mandatory)]
        [String]$Property,
        $Value,
        [Switch]$Method
    )
    If ($Method) {
        $Invoke = "InvokeMethod"
    } ElseIf ($MyInvocation.BoundParameters.ContainsKey("Value")) {
        $Invoke = "SetProperty"
    } Else {
        $Invoke = "GetProperty"
    }
    [__ComObject].InvokeMember($Property, $Invoke, $Null, $ComObject, $Value)
}
function New-FakeDirectoryEntry {
    param (
        [string]$DirectoryPath
    )
    $LastSlashIndex = $DirectoryPath.LastIndexOf('/')
    $StartIndex = $LastSlashIndex + 1
    $Name = $DirectoryPath.Substring($StartIndex, $DirectoryPath.Length - $StartIndex)
    $Parent = $DirectoryPath.Substring(0, $LastSlashIndex)
    $Path = $DirectoryPath
    $SchemaEntry = [System.DirectoryServices.DirectoryEntry]
    switch -regex ($DirectoryPath) {
        'CREATOR OWNER$' {
            $objectSid = ConvertTo-SidByteArray -SidString 'S-1-3-0'
            $Description = 'A SID to be replaced by the SID of the user who creates a new object. This SID is used in inheritable ACEs.'
            $SchemaClassName = 'user'
        }
        'SYSTEM$' {
            $objectSid = ConvertTo-SidByteArray -SidString 'S-1-5-18'
            $Description = 'By default, the SYSTEM account is granted Full Control permissions to all files on an NTFS volume'
            $SchemaClassName = 'user'
        }
        'INTERACTIVE$' {
            $objectSid = ConvertTo-SidByteArray -SidString 'S-1-5-4'
            $Description = 'Users who log on for interactive operation. This is a group identifier added to the token of a process when it was logged on interactively.'
            $SchemaClassName = 'group'
        }
        'Authenticated Users$' {
            $objectSid = ConvertTo-SidByteArray -SidString 'S-1-5-11'
            $Description = 'Any user who accesses the system through a sign-in process has the Authenticated Users identity.'
            $SchemaClassName = 'group'
        }
        'TrustedInstaller$' {
            $objectSid = ConvertTo-SidByteArray -SidString 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464'
            $Description = 'Most of the operating system files are owned by the TrustedInstaller security identifier (SID)'
            $SchemaClassName = 'user'
        }
        'ALL APPLICATION PACKAGES$' {
            $objectSid = ConvertTo-SidByteArray -SidString 'S-1-15-2-1'
            $Description = 'All applications running in an app package context. SECURITY_BUILTIN_PACKAGE_ANY_PACKAGE'
            $SchemaClassName = 'group'
        }
        'ALL RESTRICTED APPLICATION PACKAGES$' {
            $objectSid = ConvertTo-SidByteArray -SidString 'S-1-15-2-2'
            $Description = 'SECURITY_BUILTIN_PACKAGE_ANY_RESTRICTED_PACKAGE'
            $SchemaClassName = 'group'
        }
        'Everyone$' {
            $objectSid = ConvertTo-SidByteArray -SidString 'S-1-1-0'
            $Description = "A group that includes all users; aka 'World'."
            $SchemaClassName = 'group'
        }
        'LOCAL SERVICE$' {
            $objectSid = ConvertTo-SidByteArray -SidString 'S-1-5-19'
            $Description = 'A local service account'
            $SchemaClassName = 'user'
        }
        'NETWORK SERVICE$' {
            $objectSid = ConvertTo-SidByteArray -SidString 'S-1-5-20'
            $Description = 'A network service account'
            $SchemaClassName = 'user'
        }
    }
    $Properties = @{
        Name            = $Name
        Description     = $Description
        objectSid       = $objectSid
        SchemaClassName = $SchemaClassName
    }
    $Object = [PSCustomObject]@{
        Name            = $Name
        Description     = $Description
        objectSid       = $objectSid
        SchemaClassName = $SchemaClassName
        Parent          = $Parent
        Path            = $Path
        SchemaEntry     = $SchemaEntry
        Properties      = $Properties
    }
    Add-Member -InputObject $Object -Name RefreshCache -MemberType ScriptMethod -Value {}
    Add-Member -InputObject $Object -Name Invoke -MemberType ScriptMethod -Value {}
    return $Object
}
function Resolve-IdentityReference {
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory)]
        [string]$IdentityReference,
        [PSObject]$AdsiServer,
        [hashtable]$DirectoryEntryCache = ([hashtable]::Synchronized(@{})),
        [hashtable]$AdsiServersByDns = [hashtable]::Synchronized(@{}),
        [hashtable]$DomainsByNetbios = ([hashtable]::Synchronized(@{})),
        [hashtable]$DomainsBySid = ([hashtable]::Synchronized(@{})),
        [hashtable]$DomainsByFqdn = ([hashtable]::Synchronized(@{})),
        [string]$ThisHostName = (HOSTNAME.EXE),
        [string]$ThisFqdn = ([System.Net.Dns]::GetHostByName((HOSTNAME.EXE)).HostName),
        [string]$WhoAmI = (whoami.EXE),
        [hashtable]$LogBuffer = ([hashtable]::Synchronized(@{})),
        [hashtable]$CimCache = ([hashtable]::Synchronized(@{})),
        [ValidateSet('Silent', 'Quiet', 'Success', 'Debug', 'Verbose', 'Output', 'Host', 'Warning', 'Error', 'Information', $null)]
        [string]$DebugOutputStream = 'Debug'
    )
    $LogParams = @{
        ThisHostname = $ThisHostname
        Type         = $DebugOutputStream
        Buffer       = $LogBuffer
        WhoAmI       = $WhoAmI
    }
    $LoggingParams = @{
        ThisHostname = $ThisHostname
        LogBuffer    = $LogBuffer
        WhoAmI       = $WhoAmI
    }
    $GetDirectoryEntryParams = @{
        DirectoryEntryCache = $DirectoryEntryCache
        DomainsByNetbios    = $DomainsByNetbios
        DomainsBySid        = $DomainsBySid
    }
    $ServerNetBIOS = $AdsiServer.Netbios
    $CacheResult = $CimCache[$ServerNetBIOS]['Win32_AccountBySID'][$IdentityReference]
    if ($CacheResult) {
        Write-LogMsg @LogParams -Text " # 'Win32_AccountBySID' cache hit for '$IdentityReference' on '$ServerNetBios'"
        return [PSCustomObject]@{
            IdentityReference        = $IdentityReference
            SIDString                = $CacheResult.SID
            IdentityReferenceNetBios = $CacheResult.Caption -replace "^$ThisHostname\\", "$ThisHostname\" 
            IdentityReferenceDns     = "$($AdsiServer.Dns)\$($CacheResult.Name)"
        }
    } else {
        Write-LogMsg @LogParams -Text " # 'Win32_AccountBySID' cache miss for '$IdentityReference' on '$ServerNetBIOS'"
    }
    $split = $IdentityReference.Split('\')
    $DomainNetBIOS = $ServerNetBIOS
    $Name = $split[1]
    if ($Name) {
        $CacheResult = $CimCache[$ServerNetBIOS]['Win32_AccountByCaption']["$ServerNetBIOS\$Name"]
        if ($CacheResult) {
            Write-LogMsg @LogParams -Text " # 'Win32_AccountByCaption' cache hit for '$ServerNetBIOS\$Name' on '$ServerNetBIOS'"
            if ($ServerNetBIOS -eq $CacheResult.Domain) {
                $DomainDns = $AdsiServer.Dns
            }
            if (-not $DomainDns) {
                $DomainCacheResult = $DomainsByNetbios[$CacheResult.Domain]
                if ($DomainCacheResult) {
                    Write-LogMsg @LogParams -Text " # Domain NetBIOS cache hit for '$($CacheResult.Domain)'"
                    $DomainDns = $DomainCacheResult.Dns
                } else {
                    Write-LogMsg @LogParams -Text " # Domain NetBIOS cache miss for '$($CacheResult.Domain)'"
                }
            }
            if (-not $DomainDns) {
                $DomainDns = ConvertTo-Fqdn -NetBIOS $DomainNetBIOS -CimCache $CimCache -DirectoryEntryCache $DirectoryEntryCache -DomainsByFqdn $DomainsByFqdn -DomainsByNetbios $DomainsByNetbios -DomainsBySid $DomainsBySid -ThisFqdn $ThisFqdn @LoggingParams
                $DomainDn = $DomainsByNetbios[$DomainNetBIOS].DistinguishedName
            }
            return [PSCustomObject]@{
                IdentityReference        = $IdentityReference
                SIDString                = $CacheResult.SID
                IdentityReferenceNetBios = $CacheResult.Caption -replace "^$ThisHostname\\", "$ThisHostname\" 
                IdentityReferenceDns     = "$DomainDns\$($CacheResult.Name)"
            }
        } else {
            Write-LogMsg @LogParams -Text " # 'Win32_AccountByCaption' cache miss for '$ServerNetBIOS\$Name' on '$ServerNetBIOS'"
        }
    }
    $CacheResult = $CimCache[$ServerNetBIOS]['Win32_AccountByCaption']["$ServerNetBIOS\$IdentityReference"]
    if ($CacheResult) {
        Write-LogMsg @LogParams -Text " # 'Win32_AccountByCaption' cache hit for '$ServerNetBIOS\$IdentityReference' on '$ServerNetBIOS'"
        return [PSCustomObject]@{
            IdentityReference        = $IdentityReference
            SIDString                = $CacheResult.SID
            IdentityReferenceNetBios = $CacheResult.Caption.Replace("$ThisHostname\", "$ThisHostname\") 
            IdentityReferenceDns     = "$($AdsiServer.Dns)\$($CacheResult.Name)"
        }
    } else {
        Write-LogMsg @LogParams -Text " # 'Win32_AccountByCaption' cache miss for '$ServerNetBIOS\$IdentityReference' on '$ServerNetBIOS'"
    }
    switch -Wildcard ($IdentityReference) {
        "S-1-*" {
            Write-LogMsg @LogParams -Text "[System.Security.Principal.SecurityIdentifier]::new('$IdentityReference').Translate([System.Security.Principal.NTAccount])"
            $SecurityIdentifier = [System.Security.Principal.SecurityIdentifier]::new($IdentityReference)
            $NTAccount = & { $SecurityIdentifier.Translate([System.Security.Principal.NTAccount]).Value } 2>$null
            Write-LogMsg @LogParams -Text " # Translated NTAccount name for '$IdentityReference' is '$NTAccount'"
            $DomainSid = $IdentityReference.Substring(0, $IdentityReference.LastIndexOf("-"))
            $DomainCacheResult = $DomainsBySID[$DomainSid]
            if ($DomainCacheResult) {
                Write-LogMsg @LogParams -Text " # Domain SID cache hit for '$DomainSid'"
            } else {
                Write-LogMsg @LogParams -Text " # Domain SID cache miss for '$DomainSid'"
                $split = $NTAccount -split '\\'
                $DomainFromSplit = $split[0]
                if (
                    $DomainFromSplit.Contains(' ') -or
                    $DomainFromSplit.Contains('BUILTIN\')
                ) {
                    $NameFromSplit = $split[1]
                    $DomainNetBIOS = $ServerNetBIOS
                    $Caption = "$ServerNetBIOS\$NameFromSplit"
                    $Win32Acct = [PSCustomObject]@{
                        SID     = $IdentityReference
                        Caption = $Caption
                        Domain  = $ServerNetBIOS
                        Name    = $NameFromSplit
                    }
                    Write-LogMsg @LogParams -Text " # Add '$Caption' to the 'Win32_AccountByCaption' cache for '$ServerNetBIOS'"
                    $CimCache[$ServerNetBIOS]['Win32_AccountByCaption'][$Caption] = $Win32Acct
                    Write-LogMsg @LogParams -Text " # Add '$IdentityReference' to the 'Win32_AccountBySID' cache for '$ServerNetBIOS'"
                    $CimCache[$ServerNetBIOS]['Win32_AccountBySID'][$IdentityReference] = $Win32Acct
                } else {
                    $DomainNetBIOS = $DomainFromSplit
                }
                $DomainCacheResult = $DomainsByNetbios[$split[0]]
            }
            if ($DomainCacheResult) {
                $DomainNetBIOS = $DomainCacheResult.Netbios
                $DomainDns = $DomainCacheResult.Dns
            } else {
                Write-LogMsg @LogParams -Text " # Domain SID '$DomainSid' is unknown. Domain NetBIOS is '$DomainNetBIOS'"
                $DomainDns = ConvertTo-Fqdn -NetBIOS $DomainNetBIOS -CimCache $CimCache -DirectoryEntryCache $DirectoryEntryCache -DomainsByFqdn $DomainsByFqdn -DomainsByNetbios $DomainsByNetbios -DomainsBySid $DomainsBySid -ThisFqdn $ThisFqdn @LoggingParams
            }
            $AdsiServer = Get-AdsiServer -Fqdn $DomainDns -CimCache $CimCache -DirectoryEntryCache $DirectoryEntryCache -DomainsByFqdn $DomainsByFqdn -DomainsByNetbios $DomainsByNetbios -DomainsBySid $DomainsBySid -ThisFqdn $ThisFqdn @LoggingParams
            if ($NTAccount) {
                $ResolveIdentityReferenceParams = @{
                    IdentityReference   = $NTAccount
                    AdsiServer          = $AdsiServer
                    AdsiServersByDns    = $AdsiServersByDns
                    DirectoryEntryCache = $DirectoryEntryCache
                    DomainsBySID        = $DomainsBySID
                    DomainsByNetbios    = $DomainsByNetbios
                    DomainsByFqdn       = $DomainsByFqdn
                    ThisHostName        = $ThisHostName
                    ThisFqdn            = $ThisFqdn
                    LogBuffer           = $LogBuffer
                    CimCache            = $CimCache
                    WhoAmI              = $WhoAmI
                }
                $Resolved = Resolve-IdentityReference @ResolveIdentityReferenceParams
            } else {
                $Resolved = [PSCustomObject]@{
                    IdentityReference        = $IdentityReference
                    SIDString                = $IdentityReference
                    IdentityReferenceNetBios = $CacheResult.Caption -replace "^$ThisHostname\\", "$ThisHostname\" 
                    IdentityReferenceDns     = "$DomainDns\$IdentityReference"
                }
            }
            return $Resolved
        }
        "NT SERVICE\*" {
            if ($ServerNetBIOS -eq $ThisHostName) {
                Write-LogMsg @LogParams -Text "sc.exe showsid $Name"
                [string[]]$ScResult = & sc.exe showsid $Name
            } else {
                Write-LogMsg @LogParams -Text "Invoke-Command -ComputerName $ServerNetBIOS -ScriptBlock { & sc.exe showsid `$args[0] } -ArgumentList $Name"
                [string[]]$ScResult = Invoke-Command -ComputerName $ServerNetBIOS -ScriptBlock { & sc.exe showsid $args[0] } -ArgumentList $Name
            }
            $ScResultProps = @{}
            $ScResult |
            ForEach-Object {
                $Prop, $Value = ($_ -split ':').Trim()
                $ScResultProps[$Prop] = $Value
            }
            $SIDString = $ScResultProps['SERVICE SID']
            $Caption = $IdentityReference.Replace('NT SERVICE', $ServerNetBIOS)
            $DomainCacheResult = $DomainsByNetbios[$ServerNetBIOS]
            if ($DomainCacheResult) {
                $DomainDns = $DomainCacheResult.Dns
            }
            if (-not $DomainDns) {
                $DomainDns = ConvertTo-Fqdn -NetBIOS $ServerNetBIOS -CimCache $CimCache -DirectoryEntryCache $DirectoryEntryCache -DomainsByFqdn $DomainsByFqdn -DomainsByNetbios $DomainsByNetbios -DomainsBySid $DomainsBySid -ThisFqdn $ThisFqdn @LoggingParams
            }
            $Win32Acct = [PSCustomObject]@{
                SID     = $SIDString
                Caption = $Caption
                Domain  = $ServerNetBIOS
                Name    = $Name
            }
            Write-LogMsg @LogParams -Text " # Add '$Caption' to the 'Win32_AccountByCaption' cache for '$ServerNetBIOS'"
            $CimCache[$ServerNetBIOS]['Win32_AccountByCaption'][$Caption] = $Win32Acct
            Write-LogMsg @LogParams -Text " # Add '$SIDString' to the 'Win32_AccountBySID' cache for '$ServerNetBIOS'"
            $CimCache[$ServerNetBIOS]['Win32_AccountBySID'][$SIDString] = $Win32Acct
            return [PSCustomObject]@{
                IdentityReference        = $IdentityReference
                SIDString                = $SIDString
                IdentityReferenceNetBios = $Caption
                IdentityReferenceDns     = "$DomainDns\$Name"
            }
        }
        "APPLICATION PACKAGE AUTHORITY\*" {
            $KnownSIDs = @{ 
                'APPLICATION PACKAGE AUTHORITY\ALL APPLICATION PACKAGES'                                                   = 'S-1-15-2-1'
                'APPLICATION PACKAGE AUTHORITY\ALL RESTRICTED APPLICATION PACKAGES'                                        = 'S-1-15-2-2'
                'APPLICATION PACKAGE AUTHORITY\Your Internet connection'                                                   = 'S-1-15-3-1'
                'APPLICATION PACKAGE AUTHORITY\Your Internet connection, including incoming connections from the Internet' = 'S-1-15-3-2'
                'APPLICATION PACKAGE AUTHORITY\Your home or work networks'                                                 = 'S-1-15-3-3'
                'APPLICATION PACKAGE AUTHORITY\Your pictures library'                                                      = 'S-1-15-3-4'
                'APPLICATION PACKAGE AUTHORITY\Your videos library'                                                        = 'S-1-15-3-5'
                'APPLICATION PACKAGE AUTHORITY\Your music library'                                                         = 'S-1-15-3-6'
                'APPLICATION PACKAGE AUTHORITY\Your documents library'                                                     = 'S-1-15-3-7'
                'APPLICATION PACKAGE AUTHORITY\Your Windows credentials'                                                   = 'S-1-15-3-8'
                'APPLICATION PACKAGE AUTHORITY\Software and hardware certificates or a smart card'                         = 'S-1-15-3-9'
                'APPLICATION PACKAGE AUTHORITY\Removable storage'                                                          = 'S-1-15-3-10'
                'APPLICATION PACKAGE AUTHORITY\Your Appointments'                                                          = 'S-1-15-3-11'
                'APPLICATION PACKAGE AUTHORITY\Your Contacts'                                                              = 'S-1-15-3-12'
            }
            $SIDString = $KnownSIDs[$IdentityReference]
            $Caption = $IdentityReference.Replace('APPLICATION PACKAGE AUTHORITY', $ServerNetBIOS)
            $DomainCacheResult = $DomainsByNetbios[$ServerNetBIOS]
            if ($DomainCacheResult) {
                $DomainDns = $DomainCacheResult.Dns
            }
            if (-not $DomainDns) {
                $DomainDns = ConvertTo-Fqdn -NetBIOS $ServerNetBIOS -CimCache $CimCache -DirectoryEntryCache $DirectoryEntryCache -DomainsByFqdn $DomainsByFqdn -DomainsByNetbios $DomainsByNetbios -DomainsBySid $DomainsBySid -ThisFqdn $ThisFqdn @LoggingParams
            }
            $Win32Acct = [PSCustomObject]@{
                SID     = $SIDString
                Caption = $Caption
                Domain  = $ServerNetBIOS
                Name    = $Name
            }
            Write-LogMsg @LogParams -Text " # Add '$Caption' to the 'Win32_AccountByCaption' cache for '$ServerNetBIOS'"
            $CimCache[$ServerNetBIOS]['Win32_AccountByCaption'][$Caption] = $Win32Acct
            Write-LogMsg @LogParams -Text " # Add '$SIDString' to the 'Win32_AccountBySID' cache for '$ServerNetBIOS'"
            $CimCache[$ServerNetBIOS]['Win32_AccountBySID'][$SIDString] = $Win32Acct
            return [PSCustomObject]@{
                IdentityReference        = $IdentityReference
                SIDString                = $SIDString
                IdentityReferenceNetBios = $Caption
                IdentityReferenceDns     = "$DomainDns\$Name"
            }
        }
        "BUILTIN\*" {
            $DirectoryPath = "$($AdsiServer.AdsiProvider)`://$ServerNetBIOS/$Name"
            $DirectoryEntry = Get-DirectoryEntry -DirectoryPath $DirectoryPath @GetDirectoryEntryParams @LoggingParams
            $SIDString = (Add-SidInfo -InputObject $DirectoryEntry -DomainsBySid $DomainsBySid @LoggingParams).SidString
            $Caption = $IdentityReference.Replace('BUILTIN', $ServerNetBIOS)
            $DomainDns = $AdsiServer.Dns
            $Win32Acct = [PSCustomObject]@{
                SID     = $SIDString
                Caption = $Caption
                Domain  = $ServerNetBIOS
                Name    = $Name
            }
            Write-LogMsg @LogParams -Text " # Add '$Caption' to the 'Win32_AccountByCaption' cache for '$ServerNetBIOS'"
            $CimCache[$ServerNetBIOS]['Win32_AccountByCaption'][$Caption] = $Win32Acct
            Write-LogMsg @LogParams -Text " # Add '$SIDString' to the 'Win32_AccountBySID' SID cache for '$ServerNetBIOS'"
            $CimCache[$ServerNetBIOS]['Win32_AccountBySID'][$SIDString] = $Win32Acct
            return [PSCustomObject]@{
                IdentityReference        = $IdentityReference
                SIDString                = $SIDString
                IdentityReferenceNetBios = $Caption
                IdentityReferenceDns     = "$DomainDns\$Name"
            }
        }
    }
    if (-not [string]::IsNullOrEmpty($DomainNetBIOS)) {
        $DomainNetBIOSCacheResult = $DomainsByNetbios[$DomainNetBIOS]
        if (-not $DomainNetBIOSCacheResult) {
            Write-LogMsg @LogParams -Text " # Domain NetBIOS cache miss for '$($DomainNetBIOS)'."
            $DomainNetBIOSCacheResult = Get-AdsiServer -Netbios $DomainNetBIOS -CimCache $CimCache -DirectoryEntryCache $DirectoryEntryCache -DomainsByFqdn $DomainsByFqdn -DomainsByNetbios $DomainsByNetbios -DomainsBySid $DomainsBySid -ThisFqdn $ThisFqdn @LoggingParams
            $DomainsByNetbios[$DomainNetBIOS] = $DomainNetBIOSCacheResult
        } else {
            Write-LogMsg @LogParams -Text " # Domain NetBIOS cache hit for '$($DomainNetBIOS)'."
        }
        $DomainDn = $DomainNetBIOSCacheResult.DistinguishedName
        $DomainDns = $DomainNetBIOSCacheResult.Dns
        Write-LogMsg @LogParams -Text "[System.Security.Principal.NTAccount]::new('$ServerNetBIOS', '$Name').Translate([System.Security.Principal.SecurityIdentifier])"
        $NTAccount = [System.Security.Principal.NTAccount]::new($ServerNetBIOS, $Name)
        $SIDString = & { $NTAccount.Translate([System.Security.Principal.SecurityIdentifier]) } 2>$null
        if (-not $SIDString) {
            Write-LogMsg @LogParams -Text "[System.Security.Principal.NTAccount]::new('$DomainNetBIOS', '$Name')"
            $NTAccount = [System.Security.Principal.NTAccount]::new($DomainNetBIOS, $Name)
            Write-LogMsg @LogParams -Text "[System.Security.Principal.NTAccount]::new('$DomainNetBIOS', '$Name').Translate([System.Security.Principal.SecurityIdentifier])"
            $SIDString = & { $NTAccount.Translate([System.Security.Principal.SecurityIdentifier]) } 2>$null
        } else {
            $DomainNetBIOS = $ServerNetBIOS
        }
        if (-not $SIDString) {
            try {
                $SearchPath = Add-DomainFqdnToLdapPath -DirectoryPath "LDAP://$DomainDn" -ThisFqdn $ThisFqdn -CimCache $CimCache @LoggingParams
                $SearchParams = @{
                    CimCache            = $CimCache
                    DebugOutputStream   = $DebugOutputStream
                    DirectoryEntryCache = $DirectoryEntryCache
                    DirectoryPath       = $SearchPath
                    DomainsByNetbios    = $DomainsByNetbios
                    Filter              = "(samaccountname=$Name)"
                    PropertiesToLoad    = @('objectClass', 'distinguishedName', 'name', 'grouptype', 'description', 'managedby', 'member', 'objectClass', 'Department', 'Title')
                    ThisFqdn            = $ThisFqdn
                }
                $DirectoryEntry = Search-Directory @SearchParams @LoggingParams
                $SIDString = (Add-SidInfo -InputObject $DirectoryEntry -DomainsBySid $DomainsBySid @LoggingParams).SidString
            } catch {
                $LogParams['Type'] = 'Warning' 
                Write-LogMsg @LogParams -Text "'$IdentityReference' could not be resolved against its directory. Error: $($_.Exception.Message)"
                $LogParams['Type'] = $DebugOutputStream
            }
        }
        if (-not $SIDString) {
            $DirectoryPath = "$($AdsiServer.AdsiProvider)`://$ServerNetBIOS/$Name"
            $DirectoryEntry = Get-DirectoryEntry -DirectoryPath $DirectoryPath @GetDirectoryEntryParams @LoggingParams
            $SIDString = (Add-SidInfo -InputObject $DirectoryEntry -DomainsBySid $DomainsBySid @LoggingParams).SidString
        }
        if ($SIDString) {
            $DomainNetBIOS = $ServerNetBIOS
        }
        if ( '' -eq "$Name" ) {
            $Name = $IdentityReference
            Write-LogMsg @LogParams -Text " # An IdentityReference girl has no name ($Name)"
        } else {
            Write-LogMsg @LogParams -Text " # '$IdentityReference' is named '$Name'"
        }
        return [PSCustomObject]@{
            IdentityReference        = $IdentityReference
            SIDString                = $SIDString
            IdentityReferenceNetBios = "$DomainNetBios\$Name" 
            IdentityReferenceDns     = "$DomainDns\$Name"
        }
    }
}
function Search-Directory {
    param (
        [string]$DirectoryPath = (([adsisearcher]'').SearchRoot.Path),
        [string]$Filter,
        [int]$PageSize = 1000,
        [string[]]$PropertiesToLoad,
        [pscredential]$Credential,
        [string]$SearchScope = 'subtree',
        [hashtable]$CimCache = ([hashtable]::Synchronized(@{})),
        [hashtable]$DirectoryEntryCache = ([hashtable]::Synchronized(@{})),
        [hashtable]$DomainsByNetbios = ([hashtable]::Synchronized(@{})),
        [string]$ThisFqdn = ([System.Net.Dns]::GetHostByName((HOSTNAME.EXE)).HostName),
        [string]$ThisHostName = (HOSTNAME.EXE),
        [string]$WhoAmI = (whoami.EXE),
        [hashtable]$LogBuffer = ([hashtable]::Synchronized(@{})),
        [ValidateSet('Silent', 'Quiet', 'Success', 'Debug', 'Verbose', 'Output', 'Host', 'Warning', 'Error', 'Information', $null)]
        [string]$DebugOutputStream = 'Debug'
    )
    $LogParams = @{
        ThisHostname = $ThisHostname
        Type         = $DebugOutputStream
        Buffer       = $LogBuffer
        WhoAmI       = $WhoAmI
    }
    $DirectoryEntryParameters = @{
        DirectoryEntryCache = $DirectoryEntryCache
        DomainsByNetbios    = $DomainsByNetbios
        ThisHostname        = $ThisHostname
        LogBuffer           = $LogBuffer
        WhoAmI              = $WhoAmI
        CimCache            = $CimCache
        ThisFqdn            = $ThisFqdn
    }
    if ($Credential) {
        $DirectoryEntryParameters['Credential'] = $Credential
    }
    if (($null -eq $DirectoryPath -or '' -eq $DirectoryPath)) {
        $CimParams = @{
            CimCache          = $CimCache
            ComputerName      = $ThisFqdn
            DebugOutputStream = $DebugOutputStream
            ThisFqdn          = $ThisFqdn
        }
        $LoggingParams = @{
            ThisHostname = $ThisHostname
            LogBuffer    = $LogBuffer
            WhoAmI       = $WhoAmI
        }
        $Workgroup = (Get-CachedCimInstance -ClassName 'Win32_ComputerSystem' -KeyProperty Name @CimParams @LoggingParams).Workgroup
        $DirectoryPath = "WinNT://$Workgroup/$ThisHostname"
    }
    $DirectoryEntryParameters['DirectoryPath'] = $DirectoryPath
    $DirectoryEntry = Get-DirectoryEntry @DirectoryEntryParameters
    Write-LogMsg @LogParams -Text "`$DirectorySearcher = [System.DirectoryServices.DirectorySearcher]::new(([System.DirectoryServices.DirectoryEntry]::new('$DirectoryPath')))"
    $DirectorySearcher = [System.DirectoryServices.DirectorySearcher]::new($DirectoryEntry)
    if ($Filter) {
        Write-LogMsg @LogParams -Text "`$DirectorySearcher.Filter = '$Filter'"
        $DirectorySearcher.Filter = $Filter
    }
    Write-LogMsg @LogParams -Text "`$DirectorySearcher.PageSize = '$PageSize'"
    $DirectorySearcher.PageSize = $PageSize
    Write-LogMsg @LogParams -Text "`$DirectorySearcher.SearchScope = '$SearchScope'"
    $DirectorySearcher.SearchScope = $SearchScope
    ForEach ($Property in $PropertiesToLoad) {
        Write-LogMsg @LogParams -Text "`$DirectorySearcher.PropertiesToLoad.Add('$Property')"
        $null = $DirectorySearcher.PropertiesToLoad.Add($Property)
    }
    Write-LogMsg @LogParams -Text "`$DirectorySearcher.FindAll()"
    $SearchResultCollection = $DirectorySearcher.FindAll()
    $Output = [System.DirectoryServices.SearchResult[]]::new($SearchResultCollection.Count)
    $SearchResultCollection.CopyTo($Output, 0)
    return $Output
}
function ConvertTo-ClassExclusionDiv {
    param (
        [string[]]$ExcludeClass
    )
    if ($ExcludeClass) {
        $ListGroup = $ExcludeClass |
        ConvertTo-HtmlList |
        ConvertTo-BootstrapListGroup
        $Content = "Accounts whose objectClass property is in this list were excluded from the report.$ListGroup"
    } else {
        $Content = 'No accounts were excluded based on objectClass.'
    }
    Write-LogMsg @LogParams -Text "New-BootstrapDivWithHeading -HeadingText 'Accounts Excluded by Class' -Content `$Content"
    return New-BootstrapDivWithHeading -HeadingText 'Accounts Excluded by Class' -Content $Content -HeadingLevel 6
}
function ConvertTo-FileList {
    param (
        [string[]]$Format,
        $OutputDir,
        [cultureinfo]$Culture = (Get-Culture),
        [int[]]$Detail = @(0..10),
        [String]$FileName
    )
    $FileList = @{}
    ForEach ($ThisFormat in $Format) {
        $DetailStrings = @(
            'Target paths',
            'Network paths (target path servers and DFS targets resolved)',
            'Item paths (network paths expanded into their children)',
            'Access lists',
            'Access rules (resolved identity references and inheritance flags)',
            'Accounts with access',
            'Expanded access rules (expanded with account info)', 
            'Formatted permissions',
            'Best Practice issues',
            'Custom sensor output for Paessler PRTG Network Monitor'
            'Permission report'
        )
        $FileList[$ThisFormat] = switch ($ThisFormat) {
            'csv' {
                $Suffix = '.csv'
                ForEach ($Level in $Detail) {
                    if ($Detail -lt 8) {
                        $ShortDetail = $DetailStrings[$Level] -replace '\([^\)]*\)', ''
                        $TitleCaseDetail = $Culture.TextInfo.ToTitleCase($ShortDetail)
                        $SpacelessDetail = $TitleCaseDetail -replace '\s', ''
                        "$OutputDir\$Level`_$SpacelessDetail$Suffix"
                    }
                }
                break
            }
            'html' {
                $Suffix = "_$FileName.htm"
                ForEach ($Level in $Detail) {
                    if ($Level -notin 8, 9) {
                        $ShortDetail = $DetailStrings[$Level] -replace '\([^\)]*\)', ''
                        $TitleCaseDetail = $Culture.TextInfo.ToTitleCase($ShortDetail)
                        $SpacelessDetail = $TitleCaseDetail -replace '\s', ''
                        "$OutputDir\$Level`_$SpacelessDetail$Suffix"
                    }
                }
                break
            }
            'js' {
                $Suffix = "_js_$FileName.htm"
                ForEach ($Level in $Detail) {
                    if ($Level -notin 8, 9) {
                        $ShortDetail = $DetailStrings[$Level] -replace '\([^\)]*\)', ''
                        $TitleCaseDetail = $Culture.TextInfo.ToTitleCase($ShortDetail)
                        $SpacelessDetail = $TitleCaseDetail -replace '\s', ''
                        "$OutputDir\$Level`_$SpacelessDetail$Suffix"
                    }
                }
                break
            }
            'prtgxml' {
                $Suffix = '.xml'
                $Level = 9
                if ($Detail -contains $Level) {
                    $ShortDetail = $DetailStrings[$Level] -replace '\([^\)]*\)', ''
                    $TitleCaseDetail = $Culture.TextInfo.ToTitleCase($ShortDetail)
                    $SpacelessDetail = $TitleCaseDetail -replace '\s', ''
                    "$OutputDir\$Level`_$SpacelessDetail$Suffix"
                }
                break
            }
            'json' {
                $Suffix = "_$FileName.json"
                break
            }
            'xml' {
                $Suffix = '.xml'
                break
            }
        }
    }
    return $FileList
}
function ConvertTo-FileListDiv {
    param (
        [Hashtable]$FileList
    )
    ForEach ($Format in ($FileList.Keys | Sort-Object)) {
        $Files = $FileList[$Format]
        if ($Files) {
            New-BootstrapAlert -Text $Format -Class Dark -Padding ' p-2 mb-0 mt-2'
            $Files |
            Sort-Object |
            Split-Path -Leaf |
            ConvertTo-HtmlList |
            ConvertTo-BootstrapListGroup
        }
    }
}
function ConvertTo-IgnoredDomainDiv {
    param (
        [string[]]$IgnoreDomain
    )
    if ($IgnoreDomain) {
        $ListGroup = $IgnoreDomain |
        ConvertTo-HtmlList |
        ConvertTo-BootstrapListGroup
        $Content = "Accounts from these domains are listed in the report without their domain.$ListGroup"
    } else {
        $Content = 'No domains were ignored.  All accounts have their domain listed.'
    }
    Write-LogMsg @LogParams -Text "New-BootstrapDivWithHeading -HeadingText 'Domains Ignored by Name' -Content `$Content"
    return New-BootstrapDivWithHeading -HeadingText 'Domains Ignored by Name' -Content $Content -HeadingLevel 6
}
function ConvertTo-MemberExclusionDiv {
    param (
        [switch]$NoMembers
    )
    if ($NoMembers) {
        $Content = 'Group members were excluded from the report.<br />Only accounts directly from the ACLs are included in the report.'
    } else {
        $Content = 'No accounts were excluded based on group membership.<br />Members of groups from the ACLs are included in the report.'
    }
    Write-LogMsg @LogParams -Text "New-BootstrapDivWithHeading -HeadingText 'Group Members' -Content '$Content'"
    return New-BootstrapDivWithHeading -HeadingText 'Group Members' -Content $Content -HeadingLevel 6
}
function ConvertTo-NameExclusionDiv {
    param (
        [string[]]$ExcludeAccount
    )
    if ($ExcludeAccount) {
        $ListGroup = $ExcludeAccount |
        ConvertTo-HtmlList |
        ConvertTo-BootstrapListGroup
        $Content = "Accounts whose names match these regular expressions were excluded from the report.$ListGroup"
    } else {
        $Content = 'No accounts were excluded based on name.'
    }
    Write-LogMsg @LogParams -Text "New-BootstrapDivWithHeading -HeadingText 'Accounts Excluded by Name' -Content `$Content"
    return New-BootstrapDivWithHeading -HeadingText 'Accounts Excluded by Name' -Content $Content -HeadingLevel 6
}
function ConvertTo-PermissionGroup {
    [CmdletBinding()]
    param (
        [PSCustomObject[]]$Permission,
        [ValidateSet('csv', 'html', 'js', 'json', 'prtgxml', 'xml')]
        [String]$Format,
        [ValidateSet('account', 'item', 'none', 'target')]
        [String]$GroupBy = 'item',
        [string[]]$AccountProperty = @('Account', 'Name', 'DisplayName', 'Description', 'Department', 'Title'),
        [string[]]$ItemProperty = @('Folder', 'Inheritance'),
        [Hashtable]$HowToSplit
    )
    $OutputObject = @{}
    if (
        $GroupBy -eq 'none' -or
        $HowToSplit[$GroupBy]
    ) {
        return
    }
    switch ($Format) {
        'csv' {
            $OutputObject['Data'] = $Permission | ConvertTo-Csv
            break
        }
        'html' {
            $Html = $Permission | ConvertTo-Html -Fragment
            $OutputObject['Data'] = $Html
            $OutputObject['Table'] = $Html | New-BootstrapTable
            break
        }
        'js' {
            $JavaScriptTable = @{
                ID = 'Folders'
            }
            switch ($GroupBy) {
                'account' {
                    $OrderedProperties = $AccountProperty
                    $JavaScriptTable['SearchableColumn'] = $OrderedProperties
                    break
                }
                'item' {
                    $OrderedProperties = $ItemProperty
                    $JavaScriptTable['SearchableColumn'] = 'Folder'
                    $JavaScriptTable['DropdownColumn'] = 'Inheritance'
                    break
                }
            }
            $OutputObject['Data'] = ConvertTo-Json -Compress -InputObject @($Permission)
            $OutputObject['Columns'] = Get-ColumnJson -InputObject $Permission -PropNames $OrderedProperties
            $OutputObject['Table'] = ConvertTo-BootstrapJavaScriptTable -InputObject $Permission -PropNames $OrderedProperties -DataFilterControl -PageSize 25 @JavaScriptTable
            break
        }
        'xml' {
            $OutputObject['Data'] = ($Permission | ConvertTo-Xml).InnerXml
            break
        }
        default {}
    }
    return [PSCustomObject]$OutputObject
}
function ConvertTo-PermissionList {
    param (
        [Hashtable]$Permission,
        [PSCustomObject[]]$PermissionGrouping,
        [ValidateSet('csv', 'html', 'js', 'json', 'prtgxml', 'xml')]
        [String]$Format,
        [String]$ShortestPath,
        [String]$NetworkPath,
        [ValidateSet('account', 'item', 'none', 'target')]
        [String]$GroupBy = 'item',
        [Hashtable]$HowToSplit,
        [PSCustomObject]$Analysis
    )
    switch ($Format) {
        'csv' {
            if (
                $GroupBy -eq 'none' -or
                $HowToSplit[$GroupBy]
            ) {
                $Sorted = $Permission.Values | Sort-Object -Property Item, Account
                [PSCustomObject]@{
                    PSTypeName = 'Permission.PermissionList'
                    Data       = $Sorted | ConvertTo-Csv
                    PassThru   = $Sorted
                }
            } else {
                switch ($GroupBy) {
                    'account' {
                        ForEach ($Group in $PermissionGrouping) {
                            [PSCustomObject]@{
                                PSTypeName = 'Permission.PermissionList'
                                Data       = $Permission[$Group.Account.ResolvedAccountName] | ConvertTo-Csv
                                PassThru   = $Permission[$Group.Account.ResolvedAccountName]
                                Grouping   = $Group.Account.ResolvedAccountName
                            }
                        }
                        break
                    }
                    'item' {
                        ForEach ($Group in $PermissionGrouping) {
                            [PSCustomObject]@{
                                PSTypeName = 'Permission.PermissionList'
                                Data       = $Permission[$Group.Item.Path] | ConvertTo-Csv
                                PassThru   = $Permission[$Group.Item.Path]
                                Grouping   = $Group.Item.Path
                            }
                        }
                        break
                    }
                    'target' {
                        ForEach ($Group in $PermissionGrouping) {
                            $Perm = $Permission[$Group.Path]
                            if ($Perm) {
                                [PSCustomObject]@{
                                    PSTypeName = 'Permission.PermissionList'
                                    Data       = $Perm | ConvertTo-Csv
                                    Grouping   = $Group.Path
                                    PassThru   = $Perm
                                }
                            }
                        }
                        break
                    }
                }
            }
            break
        }
        'html' {
            if (
                $GroupBy -eq 'none' -or
                $HowToSplit[$GroupBy]
            ) {
                $Heading = New-HtmlHeading "Permissions in $NetworkPath" -Level 6
                $Sorted = $Permission.Values | Sort-Object -Property Item, Account
                $Html = $Sorted | ConvertTo-Html -Fragment
                $Table = $Html | New-BootstrapTable
                [PSCustomObject]@{
                    PSTypeName = 'Permission.PermissionList'
                    Data       = $Html
                    Div        = New-BootstrapDiv -Text ($Heading + $Table) -Class 'h-100 p-1 bg-light border rounded-3 table-responsive'
                    PassThru   = $Sorted
                }
            } else {
                switch ($GroupBy) {
                    'account' {
                        ForEach ($GroupID in $Permission.Keys) {
                            $Heading = New-HtmlHeading "Folders accessible to $GroupID" -Level 6
                            $StartingPermissions = $Permission[$GroupID]
                            $Html = $StartingPermissions | ConvertTo-Html -Fragment
                            $Table = $Html | New-BootstrapTable
                            [PSCustomObject]@{
                                PSTypeName = 'Permission.PermissionList'
                                Data       = $Html
                                Div        = New-BootstrapDiv -Text ($Heading + $Table) -Class 'h-100 p-1 bg-light border rounded-3 table-responsive'
                                Grouping   = $GroupID
                                PassThru   = $StartingPermissions
                            }
                        }
                        break
                    }
                    'item' {
                        ForEach ($Group in $PermissionGrouping) {
                            $GroupID = $Group.Item.Path
                            $Heading = New-HtmlHeading "Accounts with access to $GroupID" -Level 6
                            $SubHeading = Get-FolderPermissionTableHeader -Group $Group -GroupID $GroupID -ShortestFolderPath $ShortestPath
                            $StartingPermissions = $Permission[$GroupID]
                            $Html = $StartingPermissions | ConvertTo-Html -Fragment
                            $Table = $Html | New-BootstrapTable
                            [PSCustomObject]@{
                                PSTypeName = 'Permission.PermissionList'
                                Data       = $Html
                                Div        = New-BootstrapDiv -Text ($Heading + $SubHeading + $Table) -Class 'h-100 p-1 bg-light border rounded-3 table-responsive'
                                Grouping   = $GroupID
                                PassThru   = $StartingPermissions
                            }
                        }
                        break
                    }
                    'target' {
                        ForEach ($Group in $PermissionGrouping) {
                            $GroupID = $Group.Path
                            $Heading = New-HtmlHeading "Permissions in $GroupID" -Level 5
                            $StartingPermissions = $Permission[$GroupID]
                            $Html = $StartingPermissions | ConvertTo-Html -Fragment
                            $Table = $Html | New-BootstrapTable
                            [PSCustomObject]@{
                                PSTypeName = 'Permission.PermissionList'
                                Data       = $Html
                                Div        = New-BootstrapDiv -Text ($Heading + $Table) -Class 'h-100 p-1 bg-light border rounded-3 table-responsive'
                                Grouping   = $GroupID
                                PassThru   = $StartingPermissions
                            }
                        }
                        break
                    }
                }
            }
            break
        }
        'js' {
            if (
                $GroupBy -eq 'none' -or
                $HowToSplit[$GroupBy]
            ) {
                $Heading = New-HtmlHeading "Permissions in $NetworkPath" -Level 6
                $StartingPermissions = $Permission.Values | Sort-Object -Property Item, Account
                $ObjectsForJsonData = ForEach ($Obj in $StartingPermissions) {
                    [PSCustomObject]@{
                        Item              = $Obj.Item
                        Account           = $Obj.Account
                        Access            = $Obj.Access
                        DuetoMembershipIn = $Obj.'Due to Membership In'
                        SourceofAccess    = $Obj.'Source of Access'
                        Name              = $Obj.Name
                        Department        = $Obj.Department
                        Title             = $Obj.Title
                    }
                }
                $TableId = 'Perms'
                $Table = ConvertTo-BootstrapJavaScriptTable -Id $TableId -InputObject $StartingPermissions -DataFilterControl -AllColumnsSearchable -PageSize 25
                [PSCustomObject]@{
                    PSTypeName = 'Permission.PermissionList'
                    Columns    = Get-ColumnJson -InputObject $StartingPermissions -PropNames Item, Account, Access, 'Due to Membership In', 'Source of Access', Name, Department, Title
                    Data       = ConvertTo-Json -Compress -InputObject @($ObjectsForJsonData)
                    Div        = New-BootstrapDiv -Text ($Heading + $Table) -Class 'h-100 p-1 bg-light border rounded-3 table-responsive'
                    PassThru   = $ObjectsForJsonData
                    Table      = $TableId
                }
            } else {
                switch ($GroupBy) {
                    'account' {
                        ForEach ($GroupID in $Permission.Keys) {
                            $Heading = New-HtmlHeading "Items accessible to $GroupID" -Level 6
                            $StartingPermissions = $Permission[$GroupID]
                            $ObjectsForJsonData = ForEach ($Obj in $StartingPermissions) {
                                [PSCustomObject]@{
                                    Path              = $Obj.Path
                                    Access            = $Obj.Access
                                    DuetoMembershipIn = $Obj.'Due to Membership In'
                                    SourceofAccess    = $Obj.'Source of Access'
                                }
                            }
                            $TableId = "Perms_$($GroupID -replace '[^A-Za-z0-9\-_]', '-')"
                            $Table = ConvertTo-BootstrapJavaScriptTable -Id $TableId -InputObject $StartingPermissions -DataFilterControl -AllColumnsSearchable
                            [PSCustomObject]@{
                                PSTypeName = 'Permission.AccountPermissionList'
                                Columns    = Get-ColumnJson -InputObject $StartingPermissions-PropNames Path, Access, 'Due to Membership In', 'Source of Access'
                                Data       = ConvertTo-Json -Compress -InputObject @($ObjectsForJsonData)
                                Div        = New-BootstrapDiv -Text ($Heading + $Table) -Class 'h-100 p-1 bg-light border rounded-3 table-responsive'
                                PassThru   = $ObjectsForJsonData
                                Grouping   = $GroupID
                                Table      = $TableId
                            }
                        }
                        break
                    }
                    'item' {
                        ForEach ($Group in $PermissionGrouping) {
                            $GroupID = $Group.Item.Path
                            $Heading = New-HtmlHeading "Accounts with access to $GroupID" -Level 6
                            $SubHeading = Get-FolderPermissionTableHeader -Group $Group -GroupID $GroupID -ShortestFolderPath $ShortestPath
                            $StartingPermissions = $Permission[$GroupID]
                            if ($StartingPermissions) {
                                $ObjectsForJsonData = ForEach ($Obj in $StartingPermissions) {
                                    [PSCustomObject]@{
                                        Account           = $Obj.Account
                                        Access            = $Obj.Access
                                        DuetoMembershipIn = $Obj.'Due to Membership In'
                                        SourceofAccess    = $Obj.'Source of Access'
                                        Name              = $Obj.Name
                                        Department        = $Obj.Department
                                        Title             = $Obj.Title
                                    }
                                }
                                $TableId = "Perms_$($GroupID -replace '[^A-Za-z0-9\-_]', '-')"
                                $Table = ConvertTo-BootstrapJavaScriptTable -Id $TableId -InputObject $StartingPermissions -DataFilterControl -AllColumnsSearchable
                                [PSCustomObject]@{
                                    PSTypeName = 'Permission.ItemPermissionList'
                                    Columns    = Get-ColumnJson -InputObject $StartingPermissions -PropNames Account, Access, 'Due to Membership In', 'Source of Access', Name, Department, Title
                                    Data       = ConvertTo-Json -Compress -InputObject @($ObjectsForJsonData)
                                    Div        = New-BootstrapDiv -Text ($Heading + $SubHeading + $Table) -Class 'h-100 p-1 bg-light border rounded-3 table-responsive'
                                    Grouping   = $GroupID
                                    PassThru   = $ObjectsForJsonData
                                    Table      = $TableId
                                }
                            }
                        }
                        break
                    }
                    'target' {
                        ForEach ($Group in $PermissionGrouping) {
                            $GroupID = $Group.Path
                            $Heading = New-HtmlHeading "Permissions in $GroupID" -Level 5
                            $StartingPermissions = $Permission[$GroupID]
                            $ObjectsForJsonData = ForEach ($Obj in $StartingPermissions) {
                                [PSCustomObject]@{
                                    Item              = $Obj.Item
                                    Account           = $Obj.Account
                                    Access            = $Obj.Access
                                    DuetoMembershipIn = $Obj.'Due to Membership In'
                                    SourceofAccess    = $Obj.'Source of Access'
                                    Name              = $Obj.Name
                                    Department        = $Obj.Department
                                    Title             = $Obj.Title
                                }
                            }
                            $TableId = "Perms_$($GroupID -replace '[^A-Za-z0-9\-_]', '-')"
                            $Table = ConvertTo-BootstrapJavaScriptTable -Id $TableId -InputObject $StartingPermissions -DataFilterControl -AllColumnsSearchable -PageSize 25
                            [PSCustomObject]@{
                                PSTypeName = 'Permission.TargetPermissionList'
                                Columns    = Get-ColumnJson -InputObject $StartingPermissions -PropNames Item, Account, Access, 'Due to Membership In', 'Source of Access', Name, Department, Title
                                Data       = ConvertTo-Json -Compress -InputObject @($ObjectsForJsonData)
                                Div        = New-BootstrapDiv -Text ($Heading + $Table) -Class 'h-100 p-1 bg-light border rounded-3 table-responsive'
                                Grouping   = $GroupID
                                PassThru   = $ObjectsForJsonData
                                Table      = $TableId
                            }
                        }
                        break
                    }
                }
            }
            break
        }
        'prtgxml' {
            [PSCustomObject]@{
                PSTypeName = 'Permission.BestPracticeAnalysisPrtg'
                Data       = ConvertTo-PermissionPrtgXml -Analysis $Analysis
                PassThru   = $Analysis
            }
            break
        }
        'xml' {
            if (
                $GroupBy -eq 'none' -or
                $HowToSplit[$GroupBy]
            ) {
                [PSCustomObject]@{
                    PSTypeName = 'Permission.PermissionList'
                    Data       = ($Permission.Values | ConvertTo-Xml).InnerXml
                    PassThru   = $Permission.Values
                }
            } else {
                switch ($GroupBy) {
                    'account' {
                        ForEach ($Group in $PermissionGrouping) {
                            [PSCustomObject]@{
                                PSTypeName = 'Permission.AccountPermissionList'
                                Data       = ($Permission[$Group.Account.ResolvedAccountName] | ConvertTo-Xml).InnerXml
                                PassThru   = $Permission[$Account.ResolvedAccountName]
                                Grouping   = $Account.ResolvedAccountName
                            }
                        }
                        break
                    }
                    'item' {
                        ForEach ($Group in $PermissionGrouping) {
                            [PSCustomObject]@{
                                PSTypeName = 'Permission.ItemPermissionList'
                                Data       = ($Permission[$Group.Item.Path] | ConvertTo-Xml).InnerXml
                                PassThru   = $Permission[$Group.Item.Path]
                                Grouping   = $Group.Item.Path
                            }
                        }
                        break
                    }
                    'target' {
                        ForEach ($Group in $PermissionGrouping) {
                            [PSCustomObject]@{
                                PSTypeName = 'Permission.TargetPermissionList'
                                Data       = ($Permission[$Group.Path] | ConvertTo-Xml).InnerXml
                                PassThru   = $Permission[$Group.Path]
                                Grouping   = $Group.Path
                            }
                        }
                        break
                    }
                }
            }
            break
        }
    }
}
function ConvertTo-PermissionPrtgXml {
    param (
        [PSCustomObject]$Analysis
    )
    $IssuesDetected = $false
    $ItemsWithCreatorOwner = $Analysis.ACEsWithCreatorOwner.Path | Sort-Object -Unique
    $CountItemsWithBrokenInheritance = $Analysis.ItemsWithBrokenInheritance.Count
    $CountACEsWithNonCompliantAccounts = $Analysis.ACEsWithNonCompliantAccounts.Count
    $CountACEsWithUsers = $Analysis.ACEsWithUsers.Count
    $CountACEsWithUnresolvedSIDs = $Analysis.ACEsWithUnresolvedSIDs.Count
    $CountItemsWithCreatorOwner = $ItemsWithCreatorOwner.Count
    if (
        (
            $CountItemsWithBrokenInheritance +
            $CountACEsWithNonCompliantAccounts +
            $CountACEsWithUsers +
            $CountACEsWithUnresolvedSIDs +
            $CountItemsWithCreatorOwner
        ) -gt 0
    ) {
        $IssuesDetected = $true
    }
    $Channels = [System.Collections.Generic.List[String]]::new()
    $ChannelParams = @{
        MaxError   = 0.5
        Channel    = 'Folders with inheritance disabled'
        Value      = $CountItemsWithBrokenInheritance
        CustomUnit = 'folders'
    }
    $null = $Channels.Add((Format-PrtgXmlResult @ChannelParams))
    $ChannelParams = @{
        MaxError   = 0.5
        Channel    = 'ACEs for groups breaking naming convention'
        Value      = $CountACEsWithNonCompliantAccounts
        CustomUnit = 'ACEs'
    }
    $null = $Channels.Add((Format-PrtgXmlResult @ChannelParams))
    $ChannelParams = @{
        MaxError   = 0.5
        Channel    = 'ACEs for users instead of groups'
        Value      = $CountACEsWithUsers
        CustomUnit = 'ACEs'
    }
    $null = $Channels.Add((Format-PrtgXmlResult @ChannelParams))
    $ChannelParams = @{
        MaxError   = 0.5
        Channel    = 'ACEs for unresolvable SIDs'
        Value      = $CountACEsWithUnresolvedSIDs
        CustomUnit = 'ACEs'
    }
    $null = $Channels.Add((Format-PrtgXmlResult @ChannelParams))
    $ChannelParams = @{
        MaxError   = 0.5
        Channel    = "Folders with 'CREATOR OWNER' access"
        Value      = $CountItemsWithCreatorOwner
        CustomUnit = 'folders'
    }
    $null = $Channels.Add((Format-PrtgXmlResult @ChannelParams))
    Format-PrtgXmlSensorOutput -PrtgXmlResult $Channels -IssueDetected:$IssuesDetected
}
function ConvertTo-ScriptHtml {
    param (
        $Permission,
        $PermissionGrouping,
        [String]$GroupBy,
        [String]$Split
    )
    $ScriptHtmlBuilder = [System.Text.StringBuilder]::new()
    ForEach ($Group in $Permission) {
        $null = $ScriptHtmlBuilder.AppendLine((ConvertTo-BootstrapTableScript -TableId "#$($Group.Table)" -ColumnJson $Group.Columns -DataJson $Group.Data))
    }
    if ($GroupBy -ne 'none' -and $GroupBy -ne $Split) {
        $null = $ScriptHtmlBuilder.AppendLine((ConvertTo-BootstrapTableScript -TableId '#Folders' -ColumnJson $PermissionGrouping.Columns -DataJson $PermissionGrouping.Data))
    }
    return $ScriptHtmlBuilder.ToString()
}
function Expand-AccountPermissionReference {
    param (
        $Reference,
        $PrincipalsByResolvedID,
        $ACEsByGUID
    )
    ForEach ($Account in $Reference) {
        $Access = ForEach ($PermissionRef in $Account.Access) {
            [PSCustomObject]@{
                Path       = $PermissionRef.Path
                PSTypeName = 'Permission.AccountPermissionItemAccess'
                Access     = ForEach ($ACE in $ACEsByGUID[$PermissionRef.AceGUIDs]) {
                    $ACE
                }
            }
        }
        [PSCustomObject]@{
            Account     = $PrincipalsByResolvedID[$Account.Account]
            AccountName = $Account.Account
            Access      = $Access
            PSTypeName  = 'Permission.AccountPermission'
        }
    }
}
function Expand-FlatPermissionReference {
    param (
        $SortedPath,
        $PrincipalsByResolvedID,
        $ACEsByGUID,
        $AceGUIDsByPath
    )
    ForEach ($Item in $SortedPath) {
        $AceGUIDs = $AceGUIDsByPath[$Item]
        if (-not $AceGUIDs) { continue }
        ForEach ($ACE in $ACEsByGUID[$AceGUIDs]) {
            Merge-AceAndPrincipal -ACE $ACE -Principal $PrincipalsByResolvedID[$ACE.IdentityReferenceResolved] -PrincipalByResolvedID $PrincipalsByResolvedID
        }
    }
}
function Expand-ItemPermissionAccountAccessReference {
    param (
        $Reference,
        [Hashtable]$PrincipalByResolvedID,
        [Hashtable]$AceByGUID
    )
    ForEach ($PermissionRef in $Reference) {
        [PSCustomObject]@{
            Account     = $PrincipalByResolvedID[$PermissionRef.Account]
            AccountName = $PermissionRef.Account
            Access      = ForEach ($GuidList in $PermissionRef.AceGUIDs) {
                ForEach ($Guid in $GuidList) {
                    $AceByGUID[$Guid]
                }
            }
            PSTypeName  = 'Permission.ItemPermissionAccountAccess'
        }
    }
}
function Expand-ItemPermissionReference {
    param (
        $Reference,
        $PrincipalsByResolvedID,
        $ACEsByGUID,
        $ACLsByPath
    )
    ForEach ($Item in $Reference) {
        [PSCustomObject]@{
            Item       = $ACLsByPath[$Item.Path]
            Access     = Expand-ItemPermissionAccountAccessReference -Reference $Item.Access -AceByGUID $ACEsByGUID -PrincipalByResolvedID $PrincipalsByResolvedID
            PSTypeName = 'Permission.ItemPermission'
        }
    }
}
function Expand-TargetPermissionReference {
    param (
        $Reference,
        $PrincipalsByResolvedID,
        $ACEsByGUID,
        $ACLsByPath,
        [Hashtable]$AceGuidByPath,
        [ValidateSet('account', 'item', 'none', 'target')]
        [String]$GroupBy = 'item'
    )
    switch ($GroupBy) {
        'account' {
            ForEach ($Target in $Reference) {
                $TargetProperties = @{
                    PSTypeName = 'Permission.TargetPermission'
                    Path       = $Target.Path
                }
                $TargetProperties['NetworkPaths'] = ForEach ($NetworkPath in $Target.NetworkPaths) {
                    [pscustomobject]@{
                        Item       = $AclsByPath[$NetworkPath.Path]
                        PSTypeName = 'Permission.ParentItemPermission'
                        Accounts   = Expand-AccountPermissionReference -Reference $NetworkPath.Accounts -ACEsByGUID $ACEsByGUID -PrincipalsByResolvedID $PrincipalsByResolvedID
                    }
                }
                [pscustomobject]$TargetProperties
            }
            break
        }
        'item' {
            ForEach ($Target in $Reference) {
                $TargetProperties = @{
                    Path = $Target.Path
                }
                $TargetProperties['NetworkPaths'] = ForEach ($NetworkPath in $Target.NetworkPaths) {
                    [pscustomobject]@{
                        Access = Expand-ItemPermissionAccountAccessReference -Reference $NetworkPath.Access -AceByGUID $ACEsByGUID -PrincipalByResolvedID $PrincipalsByResolvedID
                        Item   = $AclsByPath[$NetworkPath.Path]
                        Items  = ForEach ($TargetChild in $NetworkPath.Items) {
                            $Access = Expand-ItemPermissionAccountAccessReference -Reference $TargetChild.Access -AceByGUID $ACEsByGUID -PrincipalByResolvedID $PrincipalsByResolvedID
                            if ($Access) {
                                [pscustomobject]@{
                                    Access     = $Access
                                    Item       = $AclsByPath[$TargetChild.Path]
                                    PSTypeName = 'Permission.ChildItemPermission'
                                }
                            }
                        }
                    }
                }
                [pscustomobject]$TargetProperties
            }
            break
        }
        default {
            $ExpansionParameters = @{
                AceGUIDsByPath         = $AceGuidByPath
                ACEsByGUID             = $ACEsByGUID
                PrincipalsByResolvedID = $PrincipalsByResolvedID
            }
            ForEach ($Target in $Reference) {
                $TargetProperties = @{
                    PSTypeName = 'Permission.TargetPermission'
                    Path       = $Target.Path
                }
                $TargetProperties['NetworkPaths'] = ForEach ($NetworkPath in $Target.NetworkPaths) {
                    [pscustomobject]@{
                        Access     = Expand-FlatPermissionReference -SortedPath $SortedPaths @ExpansionParameters
                        Item       = $AclsByPath[$NetworkPath.Path]
                        PSTypeName = 'Permission.FlatPermission'
                    }
                }
                [pscustomobject]$TargetProperties
            }
            break
        }
    }
}
function Get-ColumnJson {
    param (
        $InputObject,
        [string[]]$PropNames,
        [Hashtable]$ColumnDefinition = @{
            'Inheritance' = @{
                'width' = '1'
            }
        }
    )
    if (-not $PSBoundParameters.ContainsKey('PropNames')) {
        $PropNames = (@($InputObject)[0] | Get-Member -MemberType noteproperty).Name
    }
    $Columns = ForEach ($Prop in $PropNames) {
        $Props = $ColumnDefinition[$Prop]
        if ($Props) {
            $Props['field'] = $Prop -replace '\s', ''
            $Props['title'] = $Prop
        } else {
            $Props = @{
                'field' = $Prop -replace '\s', ''
                'title' = $Prop
            }
        }
        [PSCustomObject]$Props
    }
    $Columns |
    ConvertTo-Json -Compress
}
function Get-DetailDivHeader {
    param (
        [String]$GroupBy,
        [String]$Split
    )
    if ( $GroupBy -eq $Split ) {
        'Permissions'
    } else {
        switch ($GroupBy) {
            'account' { 'Folders Included in Those Permissions'; break }
            'item' { 'Accounts Included in Those Permissions'; break }
            'target' { 'Target Paths'; break }
            'none' { 'Permissions'; break }
        }
    }
}
function Get-FolderPermissionTableHeader {
    [OutputType([String])]
    param (
        $Group,
        [String]$GroupID,
        [String]$ShortestFolderPath
    )
    $Parent = $GroupID | Split-Path -Parent
    $Leaf = $Parent | Split-Path -Leaf -ErrorAction SilentlyContinue
    if ($Leaf) {
        $ParentLeaf = $Leaf
    } else {
        $ParentLeaf = $Parent
    }
    if ('' -ne $ParentLeaf) {
        if ($Group.Item.AreAccessRulesProtected) {
            return "Inheritance is disabled on this folder. Accounts with access to the parent ($ParentLeaf) and its subfolders cannot access this folder unless they are listed here:"
        } else {
            if ($Group.Item.Path -eq $ShortestFolderPath) {
                return "Inherited permissions from the parent ($ParentLeaf) are included. This folder can only be accessed by the accounts listed here:"
            } else {
                return "Inheritance is enabled on this folder. Accounts with access to the parent ($ParentLeaf) and its subfolders can access this folder. So can the accounts listed here:"
            }
        }
    } else {
        return 'This is the top-level folder. It can only be accessed by the accounts listed here:'
    }
}
function Get-HtmlBody {
    param (
        $NetworkPathDiv,
        $TableOfContents,
        $HtmlFolderPermissions,
        $ReportFooter,
        $HtmlFileList,
        $HtmlExclusions,
        $SummaryDivHeader,
        $DetailDivHeader
    )
    $StringBuilder = [System.Text.StringBuilder]::new()
    $null = $StringBuilder.Append((New-HtmlHeading 'Network Paths' -Level 5))
    $null = $StringBuilder.Append($NetworkPathDiv)
    if ($TableOfContents) {
        $null = $StringBuilder.Append((New-HtmlHeading $SummaryDivHeader -Level 5))
        $null = $StringBuilder.Append($TableOfContents)
    }
    $null = $StringBuilder.Append((New-HtmlHeading $DetailDivHeader -Level 5))
    ForEach ($Perm in $HtmlFolderPermissions) {
        $null = $StringBuilder.Append($Perm)
    }
    if ($HtmlExclusions) {
        $null = $StringBuilder.Append((New-HtmlHeading "Exclusions from This Report" -Level 5))
        $null = $StringBuilder.Append($HtmlExclusions)
    }
    $null = $StringBuilder.Append((New-HtmlHeading "Files Generated" -Level 5))
    $null = $StringBuilder.Append($HtmlFileList)
    $null = $StringBuilder.Append($ReportFooter)
    return $StringBuilder.ToString()
}
function Get-HtmlReportElements {
    param (
        [string[]]$ExcludeAccount,
        [string[]]$ExcludeClass = @('group', 'computer'),
        $IgnoreDomain,
        [string[]]$TargetPath,
        $NetworkPath,
        [switch]$NoMembers,
        $OutputDir,
        $WhoAmI,
        $ThisFqdn,
        $StopWatch,
        $Title,
        $Permission,
        $LogParams,
        $RecurseDepth,
        $LogFileList,
        $ReportInstanceId,
        [Hashtable]$AceByGUID,
        [Hashtable]$AclByPath,
        [Hashtable]$PrincipalByID,
        [int[]]$Detail = @(0..10),
        [cultureinfo]$Culture = (Get-Culture),
        [ValidateSet('account', 'item', 'none', 'target')]
        [String]$GroupBy = 'item',
        [String]$Split,
        [String]$FileName,
        $FormattedPermission,
        $BestPracticeIssue,
        [string[]]$Parent,
        [string[]]$FileFormat,
        [String]$OutputFormat
    )
    Write-LogMsg @LogParams -Text "Get-ReportDescription -RecurseDepth $RecurseDepth"
    $ReportDescription = Get-ReportDescription -RecurseDepth $RecurseDepth
    $NetworkPathTable = Select-ItemTableProperty -InputObject $NetworkPath -Culture $Culture -SkipFilterCheck |
    ConvertTo-Html -Fragment |
    New-BootstrapTable
    $NetworkPathDivHeader = 'Local paths were resolved to UNC paths, and UNC paths were resolved to all DFS folder targets'
    Write-LogMsg @LogParams -Text "New-BootstrapDivWithHeading -HeadingText '$NetworkPathDivHeader' -Content `$NetworkPathTable"
    $NetworkPathDiv = New-BootstrapDivWithHeading -HeadingText $NetworkPathDivHeader -Content $NetworkPathTable -Class 'h-100 p-1 bg-light border rounded-3 table-responsive' -HeadingLevel 6
    Write-LogMsg @LogParams -Text "Get-SummaryDivHeader -GroupBy $GroupBy"
    $SummaryDivHeader = Get-SummaryDivHeader -GroupBy $GroupBy -Split $Split
    Write-LogMsg @LogParams -Text "Get-SummaryTableHeader -RecurseDepth $RecurseDepth -GroupBy $GroupBy"
    $SummaryTableHeader = Get-SummaryTableHeader -RecurseDepth $RecurseDepth -GroupBy $GroupBy
    Write-LogMsg @LogParams -Text "Get-DetailDivHeader -GroupBy $GroupBy"
    $DetailDivHeader = Get-DetailDivHeader -GroupBy $GroupBy -Split $Split
    Write-LogMsg @LogParams -Text "New-HtmlHeading 'Target Paths' -Level 5"
    $TargetHeading = New-HtmlHeading 'Target Paths' -Level 5
    $TargetPathString = $TargetPath -join '<br />'
    Write-LogMsg @LogParams -Text "New-BootstrapAlert -Class Dark -Text '$TargetPathString'"
    $TargetAlert = New-BootstrapAlert -Class Dark -Text $TargetPathString -AdditionalClasses ' small'
    $ReportParameters = @{
        Title       = $Title
        Description = "$TargetHeading $TargetAlert $ReportDescription"
    }
    $ExcludedNames = ConvertTo-NameExclusionDiv -ExcludeAccount $ExcludeAccount
    $ExcludedClasses = ConvertTo-ClassExclusionDiv -ExcludeClass $ExcludeClass
    $IgnoredDomains = ConvertTo-IgnoredDomainDiv -IgnoreDomain $IgnoreDomain
    $ExcludedMembers = ConvertTo-MemberExclusionDiv -NoMembers:$NoMembers
    Write-LogMsg @LogParams -Text "New-BootstrapColumn -Html '`$ExcludedMembers`$ExcludedClasses',`$IgnoredDomains`$ExcludedNames"
    $ExclusionsDiv = New-BootstrapColumn -Html "$ExcludedMembers$ExcludedClasses", "$IgnoredDomains$ExcludedNames" -Width 6
    $HtmlListOfLogs = $LogFileList |
    Split-Path -Leaf | 
    ConvertTo-HtmlList |
    ConvertTo-BootstrapListGroup
    $HtmlReportsHeading = New-HtmlHeading -Text 'Reports' -Level 6
    $HtmlLogsHeading = New-HtmlHeading -Text 'Logs' -Level 6
    $HtmlOutputDir = New-BootstrapAlert -Text $OutputDir -Class 'secondary' -AdditionalClasses ' small'
    $ReportFileList = ConvertTo-FileList -Detail $Detail -Format $Formats -FileName $FileName
    $HtmlReportsDiv = (ConvertTo-FileListDiv -FileList $ReportFileList) -join "`r`n"
    Write-LogMsg @LogParams -Text "New-BootstrapColumn -Html '`$HtmlReportsHeading`$HtmlReportsDiv',`$HtmlLogsHeading`$HtmlListOfLogs"
    $HtmlDivOfFileColumns = New-BootstrapColumn -Html "$HtmlReportsHeading$HtmlReportsDiv", "$HtmlLogsHeading$HtmlListOfLogs" -Width 6
    Write-LogMsg @LogParams -Text "New-BootstrapDivWithHeading -HeadingText 'Output Folder:' -Content '`$HtmlOutputDir`$HtmlDivOfFileColumns'"
    $HtmlDivOfFiles = New-BootstrapDivWithHeading -HeadingText "Output Folder:" -Content "$HtmlOutputDir$HtmlDivOfFileColumns" -HeadingLevel 6
    Write-LogMsg @LogParams -Text "Get-ReportFooter -StopWatch `$StopWatch -ReportInstanceId '$ReportInstanceId' -WhoAmI '$WhoAmI' -ThisFqdn '$ThisFqdn'"
    $FooterParams = @{
        ItemCount        = $AclByPath.Keys.Count
        PermissionCount  = (
            @(
                $Permission.AccountPermissions.Access.Access.Count, 
                $Permission.ItemPermissions.Access.Access.Count,
                $Permission.TargetPermissions.NetworkPaths.Accounts.Access.Access.Count, 
                ($Permission.TargetPermissions.NetworkPaths.Items.Access.Access.Count + $Permission.TargetPermissions.NetworkPaths.Access.Access.Count), 
                $Permission.TargetPermissions.NetworkPaths.Access.Count, 
                $AceByGUID.Keys.Count
            ) |
            Measure-Object -Maximum
        ).Maximum
        PrincipalCount   = $PrincipalByID.Keys.Count
        ReportInstanceId = $ReportInstanceId
        StopWatch        = $StopWatch
        ThisFqdn         = $ThisFqdn
        WhoAmI           = $WhoAmI
        AceByGUID        = $AceByGUID
        AclByPath        = $AclByPath
    }
    $ReportFooter = Get-HtmlReportFooter @FooterParams
    [PSCustomObject]@{
        ReportFooter       = $ReportFooter
        HtmlDivOfFiles     = $HtmlDivOfFiles
        ExclusionsDiv      = $ExclusionsDiv
        ReportParameters   = $ReportParameters
        DetailDivHeader    = $DetailDivHeader
        SummaryTableHeader = $SummaryTableHeader
        SummaryDivHeader   = $SummaryDivHeader
        NetworkPathDiv     = $NetworkPathDiv
    }
}
function Get-HtmlReportFooter {
    param (
        [System.Diagnostics.Stopwatch]$StopWatch,
        [String]$WhoAmI = (whoami.EXE),
        [String]$ThisFqdn = ([System.Net.Dns]::GetHostByName((HOSTNAME.EXE)).HostName),
        [uint64]$ItemCount,
        [uint64]$TotalBytes,
        [String]$ReportInstanceId,
        [UInt64]$PermissionCount,
        [UInt64]$PrincipalCount,
        [string[]]$UnitsToResolve = @('day', 'hour', 'minute', 'second'),
        [Hashtable]$AceByGUID,
        [Hashtable]$AclByPath
    )
    $null = $StopWatch.Stop()
    $FinishTime = Get-Date
    $StartTime = $FinishTime.AddTicks(-$StopWatch.ElapsedTicks)
    $TimeZoneName = Get-TimeZoneName -Time $FinishTime
    $Duration = Format-TimeSpan -TimeSpan $StopWatch.Elapsed -UnitsToResolve $UnitsToResolve
    if ($TotalBytes) {
        $Size = " ($($TotalBytes / 1TB) TiB"
    }
    $Text = @"
Report generated by $WhoAmI on $ThisFQDN starting at $StartTime and ending at $FinishTime $TimeZoneName<br />
Processed $($AceByGUID.Keys.Count) ACEs with $PermissionCount permissions for $PrincipalCount accounts on $ItemCount items$Size in $Duration<br />
Report instance: $ReportInstanceId
"@
    New-BootstrapAlert -Class Light -Text $Text -AdditionalClasses ' small'
}
function Get-ReportDescription {
    param (
        [int]$RecurseDepth
    )
    switch ($RecurseDepth ) {
        0 {
            'Does not include permissions on subfolders (option was declined)'; break
        }
        -1 {
            'Includes all subfolders with unique permissions (including ∞ levels of subfolders)'; break
        }
        default {
            "Includes all subfolders with unique permissions (down to $RecurseDepth levels of subfolders)"; break
        }
    }
}
function Get-SummaryDivHeader {
    param (
        [String]$GroupBy,
        [String]$Split
    )
    if ( $GroupBy -eq $Split ) {
        'Permissions'
    } else {
        switch ($GroupBy) {
            'account' { 'Accounts With Permissions'; break }
            'item' { 'Items in Those Paths with Unique Permissions'; break }
            'target' { 'Target Paths'; break }
            'none' { 'Permissions'; break }
        }
    }
}
function Get-SummaryTableHeader {
    param (
        [int]$RecurseDepth,
        [String]$GroupBy
    )
    switch ($GroupBy) {
        'account' {
            if ($NoMembers) {
                'Includes accounts directly listed in the permissions only (option to include group members was declined)'
            } else {
                'Includes accounts in the permissions, and their group members'
            }
            break
        }
        'item' {
            switch ($RecurseDepth ) {
                0 {
                    'Includes the target folder only (option to report on subfolders was declined)'
                    break
                }
                -1 {
                    'Includes the target folder and all subfolders with unique permissions'
                    break
                }
                default {
                    "Includes the target folder and $RecurseDepth levels of subfolders with unique permissions"
                    break
                }
            }
            break
        }
        'target' {
            break
        }
    }
}
function Group-AccountPermissionReference {
    param (
        [string[]]$ID,
        [Hashtable]$AceGuidByID,
        [Hashtable]$AceByGuid
    )
    ForEach ($Identity in ($ID | Sort-Object)) {
        $ItemPaths = @{}
        ForEach ($Guid in $AceGuidByID[$Identity]) {
            Add-CacheItem -Cache $ItemPaths -Key $AceByGuid[$Guid].Path -Value $Guid -Type ([guid])
        }
        [PSCustomObject]@{
            Account = $Identity
            Access  = ForEach ($Item in ($ItemPaths.Keys | Sort-Object)) {
                [PSCustomObject]@{
                    Path     = $Item
                    AceGUIDs = $ItemPaths[$Item]
                }
            }
        }
    }
}
function Group-ItemPermissionReference {
    param (
        $SortedPath,
        $AceGUIDsByPath,
        $ACEsByGUID,
        $PrincipalsByResolvedID,
        [Hashtable]$Property = @{}
    )
    ForEach ($ItemPath in $SortedPath) {
        $Property['Path'] = $ItemPath
        $IDsWithAccess = Find-ResolvedIDsWithAccess -ItemPath $ItemPath -AceGUIDsByPath $AceGUIDsByPath -ACEsByGUID $ACEsByGUID -PrincipalsByResolvedID $PrincipalsByResolvedID
        $Property['Access'] = ForEach ($ID in ($IDsWithAccess.Keys | Sort-Object)) {
            [PSCustomObject]@{
                Account  = $ID
                AceGUIDs = $IDsWithAccess[$ID]
            }
        }
        [PSCustomObject]$Property
    }
}
function Group-TargetPermissionReference {
    param (
        [Hashtable]$TargetPath,
        [Hashtable]$Children,
        $PrincipalsByResolvedID,
        $AceGUIDsByResolvedID,
        $ACEsByGUID,
        $AceGUIDsByPath,
        $ACLsByPath,
        [ValidateSet('account', 'item', 'none', 'target')]
        [String]$GroupBy = 'item'
    )
    $CommonParams = @{
        AceGUIDsByPath         = $AceGUIDsByPath
        ACEsByGUID             = $ACEsByGUID
        PrincipalsByResolvedID = $PrincipalsByResolvedID
    }
    switch ($GroupBy) {
        'account' {
            ForEach ($Target in ($TargetPath.Keys | Sort-Object)) {
                $TargetProperties = @{
                    Path = $Target
                }
                $NetworkPaths = $TargetPath[$Target] | Sort-Object
                $TargetProperties['NetworkPaths'] = ForEach ($NetworkPath in $NetworkPaths) {
                    $ItemsForThisNetworkPath = [System.Collections.Generic.List[String]]::new()
                    $ItemsForThisNetworkPath.Add($NetworkPath)
                    $ItemsForThisNetworkPath.AddRange([string[]]$Children[$NetworkPath])
                    $IDsWithAccess = Find-ResolvedIDsWithAccess -ItemPath $ItemsForThisNetworkPath -AceGUIDsByPath $AceGUIDsByPath -ACEsByGUID $ACEsByGUID -PrincipalsByResolvedID $PrincipalsByResolvedID
                    $AceGuidsForThisNetworkPath = @{}
                    ForEach ($Guid in $AceGUIDsByPath[$ItemsForThisNetworkPath]) {
                        if ($Guid) {
                            ForEach ($ListItem in $Guid) {
                                $AceGuidsForThisNetworkPath[$ListItem] = $true
                            }
                        }
                    }
                    $AceGuidByIDForThisNetworkPath = @{}
                    ForEach ($ID in $IDsWithAccess.Keys) {
                        $GuidsForThisIDAndNetworkPath = [System.Collections.Generic.List[guid]]::new()
                        ForEach ($Guid in $AceGUIDsByResolvedID[$ID]) {
                            $AceContainsThisID = $AceGuidsForThisNetworkPath[$Guid]
                            if ($AceContainsThisID) {
                                $GuidsForThisIDAndNetworkPath.Add($Guid)
                            }
                        }
                        $AceGuidByIDForThisNetworkPath[$ID] = $GuidsForThisIDAndNetworkPath
                    }
                    [PSCustomObject]@{
                        Path     = $NetworkPath
                        Accounts = Group-AccountPermissionReference -ID $IDsWithAccess.Keys -AceGuidByID $AceGuidByIDForThisNetworkPath -AceByGuid $ACEsByGUID
                    }
                }
                [pscustomobject]$TargetProperties
            }
            break
        }
        'item' {
            ForEach ($Target in ($TargetPath.Keys | Sort-Object)) {
                $TargetProperties = @{
                    Path = $Target
                }
                $NetworkPaths = $TargetPath[$Target] | Sort-Object
                $TargetProperties['NetworkPaths'] = ForEach ($NetworkPath in $NetworkPaths) {
                    $TopLevelItemProperties = @{
                        'Items' = Group-ItemPermissionReference -SortedPath ($Children[$NetworkPath] | Sort-Object) -ACLsByPath $ACLsByPath @CommonParams
                    }
                    Group-ItemPermissionReference -SortedPath $NetworkPath -Property $TopLevelItemProperties -ACLsByPath $ACLsByPath @CommonParams
                }
                [pscustomobject]$TargetProperties
            }
            break
        }
        default {
            ForEach ($Target in ($TargetPath.Keys | Sort-Object)) {
                $TargetProperties = @{
                    Path = $Target
                }
                $NetworkPaths = $TargetPath[$Target] | Sort-Object
                $TargetProperties['NetworkPaths'] = ForEach ($NetworkPath in $NetworkPaths) {
                    $ItemsForThisNetworkPath = [System.Collections.Generic.List[String]]::new()
                    $ItemsForThisNetworkPath.Add($NetworkPath)
                    $ItemsForThisNetworkPath.AddRange([string[]]$Children[$NetworkPath])
                    [PSCustomObject]@{
                        Path   = $NetworkPath
                        Access = Expand-FlatPermissionReference -SortedPath $ItemsForThisNetworkPath @CommonParams
                    }
                }
                [pscustomobject]$TargetProperties
            }
            break
        }
    }
}
function Memory {
}
function Merge-AceAndPrincipal {
    param (
        $Principal,
        $ACE,
        $PrincipalByResolvedID
    )
    ForEach ($Member in $Principal.Members) {
        Merge-AceAndPrincipal -ACE $ACE -Principal $PrincipalByResolvedID[$Member] -PrincipalByResolvedID $PrincipalByResolvedID
    }
    $OutputProperties = @{
        PSTypeName  = 'Permission.FlatPermission'
        ItemPath    = $ACE.Path
        AdsiPath    = $Principal.Path
        AccountName = $Principal.ResolvedAccountName
    }
    ForEach ($Prop in ($ACE | Get-Member -View All -MemberType Property, NoteProperty).Name) {
        $OutputProperties[$Prop] = $ACE.$Prop
    }
    ForEach ($Prop in ($Principal | Get-Member -View All -MemberType Property, NoteProperty).Name) {
        $OutputProperties[$Prop] = $Principal.$Prop
    }
    return [pscustomobject]$OutputProperties
}
function Out-PermissionDetailReport {
    param (
        [int[]]$Detail,
        [Hashtable]$ReportObject,
        [scriptblock[]]$DetailExport,
        [String]$Format,
        [String]$OutputDir,
        [cultureinfo]$Culture,
        [string[]]$DetailString,
        [String]$FileName,
        [String]$FormatToReturn = 'js',
        [int]$LevelToReturn = 10
    )
    switch ($Format) {
        'csv' { $Suffix = '.csv' ; break }
        'html' { $Suffix = "_$FileName.htm" ; break }
        'js' { $Suffix = "_$Format`_$FileName.htm" ; break }
        'json' { $Suffix = "_$FileName.json" ; break }
        'prtgxml' { $Suffix = '.xml' ; break }
        'xml' { $Suffix = '.xml' ; break }
    }
    ForEach ($Level in $Detail) {
        $ShortDetail = $DetailString[$Level] -replace '\([^\)]*\)', ''
        $TitleCaseDetail = $Culture.TextInfo.ToTitleCase($ShortDetail)
        $SpacelessDetail = $TitleCaseDetail -replace '\s', ''
        $ThisReportFile = "$OutputDir\$Level`_$SpacelessDetail$Suffix"
        $Report = $ReportObject[$Level]
        $null = Invoke-Command -ScriptBlock $DetailExport[$Level] -ArgumentList $Report, $ThisReportFile
        Write-Information $ThisReportFile
        if ($Level -eq $LevelToReturn -and $Format -eq $FormatToReturn) {
            $ThisReportFile
        }
    }
}
function Resolve-Ace {
    [OutputType([void])]
    param (
        [Parameter(
            ValueFromPipeline
        )]
        [object]$ACE,
        [Hashtable]$ACLsByPath = [Hashtable]::Synchronized(@{}),
        [Parameter(
            ValueFromPipeline
        )]
        [object]$ItemPath,
        [Hashtable]$ACEsByGUID = ([Hashtable]::Synchronized(@{})),
        [Hashtable]$AceGUIDsByResolvedID = ([Hashtable]::Synchronized(@{})),
        [Hashtable]$AceGUIDsByPath = ([Hashtable]::Synchronized(@{})),
        [Hashtable]$DirectoryEntryCache = ([Hashtable]::Synchronized(@{})),
        [Hashtable]$DomainsByNetbios = ([Hashtable]::Synchronized(@{})),
        [Hashtable]$DomainsBySid = ([Hashtable]::Synchronized(@{})),
        [Hashtable]$DomainsByFqdn = ([Hashtable]::Synchronized(@{})),
        [String]$ThisHostName = (HOSTNAME.EXE),
        [String]$ThisFqdn = ([System.Net.Dns]::GetHostByName((HOSTNAME.EXE)).HostName),
        [String]$WhoAmI = (whoami.EXE),
        [Hashtable]$LogBuffer = @{},
        [Hashtable]$CimCache = @{},
        [ValidateSet('Silent', 'Quiet', 'Success', 'Debug', 'Verbose', 'Output', 'Host', 'Warning', 'Error', 'Information', $null)]
        [String]$DebugOutputStream = 'Debug',
        [string[]]$ACEPropertyName = (Get-Member -InputObject $ACE -MemberType Property, CodeProperty, ScriptProperty, NoteProperty).Name,
        [String]$Source,
        [string[]]$InheritanceFlagResolved = @('this folder but not subfolders', 'this folder and subfolders', 'this folder and files, but not subfolders', 'this folder, subfolders, and files')
    )
    $Log = @{
        ThisHostname = $ThisHostname
        Type         = $DebugOutputStream
        Buffer       = $LogBuffer
        WhoAmI       = $WhoAmI
    }
    $LogSplat = @{
        ThisHostname = $ThisHostname
        LogBuffer    = $LogBuffer
        WhoAmI       = $WhoAmI
    }
    $Cache1 = @{
        DirectoryEntryCache = $DirectoryEntryCache
        DomainsByFqdn       = $DomainsByFqdn
    }
    $Cache2 = @{
        DomainsByNetBIOS = $DomainsByNetbios
        DomainsBySid     = $DomainsBySid
        CimCache         = $CimCache
    }
    Write-LogMsg @Log -Text "Resolve-IdentityReferenceDomainDNS -IdentityReference '$($ACE.IdentityReference)' -ItemPath '$ItemPath' -ThisFqdn '$ThisFqdn' @Cache2 @Log"
    $DomainDNS = Resolve-IdentityReferenceDomainDNS -IdentityReference $ACE.IdentityReference -ItemPath $ItemPath -ThisFqdn $ThisFqdn @Cache2 @Log
    Write-LogMsg @Log -Text "`$AdsiServer = Get-AdsiServer -Fqdn '$DomainDNS' -ThisFqdn '$ThisFqdn'"
    $AdsiServer = Get-AdsiServer -Fqdn $DomainDNS -ThisFqdn $ThisFqdn @GetAdsiServerParams @Cache1 @Cache2 @LogSplat
    Write-LogMsg @Log -Text "Resolve-IdentityReference -IdentityReference '$($ACE.IdentityReference)' -AdsiServer `$AdsiServer -ThisFqdn '$ThisFqdn' # ADSI server '$($AdsiServer.AdsiProvider)://$($AdsiServer.Dns)'"
    $ResolvedIdentityReference = Resolve-IdentityReference -IdentityReference $ACE.IdentityReference -AdsiServer $AdsiServer -ThisFqdn $ThisFqdn @Cache1 @Cache2 @LogSplat
    $ObjectProperties = @{
        Access                    = "$($ACE.AccessControlType) $($ACE.FileSystemRights) $($InheritanceFlagResolved[$ACE.InheritanceFlags])"
        AdsiProvider              = $AdsiServer.AdsiProvider
        AdsiServer                = $AdsiServer.Dns
        IdentityReferenceSID      = $ResolvedIdentityReference.SIDString
        IdentityReferenceResolved = $ResolvedIdentityReference.IdentityReferenceNetBios
        Path                      = $ItemPath
        SourceOfAccess            = $Source
        PSTypeName                = 'Permission.AccessControlEntry'
    }
    ForEach ($ThisProperty in $ACEPropertyName) {
        $ObjectProperties[$ThisProperty] = $ACE.$ThisProperty
    }
    $OutputObject = [PSCustomObject]$ObjectProperties
    $Guid = [guid]::NewGuid()
    Add-CacheItem -Cache $ACEsByGUID -Key $Guid -Value $OutputObject -Type ([object])
    $Type = [guid]
    Add-CacheItem -Cache $AceGUIDsByResolvedID -Key $OutputObject.IdentityReferenceResolved -Value $Guid -Type $Type
    Add-CacheItem -Cache $AceGUIDsByPath -Key $OutputObject.Path -Value $Guid -Type $Type
}
function Resolve-Acl {
    [OutputType([PSCustomObject])]
    param (
        [Parameter(
            ValueFromPipeline
        )]
        [object]$ItemPath,
        [Hashtable]$ACLsByPath = [Hashtable]::Synchronized(@{}),
        [Hashtable]$ACEsByGUID = ([Hashtable]::Synchronized(@{})),
        [Hashtable]$AceGUIDsByResolvedID = ([Hashtable]::Synchronized(@{})),
        [Hashtable]$AceGUIDsByPath = ([Hashtable]::Synchronized(@{})),
        [Hashtable]$DirectoryEntryCache = ([Hashtable]::Synchronized(@{})),
        [Hashtable]$DomainsByNetbios = ([Hashtable]::Synchronized(@{})),
        [Hashtable]$DomainsBySid = ([Hashtable]::Synchronized(@{})),
        [Hashtable]$DomainsByFqdn = ([Hashtable]::Synchronized(@{})),
        [String]$ThisHostName = (HOSTNAME.EXE),
        [String]$ThisFqdn = ([System.Net.Dns]::GetHostByName((HOSTNAME.EXE)).HostName),
        [String]$WhoAmI = (whoami.EXE),
        [Hashtable]$LogBuffer = ([Hashtable]::Synchronized(@{})),
        [Hashtable]$CimCache = ([Hashtable]::Synchronized(@{})),
        [ValidateSet('Silent', 'Quiet', 'Success', 'Debug', 'Verbose', 'Output', 'Host', 'Warning', 'Error', 'Information', $null)]
        [String]$DebugOutputStream = 'Debug',
        [string[]]$ACEPropertyName = (Get-Member -InputObject $ItemPath -MemberType Property, CodeProperty, ScriptProperty, NoteProperty).Name,
        [string[]]$InheritanceFlagResolved = @('this folder but not subfolders', 'this folder and subfolders', 'this folder and files, but not subfolders', 'this folder, subfolders, and files')
    )
    $Log = @{
        ThisHostname = $ThisHostname
        Type         = $DebugOutputStream
        Buffer       = $LogBuffer
        WhoAmI       = $WhoAmI
    }
    $ACL = $ACLsByPath[$ItemPath]
    if ($ACL.Owner.IdentityReference) {
        Write-LogMsg @Log -Text "Resolve-Ace -ACE $($ACL.Owner) -ACEPropertyName @('$($ACEPropertyName -join "','")') @PSBoundParameters"
        Resolve-Ace -ACE $ACL.Owner -Source 'Ownership' @PSBoundParameters
    }
    ForEach ($ACE in $ACL.Access) {
        Write-LogMsg @Log -Text "Resolve-Ace -ACE $ACE -ACEPropertyName @('$($ACEPropertyName -join "','")') @PSBoundParameters"
        Resolve-Ace -ACE $ACE -Source 'Discretionary ACL' @PSBoundParameters
    }
}
function Resolve-FormatParameter {
    param (
        [ValidateSet('csv', 'html', 'js', 'json', 'prtgxml', 'xml')]
        [string[]]$FileFormat = @('csv', 'html', 'js', 'json', 'prtgxml', 'xml'),
        [ValidateSet('passthru', 'none', 'csv', 'html', 'js', 'json', 'prtgxml', 'xml')]
        [String]$OutputFormat = 'passthru'
    )
    $AllFormats = @{}
    ForEach ($Format in $FileFormat) {
        $AllFormats[$Format] = $null
    }
    if ($OutputFormat -ne 'passthru' -and $OutputFormat -ne 'none') {
        $AllFormats[$OutputFormat] = $null
    }
    $Sorted = [string[]]$AllFormats.Keys | Sort-Object -Descending
    return $Sorted
}
function Resolve-GroupByParameter {
    param (
        [ValidateSet('account', 'item', 'none', 'target')]
        [String]$GroupBy = 'item',
        [Hashtable]$HowToSplit
    )
    if (
        $GroupBy -eq 'none' -or
        $HowToSplit[$GroupBy]
    ) {
        return @{
            Property = 'Access'
            Script   = [scriptblock]::create("Select-PermissionTableProperty -InputObject `$args[0] -ShortNameById `$args[2] -IncludeFilterContents `$args[3] -ExcludeClassFilterContents `$args[4]")
        }
    } else {
        return @{
            Property = "$GroupBy`s"
            Script   = [scriptblock]::create("Select-$GroupBy`TableProperty -InputObject `$args[0] -Culture `$args[1] -ShortNameById `$args[2]")
        }
    }
}
function Resolve-IdentityReferenceDomainDNS {
    param (
        [String]$IdentityReference,
        [object]$ItemPath,
        [Hashtable]$DomainsByNetbios = ([Hashtable]::Synchronized(@{})),
        [Hashtable]$DomainsBySid = ([Hashtable]::Synchronized(@{})),
        [String]$ThisHostName = (HOSTNAME.EXE),
        [String]$ThisFqdn = ([System.Net.Dns]::GetHostByName((HOSTNAME.EXE)).HostName),
        [String]$WhoAmI = (whoami.EXE),
        [Hashtable]$LogBuffer = @{},
        [Hashtable]$CimCache = @{}
    )
    $Log = @{
        ThisHostname = $ThisHostname
        Type         = $DebugOutputStream
        Buffer       = $LogBuffer
        WhoAmI       = $WhoAmI
    }
    if ($IdentityReference.Substring(0, 4) -eq 'S-1-') {
        $IndexOfLastHyphen = $IdentityReference.LastIndexOf("-")
        $DomainSid = $IdentityReference.Substring(0, $IndexOfLastHyphen)
        if ($DomainSid) {
            $DomainCacheResult = $DomainsBySID[$DomainSid]
            if ($DomainCacheResult) {
                Write-LogMsg @Log -Text " # Domain SID cache hit for '$DomainSid' for '$IdentityReference'"
                $DomainDNS = $DomainCacheResult.Dns
            } else {
                Write-LogMsg @Log -Text " # Domain SID cache miss for '$DomainSid' for '$IdentityReference'"
            }
        }
    } else {
        $DomainNetBIOS = ($IdentityReference.Split('\'))[0]
        $KnownLocalDomains = @{
            'NT SERVICE'   = $true
            'BUILTIN'      = $true
            'NT AUTHORITY' = $true
        }
        if (-not $KnownLocalDomains[$DomainNetBIOS]) {
            if ($DomainNetBIOS) {
                $DomainDNS = $DomainsByNetbios[$DomainNetBIOS].Dns 
            }
            if (-not $DomainDNS) {
                $ThisServerDn = ConvertTo-DistinguishedName -Domain $DomainNetBIOS -DomainsByNetbios $DomainsByNetbios @LoggingParams
                $DomainDNS = ConvertTo-Fqdn -DistinguishedName $ThisServerDn -ThisFqdn $ThisFqdn -CimCache $CimCache @LoggingParams
            }
        }
    }
    if (-not $DomainDNS) {
        Write-LogMsg @Log -Text "Find-ServerNameInPath -LiteralPath '$ItemPath' -ThisFqdn '$ThisFqdn'"
        $DomainDNS = Find-ServerNameInPath -LiteralPath $ItemPath -ThisFqdn $ThisFqdn
    }
    return $DomainDNS
}
function Resolve-SplitByParameter {
    param (
        [ValidateSet('none', 'all', 'target', 'item', 'account')]
        [string[]]$SplitBy = 'all'
    )
    $result = @{}
    foreach ($Split in $SplitBy) {
        if ($Split -eq 'none') {
            return @{'none' = $true }
        } elseif ($Split -eq 'all') {
            return @{
                'target'  = $true
                'none'    = $true
                'item'    = $true
                'account' = $true
            }
        } else {
            $result[$Split] = $true
        }
    }
    return $result
}
function Select-AccountTableProperty {
    param (
        $InputObject,
        [cultureinfo]$Culture = (Get-Culture), 
        [Hashtable]$ShortNameByID = [Hashtable]::Synchronized(@{})
    )
    ForEach ($Object in $InputObject) {
        $AccountName = $ShortNameByID[$Object.Account.ResolvedAccountName]
        if ($AccountName) {
            [PSCustomObject]@{
                Account     = $AccountName
                Name        = $Object.Account.Name
                DisplayName = $Object.Account.DisplayName
                Description = $Object.Account.Description
                Department  = $Object.Account.Department
                Title       = $Object.Account.Title
            }
        }
    }
}
function Select-ItemTableProperty {
    param (
        $InputObject,
        [cultureinfo]$Culture = (Get-Culture),
        [Hashtable]$ShortNameByID = [Hashtable]::Synchronized(@{}), 
        [switch]$SkipFilterCheck
    )
    ForEach ($Object in $InputObject) {
        if (-not $SkipFilterCheck) {
            $AccountNames = $ShortNameByID[$Object.Access.Account.ResolvedAccountName]
            if (-not $AccountNames) { continue }
            $GroupString = $ShortNameByID[$Object.Access.Access.IdentityReferenceResolved]
            if (-not $GroupString) { continue }
        }
        [PSCustomObject]@{
            Folder      = $Object.Item.Path
            Inheritance = $Culture.TextInfo.ToTitleCase(-not $Object.Item.AreAccessRulesProtected)
        }
    }
}
function Select-PermissionTableProperty {
    param (
        $InputObject,
        [String]$GroupBy,
        [Hashtable]$ShortNameByID = @{},
        [Hashtable]$OutputHash = @{},
        [Hashtable]$ExcludeClassFilterContents = @{},
        [Hashtable]$IncludeFilterContents = @{}
    )
    $Type = [PSCustomObject]
    $IncludeFilterCount = $IncludeFilterContents.Keys.Count
    switch ($GroupBy) {
        'account' {
            ForEach ($Object in $InputObject) {
                $AccountName = $ShortNameByID[$Object.Account.ResolvedAccountName]
                if ($AccountName) {
                    ForEach ($AceList in $Object.Access) {
                        ForEach ($ACE in $AceList.Access) {
                            if ($ACE.IdentityReferenceResolved -eq $Object.Account.ResolvedAccountName) {
                                $GroupString = ''
                            } else {
                                $GroupString = $ShortNameByID[$ACE.IdentityReferenceResolved]
                                if ( -not $GroupString ) {
                                    if (
                                        $ExcludeClassFilterContents[$ACE.IdentityReferenceResolved] -or
                                        (
                                            $IncludeFilterCount -gt 0 -and -not
                                            $IncludeFilterContents[$Object.Account.ResolvedAccountName]
                                        )
                                    ) {
                                        $GroupString = $ACE.IdentityReferenceResolved 
                                    }
                                }
                            }
                            if ($null -ne $GroupString) {
                                $Value = [pscustomobject]@{
                                    'Path'                 = $ACE.Path
                                    'Access'               = $ACE.Access
                                    'Due to Membership In' = $GroupString
                                    'Source of Access'     = $ACE.SourceOfAccess
                                }
                                Add-CacheItem -Cache $OutputHash -Key $AccountName -Value $Value -Type $Type
                            }
                        }
                    }
                }
            }
            break
        }
        'item' {
            ForEach ($Object in $InputObject) {
                $Accounts = @{}
                ForEach ($AceList in $Object.Access) {
                    $AccountName = $ShortNameByID[$AceList.Account.ResolvedAccountName]
                    if ($AccountName) {
                        ForEach ($ACE in $AceList.Access) {
                            Add-CacheItem -Cache $Accounts -Key $AccountName -Value $ACE -Type $Type
                        }
                    }
                }
                $OutputHash[$Object.Item.Path] = ForEach ($AccountName in $Accounts.Keys) {
                    ForEach ($AceList in $Accounts[$AccountName]) {
                        ForEach ($ACE in $AceList) {
                            if ($ACE.IdentityReferenceResolved -eq $AccountName) {
                                $GroupString = ''
                            } else {
                                $GroupString = $ShortNameByID[$ACE.IdentityReferenceResolved]
                                if ( -not $GroupString ) {
                                    if (
                                        $ExcludeClassFilterContents[$ACE.IdentityReferenceResolved] -or
                                        (
                                            $IncludeFilterCount -gt 0 -and -not
                                            $IncludeFilterContents[$AccountName]
                                        )
                                    ) {
                                        $GroupString = $ACE.IdentityReferenceResolved 
                                    }
                                }
                            }
                            if ($null -ne $GroupString) {
                                [pscustomobject]@{
                                    'Account'              = $AccountName
                                    'Access'               = $ACE.Access 
                                    'Due to Membership In' = $GroupString
                                    'Source of Access'     = $ACE.SourceOfAccess 
                                    'Name'                 = $AceList.Account.Name
                                    'Department'           = $AceList.Account.Department
                                    'Title'                = $AceList.Account.Title
                                }
                            }
                        }
                    }
                }
            }
            break
        }
        default {
            $i = 0
            ForEach ($Object in $InputObject) {
                $OutputHash[$i] = ForEach ($ACE in $Object) {
                    $AccountName = $ShortNameByID[$ACE.ResolvedAccountName]
                    if ($AccountName) {
                        if ($ACE.IdentityReferenceResolved -eq $ACE.ResolvedAccountName) {
                            $GroupString = ''
                        } else {
                            $GroupString = $ShortNameByID[$ACE.IdentityReferenceResolved]
                            if ( -not $GroupString ) {
                                if (
                                    $ExcludeClassFilterContents[$ACE.IdentityReferenceResolved] -or
                                    (
                                        $IncludeFilterCount -gt 0 -and -not
                                        $IncludeFilterContents[$ACE.ResolvedAccountName]
                                    )
                                ) {
                                    $GroupString = $ACE.IdentityReferenceResolved 
                                }
                            }
                        }
                        if ($null -ne $GroupString) {
                            [pscustomobject]@{
                                'Item'                 = $Object.ItemPath
                                'Account'              = $AccountName
                                'Access'               = $ACE.Access
                                'Due to Membership In' = $GroupString
                                'Source of Access'     = $ACE.SourceOfAccess
                                'Name'                 = $ACE.Name
                                'Department'           = $ACE.Department
                                'Title'                = $ACE.Title
                            }
                        }
                    }
                }
                $i = $i + 1
            }
            break
        }
    }
    return $OutputHash
}
function Add-CacheItem {
    param (
        [Hashtable]$Cache,
        $Key,
        $Value,
        [type]$Type
    )
    $CacheResult = $Cache[$Key]
    if ($CacheResult) {
        $List = $CacheResult
    } else {
        $Command = "`$List = [System.Collections.Generic.List[$($Type.ToString())]]::new()"
        Invoke-Expression $Command
    }
    $List.Add($Value)
    $Cache[$Key] = $List
}
function ConvertTo-ItemBlock {
    param (
        $ItemPermissions
    )
    $Culture = Get-Culture
    Write-LogMsg @LogParams -Text "`$ObjectsForTable = Select-ItemTableProperty -InputObject `$ItemPermissions -Culture '$Culture'"
    $ObjectsForTable = Select-ItemTableProperty -InputObject $ItemPermissions -Culture $Culture
    Write-LogMsg @LogParams -Text "`$ObjectsForTable | ConvertTo-Html -Fragment | New-BootstrapTable"
    $HtmlTable = $ObjectsForTable |
    ConvertTo-Html -Fragment |
    New-BootstrapTable
    $JsonData = $ObjectsForTable |
    ConvertTo-Json -Compress
    Write-LogMsg @LogParams -Text "Get-ColumnJson -InputObject `$ObjectsForTable"
    $JsonColumns = Get-ColumnJson -InputObject $ObjectsForTable
    Write-LogMsg @LogParams -Text "ConvertTo-BootstrapJavaScriptTable -Id 'Folders' -InputObject `$ObjectsForTable -DataFilterControl -SearchableColumn 'Folder' -DropdownColumn 'Inheritance'"
    $JsonTable = ConvertTo-BootstrapJavaScriptTable -Id 'Folders' -InputObject $ObjectsForTable -DataFilterControl -SearchableColumn 'Folder' -DropdownColumn 'Inheritance'
    return [pscustomobject]@{
        HtmlDiv     = $HtmlTable
        JsonDiv     = $JsonTable
        JsonData    = $JsonData
        JsonColumns = $JsonColumns
    }
}
function Expand-Permission {
    param (
        $SplitBy,
        $GroupBy,
        $AceGuidByPath,
        $AceGUIDsByResolvedID,
        $ACEsByGUID,
        $PrincipalsByResolvedID,
        $ACLsByPath,
        [Hashtable]$TargetPath,
        [Hashtable]$Children,
        [String]$ThisHostName = (HOSTNAME.EXE),
        [String]$WhoAmI = (whoami.EXE),
        [Hashtable]$LogBuffer = @{},
        [ValidateSet('Silent', 'Quiet', 'Success', 'Debug', 'Verbose', 'Output', 'Host', 'Warning', 'Error', 'Information', $null)]
        [String]$DebugOutputStream = 'Debug',
        [int]$ProgressParentId
    )
    $Progress = @{
        Activity = 'Expand-Permission'
    }
    if ($PSBoundParameters.ContainsKey('ProgressParentId')) {
        $Progress['ParentId'] = $ProgressParentId
        $Progress['Id'] = $ProgressParentId + 1
    } else {
        $Progress['Id'] = 0
    }
    Write-Progress @Progress -Status "0% : Group permission references, then expand them into objects" -CurrentOperation 'Resolve-SplitByParameter' -PercentComplete 0
    $Log = @{
        Buffer       = $LogBuffer
        ThisHostname = $ThisHostname
        Type         = $DebugOutputStream
        WhoAmI       = $WhoAmI
    }
    Write-LogMsg @Log -Text "Resolve-SplitByParameter -SplitBy $SplitBy"
    $HowToSplit = Resolve-SplitByParameter -SplitBy $SplitBy
    Write-LogMsg @Log -Text "`$SortedPaths = `$AceGuidByPath.Keys | Sort-Object"
    $SortedPaths = $AceGuidByPath.Keys | Sort-Object
    $CommonParams = @{
        ACEsByGUID             = $ACEsByGUID
        PrincipalsByResolvedID = $PrincipalsByResolvedID
    }
    if (
        $HowToSplit['account']
    ) {
        Write-LogMsg @Log -Text '$AccountPermissionReferences = Group-AccountPermissionReference -ID $PrincipalsByResolvedID.Keys -AceGuidByID $AceGUIDsByResolvedID -AceByGuid $ACEsByGUID'
        $AccountPermissionReferences = Group-AccountPermissionReference -ID $PrincipalsByResolvedID.Keys -AceGuidByID $AceGUIDsByResolvedID -AceByGuid $ACEsByGUID
        Write-LogMsg @Log -Text '$AccountPermissions = Expand-AccountPermissionReference -Reference $AccountPermissionReferences @CommonParams'
        $AccountPermissions = Expand-AccountPermissionReference -Reference $AccountPermissionReferences @CommonParams
    }
    if (
        $HowToSplit['item']
    ) {
        Write-LogMsg @Log -Text '$ItemPermissionReferences = Group-ItemPermissionReference @CommonParams -SortedPath $SortedPaths -AceGUIDsByPath $AceGuidByPath -ACLsByPath $ACLsByPath'
        $ItemPermissionReferences = Group-ItemPermissionReference -SortedPath $SortedPaths -AceGUIDsByPath $AceGuidByPath -ACLsByPath $ACLsByPath @CommonParams
        Write-LogMsg @Log -Text '$ItemPermissions = Expand-ItemPermissionReference -Reference $ItemPermissionReferences -ACLsByPath $ACLsByPath @CommonParams'
        $ItemPermissions = Expand-ItemPermissionReference -Reference $ItemPermissionReferences -ACLsByPath $ACLsByPath @CommonParams
    }
    if (
        $HowToSplit['none']
    ) {
        Write-LogMsg @Log -Text '$FlatPermissions = Expand-FlatPermissionReference -SortedPath $SortedPaths -AceGUIDsByPath $AceGuidByPath @CommonParams'
        $FlatPermissions = Expand-FlatPermissionReference -SortedPath $SortedPaths -AceGUIDsByPath $AceGuidByPath @CommonParams
    }
    if (
        $HowToSplit['target']
    ) {
        Write-LogMsg @Log -Text '$TargetPermissionReferences = Group-TargetPermissionReference -TargetPath $TargetPath -Children $Children -AceGUIDsByPath $AceGuidByPath -ACLsByPath $ACLsByPath -GroupBy $GroupBy -AceGUIDsByResolvedID $AceGUIDsByResolvedID @CommonParams'
        $TargetPermissionReferences = Group-TargetPermissionReference -TargetPath $TargetPath -Children $Children -AceGUIDsByPath $AceGuidByPath -ACLsByPath $ACLsByPath -GroupBy $GroupBy -AceGUIDsByResolvedID $AceGUIDsByResolvedID @CommonParams
        Write-LogMsg @Log -Text '$TargetPermissions = Expand-TargetPermissionReference -Reference $TargetPermissionReferences -GroupBy $GroupBy -ACLsByPath $ACLsByPath @CommonParams'
        $TargetPermissions = Expand-TargetPermissionReference -Reference $TargetPermissionReferences -GroupBy $GroupBy -ACLsByPath $ACLsByPath -AceGuidByPath $AceGuidByPath @CommonParams
    }
    Write-Progress @Progress -Completed
    return [PSCustomObject]@{
        AccountPermissions = $AccountPermissions
        FlatPermissions    = $FlatPermissions
        ItemPermissions    = $ItemPermissions
        TargetPermissions  = $TargetPermissions
        SplitBy            = $HowToSplit
    }
}
function Expand-PermissionTarget {
    param (
        [int]$RecurseDepth,
        [uint16]$ThreadCount = ((Get-CimInstance -ClassName CIM_Processor | Measure-Object -Sum -Property NumberOfLogicalProcessors).Sum),
        [String]$DebugOutputStream = 'Silent',
        [String]$ThisHostname = (HOSTNAME.EXE),
        [String]$WhoAmI = (whoami.EXE),
        [Hashtable]$LogBuffer = ([Hashtable]::Synchronized(@{})),
        [int]$ProgressParentId,
        [Hashtable]$TargetPath
    )
    $Progress = @{
        Activity = 'Expand-PermissionTarget'
    }
    if ($PSBoundParameters.ContainsKey('ProgressParentId')) {
        $Progress['ParentId'] = $ProgressParentId
        $Progress['Id'] = $ProgressParentId + 1
    } else {
        $Progress['Id'] = 0
    }
    $Targets = $TargetPath.Values | ForEach-Object { $_ }
    $TargetCount = $Targets.Count
    Write-Progress @Progress -Status "0% (item 0 of $TargetCount)" -CurrentOperation "Initializing..." -PercentComplete 0
    $Log = @{
        Buffer       = $LogBuffer
        ThisHostname = $ThisHostname
        Type         = $DebugOutputStream
        WhoAmI       = $WhoAmI
    }
    [Hashtable]$Output = [Hashtable]::Synchronized(@{})
    $GetSubfolderParams = @{
        LogBuffer         = $LogBuffer
        ThisHostname      = $ThisHostname
        DebugOutputStream = $DebugOutputStream
        WhoAmI            = $WhoAmI
        Output            = $Output
        RecurseDepth      = $RecurseDepth
        ErrorAction       = 'Continue'
    }
    if ($ThreadCount -eq 1 -or $TargetCount -eq 1) {
        [int]$ProgressInterval = [math]::max(($TargetCount / 100), 1)
        $IntervalCounter = 0
        $i = 0
        ForEach ($ThisFolder in $Targets) {
            $IntervalCounter++
            if ($IntervalCounter -eq $ProgressInterval) {
                [int]$PercentComplete = $i / $TargetCount * 100
                Write-Progress @Progress -Status "$PercentComplete% (item $($i + 1) of $TargetCount))" -CurrentOperation "Get-Subfolder '$($ThisFolder)'" -PercentComplete $PercentComplete
                $IntervalCounter = 0
            }
            $i++ 
            Write-LogMsg @Log -Text "Get-Subfolder -TargetPath '$ThisFolder' -RecurseDepth $RecurseDepth"
            Get-Subfolder -TargetPath $ThisFolder @GetSubfolderParams
        }
    } else {
        $SplitThreadParams = @{
            Command           = 'Get-Subfolder'
            InputObject       = $Targets
            InputParameter    = 'TargetPath'
            DebugOutputStream = $DebugOutputStream
            TodaysHostname    = $ThisHostname
            WhoAmI            = $WhoAmI
            LogBuffer       = $LogBuffer
            Threads           = $ThreadCount
            ProgressParentId  = $Progress['Id']
            AddParam          = $GetSubfolderParams
        }
        Split-Thread @SplitThreadParams
    }
    Write-Progress @Progress -Completed
    return $Output
}
function Find-ResolvedIDsWithAccess {
    param (
        $ItemPath,
        [Hashtable]$AceGUIDsByPath,
        [Hashtable]$ACEsByGUID,
        [Hashtable]$PrincipalsByResolvedID
    )
    $IDsWithAccess = @{}
    ForEach ($Item in $ItemPath) {
        $Guids = $AceGUIDsByPath[$Item]
        if ($Guids) {
            ForEach ($Guid in $Guids) {
                ForEach ($Ace in $ACEsByGUID[$Guid]) {
                    Add-CacheItem -Cache $IDsWithAccess -Key $Ace.IdentityReferenceResolved -Value $Guid -Type ([guid])
                    ForEach ($Member in $PrincipalsByResolvedID[$Ace.IdentityReferenceResolved].Members) {
                        Add-CacheItem -Cache $IDsWithAccess -Key $Member -Value $Guid -Type ([guid])
                    }
                }
            }
        }
    }
    return $IDsWithAccess
}
function Find-ServerFqdn {
    param (
        [string[]]$Known,
        [Hashtable]$TargetPath,
        [String]$ThisFqdn = ([System.Net.Dns]::GetHostByName((HOSTNAME.EXE)).HostName),
        [int]$ProgressParentId
    )
    $Progress = @{
        Activity = 'Find-ServerFqdn'
    }
    if ($PSBoundParameters.ContainsKey('ProgressParentId')) {
        $Progress['ParentId'] = $ProgressParentId
        $ProgressId = $ProgressParentId + 1
    } else {
        $ProgressId = 0
    }
    $Progress['Id'] = $ProgressId
    $Count = $TargetPath.Keys.Count
    Write-Progress @Progress -Status "0% (path 0 of $Count)" -CurrentOperation 'Initializing' -PercentComplete 0
    $UniqueValues = @{
        $ThisFqdn = $null
    }
    ForEach ($Value in $Known) {
        $UniqueValues[$Value] = $null
    }
    $ProgressStopWatch = [System.Diagnostics.Stopwatch]::new()
    $ProgressStopWatch.Start()
    $LastRemainder = [int]::MaxValue
    $i = 0
    ForEach ($ThisPath in $TargetPath.Keys) {
        $NewRemainder = $ProgressStopWatch.ElapsedTicks % 5000
        if ($NewRemainder -lt $LastRemainder) {
            $LastRemainder = $NewRemainder
            [int]$PercentComplete = $i / $Count * 100
            Write-Progress @Progress -Status "$PercentComplete% (path $($i + 1) of $Count)" -CurrentOperation "Find-ServerNameInPath '$ThisPath'" -PercentComplete $PercentComplete
        }
        $i++ 
        $UniqueValues[(Find-ServerNameInPath -LiteralPath $ThisPath -ThisFqdn $ThisFqdn)] = $null
    }
    Write-Progress @Progress -Completed
    return $UniqueValues.Keys
}
function Format-Permission {
    param (
        [PSCustomObject]$Permission,
        [string[]]$IgnoreDomain,
        [ValidateSet('account', 'item', 'none', 'target')]
        [String]$GroupBy = 'item',
        [ValidateSet('csv', 'html', 'js', 'json', 'prtgxml', 'xml')]
        [string[]]$FileFormat = @('csv', 'html', 'js', 'json', 'prtgxml', 'xml'),
        [ValidateSet('passthru', 'none', 'csv', 'html', 'js', 'json', 'prtgxml', 'xml')]
        [String]$OutputFormat = 'passthru',
        [cultureinfo]$Culture = (Get-Culture),
        [Hashtable]$ShortNameByID = [Hashtable]::Synchronized(@{}),
        [Hashtable]$ExcludeClassFilterContents = @{},
        [Hashtable]$IncludeFilterContents = [Hashtable]::Synchronized(@{})
    )
    $FormattedResults = @{}
    $Formats = Resolve-FormatParameter -FileFormat $FileFormat -OutputFormat $OutputFormat
    $Grouping = Resolve-GroupByParameter -GroupBy $GroupBy -HowToSplit $Permission.SplitBy
    if ($Permission.SplitBy['account']) {
        $FormattedResults['SplitByAccount'] = ForEach ($Account in $Permission.AccountPermissions) {
            $Selection = $Account
            $PermissionGroupingsWithChosenProperties = Invoke-Command -ScriptBlock $Grouping['Script'] -ArgumentList $Selection, $Culture, $IgnoreDomain, $IncludeFilterContents, $ExcludeClassFilterContents
            $PermissionsWithChosenProperties = Select-PermissionTableProperty -InputObject $Selection -GroupBy $GroupBy -ShortNameById $ShortNameByID -IncludeFilterContents $IncludeFilterContents -ExcludeClassFilterContents $ExcludeClassFilterContents
            $OutputProperties = @{
                Account      = $Account.Account
                Path         = $Permission.TargetPermissions.Path.FullName
                NetworkPaths = $Permission.TargetPermissions.NetworkPaths.Item
            }
            ForEach ($Format in $Formats) {
                $OutputProperties["$Format`Group"] = ConvertTo-PermissionGroup -Format $Format -Permission $PermissionGroupingsWithChosenProperties -GroupBy $GroupBy
                $OutputProperties[$Format] = ConvertTo-PermissionList -Format $Format -Permission $PermissionsWithChosenProperties -PermissionGrouping $Selection -ShortestPath @($Permission.TargetPermissions.NetworkPaths.Item.Path)[0] -GroupBy $GroupBy -HowToSplit $Permission.SplitBy
            }
            [PSCustomObject]$OutputProperties
        }
    }
    if ($Permission.SplitBy['item']) {
        $FormattedResults['SplitByItem'] = ForEach ($Item in $Permission.ItemPermissions) {
            $Selection = $Item.Access
            $PermissionGroupingsWithChosenProperties = Invoke-Command -ScriptBlock $Grouping['Script'] -ArgumentList $Selection, $Culture, $IgnoreDomain, $IncludeFilterContents, $ExcludeClassFilterContents
            $PermissionsWithChosenProperties = Select-PermissionTableProperty -InputObject $Selection -GroupBy $GroupBy -ShortNameById $ShortNameByID -IncludeFilterContents $IncludeFilterContents -ExcludeClassFilterContents $ExcludeClassFilterContents
            $OutputProperties = @{
                Item         = $Item.Item
                TargetPaths  = $Permission.TargetPermissions.Path.FullName
                NetworkPaths = $Permission.TargetPermissions.NetworkPaths.Item
            }
            ForEach ($Format in $Formats) {
                $OutputProperties["$Format`Group"] = ConvertTo-PermissionGroup -Format $Format -Permission $PermissionGroupingsWithChosenProperties -GroupBy $GroupBy
                $OutputProperties[$Format] = ConvertTo-PermissionList -Format $Format -Permission $PermissionsWithChosenProperties -PermissionGrouping $Selection -ShortestPath @($Permission.TargetPermissions.NetworkPaths.Item.Path)[0] -GroupBy $GroupBy -HowToSplit $Permission.SplitBy
            }
            [PSCustomObject]$OutputProperties
        }
    }
    if ($Permission.SplitBy['target']) {
        $FormattedResults['SplitByTarget'] = ForEach ($Target in $Permission.TargetPermissions) {
            [PSCustomObject]@{
                PSTypeName   = 'Permission.TargetPermission'
                Path         = $Target.Path
                NetworkPaths = ForEach ($NetworkPath in $Target.NetworkPaths) {
                    $Prop = $Grouping['Property']
                    if ($Prop -eq 'items') {
                        $Selection = [System.Collections.Generic.List[PSCustomObject]]::new()
                        $Selection.Add([PSCustomObject]@{
                                PSTypeName = 'Permission.ItemPermission'
                                Item       = $NetworkPath.Item
                                Access     = $NetworkPath.Access
                            })
                        $Selection.AddRange([PSCustomObject[]]$NetworkPath.$Prop)
                    } else {
                        $Selection = $NetworkPath.$Prop
                    }
                    $PermissionGroupingsWithChosenProperties = Invoke-Command -ScriptBlock $Grouping['Script'] -ArgumentList $Selection, $Culture, $ShortNameByID, $IncludeFilterContents, $ExcludeClassFilterContents
                    $PermissionsWithChosenProperties = Select-PermissionTableProperty -InputObject $Selection -GroupBy $GroupBy -ShortNameById $ShortNameByID -IncludeFilterContents $IncludeFilterContents -ExcludeClassFilterContents $ExcludeClassFilterContents
                    $OutputProperties = @{
                        PSTypeName = "Permission.Parent$($Culture.TextInfo.ToTitleCase($GroupBy))Permission"
                        Item       = $NetworkPath.Item
                    }
                    ForEach ($Format in $Formats) {
                        $FormatString = $Format
                        if ($Format -eq 'js') {
                            $FormatString = 'json'
                        }
                        $OutputProperties["$FormatString`Group"] = ConvertTo-PermissionGroup -Format $Format -Permission $PermissionGroupingsWithChosenProperties -GroupBy $GroupBy -HowToSplit $Permission.SplitBy
                        $OutputProperties[$FormatString] = ConvertTo-PermissionList -Format $Format -Permission $PermissionsWithChosenProperties -PermissionGrouping $Selection -ShortestPath $NetworkPath.Item.Path -GroupBy $GroupBy -HowToSplit $Permission.SplitBy -NetworkPath $NetworkPath.Item.Path -Analysis $Analysis
                    }
                    [PSCustomObject]$OutputProperties
                }
            }
        }
    }
    return $FormattedResults
}
function Format-TimeSpan {
    param (
        [timespan]$TimeSpan,
        [string[]]$UnitsToResolve = @('day', 'hour', 'minute', 'second', 'millisecond')
    )
    $StringBuilder = [System.Text.StringBuilder]::new()
    $aUnitWithAValueHasBeenFound = $false
    foreach ($Unit in $UnitsToResolve) {
        if ($TimeSpan."$Unit`s") {
            if ($aUnitWithAValueHasBeenFound) {
                $null = $StringBuilder.Append(", ")
            }
            $aUnitWithAValueHasBeenFound = $true
            if ($TimeSpan."$Unit`s" -eq 1) {
                $null = $StringBuilder.Append("$($TimeSpan."$Unit`s") $Unit")
            } else {
                $null = $StringBuilder.Append("$($TimeSpan."$Unit`s") $Unit`s")
            }
        }
    }
    $StringBuilder.ToString()
}
function Get-AccessControlList {
    param (
        [Hashtable]$TargetPath,
        [uint16]$ThreadCount = ((Get-CimInstance -ClassName CIM_Processor | Measure-Object -Sum -Property NumberOfLogicalProcessors).Sum),
        [String]$DebugOutputStream = 'Debug',
        [String]$TodaysHostname = (HOSTNAME.EXE),
        [String]$WhoAmI = (whoami.EXE),
        [Hashtable]$LogBuffer = ([Hashtable]::Synchronized(@{})),
        [System.Collections.Concurrent.ConcurrentDictionary[String, PSCustomObject]]$OwnerCache = [System.Collections.Concurrent.ConcurrentDictionary[String, PSCustomObject]]::new(),
        [int]$ProgressParentId,
        [Hashtable]$Output = [Hashtable]::Synchronized(@{})
    )
    $Progress = @{
        Activity = 'Get-AccessControlList'
    }
    if ($PSBoundParameters.ContainsKey('ProgressParentId')) {
        $Progress['ParentId'] = $ProgressParentId
        $ProgressId = $ProgressParentId + 1
    } else {
        $ProgressId = 0
    }
    $Progress['Id'] = $ProgressId
    $ChildProgress = @{
        Activity = 'Get access control lists for parent and child items'
        Id       = $ProgressId + 1
        ParentId = $ProgressId
    }
    $GrandChildProgress = @{
        Activity = 'Get access control lists'
        Id       = $ProgressId + 2
        ParentId = $ProgressId + 1
    }
    Write-Progress @Progress -Status '0% (step 1 of 2) Get access control lists for parent and child items' -CurrentOperation 'Get access control lists for parent and child items' -PercentComplete 0
    $GetDirectorySecurity = @{
        LogBuffer         = $LogBuffer
        ThisHostname      = $TodaysHostname
        DebugOutputStream = $DebugOutputStream
        WhoAmI            = $WhoAmI
        OwnerCache        = $OwnerCache
        ACLsByPath        = $Output
    }
    $TargetIndex = 0
    $ParentCount = $TargetPath.Keys.Count
    if ($ThreadCount -eq 1) {
        ForEach ($Parent in $TargetPath.Keys) {
            [int]$PercentComplete = $TargetIndex / $ParentCount * 100
            $TargetIndex++
            Write-Progress @ChildProgress -Status "$PercentComplete% (parent $TargetIndex of $ParentCount) Get access control lists" -CurrentOperation $Parent -PercentComplete $PercentComplete
            Write-Progress @GrandChildProgress -Status "0% (parent) Get-DirectorySecurity -IncludeInherited" -CurrentOperation $Parent -PercentComplete 0
            Get-DirectorySecurity -LiteralPath $Parent -IncludeInherited @GetDirectorySecurity
            $Children = $TargetPath[$Parent]
            $ChildCount = $Children.Count
            [int]$ProgressInterval = [math]::max(($ChildCount / 100), 1)
            $IntervalCounter = 0
            $ChildIndex = 0
            ForEach ($Child in $Children) {
                $IntervalCounter++
                if ($IntervalCounter -eq $ProgressInterval -or $ChildIndex -eq 0) {
                    [int]$PercentComplete = $ChildIndex / $ChildCount * 100
                    Write-Progress @GrandChildProgress -Status "$PercentComplete% (child $($ChildIndex + 1) of $ChildCount) Get-DirectorySecurity" -CurrentOperation $Child -PercentComplete $PercentComplete
                    $IntervalCounter = 0
                }
                $ChildIndex++ 
                Get-DirectorySecurity -LiteralPath $Child @GetDirectorySecurity
            }
            Write-Progress @GrandChildProgress -Completed
        }
        Write-Progress @ChildProgress -Completed
    } else {
        ForEach ($Parent in $TargetPath.Keys) {
            [int]$PercentComplete = $TargetIndex / $ParentCount * 100
            $TargetIndex++
            Write-Progress @ChildProgress -Status "$PercentComplete% (parent $TargetIndex of $ParentCount) Get access control lists" -CurrentOperation $Parent -PercentComplete $PercentComplete
            Get-DirectorySecurity -LiteralPath $Parent -IncludeInherited @GetDirectorySecurity
            $Children = $TargetPath[$Parent]
            $SplitThread = @{
                Command           = 'Get-DirectorySecurity'
                InputObject       = $Children
                InputParameter    = 'LiteralPath'
                DebugOutputStream = $DebugOutputStream
                TodaysHostname    = $TodaysHostname
                WhoAmI            = $WhoAmI
                LogBuffer         = $LogBuffer
                Threads           = $ThreadCount
                ProgressParentId  = $ChildProgress['Id']
                AddParam          = $GetDirectorySecurity
            }
            Split-Thread @SplitThread
        }
        Write-Progress @ChildProgress -Completed
    }
    Write-Progress @Progress -Status '50% (step 2 of 2) Find non-inherited owners for parent and child items' -CurrentOperation 'Find non-inherited owners for parent and child items' -PercentComplete 50
    $ChildProgress['Activity'] = 'Get ACL owners'
    $GrandChildProgress['Activity'] = 'Get ACL owners'
    $GetOwnerAce = @{
        OwnerCache = $OwnerCache
        ACLsByPath = $Output
    }
    $ParentIndex = 0
    if ($ThreadCount -eq 1) {
        ForEach ($Parent in $TargetPath.Keys) {
            [int]$PercentComplete = $ParentIndex / $ParentCount * 100
            $ParentIndex++
            Write-Progress @ChildProgress -Status "$PercentComplete% (parent $ParentIndex of $ParentCount) Find non-inherited ACL Owners" -CurrentOperation $Parent -PercentComplete $PercentComplete
            Write-Progress @GrandChildProgress -Status "0% (parent) Get-OwnerAce" -CurrentOperation $Parent -PercentComplete $PercentComplete
            Get-OwnerAce -Item $Parent @GetOwnerAce
            $Children = $TargetPath[$Parent]
            $ChildCount = $Children.Count
            [int]$ProgressInterval = [math]::max(($ChildCount / 100), 1)
            $IntervalCounter = 0
            $ChildIndex = 0
            ForEach ($Child in $Children) {
                $IntervalCounter++
                if ($IntervalCounter -eq $ProgressInterval -or $ChildIndex -eq 0) {
                    [int]$PercentComplete = $ChildIndex / $ChildCount * 100
                    Write-Progress @GrandChildProgress -Status "$PercentComplete% (child $($ChildIndex + 1) of $ChildCount)) Get-OwnerAce" -CurrentOperation $Child -PercentComplete $PercentComplete
                    $IntervalCounter = 0
                }
                $ChildIndex++
                Get-OwnerAce -Item $Child @GetOwnerAce
            }
            Write-Progress @GrandChildProgress -Completed
        }
        Write-Progress @ChildProgress -Completed
    } else {
        ForEach ($Parent in $TargetPath.Keys) {
            [int]$PercentComplete = $ParentIndex / $ParentCount * 100
            $ParentIndex++
            Write-Progress @ChildProgress -Status "$PercentComplete% (parent $ParentIndex of $ParentCount) Find non-inherited ACL Owners" -CurrentOperation $Parent -PercentComplete $PercentComplete
            Get-OwnerAce -Item $Parent @GetOwnerAce
            $Children = $TargetPath[$Parent]
            $SplitThread = @{
                Command           = 'Get-OwnerAce'
                InputObject       = $Children
                InputParameter    = 'Item'
                DebugOutputStream = $DebugOutputStream
                TodaysHostname    = $TodaysHostname
                WhoAmI            = $WhoAmI
                LogBuffer       = $LogBuffer
                Threads           = $ThreadCount
                ProgressParentId  = $ChildProgress['Id']
                AddParam          = $GetOwnerAce
            }
            Split-Thread @SplitThread
        }
    }
    Write-Progress @Progress -Completed
}
function Get-CachedCimInstance {
    param (
        [String]$ComputerName,
        [String]$ClassName,
        [String]$Namespace,
        [String]$Query,
        [Hashtable]$CimCache = ([Hashtable]::Synchronized(@{})),
        [ValidateSet('Silent', 'Quiet', 'Success', 'Debug', 'Verbose', 'Output', 'Host', 'Warning', 'Error', 'Information', $null)]
        [String]$DebugOutputStream = 'Debug',
        [String]$ThisHostName = (HOSTNAME.EXE),
        [String]$ThisFqdn = ([System.Net.Dns]::GetHostByName((HOSTNAME.EXE)).HostName),
        [String]$WhoAmI = (whoami.EXE),
        [Hashtable]$LogBuffer = ([Hashtable]::Synchronized(@{})),
        [Parameter(Mandatory)]
        [String]$KeyProperty,
        [string[]]$CacheByProperty = $KeyProperty
    )
    $Log = @{
        Buffer       = $LogBuffer
        ThisHostname = $ThisHostname
        Type         = $DebugOutputStream
        WhoAmI       = $WhoAmI
    }
    if ($PSBoundParameters.ContainsKey('ClassName')) {
        $InstanceCacheKey = "$ClassName`By$KeyProperty"
    } else {
        $InstanceCacheKey = "$Query`By$KeyProperty"
    }
    $CimCacheResult = $CimCache[$ComputerName]
    if ($CimCacheResult) {
        Write-LogMsg @Log -Text "  cache hit for '$ComputerName'"
        $CimCacheSubresult = $CimCacheResult[$InstanceCacheKey]
        if ($CimCacheSubresult) {
            Write-LogMsg @Log -Text "  instance cache hit for '$InstanceCacheKey' on '$ComputerName'"
            return $CimCacheSubresult.Values
        } else {
            Write-LogMsg @Log -Text "  instance cache miss for '$InstanceCacheKey' on '$ComputerName'"
        }
    } else {
        Write-LogMsg @Log -Text "  cache miss for '$ComputerName'"
    }
    $CimSession = Get-CachedCimSession -ComputerName $ComputerName -CimCache $CimCache -ThisFqdn $ThisFqdn @Log
    if ($CimSession) {
        $GetCimInstanceParams = @{
            CimSession  = $CimSession
            ErrorAction = 'SilentlyContinue'
        }
        if ($Namespace) {
            $GetCimInstanceParams['Namespace'] = $Namespace
        }
        if ($PSBoundParameters.ContainsKey('ClassName')) {
            Write-LogMsg @Log -Text "Get-CimInstance -ClassName $ClassName -CimSession `$CimSession"
            $CimInstance = Get-CimInstance -ClassName $ClassName @GetCimInstanceParams
        }
        if ($PSBoundParameters.ContainsKey('Query')) {
            Write-LogMsg @Log -Text "Get-CimInstance -Query '$Query' -CimSession `$CimSession"
            $CimInstance = Get-CimInstance -Query $Query @GetCimInstanceParams
        }
        if ($CimInstance) {
            $InstanceCache = [Hashtable]::Synchronized(@{})
            ForEach ($Prop in $CacheByProperty) {
                if ($PSBoundParameters.ContainsKey('ClassName')) {
                    $InstanceCacheKey = "$ClassName`By$Prop"
                } else {
                    $InstanceCacheKey = "$Query`By$Prop"
                }
                ForEach ($Instance in $CimInstance) {
                    $InstancePropertyValue = $Instance.$Prop
                    Write-LogMsg @Log -Text " # Add '$InstancePropertyValue' to the '$InstanceCacheKey' cache for '$ComputerName'"
                    $InstanceCache[$InstancePropertyValue] = $Instance
                }
                $CimCache[$ComputerName][$InstanceCacheKey] = $InstanceCache
            }
            return $CimInstance
        }
    }
}
function Get-CachedCimSession {
    param (
        [String]$ComputerName,
        [Hashtable]$CimCache = ([Hashtable]::Synchronized(@{})),
        [ValidateSet('Silent', 'Quiet', 'Success', 'Debug', 'Verbose', 'Output', 'Host', 'Warning', 'Error', 'Information', $null)]
        [String]$DebugOutputStream = 'Debug',
        [String]$ThisHostName = (HOSTNAME.EXE),
        [String]$ThisFqdn = ([System.Net.Dns]::GetHostByName((HOSTNAME.EXE)).HostName),
        [String]$WhoAmI = (whoami.EXE),
        [Hashtable]$LogBuffer = ([Hashtable]::Synchronized(@{}))
    )
    $Log = @{
        Buffer       = $LogBuffer
        ThisHostname = $ThisHostname
        Type         = $DebugOutputStream
        WhoAmI       = $WhoAmI
    }
    $CimCacheResult = $CimCache[$ComputerName]
    if ($CimCacheResult) {
        Write-LogMsg @Log -Text "  cache hit for '$ComputerName'"
        $CimCacheSubresult = $CimCacheResult['CimSession']
        if ($CimCacheSubresult) {
            Write-LogMsg @Log -Text "  session cache hit for '$ComputerName'"
            return $CimCacheSubresult
        } else {
            Write-LogMsg @Log -Text "  session cache miss for '$ComputerName'"
        }
    } else {
        Write-LogMsg @Log -Text "  cache miss for '$ComputerName'"
        $CimCache[$ComputerName] = [Hashtable]::Synchronized(@{})
    }
    if (
        $ComputerName -eq $ThisHostname -or
        $ComputerName -eq "$ThisHostname." -or
        $ComputerName -eq $ThisFqdn -or
        $ComputerName -eq "$ThisFqdn." -or
        $ComputerName -eq 'localhost' -or
        $ComputerName -eq '127.0.0.1' -or
        [String]::IsNullOrEmpty($ComputerName)
    ) {
        Write-LogMsg @Log -Text '$CimSession = New-CimSession'
        $CimSession = New-CimSession
    } else {
        Write-LogMsg @Log -Text "`$CimSession = New-CimSession -ComputerName $ComputerName"
        $CimSession = New-CimSession -ComputerName $ComputerName -ErrorAction SilentlyContinue
    }
    if ($CimSession) {
        $CimCache[$ComputerName]['CimSession'] = $CimSession
        return $CimSession
    }
}
function Get-PermissionPrincipal {
    param (
        [ValidateSet('Silent', 'Quiet', 'Success', 'Debug', 'Verbose', 'Output', 'Host', 'Warning', 'Error', 'Information', $null)]
        [String]$DebugOutputStream = 'Debug',
        [int]$ThreadCount = (Get-CimInstance -ClassName CIM_Processor | Measure-Object -Sum -Property NumberOfLogicalProcessors).Sum,
        [Hashtable]$PrincipalsByResolvedID = ([Hashtable]::Synchronized(@{})),
        [Hashtable]$ACEsByResolvedID = ([Hashtable]::Synchronized(@{})),
        [Hashtable]$CimCache = ([Hashtable]::Synchronized(@{})),
        [Hashtable]$DirectoryEntryCache = ([Hashtable]::Synchronized(@{})),
        [Hashtable]$DomainsByNetbios = ([Hashtable]::Synchronized(@{})),
        [Hashtable]$DomainsBySid = ([Hashtable]::Synchronized(@{})),
        [Hashtable]$DomainsByFqdn = ([Hashtable]::Synchronized(@{})),
        [String]$ThisFqdn = ([System.Net.Dns]::GetHostByName((HOSTNAME.EXE)).HostName),
        [String]$ThisHostName = (HOSTNAME.EXE),
        [String]$WhoAmI = (whoami.EXE),
        [Hashtable]$LogBuffer = ([Hashtable]::Synchronized(@{})),
        [switch]$NoGroupMembers,
        [int]$ProgressParentId,
        [String]$CurrentDomain = (Get-CurrentDomain)
    )
    $Progress = @{
        Activity = 'Get-PermissionPrincipal'
    }
    if ($PSBoundParameters.ContainsKey('ProgressParentId')) {
        $Progress['ParentId'] = $ProgressParentId
        $Progress['Id'] = $ProgressParentId + 1
    } else {
        $Progress['Id'] = 0
    }
    [string[]]$IDs = $ACEsByResolvedID.Keys
    $Count = $IDs.Count
    Write-Progress @Progress -Status "0% (identity 0 of $Count) ConvertFrom-IdentityReferenceResolved" -CurrentOperation 'Initialize' -PercentComplete 0
    $Log = @{
        Buffer       = $LogBuffer
        ThisHostname = $ThisHostname
        Type         = $DebugOutputStream
        WhoAmI       = $WhoAmI
    }
    $ADSIConversionParams = @{
        DirectoryEntryCache    = $DirectoryEntryCache
        DomainsBySID           = $DomainsBySID
        DomainsByNetbios       = $DomainsByNetbios
        DomainsByFqdn          = $DomainsByFqdn
        ThisHostName           = $ThisHostName
        ThisFqdn               = $ThisFqdn
        WhoAmI                 = $WhoAmI
        LogBuffer              = $LogBuffer
        CimCache               = $CimCache
        DebugOutputStream      = $DebugOutputStream
        PrincipalsByResolvedID = $PrincipalsByResolvedID 
        ACEsByResolvedID       = $ACEsByResolvedID 
        CurrentDomain          = $CurrentDomain
    }
    if ($ThreadCount -eq 1) {
        if ($NoGroupMembers) {
            $ADSIConversionParams['NoGroupMembers'] = $true
        }
        [int]$ProgressInterval = [math]::max(($Count / 100), 1)
        $IntervalCounter = 0
        $i = 0
        ForEach ($ThisID in $IDs) {
            $IntervalCounter++
            if ($IntervalCounter -eq $ProgressInterval) {
                [int]$PercentComplete = $i / $Count * 100
                Write-Progress @Progress -Status "$PercentComplete% (identity $($i + 1) of $Count) ConvertFrom-IdentityReferenceResolved" -CurrentOperation $ThisID -PercentComplete $PercentComplete
                $IntervalCounter = 0
            }
            $i++
            Write-LogMsg @Log -Text "ConvertFrom-IdentityReferenceResolved -IdentityReference '$ThisID'"
            ConvertFrom-IdentityReferenceResolved -IdentityReference $ThisID @ADSIConversionParams
        }
    } else {
        if ($NoGroupMembers) {
            $ADSIConversionParams['AddSwitch'] = 'NoGroupMembers'
        }
        $SplitThreadParams = @{
            Command              = 'ConvertFrom-IdentityReferenceResolved'
            InputObject          = $IDs
            InputParameter       = 'IdentityReference'
            ObjectStringProperty = 'Name'
            TodaysHostname       = $ThisHostname
            WhoAmI               = $WhoAmI
            LogBuffer          = $LogBuffer
            Threads              = $ThreadCount
            ProgressParentId     = $Progress['Id']
            AddParam             = $ADSIConversionParams
        }
        Write-LogMsg @Log -Text "Split-Thread -Command 'ConvertFrom-IdentityReferenceResolved' -InputParameter 'IdentityReference' -InputObject `$IDs"
        Split-Thread @SplitThreadParams
    }
    Write-Progress @Progress -Completed
}
function Get-TimeZoneName {
    param (
        [datetime]$Time,
        [Microsoft.Management.Infrastructure.CimInstance]$TimeZone = (Get-CimInstance -ClassName Win32_TimeZone)
    )
    if ($Time.IsDaylightSavingTime()) {
        return $TimeZone.DaylightName
    } else {
        return $TimeZone.StandardName
    }
}
function Initialize-Cache {
    param (
        [string[]]$Fqdn,
        [ValidateSet('Silent', 'Quiet', 'Success', 'Debug', 'Verbose', 'Output', 'Host', 'Warning', 'Error', 'Information', $null)]
        [String]$DebugOutputStream = 'Debug',
        [int]$ThreadCount = (Get-CimInstance -ClassName CIM_Processor | Measure-Object -Sum -Property NumberOfLogicalProcessors).Sum,
        [Hashtable]$CimCache = ([Hashtable]::Synchronized(@{})),
        [Hashtable]$DirectoryEntryCache = ([Hashtable]::Synchronized(@{})),
        [Hashtable]$DomainsByNetbios = ([Hashtable]::Synchronized(@{})),
        [Hashtable]$DomainsBySid = ([Hashtable]::Synchronized(@{})),
        [Hashtable]$DomainsByFqdn = ([Hashtable]::Synchronized(@{})),
        [String]$ThisHostName = (HOSTNAME.EXE),
        [String]$ThisFqdn = ([System.Net.Dns]::GetHostByName((HOSTNAME.EXE)).HostName),
        [String]$WhoAmI = (whoami.EXE),
        [Hashtable]$LogBuffer = ([Hashtable]::Synchronized(@{})),
        [int]$ProgressParentId
    )
    $Progress = @{
        Activity = 'Initialize-Cache'
    }
    if ($PSBoundParameters.ContainsKey('ProgressParentId')) {
        $Progress['ParentId'] = $ProgressParentId
        $ProgressId = $ProgressParentId + 1
    } else {
        $ProgressId = 0
    }
    $Progress['Id'] = $ProgressId
    $Count = $Fqdn.Count
    $Log = @{
        Buffer       = $LogBuffer
        ThisHostname = $ThisHostname
        Type         = $DebugOutputStream
        WhoAmI       = $WhoAmI
    }
    $GetAdsiServer = @{
        DirectoryEntryCache = $DirectoryEntryCache
        DomainsByFqdn       = $DomainsByFqdn
        DomainsByNetbios    = $DomainsByNetbios
        DomainsBySid        = $DomainsBySid
        ThisHostName        = $ThisHostName
        ThisFqdn            = $ThisFqdn
        WhoAmI              = $WhoAmI
        LogBuffer           = $LogBuffer
        CimCache            = $CimCache
    }
    if ($ThreadCount -eq 1) {
        $i = 0
        ForEach ($ThisServerName in $Fqdn) {
            [int]$PercentComplete = $i / $Count * 100
            Write-Progress -Status "$PercentComplete% (FQDN $($i + 1) of $Count) Get-AdsiServer" -CurrentOperation "Get-AdsiServer '$ThisServerName'" -PercentComplete $PercentComplete @Progress
            $i++ 
            Write-LogMsg @Log -Text "Get-AdsiServer -Fqdn '$ThisServerName'"
            $null = Get-AdsiServer -Fqdn $ThisServerName @GetAdsiServer
        }
    } else {
        $SplitThread = @{
            Command          = 'Get-AdsiServer'
            InputObject      = $Fqdn
            InputParameter   = 'Fqdn'
            TodaysHostname   = $ThisHostname
            WhoAmI           = $WhoAmI
            LogBuffer      = $LogBuffer
            Timeout          = 600
            Threads          = $ThreadCount
            ProgressParentId = $ProgressParentId
            AddParam         = $GetAdsiServer
        }
        Write-LogMsg @Log -Text "Split-Thread -Command 'Get-AdsiServer' -InputParameter AdsiServer -InputObject @('$($Fqdn -join "',")')"
        $null = Split-Thread @SplitThread
    }
    Write-Progress @Progress -Completed
}
function Invoke-PermissionAnalyzer {
    param (
        [hashtable]$AclByPath,
        [hashtable]$AllowDisabledInheritance,
        [hashtable]$PrincipalByID,
        [scriptblock]$AccountConvention = { $true }
    )
    $ItemsWithBrokenInheritance = $AclByPath.Keys |
    Where-Object -FilterScript {
        $AclByPath[$_].AreAccessRulesProtected -and
        -not $AllowDisabledInheritance[$_]
    }
    $ViolatesAccountConvention = [scriptblock]::Create("!($AccountConvention)")
    $NonCompliantAccounts = $PrincipalByID.Values |
    Where-Object -FilterScript { $_.SchemaClassName -eq 'Group' } |
    Where-Object -FilterScript $ViolatesAccountConvention
    if ($NonCompliantAccounts) {
        $AceGUIDsWithNonCompliantAccounts = $AceGuidByID[$NonCompliantAccounts]
    }
    if ($AceGUIDsWithNonCompliantAccounts) {
        $ACEsWithNonCompliantAccounts = $AceByGUID[$AceGUIDsWithNonCompliantAccounts]
    }
    $ACEsWithUsers = [System.Collections.Generic.List[PSCustomObject]]::new()
    $ACEsWithUnresolvedSIDs = [System.Collections.Generic.List[PSCustomObject]]::new()
    $ACEsWithCreatorOwner = [System.Collections.Generic.List[PSCustomObject]]::new()
    ForEach ($ACE in $AceByGUID.Values) {
        if (
            $PrincipalByID[$ACE.IdentityReferenceResolved].SchemaClassName -eq 'User' -and
            $_.IdentityReferenceSID -ne 'S-1-5-18' -and 
            $_.SourceOfAccess -ne 'Ownership' 
        ) {
            $ACEsWithUsers.Add($ACE)
        }
        if ( $ACE.IdentityReferenceResolved -like "*$($ACE.IdentityReferenceSID)*" ) {
            $ACEsWithUnresolvedSIDs.Add($ACE)
        }
        if ( $ACE.IdentityReferenceResolved -match 'CREATOR OWNER' ) {
            $ACEsWithCreatorOwner.Add($ACE)
        }
    }
    return [PSCustomObject]@{
        ACEsWithCreatorOwner         = $ACEsWithCreatorOwner
        ACEsWithNonCompliantAccounts = $ACEsWithNonCompliantAccounts
        ACEsWithUsers                = $ACEsWithUsers
        ACEsWithUnresolvedSIDs       = $ACEsWithUnresolvedSIDs
        ItemsWithBrokenInheritance   = $ItemsWithBrokenInheritance
        NonCompliantAccounts         = $NonCompliantAccounts
    }
}
function Invoke-PermissionCommand {
    param (
        [String]$Command
    )
    $Steps = [System.Collections.Specialized.OrderedDictionary]::New()
    $Steps.Add(
        'Get the NTAccount caption of the user running the script, with the correct capitalization',
        { HOSTNAME.EXE }
    )
    $Steps.Add(
        'Get the hostname of the computer running the script',
        { Get-CurrentWhoAmI -LogBuffer $LogBuffer -ThisHostName $ThisHostname }
    )
    $LogParams = @{
        Buffer       = $LogBuffer
        ThisHostname = $ThisHostname
        WhoAmI       = $WhoAmI
    }
    $StepCount = $Steps.Count
    Write-LogMsg @LogParams -Type Verbose -Text $Command
    $ScriptBlock = $Steps[$Command]
    Write-LogMsg @LogParams -Type Debug -Text $ScriptBlock
    Invoke-Command -ScriptBlock $ScriptBlock
}
function Out-Permission {
    param (
        [ValidateSet('passthru', 'none', 'csv', 'html', 'js', 'json', 'prtgxml', 'xml')]
        [string]$OutputFormat = 'passthru',
        [ValidateSet('account', 'item', 'none', 'target')]
        [string]$GroupBy = 'item',
        [hashtable]$FormattedPermission
    )
    ForEach ($Split in 'target', 'item', 'account') {
        $ThisFormat = $FormattedPermission["SplitBy$Split"]
        if ($ThisFormat) {
            $ThisFormat
        }
    }
}
function Out-PermissionFile {
    param (
        [string[]]$ExcludeAccount,
        [string[]]$ExcludeClass = @('group', 'computer'),
        $IgnoreDomain,
        [string[]]$TargetPath,
        [switch]$NoMembers,
        $OutputDir,
        [String]$WhoAmI = (whoami.EXE),
        $ThisFqdn,
        $StopWatch,
        $Title,
        $Permission,
        $FormattedPermission,
        $LogParams,
        $RecurseDepth,
        $LogFileList,
        $ReportInstanceId,
        [Hashtable]$AceByGUID,
        [Hashtable]$AclByPath,
        [Hashtable]$PrincipalByID,
        [Hashtable]$Parent,
        [int[]]$Detail = @(0..10),
        [cultureinfo]$Culture = (Get-Culture),
        [ValidateSet('csv', 'html', 'js', 'json', 'prtgxml', 'xml')]
        [string[]]$FileFormat = @('csv', 'html', 'js', 'json', 'prtgxml', 'xml'),
        [ValidateSet('passthru', 'none', 'csv', 'html', 'js', 'json', 'prtgxml', 'xml')]
        [String]$OutputFormat = 'passthru',
        [ValidateSet('account', 'item', 'none', 'target')]
        [String]$GroupBy = 'item',
        [ValidateSet('none', 'all', 'target', 'item', 'account')]
        [string[]]$SplitBy = 'target',
        [PSCustomObject]$BestPracticeEval
    )
    $Formats = Resolve-FormatParameter -FileFormat $FileFormat -OutputFormat $OutputFormat
    $DetailStrings = @(
        'Item paths',
        'Resolved item paths (server names and DFS targets resolved)',
        'Expanded resolved item paths (resolved target paths expanded into their children)',
        'Access lists',
        'Access rules (resolved identity references and inheritance flags)',
        'Accounts with access',
        'Expanded access rules (expanded with account info)', 
        'Formatted permissions',
        'Best Practice issues',
        'Custom sensor output for Paessler PRTG Network Monitor',
        'Permission report'
    )
    $UnsplitDetail = $Detail | Where-Object -FilterScript { $_ -le 5 -or $_ -in 8, 9 }
    $SplitDetail = $Detail | Where-Object -FilterScript { $_ -gt 5 -and $_ -notin 8, 9 }
    $DetailScripts = @(
        { $TargetPath },
        { ForEach ($Key in $Parent.Keys) {
                [PSCustomObject]@{
                    OriginalTargetPath  = $Key
                    ResolvedNetworkPath = $Parent[$Key]
                }
            }
        },
        { $ACLsByPath.Keys },
        { $ACLsByPath.Values },
        { ForEach ($val in $AceByGUID.Values) { $val } },
        { ForEach ($val in $PrincipalsByResolvedID.Values) { $val } },
        {
            switch ($SplitBy) {
                'account' { $Permission.AccountPermissions ; break }
                'none' { $Permission.FlatPermissions ; break }
                'item' { $Permission.ItemPermissions ; break }
                'target' { $Permission.TargetPermissions ; break }
            }
        },
        { $Permissions.Data },
        { $BestPracticeEval },
        { ConvertTo-PermissionPrtgXml -Analysis $Analysis },
        {}
    )
    ForEach ($Split in $Permission.SplitBy.Keys) {
        switch ($Split) {
            'account' {
                $Subproperty = ''
                $FileNameProperty = $Split
                $FileNameSubproperty = 'ResolvedAccountName'
                $ReportFiles = $FormattedPermission["SplitBy$Split"]
                break
            }
            'item' {
                $Subproperty = ''
                $FileNameProperty = $Split
                $FileNameSubproperty = 'Path'
                $ReportFiles = $FormattedPermission["SplitBy$Split"]
                break
            }
            'none' {
                $Subproperty = 'NetworkPaths'
                $FileNameProperty = ''
                $FileNameSubproperty = 'Path'
                $ReportFiles = [PSCustomObject]@{
                    NetworkPaths = $FormattedPermission['SplitByTarget'].NetworkPaths
                    Path         = $FormattedPermission['SplitByTarget'].Path.FullName
                }
                break
            }
            'target' {
                $Subproperty = 'NetworkPaths'
                $FileNameProperty = ''
                $FileNameSubproperty = 'Path'
                $ReportFiles = $FormattedPermission["SplitBy$Split"]
                break
            }
        }
        ForEach ($Format in $Formats) {
            $FormatString = $Format
            $FormatDir = "$OutputDir\$Format"
            $null = New-Item -Path $FormatDir -ItemType Directory -ErrorAction SilentlyContinue
            switch ($Format) {
                'csv' {
                    $DetailExports = @(
                        { $args[0] | Out-File -LiteralPath $args[1] },
                        { $args[0] | Export-Csv -NoTypeInformation -LiteralPath $args[1] },
                        { $args[0] | Out-File -LiteralPath $args[1] },
                        { $args[0] | Export-Csv -NoTypeInformation -LiteralPath $args[1] },
                        { $args[0] | Export-Csv -NoTypeInformation -LiteralPath $args[1] },
                        { $args[0] | Export-Csv -NoTypeInformation -LiteralPath $args[1] },
                        { $args[0] | Export-Csv -NoTypeInformation -LiteralPath $args[1] },
                        { $args[0] | Out-File -LiteralPath $args[1] },
                        { },
                        { },
                        { }
                    )
                    $DetailScripts[10] = { }
                    break
                }
                'html' {
                    $DetailExports = @(
                        { $args[0] | Out-File -LiteralPath $args[1] },
                        { $args[0] | ConvertTo-Html -Fragment | Out-File -LiteralPath $args[1] },
                        { $args[0] -join "<br />`r`n" | Out-File -LiteralPath $args[1] },
                        { $args[0] | ConvertTo-Html -Fragment | Out-File -LiteralPath $args[1] },
                        { $args[0] | ConvertTo-Html -Fragment | Out-File -LiteralPath $args[1] },
                        { $args[0] | ConvertTo-Html -Fragment | Out-File -LiteralPath $args[1] },
                        { $args[0] | ConvertTo-Html -Fragment | Out-File -LiteralPath $args[1] },
                        { $args[0] | Out-File -LiteralPath $args[1] },
                        { },
                        { },
                        { $null = Set-Content -LiteralPath $args[1] -Value $args[0] }
                    )
                    $DetailScripts[10] = {
                        if (
                            $GroupBy -eq 'none' -or
                            $GroupBy -eq $Split
                        ) {
                            Write-LogMsg @LogParams -Text "Get-HtmlBody -HtmlFolderPermissions `$FormattedPermission.$Format.Div"
                            $Body = Get-HtmlBody @BodyParams
                            $ReportParameters = $HtmlElements.ReportParameters
                            Write-LogMsg @LogParams -Text "New-BootstrapReport @ReportParameters"
                            New-BootstrapReport -Body $Body @ReportParameters
                        } else {
                            Write-LogMsg @LogParams -Text "New-BootstrapDivWithHeading -HeadingText '$HtmlElements.SummaryTableHeader' -Content `$FormattedPermission.$Format`Group.Table"
                            $TableOfContents = New-BootstrapDivWithHeading -HeadingText $HtmlElements.SummaryTableHeader -Content $PermissionGroupings.Table -Class 'h-100 p-1 bg-light border rounded-3 table-responsive' -HeadingLevel 6
                            Write-LogMsg @LogParams -Text "Get-HtmlBody -TableOfContents `$TableOfContents -HtmlFolderPermissions `$FormattedPermission.$Format.Div"
                            $Body = Get-HtmlBody -TableOfContents $TableOfContents @BodyParams
                        }
                        $ReportParameters = $HtmlElements.ReportParameters
                        Write-LogMsg @LogParams -Text "New-BootstrapReport @$HtmlElements.ReportParameters"
                        New-BootstrapReport -Body $Body @ReportParameters
                    }
                    break
                }
                'js' {
                    $DetailExports = @(
                        { $args[0] | ConvertTo-Json -Compress -WarningAction SilentlyContinue | Out-File -LiteralPath $args[1] },
                        { $args[0] | ConvertTo-Json -Compress -WarningAction SilentlyContinue | Out-File -LiteralPath $args[1] },
                        { $args[0] | ConvertTo-Json -Compress -WarningAction SilentlyContinue | Out-File -LiteralPath $args[1] },
                        { $args[0] | ConvertTo-Json -Compress -WarningAction SilentlyContinue | Out-File -LiteralPath $args[1] },
                        { $args[0] | ConvertTo-Json -Compress -WarningAction SilentlyContinue | Out-File -LiteralPath $args[1] },
                        { $args[0] | ConvertTo-Json -Compress -WarningAction SilentlyContinue | Out-File -LiteralPath $args[1] },
                        { $args[0] | ConvertTo-Json -Compress -WarningAction SilentlyContinue | Out-File -LiteralPath $args[1] },
                        { $args[0] | ConvertTo-Json -Compress -WarningAction SilentlyContinue | Out-File -LiteralPath $args[1] },
                        { },
                        { },
                        { $null = Set-Content -LiteralPath $args[1] -Value $args[0] }
                    )
                    $DetailScripts[10] = {
                        if (
                            $GroupBy -eq 'none' -or
                            $GroupBy -eq $Split
                        ) {
                            Write-LogMsg @LogParams -Text "Get-HtmlBody -HtmlFolderPermissions `$FormattedPermission.$Format.Div"
                            $Body = Get-HtmlBody @BodyParams
                        } else {
                            Write-LogMsg @LogParams -Text "New-BootstrapDivWithHeading -HeadingText '$HtmlElements.SummaryTableHeader' -Content `$FormattedPermission.$Format`Group.Table"
                            $TableOfContents = New-BootstrapDivWithHeading -HeadingText $HtmlElements.SummaryTableHeader -Content $PermissionGroupings.Table -Class 'h-100 p-1 bg-light border rounded-3 table-responsive' -HeadingLevel 6
                            Write-LogMsg @LogParams -Text "Get-HtmlBody -TableOfContents `$TableOfContents -HtmlFolderPermissions `$FormattedPermission.$Format.Div"
                            $Body = Get-HtmlBody -TableOfContents $TableOfContents @BodyParams
                        }
                        Write-LogMsg @LogParams -Text "ConvertTo-ScriptHtml -Permission `$Permissions -PermissionGrouping `$PermissionGroupings"
                        $ScriptHtml = ConvertTo-ScriptHtml -Permission $Permissions -PermissionGrouping $PermissionGroupings -GroupBy $GroupBy -Split $Split
                        $ReportParameters = $HtmlElements.ReportParameters
                        Write-LogMsg @LogParams -Text "New-BootstrapReport -JavaScript @$HtmlElements.ReportParameters"
                        New-BootstrapReport -JavaScript -AdditionalScriptHtml $ScriptHtml -Body $Body @ReportParameters
                    }
                    $FormatString = 'json'
                    break
                }
                'json' {
                    $DetailExports = @(
                        { $args[0] | ConvertTo-Json -Compress -WarningAction SilentlyContinue | Out-File -LiteralPath $args[1] },
                        { $args[0] | ConvertTo-Json -Compress -WarningAction SilentlyContinue | Out-File -LiteralPath $args[1] },
                        { $args[0] | ConvertTo-Json -Compress -WarningAction SilentlyContinue | Out-File -LiteralPath $args[1] },
                        { $args[0] | ConvertTo-Json -Compress -WarningAction SilentlyContinue | Out-File -LiteralPath $args[1] },
                        { $args[0] | ConvertTo-Json -Compress -WarningAction SilentlyContinue | Out-File -LiteralPath $args[1] },
                        { $args[0] | ConvertTo-Json -Compress -WarningAction SilentlyContinue | Out-File -LiteralPath $args[1] },
                        { $args[0] | ConvertTo-Json -Compress -WarningAction SilentlyContinue | Out-File -LiteralPath $args[1] },
                        { $args[0] | ConvertTo-Json -Compress -WarningAction SilentlyContinue | Out-File -LiteralPath $args[1] },
                        { },
                        { },
                        { }
                    )
                    $DetailScripts[10] = { }
                    break
                }
                'prtgxml' {
                    $DetailExports = @( { }, { }, { }, { }, { }, { }, { }, { }, { }, { $args[0] | Out-File -LiteralPath $args[1] } )
                    break
                }
                'xml' {
                    $DetailExports = @(
                        { ($args[0] | ConvertTo-Xml).InnerXml | Out-File -LiteralPath $args[1] },
                        { ($args[0] | ConvertTo-Xml).InnerXml | Out-File -LiteralPath $args[1] },
                        { ($args[0] | ConvertTo-Xml).InnerXml | Out-File -LiteralPath $args[1] },
                        { ($args[0] | ConvertTo-Xml).InnerXml | Out-File -LiteralPath $args[1] },
                        { ($args[0] | ConvertTo-Xml).InnerXml | Out-File -LiteralPath $args[1] },
                        { ($args[0] | ConvertTo-Xml).InnerXml | Out-File -LiteralPath $args[1] },
                        { ($args[0] | ConvertTo-Xml).InnerXml | Out-File -LiteralPath $args[1] },
                        { ($args[0] | ConvertTo-Xml).InnerXml | Out-File -LiteralPath $args[1] },
                        { }, { }, { }
                    )
                    $DetailScripts[10] = { }
                    break
                }
            }
            $ReportObjects = @{}
            ForEach ($Level in $UnsplitDetail) {
                $ReportObjects[$Level] = Invoke-Command -ScriptBlock $DetailScripts[$Level]
                Out-PermissionDetailReport -Detail $Level -ReportObject $ReportObjects -DetailExport $DetailExports -Format $Format -OutputDir $FormatDir -Culture $Culture -DetailString $DetailStrings
            }
            ForEach ($File in $ReportFiles) {
                if ($Subproperty -eq '') {
                    $Subfile = $File
                } else {
                    $Subfile = $File.$Subproperty
                }
                if ($FileNameProperty -eq '') {
                    $FileName = $File.$FileNameSubproperty
                } else {
                    $FileName = $File.$FileNameProperty.$FileNameSubproperty
                }
                $FileName = $FileName -replace '\\\\', '' -replace '\\', '_' -replace '\:', ''
                $PermissionGroupings = $Subfile."$FormatString`Group"
                $Permissions = $Subfile.$FormatString
                $ReportObjects = @{}
                [Hashtable]$Params = $PSBoundParameters
                $Params['TargetPath'] = $File.Path
                $Params['NetworkPath'] = $File.NetworkPaths
                $Params['Split'] = $Split
                $Params['FileName'] = $FileName
                $HtmlElements = Get-HtmlReportElements @Params
                $BodyParams = @{
                    HtmlFolderPermissions = $Permissions.Div
                    HtmlExclusions        = $HtmlElements.ExclusionsDiv
                    HtmlFileList          = $HtmlElements.HtmlDivOfFiles
                    ReportFooter          = $HtmlElements.ReportFooter
                    SummaryDivHeader      = $HtmlElements.SummaryDivHeader
                    DetailDivHeader       = $HtmlElements.DetailDivHeader
                    NetworkPathDiv        = $HtmlElements.NetworkPathDiv
                }
                ForEach ($Level in $SplitDetail) {
                    $ReportObjects[$Level] = Invoke-Command -ScriptBlock $DetailScripts[$Level]
                }
                switch ($Format) {
                    'csv' {
                        Out-PermissionDetailReport -Detail $SplitDetail -ReportObject $ReportObjects -DetailExport $DetailExports -Format $Format -OutputDir $FormatDir -Culture $Culture -DetailString $DetailStrings
                        break
                    }
                    'html' {
                        Out-PermissionDetailReport -Detail $SplitDetail -ReportObject $ReportObjects -DetailExport $DetailExports -Format $Format -OutputDir $FormatDir -FileName $FileName -Culture $Culture -DetailString $DetailStrings
                        break
                    }
                    'js' {
                        Out-PermissionDetailReport -Detail $SplitDetail -ReportObject $ReportObjects -DetailExport $DetailExports -Format $Format -OutputDir $FormatDir -FileName $FileName -Culture $Culture -DetailString $DetailStrings
                        break
                    }
                    'xml' {
                        Out-PermissionDetailReport -Detail $SplitDetail -ReportObject $ReportObjects -DetailExport $DetailExports -Format $Format -OutputDir $FormatDir -Culture $Culture -DetailString $DetailStrings
                        break
                    }
                }
            }
        }
    }
}
function Remove-CachedCimSession {
    param (
        [Hashtable]$CimCache = ([Hashtable]::Synchronized(@{}))
    )
    ForEach ($CacheResult in $CimCache.Values) {
        if ($CacheResult) {
            $CimSession = $CacheResult['CimSession']
            if ($CimSession) {
                $null = Remove-CimSession -CimSession $CimSession
            }
        }
    }
}
function Resolve-AccessControlList {
    param (
        [Hashtable]$ACLsByPath = [Hashtable]::Synchronized(@{}),
        [ValidateSet('Silent', 'Quiet', 'Success', 'Debug', 'Verbose', 'Output', 'Host', 'Warning', 'Error', 'Information', $null)]
        [String]$DebugOutputStream = 'Debug',
        [int]$ThreadCount = (Get-CimInstance -ClassName CIM_Processor | Measure-Object -Sum -Property NumberOfLogicalProcessors).Sum,
        [Hashtable]$ACEsByGUID = ([Hashtable]::Synchronized(@{})),
        [Hashtable]$AceGUIDsByResolvedID = ([Hashtable]::Synchronized(@{})),
        [Hashtable]$AceGUIDsByPath = ([Hashtable]::Synchronized(@{})),
        [Hashtable]$CimCache = ([Hashtable]::Synchronized(@{})),
        [Hashtable]$DirectoryEntryCache = ([Hashtable]::Synchronized(@{})),
        [Hashtable]$DomainsByFqdn = ([Hashtable]::Synchronized(@{})),
        [Hashtable]$DomainsByNetbios = ([Hashtable]::Synchronized(@{})),
        [Hashtable]$DomainsBySid = ([Hashtable]::Synchronized(@{})),
        [String]$ThisHostName = (HOSTNAME.EXE),
        [String]$ThisFqdn = ([System.Net.Dns]::GetHostByName((HOSTNAME.EXE)).HostName),
        [String]$WhoAmI = (whoami.EXE),
        [Hashtable]$LogBuffer = ([Hashtable]::Synchronized(@{})),
        [int]$ProgressParentId,
        [string[]]$InheritanceFlagResolved = @('this folder but not subfolders', 'this folder and subfolders', 'this folder and files, but not subfolders', 'this folder, subfolders, and files')
    )
    $Progress = @{
        Activity = 'Resolve-AccessControlList'
    }
    if ($PSBoundParameters.ContainsKey('ProgressParentId')) {
        $Progress['ParentId'] = $ProgressParentId
        $Progress['Id'] = $ProgressParentId + 1
    } else {
        $Progress['Id'] = 0
    }
    $Paths = $ACLsByPath.Keys
    $Count = $Paths.Count
    Write-Progress @Progress -Status "0% (ACL 0 of $Count)" -CurrentOperation 'Initializing' -PercentComplete 0
    $Log = @{
        Buffer       = $LogBuffer
        ThisHostname = $ThisHostname
        Type         = $DebugOutputStream
        WhoAmI       = $WhoAmI
    }
    $ACEPropertyName = (Get-Member -InputObject $ACLsByPath.Values.Access[0] -MemberType Property, CodeProperty, ScriptProperty, NoteProperty).Name
    $ResolveAclParams = @{
        DirectoryEntryCache     = $DirectoryEntryCache
        DomainsBySID            = $DomainsBySID
        DomainsByNetbios        = $DomainsByNetbios
        DomainsByFqdn           = $DomainsByFqdn
        ThisHostName            = $ThisHostName
        ThisFqdn                = $ThisFqdn
        WhoAmI                  = $WhoAmI
        LogBuffer               = $LogBuffer
        CimCache                = $CimCache
        ACEsByGuid              = $ACEsByGUID
        AceGUIDsByPath          = $AceGUIDsByPath
        AceGUIDsByResolvedID    = $AceGUIDsByResolvedID
        ACLsByPath              = $ACLsByPath
        ACEPropertyName         = $ACEPropertyName
        InheritanceFlagResolved = $InheritanceFlagResolved
    }
    if ($ThreadCount -eq 1) {
        [int]$ProgressInterval = [math]::max(($Count / 100), 1)
        $IntervalCounter = 0
        $i = 0
        ForEach ($ThisPath in $Paths) {
            $IntervalCounter++
            if ($IntervalCounter -eq $ProgressInterval) {
                [int]$PercentComplete = $i / $Count * 100
                Write-Progress @Progress -Status "$PercentComplete% (ACL $($i + 1) of $Count) Resolve-Acl" -CurrentOperation $ThisPath -PercentComplete $PercentComplete
                $IntervalCounter = 0
            }
            $i++ 
            Write-LogMsg @Log -Text "Resolve-Acl -InputObject '$ThisPath' -ACLsByPath `$ACLsByPath -ACEsByGUID `$ACEsByGUID"
            Resolve-Acl -ItemPath $ThisPath @ResolveAclParams
        }
    } else {
        $SplitThreadParams = @{
            Command          = 'Resolve-Acl'
            InputObject      = $Paths
            InputParameter   = 'ItemPath'
            TodaysHostname   = $ThisHostname
            WhoAmI           = $WhoAmI
            LogBuffer        = $LogBuffer
            Threads          = $ThreadCount
            ProgressParentId = $Progress['Id']
            AddParam         = $ResolveAclParams
        }
        Write-LogMsg @Log -Text "Split-Thread -Command 'Resolve-Acl' -InputParameter InputObject -InputObject @('$($ACLsByPath.Keys -join "','")') -AddParam @{ACLsByPath=`$ACLsByPath;ACEsByGUID=`$ACEsByGUID}"
        Split-Thread @SplitThreadParams
    }
    Write-Progress @Progress -Completed
}
function Resolve-Folder {
    param (
        [String]$TargetPath,
        [Hashtable]$CimCache = ([Hashtable]::Synchronized(@{})),
        [ValidateSet('Silent', 'Quiet', 'Success', 'Debug', 'Verbose', 'Output', 'Host', 'Warning', 'Error', 'Information', $null)]
        [String]$DebugOutputStream = 'Debug',
        [String]$ThisHostname = (HOSTNAME.EXE),
        [String]$ThisFqdn = ([System.Net.Dns]::GetHostByName((HOSTNAME.EXE)).HostName),
        [String]$WhoAmI = (whoami.EXE),
        [Hashtable]$LogBuffer = ([Hashtable]::Synchronized(@{}))
    )
    $Log = @{
        Buffer       = $LogBuffer
        ThisHostname = $ThisHostname
        Type         = $DebugOutputstream
        WhoAmI       = $WhoAmI
    }
    $LogSplat = @{
        LogBuffer         = $LogBuffer
        ThisHostname      = $ThisHostname
        DebugOutputStream = $DebugOutputStream
        WhoAmI            = $WhoAmI
    }
    $RegEx = '^(?<DriveLetter>\w):'
    if ($TargetPath -match $RegEx) {
        Write-LogMsg @Log -Text "Get-CachedCimInstance -ComputerName $ThisHostname -ClassName Win32_MappedLogicalDisk"
        $MappedNetworkDrives = Get-CachedCimInstance -ComputerName $ThisHostname -ClassName Win32_MappedLogicalDisk -KeyProperty DeviceID -CimCache $CimCache -ThisFqdn $ThisFqdn @LogSplat
        $MatchingNetworkDrive = $MappedNetworkDrives |
        Where-Object -FilterScript { $_.DeviceID -eq "$($Matches.DriveLetter):" }
        if ($MatchingNetworkDrive) {
            $UNC = $MatchingNetworkDrive.ProviderName
        } else {
            $UNC = $TargetPath -replace $RegEx, "\\$(hostname)\$($Matches.DriveLetter)$"
        }
        if ($UNC) {
            $Server = $UNC.split('\')[2]
            $FQDN = ConvertTo-DnsFqdn -ComputerName $Server @LogSplat
            $UNC -replace "^\\\\$Server\\", "\\$FQDN\"
        }
    } else {
        Write-LogMsg @Log -Text "Get-NetDfsEnum -FolderPath '$TargetPath'"
        $AllDfs = Get-NetDfsEnum -FolderPath $TargetPath -ErrorAction SilentlyContinue
        if ($AllDfs) {
            $MatchingDfsEntryPaths = $AllDfs |
            Group-Object -Property DfsEntryPath |
            Where-Object -FilterScript {
                $TargetPath -match [regex]::Escape($_.Name)
            }
            $RemainingDfsEntryPaths = $MatchingDfsEntryPaths |
            Where-Object -FilterScript {
                -not [bool]$(
                    ForEach ($ThisEntryPath in $MatchingDfsEntryPaths) {
                        if ($ThisEntryPath.Name -match "$([regex]::Escape("$($_.Name)")).+") { $true }
                    }
                )
            } |
            Sort-Object -Property Name
            $RemainingDfsEntryPaths |
            Select-Object -Last 1 -ExpandProperty Group |
            ForEach-Object {
                $_.FullOriginalQueryPath -replace [regex]::Escape($_.DfsEntryPath), $_.DfsTarget
            }
        } else {
            $Server = $TargetPath.split('\')[2]
            $FQDN = ConvertTo-DnsFqdn -ComputerName $Server @LogSplat
            $TargetPath -replace "^\\\\$Server\\", "\\$FQDN\"
        }
    }
}
function Resolve-PermissionTarget {
    param (
        [Parameter(ValueFromPipeline)]
        [ValidateScript({ Test-Path $_ })]
        [System.IO.DirectoryInfo[]]$TargetPath,
        [Hashtable]$CimCache = ([Hashtable]::Synchronized(@{})),
        [ValidateSet('Silent', 'Quiet', 'Success', 'Debug', 'Verbose', 'Output', 'Host', 'Warning', 'Error', 'Information', $null)]
        [String]$DebugOutputStream = 'Debug',
        [String]$ThisHostname = (HOSTNAME.EXE),
        [String]$ThisFqdn = ([System.Net.Dns]::GetHostByName((HOSTNAME.EXE)).HostName),
        [String]$WhoAmI = (whoami.EXE),
        [Hashtable]$LogBuffer = ([Hashtable]::Synchronized(@{})),
        [Hashtable]$Output = [Hashtable]::Synchronized(@{}),
        [int]$ProgressParentId
    )
    $Log = @{
        Buffer       = $LogBuffer
        ThisHostname = $ThisHostname
        Type         = $DebugOutputstream
        WhoAmI       = $WhoAmI
    }
    $ResolveFolderSplat = @{
        DebugOutputStream = $DebugOutputStream
        CimCache          = $CimCache
        ThisFqdn          = $ThisFqdn
    }
    ForEach ($ThisTargetPath in $TargetPath) {
        Write-LogMsg @Log -Text "Resolve-Folder -TargetPath '$ThisTargetPath'"
        $Output[$ThisTargetPath] = Resolve-Folder -TargetPath $ThisTargetPath @Log @ResolveFolderSplat
    }
}
function Select-PermissionPrincipal {
    param (
        [Hashtable]$PrincipalByID = @{},
        [string[]]$ExcludeAccount,
        [string[]]$IncludeAccount,
        [string[]]$IgnoreDomain,
        [Hashtable]$IdByShortName = @{},
        [Hashtable]$ShortNameByID = @{},
        [Hashtable]$ExcludeClassFilterContents = @{},
        [Hashtable]$ExcludeFilterContents = @{},
        [Hashtable]$IncludeFilterContents = @{},
        [int]$ProgressParentId,
        [String]$ThisHostName,
        [String]$WhoAmI,
        [Hashtable]$LogBuffer
    )
    $Progress = @{
        Activity = 'Select-PermissionPrincipal'
    }
    if ($PSBoundParameters.ContainsKey('ProgressParentId')) {
        $Progress['ParentId'] = $ProgressParentId
        $Progress['Id'] = $ProgressParentId + 1
    } else {
        $Progress['Id'] = 0
    }
    $IDs = $PrincipalByID.Keys
    $Count = $IDs.Count
    Write-Progress @Progress -Status "0% (principal 0 of $Count) Select principals as specified in parameters" -CurrentOperation 'Ignore domains, and include/exclude principals based on name or class' -PercentComplete 0
    $Type = [string]
    ForEach ($ThisID in $IDs) {
        if (
            [bool]$(
                ForEach ($ClassToExclude in $ExcludeClass) {
                    $Principal = $PrincipalByID[$ThisID]
                    if ($Principal.SchemaClassName -eq $ClassToExclude) {
                        $ExcludeClassFilterContents[$ThisID] = $true
                        $true
                    }
                }
            ) -or
            [bool]$(
                ForEach ($RegEx in $ExcludeAccount) {
                    if ($ThisID -match $RegEx) {
                        $ExcludeFilterContents[$ThisID] = $true
                        $true
                    }
                }
            ) -or
            -not [bool]$(
                if ($IncludeAccount.Count -eq 0) {
                    $true
                } else {
                    ForEach ($RegEx in $IncludeAccount) {
                        if ($ThisID -match $RegEx) {
                            $true
                        } else {
                            $IncludeFilterContents[$ThisID] = $true
                        }
                    }
                }
            )
        ) { continue }
        $ShortName = $ThisID
        ForEach ($IgnoreThisDomain in $IgnoreDomain) {
            $ShortName = $ShortName -replace "^$IgnoreThisDomain\\", ''
        }
        Add-CacheItem -Cache $IdByShortName -Key $ShortName -Value $ThisID -Type $Type
        $ShortNameByID[$ThisID] = $ShortName
    }
    Write-Progress @Progress -Completed
}
$CSharpFiles = Get-ChildItem -Path "$PSScriptRoot\*.cs"
ForEach ($ThisFile in $CSharpFiles) {
    Add-Type -Path $ThisFile.FullName -ErrorAction Stop
}
function ConvertTo-BootstrapJavaScriptTable {
    param (
        [string]$Id,
        $InputObject,
        [switch]$DataFilterControl,
        [string[]]$UnsortableColumn,
        [string[]]$SearchableColumn,
        [string[]]$DropdownColumn,
        [switch]$AllColumnsSearchable,
        [string[]]$PropNames,
        [int]$PageSize
    )
    $UnsortableColumns = @{}
    ForEach ($Col in $UnsortableColumn) {
        $UnsortableColumns[$Col] = $null
    }
    $SearchableColumns = @{}
    ForEach ($Col in $SearchableColumn) {
        $SearchableColumns[$Col] = $null
    }
    $DropdownColumns = @{}
    ForEach ($Col in $DropdownColumn) {
        $DropdownColumns[$Col] = $null
    }
    $Stringbuilder = [System.Text.StringBuilder]::new()
    $null = $Stringbuilder.Append('<table id="')
    $null = $Stringbuilder.Append($Id)
    $null = $Stringbuilder.Append('"')
    if ($DataFilterControl) {
        $null = $Stringbuilder.Append(' class="table table-striped text-nowrap small table-sm" data-filter-control="true" data-pagination="true"')
    }
    if ($PageSize) {
        $null = $Stringbuilder.Append(" data-page-size=`"$PageSize`"")
    }
    $null = $Stringbuilder.AppendLine('>')
    $null = $Stringbuilder.AppendLine('<thead>')
    $null = $Stringbuilder.AppendLine('<tr>')
    if (-not $PSBoundParameters.ContainsKey('PropNames')) {
        $PropNames = ($InputObject | Get-Member -MemberType noteproperty).Name
    }
    ForEach ($Prop in $PropNames) {
        $null = $Stringbuilder.Append('<th')
        if ($DataFilterControl) {
            $null = $Stringbuilder.Append(' data-field="')
            $null = $Stringbuilder.Append(($Prop -replace '\s', ''))
            $null = $Stringbuilder.Append('"')
        }
        if ($DataFilterControl) {
            if ($SearchableColumns.ContainsKey($Prop) -or $AllColumnsSearchable) {
                $null = $Stringbuilder.Append(' data-filter-control="input"')
            }
            if ($DropdownColumns.ContainsKey($Prop)) {
                $null = $Stringbuilder.Append(' data-filter-control="select"')
            }
        }
        if (-not $UnsortableColumns.ContainsKey($Prop)) {
            $null = $Stringbuilder.Append(' data-sortable="true"')
        }
        $null = $Stringbuilder.Append('>')
        $null = $Stringbuilder.Append($Prop)
        $null = $Stringbuilder.AppendLine('</th>')
    }
    $null = $Stringbuilder.AppendLine('</tr>')
    $null = $Stringbuilder.AppendLine('</thead>')
    $null = $Stringbuilder.AppendLine('</table>')
    $Stringbuilder.ToString()
}
Function ConvertTo-BootstrapListGroup {
    [OutputType([System.String])]
    [CmdletBinding()]
    param(
        [Parameter(
            Position = 0,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName
        )]
        [System.String[]]$HtmlList
    )
    process {
        ForEach ($List in $HtmlList) {
            $List -replace
            '<ul>', '<ul class="list-group small">' -replace
            '<ol>', '<ol class="list-group small">' -replace
            '<li>', '<li class ="list-group-item">'
        }
    }
}
function ConvertTo-BootstrapTableScript {
    param (
        [Parameter(Mandatory)]
        [string]$TableId,
        [Parameter(Mandatory)]
        [string]$ColumnJson,
        [Parameter(Mandatory)]
        [string]$DataJson,
        [string]$Classes = 'table table-striped table-hover table-sm',
        [string]$HeaderStyle = 'headerStyle'
    )
    $null = $ResultingJavaScript = [System.Text.StringBuilder]::new()
    $null = $ResultingJavaScript.AppendLine('<script>')
    $null = $ResultingJavaScript.AppendLine('  $(function() {')
    $null = $ResultingJavaScript.Append("    `$('")
    $null = $ResultingJavaScript.Append($TableId)
    $null = $ResultingJavaScript.AppendLine("').bootstrapTable({")
    $null = $ResultingJavaScript.AppendLine("      classes: '$Classes',")
    $null = $ResultingJavaScript.AppendLine("      headerStyle: '$HeaderStyle',")
    $null = $ResultingJavaScript.AppendLine("      columns: $ColumnJson,")
    $null = $ResultingJavaScript.AppendLine("      data: $DataJson")
    $null = $ResultingJavaScript.AppendLine('    });')
    $null = $ResultingJavaScript.Append("    `$('")
    $null = $ResultingJavaScript.Append($TableId)
    $null = $ResultingJavaScript.Append("').attr(")
    $null = $ResultingJavaScript.AppendLine('"data-filter-control",true); //not working, but seems to result in same final element attributes so not sure why')
    $null = $ResultingJavaScript.Append("    //`$('")
    $null = $ResultingJavaScript.Append($TableId)
    $null = $ResultingJavaScript.Append("').prop(")
    $null = $ResultingJavaScript.AppendLine('"data-filter-control","true"); //does not work, and results in different final element attributes than when hard-coding the property into the HTML table')
    #
    $null = $ResultingJavaScript.AppendLine('  })')
    $null = $ResultingJavaScript.AppendLine('</script>')
    return $ResultingJavaScript.ToString()
}
function ConvertTo-HtmlList {
    param (
        [Parameter(
            Mandatory = $true,
            Position = 0,
            ValueFromPipeline = $true
        )]
        [string[]]$InputObject,
        [switch]$Ordered
    )
    begin {
        if ($Ordered) {
            $ListType = 'ol'
        } else {
            $ListType = 'ul'
        }
        $StringBuilder = [System.Text.StringBuilder]::new("<$ListType>")
    }
    process {
        ForEach ($ThisObject in $InputObject) {
            $null = $StringBuilder.Append("<li>$ThisObject</li>")
        }
    }
    end {
        $null = $StringBuilder.Append("</$ListType>")
        $StringBuilder.ToString()
    }
}
function Get-BootstrapTemplate {
	@"
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
	<head>
		<style type="text/css">
			/*!
			 * Bootstrap v5.1.3 (https://getbootstrap.com/)
			 * Copyright 2011-2021 The Bootstrap Authors
			 * Copyright 2011-2021 Twitter, Inc.
			 * Licensed under MIT (https://github.com/twbs/bootstrap/blob/main/LICENSE)
			 */
			:root{--bs-blue:#0d6efd;--bs-indigo:#6610f2;--bs-purple:#6f42c1;--bs-pink:#d63384;--bs-red:#dc3545;--bs-orange:#fd7e14;--bs-yellow:#ffc107;--bs-green:#198754;--bs-teal:#20c997;--bs-cyan:#0dcaf0;--bs-white:#fff;--bs-gray:#6c757d;--bs-gray-dark:#343a40;--bs-gray-100:#f8f9fa;--bs-gray-200:#e9ecef;--bs-gray-300:#dee2e6;--bs-gray-400:#ced4da;--bs-gray-500:#adb5bd;--bs-gray-600:#6c757d;--bs-gray-700:#495057;--bs-gray-800:#343a40;--bs-gray-900:#212529;--bs-primary:#0d6efd;--bs-secondary:#6c757d;--bs-success:#198754;--bs-info:#0dcaf0;--bs-warning:#ffc107;--bs-danger:#dc3545;--bs-light:#f8f9fa;--bs-dark:#212529;--bs-primary-rgb:13,110,253;--bs-secondary-rgb:108,117,125;--bs-success-rgb:25,135,84;--bs-info-rgb:13,202,240;--bs-warning-rgb:255,193,7;--bs-danger-rgb:220,53,69;--bs-light-rgb:248,249,250;--bs-dark-rgb:33,37,41;--bs-white-rgb:255,255,255;--bs-black-rgb:0,0,0;--bs-body-color-rgb:33,37,41;--bs-body-bg-rgb:255,255,255;--bs-font-sans-serif:system-ui,-apple-system,"Segoe UI",Roboto,"Helvetica Neue",Arial,"Noto Sans","Liberation Sans",sans-serif,"Apple Color Emoji","Segoe UI Emoji","Segoe UI Symbol","Noto Color Emoji";--bs-font-monospace:SFMono-Regular,Menlo,Monaco,Consolas,"Liberation Mono","Courier New",monospace;--bs-gradient:linear-gradient(180deg, rgba(255, 255, 255, 0.15), rgba(255, 255, 255, 0));--bs-body-font-family:var(--bs-font-sans-serif);--bs-body-font-size:1rem;--bs-body-font-weight:400;--bs-body-line-height:1.5;--bs-body-color:#212529;--bs-body-bg:#fff}*,::after,::before{box-sizing:border-box}@media (prefers-reduced-motion:no-preference){:root{scroll-behavior:smooth}}body{margin:0;font-family:var(--bs-body-font-family);font-size:var(--bs-body-font-size);font-weight:var(--bs-body-font-weight);line-height:var(--bs-body-line-height);color:var(--bs-body-color);text-align:var(--bs-body-text-align);background-color:var(--bs-body-bg);-webkit-text-size-adjust:100%;-webkit-tap-highlight-color:transparent}hr{margin:1rem 0;color:inherit;background-color:currentColor;border:0;opacity:.25}hr:not([size]){height:1px}.h1,.h2,.h3,.h4,.h5,.h6,h1,h2,h3,h4,h5,h6{margin-top:0;margin-bottom:.5rem;font-weight:500;line-height:1.2}.h1,h1{font-size:calc(1.375rem + 1.5vw)}@media (min-width:1200px){.h1,h1{font-size:2.5rem}}.h2,h2{font-size:calc(1.325rem + .9vw)}@media (min-width:1200px){.h2,h2{font-size:2rem}}.h3,h3{font-size:calc(1.3rem + .6vw)}@media (min-width:1200px){.h3,h3{font-size:1.75rem}}.h4,h4{font-size:calc(1.275rem + .3vw)}@media (min-width:1200px){.h4,h4{font-size:1.5rem}}.h5,h5{font-size:1.25rem}.h6,h6{font-size:1rem}p{margin-top:0;margin-bottom:1rem}abbr[data-bs-original-title],abbr[title]{-webkit-text-decoration:underline dotted;text-decoration:underline dotted;cursor:help;-webkit-text-decoration-skip-ink:none;text-decoration-skip-ink:none}address{margin-bottom:1rem;font-style:normal;line-height:inherit}ol,ul{padding-left:2rem}dl,ol,ul{margin-top:0;margin-bottom:1rem}ol ol,ol ul,ul ol,ul ul{margin-bottom:0}dt{font-weight:700}dd{margin-bottom:.5rem;margin-left:0}blockquote{margin:0 0 1rem}b,strong{font-weight:bolder}.small,small{font-size:.875em}.mark,mark{padding:.2em;background-color:#fcf8e3}sub,sup{position:relative;font-size:.75em;line-height:0;vertical-align:baseline}sub{bottom:-.25em}sup{top:-.5em}a{color:#0d6efd;text-decoration:underline}a:hover{color:#0a58ca}a:not([href]):not([class]),a:not([href]):not([class]):hover{color:inherit;text-decoration:none}code,kbd,pre,samp{font-family:var(--bs-font-monospace);font-size:1em;direction:ltr;unicode-bidi:bidi-override}pre{display:block;margin-top:0;margin-bottom:1rem;overflow:auto;font-size:.875em}pre code{font-size:inherit;color:inherit;word-break:normal}code{font-size:.875em;color:#d63384;word-wrap:break-word}a>code{color:inherit}kbd{padding:.2rem .4rem;font-size:.875em;color:#fff;background-color:#212529;border-radius:.2rem}kbd kbd{padding:0;font-size:1em;font-weight:700}figure{margin:0 0 1rem}img,svg{vertical-align:middle}table{caption-side:bottom;border-collapse:collapse}caption{padding-top:.5rem;padding-bottom:.5rem;color:#6c757d;text-align:left}th{text-align:inherit;text-align:-webkit-match-parent}tbody,td,tfoot,th,thead,tr{border-color:inherit;border-style:solid;border-width:0}label{display:inline-block}button{border-radius:0}button:focus:not(:focus-visible){outline:0}button,input,optgroup,select,textarea{margin:0;font-family:inherit;font-size:inherit;line-height:inherit}button,select{text-transform:none}[role=button]{cursor:pointer}select{word-wrap:normal}select:disabled{opacity:1}[list]::-webkit-calendar-picker-indicator{display:none}[type=button],[type=reset],[type=submit],button{-webkit-appearance:button}[type=button]:not(:disabled),[type=reset]:not(:disabled),[type=submit]:not(:disabled),button:not(:disabled){cursor:pointer}::-moz-focus-inner{padding:0;border-style:none}textarea{resize:vertical}fieldset{min-width:0;padding:0;margin:0;border:0}legend{float:left;width:100%;padding:0;margin-bottom:.5rem;font-size:calc(1.275rem + .3vw);line-height:inherit}@media (min-width:1200px){legend{font-size:1.5rem}}legend+*{clear:left}::-webkit-datetime-edit-day-field,::-webkit-datetime-edit-fields-wrapper,::-webkit-datetime-edit-hour-field,::-webkit-datetime-edit-minute,::-webkit-datetime-edit-month-field,::-webkit-datetime-edit-text,::-webkit-datetime-edit-year-field{padding:0}::-webkit-inner-spin-button{height:auto}[type=search]{outline-offset:-2px;-webkit-appearance:textfield}::-webkit-search-decoration{-webkit-appearance:none}::-webkit-color-swatch-wrapper{padding:0}::-webkit-file-upload-button{font:inherit}::file-selector-button{font:inherit}::-webkit-file-upload-button{font:inherit;-webkit-appearance:button}output{display:inline-block}iframe{border:0}summary{display:list-item;cursor:pointer}progress{vertical-align:baseline}[hidden]{display:none!important}.lead{font-size:1.25rem;font-weight:300}.display-1{font-size:calc(1.625rem + 4.5vw);font-weight:300;line-height:1.2}@media (min-width:1200px){.display-1{font-size:5rem}}.display-2{font-size:calc(1.575rem + 3.9vw);font-weight:300;line-height:1.2}@media (min-width:1200px){.display-2{font-size:4.5rem}}.display-3{font-size:calc(1.525rem + 3.3vw);font-weight:300;line-height:1.2}@media (min-width:1200px){.display-3{font-size:4rem}}.display-4{font-size:calc(1.475rem + 2.7vw);font-weight:300;line-height:1.2}@media (min-width:1200px){.display-4{font-size:3.5rem}}.display-5{font-size:calc(1.425rem + 2.1vw);font-weight:300;line-height:1.2}@media (min-width:1200px){.display-5{font-size:3rem}}.display-6{font-size:calc(1.375rem + 1.5vw);font-weight:300;line-height:1.2}@media (min-width:1200px){.display-6{font-size:2.5rem}}.list-unstyled{padding-left:0;list-style:none}.list-inline{padding-left:0;list-style:none}.list-inline-item{display:inline-block}.list-inline-item:not(:last-child){margin-right:.5rem}.initialism{font-size:.875em;text-transform:uppercase}.blockquote{margin-bottom:1rem;font-size:1.25rem}.blockquote>:last-child{margin-bottom:0}.blockquote-footer{margin-top:-1rem;margin-bottom:1rem;font-size:.875em;color:#6c757d}.blockquote-footer::before{content:"— "}.img-fluid{max-width:100%;height:auto}.img-thumbnail{padding:.25rem;background-color:#fff;border:1px solid #dee2e6;border-radius:.25rem;max-width:100%;height:auto}.figure{display:inline-block}.figure-img{margin-bottom:.5rem;line-height:1}.figure-caption{font-size:.875em;color:#6c757d}.container,.container-fluid,.container-lg,.container-md,.container-sm,.container-xl,.container-xxl{width:100%;padding-right:var(--bs-gutter-x,.75rem);padding-left:var(--bs-gutter-x,.75rem);margin-right:auto;margin-left:auto}@media (min-width:576px){.container,.container-sm{max-width:540px}}@media (min-width:768px){.container,.container-md,.container-sm{max-width:720px}}@media (min-width:992px){.container,.container-lg,.container-md,.container-sm{max-width:960px}}@media (min-width:1200px){.container,.container-lg,.container-md,.container-sm,.container-xl{max-width:1140px}}@media (min-width:1400px){.container,.container-lg,.container-md,.container-sm,.container-xl,.container-xxl{max-width:1320px}}.row{--bs-gutter-x:1.5rem;--bs-gutter-y:0;display:flex;flex-wrap:wrap;margin-top:calc(-1 * var(--bs-gutter-y));margin-right:calc(-.5 * var(--bs-gutter-x));margin-left:calc(-.5 * var(--bs-gutter-x))}.row>*{flex-shrink:0;width:100%;max-width:100%;padding-right:calc(var(--bs-gutter-x) * .5);padding-left:calc(var(--bs-gutter-x) * .5);margin-top:var(--bs-gutter-y)}.col{flex:1 0 0%}.row-cols-auto>*{flex:0 0 auto;width:auto}.row-cols-1>*{flex:0 0 auto;width:100%}.row-cols-2>*{flex:0 0 auto;width:50%}.row-cols-3>*{flex:0 0 auto;width:33.3333333333%}.row-cols-4>*{flex:0 0 auto;width:25%}.row-cols-5>*{flex:0 0 auto;width:20%}.row-cols-6>*{flex:0 0 auto;width:16.6666666667%}.col-auto{flex:0 0 auto;width:auto}.col-1{flex:0 0 auto;width:8.33333333%}.col-2{flex:0 0 auto;width:16.66666667%}.col-3{flex:0 0 auto;width:25%}.col-4{flex:0 0 auto;width:33.33333333%}.col-5{flex:0 0 auto;width:41.66666667%}.col-6{flex:0 0 auto;width:50%}.col-7{flex:0 0 auto;width:58.33333333%}.col-8{flex:0 0 auto;width:66.66666667%}.col-9{flex:0 0 auto;width:75%}.col-10{flex:0 0 auto;width:83.33333333%}.col-11{flex:0 0 auto;width:91.66666667%}.col-12{flex:0 0 auto;width:100%}.offset-1{margin-left:8.33333333%}.offset-2{margin-left:16.66666667%}.offset-3{margin-left:25%}.offset-4{margin-left:33.33333333%}.offset-5{margin-left:41.66666667%}.offset-6{margin-left:50%}.offset-7{margin-left:58.33333333%}.offset-8{margin-left:66.66666667%}.offset-9{margin-left:75%}.offset-10{margin-left:83.33333333%}.offset-11{margin-left:91.66666667%}.g-0,.gx-0{--bs-gutter-x:0}.g-0,.gy-0{--bs-gutter-y:0}.g-1,.gx-1{--bs-gutter-x:0.25rem}.g-1,.gy-1{--bs-gutter-y:0.25rem}.g-2,.gx-2{--bs-gutter-x:0.5rem}.g-2,.gy-2{--bs-gutter-y:0.5rem}.g-3,.gx-3{--bs-gutter-x:1rem}.g-3,.gy-3{--bs-gutter-y:1rem}.g-4,.gx-4{--bs-gutter-x:1.5rem}.g-4,.gy-4{--bs-gutter-y:1.5rem}.g-5,.gx-5{--bs-gutter-x:3rem}.g-5,.gy-5{--bs-gutter-y:3rem}@media (min-width:576px){.col-sm{flex:1 0 0%}.row-cols-sm-auto>*{flex:0 0 auto;width:auto}.row-cols-sm-1>*{flex:0 0 auto;width:100%}.row-cols-sm-2>*{flex:0 0 auto;width:50%}.row-cols-sm-3>*{flex:0 0 auto;width:33.3333333333%}.row-cols-sm-4>*{flex:0 0 auto;width:25%}.row-cols-sm-5>*{flex:0 0 auto;width:20%}.row-cols-sm-6>*{flex:0 0 auto;width:16.6666666667%}.col-sm-auto{flex:0 0 auto;width:auto}.col-sm-1{flex:0 0 auto;width:8.33333333%}.col-sm-2{flex:0 0 auto;width:16.66666667%}.col-sm-3{flex:0 0 auto;width:25%}.col-sm-4{flex:0 0 auto;width:33.33333333%}.col-sm-5{flex:0 0 auto;width:41.66666667%}.col-sm-6{flex:0 0 auto;width:50%}.col-sm-7{flex:0 0 auto;width:58.33333333%}.col-sm-8{flex:0 0 auto;width:66.66666667%}.col-sm-9{flex:0 0 auto;width:75%}.col-sm-10{flex:0 0 auto;width:83.33333333%}.col-sm-11{flex:0 0 auto;width:91.66666667%}.col-sm-12{flex:0 0 auto;width:100%}.offset-sm-0{margin-left:0}.offset-sm-1{margin-left:8.33333333%}.offset-sm-2{margin-left:16.66666667%}.offset-sm-3{margin-left:25%}.offset-sm-4{margin-left:33.33333333%}.offset-sm-5{margin-left:41.66666667%}.offset-sm-6{margin-left:50%}.offset-sm-7{margin-left:58.33333333%}.offset-sm-8{margin-left:66.66666667%}.offset-sm-9{margin-left:75%}.offset-sm-10{margin-left:83.33333333%}.offset-sm-11{margin-left:91.66666667%}.g-sm-0,.gx-sm-0{--bs-gutter-x:0}.g-sm-0,.gy-sm-0{--bs-gutter-y:0}.g-sm-1,.gx-sm-1{--bs-gutter-x:0.25rem}.g-sm-1,.gy-sm-1{--bs-gutter-y:0.25rem}.g-sm-2,.gx-sm-2{--bs-gutter-x:0.5rem}.g-sm-2,.gy-sm-2{--bs-gutter-y:0.5rem}.g-sm-3,.gx-sm-3{--bs-gutter-x:1rem}.g-sm-3,.gy-sm-3{--bs-gutter-y:1rem}.g-sm-4,.gx-sm-4{--bs-gutter-x:1.5rem}.g-sm-4,.gy-sm-4{--bs-gutter-y:1.5rem}.g-sm-5,.gx-sm-5{--bs-gutter-x:3rem}.g-sm-5,.gy-sm-5{--bs-gutter-y:3rem}}@media (min-width:768px){.col-md{flex:1 0 0%}.row-cols-md-auto>*{flex:0 0 auto;width:auto}.row-cols-md-1>*{flex:0 0 auto;width:100%}.row-cols-md-2>*{flex:0 0 auto;width:50%}.row-cols-md-3>*{flex:0 0 auto;width:33.3333333333%}.row-cols-md-4>*{flex:0 0 auto;width:25%}.row-cols-md-5>*{flex:0 0 auto;width:20%}.row-cols-md-6>*{flex:0 0 auto;width:16.6666666667%}.col-md-auto{flex:0 0 auto;width:auto}.col-md-1{flex:0 0 auto;width:8.33333333%}.col-md-2{flex:0 0 auto;width:16.66666667%}.col-md-3{flex:0 0 auto;width:25%}.col-md-4{flex:0 0 auto;width:33.33333333%}.col-md-5{flex:0 0 auto;width:41.66666667%}.col-md-6{flex:0 0 auto;width:50%}.col-md-7{flex:0 0 auto;width:58.33333333%}.col-md-8{flex:0 0 auto;width:66.66666667%}.col-md-9{flex:0 0 auto;width:75%}.col-md-10{flex:0 0 auto;width:83.33333333%}.col-md-11{flex:0 0 auto;width:91.66666667%}.col-md-12{flex:0 0 auto;width:100%}.offset-md-0{margin-left:0}.offset-md-1{margin-left:8.33333333%}.offset-md-2{margin-left:16.66666667%}.offset-md-3{margin-left:25%}.offset-md-4{margin-left:33.33333333%}.offset-md-5{margin-left:41.66666667%}.offset-md-6{margin-left:50%}.offset-md-7{margin-left:58.33333333%}.offset-md-8{margin-left:66.66666667%}.offset-md-9{margin-left:75%}.offset-md-10{margin-left:83.33333333%}.offset-md-11{margin-left:91.66666667%}.g-md-0,.gx-md-0{--bs-gutter-x:0}.g-md-0,.gy-md-0{--bs-gutter-y:0}.g-md-1,.gx-md-1{--bs-gutter-x:0.25rem}.g-md-1,.gy-md-1{--bs-gutter-y:0.25rem}.g-md-2,.gx-md-2{--bs-gutter-x:0.5rem}.g-md-2,.gy-md-2{--bs-gutter-y:0.5rem}.g-md-3,.gx-md-3{--bs-gutter-x:1rem}.g-md-3,.gy-md-3{--bs-gutter-y:1rem}.g-md-4,.gx-md-4{--bs-gutter-x:1.5rem}.g-md-4,.gy-md-4{--bs-gutter-y:1.5rem}.g-md-5,.gx-md-5{--bs-gutter-x:3rem}.g-md-5,.gy-md-5{--bs-gutter-y:3rem}}@media (min-width:992px){.col-lg{flex:1 0 0%}.row-cols-lg-auto>*{flex:0 0 auto;width:auto}.row-cols-lg-1>*{flex:0 0 auto;width:100%}.row-cols-lg-2>*{flex:0 0 auto;width:50%}.row-cols-lg-3>*{flex:0 0 auto;width:33.3333333333%}.row-cols-lg-4>*{flex:0 0 auto;width:25%}.row-cols-lg-5>*{flex:0 0 auto;width:20%}.row-cols-lg-6>*{flex:0 0 auto;width:16.6666666667%}.col-lg-auto{flex:0 0 auto;width:auto}.col-lg-1{flex:0 0 auto;width:8.33333333%}.col-lg-2{flex:0 0 auto;width:16.66666667%}.col-lg-3{flex:0 0 auto;width:25%}.col-lg-4{flex:0 0 auto;width:33.33333333%}.col-lg-5{flex:0 0 auto;width:41.66666667%}.col-lg-6{flex:0 0 auto;width:50%}.col-lg-7{flex:0 0 auto;width:58.33333333%}.col-lg-8{flex:0 0 auto;width:66.66666667%}.col-lg-9{flex:0 0 auto;width:75%}.col-lg-10{flex:0 0 auto;width:83.33333333%}.col-lg-11{flex:0 0 auto;width:91.66666667%}.col-lg-12{flex:0 0 auto;width:100%}.offset-lg-0{margin-left:0}.offset-lg-1{margin-left:8.33333333%}.offset-lg-2{margin-left:16.66666667%}.offset-lg-3{margin-left:25%}.offset-lg-4{margin-left:33.33333333%}.offset-lg-5{margin-left:41.66666667%}.offset-lg-6{margin-left:50%}.offset-lg-7{margin-left:58.33333333%}.offset-lg-8{margin-left:66.66666667%}.offset-lg-9{margin-left:75%}.offset-lg-10{margin-left:83.33333333%}.offset-lg-11{margin-left:91.66666667%}.g-lg-0,.gx-lg-0{--bs-gutter-x:0}.g-lg-0,.gy-lg-0{--bs-gutter-y:0}.g-lg-1,.gx-lg-1{--bs-gutter-x:0.25rem}.g-lg-1,.gy-lg-1{--bs-gutter-y:0.25rem}.g-lg-2,.gx-lg-2{--bs-gutter-x:0.5rem}.g-lg-2,.gy-lg-2{--bs-gutter-y:0.5rem}.g-lg-3,.gx-lg-3{--bs-gutter-x:1rem}.g-lg-3,.gy-lg-3{--bs-gutter-y:1rem}.g-lg-4,.gx-lg-4{--bs-gutter-x:1.5rem}.g-lg-4,.gy-lg-4{--bs-gutter-y:1.5rem}.g-lg-5,.gx-lg-5{--bs-gutter-x:3rem}.g-lg-5,.gy-lg-5{--bs-gutter-y:3rem}}@media (min-width:1200px){.col-xl{flex:1 0 0%}.row-cols-xl-auto>*{flex:0 0 auto;width:auto}.row-cols-xl-1>*{flex:0 0 auto;width:100%}.row-cols-xl-2>*{flex:0 0 auto;width:50%}.row-cols-xl-3>*{flex:0 0 auto;width:33.3333333333%}.row-cols-xl-4>*{flex:0 0 auto;width:25%}.row-cols-xl-5>*{flex:0 0 auto;width:20%}.row-cols-xl-6>*{flex:0 0 auto;width:16.6666666667%}.col-xl-auto{flex:0 0 auto;width:auto}.col-xl-1{flex:0 0 auto;width:8.33333333%}.col-xl-2{flex:0 0 auto;width:16.66666667%}.col-xl-3{flex:0 0 auto;width:25%}.col-xl-4{flex:0 0 auto;width:33.33333333%}.col-xl-5{flex:0 0 auto;width:41.66666667%}.col-xl-6{flex:0 0 auto;width:50%}.col-xl-7{flex:0 0 auto;width:58.33333333%}.col-xl-8{flex:0 0 auto;width:66.66666667%}.col-xl-9{flex:0 0 auto;width:75%}.col-xl-10{flex:0 0 auto;width:83.33333333%}.col-xl-11{flex:0 0 auto;width:91.66666667%}.col-xl-12{flex:0 0 auto;width:100%}.offset-xl-0{margin-left:0}.offset-xl-1{margin-left:8.33333333%}.offset-xl-2{margin-left:16.66666667%}.offset-xl-3{margin-left:25%}.offset-xl-4{margin-left:33.33333333%}.offset-xl-5{margin-left:41.66666667%}.offset-xl-6{margin-left:50%}.offset-xl-7{margin-left:58.33333333%}.offset-xl-8{margin-left:66.66666667%}.offset-xl-9{margin-left:75%}.offset-xl-10{margin-left:83.33333333%}.offset-xl-11{margin-left:91.66666667%}.g-xl-0,.gx-xl-0{--bs-gutter-x:0}.g-xl-0,.gy-xl-0{--bs-gutter-y:0}.g-xl-1,.gx-xl-1{--bs-gutter-x:0.25rem}.g-xl-1,.gy-xl-1{--bs-gutter-y:0.25rem}.g-xl-2,.gx-xl-2{--bs-gutter-x:0.5rem}.g-xl-2,.gy-xl-2{--bs-gutter-y:0.5rem}.g-xl-3,.gx-xl-3{--bs-gutter-x:1rem}.g-xl-3,.gy-xl-3{--bs-gutter-y:1rem}.g-xl-4,.gx-xl-4{--bs-gutter-x:1.5rem}.g-xl-4,.gy-xl-4{--bs-gutter-y:1.5rem}.g-xl-5,.gx-xl-5{--bs-gutter-x:3rem}.g-xl-5,.gy-xl-5{--bs-gutter-y:3rem}}@media (min-width:1400px){.col-xxl{flex:1 0 0%}.row-cols-xxl-auto>*{flex:0 0 auto;width:auto}.row-cols-xxl-1>*{flex:0 0 auto;width:100%}.row-cols-xxl-2>*{flex:0 0 auto;width:50%}.row-cols-xxl-3>*{flex:0 0 auto;width:33.3333333333%}.row-cols-xxl-4>*{flex:0 0 auto;width:25%}.row-cols-xxl-5>*{flex:0 0 auto;width:20%}.row-cols-xxl-6>*{flex:0 0 auto;width:16.6666666667%}.col-xxl-auto{flex:0 0 auto;width:auto}.col-xxl-1{flex:0 0 auto;width:8.33333333%}.col-xxl-2{flex:0 0 auto;width:16.66666667%}.col-xxl-3{flex:0 0 auto;width:25%}.col-xxl-4{flex:0 0 auto;width:33.33333333%}.col-xxl-5{flex:0 0 auto;width:41.66666667%}.col-xxl-6{flex:0 0 auto;width:50%}.col-xxl-7{flex:0 0 auto;width:58.33333333%}.col-xxl-8{flex:0 0 auto;width:66.66666667%}.col-xxl-9{flex:0 0 auto;width:75%}.col-xxl-10{flex:0 0 auto;width:83.33333333%}.col-xxl-11{flex:0 0 auto;width:91.66666667%}.col-xxl-12{flex:0 0 auto;width:100%}.offset-xxl-0{margin-left:0}.offset-xxl-1{margin-left:8.33333333%}.offset-xxl-2{margin-left:16.66666667%}.offset-xxl-3{margin-left:25%}.offset-xxl-4{margin-left:33.33333333%}.offset-xxl-5{margin-left:41.66666667%}.offset-xxl-6{margin-left:50%}.offset-xxl-7{margin-left:58.33333333%}.offset-xxl-8{margin-left:66.66666667%}.offset-xxl-9{margin-left:75%}.offset-xxl-10{margin-left:83.33333333%}.offset-xxl-11{margin-left:91.66666667%}.g-xxl-0,.gx-xxl-0{--bs-gutter-x:0}.g-xxl-0,.gy-xxl-0{--bs-gutter-y:0}.g-xxl-1,.gx-xxl-1{--bs-gutter-x:0.25rem}.g-xxl-1,.gy-xxl-1{--bs-gutter-y:0.25rem}.g-xxl-2,.gx-xxl-2{--bs-gutter-x:0.5rem}.g-xxl-2,.gy-xxl-2{--bs-gutter-y:0.5rem}.g-xxl-3,.gx-xxl-3{--bs-gutter-x:1rem}.g-xxl-3,.gy-xxl-3{--bs-gutter-y:1rem}.g-xxl-4,.gx-xxl-4{--bs-gutter-x:1.5rem}.g-xxl-4,.gy-xxl-4{--bs-gutter-y:1.5rem}.g-xxl-5,.gx-xxl-5{--bs-gutter-x:3rem}.g-xxl-5,.gy-xxl-5{--bs-gutter-y:3rem}}.table{--bs-table-bg:transparent;--bs-table-accent-bg:transparent;--bs-table-striped-color:#212529;--bs-table-striped-bg:rgba(0, 0, 0, 0.05);--bs-table-active-color:#212529;--bs-table-active-bg:rgba(0, 0, 0, 0.1);--bs-table-hover-color:#212529;--bs-table-hover-bg:rgba(0, 0, 0, 0.075);width:100%;margin-bottom:1rem;color:#212529;vertical-align:top;border-color:#dee2e6}.table>:not(caption)>*>*{padding:.5rem .5rem;background-color:var(--bs-table-bg);border-bottom-width:1px;box-shadow:inset 0 0 0 9999px var(--bs-table-accent-bg)}.table>tbody{vertical-align:inherit}.table>thead{vertical-align:bottom}.table>:not(:first-child){border-top:2px solid currentColor}.caption-top{caption-side:top}.table-sm>:not(caption)>*>*{padding:.25rem .25rem}.table-bordered>:not(caption)>*{border-width:1px 0}.table-bordered>:not(caption)>*>*{border-width:0 1px}.table-borderless>:not(caption)>*>*{border-bottom-width:0}.table-borderless>:not(:first-child){border-top-width:0}.table-striped>tbody>tr:nth-of-type(odd)>*{--bs-table-accent-bg:var(--bs-table-striped-bg);color:var(--bs-table-striped-color)}.table-active{--bs-table-accent-bg:var(--bs-table-active-bg);color:var(--bs-table-active-color)}.table-hover>tbody>tr:hover>*{--bs-table-accent-bg:var(--bs-table-hover-bg);color:var(--bs-table-hover-color)}.table-primary{--bs-table-bg:#cfe2ff;--bs-table-striped-bg:#c5d7f2;--bs-table-striped-color:#000;--bs-table-active-bg:#bacbe6;--bs-table-active-color:#000;--bs-table-hover-bg:#bfd1ec;--bs-table-hover-color:#000;color:#000;border-color:#bacbe6}.table-secondary{--bs-table-bg:#e2e3e5;--bs-table-striped-bg:#d7d8da;--bs-table-striped-color:#000;--bs-table-active-bg:#cbccce;--bs-table-active-color:#000;--bs-table-hover-bg:#d1d2d4;--bs-table-hover-color:#000;color:#000;border-color:#cbccce}.table-success{--bs-table-bg:#d1e7dd;--bs-table-striped-bg:#c7dbd2;--bs-table-striped-color:#000;--bs-table-active-bg:#bcd0c7;--bs-table-active-color:#000;--bs-table-hover-bg:#c1d6cc;--bs-table-hover-color:#000;color:#000;border-color:#bcd0c7}.table-info{--bs-table-bg:#cff4fc;--bs-table-striped-bg:#c5e8ef;--bs-table-striped-color:#000;--bs-table-active-bg:#badce3;--bs-table-active-color:#000;--bs-table-hover-bg:#bfe2e9;--bs-table-hover-color:#000;color:#000;border-color:#badce3}.table-warning{--bs-table-bg:#fff3cd;--bs-table-striped-bg:#f2e7c3;--bs-table-striped-color:#000;--bs-table-active-bg:#e6dbb9;--bs-table-active-color:#000;--bs-table-hover-bg:#ece1be;--bs-table-hover-color:#000;color:#000;border-color:#e6dbb9}.table-danger{--bs-table-bg:#f8d7da;--bs-table-striped-bg:#eccccf;--bs-table-striped-color:#000;--bs-table-active-bg:#dfc2c4;--bs-table-active-color:#000;--bs-table-hover-bg:#e5c7ca;--bs-table-hover-color:#000;color:#000;border-color:#dfc2c4}.table-light{--bs-table-bg:#f8f9fa;--bs-table-striped-bg:#ecedee;--bs-table-striped-color:#000;--bs-table-active-bg:#dfe0e1;--bs-table-active-color:#000;--bs-table-hover-bg:#e5e6e7;--bs-table-hover-color:#000;color:#000;border-color:#dfe0e1}.table-dark{--bs-table-bg:#212529;--bs-table-striped-bg:#2c3034;--bs-table-striped-color:#fff;--bs-table-active-bg:#373b3e;--bs-table-active-color:#fff;--bs-table-hover-bg:#323539;--bs-table-hover-color:#fff;color:#fff;border-color:#373b3e}.table-responsive{overflow-x:auto;-webkit-overflow-scrolling:touch}@media (max-width:575.98px){.table-responsive-sm{overflow-x:auto;-webkit-overflow-scrolling:touch}}@media (max-width:767.98px){.table-responsive-md{overflow-x:auto;-webkit-overflow-scrolling:touch}}@media (max-width:991.98px){.table-responsive-lg{overflow-x:auto;-webkit-overflow-scrolling:touch}}@media (max-width:1199.98px){.table-responsive-xl{overflow-x:auto;-webkit-overflow-scrolling:touch}}@media (max-width:1399.98px){.table-responsive-xxl{overflow-x:auto;-webkit-overflow-scrolling:touch}}.form-label{margin-bottom:.5rem}.col-form-label{padding-top:calc(.375rem + 1px);padding-bottom:calc(.375rem + 1px);margin-bottom:0;font-size:inherit;line-height:1.5}.col-form-label-lg{padding-top:calc(.5rem + 1px);padding-bottom:calc(.5rem + 1px);font-size:1.25rem}.col-form-label-sm{padding-top:calc(.25rem + 1px);padding-bottom:calc(.25rem + 1px);font-size:.875rem}.form-text{margin-top:.25rem;font-size:.875em;color:#6c757d}.form-control{display:block;width:100%;padding:.375rem .75rem;font-size:1rem;font-weight:400;line-height:1.5;color:#212529;background-color:#fff;background-clip:padding-box;border:1px solid #ced4da;-webkit-appearance:none;-moz-appearance:none;appearance:none;border-radius:.25rem;transition:border-color .15s ease-in-out,box-shadow .15s ease-in-out}@media (prefers-reduced-motion:reduce){.form-control{transition:none}}.form-control[type=file]{overflow:hidden}.form-control[type=file]:not(:disabled):not([readonly]){cursor:pointer}.form-control:focus{color:#212529;background-color:#fff;border-color:#86b7fe;outline:0;box-shadow:0 0 0 .25rem rgba(13,110,253,.25)}.form-control::-webkit-date-and-time-value{height:1.5em}.form-control::-moz-placeholder{color:#6c757d;opacity:1}.form-control::placeholder{color:#6c757d;opacity:1}.form-control:disabled,.form-control[readonly]{background-color:#e9ecef;opacity:1}.form-control::-webkit-file-upload-button{padding:.375rem .75rem;margin:-.375rem -.75rem;-webkit-margin-end:.75rem;margin-inline-end:.75rem;color:#212529;background-color:#e9ecef;pointer-events:none;border-color:inherit;border-style:solid;border-width:0;border-inline-end-width:1px;border-radius:0;-webkit-transition:color .15s ease-in-out,background-color .15s ease-in-out,border-color .15s ease-in-out,box-shadow .15s ease-in-out;transition:color .15s ease-in-out,background-color .15s ease-in-out,border-color .15s ease-in-out,box-shadow .15s ease-in-out}.form-control::file-selector-button{padding:.375rem .75rem;margin:-.375rem -.75rem;-webkit-margin-end:.75rem;margin-inline-end:.75rem;color:#212529;background-color:#e9ecef;pointer-events:none;border-color:inherit;border-style:solid;border-width:0;border-inline-end-width:1px;border-radius:0;transition:color .15s ease-in-out,background-color .15s ease-in-out,border-color .15s ease-in-out,box-shadow .15s ease-in-out}@media (prefers-reduced-motion:reduce){.form-control::-webkit-file-upload-button{-webkit-transition:none;transition:none}.form-control::file-selector-button{transition:none}}.form-control:hover:not(:disabled):not([readonly])::-webkit-file-upload-button{background-color:#dde0e3}.form-control:hover:not(:disabled):not([readonly])::file-selector-button{background-color:#dde0e3}.form-control::-webkit-file-upload-button{padding:.375rem .75rem;margin:-.375rem -.75rem;-webkit-margin-end:.75rem;margin-inline-end:.75rem;color:#212529;background-color:#e9ecef;pointer-events:none;border-color:inherit;border-style:solid;border-width:0;border-inline-end-width:1px;border-radius:0;-webkit-transition:color .15s ease-in-out,background-color .15s ease-in-out,border-color .15s ease-in-out,box-shadow .15s ease-in-out;transition:color .15s ease-in-out,background-color .15s ease-in-out,border-color .15s ease-in-out,box-shadow .15s ease-in-out}@media (prefers-reduced-motion:reduce){.form-control::-webkit-file-upload-button{-webkit-transition:none;transition:none}}.form-control:hover:not(:disabled):not([readonly])::-webkit-file-upload-button{background-color:#dde0e3}.form-control-plaintext{display:block;width:100%;padding:.375rem 0;margin-bottom:0;line-height:1.5;color:#212529;background-color:transparent;border:solid transparent;border-width:1px 0}.form-control-plaintext.form-control-lg,.form-control-plaintext.form-control-sm{padding-right:0;padding-left:0}.form-control-sm{min-height:calc(1.5em + .5rem + 2px);padding:.25rem .5rem;font-size:.875rem;border-radius:.2rem}.form-control-sm::-webkit-file-upload-button{padding:.25rem .5rem;margin:-.25rem -.5rem;-webkit-margin-end:.5rem;margin-inline-end:.5rem}.form-control-sm::file-selector-button{padding:.25rem .5rem;margin:-.25rem -.5rem;-webkit-margin-end:.5rem;margin-inline-end:.5rem}.form-control-sm::-webkit-file-upload-button{padding:.25rem .5rem;margin:-.25rem -.5rem;-webkit-margin-end:.5rem;margin-inline-end:.5rem}.form-control-lg{min-height:calc(1.5em + 1rem + 2px);padding:.5rem 1rem;font-size:1.25rem;border-radius:.3rem}.form-control-lg::-webkit-file-upload-button{padding:.5rem 1rem;margin:-.5rem -1rem;-webkit-margin-end:1rem;margin-inline-end:1rem}.form-control-lg::file-selector-button{padding:.5rem 1rem;margin:-.5rem -1rem;-webkit-margin-end:1rem;margin-inline-end:1rem}.form-control-lg::-webkit-file-upload-button{padding:.5rem 1rem;margin:-.5rem -1rem;-webkit-margin-end:1rem;margin-inline-end:1rem}textarea.form-control{min-height:calc(1.5em + .75rem + 2px)}textarea.form-control-sm{min-height:calc(1.5em + .5rem + 2px)}textarea.form-control-lg{min-height:calc(1.5em + 1rem + 2px)}.form-control-color{width:3rem;height:auto;padding:.375rem}.form-control-color:not(:disabled):not([readonly]){cursor:pointer}.form-control-color::-moz-color-swatch{height:1.5em;border-radius:.25rem}.form-control-color::-webkit-color-swatch{height:1.5em;border-radius:.25rem}.form-select{display:block;width:100%;padding:.375rem 2.25rem .375rem .75rem;-moz-padding-start:calc(0.75rem - 3px);font-size:1rem;font-weight:400;line-height:1.5;color:#212529;background-color:#fff;background-image:url("data:image/svg+xml,%3csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16'%3e%3cpath fill='none' stroke='%23343a40' stroke-linecap='round' stroke-linejoin='round' stroke-width='2' d='M2 5l6 6 6-6'/%3e%3c/svg%3e");background-repeat:no-repeat;background-position:right .75rem center;background-size:16px 12px;border:1px solid #ced4da;border-radius:.25rem;transition:border-color .15s ease-in-out,box-shadow .15s ease-in-out;-webkit-appearance:none;-moz-appearance:none;appearance:none}@media (prefers-reduced-motion:reduce){.form-select{transition:none}}.form-select:focus{border-color:#86b7fe;outline:0;box-shadow:0 0 0 .25rem rgba(13,110,253,.25)}.form-select[multiple],.form-select[size]:not([size="1"]){padding-right:.75rem;background-image:none}.form-select:disabled{background-color:#e9ecef}.form-select:-moz-focusring{color:transparent;text-shadow:0 0 0 #212529}.form-select-sm{padding-top:.25rem;padding-bottom:.25rem;padding-left:.5rem;font-size:.875rem;border-radius:.2rem}.form-select-lg{padding-top:.5rem;padding-bottom:.5rem;padding-left:1rem;font-size:1.25rem;border-radius:.3rem}.form-check{display:block;min-height:1.5rem;padding-left:1.5em;margin-bottom:.125rem}.form-check .form-check-input{float:left;margin-left:-1.5em}.form-check-input{width:1em;height:1em;margin-top:.25em;vertical-align:top;background-color:#fff;background-repeat:no-repeat;background-position:center;background-size:contain;border:1px solid rgba(0,0,0,.25);-webkit-appearance:none;-moz-appearance:none;appearance:none;-webkit-print-color-adjust:exact;color-adjust:exact}.form-check-input[type=checkbox]{border-radius:.25em}.form-check-input[type=radio]{border-radius:50%}.form-check-input:active{filter:brightness(90%)}.form-check-input:focus{border-color:#86b7fe;outline:0;box-shadow:0 0 0 .25rem rgba(13,110,253,.25)}.form-check-input:checked{background-color:#0d6efd;border-color:#0d6efd}.form-check-input:checked[type=checkbox]{background-image:url("data:image/svg+xml,%3csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 20 20'%3e%3cpath fill='none' stroke='%23fff' stroke-linecap='round' stroke-linejoin='round' stroke-width='3' d='M6 10l3 3l6-6'/%3e%3c/svg%3e")}.form-check-input:checked[type=radio]{background-image:url("data:image/svg+xml,%3csvg xmlns='http://www.w3.org/2000/svg' viewBox='-4 -4 8 8'%3e%3ccircle r='2' fill='%23fff'/%3e%3c/svg%3e")}.form-check-input[type=checkbox]:indeterminate{background-color:#0d6efd;border-color:#0d6efd;background-image:url("data:image/svg+xml,%3csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 20 20'%3e%3cpath fill='none' stroke='%23fff' stroke-linecap='round' stroke-linejoin='round' stroke-width='3' d='M6 10h8'/%3e%3c/svg%3e")}.form-check-input:disabled{pointer-events:none;filter:none;opacity:.5}.form-check-input:disabled~.form-check-label,.form-check-input[disabled]~.form-check-label{opacity:.5}.form-switch{padding-left:2.5em}.form-switch .form-check-input{width:2em;margin-left:-2.5em;background-image:url("data:image/svg+xml,%3csvg xmlns='http://www.w3.org/2000/svg' viewBox='-4 -4 8 8'%3e%3ccircle r='3' fill='rgba%280, 0, 0, 0.25%29'/%3e%3c/svg%3e");background-position:left center;border-radius:2em;transition:background-position .15s ease-in-out}@media (prefers-reduced-motion:reduce){.form-switch .form-check-input{transition:none}}.form-switch .form-check-input:focus{background-image:url("data:image/svg+xml,%3csvg xmlns='http://www.w3.org/2000/svg' viewBox='-4 -4 8 8'%3e%3ccircle r='3' fill='%2386b7fe'/%3e%3c/svg%3e")}.form-switch .form-check-input:checked{background-position:right center;background-image:url("data:image/svg+xml,%3csvg xmlns='http://www.w3.org/2000/svg' viewBox='-4 -4 8 8'%3e%3ccircle r='3' fill='%23fff'/%3e%3c/svg%3e")}.form-check-inline{display:inline-block;margin-right:1rem}.btn-check{position:absolute;clip:rect(0,0,0,0);pointer-events:none}.btn-check:disabled+.btn,.btn-check[disabled]+.btn{pointer-events:none;filter:none;opacity:.65}.form-range{width:100%;height:1.5rem;padding:0;background-color:transparent;-webkit-appearance:none;-moz-appearance:none;appearance:none}.form-range:focus{outline:0}.form-range:focus::-webkit-slider-thumb{box-shadow:0 0 0 1px #fff,0 0 0 .25rem rgba(13,110,253,.25)}.form-range:focus::-moz-range-thumb{box-shadow:0 0 0 1px #fff,0 0 0 .25rem rgba(13,110,253,.25)}.form-range::-moz-focus-outer{border:0}.form-range::-webkit-slider-thumb{width:1rem;height:1rem;margin-top:-.25rem;background-color:#0d6efd;border:0;border-radius:1rem;-webkit-transition:background-color .15s ease-in-out,border-color .15s ease-in-out,box-shadow .15s ease-in-out;transition:background-color .15s ease-in-out,border-color .15s ease-in-out,box-shadow .15s ease-in-out;-webkit-appearance:none;appearance:none}@media (prefers-reduced-motion:reduce){.form-range::-webkit-slider-thumb{-webkit-transition:none;transition:none}}.form-range::-webkit-slider-thumb:active{background-color:#b6d4fe}.form-range::-webkit-slider-runnable-track{width:100%;height:.5rem;color:transparent;cursor:pointer;background-color:#dee2e6;border-color:transparent;border-radius:1rem}.form-range::-moz-range-thumb{width:1rem;height:1rem;background-color:#0d6efd;border:0;border-radius:1rem;-moz-transition:background-color .15s ease-in-out,border-color .15s ease-in-out,box-shadow .15s ease-in-out;transition:background-color .15s ease-in-out,border-color .15s ease-in-out,box-shadow .15s ease-in-out;-moz-appearance:none;appearance:none}@media (prefers-reduced-motion:reduce){.form-range::-moz-range-thumb{-moz-transition:none;transition:none}}.form-range::-moz-range-thumb:active{background-color:#b6d4fe}.form-range::-moz-range-track{width:100%;height:.5rem;color:transparent;cursor:pointer;background-color:#dee2e6;border-color:transparent;border-radius:1rem}.form-range:disabled{pointer-events:none}.form-range:disabled::-webkit-slider-thumb{background-color:#adb5bd}.form-range:disabled::-moz-range-thumb{background-color:#adb5bd}.form-floating{position:relative}.form-floating>.form-control,.form-floating>.form-select{height:calc(3.5rem + 2px);line-height:1.25}.form-floating>label{position:absolute;top:0;left:0;height:100%;padding:1rem .75rem;pointer-events:none;border:1px solid transparent;transform-origin:0 0;transition:opacity .1s ease-in-out,transform .1s ease-in-out}@media (prefers-reduced-motion:reduce){.form-floating>label{transition:none}}.form-floating>.form-control{padding:1rem .75rem}.form-floating>.form-control::-moz-placeholder{color:transparent}.form-floating>.form-control::placeholder{color:transparent}.form-floating>.form-control:not(:-moz-placeholder-shown){padding-top:1.625rem;padding-bottom:.625rem}.form-floating>.form-control:focus,.form-floating>.form-control:not(:placeholder-shown){padding-top:1.625rem;padding-bottom:.625rem}.form-floating>.form-control:-webkit-autofill{padding-top:1.625rem;padding-bottom:.625rem}.form-floating>.form-select{padding-top:1.625rem;padding-bottom:.625rem}.form-floating>.form-control:not(:-moz-placeholder-shown)~label{opacity:.65;transform:scale(.85) translateY(-.5rem) translateX(.15rem)}.form-floating>.form-control:focus~label,.form-floating>.form-control:not(:placeholder-shown)~label,.form-floating>.form-select~label{opacity:.65;transform:scale(.85) translateY(-.5rem) translateX(.15rem)}.form-floating>.form-control:-webkit-autofill~label{opacity:.65;transform:scale(.85) translateY(-.5rem) translateX(.15rem)}.input-group{position:relative;display:flex;flex-wrap:wrap;align-items:stretch;width:100%}.input-group>.form-control,.input-group>.form-select{position:relative;flex:1 1 auto;width:1%;min-width:0}.input-group>.form-control:focus,.input-group>.form-select:focus{z-index:3}.input-group .btn{position:relative;z-index:2}.input-group .btn:focus{z-index:3}.input-group-text{display:flex;align-items:center;padding:.375rem .75rem;font-size:1rem;font-weight:400;line-height:1.5;color:#212529;text-align:center;white-space:nowrap;background-color:#e9ecef;border:1px solid #ced4da;border-radius:.25rem}.input-group-lg>.btn,.input-group-lg>.form-control,.input-group-lg>.form-select,.input-group-lg>.input-group-text{padding:.5rem 1rem;font-size:1.25rem;border-radius:.3rem}.input-group-sm>.btn,.input-group-sm>.form-control,.input-group-sm>.form-select,.input-group-sm>.input-group-text{padding:.25rem .5rem;font-size:.875rem;border-radius:.2rem}.input-group-lg>.form-select,.input-group-sm>.form-select{padding-right:3rem}.input-group:not(.has-validation)>.dropdown-toggle:nth-last-child(n+3),.input-group:not(.has-validation)>:not(:last-child):not(.dropdown-toggle):not(.dropdown-menu){border-top-right-radius:0;border-bottom-right-radius:0}.input-group.has-validation>.dropdown-toggle:nth-last-child(n+4),.input-group.has-validation>:nth-last-child(n+3):not(.dropdown-toggle):not(.dropdown-menu){border-top-right-radius:0;border-bottom-right-radius:0}.input-group>:not(:first-child):not(.dropdown-menu):not(.valid-tooltip):not(.valid-feedback):not(.invalid-tooltip):not(.invalid-feedback){margin-left:-1px;border-top-left-radius:0;border-bottom-left-radius:0}.valid-feedback{display:none;width:100%;margin-top:.25rem;font-size:.875em;color:#198754}.valid-tooltip{position:absolute;top:100%;z-index:5;display:none;max-width:100%;padding:.25rem .5rem;margin-top:.1rem;font-size:.875rem;color:#fff;background-color:rgba(25,135,84,.9);border-radius:.25rem}.is-valid~.valid-feedback,.is-valid~.valid-tooltip,.was-validated :valid~.valid-feedback,.was-validated :valid~.valid-tooltip{display:block}.form-control.is-valid,.was-validated .form-control:valid{border-color:#198754;padding-right:calc(1.5em + .75rem);background-image:url("data:image/svg+xml,%3csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 8 8'%3e%3cpath fill='%23198754' d='M2.3 6.73L.6 4.53c-.4-1.04.46-1.4 1.1-.8l1.1 1.4 3.4-3.8c.6-.63 1.6-.27 1.2.7l-4 4.6c-.43.5-.8.4-1.1.1z'/%3e%3c/svg%3e");background-repeat:no-repeat;background-position:right calc(.375em + .1875rem) center;background-size:calc(.75em + .375rem) calc(.75em + .375rem)}.form-control.is-valid:focus,.was-validated .form-control:valid:focus{border-color:#198754;box-shadow:0 0 0 .25rem rgba(25,135,84,.25)}.was-validated textarea.form-control:valid,textarea.form-control.is-valid{padding-right:calc(1.5em + .75rem);background-position:top calc(.375em + .1875rem) right calc(.375em + .1875rem)}.form-select.is-valid,.was-validated .form-select:valid{border-color:#198754}.form-select.is-valid:not([multiple]):not([size]),.form-select.is-valid:not([multiple])[size="1"],.was-validated .form-select:valid:not([multiple]):not([size]),.was-validated .form-select:valid:not([multiple])[size="1"]{padding-right:4.125rem;background-image:url("data:image/svg+xml,%3csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16'%3e%3cpath fill='none' stroke='%23343a40' stroke-linecap='round' stroke-linejoin='round' stroke-width='2' d='M2 5l6 6 6-6'/%3e%3c/svg%3e"),url("data:image/svg+xml,%3csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 8 8'%3e%3cpath fill='%23198754' d='M2.3 6.73L.6 4.53c-.4-1.04.46-1.4 1.1-.8l1.1 1.4 3.4-3.8c.6-.63 1.6-.27 1.2.7l-4 4.6c-.43.5-.8.4-1.1.1z'/%3e%3c/svg%3e");background-position:right .75rem center,center right 2.25rem;background-size:16px 12px,calc(.75em + .375rem) calc(.75em + .375rem)}.form-select.is-valid:focus,.was-validated .form-select:valid:focus{border-color:#198754;box-shadow:0 0 0 .25rem rgba(25,135,84,.25)}.form-check-input.is-valid,.was-validated .form-check-input:valid{border-color:#198754}.form-check-input.is-valid:checked,.was-validated .form-check-input:valid:checked{background-color:#198754}.form-check-input.is-valid:focus,.was-validated .form-check-input:valid:focus{box-shadow:0 0 0 .25rem rgba(25,135,84,.25)}.form-check-input.is-valid~.form-check-label,.was-validated .form-check-input:valid~.form-check-label{color:#198754}.form-check-inline .form-check-input~.valid-feedback{margin-left:.5em}.input-group .form-control.is-valid,.input-group .form-select.is-valid,.was-validated .input-group .form-control:valid,.was-validated .input-group .form-select:valid{z-index:1}.input-group .form-control.is-valid:focus,.input-group .form-select.is-valid:focus,.was-validated .input-group .form-control:valid:focus,.was-validated .input-group .form-select:valid:focus{z-index:3}.invalid-feedback{display:none;width:100%;margin-top:.25rem;font-size:.875em;color:#dc3545}.invalid-tooltip{position:absolute;top:100%;z-index:5;display:none;max-width:100%;padding:.25rem .5rem;margin-top:.1rem;font-size:.875rem;color:#fff;background-color:rgba(220,53,69,.9);border-radius:.25rem}.is-invalid~.invalid-feedback,.is-invalid~.invalid-tooltip,.was-validated :invalid~.invalid-feedback,.was-validated :invalid~.invalid-tooltip{display:block}.form-control.is-invalid,.was-validated .form-control:invalid{border-color:#dc3545;padding-right:calc(1.5em + .75rem);background-image:url("data:image/svg+xml,%3csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 12 12' width='12' height='12' fill='none' stroke='%23dc3545'%3e%3ccircle cx='6' cy='6' r='4.5'/%3e%3cpath stroke-linejoin='round' d='M5.8 3.6h.4L6 6.5z'/%3e%3ccircle cx='6' cy='8.2' r='.6' fill='%23dc3545' stroke='none'/%3e%3c/svg%3e");background-repeat:no-repeat;background-position:right calc(.375em + .1875rem) center;background-size:calc(.75em + .375rem) calc(.75em + .375rem)}.form-control.is-invalid:focus,.was-validated .form-control:invalid:focus{border-color:#dc3545;box-shadow:0 0 0 .25rem rgba(220,53,69,.25)}.was-validated textarea.form-control:invalid,textarea.form-control.is-invalid{padding-right:calc(1.5em + .75rem);background-position:top calc(.375em + .1875rem) right calc(.375em + .1875rem)}.form-select.is-invalid,.was-validated .form-select:invalid{border-color:#dc3545}.form-select.is-invalid:not([multiple]):not([size]),.form-select.is-invalid:not([multiple])[size="1"],.was-validated .form-select:invalid:not([multiple]):not([size]),.was-validated .form-select:invalid:not([multiple])[size="1"]{padding-right:4.125rem;background-image:url("data:image/svg+xml,%3csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16'%3e%3cpath fill='none' stroke='%23343a40' stroke-linecap='round' stroke-linejoin='round' stroke-width='2' d='M2 5l6 6 6-6'/%3e%3c/svg%3e"),url("data:image/svg+xml,%3csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 12 12' width='12' height='12' fill='none' stroke='%23dc3545'%3e%3ccircle cx='6' cy='6' r='4.5'/%3e%3cpath stroke-linejoin='round' d='M5.8 3.6h.4L6 6.5z'/%3e%3ccircle cx='6' cy='8.2' r='.6' fill='%23dc3545' stroke='none'/%3e%3c/svg%3e");background-position:right .75rem center,center right 2.25rem;background-size:16px 12px,calc(.75em + .375rem) calc(.75em + .375rem)}.form-select.is-invalid:focus,.was-validated .form-select:invalid:focus{border-color:#dc3545;box-shadow:0 0 0 .25rem rgba(220,53,69,.25)}.form-check-input.is-invalid,.was-validated .form-check-input:invalid{border-color:#dc3545}.form-check-input.is-invalid:checked,.was-validated .form-check-input:invalid:checked{background-color:#dc3545}.form-check-input.is-invalid:focus,.was-validated .form-check-input:invalid:focus{box-shadow:0 0 0 .25rem rgba(220,53,69,.25)}.form-check-input.is-invalid~.form-check-label,.was-validated .form-check-input:invalid~.form-check-label{color:#dc3545}.form-check-inline .form-check-input~.invalid-feedback{margin-left:.5em}.input-group .form-control.is-invalid,.input-group .form-select.is-invalid,.was-validated .input-group .form-control:invalid,.was-validated .input-group .form-select:invalid{z-index:2}.input-group .form-control.is-invalid:focus,.input-group .form-select.is-invalid:focus,.was-validated .input-group .form-control:invalid:focus,.was-validated .input-group .form-select:invalid:focus{z-index:3}.btn{display:inline-block;font-weight:400;line-height:1.5;color:#212529;text-align:center;text-decoration:none;vertical-align:middle;cursor:pointer;-webkit-user-select:none;-moz-user-select:none;user-select:none;background-color:transparent;border:1px solid transparent;padding:.375rem .75rem;font-size:1rem;border-radius:.25rem;transition:color .15s ease-in-out,background-color .15s ease-in-out,border-color .15s ease-in-out,box-shadow .15s ease-in-out}@media (prefers-reduced-motion:reduce){.btn{transition:none}}.btn:hover{color:#212529}.btn-check:focus+.btn,.btn:focus{outline:0;box-shadow:0 0 0 .25rem rgba(13,110,253,.25)}.btn.disabled,.btn:disabled,fieldset:disabled .btn{pointer-events:none;opacity:.65}.btn-primary{color:#fff;background-color:#0d6efd;border-color:#0d6efd}.btn-primary:hover{color:#fff;background-color:#0b5ed7;border-color:#0a58ca}.btn-check:focus+.btn-primary,.btn-primary:focus{color:#fff;background-color:#0b5ed7;border-color:#0a58ca;box-shadow:0 0 0 .25rem rgba(49,132,253,.5)}.btn-check:active+.btn-primary,.btn-check:checked+.btn-primary,.btn-primary.active,.btn-primary:active,.show>.btn-primary.dropdown-toggle{color:#fff;background-color:#0a58ca;border-color:#0a53be}.btn-check:active+.btn-primary:focus,.btn-check:checked+.btn-primary:focus,.btn-primary.active:focus,.btn-primary:active:focus,.show>.btn-primary.dropdown-toggle:focus{box-shadow:0 0 0 .25rem rgba(49,132,253,.5)}.btn-primary.disabled,.btn-primary:disabled{color:#fff;background-color:#0d6efd;border-color:#0d6efd}.btn-secondary{color:#fff;background-color:#6c757d;border-color:#6c757d}.btn-secondary:hover{color:#fff;background-color:#5c636a;border-color:#565e64}.btn-check:focus+.btn-secondary,.btn-secondary:focus{color:#fff;background-color:#5c636a;border-color:#565e64;box-shadow:0 0 0 .25rem rgba(130,138,145,.5)}.btn-check:active+.btn-secondary,.btn-check:checked+.btn-secondary,.btn-secondary.active,.btn-secondary:active,.show>.btn-secondary.dropdown-toggle{color:#fff;background-color:#565e64;border-color:#51585e}.btn-check:active+.btn-secondary:focus,.btn-check:checked+.btn-secondary:focus,.btn-secondary.active:focus,.btn-secondary:active:focus,.show>.btn-secondary.dropdown-toggle:focus{box-shadow:0 0 0 .25rem rgba(130,138,145,.5)}.btn-secondary.disabled,.btn-secondary:disabled{color:#fff;background-color:#6c757d;border-color:#6c757d}.btn-success{color:#fff;background-color:#198754;border-color:#198754}.btn-success:hover{color:#fff;background-color:#157347;border-color:#146c43}.btn-check:focus+.btn-success,.btn-success:focus{color:#fff;background-color:#157347;border-color:#146c43;box-shadow:0 0 0 .25rem rgba(60,153,110,.5)}.btn-check:active+.btn-success,.btn-check:checked+.btn-success,.btn-success.active,.btn-success:active,.show>.btn-success.dropdown-toggle{color:#fff;background-color:#146c43;border-color:#13653f}.btn-check:active+.btn-success:focus,.btn-check:checked+.btn-success:focus,.btn-success.active:focus,.btn-success:active:focus,.show>.btn-success.dropdown-toggle:focus{box-shadow:0 0 0 .25rem rgba(60,153,110,.5)}.btn-success.disabled,.btn-success:disabled{color:#fff;background-color:#198754;border-color:#198754}.btn-info{color:#000;background-color:#0dcaf0;border-color:#0dcaf0}.btn-info:hover{color:#000;background-color:#31d2f2;border-color:#25cff2}.btn-check:focus+.btn-info,.btn-info:focus{color:#000;background-color:#31d2f2;border-color:#25cff2;box-shadow:0 0 0 .25rem rgba(11,172,204,.5)}.btn-check:active+.btn-info,.btn-check:checked+.btn-info,.btn-info.active,.btn-info:active,.show>.btn-info.dropdown-toggle{color:#000;background-color:#3dd5f3;border-color:#25cff2}.btn-check:active+.btn-info:focus,.btn-check:checked+.btn-info:focus,.btn-info.active:focus,.btn-info:active:focus,.show>.btn-info.dropdown-toggle:focus{box-shadow:0 0 0 .25rem rgba(11,172,204,.5)}.btn-info.disabled,.btn-info:disabled{color:#000;background-color:#0dcaf0;border-color:#0dcaf0}.btn-warning{color:#000;background-color:#ffc107;border-color:#ffc107}.btn-warning:hover{color:#000;background-color:#ffca2c;border-color:#ffc720}.btn-check:focus+.btn-warning,.btn-warning:focus{color:#000;background-color:#ffca2c;border-color:#ffc720;box-shadow:0 0 0 .25rem rgba(217,164,6,.5)}.btn-check:active+.btn-warning,.btn-check:checked+.btn-warning,.btn-warning.active,.btn-warning:active,.show>.btn-warning.dropdown-toggle{color:#000;background-color:#ffcd39;border-color:#ffc720}.btn-check:active+.btn-warning:focus,.btn-check:checked+.btn-warning:focus,.btn-warning.active:focus,.btn-warning:active:focus,.show>.btn-warning.dropdown-toggle:focus{box-shadow:0 0 0 .25rem rgba(217,164,6,.5)}.btn-warning.disabled,.btn-warning:disabled{color:#000;background-color:#ffc107;border-color:#ffc107}.btn-danger{color:#fff;background-color:#dc3545;border-color:#dc3545}.btn-danger:hover{color:#fff;background-color:#bb2d3b;border-color:#b02a37}.btn-check:focus+.btn-danger,.btn-danger:focus{color:#fff;background-color:#bb2d3b;border-color:#b02a37;box-shadow:0 0 0 .25rem rgba(225,83,97,.5)}.btn-check:active+.btn-danger,.btn-check:checked+.btn-danger,.btn-danger.active,.btn-danger:active,.show>.btn-danger.dropdown-toggle{color:#fff;background-color:#b02a37;border-color:#a52834}.btn-check:active+.btn-danger:focus,.btn-check:checked+.btn-danger:focus,.btn-danger.active:focus,.btn-danger:active:focus,.show>.btn-danger.dropdown-toggle:focus{box-shadow:0 0 0 .25rem rgba(225,83,97,.5)}.btn-danger.disabled,.btn-danger:disabled{color:#fff;background-color:#dc3545;border-color:#dc3545}.btn-light{color:#000;background-color:#f8f9fa;border-color:#f8f9fa}.btn-light:hover{color:#000;background-color:#f9fafb;border-color:#f9fafb}.btn-check:focus+.btn-light,.btn-light:focus{color:#000;background-color:#f9fafb;border-color:#f9fafb;box-shadow:0 0 0 .25rem rgba(211,212,213,.5)}.btn-check:active+.btn-light,.btn-check:checked+.btn-light,.btn-light.active,.btn-light:active,.show>.btn-light.dropdown-toggle{color:#000;background-color:#f9fafb;border-color:#f9fafb}.btn-check:active+.btn-light:focus,.btn-check:checked+.btn-light:focus,.btn-light.active:focus,.btn-light:active:focus,.show>.btn-light.dropdown-toggle:focus{box-shadow:0 0 0 .25rem rgba(211,212,213,.5)}.btn-light.disabled,.btn-light:disabled{color:#000;background-color:#f8f9fa;border-color:#f8f9fa}.btn-dark{color:#fff;background-color:#212529;border-color:#212529}.btn-dark:hover{color:#fff;background-color:#1c1f23;border-color:#1a1e21}.btn-check:focus+.btn-dark,.btn-dark:focus{color:#fff;background-color:#1c1f23;border-color:#1a1e21;box-shadow:0 0 0 .25rem rgba(66,70,73,.5)}.btn-check:active+.btn-dark,.btn-check:checked+.btn-dark,.btn-dark.active,.btn-dark:active,.show>.btn-dark.dropdown-toggle{color:#fff;background-color:#1a1e21;border-color:#191c1f}.btn-check:active+.btn-dark:focus,.btn-check:checked+.btn-dark:focus,.btn-dark.active:focus,.btn-dark:active:focus,.show>.btn-dark.dropdown-toggle:focus{box-shadow:0 0 0 .25rem rgba(66,70,73,.5)}.btn-dark.disabled,.btn-dark:disabled{color:#fff;background-color:#212529;border-color:#212529}.btn-outline-primary{color:#0d6efd;border-color:#0d6efd}.btn-outline-primary:hover{color:#fff;background-color:#0d6efd;border-color:#0d6efd}.btn-check:focus+.btn-outline-primary,.btn-outline-primary:focus{box-shadow:0 0 0 .25rem rgba(13,110,253,.5)}.btn-check:active+.btn-outline-primary,.btn-check:checked+.btn-outline-primary,.btn-outline-primary.active,.btn-outline-primary.dropdown-toggle.show,.btn-outline-primary:active{color:#fff;background-color:#0d6efd;border-color:#0d6efd}.btn-check:active+.btn-outline-primary:focus,.btn-check:checked+.btn-outline-primary:focus,.btn-outline-primary.active:focus,.btn-outline-primary.dropdown-toggle.show:focus,.btn-outline-primary:active:focus{box-shadow:0 0 0 .25rem rgba(13,110,253,.5)}.btn-outline-primary.disabled,.btn-outline-primary:disabled{color:#0d6efd;background-color:transparent}.btn-outline-secondary{color:#6c757d;border-color:#6c757d}.btn-outline-secondary:hover{color:#fff;background-color:#6c757d;border-color:#6c757d}.btn-check:focus+.btn-outline-secondary,.btn-outline-secondary:focus{box-shadow:0 0 0 .25rem rgba(108,117,125,.5)}.btn-check:active+.btn-outline-secondary,.btn-check:checked+.btn-outline-secondary,.btn-outline-secondary.active,.btn-outline-secondary.dropdown-toggle.show,.btn-outline-secondary:active{color:#fff;background-color:#6c757d;border-color:#6c757d}.btn-check:active+.btn-outline-secondary:focus,.btn-check:checked+.btn-outline-secondary:focus,.btn-outline-secondary.active:focus,.btn-outline-secondary.dropdown-toggle.show:focus,.btn-outline-secondary:active:focus{box-shadow:0 0 0 .25rem rgba(108,117,125,.5)}.btn-outline-secondary.disabled,.btn-outline-secondary:disabled{color:#6c757d;background-color:transparent}.btn-outline-success{color:#198754;border-color:#198754}.btn-outline-success:hover{color:#fff;background-color:#198754;border-color:#198754}.btn-check:focus+.btn-outline-success,.btn-outline-success:focus{box-shadow:0 0 0 .25rem rgba(25,135,84,.5)}.btn-check:active+.btn-outline-success,.btn-check:checked+.btn-outline-success,.btn-outline-success.active,.btn-outline-success.dropdown-toggle.show,.btn-outline-success:active{color:#fff;background-color:#198754;border-color:#198754}.btn-check:active+.btn-outline-success:focus,.btn-check:checked+.btn-outline-success:focus,.btn-outline-success.active:focus,.btn-outline-success.dropdown-toggle.show:focus,.btn-outline-success:active:focus{box-shadow:0 0 0 .25rem rgba(25,135,84,.5)}.btn-outline-success.disabled,.btn-outline-success:disabled{color:#198754;background-color:transparent}.btn-outline-info{color:#0dcaf0;border-color:#0dcaf0}.btn-outline-info:hover{color:#000;background-color:#0dcaf0;border-color:#0dcaf0}.btn-check:focus+.btn-outline-info,.btn-outline-info:focus{box-shadow:0 0 0 .25rem rgba(13,202,240,.5)}.btn-check:active+.btn-outline-info,.btn-check:checked+.btn-outline-info,.btn-outline-info.active,.btn-outline-info.dropdown-toggle.show,.btn-outline-info:active{color:#000;background-color:#0dcaf0;border-color:#0dcaf0}.btn-check:active+.btn-outline-info:focus,.btn-check:checked+.btn-outline-info:focus,.btn-outline-info.active:focus,.btn-outline-info.dropdown-toggle.show:focus,.btn-outline-info:active:focus{box-shadow:0 0 0 .25rem rgba(13,202,240,.5)}.btn-outline-info.disabled,.btn-outline-info:disabled{color:#0dcaf0;background-color:transparent}.btn-outline-warning{color:#ffc107;border-color:#ffc107}.btn-outline-warning:hover{color:#000;background-color:#ffc107;border-color:#ffc107}.btn-check:focus+.btn-outline-warning,.btn-outline-warning:focus{box-shadow:0 0 0 .25rem rgba(255,193,7,.5)}.btn-check:active+.btn-outline-warning,.btn-check:checked+.btn-outline-warning,.btn-outline-warning.active,.btn-outline-warning.dropdown-toggle.show,.btn-outline-warning:active{color:#000;background-color:#ffc107;border-color:#ffc107}.btn-check:active+.btn-outline-warning:focus,.btn-check:checked+.btn-outline-warning:focus,.btn-outline-warning.active:focus,.btn-outline-warning.dropdown-toggle.show:focus,.btn-outline-warning:active:focus{box-shadow:0 0 0 .25rem rgba(255,193,7,.5)}.btn-outline-warning.disabled,.btn-outline-warning:disabled{color:#ffc107;background-color:transparent}.btn-outline-danger{color:#dc3545;border-color:#dc3545}.btn-outline-danger:hover{color:#fff;background-color:#dc3545;border-color:#dc3545}.btn-check:focus+.btn-outline-danger,.btn-outline-danger:focus{box-shadow:0 0 0 .25rem rgba(220,53,69,.5)}.btn-check:active+.btn-outline-danger,.btn-check:checked+.btn-outline-danger,.btn-outline-danger.active,.btn-outline-danger.dropdown-toggle.show,.btn-outline-danger:active{color:#fff;background-color:#dc3545;border-color:#dc3545}.btn-check:active+.btn-outline-danger:focus,.btn-check:checked+.btn-outline-danger:focus,.btn-outline-danger.active:focus,.btn-outline-danger.dropdown-toggle.show:focus,.btn-outline-danger:active:focus{box-shadow:0 0 0 .25rem rgba(220,53,69,.5)}.btn-outline-danger.disabled,.btn-outline-danger:disabled{color:#dc3545;background-color:transparent}.btn-outline-light{color:#f8f9fa;border-color:#f8f9fa}.btn-outline-light:hover{color:#000;background-color:#f8f9fa;border-color:#f8f9fa}.btn-check:focus+.btn-outline-light,.btn-outline-light:focus{box-shadow:0 0 0 .25rem rgba(248,249,250,.5)}.btn-check:active+.btn-outline-light,.btn-check:checked+.btn-outline-light,.btn-outline-light.active,.btn-outline-light.dropdown-toggle.show,.btn-outline-light:active{color:#000;background-color:#f8f9fa;border-color:#f8f9fa}.btn-check:active+.btn-outline-light:focus,.btn-check:checked+.btn-outline-light:focus,.btn-outline-light.active:focus,.btn-outline-light.dropdown-toggle.show:focus,.btn-outline-light:active:focus{box-shadow:0 0 0 .25rem rgba(248,249,250,.5)}.btn-outline-light.disabled,.btn-outline-light:disabled{color:#f8f9fa;background-color:transparent}.btn-outline-dark{color:#212529;border-color:#212529}.btn-outline-dark:hover{color:#fff;background-color:#212529;border-color:#212529}.btn-check:focus+.btn-outline-dark,.btn-outline-dark:focus{box-shadow:0 0 0 .25rem rgba(33,37,41,.5)}.btn-check:active+.btn-outline-dark,.btn-check:checked+.btn-outline-dark,.btn-outline-dark.active,.btn-outline-dark.dropdown-toggle.show,.btn-outline-dark:active{color:#fff;background-color:#212529;border-color:#212529}.btn-check:active+.btn-outline-dark:focus,.btn-check:checked+.btn-outline-dark:focus,.btn-outline-dark.active:focus,.btn-outline-dark.dropdown-toggle.show:focus,.btn-outline-dark:active:focus{box-shadow:0 0 0 .25rem rgba(33,37,41,.5)}.btn-outline-dark.disabled,.btn-outline-dark:disabled{color:#212529;background-color:transparent}.btn-link{font-weight:400;color:#0d6efd;text-decoration:underline}.btn-link:hover{color:#0a58ca}.btn-link.disabled,.btn-link:disabled{color:#6c757d}.btn-group-lg>.btn,.btn-lg{padding:.5rem 1rem;font-size:1.25rem;border-radius:.3rem}.btn-group-sm>.btn,.btn-sm{padding:.25rem .5rem;font-size:.875rem;border-radius:.2rem}.fade{transition:opacity .15s linear}@media (prefers-reduced-motion:reduce){.fade{transition:none}}.fade:not(.show){opacity:0}.collapse:not(.show){display:none}.collapsing{height:0;overflow:hidden;transition:height .35s ease}@media (prefers-reduced-motion:reduce){.collapsing{transition:none}}.collapsing.collapse-horizontal{width:0;height:auto;transition:width .35s ease}@media (prefers-reduced-motion:reduce){.collapsing.collapse-horizontal{transition:none}}.dropdown,.dropend,.dropstart,.dropup{position:relative}.dropdown-toggle{white-space:nowrap}.dropdown-toggle::after{display:inline-block;margin-left:.255em;vertical-align:.255em;content:"";border-top:.3em solid;border-right:.3em solid transparent;border-bottom:0;border-left:.3em solid transparent}.dropdown-toggle:empty::after{margin-left:0}.dropdown-menu{position:absolute;z-index:1000;display:none;min-width:10rem;padding:.5rem 0;margin:0;font-size:1rem;color:#212529;text-align:left;list-style:none;background-color:#fff;background-clip:padding-box;border:1px solid rgba(0,0,0,.15);border-radius:.25rem}.dropdown-menu[data-bs-popper]{top:100%;left:0;margin-top:.125rem}.dropdown-menu-start{--bs-position:start}.dropdown-menu-start[data-bs-popper]{right:auto;left:0}.dropdown-menu-end{--bs-position:end}.dropdown-menu-end[data-bs-popper]{right:0;left:auto}@media (min-width:576px){.dropdown-menu-sm-start{--bs-position:start}.dropdown-menu-sm-start[data-bs-popper]{right:auto;left:0}.dropdown-menu-sm-end{--bs-position:end}.dropdown-menu-sm-end[data-bs-popper]{right:0;left:auto}}@media (min-width:768px){.dropdown-menu-md-start{--bs-position:start}.dropdown-menu-md-start[data-bs-popper]{right:auto;left:0}.dropdown-menu-md-end{--bs-position:end}.dropdown-menu-md-end[data-bs-popper]{right:0;left:auto}}@media (min-width:992px){.dropdown-menu-lg-start{--bs-position:start}.dropdown-menu-lg-start[data-bs-popper]{right:auto;left:0}.dropdown-menu-lg-end{--bs-position:end}.dropdown-menu-lg-end[data-bs-popper]{right:0;left:auto}}@media (min-width:1200px){.dropdown-menu-xl-start{--bs-position:start}.dropdown-menu-xl-start[data-bs-popper]{right:auto;left:0}.dropdown-menu-xl-end{--bs-position:end}.dropdown-menu-xl-end[data-bs-popper]{right:0;left:auto}}@media (min-width:1400px){.dropdown-menu-xxl-start{--bs-position:start}.dropdown-menu-xxl-start[data-bs-popper]{right:auto;left:0}.dropdown-menu-xxl-end{--bs-position:end}.dropdown-menu-xxl-end[data-bs-popper]{right:0;left:auto}}.dropup .dropdown-menu[data-bs-popper]{top:auto;bottom:100%;margin-top:0;margin-bottom:.125rem}.dropup .dropdown-toggle::after{display:inline-block;margin-left:.255em;vertical-align:.255em;content:"";border-top:0;border-right:.3em solid transparent;border-bottom:.3em solid;border-left:.3em solid transparent}.dropup .dropdown-toggle:empty::after{margin-left:0}.dropend .dropdown-menu[data-bs-popper]{top:0;right:auto;left:100%;margin-top:0;margin-left:.125rem}.dropend .dropdown-toggle::after{display:inline-block;margin-left:.255em;vertical-align:.255em;content:"";border-top:.3em solid transparent;border-right:0;border-bottom:.3em solid transparent;border-left:.3em solid}.dropend .dropdown-toggle:empty::after{margin-left:0}.dropend .dropdown-toggle::after{vertical-align:0}.dropstart .dropdown-menu[data-bs-popper]{top:0;right:100%;left:auto;margin-top:0;margin-right:.125rem}.dropstart .dropdown-toggle::after{display:inline-block;margin-left:.255em;vertical-align:.255em;content:""}.dropstart .dropdown-toggle::after{display:none}.dropstart .dropdown-toggle::before{display:inline-block;margin-right:.255em;vertical-align:.255em;content:"";border-top:.3em solid transparent;border-right:.3em solid;border-bottom:.3em solid transparent}.dropstart .dropdown-toggle:empty::after{margin-left:0}.dropstart .dropdown-toggle::before{vertical-align:0}.dropdown-divider{height:0;margin:.5rem 0;overflow:hidden;border-top:1px solid rgba(0,0,0,.15)}.dropdown-item{display:block;width:100%;padding:.25rem 1rem;clear:both;font-weight:400;color:#212529;text-align:inherit;text-decoration:none;white-space:nowrap;background-color:transparent;border:0}.dropdown-item:focus,.dropdown-item:hover{color:#1e2125;background-color:#e9ecef}.dropdown-item.active,.dropdown-item:active{color:#fff;text-decoration:none;background-color:#0d6efd}.dropdown-item.disabled,.dropdown-item:disabled{color:#adb5bd;pointer-events:none;background-color:transparent}.dropdown-menu.show{display:block}.dropdown-header{display:block;padding:.5rem 1rem;margin-bottom:0;font-size:.875rem;color:#6c757d;white-space:nowrap}.dropdown-item-text{display:block;padding:.25rem 1rem;color:#212529}.dropdown-menu-dark{color:#dee2e6;background-color:#343a40;border-color:rgba(0,0,0,.15)}.dropdown-menu-dark .dropdown-item{color:#dee2e6}.dropdown-menu-dark .dropdown-item:focus,.dropdown-menu-dark .dropdown-item:hover{color:#fff;background-color:rgba(255,255,255,.15)}.dropdown-menu-dark .dropdown-item.active,.dropdown-menu-dark .dropdown-item:active{color:#fff;background-color:#0d6efd}.dropdown-menu-dark .dropdown-item.disabled,.dropdown-menu-dark .dropdown-item:disabled{color:#adb5bd}.dropdown-menu-dark .dropdown-divider{border-color:rgba(0,0,0,.15)}.dropdown-menu-dark .dropdown-item-text{color:#dee2e6}.dropdown-menu-dark .dropdown-header{color:#adb5bd}.btn-group,.btn-group-vertical{position:relative;display:inline-flex;vertical-align:middle}.btn-group-vertical>.btn,.btn-group>.btn{position:relative;flex:1 1 auto}.btn-group-vertical>.btn-check:checked+.btn,.btn-group-vertical>.btn-check:focus+.btn,.btn-group-vertical>.btn.active,.btn-group-vertical>.btn:active,.btn-group-vertical>.btn:focus,.btn-group-vertical>.btn:hover,.btn-group>.btn-check:checked+.btn,.btn-group>.btn-check:focus+.btn,.btn-group>.btn.active,.btn-group>.btn:active,.btn-group>.btn:focus,.btn-group>.btn:hover{z-index:1}.btn-toolbar{display:flex;flex-wrap:wrap;justify-content:flex-start}.btn-toolbar .input-group{width:auto}.btn-group>.btn-group:not(:first-child),.btn-group>.btn:not(:first-child){margin-left:-1px}.btn-group>.btn-group:not(:last-child)>.btn,.btn-group>.btn:not(:last-child):not(.dropdown-toggle){border-top-right-radius:0;border-bottom-right-radius:0}.btn-group>.btn-group:not(:first-child)>.btn,.btn-group>.btn:nth-child(n+3),.btn-group>:not(.btn-check)+.btn{border-top-left-radius:0;border-bottom-left-radius:0}.dropdown-toggle-split{padding-right:.5625rem;padding-left:.5625rem}.dropdown-toggle-split::after,.dropend .dropdown-toggle-split::after,.dropup .dropdown-toggle-split::after{margin-left:0}.dropstart .dropdown-toggle-split::before{margin-right:0}.btn-group-sm>.btn+.dropdown-toggle-split,.btn-sm+.dropdown-toggle-split{padding-right:.375rem;padding-left:.375rem}.btn-group-lg>.btn+.dropdown-toggle-split,.btn-lg+.dropdown-toggle-split{padding-right:.75rem;padding-left:.75rem}.btn-group-vertical{flex-direction:column;align-items:flex-start;justify-content:center}.btn-group-vertical>.btn,.btn-group-vertical>.btn-group{width:100%}.btn-group-vertical>.btn-group:not(:first-child),.btn-group-vertical>.btn:not(:first-child){margin-top:-1px}.btn-group-vertical>.btn-group:not(:last-child)>.btn,.btn-group-vertical>.btn:not(:last-child):not(.dropdown-toggle){border-bottom-right-radius:0;border-bottom-left-radius:0}.btn-group-vertical>.btn-group:not(:first-child)>.btn,.btn-group-vertical>.btn~.btn{border-top-left-radius:0;border-top-right-radius:0}.nav{display:flex;flex-wrap:wrap;padding-left:0;margin-bottom:0;list-style:none}.nav-link{display:block;padding:.5rem 1rem;color:#0d6efd;text-decoration:none;transition:color .15s ease-in-out,background-color .15s ease-in-out,border-color .15s ease-in-out}@media (prefers-reduced-motion:reduce){.nav-link{transition:none}}.nav-link:focus,.nav-link:hover{color:#0a58ca}.nav-link.disabled{color:#6c757d;pointer-events:none;cursor:default}.nav-tabs{border-bottom:1px solid #dee2e6}.nav-tabs .nav-link{margin-bottom:-1px;background:0 0;border:1px solid transparent;border-top-left-radius:.25rem;border-top-right-radius:.25rem}.nav-tabs .nav-link:focus,.nav-tabs .nav-link:hover{border-color:#e9ecef #e9ecef #dee2e6;isolation:isolate}.nav-tabs .nav-link.disabled{color:#6c757d;background-color:transparent;border-color:transparent}.nav-tabs .nav-item.show .nav-link,.nav-tabs .nav-link.active{color:#495057;background-color:#fff;border-color:#dee2e6 #dee2e6 #fff}.nav-tabs .dropdown-menu{margin-top:-1px;border-top-left-radius:0;border-top-right-radius:0}.nav-pills .nav-link{background:0 0;border:0;border-radius:.25rem}.nav-pills .nav-link.active,.nav-pills .show>.nav-link{color:#fff;background-color:#0d6efd}.nav-fill .nav-item,.nav-fill>.nav-link{flex:1 1 auto;text-align:center}.nav-justified .nav-item,.nav-justified>.nav-link{flex-basis:0;flex-grow:1;text-align:center}.nav-fill .nav-item .nav-link,.nav-justified .nav-item .nav-link{width:100%}.tab-content>.tab-pane{display:none}.tab-content>.active{display:block}.navbar{position:relative;display:flex;flex-wrap:wrap;align-items:center;justify-content:space-between;padding-top:.5rem;padding-bottom:.5rem}.navbar>.container,.navbar>.container-fluid,.navbar>.container-lg,.navbar>.container-md,.navbar>.container-sm,.navbar>.container-xl,.navbar>.container-xxl{display:flex;flex-wrap:inherit;align-items:center;justify-content:space-between}.navbar-brand{padding-top:.3125rem;padding-bottom:.3125rem;margin-right:1rem;font-size:1.25rem;text-decoration:none;white-space:nowrap}.navbar-nav{display:flex;flex-direction:column;padding-left:0;margin-bottom:0;list-style:none}.navbar-nav .nav-link{padding-right:0;padding-left:0}.navbar-nav .dropdown-menu{position:static}.navbar-text{padding-top:.5rem;padding-bottom:.5rem}.navbar-collapse{flex-basis:100%;flex-grow:1;align-items:center}.navbar-toggler{padding:.25rem .75rem;font-size:1.25rem;line-height:1;background-color:transparent;border:1px solid transparent;border-radius:.25rem;transition:box-shadow .15s ease-in-out}@media (prefers-reduced-motion:reduce){.navbar-toggler{transition:none}}.navbar-toggler:hover{text-decoration:none}.navbar-toggler:focus{text-decoration:none;outline:0;box-shadow:0 0 0 .25rem}.navbar-toggler-icon{display:inline-block;width:1.5em;height:1.5em;vertical-align:middle;background-repeat:no-repeat;background-position:center;background-size:100%}.navbar-nav-scroll{max-height:var(--bs-scroll-height,75vh);overflow-y:auto}@media (min-width:576px){.navbar-expand-sm{flex-wrap:nowrap;justify-content:flex-start}.navbar-expand-sm .navbar-nav{flex-direction:row}.navbar-expand-sm .navbar-nav .dropdown-menu{position:absolute}.navbar-expand-sm .navbar-nav .nav-link{padding-right:.5rem;padding-left:.5rem}.navbar-expand-sm .navbar-nav-scroll{overflow:visible}.navbar-expand-sm .navbar-collapse{display:flex!important;flex-basis:auto}.navbar-expand-sm .navbar-toggler{display:none}.navbar-expand-sm .offcanvas-header{display:none}.navbar-expand-sm .offcanvas{position:inherit;bottom:0;z-index:1000;flex-grow:1;visibility:visible!important;background-color:transparent;border-right:0;border-left:0;transition:none;transform:none}.navbar-expand-sm .offcanvas-bottom,.navbar-expand-sm .offcanvas-top{height:auto;border-top:0;border-bottom:0}.navbar-expand-sm .offcanvas-body{display:flex;flex-grow:0;padding:0;overflow-y:visible}}@media (min-width:768px){.navbar-expand-md{flex-wrap:nowrap;justify-content:flex-start}.navbar-expand-md .navbar-nav{flex-direction:row}.navbar-expand-md .navbar-nav .dropdown-menu{position:absolute}.navbar-expand-md .navbar-nav .nav-link{padding-right:.5rem;padding-left:.5rem}.navbar-expand-md .navbar-nav-scroll{overflow:visible}.navbar-expand-md .navbar-collapse{display:flex!important;flex-basis:auto}.navbar-expand-md .navbar-toggler{display:none}.navbar-expand-md .offcanvas-header{display:none}.navbar-expand-md .offcanvas{position:inherit;bottom:0;z-index:1000;flex-grow:1;visibility:visible!important;background-color:transparent;border-right:0;border-left:0;transition:none;transform:none}.navbar-expand-md .offcanvas-bottom,.navbar-expand-md .offcanvas-top{height:auto;border-top:0;border-bottom:0}.navbar-expand-md .offcanvas-body{display:flex;flex-grow:0;padding:0;overflow-y:visible}}@media (min-width:992px){.navbar-expand-lg{flex-wrap:nowrap;justify-content:flex-start}.navbar-expand-lg .navbar-nav{flex-direction:row}.navbar-expand-lg .navbar-nav .dropdown-menu{position:absolute}.navbar-expand-lg .navbar-nav .nav-link{padding-right:.5rem;padding-left:.5rem}.navbar-expand-lg .navbar-nav-scroll{overflow:visible}.navbar-expand-lg .navbar-collapse{display:flex!important;flex-basis:auto}.navbar-expand-lg .navbar-toggler{display:none}.navbar-expand-lg .offcanvas-header{display:none}.navbar-expand-lg .offcanvas{position:inherit;bottom:0;z-index:1000;flex-grow:1;visibility:visible!important;background-color:transparent;border-right:0;border-left:0;transition:none;transform:none}.navbar-expand-lg .offcanvas-bottom,.navbar-expand-lg .offcanvas-top{height:auto;border-top:0;border-bottom:0}.navbar-expand-lg .offcanvas-body{display:flex;flex-grow:0;padding:0;overflow-y:visible}}@media (min-width:1200px){.navbar-expand-xl{flex-wrap:nowrap;justify-content:flex-start}.navbar-expand-xl .navbar-nav{flex-direction:row}.navbar-expand-xl .navbar-nav .dropdown-menu{position:absolute}.navbar-expand-xl .navbar-nav .nav-link{padding-right:.5rem;padding-left:.5rem}.navbar-expand-xl .navbar-nav-scroll{overflow:visible}.navbar-expand-xl .navbar-collapse{display:flex!important;flex-basis:auto}.navbar-expand-xl .navbar-toggler{display:none}.navbar-expand-xl .offcanvas-header{display:none}.navbar-expand-xl .offcanvas{position:inherit;bottom:0;z-index:1000;flex-grow:1;visibility:visible!important;background-color:transparent;border-right:0;border-left:0;transition:none;transform:none}.navbar-expand-xl .offcanvas-bottom,.navbar-expand-xl .offcanvas-top{height:auto;border-top:0;border-bottom:0}.navbar-expand-xl .offcanvas-body{display:flex;flex-grow:0;padding:0;overflow-y:visible}}@media (min-width:1400px){.navbar-expand-xxl{flex-wrap:nowrap;justify-content:flex-start}.navbar-expand-xxl .navbar-nav{flex-direction:row}.navbar-expand-xxl .navbar-nav .dropdown-menu{position:absolute}.navbar-expand-xxl .navbar-nav .nav-link{padding-right:.5rem;padding-left:.5rem}.navbar-expand-xxl .navbar-nav-scroll{overflow:visible}.navbar-expand-xxl .navbar-collapse{display:flex!important;flex-basis:auto}.navbar-expand-xxl .navbar-toggler{display:none}.navbar-expand-xxl .offcanvas-header{display:none}.navbar-expand-xxl .offcanvas{position:inherit;bottom:0;z-index:1000;flex-grow:1;visibility:visible!important;background-color:transparent;border-right:0;border-left:0;transition:none;transform:none}.navbar-expand-xxl .offcanvas-bottom,.navbar-expand-xxl .offcanvas-top{height:auto;border-top:0;border-bottom:0}.navbar-expand-xxl .offcanvas-body{display:flex;flex-grow:0;padding:0;overflow-y:visible}}.navbar-expand{flex-wrap:nowrap;justify-content:flex-start}.navbar-expand .navbar-nav{flex-direction:row}.navbar-expand .navbar-nav .dropdown-menu{position:absolute}.navbar-expand .navbar-nav .nav-link{padding-right:.5rem;padding-left:.5rem}.navbar-expand .navbar-nav-scroll{overflow:visible}.navbar-expand .navbar-collapse{display:flex!important;flex-basis:auto}.navbar-expand .navbar-toggler{display:none}.navbar-expand .offcanvas-header{display:none}.navbar-expand .offcanvas{position:inherit;bottom:0;z-index:1000;flex-grow:1;visibility:visible!important;background-color:transparent;border-right:0;border-left:0;transition:none;transform:none}.navbar-expand .offcanvas-bottom,.navbar-expand .offcanvas-top{height:auto;border-top:0;border-bottom:0}.navbar-expand .offcanvas-body{display:flex;flex-grow:0;padding:0;overflow-y:visible}.navbar-light .navbar-brand{color:rgba(0,0,0,.9)}.navbar-light .navbar-brand:focus,.navbar-light .navbar-brand:hover{color:rgba(0,0,0,.9)}.navbar-light .navbar-nav .nav-link{color:rgba(0,0,0,.55)}.navbar-light .navbar-nav .nav-link:focus,.navbar-light .navbar-nav .nav-link:hover{color:rgba(0,0,0,.7)}.navbar-light .navbar-nav .nav-link.disabled{color:rgba(0,0,0,.3)}.navbar-light .navbar-nav .nav-link.active,.navbar-light .navbar-nav .show>.nav-link{color:rgba(0,0,0,.9)}.navbar-light .navbar-toggler{color:rgba(0,0,0,.55);border-color:rgba(0,0,0,.1)}.navbar-light .navbar-toggler-icon{background-image:url("data:image/svg+xml,%3csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 30 30'%3e%3cpath stroke='rgba%280, 0, 0, 0.55%29' stroke-linecap='round' stroke-miterlimit='10' stroke-width='2' d='M4 7h22M4 15h22M4 23h22'/%3e%3c/svg%3e")}.navbar-light .navbar-text{color:rgba(0,0,0,.55)}.navbar-light .navbar-text a,.navbar-light .navbar-text a:focus,.navbar-light .navbar-text a:hover{color:rgba(0,0,0,.9)}.navbar-dark .navbar-brand{color:#fff}.navbar-dark .navbar-brand:focus,.navbar-dark .navbar-brand:hover{color:#fff}.navbar-dark .navbar-nav .nav-link{color:rgba(255,255,255,.55)}.navbar-dark .navbar-nav .nav-link:focus,.navbar-dark .navbar-nav .nav-link:hover{color:rgba(255,255,255,.75)}.navbar-dark .navbar-nav .nav-link.disabled{color:rgba(255,255,255,.25)}.navbar-dark .navbar-nav .nav-link.active,.navbar-dark .navbar-nav .show>.nav-link{color:#fff}.navbar-dark .navbar-toggler{color:rgba(255,255,255,.55);border-color:rgba(255,255,255,.1)}.navbar-dark .navbar-toggler-icon{background-image:url("data:image/svg+xml,%3csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 30 30'%3e%3cpath stroke='rgba%28255, 255, 255, 0.55%29' stroke-linecap='round' stroke-miterlimit='10' stroke-width='2' d='M4 7h22M4 15h22M4 23h22'/%3e%3c/svg%3e")}.navbar-dark .navbar-text{color:rgba(255,255,255,.55)}.navbar-dark .navbar-text a,.navbar-dark .navbar-text a:focus,.navbar-dark .navbar-text a:hover{color:#fff}.card{position:relative;display:flex;flex-direction:column;min-width:0;word-wrap:break-word;background-color:#fff;background-clip:border-box;border:1px solid rgba(0,0,0,.125);border-radius:.25rem}.card>hr{margin-right:0;margin-left:0}.card>.list-group{border-top:inherit;border-bottom:inherit}.card>.list-group:first-child{border-top-width:0;border-top-left-radius:calc(.25rem - 1px);border-top-right-radius:calc(.25rem - 1px)}.card>.list-group:last-child{border-bottom-width:0;border-bottom-right-radius:calc(.25rem - 1px);border-bottom-left-radius:calc(.25rem - 1px)}.card>.card-header+.list-group,.card>.list-group+.card-footer{border-top:0}.card-body{flex:1 1 auto;padding:1rem 1rem}.card-title{margin-bottom:.5rem}.card-subtitle{margin-top:-.25rem;margin-bottom:0}.card-text:last-child{margin-bottom:0}.card-link+.card-link{margin-left:1rem}.card-header{padding:.5rem 1rem;margin-bottom:0;background-color:rgba(0,0,0,.03);border-bottom:1px solid rgba(0,0,0,.125)}.card-header:first-child{border-radius:calc(.25rem - 1px) calc(.25rem - 1px) 0 0}.card-footer{padding:.5rem 1rem;background-color:rgba(0,0,0,.03);border-top:1px solid rgba(0,0,0,.125)}.card-footer:last-child{border-radius:0 0 calc(.25rem - 1px) calc(.25rem - 1px)}.card-header-tabs{margin-right:-.5rem;margin-bottom:-.5rem;margin-left:-.5rem;border-bottom:0}.card-header-pills{margin-right:-.5rem;margin-left:-.5rem}.card-img-overlay{position:absolute;top:0;right:0;bottom:0;left:0;padding:1rem;border-radius:calc(.25rem - 1px)}.card-img,.card-img-bottom,.card-img-top{width:100%}.card-img,.card-img-top{border-top-left-radius:calc(.25rem - 1px);border-top-right-radius:calc(.25rem - 1px)}.card-img,.card-img-bottom{border-bottom-right-radius:calc(.25rem - 1px);border-bottom-left-radius:calc(.25rem - 1px)}.card-group>.card{margin-bottom:.75rem}@media (min-width:576px){.card-group{display:flex;flex-flow:row wrap}.card-group>.card{flex:1 0 0%;margin-bottom:0}.card-group>.card+.card{margin-left:0;border-left:0}.card-group>.card:not(:last-child){border-top-right-radius:0;border-bottom-right-radius:0}.card-group>.card:not(:last-child) .card-header,.card-group>.card:not(:last-child) .card-img-top{border-top-right-radius:0}.card-group>.card:not(:last-child) .card-footer,.card-group>.card:not(:last-child) .card-img-bottom{border-bottom-right-radius:0}.card-group>.card:not(:first-child){border-top-left-radius:0;border-bottom-left-radius:0}.card-group>.card:not(:first-child) .card-header,.card-group>.card:not(:first-child) .card-img-top{border-top-left-radius:0}.card-group>.card:not(:first-child) .card-footer,.card-group>.card:not(:first-child) .card-img-bottom{border-bottom-left-radius:0}}.accordion-button{position:relative;display:flex;align-items:center;width:100%;padding:1rem 1.25rem;font-size:1rem;color:#212529;text-align:left;background-color:#fff;border:0;border-radius:0;overflow-anchor:none;transition:color .15s ease-in-out,background-color .15s ease-in-out,border-color .15s ease-in-out,box-shadow .15s ease-in-out,border-radius .15s ease}@media (prefers-reduced-motion:reduce){.accordion-button{transition:none}}.accordion-button:not(.collapsed){color:#0c63e4;background-color:#e7f1ff;box-shadow:inset 0 -1px 0 rgba(0,0,0,.125)}.accordion-button:not(.collapsed)::after{background-image:url("data:image/svg+xml,%3csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16' fill='%230c63e4'%3e%3cpath fill-rule='evenodd' d='M1.646 4.646a.5.5 0 0 1 .708 0L8 10.293l5.646-5.647a.5.5 0 0 1 .708.708l-6 6a.5.5 0 0 1-.708 0l-6-6a.5.5 0 0 1 0-.708z'/%3e%3c/svg%3e");transform:rotate(-180deg)}.accordion-button::after{flex-shrink:0;width:1.25rem;height:1.25rem;margin-left:auto;content:"";background-image:url("data:image/svg+xml,%3csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16' fill='%23212529'%3e%3cpath fill-rule='evenodd' d='M1.646 4.646a.5.5 0 0 1 .708 0L8 10.293l5.646-5.647a.5.5 0 0 1 .708.708l-6 6a.5.5 0 0 1-.708 0l-6-6a.5.5 0 0 1 0-.708z'/%3e%3c/svg%3e");background-repeat:no-repeat;background-size:1.25rem;transition:transform .2s ease-in-out}@media (prefers-reduced-motion:reduce){.accordion-button::after{transition:none}}.accordion-button:hover{z-index:2}.accordion-button:focus{z-index:3;border-color:#86b7fe;outline:0;box-shadow:0 0 0 .25rem rgba(13,110,253,.25)}.accordion-header{margin-bottom:0}.accordion-item{background-color:#fff;border:1px solid rgba(0,0,0,.125)}.accordion-item:first-of-type{border-top-left-radius:.25rem;border-top-right-radius:.25rem}.accordion-item:first-of-type .accordion-button{border-top-left-radius:calc(.25rem - 1px);border-top-right-radius:calc(.25rem - 1px)}.accordion-item:not(:first-of-type){border-top:0}.accordion-item:last-of-type{border-bottom-right-radius:.25rem;border-bottom-left-radius:.25rem}.accordion-item:last-of-type .accordion-button.collapsed{border-bottom-right-radius:calc(.25rem - 1px);border-bottom-left-radius:calc(.25rem - 1px)}.accordion-item:last-of-type .accordion-collapse{border-bottom-right-radius:.25rem;border-bottom-left-radius:.25rem}.accordion-body{padding:1rem 1.25rem}.accordion-flush .accordion-collapse{border-width:0}.accordion-flush .accordion-item{border-right:0;border-left:0;border-radius:0}.accordion-flush .accordion-item:first-child{border-top:0}.accordion-flush .accordion-item:last-child{border-bottom:0}.accordion-flush .accordion-item .accordion-button{border-radius:0}.breadcrumb{display:flex;flex-wrap:wrap;padding:0 0;margin-bottom:1rem;list-style:none}.breadcrumb-item+.breadcrumb-item{padding-left:.5rem}.breadcrumb-item+.breadcrumb-item::before{float:left;padding-right:.5rem;color:#6c757d;content:var(--bs-breadcrumb-divider, "/")}.breadcrumb-item.active{color:#6c757d}.pagination{display:flex;padding-left:0;list-style:none}.page-link{position:relative;display:block;color:#0d6efd;text-decoration:none;background-color:#fff;border:1px solid #dee2e6;transition:color .15s ease-in-out,background-color .15s ease-in-out,border-color .15s ease-in-out,box-shadow .15s ease-in-out}@media (prefers-reduced-motion:reduce){.page-link{transition:none}}.page-link:hover{z-index:2;color:#0a58ca;background-color:#e9ecef;border-color:#dee2e6}.page-link:focus{z-index:3;color:#0a58ca;background-color:#e9ecef;outline:0;box-shadow:0 0 0 .25rem rgba(13,110,253,.25)}.page-item:not(:first-child) .page-link{margin-left:-1px}.page-item.active .page-link{z-index:3;color:#fff;background-color:#0d6efd;border-color:#0d6efd}.page-item.disabled .page-link{color:#6c757d;pointer-events:none;background-color:#fff;border-color:#dee2e6}.page-link{padding:.375rem .75rem}.page-item:first-child .page-link{border-top-left-radius:.25rem;border-bottom-left-radius:.25rem}.page-item:last-child .page-link{border-top-right-radius:.25rem;border-bottom-right-radius:.25rem}.pagination-lg .page-link{padding:.75rem 1.5rem;font-size:1.25rem}.pagination-lg .page-item:first-child .page-link{border-top-left-radius:.3rem;border-bottom-left-radius:.3rem}.pagination-lg .page-item:last-child .page-link{border-top-right-radius:.3rem;border-bottom-right-radius:.3rem}.pagination-sm .page-link{padding:.25rem .5rem;font-size:.875rem}.pagination-sm .page-item:first-child .page-link{border-top-left-radius:.2rem;border-bottom-left-radius:.2rem}.pagination-sm .page-item:last-child .page-link{border-top-right-radius:.2rem;border-bottom-right-radius:.2rem}.badge{display:inline-block;padding:.35em .65em;font-size:.75em;font-weight:700;line-height:1;color:#fff;text-align:center;white-space:nowrap;vertical-align:baseline;border-radius:.25rem}.badge:empty{display:none}.btn .badge{position:relative;top:-1px}.alert{position:relative;padding:1rem 1rem;margin-bottom:1rem;border:1px solid transparent;border-radius:.25rem}.alert-heading{color:inherit}.alert-link{font-weight:700}.alert-dismissible{padding-right:3rem}.alert-dismissible .btn-close{position:absolute;top:0;right:0;z-index:2;padding:1.25rem 1rem}.alert-primary{color:#084298;background-color:#cfe2ff;border-color:#b6d4fe}.alert-primary .alert-link{color:#06357a}.alert-secondary{color:#41464b;background-color:#e2e3e5;border-color:#d3d6d8}.alert-secondary .alert-link{color:#34383c}.alert-success{color:#0f5132;background-color:#d1e7dd;border-color:#badbcc}.alert-success .alert-link{color:#0c4128}.alert-info{color:#055160;background-color:#cff4fc;border-color:#b6effb}.alert-info .alert-link{color:#04414d}.alert-warning{color:#664d03;background-color:#fff3cd;border-color:#ffecb5}.alert-warning .alert-link{color:#523e02}.alert-danger{color:#842029;background-color:#f8d7da;border-color:#f5c2c7}.alert-danger .alert-link{color:#6a1a21}.alert-light{color:#636464;background-color:#fefefe;border-color:#fdfdfe}.alert-light .alert-link{color:#4f5050}.alert-dark{color:#141619;background-color:#d3d3d4;border-color:#bcbebf}.alert-dark .alert-link{color:#101214}@-webkit-keyframes progress-bar-stripes{0%{background-position-x:1rem}}@keyframes progress-bar-stripes{0%{background-position-x:1rem}}.progress{display:flex;height:1rem;overflow:hidden;font-size:.75rem;background-color:#e9ecef;border-radius:.25rem}.progress-bar{display:flex;flex-direction:column;justify-content:center;overflow:hidden;color:#fff;text-align:center;white-space:nowrap;background-color:#0d6efd;transition:width .6s ease}@media (prefers-reduced-motion:reduce){.progress-bar{transition:none}}.progress-bar-striped{background-image:linear-gradient(45deg,rgba(255,255,255,.15) 25%,transparent 25%,transparent 50%,rgba(255,255,255,.15) 50%,rgba(255,255,255,.15) 75%,transparent 75%,transparent);background-size:1rem 1rem}.progress-bar-animated{-webkit-animation:1s linear infinite progress-bar-stripes;animation:1s linear infinite progress-bar-stripes}@media (prefers-reduced-motion:reduce){.progress-bar-animated{-webkit-animation:none;animation:none}}.list-group{display:flex;flex-direction:column;padding-left:0;margin-bottom:0;border-radius:.25rem}.list-group-numbered{list-style-type:none;counter-reset:section}.list-group-numbered>li::before{content:counters(section, ".") ". ";counter-increment:section}.list-group-item-action{width:100%;color:#495057;text-align:inherit}.list-group-item-action:focus,.list-group-item-action:hover{z-index:1;color:#495057;text-decoration:none;background-color:#f8f9fa}.list-group-item-action:active{color:#212529;background-color:#e9ecef}.list-group-item{position:relative;display:block;padding:.5rem 1rem;color:#212529;text-decoration:none;background-color:#fff;border:1px solid rgba(0,0,0,.125)}.list-group-item:first-child{border-top-left-radius:inherit;border-top-right-radius:inherit}.list-group-item:last-child{border-bottom-right-radius:inherit;border-bottom-left-radius:inherit}.list-group-item.disabled,.list-group-item:disabled{color:#6c757d;pointer-events:none;background-color:#fff}.list-group-item.active{z-index:2;color:#fff;background-color:#0d6efd;border-color:#0d6efd}.list-group-item+.list-group-item{border-top-width:0}.list-group-item+.list-group-item.active{margin-top:-1px;border-top-width:1px}.list-group-horizontal{flex-direction:row}.list-group-horizontal>.list-group-item:first-child{border-bottom-left-radius:.25rem;border-top-right-radius:0}.list-group-horizontal>.list-group-item:last-child{border-top-right-radius:.25rem;border-bottom-left-radius:0}.list-group-horizontal>.list-group-item.active{margin-top:0}.list-group-horizontal>.list-group-item+.list-group-item{border-top-width:1px;border-left-width:0}.list-group-horizontal>.list-group-item+.list-group-item.active{margin-left:-1px;border-left-width:1px}@media (min-width:576px){.list-group-horizontal-sm{flex-direction:row}.list-group-horizontal-sm>.list-group-item:first-child{border-bottom-left-radius:.25rem;border-top-right-radius:0}.list-group-horizontal-sm>.list-group-item:last-child{border-top-right-radius:.25rem;border-bottom-left-radius:0}.list-group-horizontal-sm>.list-group-item.active{margin-top:0}.list-group-horizontal-sm>.list-group-item+.list-group-item{border-top-width:1px;border-left-width:0}.list-group-horizontal-sm>.list-group-item+.list-group-item.active{margin-left:-1px;border-left-width:1px}}@media (min-width:768px){.list-group-horizontal-md{flex-direction:row}.list-group-horizontal-md>.list-group-item:first-child{border-bottom-left-radius:.25rem;border-top-right-radius:0}.list-group-horizontal-md>.list-group-item:last-child{border-top-right-radius:.25rem;border-bottom-left-radius:0}.list-group-horizontal-md>.list-group-item.active{margin-top:0}.list-group-horizontal-md>.list-group-item+.list-group-item{border-top-width:1px;border-left-width:0}.list-group-horizontal-md>.list-group-item+.list-group-item.active{margin-left:-1px;border-left-width:1px}}@media (min-width:992px){.list-group-horizontal-lg{flex-direction:row}.list-group-horizontal-lg>.list-group-item:first-child{border-bottom-left-radius:.25rem;border-top-right-radius:0}.list-group-horizontal-lg>.list-group-item:last-child{border-top-right-radius:.25rem;border-bottom-left-radius:0}.list-group-horizontal-lg>.list-group-item.active{margin-top:0}.list-group-horizontal-lg>.list-group-item+.list-group-item{border-top-width:1px;border-left-width:0}.list-group-horizontal-lg>.list-group-item+.list-group-item.active{margin-left:-1px;border-left-width:1px}}@media (min-width:1200px){.list-group-horizontal-xl{flex-direction:row}.list-group-horizontal-xl>.list-group-item:first-child{border-bottom-left-radius:.25rem;border-top-right-radius:0}.list-group-horizontal-xl>.list-group-item:last-child{border-top-right-radius:.25rem;border-bottom-left-radius:0}.list-group-horizontal-xl>.list-group-item.active{margin-top:0}.list-group-horizontal-xl>.list-group-item+.list-group-item{border-top-width:1px;border-left-width:0}.list-group-horizontal-xl>.list-group-item+.list-group-item.active{margin-left:-1px;border-left-width:1px}}@media (min-width:1400px){.list-group-horizontal-xxl{flex-direction:row}.list-group-horizontal-xxl>.list-group-item:first-child{border-bottom-left-radius:.25rem;border-top-right-radius:0}.list-group-horizontal-xxl>.list-group-item:last-child{border-top-right-radius:.25rem;border-bottom-left-radius:0}.list-group-horizontal-xxl>.list-group-item.active{margin-top:0}.list-group-horizontal-xxl>.list-group-item+.list-group-item{border-top-width:1px;border-left-width:0}.list-group-horizontal-xxl>.list-group-item+.list-group-item.active{margin-left:-1px;border-left-width:1px}}.list-group-flush{border-radius:0}.list-group-flush>.list-group-item{border-width:0 0 1px}.list-group-flush>.list-group-item:last-child{border-bottom-width:0}.list-group-item-primary{color:#084298;background-color:#cfe2ff}.list-group-item-primary.list-group-item-action:focus,.list-group-item-primary.list-group-item-action:hover{color:#084298;background-color:#bacbe6}.list-group-item-primary.list-group-item-action.active{color:#fff;background-color:#084298;border-color:#084298}.list-group-item-secondary{color:#41464b;background-color:#e2e3e5}.list-group-item-secondary.list-group-item-action:focus,.list-group-item-secondary.list-group-item-action:hover{color:#41464b;background-color:#cbccce}.list-group-item-secondary.list-group-item-action.active{color:#fff;background-color:#41464b;border-color:#41464b}.list-group-item-success{color:#0f5132;background-color:#d1e7dd}.list-group-item-success.list-group-item-action:focus,.list-group-item-success.list-group-item-action:hover{color:#0f5132;background-color:#bcd0c7}.list-group-item-success.list-group-item-action.active{color:#fff;background-color:#0f5132;border-color:#0f5132}.list-group-item-info{color:#055160;background-color:#cff4fc}.list-group-item-info.list-group-item-action:focus,.list-group-item-info.list-group-item-action:hover{color:#055160;background-color:#badce3}.list-group-item-info.list-group-item-action.active{color:#fff;background-color:#055160;border-color:#055160}.list-group-item-warning{color:#664d03;background-color:#fff3cd}.list-group-item-warning.list-group-item-action:focus,.list-group-item-warning.list-group-item-action:hover{color:#664d03;background-color:#e6dbb9}.list-group-item-warning.list-group-item-action.active{color:#fff;background-color:#664d03;border-color:#664d03}.list-group-item-danger{color:#842029;background-color:#f8d7da}.list-group-item-danger.list-group-item-action:focus,.list-group-item-danger.list-group-item-action:hover{color:#842029;background-color:#dfc2c4}.list-group-item-danger.list-group-item-action.active{color:#fff;background-color:#842029;border-color:#842029}.list-group-item-light{color:#636464;background-color:#fefefe}.list-group-item-light.list-group-item-action:focus,.list-group-item-light.list-group-item-action:hover{color:#636464;background-color:#e5e5e5}.list-group-item-light.list-group-item-action.active{color:#fff;background-color:#636464;border-color:#636464}.list-group-item-dark{color:#141619;background-color:#d3d3d4}.list-group-item-dark.list-group-item-action:focus,.list-group-item-dark.list-group-item-action:hover{color:#141619;background-color:#bebebf}.list-group-item-dark.list-group-item-action.active{color:#fff;background-color:#141619;border-color:#141619}.btn-close{box-sizing:content-box;width:1em;height:1em;padding:.25em .25em;color:#000;background:transparent url("data:image/svg+xml,%3csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16' fill='%23000'%3e%3cpath d='M.293.293a1 1 0 011.414 0L8 6.586 14.293.293a1 1 0 111.414 1.414L9.414 8l6.293 6.293a1 1 0 01-1.414 1.414L8 9.414l-6.293 6.293a1 1 0 01-1.414-1.414L6.586 8 .293 1.707a1 1 0 010-1.414z'/%3e%3c/svg%3e") center/1em auto no-repeat;border:0;border-radius:.25rem;opacity:.5}.btn-close:hover{color:#000;text-decoration:none;opacity:.75}.btn-close:focus{outline:0;box-shadow:0 0 0 .25rem rgba(13,110,253,.25);opacity:1}.btn-close.disabled,.btn-close:disabled{pointer-events:none;-webkit-user-select:none;-moz-user-select:none;user-select:none;opacity:.25}.btn-close-white{filter:invert(1) grayscale(100%) brightness(200%)}.toast{width:350px;max-width:100%;font-size:.875rem;pointer-events:auto;background-color:rgba(255,255,255,.85);background-clip:padding-box;border:1px solid rgba(0,0,0,.1);box-shadow:0 .5rem 1rem rgba(0,0,0,.15);border-radius:.25rem}.toast.showing{opacity:0}.toast:not(.show){display:none}.toast-container{width:-webkit-max-content;width:-moz-max-content;width:max-content;max-width:100%;pointer-events:none}.toast-container>:not(:last-child){margin-bottom:.75rem}.toast-header{display:flex;align-items:center;padding:.5rem .75rem;color:#6c757d;background-color:rgba(255,255,255,.85);background-clip:padding-box;border-bottom:1px solid rgba(0,0,0,.05);border-top-left-radius:calc(.25rem - 1px);border-top-right-radius:calc(.25rem - 1px)}.toast-header .btn-close{margin-right:-.375rem;margin-left:.75rem}.toast-body{padding:.75rem;word-wrap:break-word}.modal{position:fixed;top:0;left:0;z-index:1055;display:none;width:100%;height:100%;overflow-x:hidden;overflow-y:auto;outline:0}.modal-dialog{position:relative;width:auto;margin:.5rem;pointer-events:none}.modal.fade .modal-dialog{transition:transform .3s ease-out;transform:translate(0,-50px)}@media (prefers-reduced-motion:reduce){.modal.fade .modal-dialog{transition:none}}.modal.show .modal-dialog{transform:none}.modal.modal-static .modal-dialog{transform:scale(1.02)}.modal-dialog-scrollable{height:calc(100% - 1rem)}.modal-dialog-scrollable .modal-content{max-height:100%;overflow:hidden}.modal-dialog-scrollable .modal-body{overflow-y:auto}.modal-dialog-centered{display:flex;align-items:center;min-height:calc(100% - 1rem)}.modal-content{position:relative;display:flex;flex-direction:column;width:100%;pointer-events:auto;background-color:#fff;background-clip:padding-box;border:1px solid rgba(0,0,0,.2);border-radius:.3rem;outline:0}.modal-backdrop{position:fixed;top:0;left:0;z-index:1050;width:100vw;height:100vh;background-color:#000}.modal-backdrop.fade{opacity:0}.modal-backdrop.show{opacity:.5}.modal-header{display:flex;flex-shrink:0;align-items:center;justify-content:space-between;padding:1rem 1rem;border-bottom:1px solid #dee2e6;border-top-left-radius:calc(.3rem - 1px);border-top-right-radius:calc(.3rem - 1px)}.modal-header .btn-close{padding:.5rem .5rem;margin:-.5rem -.5rem -.5rem auto}.modal-title{margin-bottom:0;line-height:1.5}.modal-body{position:relative;flex:1 1 auto;padding:1rem}.modal-footer{display:flex;flex-wrap:wrap;flex-shrink:0;align-items:center;justify-content:flex-end;padding:.75rem;border-top:1px solid #dee2e6;border-bottom-right-radius:calc(.3rem - 1px);border-bottom-left-radius:calc(.3rem - 1px)}.modal-footer>*{margin:.25rem}@media (min-width:576px){.modal-dialog{max-width:500px;margin:1.75rem auto}.modal-dialog-scrollable{height:calc(100% - 3.5rem)}.modal-dialog-centered{min-height:calc(100% - 3.5rem)}.modal-sm{max-width:300px}}@media (min-width:992px){.modal-lg,.modal-xl{max-width:800px}}@media (min-width:1200px){.modal-xl{max-width:1140px}}.modal-fullscreen{width:100vw;max-width:none;height:100%;margin:0}.modal-fullscreen .modal-content{height:100%;border:0;border-radius:0}.modal-fullscreen .modal-header{border-radius:0}.modal-fullscreen .modal-body{overflow-y:auto}.modal-fullscreen .modal-footer{border-radius:0}@media (max-width:575.98px){.modal-fullscreen-sm-down{width:100vw;max-width:none;height:100%;margin:0}.modal-fullscreen-sm-down .modal-content{height:100%;border:0;border-radius:0}.modal-fullscreen-sm-down .modal-header{border-radius:0}.modal-fullscreen-sm-down .modal-body{overflow-y:auto}.modal-fullscreen-sm-down .modal-footer{border-radius:0}}@media (max-width:767.98px){.modal-fullscreen-md-down{width:100vw;max-width:none;height:100%;margin:0}.modal-fullscreen-md-down .modal-content{height:100%;border:0;border-radius:0}.modal-fullscreen-md-down .modal-header{border-radius:0}.modal-fullscreen-md-down .modal-body{overflow-y:auto}.modal-fullscreen-md-down .modal-footer{border-radius:0}}@media (max-width:991.98px){.modal-fullscreen-lg-down{width:100vw;max-width:none;height:100%;margin:0}.modal-fullscreen-lg-down .modal-content{height:100%;border:0;border-radius:0}.modal-fullscreen-lg-down .modal-header{border-radius:0}.modal-fullscreen-lg-down .modal-body{overflow-y:auto}.modal-fullscreen-lg-down .modal-footer{border-radius:0}}@media (max-width:1199.98px){.modal-fullscreen-xl-down{width:100vw;max-width:none;height:100%;margin:0}.modal-fullscreen-xl-down .modal-content{height:100%;border:0;border-radius:0}.modal-fullscreen-xl-down .modal-header{border-radius:0}.modal-fullscreen-xl-down .modal-body{overflow-y:auto}.modal-fullscreen-xl-down .modal-footer{border-radius:0}}@media (max-width:1399.98px){.modal-fullscreen-xxl-down{width:100vw;max-width:none;height:100%;margin:0}.modal-fullscreen-xxl-down .modal-content{height:100%;border:0;border-radius:0}.modal-fullscreen-xxl-down .modal-header{border-radius:0}.modal-fullscreen-xxl-down .modal-body{overflow-y:auto}.modal-fullscreen-xxl-down .modal-footer{border-radius:0}}.tooltip{position:absolute;z-index:1080;display:block;margin:0;font-family:var(--bs-font-sans-serif);font-style:normal;font-weight:400;line-height:1.5;text-align:left;text-align:start;text-decoration:none;text-shadow:none;text-transform:none;letter-spacing:normal;word-break:normal;word-spacing:normal;white-space:normal;line-break:auto;font-size:.875rem;word-wrap:break-word;opacity:0}.tooltip.show{opacity:.9}.tooltip .tooltip-arrow{position:absolute;display:block;width:.8rem;height:.4rem}.tooltip .tooltip-arrow::before{position:absolute;content:"";border-color:transparent;border-style:solid}.bs-tooltip-auto[data-popper-placement^=top],.bs-tooltip-top{padding:.4rem 0}.bs-tooltip-auto[data-popper-placement^=top] .tooltip-arrow,.bs-tooltip-top .tooltip-arrow{bottom:0}.bs-tooltip-auto[data-popper-placement^=top] .tooltip-arrow::before,.bs-tooltip-top .tooltip-arrow::before{top:-1px;border-width:.4rem .4rem 0;border-top-color:#000}.bs-tooltip-auto[data-popper-placement^=right],.bs-tooltip-end{padding:0 .4rem}.bs-tooltip-auto[data-popper-placement^=right] .tooltip-arrow,.bs-tooltip-end .tooltip-arrow{left:0;width:.4rem;height:.8rem}.bs-tooltip-auto[data-popper-placement^=right] .tooltip-arrow::before,.bs-tooltip-end .tooltip-arrow::before{right:-1px;border-width:.4rem .4rem .4rem 0;border-right-color:#000}.bs-tooltip-auto[data-popper-placement^=bottom],.bs-tooltip-bottom{padding:.4rem 0}.bs-tooltip-auto[data-popper-placement^=bottom] .tooltip-arrow,.bs-tooltip-bottom .tooltip-arrow{top:0}.bs-tooltip-auto[data-popper-placement^=bottom] .tooltip-arrow::before,.bs-tooltip-bottom .tooltip-arrow::before{bottom:-1px;border-width:0 .4rem .4rem;border-bottom-color:#000}.bs-tooltip-auto[data-popper-placement^=left],.bs-tooltip-start{padding:0 .4rem}.bs-tooltip-auto[data-popper-placement^=left] .tooltip-arrow,.bs-tooltip-start .tooltip-arrow{right:0;width:.4rem;height:.8rem}.bs-tooltip-auto[data-popper-placement^=left] .tooltip-arrow::before,.bs-tooltip-start .tooltip-arrow::before{left:-1px;border-width:.4rem 0 .4rem .4rem;border-left-color:#000}.tooltip-inner{max-width:200px;padding:.25rem .5rem;color:#fff;text-align:center;background-color:#000;border-radius:.25rem}.popover{position:absolute;top:0;left:0;z-index:1070;display:block;max-width:276px;font-family:var(--bs-font-sans-serif);font-style:normal;font-weight:400;line-height:1.5;text-align:left;text-align:start;text-decoration:none;text-shadow:none;text-transform:none;letter-spacing:normal;word-break:normal;word-spacing:normal;white-space:normal;line-break:auto;font-size:.875rem;word-wrap:break-word;background-color:#fff;background-clip:padding-box;border:1px solid rgba(0,0,0,.2);border-radius:.3rem}.popover .popover-arrow{position:absolute;display:block;width:1rem;height:.5rem}.popover .popover-arrow::after,.popover .popover-arrow::before{position:absolute;display:block;content:"";border-color:transparent;border-style:solid}.bs-popover-auto[data-popper-placement^=top]>.popover-arrow,.bs-popover-top>.popover-arrow{bottom:calc(-.5rem - 1px)}.bs-popover-auto[data-popper-placement^=top]>.popover-arrow::before,.bs-popover-top>.popover-arrow::before{bottom:0;border-width:.5rem .5rem 0;border-top-color:rgba(0,0,0,.25)}.bs-popover-auto[data-popper-placement^=top]>.popover-arrow::after,.bs-popover-top>.popover-arrow::after{bottom:1px;border-width:.5rem .5rem 0;border-top-color:#fff}.bs-popover-auto[data-popper-placement^=right]>.popover-arrow,.bs-popover-end>.popover-arrow{left:calc(-.5rem - 1px);width:.5rem;height:1rem}.bs-popover-auto[data-popper-placement^=right]>.popover-arrow::before,.bs-popover-end>.popover-arrow::before{left:0;border-width:.5rem .5rem .5rem 0;border-right-color:rgba(0,0,0,.25)}.bs-popover-auto[data-popper-placement^=right]>.popover-arrow::after,.bs-popover-end>.popover-arrow::after{left:1px;border-width:.5rem .5rem .5rem 0;border-right-color:#fff}.bs-popover-auto[data-popper-placement^=bottom]>.popover-arrow,.bs-popover-bottom>.popover-arrow{top:calc(-.5rem - 1px)}.bs-popover-auto[data-popper-placement^=bottom]>.popover-arrow::before,.bs-popover-bottom>.popover-arrow::before{top:0;border-width:0 .5rem .5rem .5rem;border-bottom-color:rgba(0,0,0,.25)}.bs-popover-auto[data-popper-placement^=bottom]>.popover-arrow::after,.bs-popover-bottom>.popover-arrow::after{top:1px;border-width:0 .5rem .5rem .5rem;border-bottom-color:#fff}.bs-popover-auto[data-popper-placement^=bottom] .popover-header::before,.bs-popover-bottom .popover-header::before{position:absolute;top:0;left:50%;display:block;width:1rem;margin-left:-.5rem;content:"";border-bottom:1px solid #f0f0f0}.bs-popover-auto[data-popper-placement^=left]>.popover-arrow,.bs-popover-start>.popover-arrow{right:calc(-.5rem - 1px);width:.5rem;height:1rem}.bs-popover-auto[data-popper-placement^=left]>.popover-arrow::before,.bs-popover-start>.popover-arrow::before{right:0;border-width:.5rem 0 .5rem .5rem;border-left-color:rgba(0,0,0,.25)}.bs-popover-auto[data-popper-placement^=left]>.popover-arrow::after,.bs-popover-start>.popover-arrow::after{right:1px;border-width:.5rem 0 .5rem .5rem;border-left-color:#fff}.popover-header{padding:.5rem 1rem;margin-bottom:0;font-size:1rem;background-color:#f0f0f0;border-bottom:1px solid rgba(0,0,0,.2);border-top-left-radius:calc(.3rem - 1px);border-top-right-radius:calc(.3rem - 1px)}.popover-header:empty{display:none}.popover-body{padding:1rem 1rem;color:#212529}.carousel{position:relative}.carousel.pointer-event{touch-action:pan-y}.carousel-inner{position:relative;width:100%;overflow:hidden}.carousel-inner::after{display:block;clear:both;content:""}.carousel-item{position:relative;display:none;float:left;width:100%;margin-right:-100%;-webkit-backface-visibility:hidden;backface-visibility:hidden;transition:transform .6s ease-in-out}@media (prefers-reduced-motion:reduce){.carousel-item{transition:none}}.carousel-item-next,.carousel-item-prev,.carousel-item.active{display:block}.active.carousel-item-end,.carousel-item-next:not(.carousel-item-start){transform:translateX(100%)}.active.carousel-item-start,.carousel-item-prev:not(.carousel-item-end){transform:translateX(-100%)}.carousel-fade .carousel-item{opacity:0;transition-property:opacity;transform:none}.carousel-fade .carousel-item-next.carousel-item-start,.carousel-fade .carousel-item-prev.carousel-item-end,.carousel-fade .carousel-item.active{z-index:1;opacity:1}.carousel-fade .active.carousel-item-end,.carousel-fade .active.carousel-item-start{z-index:0;opacity:0;transition:opacity 0s .6s}@media (prefers-reduced-motion:reduce){.carousel-fade .active.carousel-item-end,.carousel-fade .active.carousel-item-start{transition:none}}.carousel-control-next,.carousel-control-prev{position:absolute;top:0;bottom:0;z-index:1;display:flex;align-items:center;justify-content:center;width:15%;padding:0;color:#fff;text-align:center;background:0 0;border:0;opacity:.5;transition:opacity .15s ease}@media (prefers-reduced-motion:reduce){.carousel-control-next,.carousel-control-prev{transition:none}}.carousel-control-next:focus,.carousel-control-next:hover,.carousel-control-prev:focus,.carousel-control-prev:hover{color:#fff;text-decoration:none;outline:0;opacity:.9}.carousel-control-prev{left:0}.carousel-control-next{right:0}.carousel-control-next-icon,.carousel-control-prev-icon{display:inline-block;width:2rem;height:2rem;background-repeat:no-repeat;background-position:50%;background-size:100% 100%}.carousel-control-prev-icon{background-image:url("data:image/svg+xml,%3csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16' fill='%23fff'%3e%3cpath d='M11.354 1.646a.5.5 0 0 1 0 .708L5.707 8l5.647 5.646a.5.5 0 0 1-.708.708l-6-6a.5.5 0 0 1 0-.708l6-6a.5.5 0 0 1 .708 0z'/%3e%3c/svg%3e")}.carousel-control-next-icon{background-image:url("data:image/svg+xml,%3csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16' fill='%23fff'%3e%3cpath d='M4.646 1.646a.5.5 0 0 1 .708 0l6 6a.5.5 0 0 1 0 .708l-6 6a.5.5 0 0 1-.708-.708L10.293 8 4.646 2.354a.5.5 0 0 1 0-.708z'/%3e%3c/svg%3e")}.carousel-indicators{position:absolute;right:0;bottom:0;left:0;z-index:2;display:flex;justify-content:center;padding:0;margin-right:15%;margin-bottom:1rem;margin-left:15%;list-style:none}.carousel-indicators [data-bs-target]{box-sizing:content-box;flex:0 1 auto;width:30px;height:3px;padding:0;margin-right:3px;margin-left:3px;text-indent:-999px;cursor:pointer;background-color:#fff;background-clip:padding-box;border:0;border-top:10px solid transparent;border-bottom:10px solid transparent;opacity:.5;transition:opacity .6s ease}@media (prefers-reduced-motion:reduce){.carousel-indicators [data-bs-target]{transition:none}}.carousel-indicators .active{opacity:1}.carousel-caption{position:absolute;right:15%;bottom:1.25rem;left:15%;padding-top:1.25rem;padding-bottom:1.25rem;color:#fff;text-align:center}.carousel-dark .carousel-control-next-icon,.carousel-dark .carousel-control-prev-icon{filter:invert(1) grayscale(100)}.carousel-dark .carousel-indicators [data-bs-target]{background-color:#000}.carousel-dark .carousel-caption{color:#000}@-webkit-keyframes spinner-border{to{transform:rotate(360deg)}}@keyframes spinner-border{to{transform:rotate(360deg)}}.spinner-border{display:inline-block;width:2rem;height:2rem;vertical-align:-.125em;border:.25em solid currentColor;border-right-color:transparent;border-radius:50%;-webkit-animation:.75s linear infinite spinner-border;animation:.75s linear infinite spinner-border}.spinner-border-sm{width:1rem;height:1rem;border-width:.2em}@-webkit-keyframes spinner-grow{0%{transform:scale(0)}50%{opacity:1;transform:none}}@keyframes spinner-grow{0%{transform:scale(0)}50%{opacity:1;transform:none}}.spinner-grow{display:inline-block;width:2rem;height:2rem;vertical-align:-.125em;background-color:currentColor;border-radius:50%;opacity:0;-webkit-animation:.75s linear infinite spinner-grow;animation:.75s linear infinite spinner-grow}.spinner-grow-sm{width:1rem;height:1rem}@media (prefers-reduced-motion:reduce){.spinner-border,.spinner-grow{-webkit-animation-duration:1.5s;animation-duration:1.5s}}.offcanvas{position:fixed;bottom:0;z-index:1045;display:flex;flex-direction:column;max-width:100%;visibility:hidden;background-color:#fff;background-clip:padding-box;outline:0;transition:transform .3s ease-in-out}@media (prefers-reduced-motion:reduce){.offcanvas{transition:none}}.offcanvas-backdrop{position:fixed;top:0;left:0;z-index:1040;width:100vw;height:100vh;background-color:#000}.offcanvas-backdrop.fade{opacity:0}.offcanvas-backdrop.show{opacity:.5}.offcanvas-header{display:flex;align-items:center;justify-content:space-between;padding:1rem 1rem}.offcanvas-header .btn-close{padding:.5rem .5rem;margin-top:-.5rem;margin-right:-.5rem;margin-bottom:-.5rem}.offcanvas-title{margin-bottom:0;line-height:1.5}.offcanvas-body{flex-grow:1;padding:1rem 1rem;overflow-y:auto}.offcanvas-start{top:0;left:0;width:400px;border-right:1px solid rgba(0,0,0,.2);transform:translateX(-100%)}.offcanvas-end{top:0;right:0;width:400px;border-left:1px solid rgba(0,0,0,.2);transform:translateX(100%)}.offcanvas-top{top:0;right:0;left:0;height:30vh;max-height:100%;border-bottom:1px solid rgba(0,0,0,.2);transform:translateY(-100%)}.offcanvas-bottom{right:0;left:0;height:30vh;max-height:100%;border-top:1px solid rgba(0,0,0,.2);transform:translateY(100%)}.offcanvas.show{transform:none}.placeholder{display:inline-block;min-height:1em;vertical-align:middle;cursor:wait;background-color:currentColor;opacity:.5}.placeholder.btn::before{display:inline-block;content:""}.placeholder-xs{min-height:.6em}.placeholder-sm{min-height:.8em}.placeholder-lg{min-height:1.2em}.placeholder-glow .placeholder{-webkit-animation:placeholder-glow 2s ease-in-out infinite;animation:placeholder-glow 2s ease-in-out infinite}@-webkit-keyframes placeholder-glow{50%{opacity:.2}}@keyframes placeholder-glow{50%{opacity:.2}}.placeholder-wave{-webkit-mask-image:linear-gradient(130deg,#000 55%,rgba(0,0,0,0.8) 75%,#000 95%);mask-image:linear-gradient(130deg,#000 55%,rgba(0,0,0,0.8) 75%,#000 95%);-webkit-mask-size:200% 100%;mask-size:200% 100%;-webkit-animation:placeholder-wave 2s linear infinite;animation:placeholder-wave 2s linear infinite}@-webkit-keyframes placeholder-wave{100%{-webkit-mask-position:-200% 0%;mask-position:-200% 0%}}@keyframes placeholder-wave{100%{-webkit-mask-position:-200% 0%;mask-position:-200% 0%}}.clearfix::after{display:block;clear:both;content:""}.link-primary{color:#0d6efd}.link-primary:focus,.link-primary:hover{color:#0a58ca}.link-secondary{color:#6c757d}.link-secondary:focus,.link-secondary:hover{color:#565e64}.link-success{color:#198754}.link-success:focus,.link-success:hover{color:#146c43}.link-info{color:#0dcaf0}.link-info:focus,.link-info:hover{color:#3dd5f3}.link-warning{color:#ffc107}.link-warning:focus,.link-warning:hover{color:#ffcd39}.link-danger{color:#dc3545}.link-danger:focus,.link-danger:hover{color:#b02a37}.link-light{color:#f8f9fa}.link-light:focus,.link-light:hover{color:#f9fafb}.link-dark{color:#212529}.link-dark:focus,.link-dark:hover{color:#1a1e21}.ratio{position:relative;width:100%}.ratio::before{display:block;padding-top:var(--bs-aspect-ratio);content:""}.ratio>*{position:absolute;top:0;left:0;width:100%;height:100%}.ratio-1x1{--bs-aspect-ratio:100%}.ratio-4x3{--bs-aspect-ratio:75%}.ratio-16x9{--bs-aspect-ratio:56.25%}.ratio-21x9{--bs-aspect-ratio:42.8571428571%}.fixed-top{position:fixed;top:0;right:0;left:0;z-index:1030}.fixed-bottom{position:fixed;right:0;bottom:0;left:0;z-index:1030}.sticky-top{position:-webkit-sticky;position:sticky;top:0;z-index:1020}@media (min-width:576px){.sticky-sm-top{position:-webkit-sticky;position:sticky;top:0;z-index:1020}}@media (min-width:768px){.sticky-md-top{position:-webkit-sticky;position:sticky;top:0;z-index:1020}}@media (min-width:992px){.sticky-lg-top{position:-webkit-sticky;position:sticky;top:0;z-index:1020}}@media (min-width:1200px){.sticky-xl-top{position:-webkit-sticky;position:sticky;top:0;z-index:1020}}@media (min-width:1400px){.sticky-xxl-top{position:-webkit-sticky;position:sticky;top:0;z-index:1020}}.hstack{display:flex;flex-direction:row;align-items:center;align-self:stretch}.vstack{display:flex;flex:1 1 auto;flex-direction:column;align-self:stretch}.visually-hidden,.visually-hidden-focusable:not(:focus):not(:focus-within){position:absolute!important;width:1px!important;height:1px!important;padding:0!important;margin:-1px!important;overflow:hidden!important;clip:rect(0,0,0,0)!important;white-space:nowrap!important;border:0!important}.stretched-link::after{position:absolute;top:0;right:0;bottom:0;left:0;z-index:1;content:""}.text-truncate{overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.vr{display:inline-block;align-self:stretch;width:1px;min-height:1em;background-color:currentColor;opacity:.25}.align-baseline{vertical-align:baseline!important}.align-top{vertical-align:top!important}.align-middle{vertical-align:middle!important}.align-bottom{vertical-align:bottom!important}.align-text-bottom{vertical-align:text-bottom!important}.align-text-top{vertical-align:text-top!important}.float-start{float:left!important}.float-end{float:right!important}.float-none{float:none!important}.opacity-0{opacity:0!important}.opacity-25{opacity:.25!important}.opacity-50{opacity:.5!important}.opacity-75{opacity:.75!important}.opacity-100{opacity:1!important}.overflow-auto{overflow:auto!important}.overflow-hidden{overflow:hidden!important}.overflow-visible{overflow:visible!important}.overflow-scroll{overflow:scroll!important}.d-inline{display:inline!important}.d-inline-block{display:inline-block!important}.d-block{display:block!important}.d-grid{display:grid!important}.d-table{display:table!important}.d-table-row{display:table-row!important}.d-table-cell{display:table-cell!important}.d-flex{display:flex!important}.d-inline-flex{display:inline-flex!important}.d-none{display:none!important}.shadow{box-shadow:0 .5rem 1rem rgba(0,0,0,.15)!important}.shadow-sm{box-shadow:0 .125rem .25rem rgba(0,0,0,.075)!important}.shadow-lg{box-shadow:0 1rem 3rem rgba(0,0,0,.175)!important}.shadow-none{box-shadow:none!important}.position-static{position:static!important}.position-relative{position:relative!important}.position-absolute{position:absolute!important}.position-fixed{position:fixed!important}.position-sticky{position:-webkit-sticky!important;position:sticky!important}.top-0{top:0!important}.top-50{top:50%!important}.top-100{top:100%!important}.bottom-0{bottom:0!important}.bottom-50{bottom:50%!important}.bottom-100{bottom:100%!important}.start-0{left:0!important}.start-50{left:50%!important}.start-100{left:100%!important}.end-0{right:0!important}.end-50{right:50%!important}.end-100{right:100%!important}.translate-middle{transform:translate(-50%,-50%)!important}.translate-middle-x{transform:translateX(-50%)!important}.translate-middle-y{transform:translateY(-50%)!important}.border{border:1px solid #dee2e6!important}.border-0{border:0!important}.border-top{border-top:1px solid #dee2e6!important}.border-top-0{border-top:0!important}.border-end{border-right:1px solid #dee2e6!important}.border-end-0{border-right:0!important}.border-bottom{border-bottom:1px solid #dee2e6!important}.border-bottom-0{border-bottom:0!important}.border-start{border-left:1px solid #dee2e6!important}.border-start-0{border-left:0!important}.border-primary{border-color:#0d6efd!important}.border-secondary{border-color:#6c757d!important}.border-success{border-color:#198754!important}.border-info{border-color:#0dcaf0!important}.border-warning{border-color:#ffc107!important}.border-danger{border-color:#dc3545!important}.border-light{border-color:#f8f9fa!important}.border-dark{border-color:#212529!important}.border-white{border-color:#fff!important}.border-1{border-width:1px!important}.border-2{border-width:2px!important}.border-3{border-width:3px!important}.border-4{border-width:4px!important}.border-5{border-width:5px!important}.w-25{width:25%!important}.w-50{width:50%!important}.w-75{width:75%!important}.w-100{width:100%!important}.w-auto{width:auto!important}.mw-100{max-width:100%!important}.vw-100{width:100vw!important}.min-vw-100{min-width:100vw!important}.h-25{height:25%!important}.h-50{height:50%!important}.h-75{height:75%!important}.h-100{height:100%!important}.h-auto{height:auto!important}.mh-100{max-height:100%!important}.vh-100{height:100vh!important}.min-vh-100{min-height:100vh!important}.flex-fill{flex:1 1 auto!important}.flex-row{flex-direction:row!important}.flex-column{flex-direction:column!important}.flex-row-reverse{flex-direction:row-reverse!important}.flex-column-reverse{flex-direction:column-reverse!important}.flex-grow-0{flex-grow:0!important}.flex-grow-1{flex-grow:1!important}.flex-shrink-0{flex-shrink:0!important}.flex-shrink-1{flex-shrink:1!important}.flex-wrap{flex-wrap:wrap!important}.flex-nowrap{flex-wrap:nowrap!important}.flex-wrap-reverse{flex-wrap:wrap-reverse!important}.gap-0{gap:0!important}.gap-1{gap:.25rem!important}.gap-2{gap:.5rem!important}.gap-3{gap:1rem!important}.gap-4{gap:1.5rem!important}.gap-5{gap:3rem!important}.justify-content-start{justify-content:flex-start!important}.justify-content-end{justify-content:flex-end!important}.justify-content-center{justify-content:center!important}.justify-content-between{justify-content:space-between!important}.justify-content-around{justify-content:space-around!important}.justify-content-evenly{justify-content:space-evenly!important}.align-items-start{align-items:flex-start!important}.align-items-end{align-items:flex-end!important}.align-items-center{align-items:center!important}.align-items-baseline{align-items:baseline!important}.align-items-stretch{align-items:stretch!important}.align-content-start{align-content:flex-start!important}.align-content-end{align-content:flex-end!important}.align-content-center{align-content:center!important}.align-content-between{align-content:space-between!important}.align-content-around{align-content:space-around!important}.align-content-stretch{align-content:stretch!important}.align-self-auto{align-self:auto!important}.align-self-start{align-self:flex-start!important}.align-self-end{align-self:flex-end!important}.align-self-center{align-self:center!important}.align-self-baseline{align-self:baseline!important}.align-self-stretch{align-self:stretch!important}.order-first{order:-1!important}.order-0{order:0!important}.order-1{order:1!important}.order-2{order:2!important}.order-3{order:3!important}.order-4{order:4!important}.order-5{order:5!important}.order-last{order:6!important}.m-0{margin:0!important}.m-1{margin:.25rem!important}.m-2{margin:.5rem!important}.m-3{margin:1rem!important}.m-4{margin:1.5rem!important}.m-5{margin:3rem!important}.m-auto{margin:auto!important}.mx-0{margin-right:0!important;margin-left:0!important}.mx-1{margin-right:.25rem!important;margin-left:.25rem!important}.mx-2{margin-right:.5rem!important;margin-left:.5rem!important}.mx-3{margin-right:1rem!important;margin-left:1rem!important}.mx-4{margin-right:1.5rem!important;margin-left:1.5rem!important}.mx-5{margin-right:3rem!important;margin-left:3rem!important}.mx-auto{margin-right:auto!important;margin-left:auto!important}.my-0{margin-top:0!important;margin-bottom:0!important}.my-1{margin-top:.25rem!important;margin-bottom:.25rem!important}.my-2{margin-top:.5rem!important;margin-bottom:.5rem!important}.my-3{margin-top:1rem!important;margin-bottom:1rem!important}.my-4{margin-top:1.5rem!important;margin-bottom:1.5rem!important}.my-5{margin-top:3rem!important;margin-bottom:3rem!important}.my-auto{margin-top:auto!important;margin-bottom:auto!important}.mt-0{margin-top:0!important}.mt-1{margin-top:.25rem!important}.mt-2{margin-top:.5rem!important}.mt-3{margin-top:1rem!important}.mt-4{margin-top:1.5rem!important}.mt-5{margin-top:3rem!important}.mt-auto{margin-top:auto!important}.me-0{margin-right:0!important}.me-1{margin-right:.25rem!important}.me-2{margin-right:.5rem!important}.me-3{margin-right:1rem!important}.me-4{margin-right:1.5rem!important}.me-5{margin-right:3rem!important}.me-auto{margin-right:auto!important}.mb-0{margin-bottom:0!important}.mb-1{margin-bottom:.25rem!important}.mb-2{margin-bottom:.5rem!important}.mb-3{margin-bottom:1rem!important}.mb-4{margin-bottom:1.5rem!important}.mb-5{margin-bottom:3rem!important}.mb-auto{margin-bottom:auto!important}.ms-0{margin-left:0!important}.ms-1{margin-left:.25rem!important}.ms-2{margin-left:.5rem!important}.ms-3{margin-left:1rem!important}.ms-4{margin-left:1.5rem!important}.ms-5{margin-left:3rem!important}.ms-auto{margin-left:auto!important}.p-0{padding:0!important}.p-1{padding:.25rem!important}.p-2{padding:.5rem!important}.p-3{padding:1rem!important}.p-4{padding:1.5rem!important}.p-5{padding:3rem!important}.px-0{padding-right:0!important;padding-left:0!important}.px-1{padding-right:.25rem!important;padding-left:.25rem!important}.px-2{padding-right:.5rem!important;padding-left:.5rem!important}.px-3{padding-right:1rem!important;padding-left:1rem!important}.px-4{padding-right:1.5rem!important;padding-left:1.5rem!important}.px-5{padding-right:3rem!important;padding-left:3rem!important}.py-0{padding-top:0!important;padding-bottom:0!important}.py-1{padding-top:.25rem!important;padding-bottom:.25rem!important}.py-2{padding-top:.5rem!important;padding-bottom:.5rem!important}.py-3{padding-top:1rem!important;padding-bottom:1rem!important}.py-4{padding-top:1.5rem!important;padding-bottom:1.5rem!important}.py-5{padding-top:3rem!important;padding-bottom:3rem!important}.pt-0{padding-top:0!important}.pt-1{padding-top:.25rem!important}.pt-2{padding-top:.5rem!important}.pt-3{padding-top:1rem!important}.pt-4{padding-top:1.5rem!important}.pt-5{padding-top:3rem!important}.pe-0{padding-right:0!important}.pe-1{padding-right:.25rem!important}.pe-2{padding-right:.5rem!important}.pe-3{padding-right:1rem!important}.pe-4{padding-right:1.5rem!important}.pe-5{padding-right:3rem!important}.pb-0{padding-bottom:0!important}.pb-1{padding-bottom:.25rem!important}.pb-2{padding-bottom:.5rem!important}.pb-3{padding-bottom:1rem!important}.pb-4{padding-bottom:1.5rem!important}.pb-5{padding-bottom:3rem!important}.ps-0{padding-left:0!important}.ps-1{padding-left:.25rem!important}.ps-2{padding-left:.5rem!important}.ps-3{padding-left:1rem!important}.ps-4{padding-left:1.5rem!important}.ps-5{padding-left:3rem!important}.font-monospace{font-family:var(--bs-font-monospace)!important}.fs-1{font-size:calc(1.375rem + 1.5vw)!important}.fs-2{font-size:calc(1.325rem + .9vw)!important}.fs-3{font-size:calc(1.3rem + .6vw)!important}.fs-4{font-size:calc(1.275rem + .3vw)!important}.fs-5{font-size:1.25rem!important}.fs-6{font-size:1rem!important}.fst-italic{font-style:italic!important}.fst-normal{font-style:normal!important}.fw-light{font-weight:300!important}.fw-lighter{font-weight:lighter!important}.fw-normal{font-weight:400!important}.fw-bold{font-weight:700!important}.fw-bolder{font-weight:bolder!important}.lh-1{line-height:1!important}.lh-sm{line-height:1.25!important}.lh-base{line-height:1.5!important}.lh-lg{line-height:2!important}.text-start{text-align:left!important}.text-end{text-align:right!important}.text-center{text-align:center!important}.text-decoration-none{text-decoration:none!important}.text-decoration-underline{text-decoration:underline!important}.text-decoration-line-through{text-decoration:line-through!important}.text-lowercase{text-transform:lowercase!important}.text-uppercase{text-transform:uppercase!important}.text-capitalize{text-transform:capitalize!important}.text-wrap{white-space:normal!important}.text-nowrap{white-space:nowrap!important}.text-break{word-wrap:break-word!important;word-break:break-word!important}.text-primary{--bs-text-opacity:1;color:rgba(var(--bs-primary-rgb),var(--bs-text-opacity))!important}.text-secondary{--bs-text-opacity:1;color:rgba(var(--bs-secondary-rgb),var(--bs-text-opacity))!important}.text-success{--bs-text-opacity:1;color:rgba(var(--bs-success-rgb),var(--bs-text-opacity))!important}.text-info{--bs-text-opacity:1;color:rgba(var(--bs-info-rgb),var(--bs-text-opacity))!important}.text-warning{--bs-text-opacity:1;color:rgba(var(--bs-warning-rgb),var(--bs-text-opacity))!important}.text-danger{--bs-text-opacity:1;color:rgba(var(--bs-danger-rgb),var(--bs-text-opacity))!important}.text-light{--bs-text-opacity:1;color:rgba(var(--bs-light-rgb),var(--bs-text-opacity))!important}.text-dark{--bs-text-opacity:1;color:rgba(var(--bs-dark-rgb),var(--bs-text-opacity))!important}.text-black{--bs-text-opacity:1;color:rgba(var(--bs-black-rgb),var(--bs-text-opacity))!important}.text-white{--bs-text-opacity:1;color:rgba(var(--bs-white-rgb),var(--bs-text-opacity))!important}.text-body{--bs-text-opacity:1;color:rgba(var(--bs-body-color-rgb),var(--bs-text-opacity))!important}.text-muted{--bs-text-opacity:1;color:#6c757d!important}.text-black-50{--bs-text-opacity:1;color:rgba(0,0,0,.5)!important}.text-white-50{--bs-text-opacity:1;color:rgba(255,255,255,.5)!important}.text-reset{--bs-text-opacity:1;color:inherit!important}.text-opacity-25{--bs-text-opacity:0.25}.text-opacity-50{--bs-text-opacity:0.5}.text-opacity-75{--bs-text-opacity:0.75}.text-opacity-100{--bs-text-opacity:1}.bg-primary{--bs-bg-opacity:1;background-color:rgba(var(--bs-primary-rgb),var(--bs-bg-opacity))!important}.bg-secondary{--bs-bg-opacity:1;background-color:rgba(var(--bs-secondary-rgb),var(--bs-bg-opacity))!important}.bg-success{--bs-bg-opacity:1;background-color:rgba(var(--bs-success-rgb),var(--bs-bg-opacity))!important}.bg-info{--bs-bg-opacity:1;background-color:rgba(var(--bs-info-rgb),var(--bs-bg-opacity))!important}.bg-warning{--bs-bg-opacity:1;background-color:rgba(var(--bs-warning-rgb),var(--bs-bg-opacity))!important}.bg-danger{--bs-bg-opacity:1;background-color:rgba(var(--bs-danger-rgb),var(--bs-bg-opacity))!important}.bg-light{--bs-bg-opacity:1;background-color:rgba(var(--bs-light-rgb),var(--bs-bg-opacity))!important}.bg-dark{--bs-bg-opacity:1;background-color:rgba(var(--bs-dark-rgb),var(--bs-bg-opacity))!important}.bg-black{--bs-bg-opacity:1;background-color:rgba(var(--bs-black-rgb),var(--bs-bg-opacity))!important}.bg-white{--bs-bg-opacity:1;background-color:rgba(var(--bs-white-rgb),var(--bs-bg-opacity))!important}.bg-body{--bs-bg-opacity:1;background-color:rgba(var(--bs-body-bg-rgb),var(--bs-bg-opacity))!important}.bg-transparent{--bs-bg-opacity:1;background-color:transparent!important}.bg-opacity-10{--bs-bg-opacity:0.1}.bg-opacity-25{--bs-bg-opacity:0.25}.bg-opacity-50{--bs-bg-opacity:0.5}.bg-opacity-75{--bs-bg-opacity:0.75}.bg-opacity-100{--bs-bg-opacity:1}.bg-gradient{background-image:var(--bs-gradient)!important}.user-select-all{-webkit-user-select:all!important;-moz-user-select:all!important;user-select:all!important}.user-select-auto{-webkit-user-select:auto!important;-moz-user-select:auto!important;user-select:auto!important}.user-select-none{-webkit-user-select:none!important;-moz-user-select:none!important;user-select:none!important}.pe-none{pointer-events:none!important}.pe-auto{pointer-events:auto!important}.rounded{border-radius:.25rem!important}.rounded-0{border-radius:0!important}.rounded-1{border-radius:.2rem!important}.rounded-2{border-radius:.25rem!important}.rounded-3{border-radius:.3rem!important}.rounded-circle{border-radius:50%!important}.rounded-pill{border-radius:50rem!important}.rounded-top{border-top-left-radius:.25rem!important;border-top-right-radius:.25rem!important}.rounded-end{border-top-right-radius:.25rem!important;border-bottom-right-radius:.25rem!important}.rounded-bottom{border-bottom-right-radius:.25rem!important;border-bottom-left-radius:.25rem!important}.rounded-start{border-bottom-left-radius:.25rem!important;border-top-left-radius:.25rem!important}.visible{visibility:visible!important}.invisible{visibility:hidden!important}@media (min-width:576px){.float-sm-start{float:left!important}.float-sm-end{float:right!important}.float-sm-none{float:none!important}.d-sm-inline{display:inline!important}.d-sm-inline-block{display:inline-block!important}.d-sm-block{display:block!important}.d-sm-grid{display:grid!important}.d-sm-table{display:table!important}.d-sm-table-row{display:table-row!important}.d-sm-table-cell{display:table-cell!important}.d-sm-flex{display:flex!important}.d-sm-inline-flex{display:inline-flex!important}.d-sm-none{display:none!important}.flex-sm-fill{flex:1 1 auto!important}.flex-sm-row{flex-direction:row!important}.flex-sm-column{flex-direction:column!important}.flex-sm-row-reverse{flex-direction:row-reverse!important}.flex-sm-column-reverse{flex-direction:column-reverse!important}.flex-sm-grow-0{flex-grow:0!important}.flex-sm-grow-1{flex-grow:1!important}.flex-sm-shrink-0{flex-shrink:0!important}.flex-sm-shrink-1{flex-shrink:1!important}.flex-sm-wrap{flex-wrap:wrap!important}.flex-sm-nowrap{flex-wrap:nowrap!important}.flex-sm-wrap-reverse{flex-wrap:wrap-reverse!important}.gap-sm-0{gap:0!important}.gap-sm-1{gap:.25rem!important}.gap-sm-2{gap:.5rem!important}.gap-sm-3{gap:1rem!important}.gap-sm-4{gap:1.5rem!important}.gap-sm-5{gap:3rem!important}.justify-content-sm-start{justify-content:flex-start!important}.justify-content-sm-end{justify-content:flex-end!important}.justify-content-sm-center{justify-content:center!important}.justify-content-sm-between{justify-content:space-between!important}.justify-content-sm-around{justify-content:space-around!important}.justify-content-sm-evenly{justify-content:space-evenly!important}.align-items-sm-start{align-items:flex-start!important}.align-items-sm-end{align-items:flex-end!important}.align-items-sm-center{align-items:center!important}.align-items-sm-baseline{align-items:baseline!important}.align-items-sm-stretch{align-items:stretch!important}.align-content-sm-start{align-content:flex-start!important}.align-content-sm-end{align-content:flex-end!important}.align-content-sm-center{align-content:center!important}.align-content-sm-between{align-content:space-between!important}.align-content-sm-around{align-content:space-around!important}.align-content-sm-stretch{align-content:stretch!important}.align-self-sm-auto{align-self:auto!important}.align-self-sm-start{align-self:flex-start!important}.align-self-sm-end{align-self:flex-end!important}.align-self-sm-center{align-self:center!important}.align-self-sm-baseline{align-self:baseline!important}.align-self-sm-stretch{align-self:stretch!important}.order-sm-first{order:-1!important}.order-sm-0{order:0!important}.order-sm-1{order:1!important}.order-sm-2{order:2!important}.order-sm-3{order:3!important}.order-sm-4{order:4!important}.order-sm-5{order:5!important}.order-sm-last{order:6!important}.m-sm-0{margin:0!important}.m-sm-1{margin:.25rem!important}.m-sm-2{margin:.5rem!important}.m-sm-3{margin:1rem!important}.m-sm-4{margin:1.5rem!important}.m-sm-5{margin:3rem!important}.m-sm-auto{margin:auto!important}.mx-sm-0{margin-right:0!important;margin-left:0!important}.mx-sm-1{margin-right:.25rem!important;margin-left:.25rem!important}.mx-sm-2{margin-right:.5rem!important;margin-left:.5rem!important}.mx-sm-3{margin-right:1rem!important;margin-left:1rem!important}.mx-sm-4{margin-right:1.5rem!important;margin-left:1.5rem!important}.mx-sm-5{margin-right:3rem!important;margin-left:3rem!important}.mx-sm-auto{margin-right:auto!important;margin-left:auto!important}.my-sm-0{margin-top:0!important;margin-bottom:0!important}.my-sm-1{margin-top:.25rem!important;margin-bottom:.25rem!important}.my-sm-2{margin-top:.5rem!important;margin-bottom:.5rem!important}.my-sm-3{margin-top:1rem!important;margin-bottom:1rem!important}.my-sm-4{margin-top:1.5rem!important;margin-bottom:1.5rem!important}.my-sm-5{margin-top:3rem!important;margin-bottom:3rem!important}.my-sm-auto{margin-top:auto!important;margin-bottom:auto!important}.mt-sm-0{margin-top:0!important}.mt-sm-1{margin-top:.25rem!important}.mt-sm-2{margin-top:.5rem!important}.mt-sm-3{margin-top:1rem!important}.mt-sm-4{margin-top:1.5rem!important}.mt-sm-5{margin-top:3rem!important}.mt-sm-auto{margin-top:auto!important}.me-sm-0{margin-right:0!important}.me-sm-1{margin-right:.25rem!important}.me-sm-2{margin-right:.5rem!important}.me-sm-3{margin-right:1rem!important}.me-sm-4{margin-right:1.5rem!important}.me-sm-5{margin-right:3rem!important}.me-sm-auto{margin-right:auto!important}.mb-sm-0{margin-bottom:0!important}.mb-sm-1{margin-bottom:.25rem!important}.mb-sm-2{margin-bottom:.5rem!important}.mb-sm-3{margin-bottom:1rem!important}.mb-sm-4{margin-bottom:1.5rem!important}.mb-sm-5{margin-bottom:3rem!important}.mb-sm-auto{margin-bottom:auto!important}.ms-sm-0{margin-left:0!important}.ms-sm-1{margin-left:.25rem!important}.ms-sm-2{margin-left:.5rem!important}.ms-sm-3{margin-left:1rem!important}.ms-sm-4{margin-left:1.5rem!important}.ms-sm-5{margin-left:3rem!important}.ms-sm-auto{margin-left:auto!important}.p-sm-0{padding:0!important}.p-sm-1{padding:.25rem!important}.p-sm-2{padding:.5rem!important}.p-sm-3{padding:1rem!important}.p-sm-4{padding:1.5rem!important}.p-sm-5{padding:3rem!important}.px-sm-0{padding-right:0!important;padding-left:0!important}.px-sm-1{padding-right:.25rem!important;padding-left:.25rem!important}.px-sm-2{padding-right:.5rem!important;padding-left:.5rem!important}.px-sm-3{padding-right:1rem!important;padding-left:1rem!important}.px-sm-4{padding-right:1.5rem!important;padding-left:1.5rem!important}.px-sm-5{padding-right:3rem!important;padding-left:3rem!important}.py-sm-0{padding-top:0!important;padding-bottom:0!important}.py-sm-1{padding-top:.25rem!important;padding-bottom:.25rem!important}.py-sm-2{padding-top:.5rem!important;padding-bottom:.5rem!important}.py-sm-3{padding-top:1rem!important;padding-bottom:1rem!important}.py-sm-4{padding-top:1.5rem!important;padding-bottom:1.5rem!important}.py-sm-5{padding-top:3rem!important;padding-bottom:3rem!important}.pt-sm-0{padding-top:0!important}.pt-sm-1{padding-top:.25rem!important}.pt-sm-2{padding-top:.5rem!important}.pt-sm-3{padding-top:1rem!important}.pt-sm-4{padding-top:1.5rem!important}.pt-sm-5{padding-top:3rem!important}.pe-sm-0{padding-right:0!important}.pe-sm-1{padding-right:.25rem!important}.pe-sm-2{padding-right:.5rem!important}.pe-sm-3{padding-right:1rem!important}.pe-sm-4{padding-right:1.5rem!important}.pe-sm-5{padding-right:3rem!important}.pb-sm-0{padding-bottom:0!important}.pb-sm-1{padding-bottom:.25rem!important}.pb-sm-2{padding-bottom:.5rem!important}.pb-sm-3{padding-bottom:1rem!important}.pb-sm-4{padding-bottom:1.5rem!important}.pb-sm-5{padding-bottom:3rem!important}.ps-sm-0{padding-left:0!important}.ps-sm-1{padding-left:.25rem!important}.ps-sm-2{padding-left:.5rem!important}.ps-sm-3{padding-left:1rem!important}.ps-sm-4{padding-left:1.5rem!important}.ps-sm-5{padding-left:3rem!important}.text-sm-start{text-align:left!important}.text-sm-end{text-align:right!important}.text-sm-center{text-align:center!important}}@media (min-width:768px){.float-md-start{float:left!important}.float-md-end{float:right!important}.float-md-none{float:none!important}.d-md-inline{display:inline!important}.d-md-inline-block{display:inline-block!important}.d-md-block{display:block!important}.d-md-grid{display:grid!important}.d-md-table{display:table!important}.d-md-table-row{display:table-row!important}.d-md-table-cell{display:table-cell!important}.d-md-flex{display:flex!important}.d-md-inline-flex{display:inline-flex!important}.d-md-none{display:none!important}.flex-md-fill{flex:1 1 auto!important}.flex-md-row{flex-direction:row!important}.flex-md-column{flex-direction:column!important}.flex-md-row-reverse{flex-direction:row-reverse!important}.flex-md-column-reverse{flex-direction:column-reverse!important}.flex-md-grow-0{flex-grow:0!important}.flex-md-grow-1{flex-grow:1!important}.flex-md-shrink-0{flex-shrink:0!important}.flex-md-shrink-1{flex-shrink:1!important}.flex-md-wrap{flex-wrap:wrap!important}.flex-md-nowrap{flex-wrap:nowrap!important}.flex-md-wrap-reverse{flex-wrap:wrap-reverse!important}.gap-md-0{gap:0!important}.gap-md-1{gap:.25rem!important}.gap-md-2{gap:.5rem!important}.gap-md-3{gap:1rem!important}.gap-md-4{gap:1.5rem!important}.gap-md-5{gap:3rem!important}.justify-content-md-start{justify-content:flex-start!important}.justify-content-md-end{justify-content:flex-end!important}.justify-content-md-center{justify-content:center!important}.justify-content-md-between{justify-content:space-between!important}.justify-content-md-around{justify-content:space-around!important}.justify-content-md-evenly{justify-content:space-evenly!important}.align-items-md-start{align-items:flex-start!important}.align-items-md-end{align-items:flex-end!important}.align-items-md-center{align-items:center!important}.align-items-md-baseline{align-items:baseline!important}.align-items-md-stretch{align-items:stretch!important}.align-content-md-start{align-content:flex-start!important}.align-content-md-end{align-content:flex-end!important}.align-content-md-center{align-content:center!important}.align-content-md-between{align-content:space-between!important}.align-content-md-around{align-content:space-around!important}.align-content-md-stretch{align-content:stretch!important}.align-self-md-auto{align-self:auto!important}.align-self-md-start{align-self:flex-start!important}.align-self-md-end{align-self:flex-end!important}.align-self-md-center{align-self:center!important}.align-self-md-baseline{align-self:baseline!important}.align-self-md-stretch{align-self:stretch!important}.order-md-first{order:-1!important}.order-md-0{order:0!important}.order-md-1{order:1!important}.order-md-2{order:2!important}.order-md-3{order:3!important}.order-md-4{order:4!important}.order-md-5{order:5!important}.order-md-last{order:6!important}.m-md-0{margin:0!important}.m-md-1{margin:.25rem!important}.m-md-2{margin:.5rem!important}.m-md-3{margin:1rem!important}.m-md-4{margin:1.5rem!important}.m-md-5{margin:3rem!important}.m-md-auto{margin:auto!important}.mx-md-0{margin-right:0!important;margin-left:0!important}.mx-md-1{margin-right:.25rem!important;margin-left:.25rem!important}.mx-md-2{margin-right:.5rem!important;margin-left:.5rem!important}.mx-md-3{margin-right:1rem!important;margin-left:1rem!important}.mx-md-4{margin-right:1.5rem!important;margin-left:1.5rem!important}.mx-md-5{margin-right:3rem!important;margin-left:3rem!important}.mx-md-auto{margin-right:auto!important;margin-left:auto!important}.my-md-0{margin-top:0!important;margin-bottom:0!important}.my-md-1{margin-top:.25rem!important;margin-bottom:.25rem!important}.my-md-2{margin-top:.5rem!important;margin-bottom:.5rem!important}.my-md-3{margin-top:1rem!important;margin-bottom:1rem!important}.my-md-4{margin-top:1.5rem!important;margin-bottom:1.5rem!important}.my-md-5{margin-top:3rem!important;margin-bottom:3rem!important}.my-md-auto{margin-top:auto!important;margin-bottom:auto!important}.mt-md-0{margin-top:0!important}.mt-md-1{margin-top:.25rem!important}.mt-md-2{margin-top:.5rem!important}.mt-md-3{margin-top:1rem!important}.mt-md-4{margin-top:1.5rem!important}.mt-md-5{margin-top:3rem!important}.mt-md-auto{margin-top:auto!important}.me-md-0{margin-right:0!important}.me-md-1{margin-right:.25rem!important}.me-md-2{margin-right:.5rem!important}.me-md-3{margin-right:1rem!important}.me-md-4{margin-right:1.5rem!important}.me-md-5{margin-right:3rem!important}.me-md-auto{margin-right:auto!important}.mb-md-0{margin-bottom:0!important}.mb-md-1{margin-bottom:.25rem!important}.mb-md-2{margin-bottom:.5rem!important}.mb-md-3{margin-bottom:1rem!important}.mb-md-4{margin-bottom:1.5rem!important}.mb-md-5{margin-bottom:3rem!important}.mb-md-auto{margin-bottom:auto!important}.ms-md-0{margin-left:0!important}.ms-md-1{margin-left:.25rem!important}.ms-md-2{margin-left:.5rem!important}.ms-md-3{margin-left:1rem!important}.ms-md-4{margin-left:1.5rem!important}.ms-md-5{margin-left:3rem!important}.ms-md-auto{margin-left:auto!important}.p-md-0{padding:0!important}.p-md-1{padding:.25rem!important}.p-md-2{padding:.5rem!important}.p-md-3{padding:1rem!important}.p-md-4{padding:1.5rem!important}.p-md-5{padding:3rem!important}.px-md-0{padding-right:0!important;padding-left:0!important}.px-md-1{padding-right:.25rem!important;padding-left:.25rem!important}.px-md-2{padding-right:.5rem!important;padding-left:.5rem!important}.px-md-3{padding-right:1rem!important;padding-left:1rem!important}.px-md-4{padding-right:1.5rem!important;padding-left:1.5rem!important}.px-md-5{padding-right:3rem!important;padding-left:3rem!important}.py-md-0{padding-top:0!important;padding-bottom:0!important}.py-md-1{padding-top:.25rem!important;padding-bottom:.25rem!important}.py-md-2{padding-top:.5rem!important;padding-bottom:.5rem!important}.py-md-3{padding-top:1rem!important;padding-bottom:1rem!important}.py-md-4{padding-top:1.5rem!important;padding-bottom:1.5rem!important}.py-md-5{padding-top:3rem!important;padding-bottom:3rem!important}.pt-md-0{padding-top:0!important}.pt-md-1{padding-top:.25rem!important}.pt-md-2{padding-top:.5rem!important}.pt-md-3{padding-top:1rem!important}.pt-md-4{padding-top:1.5rem!important}.pt-md-5{padding-top:3rem!important}.pe-md-0{padding-right:0!important}.pe-md-1{padding-right:.25rem!important}.pe-md-2{padding-right:.5rem!important}.pe-md-3{padding-right:1rem!important}.pe-md-4{padding-right:1.5rem!important}.pe-md-5{padding-right:3rem!important}.pb-md-0{padding-bottom:0!important}.pb-md-1{padding-bottom:.25rem!important}.pb-md-2{padding-bottom:.5rem!important}.pb-md-3{padding-bottom:1rem!important}.pb-md-4{padding-bottom:1.5rem!important}.pb-md-5{padding-bottom:3rem!important}.ps-md-0{padding-left:0!important}.ps-md-1{padding-left:.25rem!important}.ps-md-2{padding-left:.5rem!important}.ps-md-3{padding-left:1rem!important}.ps-md-4{padding-left:1.5rem!important}.ps-md-5{padding-left:3rem!important}.text-md-start{text-align:left!important}.text-md-end{text-align:right!important}.text-md-center{text-align:center!important}}@media (min-width:992px){.float-lg-start{float:left!important}.float-lg-end{float:right!important}.float-lg-none{float:none!important}.d-lg-inline{display:inline!important}.d-lg-inline-block{display:inline-block!important}.d-lg-block{display:block!important}.d-lg-grid{display:grid!important}.d-lg-table{display:table!important}.d-lg-table-row{display:table-row!important}.d-lg-table-cell{display:table-cell!important}.d-lg-flex{display:flex!important}.d-lg-inline-flex{display:inline-flex!important}.d-lg-none{display:none!important}.flex-lg-fill{flex:1 1 auto!important}.flex-lg-row{flex-direction:row!important}.flex-lg-column{flex-direction:column!important}.flex-lg-row-reverse{flex-direction:row-reverse!important}.flex-lg-column-reverse{flex-direction:column-reverse!important}.flex-lg-grow-0{flex-grow:0!important}.flex-lg-grow-1{flex-grow:1!important}.flex-lg-shrink-0{flex-shrink:0!important}.flex-lg-shrink-1{flex-shrink:1!important}.flex-lg-wrap{flex-wrap:wrap!important}.flex-lg-nowrap{flex-wrap:nowrap!important}.flex-lg-wrap-reverse{flex-wrap:wrap-reverse!important}.gap-lg-0{gap:0!important}.gap-lg-1{gap:.25rem!important}.gap-lg-2{gap:.5rem!important}.gap-lg-3{gap:1rem!important}.gap-lg-4{gap:1.5rem!important}.gap-lg-5{gap:3rem!important}.justify-content-lg-start{justify-content:flex-start!important}.justify-content-lg-end{justify-content:flex-end!important}.justify-content-lg-center{justify-content:center!important}.justify-content-lg-between{justify-content:space-between!important}.justify-content-lg-around{justify-content:space-around!important}.justify-content-lg-evenly{justify-content:space-evenly!important}.align-items-lg-start{align-items:flex-start!important}.align-items-lg-end{align-items:flex-end!important}.align-items-lg-center{align-items:center!important}.align-items-lg-baseline{align-items:baseline!important}.align-items-lg-stretch{align-items:stretch!important}.align-content-lg-start{align-content:flex-start!important}.align-content-lg-end{align-content:flex-end!important}.align-content-lg-center{align-content:center!important}.align-content-lg-between{align-content:space-between!important}.align-content-lg-around{align-content:space-around!important}.align-content-lg-stretch{align-content:stretch!important}.align-self-lg-auto{align-self:auto!important}.align-self-lg-start{align-self:flex-start!important}.align-self-lg-end{align-self:flex-end!important}.align-self-lg-center{align-self:center!important}.align-self-lg-baseline{align-self:baseline!important}.align-self-lg-stretch{align-self:stretch!important}.order-lg-first{order:-1!important}.order-lg-0{order:0!important}.order-lg-1{order:1!important}.order-lg-2{order:2!important}.order-lg-3{order:3!important}.order-lg-4{order:4!important}.order-lg-5{order:5!important}.order-lg-last{order:6!important}.m-lg-0{margin:0!important}.m-lg-1{margin:.25rem!important}.m-lg-2{margin:.5rem!important}.m-lg-3{margin:1rem!important}.m-lg-4{margin:1.5rem!important}.m-lg-5{margin:3rem!important}.m-lg-auto{margin:auto!important}.mx-lg-0{margin-right:0!important;margin-left:0!important}.mx-lg-1{margin-right:.25rem!important;margin-left:.25rem!important}.mx-lg-2{margin-right:.5rem!important;margin-left:.5rem!important}.mx-lg-3{margin-right:1rem!important;margin-left:1rem!important}.mx-lg-4{margin-right:1.5rem!important;margin-left:1.5rem!important}.mx-lg-5{margin-right:3rem!important;margin-left:3rem!important}.mx-lg-auto{margin-right:auto!important;margin-left:auto!important}.my-lg-0{margin-top:0!important;margin-bottom:0!important}.my-lg-1{margin-top:.25rem!important;margin-bottom:.25rem!important}.my-lg-2{margin-top:.5rem!important;margin-bottom:.5rem!important}.my-lg-3{margin-top:1rem!important;margin-bottom:1rem!important}.my-lg-4{margin-top:1.5rem!important;margin-bottom:1.5rem!important}.my-lg-5{margin-top:3rem!important;margin-bottom:3rem!important}.my-lg-auto{margin-top:auto!important;margin-bottom:auto!important}.mt-lg-0{margin-top:0!important}.mt-lg-1{margin-top:.25rem!important}.mt-lg-2{margin-top:.5rem!important}.mt-lg-3{margin-top:1rem!important}.mt-lg-4{margin-top:1.5rem!important}.mt-lg-5{margin-top:3rem!important}.mt-lg-auto{margin-top:auto!important}.me-lg-0{margin-right:0!important}.me-lg-1{margin-right:.25rem!important}.me-lg-2{margin-right:.5rem!important}.me-lg-3{margin-right:1rem!important}.me-lg-4{margin-right:1.5rem!important}.me-lg-5{margin-right:3rem!important}.me-lg-auto{margin-right:auto!important}.mb-lg-0{margin-bottom:0!important}.mb-lg-1{margin-bottom:.25rem!important}.mb-lg-2{margin-bottom:.5rem!important}.mb-lg-3{margin-bottom:1rem!important}.mb-lg-4{margin-bottom:1.5rem!important}.mb-lg-5{margin-bottom:3rem!important}.mb-lg-auto{margin-bottom:auto!important}.ms-lg-0{margin-left:0!important}.ms-lg-1{margin-left:.25rem!important}.ms-lg-2{margin-left:.5rem!important}.ms-lg-3{margin-left:1rem!important}.ms-lg-4{margin-left:1.5rem!important}.ms-lg-5{margin-left:3rem!important}.ms-lg-auto{margin-left:auto!important}.p-lg-0{padding:0!important}.p-lg-1{padding:.25rem!important}.p-lg-2{padding:.5rem!important}.p-lg-3{padding:1rem!important}.p-lg-4{padding:1.5rem!important}.p-lg-5{padding:3rem!important}.px-lg-0{padding-right:0!important;padding-left:0!important}.px-lg-1{padding-right:.25rem!important;padding-left:.25rem!important}.px-lg-2{padding-right:.5rem!important;padding-left:.5rem!important}.px-lg-3{padding-right:1rem!important;padding-left:1rem!important}.px-lg-4{padding-right:1.5rem!important;padding-left:1.5rem!important}.px-lg-5{padding-right:3rem!important;padding-left:3rem!important}.py-lg-0{padding-top:0!important;padding-bottom:0!important}.py-lg-1{padding-top:.25rem!important;padding-bottom:.25rem!important}.py-lg-2{padding-top:.5rem!important;padding-bottom:.5rem!important}.py-lg-3{padding-top:1rem!important;padding-bottom:1rem!important}.py-lg-4{padding-top:1.5rem!important;padding-bottom:1.5rem!important}.py-lg-5{padding-top:3rem!important;padding-bottom:3rem!important}.pt-lg-0{padding-top:0!important}.pt-lg-1{padding-top:.25rem!important}.pt-lg-2{padding-top:.5rem!important}.pt-lg-3{padding-top:1rem!important}.pt-lg-4{padding-top:1.5rem!important}.pt-lg-5{padding-top:3rem!important}.pe-lg-0{padding-right:0!important}.pe-lg-1{padding-right:.25rem!important}.pe-lg-2{padding-right:.5rem!important}.pe-lg-3{padding-right:1rem!important}.pe-lg-4{padding-right:1.5rem!important}.pe-lg-5{padding-right:3rem!important}.pb-lg-0{padding-bottom:0!important}.pb-lg-1{padding-bottom:.25rem!important}.pb-lg-2{padding-bottom:.5rem!important}.pb-lg-3{padding-bottom:1rem!important}.pb-lg-4{padding-bottom:1.5rem!important}.pb-lg-5{padding-bottom:3rem!important}.ps-lg-0{padding-left:0!important}.ps-lg-1{padding-left:.25rem!important}.ps-lg-2{padding-left:.5rem!important}.ps-lg-3{padding-left:1rem!important}.ps-lg-4{padding-left:1.5rem!important}.ps-lg-5{padding-left:3rem!important}.text-lg-start{text-align:left!important}.text-lg-end{text-align:right!important}.text-lg-center{text-align:center!important}}@media (min-width:1200px){.float-xl-start{float:left!important}.float-xl-end{float:right!important}.float-xl-none{float:none!important}.d-xl-inline{display:inline!important}.d-xl-inline-block{display:inline-block!important}.d-xl-block{display:block!important}.d-xl-grid{display:grid!important}.d-xl-table{display:table!important}.d-xl-table-row{display:table-row!important}.d-xl-table-cell{display:table-cell!important}.d-xl-flex{display:flex!important}.d-xl-inline-flex{display:inline-flex!important}.d-xl-none{display:none!important}.flex-xl-fill{flex:1 1 auto!important}.flex-xl-row{flex-direction:row!important}.flex-xl-column{flex-direction:column!important}.flex-xl-row-reverse{flex-direction:row-reverse!important}.flex-xl-column-reverse{flex-direction:column-reverse!important}.flex-xl-grow-0{flex-grow:0!important}.flex-xl-grow-1{flex-grow:1!important}.flex-xl-shrink-0{flex-shrink:0!important}.flex-xl-shrink-1{flex-shrink:1!important}.flex-xl-wrap{flex-wrap:wrap!important}.flex-xl-nowrap{flex-wrap:nowrap!important}.flex-xl-wrap-reverse{flex-wrap:wrap-reverse!important}.gap-xl-0{gap:0!important}.gap-xl-1{gap:.25rem!important}.gap-xl-2{gap:.5rem!important}.gap-xl-3{gap:1rem!important}.gap-xl-4{gap:1.5rem!important}.gap-xl-5{gap:3rem!important}.justify-content-xl-start{justify-content:flex-start!important}.justify-content-xl-end{justify-content:flex-end!important}.justify-content-xl-center{justify-content:center!important}.justify-content-xl-between{justify-content:space-between!important}.justify-content-xl-around{justify-content:space-around!important}.justify-content-xl-evenly{justify-content:space-evenly!important}.align-items-xl-start{align-items:flex-start!important}.align-items-xl-end{align-items:flex-end!important}.align-items-xl-center{align-items:center!important}.align-items-xl-baseline{align-items:baseline!important}.align-items-xl-stretch{align-items:stretch!important}.align-content-xl-start{align-content:flex-start!important}.align-content-xl-end{align-content:flex-end!important}.align-content-xl-center{align-content:center!important}.align-content-xl-between{align-content:space-between!important}.align-content-xl-around{align-content:space-around!important}.align-content-xl-stretch{align-content:stretch!important}.align-self-xl-auto{align-self:auto!important}.align-self-xl-start{align-self:flex-start!important}.align-self-xl-end{align-self:flex-end!important}.align-self-xl-center{align-self:center!important}.align-self-xl-baseline{align-self:baseline!important}.align-self-xl-stretch{align-self:stretch!important}.order-xl-first{order:-1!important}.order-xl-0{order:0!important}.order-xl-1{order:1!important}.order-xl-2{order:2!important}.order-xl-3{order:3!important}.order-xl-4{order:4!important}.order-xl-5{order:5!important}.order-xl-last{order:6!important}.m-xl-0{margin:0!important}.m-xl-1{margin:.25rem!important}.m-xl-2{margin:.5rem!important}.m-xl-3{margin:1rem!important}.m-xl-4{margin:1.5rem!important}.m-xl-5{margin:3rem!important}.m-xl-auto{margin:auto!important}.mx-xl-0{margin-right:0!important;margin-left:0!important}.mx-xl-1{margin-right:.25rem!important;margin-left:.25rem!important}.mx-xl-2{margin-right:.5rem!important;margin-left:.5rem!important}.mx-xl-3{margin-right:1rem!important;margin-left:1rem!important}.mx-xl-4{margin-right:1.5rem!important;margin-left:1.5rem!important}.mx-xl-5{margin-right:3rem!important;margin-left:3rem!important}.mx-xl-auto{margin-right:auto!important;margin-left:auto!important}.my-xl-0{margin-top:0!important;margin-bottom:0!important}.my-xl-1{margin-top:.25rem!important;margin-bottom:.25rem!important}.my-xl-2{margin-top:.5rem!important;margin-bottom:.5rem!important}.my-xl-3{margin-top:1rem!important;margin-bottom:1rem!important}.my-xl-4{margin-top:1.5rem!important;margin-bottom:1.5rem!important}.my-xl-5{margin-top:3rem!important;margin-bottom:3rem!important}.my-xl-auto{margin-top:auto!important;margin-bottom:auto!important}.mt-xl-0{margin-top:0!important}.mt-xl-1{margin-top:.25rem!important}.mt-xl-2{margin-top:.5rem!important}.mt-xl-3{margin-top:1rem!important}.mt-xl-4{margin-top:1.5rem!important}.mt-xl-5{margin-top:3rem!important}.mt-xl-auto{margin-top:auto!important}.me-xl-0{margin-right:0!important}.me-xl-1{margin-right:.25rem!important}.me-xl-2{margin-right:.5rem!important}.me-xl-3{margin-right:1rem!important}.me-xl-4{margin-right:1.5rem!important}.me-xl-5{margin-right:3rem!important}.me-xl-auto{margin-right:auto!important}.mb-xl-0{margin-bottom:0!important}.mb-xl-1{margin-bottom:.25rem!important}.mb-xl-2{margin-bottom:.5rem!important}.mb-xl-3{margin-bottom:1rem!important}.mb-xl-4{margin-bottom:1.5rem!important}.mb-xl-5{margin-bottom:3rem!important}.mb-xl-auto{margin-bottom:auto!important}.ms-xl-0{margin-left:0!important}.ms-xl-1{margin-left:.25rem!important}.ms-xl-2{margin-left:.5rem!important}.ms-xl-3{margin-left:1rem!important}.ms-xl-4{margin-left:1.5rem!important}.ms-xl-5{margin-left:3rem!important}.ms-xl-auto{margin-left:auto!important}.p-xl-0{padding:0!important}.p-xl-1{padding:.25rem!important}.p-xl-2{padding:.5rem!important}.p-xl-3{padding:1rem!important}.p-xl-4{padding:1.5rem!important}.p-xl-5{padding:3rem!important}.px-xl-0{padding-right:0!important;padding-left:0!important}.px-xl-1{padding-right:.25rem!important;padding-left:.25rem!important}.px-xl-2{padding-right:.5rem!important;padding-left:.5rem!important}.px-xl-3{padding-right:1rem!important;padding-left:1rem!important}.px-xl-4{padding-right:1.5rem!important;padding-left:1.5rem!important}.px-xl-5{padding-right:3rem!important;padding-left:3rem!important}.py-xl-0{padding-top:0!important;padding-bottom:0!important}.py-xl-1{padding-top:.25rem!important;padding-bottom:.25rem!important}.py-xl-2{padding-top:.5rem!important;padding-bottom:.5rem!important}.py-xl-3{padding-top:1rem!important;padding-bottom:1rem!important}.py-xl-4{padding-top:1.5rem!important;padding-bottom:1.5rem!important}.py-xl-5{padding-top:3rem!important;padding-bottom:3rem!important}.pt-xl-0{padding-top:0!important}.pt-xl-1{padding-top:.25rem!important}.pt-xl-2{padding-top:.5rem!important}.pt-xl-3{padding-top:1rem!important}.pt-xl-4{padding-top:1.5rem!important}.pt-xl-5{padding-top:3rem!important}.pe-xl-0{padding-right:0!important}.pe-xl-1{padding-right:.25rem!important}.pe-xl-2{padding-right:.5rem!important}.pe-xl-3{padding-right:1rem!important}.pe-xl-4{padding-right:1.5rem!important}.pe-xl-5{padding-right:3rem!important}.pb-xl-0{padding-bottom:0!important}.pb-xl-1{padding-bottom:.25rem!important}.pb-xl-2{padding-bottom:.5rem!important}.pb-xl-3{padding-bottom:1rem!important}.pb-xl-4{padding-bottom:1.5rem!important}.pb-xl-5{padding-bottom:3rem!important}.ps-xl-0{padding-left:0!important}.ps-xl-1{padding-left:.25rem!important}.ps-xl-2{padding-left:.5rem!important}.ps-xl-3{padding-left:1rem!important}.ps-xl-4{padding-left:1.5rem!important}.ps-xl-5{padding-left:3rem!important}.text-xl-start{text-align:left!important}.text-xl-end{text-align:right!important}.text-xl-center{text-align:center!important}}@media (min-width:1400px){.float-xxl-start{float:left!important}.float-xxl-end{float:right!important}.float-xxl-none{float:none!important}.d-xxl-inline{display:inline!important}.d-xxl-inline-block{display:inline-block!important}.d-xxl-block{display:block!important}.d-xxl-grid{display:grid!important}.d-xxl-table{display:table!important}.d-xxl-table-row{display:table-row!important}.d-xxl-table-cell{display:table-cell!important}.d-xxl-flex{display:flex!important}.d-xxl-inline-flex{display:inline-flex!important}.d-xxl-none{display:none!important}.flex-xxl-fill{flex:1 1 auto!important}.flex-xxl-row{flex-direction:row!important}.flex-xxl-column{flex-direction:column!important}.flex-xxl-row-reverse{flex-direction:row-reverse!important}.flex-xxl-column-reverse{flex-direction:column-reverse!important}.flex-xxl-grow-0{flex-grow:0!important}.flex-xxl-grow-1{flex-grow:1!important}.flex-xxl-shrink-0{flex-shrink:0!important}.flex-xxl-shrink-1{flex-shrink:1!important}.flex-xxl-wrap{flex-wrap:wrap!important}.flex-xxl-nowrap{flex-wrap:nowrap!important}.flex-xxl-wrap-reverse{flex-wrap:wrap-reverse!important}.gap-xxl-0{gap:0!important}.gap-xxl-1{gap:.25rem!important}.gap-xxl-2{gap:.5rem!important}.gap-xxl-3{gap:1rem!important}.gap-xxl-4{gap:1.5rem!important}.gap-xxl-5{gap:3rem!important}.justify-content-xxl-start{justify-content:flex-start!important}.justify-content-xxl-end{justify-content:flex-end!important}.justify-content-xxl-center{justify-content:center!important}.justify-content-xxl-between{justify-content:space-between!important}.justify-content-xxl-around{justify-content:space-around!important}.justify-content-xxl-evenly{justify-content:space-evenly!important}.align-items-xxl-start{align-items:flex-start!important}.align-items-xxl-end{align-items:flex-end!important}.align-items-xxl-center{align-items:center!important}.align-items-xxl-baseline{align-items:baseline!important}.align-items-xxl-stretch{align-items:stretch!important}.align-content-xxl-start{align-content:flex-start!important}.align-content-xxl-end{align-content:flex-end!important}.align-content-xxl-center{align-content:center!important}.align-content-xxl-between{align-content:space-between!important}.align-content-xxl-around{align-content:space-around!important}.align-content-xxl-stretch{align-content:stretch!important}.align-self-xxl-auto{align-self:auto!important}.align-self-xxl-start{align-self:flex-start!important}.align-self-xxl-end{align-self:flex-end!important}.align-self-xxl-center{align-self:center!important}.align-self-xxl-baseline{align-self:baseline!important}.align-self-xxl-stretch{align-self:stretch!important}.order-xxl-first{order:-1!important}.order-xxl-0{order:0!important}.order-xxl-1{order:1!important}.order-xxl-2{order:2!important}.order-xxl-3{order:3!important}.order-xxl-4{order:4!important}.order-xxl-5{order:5!important}.order-xxl-last{order:6!important}.m-xxl-0{margin:0!important}.m-xxl-1{margin:.25rem!important}.m-xxl-2{margin:.5rem!important}.m-xxl-3{margin:1rem!important}.m-xxl-4{margin:1.5rem!important}.m-xxl-5{margin:3rem!important}.m-xxl-auto{margin:auto!important}.mx-xxl-0{margin-right:0!important;margin-left:0!important}.mx-xxl-1{margin-right:.25rem!important;margin-left:.25rem!important}.mx-xxl-2{margin-right:.5rem!important;margin-left:.5rem!important}.mx-xxl-3{margin-right:1rem!important;margin-left:1rem!important}.mx-xxl-4{margin-right:1.5rem!important;margin-left:1.5rem!important}.mx-xxl-5{margin-right:3rem!important;margin-left:3rem!important}.mx-xxl-auto{margin-right:auto!important;margin-left:auto!important}.my-xxl-0{margin-top:0!important;margin-bottom:0!important}.my-xxl-1{margin-top:.25rem!important;margin-bottom:.25rem!important}.my-xxl-2{margin-top:.5rem!important;margin-bottom:.5rem!important}.my-xxl-3{margin-top:1rem!important;margin-bottom:1rem!important}.my-xxl-4{margin-top:1.5rem!important;margin-bottom:1.5rem!important}.my-xxl-5{margin-top:3rem!important;margin-bottom:3rem!important}.my-xxl-auto{margin-top:auto!important;margin-bottom:auto!important}.mt-xxl-0{margin-top:0!important}.mt-xxl-1{margin-top:.25rem!important}.mt-xxl-2{margin-top:.5rem!important}.mt-xxl-3{margin-top:1rem!important}.mt-xxl-4{margin-top:1.5rem!important}.mt-xxl-5{margin-top:3rem!important}.mt-xxl-auto{margin-top:auto!important}.me-xxl-0{margin-right:0!important}.me-xxl-1{margin-right:.25rem!important}.me-xxl-2{margin-right:.5rem!important}.me-xxl-3{margin-right:1rem!important}.me-xxl-4{margin-right:1.5rem!important}.me-xxl-5{margin-right:3rem!important}.me-xxl-auto{margin-right:auto!important}.mb-xxl-0{margin-bottom:0!important}.mb-xxl-1{margin-bottom:.25rem!important}.mb-xxl-2{margin-bottom:.5rem!important}.mb-xxl-3{margin-bottom:1rem!important}.mb-xxl-4{margin-bottom:1.5rem!important}.mb-xxl-5{margin-bottom:3rem!important}.mb-xxl-auto{margin-bottom:auto!important}.ms-xxl-0{margin-left:0!important}.ms-xxl-1{margin-left:.25rem!important}.ms-xxl-2{margin-left:.5rem!important}.ms-xxl-3{margin-left:1rem!important}.ms-xxl-4{margin-left:1.5rem!important}.ms-xxl-5{margin-left:3rem!important}.ms-xxl-auto{margin-left:auto!important}.p-xxl-0{padding:0!important}.p-xxl-1{padding:.25rem!important}.p-xxl-2{padding:.5rem!important}.p-xxl-3{padding:1rem!important}.p-xxl-4{padding:1.5rem!important}.p-xxl-5{padding:3rem!important}.px-xxl-0{padding-right:0!important;padding-left:0!important}.px-xxl-1{padding-right:.25rem!important;padding-left:.25rem!important}.px-xxl-2{padding-right:.5rem!important;padding-left:.5rem!important}.px-xxl-3{padding-right:1rem!important;padding-left:1rem!important}.px-xxl-4{padding-right:1.5rem!important;padding-left:1.5rem!important}.px-xxl-5{padding-right:3rem!important;padding-left:3rem!important}.py-xxl-0{padding-top:0!important;padding-bottom:0!important}.py-xxl-1{padding-top:.25rem!important;padding-bottom:.25rem!important}.py-xxl-2{padding-top:.5rem!important;padding-bottom:.5rem!important}.py-xxl-3{padding-top:1rem!important;padding-bottom:1rem!important}.py-xxl-4{padding-top:1.5rem!important;padding-bottom:1.5rem!important}.py-xxl-5{padding-top:3rem!important;padding-bottom:3rem!important}.pt-xxl-0{padding-top:0!important}.pt-xxl-1{padding-top:.25rem!important}.pt-xxl-2{padding-top:.5rem!important}.pt-xxl-3{padding-top:1rem!important}.pt-xxl-4{padding-top:1.5rem!important}.pt-xxl-5{padding-top:3rem!important}.pe-xxl-0{padding-right:0!important}.pe-xxl-1{padding-right:.25rem!important}.pe-xxl-2{padding-right:.5rem!important}.pe-xxl-3{padding-right:1rem!important}.pe-xxl-4{padding-right:1.5rem!important}.pe-xxl-5{padding-right:3rem!important}.pb-xxl-0{padding-bottom:0!important}.pb-xxl-1{padding-bottom:.25rem!important}.pb-xxl-2{padding-bottom:.5rem!important}.pb-xxl-3{padding-bottom:1rem!important}.pb-xxl-4{padding-bottom:1.5rem!important}.pb-xxl-5{padding-bottom:3rem!important}.ps-xxl-0{padding-left:0!important}.ps-xxl-1{padding-left:.25rem!important}.ps-xxl-2{padding-left:.5rem!important}.ps-xxl-3{padding-left:1rem!important}.ps-xxl-4{padding-left:1.5rem!important}.ps-xxl-5{padding-left:3rem!important}.text-xxl-start{text-align:left!important}.text-xxl-end{text-align:right!important}.text-xxl-center{text-align:center!important}}@media (min-width:1200px){.fs-1{font-size:2.5rem!important}.fs-2{font-size:2rem!important}.fs-3{font-size:1.75rem!important}.fs-4{font-size:1.5rem!important}}@media print{.d-print-inline{display:inline!important}.d-print-inline-block{display:inline-block!important}.d-print-block{display:block!important}.d-print-grid{display:grid!important}.d-print-table{display:table!important}.d-print-table-row{display:table-row!important}.d-print-table-cell{display:table-cell!important}.d-print-flex{display:flex!important}.d-print-inline-flex{display:inline-flex!important}.d-print-none{display:none!important}}
			/*# sourceMappingURL=bootstrap.min.css.map */
		</style>
		<style type="text/css">
			/**
			 * bootstrap-table - An extended table to integration with some of the most widely used CSS frameworks. (Supports Bootstrap, Semantic UI, Bulma, Material Design, Foundation)
			 *
			 * @version v1.22.4
			 * @homepage https://bootstrap-table.com
			 * @author wenzhixin <wenzhixin2010@gmail.com> (http://wenzhixin.net.cn/)
			 * @license MIT
			 */
			.bootstrap-table .fixed-table-toolbar::after{content:"";display:block;clear:both}.bootstrap-table .fixed-table-toolbar .bs-bars,.bootstrap-table .fixed-table-toolbar .columns,.bootstrap-table .fixed-table-toolbar .search{position:relative;margin-top:10px;margin-bottom:10px}.bootstrap-table .fixed-table-toolbar .columns .btn-group>.btn-group{display:inline-block;margin-left:-1px!important}.bootstrap-table .fixed-table-toolbar .columns .btn-group>.btn-group>.btn{border-radius:0}.bootstrap-table .fixed-table-toolbar .columns .btn-group>.btn-group:first-child>.btn{border-top-left-radius:4px;border-bottom-left-radius:4px}.bootstrap-table .fixed-table-toolbar .columns .btn-group>.btn-group:last-child>.btn{border-top-right-radius:4px;border-bottom-right-radius:4px}.bootstrap-table .fixed-table-toolbar .columns .dropdown-menu{text-align:left;max-height:300px;overflow:auto;-ms-overflow-style:scrollbar;z-index:1001}.bootstrap-table .fixed-table-toolbar .columns label{display:block;padding:3px 20px;clear:both;font-weight:400;line-height:1.4286}.bootstrap-table .fixed-table-toolbar .columns-left{margin-right:5px}.bootstrap-table .fixed-table-toolbar .columns-right{margin-left:5px}.bootstrap-table .fixed-table-toolbar .pull-right .dropdown-menu{right:0;left:auto}.bootstrap-table .fixed-table-container{position:relative;clear:both}.bootstrap-table .fixed-table-container .table{width:100%;margin-bottom:0!important}.bootstrap-table .fixed-table-container .table td,.bootstrap-table .fixed-table-container .table th{vertical-align:middle;box-sizing:border-box}.bootstrap-table .fixed-table-container .table tfoot th,.bootstrap-table .fixed-table-container .table thead th{vertical-align:bottom;padding:0;margin:0}.bootstrap-table .fixed-table-container .table tfoot th:focus,.bootstrap-table .fixed-table-container .table thead th:focus{outline:0 solid transparent}.bootstrap-table .fixed-table-container .table tfoot th.detail,.bootstrap-table .fixed-table-container .table thead th.detail{width:30px}.bootstrap-table .fixed-table-container .table tfoot th .th-inner,.bootstrap-table .fixed-table-container .table thead th .th-inner{padding:.75rem;vertical-align:bottom;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.bootstrap-table .fixed-table-container .table tfoot th .sortable,.bootstrap-table .fixed-table-container .table thead th .sortable{cursor:pointer;background-position:right;background-repeat:no-repeat;padding-right:30px!important}.bootstrap-table .fixed-table-container .table tfoot th .sortable.sortable-center,.bootstrap-table .fixed-table-container .table thead th .sortable.sortable-center{padding-left:20px!important;padding-right:20px!important}.bootstrap-table .fixed-table-container .table tfoot th .both,.bootstrap-table .fixed-table-container .table thead th .both{background-image:url("data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABMAAAATCAQAAADYWf5HAAAAkElEQVQoz7X QMQ5AQBCF4dWQSJxC5wwax1Cq1e7BAdxD5SL+Tq/QCM1oNiJidwox0355mXnG/DrEtIQ6azioNZQxI0ykPhTQIwhCR+BmBYtlK7kLJYwWCcJA9M4qdrZrd8pPjZWPtOqdRQy320YSV17OatFC4euts6z39GYMKRPCTKY9UnPQ6P+GtMRfGtPnBCiqhAeJPmkqAAAAAElFTkSuQmCC")}.bootstrap-table .fixed-table-container .table tfoot th .asc,.bootstrap-table .fixed-table-container .table thead th .asc{background-image:url("data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABMAAAATCAYAAAByUDbMAAAAZ0lEQVQ4y2NgGLKgquEuFxBPAGI2ahhWCsS/gDibUoO0gPgxEP8H4ttArEyuQYxAPBdqEAxPBImTY5gjEL9DM+wTENuQahAvEO9DMwiGdwAxOymGJQLxTyD+jgWDxCMZRsEoGAVoAADeemwtPcZI2wAAAABJRU5ErkJggg==")}.bootstrap-table .fixed-table-container .table tfoot th .desc,.bootstrap-table .fixed-table-container .table thead th .desc{background-image:url("data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABMAAAATCAYAAAByUDbMAAAAZUlEQVQ4y2NgGAWjYBSggaqGu5FA/BOIv2PBIPFEUgxjB+IdQPwfC94HxLykus4GiD+hGfQOiB3J8SojEE9EM2wuSJzcsFMG4ttQgx4DsRalkZENxL+AuJQaMcsGxBOAmGvopk8AVz1sLZgg0bsAAAAASUVORK5CYII= ")}.bootstrap-table .fixed-table-container .table tbody tr.selected td{background-color:rgba(0,0,0,.075)}.bootstrap-table .fixed-table-container .table tbody tr.no-records-found td{text-align:center}.bootstrap-table .fixed-table-container .table tbody tr .card-view{display:flex}.bootstrap-table .fixed-table-container .table tbody tr .card-view .card-view-title{font-weight:700;display:inline-block;min-width:30%;width:auto!important;text-align:left!important}.bootstrap-table .fixed-table-container .table tbody tr .card-view .card-view-value{width:100%!important;text-align:left!important}.bootstrap-table .fixed-table-container .table .bs-checkbox{text-align:center}.bootstrap-table .fixed-table-container .table .bs-checkbox label{margin-bottom:0}.bootstrap-table .fixed-table-container .table .bs-checkbox label input[type=checkbox],.bootstrap-table .fixed-table-container .table .bs-checkbox label input[type=radio]{margin:0 auto!important}.bootstrap-table .fixed-table-container .table.table-sm .th-inner{padding:.25rem}.bootstrap-table .fixed-table-container.fixed-height:not(.has-footer){border-bottom:1px solid #dee2e6}.bootstrap-table .fixed-table-container.fixed-height.has-card-view{border-top:1px solid #dee2e6;border-bottom:1px solid #dee2e6}.bootstrap-table .fixed-table-container.fixed-height .fixed-table-border{border-left:1px solid #dee2e6;border-right:1px solid #dee2e6}.bootstrap-table .fixed-table-container.fixed-height .table thead th{border-bottom:1px solid #dee2e6}.bootstrap-table .fixed-table-container.fixed-height .table-dark thead th{border-bottom:1px solid #32383e}.bootstrap-table .fixed-table-container .fixed-table-header{overflow:hidden}.bootstrap-table .fixed-table-container .fixed-table-body{overflow:auto auto;height:100%}.bootstrap-table .fixed-table-container .fixed-table-body .fixed-table-loading{align-items:center;background:#fff;display:flex;justify-content:center;position:absolute;bottom:0;width:100%;max-width:100%;z-index:1000;transition:visibility 0s,opacity .15s ease-in-out;opacity:0;visibility:hidden}.bootstrap-table .fixed-table-container .fixed-table-body .fixed-table-loading.open{visibility:visible;opacity:1}.bootstrap-table .fixed-table-container .fixed-table-body .fixed-table-loading .loading-wrap{align-items:baseline;display:flex;justify-content:center}.bootstrap-table .fixed-table-container .fixed-table-body .fixed-table-loading .loading-wrap .loading-text{margin-right:6px}.bootstrap-table .fixed-table-container .fixed-table-body .fixed-table-loading .loading-wrap .animation-wrap{align-items:center;display:flex;justify-content:center}.bootstrap-table .fixed-table-container .fixed-table-body .fixed-table-loading .loading-wrap .animation-dot,.bootstrap-table .fixed-table-container .fixed-table-body .fixed-table-loading .loading-wrap .animation-wrap::after,.bootstrap-table .fixed-table-container .fixed-table-body .fixed-table-loading .loading-wrap .animation-wrap::before{content:"";animation-duration:1.5s;animation-iteration-count:infinite;animation-name:loading;background:#212529;border-radius:50%;display:block;height:5px;margin:0 4px;opacity:0;width:5px}.bootstrap-table .fixed-table-container .fixed-table-body .fixed-table-loading .loading-wrap .animation-dot{animation-delay:.3s}.bootstrap-table .fixed-table-container .fixed-table-body .fixed-table-loading .loading-wrap .animation-wrap::after{animation-delay:.6s}.bootstrap-table .fixed-table-container .fixed-table-body .fixed-table-loading.table-dark{background:#212529}.bootstrap-table .fixed-table-container .fixed-table-body .fixed-table-loading.table-dark .animation-dot,.bootstrap-table .fixed-table-container .fixed-table-body .fixed-table-loading.table-dark .animation-wrap::after,.bootstrap-table .fixed-table-container .fixed-table-body .fixed-table-loading.table-dark .animation-wrap::before{background:#fff}.bootstrap-table .fixed-table-container .fixed-table-footer{overflow:hidden}.bootstrap-table .fixed-table-pagination::after{content:"";display:block;clear:both}.bootstrap-table .fixed-table-pagination>.pagination,.bootstrap-table .fixed-table-pagination>.pagination-detail{margin-top:10px;margin-bottom:10px}.bootstrap-table .fixed-table-pagination>.pagination-detail .pagination-info{line-height:34px;margin-right:5px}.bootstrap-table .fixed-table-pagination>.pagination-detail .page-list{display:inline-block}.bootstrap-table .fixed-table-pagination>.pagination-detail .page-list .btn-group{position:relative;display:inline-block;vertical-align:middle}.bootstrap-table .fixed-table-pagination>.pagination-detail .page-list .btn-group .dropdown-menu{margin-bottom:0}.bootstrap-table .fixed-table-pagination>.pagination ul.pagination{margin:0}.bootstrap-table .fixed-table-pagination>.pagination ul.pagination li.page-intermediate a{color:#c8c8c8}.bootstrap-table .fixed-table-pagination>.pagination ul.pagination li.page-intermediate a::before{content:"\2B05"}.bootstrap-table .fixed-table-pagination>.pagination ul.pagination li.page-intermediate a::after{content:"\27A1"}.bootstrap-table .fixed-table-pagination>.pagination ul.pagination li.disabled a{pointer-events:none;cursor:default}.bootstrap-table.fullscreen{position:fixed;top:0;left:0;z-index:1050;width:100%!important;background:#fff;height:calc(100vh);overflow-y:scroll}.bootstrap-table.bootstrap4 .pagination-lg .page-link,.bootstrap-table.bootstrap5 .pagination-lg .page-link{padding:.5rem 1rem}.bootstrap-table.bootstrap5 .float-left{float:left}.bootstrap-table.bootstrap5 .float-right{float:right}div.fixed-table-scroll-inner{width:100%;height:200px}div.fixed-table-scroll-outer{top:0;left:0;visibility:hidden;width:200px;height:150px;overflow:hidden}@keyframes loading{0%{opacity:0}50%{opacity:1}100%{opacity:0}}
		</style>
		<style type="text/css">
			/**
			  * bootstrap-table - An extended table to integration with some of the most widely used CSS frameworks. (Supports Bootstrap, Semantic UI, Bulma, Material Design, Foundation)
			  *
			  * @version v1.22.4
			  * @homepage https://bootstrap-table.com
			  * @author wenzhixin <wenzhixin2010@gmail.com> (http://wenzhixin.net.cn/)
			  * @license MIT
			*/
			@charset "UTF-8";.no-filter-control{height:40px}.filter-control{margin:0 2px 2px}.ms-choice{border:0}.ms-parent>button:focus{outline:0}
		</style>
		<title>_ReportTitle_</title>
	</head>
	<body>
		<div class="container theme-showcase" role="main">
			<div class="p-2 mb-2 bg-light rounded-3">
				<h3 class="fw-bold">_ReportTitle_</h2>
				<p>_ReportDescription_</p>
			</div>
			_ReportBody_
		</div>
		_ReportScript_
	</body>
</html>
"@
}
function Get-JavaScript {
	@'
		<script>
			//src="https://code.jquery.com/jquery-3.7.1.min.js" integrity="sha256-o88AwQnZB+VDvE9tvIXrMQaPlFFSUTR+nldQm1LuPXQ=" crossorigin="anonymous"
			/*! jQuery v3.7.1 | (c) OpenJS Foundation and other contributors | jquery.org/license */
			!function(e,t){"use strict";"object"==typeof module&&"object"==typeof module.exports?module.exports=e.document?t(e,!0):function(e){if(!e.document)throw new Error("jQuery requires a window with a document");return t(e)}:t(e)}("undefined"!=typeof window?window:this,function(ie,e){"use strict";var oe=[],r=Object.getPrototypeOf,ae=oe.slice,g=oe.flat?function(e){return oe.flat.call(e)}:function(e){return oe.concat.apply([],e)},s=oe.push,se=oe.indexOf,n={},i=n.toString,ue=n.hasOwnProperty,o=ue.toString,a=o.call(Object),le={},v=function(e){return"function"==typeof e&&"number"!=typeof e.nodeType&&"function"!=typeof e.item},y=function(e){return null!=e&&e===e.window},C=ie.document,u={type:!0,src:!0,nonce:!0,noModule:!0};function m(e,t,n){var r,i,o=(n=n||C).createElement("script");if(o.text=e,t)for(r in u)(i=t[r]||t.getAttribute&&t.getAttribute(r))&&o.setAttribute(r,i);n.head.appendChild(o).parentNode.removeChild(o)}function x(e){return null==e?e+"":"object"==typeof e||"function"==typeof e?n[i.call(e)]||"object":typeof e}var t="3.7.1",l=/HTML$/i,ce=function(e,t){return new ce.fn.init(e,t)};function c(e){var t=!!e&&"length"in e&&e.length,n=x(e);return!v(e)&&!y(e)&&("array"===n||0===t||"number"==typeof t&&0<t&&t-1 in e)}function fe(e,t){return e.nodeName&&e.nodeName.toLowerCase()===t.toLowerCase()}ce.fn=ce.prototype={jquery:t,constructor:ce,length:0,toArray:function(){return ae.call(this)},get:function(e){return null==e?ae.call(this):e<0?this[e+this.length]:this[e]},pushStack:function(e){var t=ce.merge(this.constructor(),e);return t.prevObject=this,t},each:function(e){return ce.each(this,e)},map:function(n){return this.pushStack(ce.map(this,function(e,t){return n.call(e,t,e)}))},slice:function(){return this.pushStack(ae.apply(this,arguments))},first:function(){return this.eq(0)},last:function(){return this.eq(-1)},even:function(){return this.pushStack(ce.grep(this,function(e,t){return(t+1)%2}))},odd:function(){return this.pushStack(ce.grep(this,function(e,t){return t%2}))},eq:function(e){var t=this.length,n=+e+(e<0?t:0);return this.pushStack(0<=n&&n<t?[this[n]]:[])},end:function(){return this.prevObject||this.constructor()},push:s,sort:oe.sort,splice:oe.splice},ce.extend=ce.fn.extend=function(){var e,t,n,r,i,o,a=arguments[0]||{},s=1,u=arguments.length,l=!1;for("boolean"==typeof a&&(l=a,a=arguments[s]||{},s++),"object"==typeof a||v(a)||(a={}),s===u&&(a=this,s--);s<u;s++)if(null!=(e=arguments[s]))for(t in e)r=e[t],"__proto__"!==t&&a!==r&&(l&&r&&(ce.isPlainObject(r)||(i=Array.isArray(r)))?(n=a[t],o=i&&!Array.isArray(n)?[]:i||ce.isPlainObject(n)?n:{},i=!1,a[t]=ce.extend(l,o,r)):void 0!==r&&(a[t]=r));return a},ce.extend({expando:"jQuery"+(t+Math.random()).replace(/\D/g,""),isReady:!0,error:function(e){throw new Error(e)},noop:function(){},isPlainObject:function(e){var t,n;return!(!e||"[object Object]"!==i.call(e))&&(!(t=r(e))||"function"==typeof(n=ue.call(t,"constructor")&&t.constructor)&&o.call(n)===a)},isEmptyObject:function(e){var t;for(t in e)return!1;return!0},globalEval:function(e,t,n){m(e,{nonce:t&&t.nonce},n)},each:function(e,t){var n,r=0;if(c(e)){for(n=e.length;r<n;r++)if(!1===t.call(e[r],r,e[r]))break}else for(r in e)if(!1===t.call(e[r],r,e[r]))break;return e},text:function(e){var t,n="",r=0,i=e.nodeType;if(!i)while(t=e[r++])n+=ce.text(t);return 1===i||11===i?e.textContent:9===i?e.documentElement.textContent:3===i||4===i?e.nodeValue:n},makeArray:function(e,t){var n=t||[];return null!=e&&(c(Object(e))?ce.merge(n,"string"==typeof e?[e]:e):s.call(n,e)),n},inArray:function(e,t,n){return null==t?-1:se.call(t,e,n)},isXMLDoc:function(e){var t=e&&e.namespaceURI,n=e&&(e.ownerDocument||e).documentElement;return!l.test(t||n&&n.nodeName||"HTML")},merge:function(e,t){for(var n=+t.length,r=0,i=e.length;r<n;r++)e[i++]=t[r];return e.length=i,e},grep:function(e,t,n){for(var r=[],i=0,o=e.length,a=!n;i<o;i++)!t(e[i],i)!==a&&r.push(e[i]);return r},map:function(e,t,n){var r,i,o=0,a=[];if(c(e))for(r=e.length;o<r;o++)null!=(i=t(e[o],o,n))&&a.push(i);else for(o in e)null!=(i=t(e[o],o,n))&&a.push(i);return g(a)},guid:1,support:le}),"function"==typeof Symbol&&(ce.fn[Symbol.iterator]=oe[Symbol.iterator]),ce.each("Boolean Number String Function Array Date RegExp Object Error Symbol".split(" "),function(e,t){n["[object "+t+"]"]=t.toLowerCase()});var pe=oe.pop,de=oe.sort,he=oe.splice,ge="[\\x20\\t\\r\\n\\f]",ve=new RegExp("^"+ge+"+|((?:^|[^\\\\])(?:\\\\.)*)"+ge+"+$","g");ce.contains=function(e,t){var n=t&&t.parentNode;return e===n||!(!n||1!==n.nodeType||!(e.contains?e.contains(n):e.compareDocumentPosition&&16&e.compareDocumentPosition(n)))};var f=/([\0-\x1f\x7f]|^-?\d)|^-$|[^\x80-\uFFFF\w-]/g;function p(e,t){return t?"\0"===e?"\ufffd":e.slice(0,-1)+"\\"+e.charCodeAt(e.length-1).toString(16)+" ":"\\"+e}ce.escapeSelector=function(e){return(e+"").replace(f,p)};var ye=C,me=s;!function(){var e,b,w,o,a,T,r,C,d,i,k=me,S=ce.expando,E=0,n=0,s=W(),c=W(),u=W(),h=W(),l=function(e,t){return e===t&&(a=!0),0},f="checked|selected|async|autofocus|autoplay|controls|defer|disabled|hidden|ismap|loop|multiple|open|readonly|required|scoped",t="(?:\\\\[\\da-fA-F]{1,6}"+ge+"?|\\\\[^\\r\\n\\f]|[\\w-]|[^\0-\\x7f])+",p="\\["+ge+"*("+t+")(?:"+ge+"*([*^$|!~]?=)"+ge+"*(?:'((?:\\\\.|[^\\\\'])*)'|\"((?:\\\\.|[^\\\\\"])*)\"|("+t+"))|)"+ge+"*\\]",g=":("+t+")(?:\\((('((?:\\\\.|[^\\\\'])*)'|\"((?:\\\\.|[^\\\\\"])*)\")|((?:\\\\.|[^\\\\()[\\]]|"+p+")*)|.*)\\)|)",v=new RegExp(ge+"+","g"),y=new RegExp("^"+ge+"*,"+ge+"*"),m=new RegExp("^"+ge+"*([>+~]|"+ge+")"+ge+"*"),x=new RegExp(ge+"|>"),j=new RegExp(g),A=new RegExp("^"+t+"$"),D={ID:new RegExp("^#("+t+")"),CLASS:new RegExp("^\\.("+t+")"),TAG:new RegExp("^("+t+"|[*])"),ATTR:new RegExp("^"+p),PSEUDO:new RegExp("^"+g),CHILD:new RegExp("^:(only|first|last|nth|nth-last)-(child|of-type)(?:\\("+ge+"*(even|odd|(([+-]|)(\\d*)n|)"+ge+"*(?:([+-]|)"+ge+"*(\\d+)|))"+ge+"*\\)|)","i"),bool:new RegExp("^(?:"+f+")$","i"),needsContext:new RegExp("^"+ge+"*[>+~]|:(even|odd|eq|gt|lt|nth|first|last)(?:\\("+ge+"*((?:-\\d)?\\d*)"+ge+"*\\)|)(?=[^-]|$)","i")},N=/^(?:input|select|textarea|button)$/i,q=/^h\d$/i,L=/^(?:#([\w-]+)|(\w+)|\.([\w-]+))$/,H=/[+~]/,O=new RegExp("\\\\[\\da-fA-F]{1,6}"+ge+"?|\\\\([^\\r\\n\\f])","g"),P=function(e,t){var n="0x"+e.slice(1)-65536;return t||(n<0?String.fromCharCode(n+65536):String.fromCharCode(n>>10|55296,1023&n|56320))},M=function(){V()},R=J(function(e){return!0===e.disabled&&fe(e,"fieldset")},{dir:"parentNode",next:"legend"});try{k.apply(oe=ae.call(ye.childNodes),ye.childNodes),oe[ye.childNodes.length].nodeType}catch(e){k={apply:function(e,t){me.apply(e,ae.call(t))},call:function(e){me.apply(e,ae.call(arguments,1))}}}function I(t,e,n,r){var i,o,a,s,u,l,c,f=e&&e.ownerDocument,p=e?e.nodeType:9;if(n=n||[],"string"!=typeof t||!t||1!==p&&9!==p&&11!==p)return n;if(!r&&(V(e),e=e||T,C)){if(11!==p&&(u=L.exec(t)))if(i=u[1]){if(9===p){if(!(a=e.getElementById(i)))return n;if(a.id===i)return k.call(n,a),n}else if(f&&(a=f.getElementById(i))&&I.contains(e,a)&&a.id===i)return k.call(n,a),n}else{if(u[2])return k.apply(n,e.getElementsByTagName(t)),n;if((i=u[3])&&e.getElementsByClassName)return k.apply(n,e.getElementsByClassName(i)),n}if(!(h[t+" "]||d&&d.test(t))){if(c=t,f=e,1===p&&(x.test(t)||m.test(t))){(f=H.test(t)&&U(e.parentNode)||e)==e&&le.scope||((s=e.getAttribute("id"))?s=ce.escapeSelector(s):e.setAttribute("id",s=S)),o=(l=Y(t)).length;while(o--)l[o]=(s?"#"+s:":scope")+" "+Q(l[o]);c=l.join(",")}try{return k.apply(n,f.querySelectorAll(c)),n}catch(e){h(t,!0)}finally{s===S&&e.removeAttribute("id")}}}return re(t.replace(ve,"$1"),e,n,r)}function W(){var r=[];return function e(t,n){return r.push(t+" ")>b.cacheLength&&delete e[r.shift()],e[t+" "]=n}}function F(e){return e[S]=!0,e}function $(e){var t=T.createElement("fieldset");try{return!!e(t)}catch(e){return!1}finally{t.parentNode&&t.parentNode.removeChild(t),t=null}}function B(t){return function(e){return fe(e,"input")&&e.type===t}}function _(t){return function(e){return(fe(e,"input")||fe(e,"button"))&&e.type===t}}function z(t){return function(e){return"form"in e?e.parentNode&&!1===e.disabled?"label"in e?"label"in e.parentNode?e.parentNode.disabled===t:e.disabled===t:e.isDisabled===t||e.isDisabled!==!t&&R(e)===t:e.disabled===t:"label"in e&&e.disabled===t}}function X(a){return F(function(o){return o=+o,F(function(e,t){var n,r=a([],e.length,o),i=r.length;while(i--)e[n=r[i]]&&(e[n]=!(t[n]=e[n]))})})}function U(e){return e&&"undefined"!=typeof e.getElementsByTagName&&e}function V(e){var t,n=e?e.ownerDocument||e:ye;return n!=T&&9===n.nodeType&&n.documentElement&&(r=(T=n).documentElement,C=!ce.isXMLDoc(T),i=r.matches||r.webkitMatchesSelector||r.msMatchesSelector,r.msMatchesSelector&&ye!=T&&(t=T.defaultView)&&t.top!==t&&t.addEventListener("unload",M),le.getById=$(function(e){return r.appendChild(e).id=ce.expando,!T.getElementsByName||!T.getElementsByName(ce.expando).length}),le.disconnectedMatch=$(function(e){return i.call(e,"*")}),le.scope=$(function(){return T.querySelectorAll(":scope")}),le.cssHas=$(function(){try{return T.querySelector(":has(*,:jqfake)"),!1}catch(e){return!0}}),le.getById?(b.filter.ID=function(e){var t=e.replace(O,P);return function(e){return e.getAttribute("id")===t}},b.find.ID=function(e,t){if("undefined"!=typeof t.getElementById&&C){var n=t.getElementById(e);return n?[n]:[]}}):(b.filter.ID=function(e){var n=e.replace(O,P);return function(e){var t="undefined"!=typeof e.getAttributeNode&&e.getAttributeNode("id");return t&&t.value===n}},b.find.ID=function(e,t){if("undefined"!=typeof t.getElementById&&C){var n,r,i,o=t.getElementById(e);if(o){if((n=o.getAttributeNode("id"))&&n.value===e)return[o];i=t.getElementsByName(e),r=0;while(o=i[r++])if((n=o.getAttributeNode("id"))&&n.value===e)return[o]}return[]}}),b.find.TAG=function(e,t){return"undefined"!=typeof t.getElementsByTagName?t.getElementsByTagName(e):t.querySelectorAll(e)},b.find.CLASS=function(e,t){if("undefined"!=typeof t.getElementsByClassName&&C)return t.getElementsByClassName(e)},d=[],$(function(e){var t;r.appendChild(e).innerHTML="<a id='"+S+"' href='' disabled='disabled'></a><select id='"+S+"-\r\\' disabled='disabled'><option selected=''></option></select>",e.querySelectorAll("[selected]").length||d.push("\\["+ge+"*(?:value|"+f+")"),e.querySelectorAll("[id~="+S+"-]").length||d.push("~="),e.querySelectorAll("a#"+S+"+*").length||d.push(".#.+[+~]"),e.querySelectorAll(":checked").length||d.push(":checked"),(t=T.createElement("input")).setAttribute("type","hidden"),e.appendChild(t).setAttribute("name","D"),r.appendChild(e).disabled=!0,2!==e.querySelectorAll(":disabled").length&&d.push(":enabled",":disabled"),(t=T.createElement("input")).setAttribute("name",""),e.appendChild(t),e.querySelectorAll("[name='']").length||d.push("\\["+ge+"*name"+ge+"*="+ge+"*(?:''|\"\")")}),le.cssHas||d.push(":has"),d=d.length&&new RegExp(d.join("|")),l=function(e,t){if(e===t)return a=!0,0;var n=!e.compareDocumentPosition-!t.compareDocumentPosition;return n||(1&(n=(e.ownerDocument||e)==(t.ownerDocument||t)?e.compareDocumentPosition(t):1)||!le.sortDetached&&t.compareDocumentPosition(e)===n?e===T||e.ownerDocument==ye&&I.contains(ye,e)?-1:t===T||t.ownerDocument==ye&&I.contains(ye,t)?1:o?se.call(o,e)-se.call(o,t):0:4&n?-1:1)}),T}for(e in I.matches=function(e,t){return I(e,null,null,t)},I.matchesSelector=function(e,t){if(V(e),C&&!h[t+" "]&&(!d||!d.test(t)))try{var n=i.call(e,t);if(n||le.disconnectedMatch||e.document&&11!==e.document.nodeType)return n}catch(e){h(t,!0)}return 0<I(t,T,null,[e]).length},I.contains=function(e,t){return(e.ownerDocument||e)!=T&&V(e),ce.contains(e,t)},I.attr=function(e,t){(e.ownerDocument||e)!=T&&V(e);var n=b.attrHandle[t.toLowerCase()],r=n&&ue.call(b.attrHandle,t.toLowerCase())?n(e,t,!C):void 0;return void 0!==r?r:e.getAttribute(t)},I.error=function(e){throw new Error("Syntax error, unrecognized expression: "+e)},ce.uniqueSort=function(e){var t,n=[],r=0,i=0;if(a=!le.sortStable,o=!le.sortStable&&ae.call(e,0),de.call(e,l),a){while(t=e[i++])t===e[i]&&(r=n.push(i));while(r--)he.call(e,n[r],1)}return o=null,e},ce.fn.uniqueSort=function(){return this.pushStack(ce.uniqueSort(ae.apply(this)))},(b=ce.expr={cacheLength:50,createPseudo:F,match:D,attrHandle:{},find:{},relative:{">":{dir:"parentNode",first:!0}," ":{dir:"parentNode"},"+":{dir:"previousSibling",first:!0},"~":{dir:"previousSibling"}},preFilter:{ATTR:function(e){return e[1]=e[1].replace(O,P),e[3]=(e[3]||e[4]||e[5]||"").replace(O,P),"~="===e[2]&&(e[3]=" "+e[3]+" "),e.slice(0,4)},CHILD:function(e){return e[1]=e[1].toLowerCase(),"nth"===e[1].slice(0,3)?(e[3]||I.error(e[0]),e[4]=+(e[4]?e[5]+(e[6]||1):2*("even"===e[3]||"odd"===e[3])),e[5]=+(e[7]+e[8]||"odd"===e[3])):e[3]&&I.error(e[0]),e},PSEUDO:function(e){var t,n=!e[6]&&e[2];return D.CHILD.test(e[0])?null:(e[3]?e[2]=e[4]||e[5]||"":n&&j.test(n)&&(t=Y(n,!0))&&(t=n.indexOf(")",n.length-t)-n.length)&&(e[0]=e[0].slice(0,t),e[2]=n.slice(0,t)),e.slice(0,3))}},filter:{TAG:function(e){var t=e.replace(O,P).toLowerCase();return"*"===e?function(){return!0}:function(e){return fe(e,t)}},CLASS:function(e){var t=s[e+" "];return t||(t=new RegExp("(^|"+ge+")"+e+"("+ge+"|$)"))&&s(e,function(e){return t.test("string"==typeof e.className&&e.className||"undefined"!=typeof e.getAttribute&&e.getAttribute("class")||"")})},ATTR:function(n,r,i){return function(e){var t=I.attr(e,n);return null==t?"!="===r:!r||(t+="","="===r?t===i:"!="===r?t!==i:"^="===r?i&&0===t.indexOf(i):"*="===r?i&&-1<t.indexOf(i):"$="===r?i&&t.slice(-i.length)===i:"~="===r?-1<(" "+t.replace(v," ")+" ").indexOf(i):"|="===r&&(t===i||t.slice(0,i.length+1)===i+"-"))}},CHILD:function(d,e,t,h,g){var v="nth"!==d.slice(0,3),y="last"!==d.slice(-4),m="of-type"===e;return 1===h&&0===g?function(e){return!!e.parentNode}:function(e,t,n){var r,i,o,a,s,u=v!==y?"nextSibling":"previousSibling",l=e.parentNode,c=m&&e.nodeName.toLowerCase(),f=!n&&!m,p=!1;if(l){if(v){while(u){o=e;while(o=o[u])if(m?fe(o,c):1===o.nodeType)return!1;s=u="only"===d&&!s&&"nextSibling"}return!0}if(s=[y?l.firstChild:l.lastChild],y&&f){p=(a=(r=(i=l[S]||(l[S]={}))[d]||[])[0]===E&&r[1])&&r[2],o=a&&l.childNodes[a];while(o=++a&&o&&o[u]||(p=a=0)||s.pop())if(1===o.nodeType&&++p&&o===e){i[d]=[E,a,p];break}}else if(f&&(p=a=(r=(i=e[S]||(e[S]={}))[d]||[])[0]===E&&r[1]),!1===p)while(o=++a&&o&&o[u]||(p=a=0)||s.pop())if((m?fe(o,c):1===o.nodeType)&&++p&&(f&&((i=o[S]||(o[S]={}))[d]=[E,p]),o===e))break;return(p-=g)===h||p%h==0&&0<=p/h}}},PSEUDO:function(e,o){var t,a=b.pseudos[e]||b.setFilters[e.toLowerCase()]||I.error("unsupported pseudo: "+e);return a[S]?a(o):1<a.length?(t=[e,e,"",o],b.setFilters.hasOwnProperty(e.toLowerCase())?F(function(e,t){var n,r=a(e,o),i=r.length;while(i--)e[n=se.call(e,r[i])]=!(t[n]=r[i])}):function(e){return a(e,0,t)}):a}},pseudos:{not:F(function(e){var r=[],i=[],s=ne(e.replace(ve,"$1"));return s[S]?F(function(e,t,n,r){var i,o=s(e,null,r,[]),a=e.length;while(a--)(i=o[a])&&(e[a]=!(t[a]=i))}):function(e,t,n){return r[0]=e,s(r,null,n,i),r[0]=null,!i.pop()}}),has:F(function(t){return function(e){return 0<I(t,e).length}}),contains:F(function(t){return t=t.replace(O,P),function(e){return-1<(e.textContent||ce.text(e)).indexOf(t)}}),lang:F(function(n){return A.test(n||"")||I.error("unsupported lang: "+n),n=n.replace(O,P).toLowerCase(),function(e){var t;do{if(t=C?e.lang:e.getAttribute("xml:lang")||e.getAttribute("lang"))return(t=t.toLowerCase())===n||0===t.indexOf(n+"-")}while((e=e.parentNode)&&1===e.nodeType);return!1}}),target:function(e){var t=ie.location&&ie.location.hash;return t&&t.slice(1)===e.id},root:function(e){return e===r},focus:function(e){return e===function(){try{return T.activeElement}catch(e){}}()&&T.hasFocus()&&!!(e.type||e.href||~e.tabIndex)},enabled:z(!1),disabled:z(!0),checked:function(e){return fe(e,"input")&&!!e.checked||fe(e,"option")&&!!e.selected},selected:function(e){return e.parentNode&&e.parentNode.selectedIndex,!0===e.selected},empty:function(e){for(e=e.firstChild;e;e=e.nextSibling)if(e.nodeType<6)return!1;return!0},parent:function(e){return!b.pseudos.empty(e)},header:function(e){return q.test(e.nodeName)},input:function(e){return N.test(e.nodeName)},button:function(e){return fe(e,"input")&&"button"===e.type||fe(e,"button")},text:function(e){var t;return fe(e,"input")&&"text"===e.type&&(null==(t=e.getAttribute("type"))||"text"===t.toLowerCase())},first:X(function(){return[0]}),last:X(function(e,t){return[t-1]}),eq:X(function(e,t,n){return[n<0?n+t:n]}),even:X(function(e,t){for(var n=0;n<t;n+=2)e.push(n);return e}),odd:X(function(e,t){for(var n=1;n<t;n+=2)e.push(n);return e}),lt:X(function(e,t,n){var r;for(r=n<0?n+t:t<n?t:n;0<=--r;)e.push(r);return e}),gt:X(function(e,t,n){for(var r=n<0?n+t:n;++r<t;)e.push(r);return e})}}).pseudos.nth=b.pseudos.eq,{radio:!0,checkbox:!0,file:!0,password:!0,image:!0})b.pseudos[e]=B(e);for(e in{submit:!0,reset:!0})b.pseudos[e]=_(e);function G(){}function Y(e,t){var n,r,i,o,a,s,u,l=c[e+" "];if(l)return t?0:l.slice(0);a=e,s=[],u=b.preFilter;while(a){for(o in n&&!(r=y.exec(a))||(r&&(a=a.slice(r[0].length)||a),s.push(i=[])),n=!1,(r=m.exec(a))&&(n=r.shift(),i.push({value:n,type:r[0].replace(ve," ")}),a=a.slice(n.length)),b.filter)!(r=D[o].exec(a))||u[o]&&!(r=u[o](r))||(n=r.shift(),i.push({value:n,type:o,matches:r}),a=a.slice(n.length));if(!n)break}return t?a.length:a?I.error(e):c(e,s).slice(0)}function Q(e){for(var t=0,n=e.length,r="";t<n;t++)r+=e[t].value;return r}function J(a,e,t){var s=e.dir,u=e.next,l=u||s,c=t&&"parentNode"===l,f=n++;return e.first?function(e,t,n){while(e=e[s])if(1===e.nodeType||c)return a(e,t,n);return!1}:function(e,t,n){var r,i,o=[E,f];if(n){while(e=e[s])if((1===e.nodeType||c)&&a(e,t,n))return!0}else while(e=e[s])if(1===e.nodeType||c)if(i=e[S]||(e[S]={}),u&&fe(e,u))e=e[s]||e;else{if((r=i[l])&&r[0]===E&&r[1]===f)return o[2]=r[2];if((i[l]=o)[2]=a(e,t,n))return!0}return!1}}function K(i){return 1<i.length?function(e,t,n){var r=i.length;while(r--)if(!i[r](e,t,n))return!1;return!0}:i[0]}function Z(e,t,n,r,i){for(var o,a=[],s=0,u=e.length,l=null!=t;s<u;s++)(o=e[s])&&(n&&!n(o,r,i)||(a.push(o),l&&t.push(s)));return a}function ee(d,h,g,v,y,e){return v&&!v[S]&&(v=ee(v)),y&&!y[S]&&(y=ee(y,e)),F(function(e,t,n,r){var i,o,a,s,u=[],l=[],c=t.length,f=e||function(e,t,n){for(var r=0,i=t.length;r<i;r++)I(e,t[r],n);return n}(h||"*",n.nodeType?[n]:n,[]),p=!d||!e&&h?f:Z(f,u,d,n,r);if(g?g(p,s=y||(e?d:c||v)?[]:t,n,r):s=p,v){i=Z(s,l),v(i,[],n,r),o=i.length;while(o--)(a=i[o])&&(s[l[o]]=!(p[l[o]]=a))}if(e){if(y||d){if(y){i=[],o=s.length;while(o--)(a=s[o])&&i.push(p[o]=a);y(null,s=[],i,r)}o=s.length;while(o--)(a=s[o])&&-1<(i=y?se.call(e,a):u[o])&&(e[i]=!(t[i]=a))}}else s=Z(s===t?s.splice(c,s.length):s),y?y(null,t,s,r):k.apply(t,s)})}function te(e){for(var i,t,n,r=e.length,o=b.relative[e[0].type],a=o||b.relative[" "],s=o?1:0,u=J(function(e){return e===i},a,!0),l=J(function(e){return-1<se.call(i,e)},a,!0),c=[function(e,t,n){var r=!o&&(n||t!=w)||((i=t).nodeType?u(e,t,n):l(e,t,n));return i=null,r}];s<r;s++)if(t=b.relative[e[s].type])c=[J(K(c),t)];else{if((t=b.filter[e[s].type].apply(null,e[s].matches))[S]){for(n=++s;n<r;n++)if(b.relative[e[n].type])break;return ee(1<s&&K(c),1<s&&Q(e.slice(0,s-1).concat({value:" "===e[s-2].type?"*":""})).replace(ve,"$1"),t,s<n&&te(e.slice(s,n)),n<r&&te(e=e.slice(n)),n<r&&Q(e))}c.push(t)}return K(c)}function ne(e,t){var n,v,y,m,x,r,i=[],o=[],a=u[e+" "];if(!a){t||(t=Y(e)),n=t.length;while(n--)(a=te(t[n]))[S]?i.push(a):o.push(a);(a=u(e,(v=o,m=0<(y=i).length,x=0<v.length,r=function(e,t,n,r,i){var o,a,s,u=0,l="0",c=e&&[],f=[],p=w,d=e||x&&b.find.TAG("*",i),h=E+=null==p?1:Math.random()||.1,g=d.length;for(i&&(w=t==T||t||i);l!==g&&null!=(o=d[l]);l++){if(x&&o){a=0,t||o.ownerDocument==T||(V(o),n=!C);while(s=v[a++])if(s(o,t||T,n)){k.call(r,o);break}i&&(E=h)}m&&((o=!s&&o)&&u--,e&&c.push(o))}if(u+=l,m&&l!==u){a=0;while(s=y[a++])s(c,f,t,n);if(e){if(0<u)while(l--)c[l]||f[l]||(f[l]=pe.call(r));f=Z(f)}k.apply(r,f),i&&!e&&0<f.length&&1<u+y.length&&ce.uniqueSort(r)}return i&&(E=h,w=p),c},m?F(r):r))).selector=e}return a}function re(e,t,n,r){var i,o,a,s,u,l="function"==typeof e&&e,c=!r&&Y(e=l.selector||e);if(n=n||[],1===c.length){if(2<(o=c[0]=c[0].slice(0)).length&&"ID"===(a=o[0]).type&&9===t.nodeType&&C&&b.relative[o[1].type]){if(!(t=(b.find.ID(a.matches[0].replace(O,P),t)||[])[0]))return n;l&&(t=t.parentNode),e=e.slice(o.shift().value.length)}i=D.needsContext.test(e)?0:o.length;while(i--){if(a=o[i],b.relative[s=a.type])break;if((u=b.find[s])&&(r=u(a.matches[0].replace(O,P),H.test(o[0].type)&&U(t.parentNode)||t))){if(o.splice(i,1),!(e=r.length&&Q(o)))return k.apply(n,r),n;break}}}return(l||ne(e,c))(r,t,!C,n,!t||H.test(e)&&U(t.parentNode)||t),n}G.prototype=b.filters=b.pseudos,b.setFilters=new G,le.sortStable=S.split("").sort(l).join("")===S,V(),le.sortDetached=$(function(e){return 1&e.compareDocumentPosition(T.createElement("fieldset"))}),ce.find=I,ce.expr[":"]=ce.expr.pseudos,ce.unique=ce.uniqueSort,I.compile=ne,I.select=re,I.setDocument=V,I.tokenize=Y,I.escape=ce.escapeSelector,I.getText=ce.text,I.isXML=ce.isXMLDoc,I.selectors=ce.expr,I.support=ce.support,I.uniqueSort=ce.uniqueSort}();var d=function(e,t,n){var r=[],i=void 0!==n;while((e=e[t])&&9!==e.nodeType)if(1===e.nodeType){if(i&&ce(e).is(n))break;r.push(e)}return r},h=function(e,t){for(var n=[];e;e=e.nextSibling)1===e.nodeType&&e!==t&&n.push(e);return n},b=ce.expr.match.needsContext,w=/^<([a-z][^\/\0>:\x20\t\r\n\f]*)[\x20\t\r\n\f]*\/?>(?:<\/\1>|)$/i;function T(e,n,r){return v(n)?ce.grep(e,function(e,t){return!!n.call(e,t,e)!==r}):n.nodeType?ce.grep(e,function(e){return e===n!==r}):"string"!=typeof n?ce.grep(e,function(e){return-1<se.call(n,e)!==r}):ce.filter(n,e,r)}ce.filter=function(e,t,n){var r=t[0];return n&&(e=":not("+e+")"),1===t.length&&1===r.nodeType?ce.find.matchesSelector(r,e)?[r]:[]:ce.find.matches(e,ce.grep(t,function(e){return 1===e.nodeType}))},ce.fn.extend({find:function(e){var t,n,r=this.length,i=this;if("string"!=typeof e)return this.pushStack(ce(e).filter(function(){for(t=0;t<r;t++)if(ce.contains(i[t],this))return!0}));for(n=this.pushStack([]),t=0;t<r;t++)ce.find(e,i[t],n);return 1<r?ce.uniqueSort(n):n},filter:function(e){return this.pushStack(T(this,e||[],!1))},not:function(e){return this.pushStack(T(this,e||[],!0))},is:function(e){return!!T(this,"string"==typeof e&&b.test(e)?ce(e):e||[],!1).length}});var k,S=/^(?:\s*(<[\w\W]+>)[^>]*|#([\w-]+))$/;(ce.fn.init=function(e,t,n){var r,i;if(!e)return this;if(n=n||k,"string"==typeof e){if(!(r="<"===e[0]&&">"===e[e.length-1]&&3<=e.length?[null,e,null]:S.exec(e))||!r[1]&&t)return!t||t.jquery?(t||n).find(e):this.constructor(t).find(e);if(r[1]){if(t=t instanceof ce?t[0]:t,ce.merge(this,ce.parseHTML(r[1],t&&t.nodeType?t.ownerDocument||t:C,!0)),w.test(r[1])&&ce.isPlainObject(t))for(r in t)v(this[r])?this[r](t[r]):this.attr(r,t[r]);return this}return(i=C.getElementById(r[2]))&&(this[0]=i,this.length=1),this}return e.nodeType?(this[0]=e,this.length=1,this):v(e)?void 0!==n.ready?n.ready(e):e(ce):ce.makeArray(e,this)}).prototype=ce.fn,k=ce(C);var E=/^(?:parents|prev(?:Until|All))/,j={children:!0,contents:!0,next:!0,prev:!0};function A(e,t){while((e=e[t])&&1!==e.nodeType);return e}ce.fn.extend({has:function(e){var t=ce(e,this),n=t.length;return this.filter(function(){for(var e=0;e<n;e++)if(ce.contains(this,t[e]))return!0})},closest:function(e,t){var n,r=0,i=this.length,o=[],a="string"!=typeof e&&ce(e);if(!b.test(e))for(;r<i;r++)for(n=this[r];n&&n!==t;n=n.parentNode)if(n.nodeType<11&&(a?-1<a.index(n):1===n.nodeType&&ce.find.matchesSelector(n,e))){o.push(n);break}return this.pushStack(1<o.length?ce.uniqueSort(o):o)},index:function(e){return e?"string"==typeof e?se.call(ce(e),this[0]):se.call(this,e.jquery?e[0]:e):this[0]&&this[0].parentNode?this.first().prevAll().length:-1},add:function(e,t){return this.pushStack(ce.uniqueSort(ce.merge(this.get(),ce(e,t))))},addBack:function(e){return this.add(null==e?this.prevObject:this.prevObject.filter(e))}}),ce.each({parent:function(e){var t=e.parentNode;return t&&11!==t.nodeType?t:null},parents:function(e){return d(e,"parentNode")},parentsUntil:function(e,t,n){return d(e,"parentNode",n)},next:function(e){return A(e,"nextSibling")},prev:function(e){return A(e,"previousSibling")},nextAll:function(e){return d(e,"nextSibling")},prevAll:function(e){return d(e,"previousSibling")},nextUntil:function(e,t,n){return d(e,"nextSibling",n)},prevUntil:function(e,t,n){return d(e,"previousSibling",n)},siblings:function(e){return h((e.parentNode||{}).firstChild,e)},children:function(e){return h(e.firstChild)},contents:function(e){return null!=e.contentDocument&&r(e.contentDocument)?e.contentDocument:(fe(e,"template")&&(e=e.content||e),ce.merge([],e.childNodes))}},function(r,i){ce.fn[r]=function(e,t){var n=ce.map(this,i,e);return"Until"!==r.slice(-5)&&(t=e),t&&"string"==typeof t&&(n=ce.filter(t,n)),1<this.length&&(j[r]||ce.uniqueSort(n),E.test(r)&&n.reverse()),this.pushStack(n)}});var D=/[^\x20\t\r\n\f]+/g;function N(e){return e}function q(e){throw e}function L(e,t,n,r){var i;try{e&&v(i=e.promise)?i.call(e).done(t).fail(n):e&&v(i=e.then)?i.call(e,t,n):t.apply(void 0,[e].slice(r))}catch(e){n.apply(void 0,[e])}}ce.Callbacks=function(r){var e,n;r="string"==typeof r?(e=r,n={},ce.each(e.match(D)||[],function(e,t){n[t]=!0}),n):ce.extend({},r);var i,t,o,a,s=[],u=[],l=-1,c=function(){for(a=a||r.once,o=i=!0;u.length;l=-1){t=u.shift();while(++l<s.length)!1===s[l].apply(t[0],t[1])&&r.stopOnFalse&&(l=s.length,t=!1)}r.memory||(t=!1),i=!1,a&&(s=t?[]:"")},f={add:function(){return s&&(t&&!i&&(l=s.length-1,u.push(t)),function n(e){ce.each(e,function(e,t){v(t)?r.unique&&f.has(t)||s.push(t):t&&t.length&&"string"!==x(t)&&n(t)})}(arguments),t&&!i&&c()),this},remove:function(){return ce.each(arguments,function(e,t){var n;while(-1<(n=ce.inArray(t,s,n)))s.splice(n,1),n<=l&&l--}),this},has:function(e){return e?-1<ce.inArray(e,s):0<s.length},empty:function(){return s&&(s=[]),this},disable:function(){return a=u=[],s=t="",this},disabled:function(){return!s},lock:function(){return a=u=[],t||i||(s=t=""),this},locked:function(){return!!a},fireWith:function(e,t){return a||(t=[e,(t=t||[]).slice?t.slice():t],u.push(t),i||c()),this},fire:function(){return f.fireWith(this,arguments),this},fired:function(){return!!o}};return f},ce.extend({Deferred:function(e){var o=[["notify","progress",ce.Callbacks("memory"),ce.Callbacks("memory"),2],["resolve","done",ce.Callbacks("once memory"),ce.Callbacks("once memory"),0,"resolved"],["reject","fail",ce.Callbacks("once memory"),ce.Callbacks("once memory"),1,"rejected"]],i="pending",a={state:function(){return i},always:function(){return s.done(arguments).fail(arguments),this},"catch":function(e){return a.then(null,e)},pipe:function(){var i=arguments;return ce.Deferred(function(r){ce.each(o,function(e,t){var n=v(i[t[4]])&&i[t[4]];s[t[1]](function(){var e=n&&n.apply(this,arguments);e&&v(e.promise)?e.promise().progress(r.notify).done(r.resolve).fail(r.reject):r[t[0]+"With"](this,n?[e]:arguments)})}),i=null}).promise()},then:function(t,n,r){var u=0;function l(i,o,a,s){return function(){var n=this,r=arguments,e=function(){var e,t;if(!(i<u)){if((e=a.apply(n,r))===o.promise())throw new TypeError("Thenable self-resolution");t=e&&("object"==typeof e||"function"==typeof e)&&e.then,v(t)?s?t.call(e,l(u,o,N,s),l(u,o,q,s)):(u++,t.call(e,l(u,o,N,s),l(u,o,q,s),l(u,o,N,o.notifyWith))):(a!==N&&(n=void 0,r=[e]),(s||o.resolveWith)(n,r))}},t=s?e:function(){try{e()}catch(e){ce.Deferred.exceptionHook&&ce.Deferred.exceptionHook(e,t.error),u<=i+1&&(a!==q&&(n=void 0,r=[e]),o.rejectWith(n,r))}};i?t():(ce.Deferred.getErrorHook?t.error=ce.Deferred.getErrorHook():ce.Deferred.getStackHook&&(t.error=ce.Deferred.getStackHook()),ie.setTimeout(t))}}return ce.Deferred(function(e){o[0][3].add(l(0,e,v(r)?r:N,e.notifyWith)),o[1][3].add(l(0,e,v(t)?t:N)),o[2][3].add(l(0,e,v(n)?n:q))}).promise()},promise:function(e){return null!=e?ce.extend(e,a):a}},s={};return ce.each(o,function(e,t){var n=t[2],r=t[5];a[t[1]]=n.add,r&&n.add(function(){i=r},o[3-e][2].disable,o[3-e][3].disable,o[0][2].lock,o[0][3].lock),n.add(t[3].fire),s[t[0]]=function(){return s[t[0]+"With"](this===s?void 0:this,arguments),this},s[t[0]+"With"]=n.fireWith}),a.promise(s),e&&e.call(s,s),s},when:function(e){var n=arguments.length,t=n,r=Array(t),i=ae.call(arguments),o=ce.Deferred(),a=function(t){return function(e){r[t]=this,i[t]=1<arguments.length?ae.call(arguments):e,--n||o.resolveWith(r,i)}};if(n<=1&&(L(e,o.done(a(t)).resolve,o.reject,!n),"pending"===o.state()||v(i[t]&&i[t].then)))return o.then();while(t--)L(i[t],a(t),o.reject);return o.promise()}});var H=/^(Eval|Internal|Range|Reference|Syntax|Type|URI)Error$/;ce.Deferred.exceptionHook=function(e,t){ie.console&&ie.console.warn&&e&&H.test(e.name)&&ie.console.warn("jQuery.Deferred exception: "+e.message,e.stack,t)},ce.readyException=function(e){ie.setTimeout(function(){throw e})};var O=ce.Deferred();function P(){C.removeEventListener("DOMContentLoaded",P),ie.removeEventListener("load",P),ce.ready()}ce.fn.ready=function(e){return O.then(e)["catch"](function(e){ce.readyException(e)}),this},ce.extend({isReady:!1,readyWait:1,ready:function(e){(!0===e?--ce.readyWait:ce.isReady)||(ce.isReady=!0)!==e&&0<--ce.readyWait||O.resolveWith(C,[ce])}}),ce.ready.then=O.then,"complete"===C.readyState||"loading"!==C.readyState&&!C.documentElement.doScroll?ie.setTimeout(ce.ready):(C.addEventListener("DOMContentLoaded",P),ie.addEventListener("load",P));var M=function(e,t,n,r,i,o,a){var s=0,u=e.length,l=null==n;if("object"===x(n))for(s in i=!0,n)M(e,t,s,n[s],!0,o,a);else if(void 0!==r&&(i=!0,v(r)||(a=!0),l&&(a?(t.call(e,r),t=null):(l=t,t=function(e,t,n){return l.call(ce(e),n)})),t))for(;s<u;s++)t(e[s],n,a?r:r.call(e[s],s,t(e[s],n)));return i?e:l?t.call(e):u?t(e[0],n):o},R=/^-ms-/,I=/-([a-z])/g;function W(e,t){return t.toUpperCase()}function F(e){return e.replace(R,"ms-").replace(I,W)}var $=function(e){return 1===e.nodeType||9===e.nodeType||!+e.nodeType};function B(){this.expando=ce.expando+B.uid++}B.uid=1,B.prototype={cache:function(e){var t=e[this.expando];return t||(t={},$(e)&&(e.nodeType?e[this.expando]=t:Object.defineProperty(e,this.expando,{value:t,configurable:!0}))),t},set:function(e,t,n){var r,i=this.cache(e);if("string"==typeof t)i[F(t)]=n;else for(r in t)i[F(r)]=t[r];return i},get:function(e,t){return void 0===t?this.cache(e):e[this.expando]&&e[this.expando][F(t)]},access:function(e,t,n){return void 0===t||t&&"string"==typeof t&&void 0===n?this.get(e,t):(this.set(e,t,n),void 0!==n?n:t)},remove:function(e,t){var n,r=e[this.expando];if(void 0!==r){if(void 0!==t){n=(t=Array.isArray(t)?t.map(F):(t=F(t))in r?[t]:t.match(D)||[]).length;while(n--)delete r[t[n]]}(void 0===t||ce.isEmptyObject(r))&&(e.nodeType?e[this.expando]=void 0:delete e[this.expando])}},hasData:function(e){var t=e[this.expando];return void 0!==t&&!ce.isEmptyObject(t)}};var _=new B,z=new B,X=/^(?:\{[\w\W]*\}|\[[\w\W]*\])$/,U=/[A-Z]/g;function V(e,t,n){var r,i;if(void 0===n&&1===e.nodeType)if(r="data-"+t.replace(U,"-$&").toLowerCase(),"string"==typeof(n=e.getAttribute(r))){try{n="true"===(i=n)||"false"!==i&&("null"===i?null:i===+i+""?+i:X.test(i)?JSON.parse(i):i)}catch(e){}z.set(e,t,n)}else n=void 0;return n}ce.extend({hasData:function(e){return z.hasData(e)||_.hasData(e)},data:function(e,t,n){return z.access(e,t,n)},removeData:function(e,t){z.remove(e,t)},_data:function(e,t,n){return _.access(e,t,n)},_removeData:function(e,t){_.remove(e,t)}}),ce.fn.extend({data:function(n,e){var t,r,i,o=this[0],a=o&&o.attributes;if(void 0===n){if(this.length&&(i=z.get(o),1===o.nodeType&&!_.get(o,"hasDataAttrs"))){t=a.length;while(t--)a[t]&&0===(r=a[t].name).indexOf("data-")&&(r=F(r.slice(5)),V(o,r,i[r]));_.set(o,"hasDataAttrs",!0)}return i}return"object"==typeof n?this.each(function(){z.set(this,n)}):M(this,function(e){var t;if(o&&void 0===e)return void 0!==(t=z.get(o,n))?t:void 0!==(t=V(o,n))?t:void 0;this.each(function(){z.set(this,n,e)})},null,e,1<arguments.length,null,!0)},removeData:function(e){return this.each(function(){z.remove(this,e)})}}),ce.extend({queue:function(e,t,n){var r;if(e)return t=(t||"fx")+"queue",r=_.get(e,t),n&&(!r||Array.isArray(n)?r=_.access(e,t,ce.makeArray(n)):r.push(n)),r||[]},dequeue:function(e,t){t=t||"fx";var n=ce.queue(e,t),r=n.length,i=n.shift(),o=ce._queueHooks(e,t);"inprogress"===i&&(i=n.shift(),r--),i&&("fx"===t&&n.unshift("inprogress"),delete o.stop,i.call(e,function(){ce.dequeue(e,t)},o)),!r&&o&&o.empty.fire()},_queueHooks:function(e,t){var n=t+"queueHooks";return _.get(e,n)||_.access(e,n,{empty:ce.Callbacks("once memory").add(function(){_.remove(e,[t+"queue",n])})})}}),ce.fn.extend({queue:function(t,n){var e=2;return"string"!=typeof t&&(n=t,t="fx",e--),arguments.length<e?ce.queue(this[0],t):void 0===n?this:this.each(function(){var e=ce.queue(this,t,n);ce._queueHooks(this,t),"fx"===t&&"inprogress"!==e[0]&&ce.dequeue(this,t)})},dequeue:function(e){return this.each(function(){ce.dequeue(this,e)})},clearQueue:function(e){return this.queue(e||"fx",[])},promise:function(e,t){var n,r=1,i=ce.Deferred(),o=this,a=this.length,s=function(){--r||i.resolveWith(o,[o])};"string"!=typeof e&&(t=e,e=void 0),e=e||"fx";while(a--)(n=_.get(o[a],e+"queueHooks"))&&n.empty&&(r++,n.empty.add(s));return s(),i.promise(t)}});var G=/[+-]?(?:\d*\.|)\d+(?:[eE][+-]?\d+|)/.source,Y=new RegExp("^(?:([+-])=|)("+G+")([a-z%]*)$","i"),Q=["Top","Right","Bottom","Left"],J=C.documentElement,K=function(e){return ce.contains(e.ownerDocument,e)},Z={composed:!0};J.getRootNode&&(K=function(e){return ce.contains(e.ownerDocument,e)||e.getRootNode(Z)===e.ownerDocument});var ee=function(e,t){return"none"===(e=t||e).style.display||""===e.style.display&&K(e)&&"none"===ce.css(e,"display")};function te(e,t,n,r){var i,o,a=20,s=r?function(){return r.cur()}:function(){return ce.css(e,t,"")},u=s(),l=n&&n[3]||(ce.cssNumber[t]?"":"px"),c=e.nodeType&&(ce.cssNumber[t]||"px"!==l&&+u)&&Y.exec(ce.css(e,t));if(c&&c[3]!==l){u/=2,l=l||c[3],c=+u||1;while(a--)ce.style(e,t,c+l),(1-o)*(1-(o=s()/u||.5))<=0&&(a=0),c/=o;c*=2,ce.style(e,t,c+l),n=n||[]}return n&&(c=+c||+u||0,i=n[1]?c+(n[1]+1)*n[2]:+n[2],r&&(r.unit=l,r.start=c,r.end=i)),i}var ne={};function re(e,t){for(var n,r,i,o,a,s,u,l=[],c=0,f=e.length;c<f;c++)(r=e[c]).style&&(n=r.style.display,t?("none"===n&&(l[c]=_.get(r,"display")||null,l[c]||(r.style.display="")),""===r.style.display&&ee(r)&&(l[c]=(u=a=o=void 0,a=(i=r).ownerDocument,s=i.nodeName,(u=ne[s])||(o=a.body.appendChild(a.createElement(s)),u=ce.css(o,"display"),o.parentNode.removeChild(o),"none"===u&&(u="block"),ne[s]=u)))):"none"!==n&&(l[c]="none",_.set(r,"display",n)));for(c=0;c<f;c++)null!=l[c]&&(e[c].style.display=l[c]);return e}ce.fn.extend({show:function(){return re(this,!0)},hide:function(){return re(this)},toggle:function(e){return"boolean"==typeof e?e?this.show():this.hide():this.each(function(){ee(this)?ce(this).show():ce(this).hide()})}});var xe,be,we=/^(?:checkbox|radio)$/i,Te=/<([a-z][^\/\0>\x20\t\r\n\f]*)/i,Ce=/^$|^module$|\/(?:java|ecma)script/i;xe=C.createDocumentFragment().appendChild(C.createElement("div")),(be=C.createElement("input")).setAttribute("type","radio"),be.setAttribute("checked","checked"),be.setAttribute("name","t"),xe.appendChild(be),le.checkClone=xe.cloneNode(!0).cloneNode(!0).lastChild.checked,xe.innerHTML="<textarea>x</textarea>",le.noCloneChecked=!!xe.cloneNode(!0).lastChild.defaultValue,xe.innerHTML="<option></option>",le.option=!!xe.lastChild;var ke={thead:[1,"<table>","</table>"],col:[2,"<table><colgroup>","</colgroup></table>"],tr:[2,"<table><tbody>","</tbody></table>"],td:[3,"<table><tbody><tr>","</tr></tbody></table>"],_default:[0,"",""]};function Se(e,t){var n;return n="undefined"!=typeof e.getElementsByTagName?e.getElementsByTagName(t||"*"):"undefined"!=typeof e.querySelectorAll?e.querySelectorAll(t||"*"):[],void 0===t||t&&fe(e,t)?ce.merge([e],n):n}function Ee(e,t){for(var n=0,r=e.length;n<r;n++)_.set(e[n],"globalEval",!t||_.get(t[n],"globalEval"))}ke.tbody=ke.tfoot=ke.colgroup=ke.caption=ke.thead,ke.th=ke.td,le.option||(ke.optgroup=ke.option=[1,"<select multiple='multiple'>","</select>"]);var je=/<|&#?\w+;/;function Ae(e,t,n,r,i){for(var o,a,s,u,l,c,f=t.createDocumentFragment(),p=[],d=0,h=e.length;d<h;d++)if((o=e[d])||0===o)if("object"===x(o))ce.merge(p,o.nodeType?[o]:o);else if(je.test(o)){a=a||f.appendChild(t.createElement("div")),s=(Te.exec(o)||["",""])[1].toLowerCase(),u=ke[s]||ke._default,a.innerHTML=u[1]+ce.htmlPrefilter(o)+u[2],c=u[0];while(c--)a=a.lastChild;ce.merge(p,a.childNodes),(a=f.firstChild).textContent=""}else p.push(t.createTextNode(o));f.textContent="",d=0;while(o=p[d++])if(r&&-1<ce.inArray(o,r))i&&i.push(o);else if(l=K(o),a=Se(f.appendChild(o),"script"),l&&Ee(a),n){c=0;while(o=a[c++])Ce.test(o.type||"")&&n.push(o)}return f}var De=/^([^.]*)(?:\.(.+)|)/;function Ne(){return!0}function qe(){return!1}function Le(e,t,n,r,i,o){var a,s;if("object"==typeof t){for(s in"string"!=typeof n&&(r=r||n,n=void 0),t)Le(e,s,n,r,t[s],o);return e}if(null==r&&null==i?(i=n,r=n=void 0):null==i&&("string"==typeof n?(i=r,r=void 0):(i=r,r=n,n=void 0)),!1===i)i=qe;else if(!i)return e;return 1===o&&(a=i,(i=function(e){return ce().off(e),a.apply(this,arguments)}).guid=a.guid||(a.guid=ce.guid++)),e.each(function(){ce.event.add(this,t,i,r,n)})}function He(e,r,t){t?(_.set(e,r,!1),ce.event.add(e,r,{namespace:!1,handler:function(e){var t,n=_.get(this,r);if(1&e.isTrigger&&this[r]){if(n)(ce.event.special[r]||{}).delegateType&&e.stopPropagation();else if(n=ae.call(arguments),_.set(this,r,n),this[r](),t=_.get(this,r),_.set(this,r,!1),n!==t)return e.stopImmediatePropagation(),e.preventDefault(),t}else n&&(_.set(this,r,ce.event.trigger(n[0],n.slice(1),this)),e.stopPropagation(),e.isImmediatePropagationStopped=Ne)}})):void 0===_.get(e,r)&&ce.event.add(e,r,Ne)}ce.event={global:{},add:function(t,e,n,r,i){var o,a,s,u,l,c,f,p,d,h,g,v=_.get(t);if($(t)){n.handler&&(n=(o=n).handler,i=o.selector),i&&ce.find.matchesSelector(J,i),n.guid||(n.guid=ce.guid++),(u=v.events)||(u=v.events=Object.create(null)),(a=v.handle)||(a=v.handle=function(e){return"undefined"!=typeof ce&&ce.event.triggered!==e.type?ce.event.dispatch.apply(t,arguments):void 0}),l=(e=(e||"").match(D)||[""]).length;while(l--)d=g=(s=De.exec(e[l])||[])[1],h=(s[2]||"").split(".").sort(),d&&(f=ce.event.special[d]||{},d=(i?f.delegateType:f.bindType)||d,f=ce.event.special[d]||{},c=ce.extend({type:d,origType:g,data:r,handler:n,guid:n.guid,selector:i,needsContext:i&&ce.expr.match.needsContext.test(i),namespace:h.join(".")},o),(p=u[d])||((p=u[d]=[]).delegateCount=0,f.setup&&!1!==f.setup.call(t,r,h,a)||t.addEventListener&&t.addEventListener(d,a)),f.add&&(f.add.call(t,c),c.handler.guid||(c.handler.guid=n.guid)),i?p.splice(p.delegateCount++,0,c):p.push(c),ce.event.global[d]=!0)}},remove:function(e,t,n,r,i){var o,a,s,u,l,c,f,p,d,h,g,v=_.hasData(e)&&_.get(e);if(v&&(u=v.events)){l=(t=(t||"").match(D)||[""]).length;while(l--)if(d=g=(s=De.exec(t[l])||[])[1],h=(s[2]||"").split(".").sort(),d){f=ce.event.special[d]||{},p=u[d=(r?f.delegateType:f.bindType)||d]||[],s=s[2]&&new RegExp("(^|\\.)"+h.join("\\.(?:.*\\.|)")+"(\\.|$)"),a=o=p.length;while(o--)c=p[o],!i&&g!==c.origType||n&&n.guid!==c.guid||s&&!s.test(c.namespace)||r&&r!==c.selector&&("**"!==r||!c.selector)||(p.splice(o,1),c.selector&&p.delegateCount--,f.remove&&f.remove.call(e,c));a&&!p.length&&(f.teardown&&!1!==f.teardown.call(e,h,v.handle)||ce.removeEvent(e,d,v.handle),delete u[d])}else for(d in u)ce.event.remove(e,d+t[l],n,r,!0);ce.isEmptyObject(u)&&_.remove(e,"handle events")}},dispatch:function(e){var t,n,r,i,o,a,s=new Array(arguments.length),u=ce.event.fix(e),l=(_.get(this,"events")||Object.create(null))[u.type]||[],c=ce.event.special[u.type]||{};for(s[0]=u,t=1;t<arguments.length;t++)s[t]=arguments[t];if(u.delegateTarget=this,!c.preDispatch||!1!==c.preDispatch.call(this,u)){a=ce.event.handlers.call(this,u,l),t=0;while((i=a[t++])&&!u.isPropagationStopped()){u.currentTarget=i.elem,n=0;while((o=i.handlers[n++])&&!u.isImmediatePropagationStopped())u.rnamespace&&!1!==o.namespace&&!u.rnamespace.test(o.namespace)||(u.handleObj=o,u.data=o.data,void 0!==(r=((ce.event.special[o.origType]||{}).handle||o.handler).apply(i.elem,s))&&!1===(u.result=r)&&(u.preventDefault(),u.stopPropagation()))}return c.postDispatch&&c.postDispatch.call(this,u),u.result}},handlers:function(e,t){var n,r,i,o,a,s=[],u=t.delegateCount,l=e.target;if(u&&l.nodeType&&!("click"===e.type&&1<=e.button))for(;l!==this;l=l.parentNode||this)if(1===l.nodeType&&("click"!==e.type||!0!==l.disabled)){for(o=[],a={},n=0;n<u;n++)void 0===a[i=(r=t[n]).selector+" "]&&(a[i]=r.needsContext?-1<ce(i,this).index(l):ce.find(i,this,null,[l]).length),a[i]&&o.push(r);o.length&&s.push({elem:l,handlers:o})}return l=this,u<t.length&&s.push({elem:l,handlers:t.slice(u)}),s},addProp:function(t,e){Object.defineProperty(ce.Event.prototype,t,{enumerable:!0,configurable:!0,get:v(e)?function(){if(this.originalEvent)return e(this.originalEvent)}:function(){if(this.originalEvent)return this.originalEvent[t]},set:function(e){Object.defineProperty(this,t,{enumerable:!0,configurable:!0,writable:!0,value:e})}})},fix:function(e){return e[ce.expando]?e:new ce.Event(e)},special:{load:{noBubble:!0},click:{setup:function(e){var t=this||e;return we.test(t.type)&&t.click&&fe(t,"input")&&He(t,"click",!0),!1},trigger:function(e){var t=this||e;return we.test(t.type)&&t.click&&fe(t,"input")&&He(t,"click"),!0},_default:function(e){var t=e.target;return we.test(t.type)&&t.click&&fe(t,"input")&&_.get(t,"click")||fe(t,"a")}},beforeunload:{postDispatch:function(e){void 0!==e.result&&e.originalEvent&&(e.originalEvent.returnValue=e.result)}}}},ce.removeEvent=function(e,t,n){e.removeEventListener&&e.removeEventListener(t,n)},ce.Event=function(e,t){if(!(this instanceof ce.Event))return new ce.Event(e,t);e&&e.type?(this.originalEvent=e,this.type=e.type,this.isDefaultPrevented=e.defaultPrevented||void 0===e.defaultPrevented&&!1===e.returnValue?Ne:qe,this.target=e.target&&3===e.target.nodeType?e.target.parentNode:e.target,this.currentTarget=e.currentTarget,this.relatedTarget=e.relatedTarget):this.type=e,t&&ce.extend(this,t),this.timeStamp=e&&e.timeStamp||Date.now(),this[ce.expando]=!0},ce.Event.prototype={constructor:ce.Event,isDefaultPrevented:qe,isPropagationStopped:qe,isImmediatePropagationStopped:qe,isSimulated:!1,preventDefault:function(){var e=this.originalEvent;this.isDefaultPrevented=Ne,e&&!this.isSimulated&&e.preventDefault()},stopPropagation:function(){var e=this.originalEvent;this.isPropagationStopped=Ne,e&&!this.isSimulated&&e.stopPropagation()},stopImmediatePropagation:function(){var e=this.originalEvent;this.isImmediatePropagationStopped=Ne,e&&!this.isSimulated&&e.stopImmediatePropagation(),this.stopPropagation()}},ce.each({altKey:!0,bubbles:!0,cancelable:!0,changedTouches:!0,ctrlKey:!0,detail:!0,eventPhase:!0,metaKey:!0,pageX:!0,pageY:!0,shiftKey:!0,view:!0,"char":!0,code:!0,charCode:!0,key:!0,keyCode:!0,button:!0,buttons:!0,clientX:!0,clientY:!0,offsetX:!0,offsetY:!0,pointerId:!0,pointerType:!0,screenX:!0,screenY:!0,targetTouches:!0,toElement:!0,touches:!0,which:!0},ce.event.addProp),ce.each({focus:"focusin",blur:"focusout"},function(r,i){function o(e){if(C.documentMode){var t=_.get(this,"handle"),n=ce.event.fix(e);n.type="focusin"===e.type?"focus":"blur",n.isSimulated=!0,t(e),n.target===n.currentTarget&&t(n)}else ce.event.simulate(i,e.target,ce.event.fix(e))}ce.event.special[r]={setup:function(){var e;if(He(this,r,!0),!C.documentMode)return!1;(e=_.get(this,i))||this.addEventListener(i,o),_.set(this,i,(e||0)+1)},trigger:function(){return He(this,r),!0},teardown:function(){var e;if(!C.documentMode)return!1;(e=_.get(this,i)-1)?_.set(this,i,e):(this.removeEventListener(i,o),_.remove(this,i))},_default:function(e){return _.get(e.target,r)},delegateType:i},ce.event.special[i]={setup:function(){var e=this.ownerDocument||this.document||this,t=C.documentMode?this:e,n=_.get(t,i);n||(C.documentMode?this.addEventListener(i,o):e.addEventListener(r,o,!0)),_.set(t,i,(n||0)+1)},teardown:function(){var e=this.ownerDocument||this.document||this,t=C.documentMode?this:e,n=_.get(t,i)-1;n?_.set(t,i,n):(C.documentMode?this.removeEventListener(i,o):e.removeEventListener(r,o,!0),_.remove(t,i))}}}),ce.each({mouseenter:"mouseover",mouseleave:"mouseout",pointerenter:"pointerover",pointerleave:"pointerout"},function(e,i){ce.event.special[e]={delegateType:i,bindType:i,handle:function(e){var t,n=e.relatedTarget,r=e.handleObj;return n&&(n===this||ce.contains(this,n))||(e.type=r.origType,t=r.handler.apply(this,arguments),e.type=i),t}}}),ce.fn.extend({on:function(e,t,n,r){return Le(this,e,t,n,r)},one:function(e,t,n,r){return Le(this,e,t,n,r,1)},off:function(e,t,n){var r,i;if(e&&e.preventDefault&&e.handleObj)return r=e.handleObj,ce(e.delegateTarget).off(r.namespace?r.origType+"."+r.namespace:r.origType,r.selector,r.handler),this;if("object"==typeof e){for(i in e)this.off(i,t,e[i]);return this}return!1!==t&&"function"!=typeof t||(n=t,t=void 0),!1===n&&(n=qe),this.each(function(){ce.event.remove(this,e,n,t)})}});var Oe=/<script|<style|<link/i,Pe=/checked\s*(?:[^=]|=\s*.checked.)/i,Me=/^\s*<!\[CDATA\[|\]\]>\s*$/g;function Re(e,t){return fe(e,"table")&&fe(11!==t.nodeType?t:t.firstChild,"tr")&&ce(e).children("tbody")[0]||e}function Ie(e){return e.type=(null!==e.getAttribute("type"))+"/"+e.type,e}function We(e){return"true/"===(e.type||"").slice(0,5)?e.type=e.type.slice(5):e.removeAttribute("type"),e}function Fe(e,t){var n,r,i,o,a,s;if(1===t.nodeType){if(_.hasData(e)&&(s=_.get(e).events))for(i in _.remove(t,"handle events"),s)for(n=0,r=s[i].length;n<r;n++)ce.event.add(t,i,s[i][n]);z.hasData(e)&&(o=z.access(e),a=ce.extend({},o),z.set(t,a))}}function $e(n,r,i,o){r=g(r);var e,t,a,s,u,l,c=0,f=n.length,p=f-1,d=r[0],h=v(d);if(h||1<f&&"string"==typeof d&&!le.checkClone&&Pe.test(d))return n.each(function(e){var t=n.eq(e);h&&(r[0]=d.call(this,e,t.html())),$e(t,r,i,o)});if(f&&(t=(e=Ae(r,n[0].ownerDocument,!1,n,o)).firstChild,1===e.childNodes.length&&(e=t),t||o)){for(s=(a=ce.map(Se(e,"script"),Ie)).length;c<f;c++)u=e,c!==p&&(u=ce.clone(u,!0,!0),s&&ce.merge(a,Se(u,"script"))),i.call(n[c],u,c);if(s)for(l=a[a.length-1].ownerDocument,ce.map(a,We),c=0;c<s;c++)u=a[c],Ce.test(u.type||"")&&!_.access(u,"globalEval")&&ce.contains(l,u)&&(u.src&&"module"!==(u.type||"").toLowerCase()?ce._evalUrl&&!u.noModule&&ce._evalUrl(u.src,{nonce:u.nonce||u.getAttribute("nonce")},l):m(u.textContent.replace(Me,""),u,l))}return n}function Be(e,t,n){for(var r,i=t?ce.filter(t,e):e,o=0;null!=(r=i[o]);o++)n||1!==r.nodeType||ce.cleanData(Se(r)),r.parentNode&&(n&&K(r)&&Ee(Se(r,"script")),r.parentNode.removeChild(r));return e}ce.extend({htmlPrefilter:function(e){return e},clone:function(e,t,n){var r,i,o,a,s,u,l,c=e.cloneNode(!0),f=K(e);if(!(le.noCloneChecked||1!==e.nodeType&&11!==e.nodeType||ce.isXMLDoc(e)))for(a=Se(c),r=0,i=(o=Se(e)).length;r<i;r++)s=o[r],u=a[r],void 0,"input"===(l=u.nodeName.toLowerCase())&&we.test(s.type)?u.checked=s.checked:"input"!==l&&"textarea"!==l||(u.defaultValue=s.defaultValue);if(t)if(n)for(o=o||Se(e),a=a||Se(c),r=0,i=o.length;r<i;r++)Fe(o[r],a[r]);else Fe(e,c);return 0<(a=Se(c,"script")).length&&Ee(a,!f&&Se(e,"script")),c},cleanData:function(e){for(var t,n,r,i=ce.event.special,o=0;void 0!==(n=e[o]);o++)if($(n)){if(t=n[_.expando]){if(t.events)for(r in t.events)i[r]?ce.event.remove(n,r):ce.removeEvent(n,r,t.handle);n[_.expando]=void 0}n[z.expando]&&(n[z.expando]=void 0)}}}),ce.fn.extend({detach:function(e){return Be(this,e,!0)},remove:function(e){return Be(this,e)},text:function(e){return M(this,function(e){return void 0===e?ce.text(this):this.empty().each(function(){1!==this.nodeType&&11!==this.nodeType&&9!==this.nodeType||(this.textContent=e)})},null,e,arguments.length)},append:function(){return $e(this,arguments,function(e){1!==this.nodeType&&11!==this.nodeType&&9!==this.nodeType||Re(this,e).appendChild(e)})},prepend:function(){return $e(this,arguments,function(e){if(1===this.nodeType||11===this.nodeType||9===this.nodeType){var t=Re(this,e);t.insertBefore(e,t.firstChild)}})},before:function(){return $e(this,arguments,function(e){this.parentNode&&this.parentNode.insertBefore(e,this)})},after:function(){return $e(this,arguments,function(e){this.parentNode&&this.parentNode.insertBefore(e,this.nextSibling)})},empty:function(){for(var e,t=0;null!=(e=this[t]);t++)1===e.nodeType&&(ce.cleanData(Se(e,!1)),e.textContent="");return this},clone:function(e,t){return e=null!=e&&e,t=null==t?e:t,this.map(function(){return ce.clone(this,e,t)})},html:function(e){return M(this,function(e){var t=this[0]||{},n=0,r=this.length;if(void 0===e&&1===t.nodeType)return t.innerHTML;if("string"==typeof e&&!Oe.test(e)&&!ke[(Te.exec(e)||["",""])[1].toLowerCase()]){e=ce.htmlPrefilter(e);try{for(;n<r;n++)1===(t=this[n]||{}).nodeType&&(ce.cleanData(Se(t,!1)),t.innerHTML=e);t=0}catch(e){}}t&&this.empty().append(e)},null,e,arguments.length)},replaceWith:function(){var n=[];return $e(this,arguments,function(e){var t=this.parentNode;ce.inArray(this,n)<0&&(ce.cleanData(Se(this)),t&&t.replaceChild(e,this))},n)}}),ce.each({appendTo:"append",prependTo:"prepend",insertBefore:"before",insertAfter:"after",replaceAll:"replaceWith"},function(e,a){ce.fn[e]=function(e){for(var t,n=[],r=ce(e),i=r.length-1,o=0;o<=i;o++)t=o===i?this:this.clone(!0),ce(r[o])[a](t),s.apply(n,t.get());return this.pushStack(n)}});var _e=new RegExp("^("+G+")(?!px)[a-z%]+$","i"),ze=/^--/,Xe=function(e){var t=e.ownerDocument.defaultView;return t&&t.opener||(t=ie),t.getComputedStyle(e)},Ue=function(e,t,n){var r,i,o={};for(i in t)o[i]=e.style[i],e.style[i]=t[i];for(i in r=n.call(e),t)e.style[i]=o[i];return r},Ve=new RegExp(Q.join("|"),"i");function Ge(e,t,n){var r,i,o,a,s=ze.test(t),u=e.style;return(n=n||Xe(e))&&(a=n.getPropertyValue(t)||n[t],s&&a&&(a=a.replace(ve,"$1")||void 0),""!==a||K(e)||(a=ce.style(e,t)),!le.pixelBoxStyles()&&_e.test(a)&&Ve.test(t)&&(r=u.width,i=u.minWidth,o=u.maxWidth,u.minWidth=u.maxWidth=u.width=a,a=n.width,u.width=r,u.minWidth=i,u.maxWidth=o)),void 0!==a?a+"":a}function Ye(e,t){return{get:function(){if(!e())return(this.get=t).apply(this,arguments);delete this.get}}}!function(){function e(){if(l){u.style.cssText="position:absolute;left:-11111px;width:60px;margin-top:1px;padding:0;border:0",l.style.cssText="position:relative;display:block;box-sizing:border-box;overflow:scroll;margin:auto;border:1px;padding:1px;width:60%;top:1%",J.appendChild(u).appendChild(l);var e=ie.getComputedStyle(l);n="1%"!==e.top,s=12===t(e.marginLeft),l.style.right="60%",o=36===t(e.right),r=36===t(e.width),l.style.position="absolute",i=12===t(l.offsetWidth/3),J.removeChild(u),l=null}}function t(e){return Math.round(parseFloat(e))}var n,r,i,o,a,s,u=C.createElement("div"),l=C.createElement("div");l.style&&(l.style.backgroundClip="content-box",l.cloneNode(!0).style.backgroundClip="",le.clearCloneStyle="content-box"===l.style.backgroundClip,ce.extend(le,{boxSizingReliable:function(){return e(),r},pixelBoxStyles:function(){return e(),o},pixelPosition:function(){return e(),n},reliableMarginLeft:function(){return e(),s},scrollboxSize:function(){return e(),i},reliableTrDimensions:function(){var e,t,n,r;return null==a&&(e=C.createElement("table"),t=C.createElement("tr"),n=C.createElement("div"),e.style.cssText="position:absolute;left:-11111px;border-collapse:separate",t.style.cssText="box-sizing:content-box;border:1px solid",t.style.height="1px",n.style.height="9px",n.style.display="block",J.appendChild(e).appendChild(t).appendChild(n),r=ie.getComputedStyle(t),a=parseInt(r.height,10)+parseInt(r.borderTopWidth,10)+parseInt(r.borderBottomWidth,10)===t.offsetHeight,J.removeChild(e)),a}}))}();var Qe=["Webkit","Moz","ms"],Je=C.createElement("div").style,Ke={};function Ze(e){var t=ce.cssProps[e]||Ke[e];return t||(e in Je?e:Ke[e]=function(e){var t=e[0].toUpperCase()+e.slice(1),n=Qe.length;while(n--)if((e=Qe[n]+t)in Je)return e}(e)||e)}var et=/^(none|table(?!-c[ea]).+)/,tt={position:"absolute",visibility:"hidden",display:"block"},nt={letterSpacing:"0",fontWeight:"400"};function rt(e,t,n){var r=Y.exec(t);return r?Math.max(0,r[2]-(n||0))+(r[3]||"px"):t}function it(e,t,n,r,i,o){var a="width"===t?1:0,s=0,u=0,l=0;if(n===(r?"border":"content"))return 0;for(;a<4;a+=2)"margin"===n&&(l+=ce.css(e,n+Q[a],!0,i)),r?("content"===n&&(u-=ce.css(e,"padding"+Q[a],!0,i)),"margin"!==n&&(u-=ce.css(e,"border"+Q[a]+"Width",!0,i))):(u+=ce.css(e,"padding"+Q[a],!0,i),"padding"!==n?u+=ce.css(e,"border"+Q[a]+"Width",!0,i):s+=ce.css(e,"border"+Q[a]+"Width",!0,i));return!r&&0<=o&&(u+=Math.max(0,Math.ceil(e["offset"+t[0].toUpperCase()+t.slice(1)]-o-u-s-.5))||0),u+l}function ot(e,t,n){var r=Xe(e),i=(!le.boxSizingReliable()||n)&&"border-box"===ce.css(e,"boxSizing",!1,r),o=i,a=Ge(e,t,r),s="offset"+t[0].toUpperCase()+t.slice(1);if(_e.test(a)){if(!n)return a;a="auto"}return(!le.boxSizingReliable()&&i||!le.reliableTrDimensions()&&fe(e,"tr")||"auto"===a||!parseFloat(a)&&"inline"===ce.css(e,"display",!1,r))&&e.getClientRects().length&&(i="border-box"===ce.css(e,"boxSizing",!1,r),(o=s in e)&&(a=e[s])),(a=parseFloat(a)||0)+it(e,t,n||(i?"border":"content"),o,r,a)+"px"}function at(e,t,n,r,i){return new at.prototype.init(e,t,n,r,i)}ce.extend({cssHooks:{opacity:{get:function(e,t){if(t){var n=Ge(e,"opacity");return""===n?"1":n}}}},cssNumber:{animationIterationCount:!0,aspectRatio:!0,borderImageSlice:!0,columnCount:!0,flexGrow:!0,flexShrink:!0,fontWeight:!0,gridArea:!0,gridColumn:!0,gridColumnEnd:!0,gridColumnStart:!0,gridRow:!0,gridRowEnd:!0,gridRowStart:!0,lineHeight:!0,opacity:!0,order:!0,orphans:!0,scale:!0,widows:!0,zIndex:!0,zoom:!0,fillOpacity:!0,floodOpacity:!0,stopOpacity:!0,strokeMiterlimit:!0,strokeOpacity:!0},cssProps:{},style:function(e,t,n,r){if(e&&3!==e.nodeType&&8!==e.nodeType&&e.style){var i,o,a,s=F(t),u=ze.test(t),l=e.style;if(u||(t=Ze(s)),a=ce.cssHooks[t]||ce.cssHooks[s],void 0===n)return a&&"get"in a&&void 0!==(i=a.get(e,!1,r))?i:l[t];"string"===(o=typeof n)&&(i=Y.exec(n))&&i[1]&&(n=te(e,t,i),o="number"),null!=n&&n==n&&("number"!==o||u||(n+=i&&i[3]||(ce.cssNumber[s]?"":"px")),le.clearCloneStyle||""!==n||0!==t.indexOf("background")||(l[t]="inherit"),a&&"set"in a&&void 0===(n=a.set(e,n,r))||(u?l.setProperty(t,n):l[t]=n))}},css:function(e,t,n,r){var i,o,a,s=F(t);return ze.test(t)||(t=Ze(s)),(a=ce.cssHooks[t]||ce.cssHooks[s])&&"get"in a&&(i=a.get(e,!0,n)),void 0===i&&(i=Ge(e,t,r)),"normal"===i&&t in nt&&(i=nt[t]),""===n||n?(o=parseFloat(i),!0===n||isFinite(o)?o||0:i):i}}),ce.each(["height","width"],function(e,u){ce.cssHooks[u]={get:function(e,t,n){if(t)return!et.test(ce.css(e,"display"))||e.getClientRects().length&&e.getBoundingClientRect().width?ot(e,u,n):Ue(e,tt,function(){return ot(e,u,n)})},set:function(e,t,n){var r,i=Xe(e),o=!le.scrollboxSize()&&"absolute"===i.position,a=(o||n)&&"border-box"===ce.css(e,"boxSizing",!1,i),s=n?it(e,u,n,a,i):0;return a&&o&&(s-=Math.ceil(e["offset"+u[0].toUpperCase()+u.slice(1)]-parseFloat(i[u])-it(e,u,"border",!1,i)-.5)),s&&(r=Y.exec(t))&&"px"!==(r[3]||"px")&&(e.style[u]=t,t=ce.css(e,u)),rt(0,t,s)}}}),ce.cssHooks.marginLeft=Ye(le.reliableMarginLeft,function(e,t){if(t)return(parseFloat(Ge(e,"marginLeft"))||e.getBoundingClientRect().left-Ue(e,{marginLeft:0},function(){return e.getBoundingClientRect().left}))+"px"}),ce.each({margin:"",padding:"",border:"Width"},function(i,o){ce.cssHooks[i+o]={expand:function(e){for(var t=0,n={},r="string"==typeof e?e.split(" "):[e];t<4;t++)n[i+Q[t]+o]=r[t]||r[t-2]||r[0];return n}},"margin"!==i&&(ce.cssHooks[i+o].set=rt)}),ce.fn.extend({css:function(e,t){return M(this,function(e,t,n){var r,i,o={},a=0;if(Array.isArray(t)){for(r=Xe(e),i=t.length;a<i;a++)o[t[a]]=ce.css(e,t[a],!1,r);return o}return void 0!==n?ce.style(e,t,n):ce.css(e,t)},e,t,1<arguments.length)}}),((ce.Tween=at).prototype={constructor:at,init:function(e,t,n,r,i,o){this.elem=e,this.prop=n,this.easing=i||ce.easing._default,this.options=t,this.start=this.now=this.cur(),this.end=r,this.unit=o||(ce.cssNumber[n]?"":"px")},cur:function(){var e=at.propHooks[this.prop];return e&&e.get?e.get(this):at.propHooks._default.get(this)},run:function(e){var t,n=at.propHooks[this.prop];return this.options.duration?this.pos=t=ce.easing[this.easing](e,this.options.duration*e,0,1,this.options.duration):this.pos=t=e,this.now=(this.end-this.start)*t+this.start,this.options.step&&this.options.step.call(this.elem,this.now,this),n&&n.set?n.set(this):at.propHooks._default.set(this),this}}).init.prototype=at.prototype,(at.propHooks={_default:{get:function(e){var t;return 1!==e.elem.nodeType||null!=e.elem[e.prop]&&null==e.elem.style[e.prop]?e.elem[e.prop]:(t=ce.css(e.elem,e.prop,""))&&"auto"!==t?t:0},set:function(e){ce.fx.step[e.prop]?ce.fx.step[e.prop](e):1!==e.elem.nodeType||!ce.cssHooks[e.prop]&&null==e.elem.style[Ze(e.prop)]?e.elem[e.prop]=e.now:ce.style(e.elem,e.prop,e.now+e.unit)}}}).scrollTop=at.propHooks.scrollLeft={set:function(e){e.elem.nodeType&&e.elem.parentNode&&(e.elem[e.prop]=e.now)}},ce.easing={linear:function(e){return e},swing:function(e){return.5-Math.cos(e*Math.PI)/2},_default:"swing"},ce.fx=at.prototype.init,ce.fx.step={};var st,ut,lt,ct,ft=/^(?:toggle|show|hide)$/,pt=/queueHooks$/;function dt(){ut&&(!1===C.hidden&&ie.requestAnimationFrame?ie.requestAnimationFrame(dt):ie.setTimeout(dt,ce.fx.interval),ce.fx.tick())}function ht(){return ie.setTimeout(function(){st=void 0}),st=Date.now()}function gt(e,t){var n,r=0,i={height:e};for(t=t?1:0;r<4;r+=2-t)i["margin"+(n=Q[r])]=i["padding"+n]=e;return t&&(i.opacity=i.width=e),i}function vt(e,t,n){for(var r,i=(yt.tweeners[t]||[]).concat(yt.tweeners["*"]),o=0,a=i.length;o<a;o++)if(r=i[o].call(n,t,e))return r}function yt(o,e,t){var n,a,r=0,i=yt.prefilters.length,s=ce.Deferred().always(function(){delete u.elem}),u=function(){if(a)return!1;for(var e=st||ht(),t=Math.max(0,l.startTime+l.duration-e),n=1-(t/l.duration||0),r=0,i=l.tweens.length;r<i;r++)l.tweens[r].run(n);return s.notifyWith(o,[l,n,t]),n<1&&i?t:(i||s.notifyWith(o,[l,1,0]),s.resolveWith(o,[l]),!1)},l=s.promise({elem:o,props:ce.extend({},e),opts:ce.extend(!0,{specialEasing:{},easing:ce.easing._default},t),originalProperties:e,originalOptions:t,startTime:st||ht(),duration:t.duration,tweens:[],createTween:function(e,t){var n=ce.Tween(o,l.opts,e,t,l.opts.specialEasing[e]||l.opts.easing);return l.tweens.push(n),n},stop:function(e){var t=0,n=e?l.tweens.length:0;if(a)return this;for(a=!0;t<n;t++)l.tweens[t].run(1);return e?(s.notifyWith(o,[l,1,0]),s.resolveWith(o,[l,e])):s.rejectWith(o,[l,e]),this}}),c=l.props;for(!function(e,t){var n,r,i,o,a;for(n in e)if(i=t[r=F(n)],o=e[n],Array.isArray(o)&&(i=o[1],o=e[n]=o[0]),n!==r&&(e[r]=o,delete e[n]),(a=ce.cssHooks[r])&&"expand"in a)for(n in o=a.expand(o),delete e[r],o)n in e||(e[n]=o[n],t[n]=i);else t[r]=i}(c,l.opts.specialEasing);r<i;r++)if(n=yt.prefilters[r].call(l,o,c,l.opts))return v(n.stop)&&(ce._queueHooks(l.elem,l.opts.queue).stop=n.stop.bind(n)),n;return ce.map(c,vt,l),v(l.opts.start)&&l.opts.start.call(o,l),l.progress(l.opts.progress).done(l.opts.done,l.opts.complete).fail(l.opts.fail).always(l.opts.always),ce.fx.timer(ce.extend(u,{elem:o,anim:l,queue:l.opts.queue})),l}ce.Animation=ce.extend(yt,{tweeners:{"*":[function(e,t){var n=this.createTween(e,t);return te(n.elem,e,Y.exec(t),n),n}]},tweener:function(e,t){v(e)?(t=e,e=["*"]):e=e.match(D);for(var n,r=0,i=e.length;r<i;r++)n=e[r],yt.tweeners[n]=yt.tweeners[n]||[],yt.tweeners[n].unshift(t)},prefilters:[function(e,t,n){var r,i,o,a,s,u,l,c,f="width"in t||"height"in t,p=this,d={},h=e.style,g=e.nodeType&&ee(e),v=_.get(e,"fxshow");for(r in n.queue||(null==(a=ce._queueHooks(e,"fx")).unqueued&&(a.unqueued=0,s=a.empty.fire,a.empty.fire=function(){a.unqueued||s()}),a.unqueued++,p.always(function(){p.always(function(){a.unqueued--,ce.queue(e,"fx").length||a.empty.fire()})})),t)if(i=t[r],ft.test(i)){if(delete t[r],o=o||"toggle"===i,i===(g?"hide":"show")){if("show"!==i||!v||void 0===v[r])continue;g=!0}d[r]=v&&v[r]||ce.style(e,r)}if((u=!ce.isEmptyObject(t))||!ce.isEmptyObject(d))for(r in f&&1===e.nodeType&&(n.overflow=[h.overflow,h.overflowX,h.overflowY],null==(l=v&&v.display)&&(l=_.get(e,"display")),"none"===(c=ce.css(e,"display"))&&(l?c=l:(re([e],!0),l=e.style.display||l,c=ce.css(e,"display"),re([e]))),("inline"===c||"inline-block"===c&&null!=l)&&"none"===ce.css(e,"float")&&(u||(p.done(function(){h.display=l}),null==l&&(c=h.display,l="none"===c?"":c)),h.display="inline-block")),n.overflow&&(h.overflow="hidden",p.always(function(){h.overflow=n.overflow[0],h.overflowX=n.overflow[1],h.overflowY=n.overflow[2]})),u=!1,d)u||(v?"hidden"in v&&(g=v.hidden):v=_.access(e,"fxshow",{display:l}),o&&(v.hidden=!g),g&&re([e],!0),p.done(function(){for(r in g||re([e]),_.remove(e,"fxshow"),d)ce.style(e,r,d[r])})),u=vt(g?v[r]:0,r,p),r in v||(v[r]=u.start,g&&(u.end=u.start,u.start=0))}],prefilter:function(e,t){t?yt.prefilters.unshift(e):yt.prefilters.push(e)}}),ce.speed=function(e,t,n){var r=e&&"object"==typeof e?ce.extend({},e):{complete:n||!n&&t||v(e)&&e,duration:e,easing:n&&t||t&&!v(t)&&t};return ce.fx.off?r.duration=0:"number"!=typeof r.duration&&(r.duration in ce.fx.speeds?r.duration=ce.fx.speeds[r.duration]:r.duration=ce.fx.speeds._default),null!=r.queue&&!0!==r.queue||(r.queue="fx"),r.old=r.complete,r.complete=function(){v(r.old)&&r.old.call(this),r.queue&&ce.dequeue(this,r.queue)},r},ce.fn.extend({fadeTo:function(e,t,n,r){return this.filter(ee).css("opacity",0).show().end().animate({opacity:t},e,n,r)},animate:function(t,e,n,r){var i=ce.isEmptyObject(t),o=ce.speed(e,n,r),a=function(){var e=yt(this,ce.extend({},t),o);(i||_.get(this,"finish"))&&e.stop(!0)};return a.finish=a,i||!1===o.queue?this.each(a):this.queue(o.queue,a)},stop:function(i,e,o){var a=function(e){var t=e.stop;delete e.stop,t(o)};return"string"!=typeof i&&(o=e,e=i,i=void 0),e&&this.queue(i||"fx",[]),this.each(function(){var e=!0,t=null!=i&&i+"queueHooks",n=ce.timers,r=_.get(this);if(t)r[t]&&r[t].stop&&a(r[t]);else for(t in r)r[t]&&r[t].stop&&pt.test(t)&&a(r[t]);for(t=n.length;t--;)n[t].elem!==this||null!=i&&n[t].queue!==i||(n[t].anim.stop(o),e=!1,n.splice(t,1));!e&&o||ce.dequeue(this,i)})},finish:function(a){return!1!==a&&(a=a||"fx"),this.each(function(){var e,t=_.get(this),n=t[a+"queue"],r=t[a+"queueHooks"],i=ce.timers,o=n?n.length:0;for(t.finish=!0,ce.queue(this,a,[]),r&&r.stop&&r.stop.call(this,!0),e=i.length;e--;)i[e].elem===this&&i[e].queue===a&&(i[e].anim.stop(!0),i.splice(e,1));for(e=0;e<o;e++)n[e]&&n[e].finish&&n[e].finish.call(this);delete t.finish})}}),ce.each(["toggle","show","hide"],function(e,r){var i=ce.fn[r];ce.fn[r]=function(e,t,n){return null==e||"boolean"==typeof e?i.apply(this,arguments):this.animate(gt(r,!0),e,t,n)}}),ce.each({slideDown:gt("show"),slideUp:gt("hide"),slideToggle:gt("toggle"),fadeIn:{opacity:"show"},fadeOut:{opacity:"hide"},fadeToggle:{opacity:"toggle"}},function(e,r){ce.fn[e]=function(e,t,n){return this.animate(r,e,t,n)}}),ce.timers=[],ce.fx.tick=function(){var e,t=0,n=ce.timers;for(st=Date.now();t<n.length;t++)(e=n[t])()||n[t]!==e||n.splice(t--,1);n.length||ce.fx.stop(),st=void 0},ce.fx.timer=function(e){ce.timers.push(e),ce.fx.start()},ce.fx.interval=13,ce.fx.start=function(){ut||(ut=!0,dt())},ce.fx.stop=function(){ut=null},ce.fx.speeds={slow:600,fast:200,_default:400},ce.fn.delay=function(r,e){return r=ce.fx&&ce.fx.speeds[r]||r,e=e||"fx",this.queue(e,function(e,t){var n=ie.setTimeout(e,r);t.stop=function(){ie.clearTimeout(n)}})},lt=C.createElement("input"),ct=C.createElement("select").appendChild(C.createElement("option")),lt.type="checkbox",le.checkOn=""!==lt.value,le.optSelected=ct.selected,(lt=C.createElement("input")).value="t",lt.type="radio",le.radioValue="t"===lt.value;var mt,xt=ce.expr.attrHandle;ce.fn.extend({attr:function(e,t){return M(this,ce.attr,e,t,1<arguments.length)},removeAttr:function(e){return this.each(function(){ce.removeAttr(this,e)})}}),ce.extend({attr:function(e,t,n){var r,i,o=e.nodeType;if(3!==o&&8!==o&&2!==o)return"undefined"==typeof e.getAttribute?ce.prop(e,t,n):(1===o&&ce.isXMLDoc(e)||(i=ce.attrHooks[t.toLowerCase()]||(ce.expr.match.bool.test(t)?mt:void 0)),void 0!==n?null===n?void ce.removeAttr(e,t):i&&"set"in i&&void 0!==(r=i.set(e,n,t))?r:(e.setAttribute(t,n+""),n):i&&"get"in i&&null!==(r=i.get(e,t))?r:null==(r=ce.find.attr(e,t))?void 0:r)},attrHooks:{type:{set:function(e,t){if(!le.radioValue&&"radio"===t&&fe(e,"input")){var n=e.value;return e.setAttribute("type",t),n&&(e.value=n),t}}}},removeAttr:function(e,t){var n,r=0,i=t&&t.match(D);if(i&&1===e.nodeType)while(n=i[r++])e.removeAttribute(n)}}),mt={set:function(e,t,n){return!1===t?ce.removeAttr(e,n):e.setAttribute(n,n),n}},ce.each(ce.expr.match.bool.source.match(/\w+/g),function(e,t){var a=xt[t]||ce.find.attr;xt[t]=function(e,t,n){var r,i,o=t.toLowerCase();return n||(i=xt[o],xt[o]=r,r=null!=a(e,t,n)?o:null,xt[o]=i),r}});var bt=/^(?:input|select|textarea|button)$/i,wt=/^(?:a|area)$/i;function Tt(e){return(e.match(D)||[]).join(" ")}function Ct(e){return e.getAttribute&&e.getAttribute("class")||""}function kt(e){return Array.isArray(e)?e:"string"==typeof e&&e.match(D)||[]}ce.fn.extend({prop:function(e,t){return M(this,ce.prop,e,t,1<arguments.length)},removeProp:function(e){return this.each(function(){delete this[ce.propFix[e]||e]})}}),ce.extend({prop:function(e,t,n){var r,i,o=e.nodeType;if(3!==o&&8!==o&&2!==o)return 1===o&&ce.isXMLDoc(e)||(t=ce.propFix[t]||t,i=ce.propHooks[t]),void 0!==n?i&&"set"in i&&void 0!==(r=i.set(e,n,t))?r:e[t]=n:i&&"get"in i&&null!==(r=i.get(e,t))?r:e[t]},propHooks:{tabIndex:{get:function(e){var t=ce.find.attr(e,"tabindex");return t?parseInt(t,10):bt.test(e.nodeName)||wt.test(e.nodeName)&&e.href?0:-1}}},propFix:{"for":"htmlFor","class":"className"}}),le.optSelected||(ce.propHooks.selected={get:function(e){var t=e.parentNode;return t&&t.parentNode&&t.parentNode.selectedIndex,null},set:function(e){var t=e.parentNode;t&&(t.selectedIndex,t.parentNode&&t.parentNode.selectedIndex)}}),ce.each(["tabIndex","readOnly","maxLength","cellSpacing","cellPadding","rowSpan","colSpan","useMap","frameBorder","contentEditable"],function(){ce.propFix[this.toLowerCase()]=this}),ce.fn.extend({addClass:function(t){var e,n,r,i,o,a;return v(t)?this.each(function(e){ce(this).addClass(t.call(this,e,Ct(this)))}):(e=kt(t)).length?this.each(function(){if(r=Ct(this),n=1===this.nodeType&&" "+Tt(r)+" "){for(o=0;o<e.length;o++)i=e[o],n.indexOf(" "+i+" ")<0&&(n+=i+" ");a=Tt(n),r!==a&&this.setAttribute("class",a)}}):this},removeClass:function(t){var e,n,r,i,o,a;return v(t)?this.each(function(e){ce(this).removeClass(t.call(this,e,Ct(this)))}):arguments.length?(e=kt(t)).length?this.each(function(){if(r=Ct(this),n=1===this.nodeType&&" "+Tt(r)+" "){for(o=0;o<e.length;o++){i=e[o];while(-1<n.indexOf(" "+i+" "))n=n.replace(" "+i+" "," ")}a=Tt(n),r!==a&&this.setAttribute("class",a)}}):this:this.attr("class","")},toggleClass:function(t,n){var e,r,i,o,a=typeof t,s="string"===a||Array.isArray(t);return v(t)?this.each(function(e){ce(this).toggleClass(t.call(this,e,Ct(this),n),n)}):"boolean"==typeof n&&s?n?this.addClass(t):this.removeClass(t):(e=kt(t),this.each(function(){if(s)for(o=ce(this),i=0;i<e.length;i++)r=e[i],o.hasClass(r)?o.removeClass(r):o.addClass(r);else void 0!==t&&"boolean"!==a||((r=Ct(this))&&_.set(this,"__className__",r),this.setAttribute&&this.setAttribute("class",r||!1===t?"":_.get(this,"__className__")||""))}))},hasClass:function(e){var t,n,r=0;t=" "+e+" ";while(n=this[r++])if(1===n.nodeType&&-1<(" "+Tt(Ct(n))+" ").indexOf(t))return!0;return!1}});var St=/\r/g;ce.fn.extend({val:function(n){var r,e,i,t=this[0];return arguments.length?(i=v(n),this.each(function(e){var t;1===this.nodeType&&(null==(t=i?n.call(this,e,ce(this).val()):n)?t="":"number"==typeof t?t+="":Array.isArray(t)&&(t=ce.map(t,function(e){return null==e?"":e+""})),(r=ce.valHooks[this.type]||ce.valHooks[this.nodeName.toLowerCase()])&&"set"in r&&void 0!==r.set(this,t,"value")||(this.value=t))})):t?(r=ce.valHooks[t.type]||ce.valHooks[t.nodeName.toLowerCase()])&&"get"in r&&void 0!==(e=r.get(t,"value"))?e:"string"==typeof(e=t.value)?e.replace(St,""):null==e?"":e:void 0}}),ce.extend({valHooks:{option:{get:function(e){var t=ce.find.attr(e,"value");return null!=t?t:Tt(ce.text(e))}},select:{get:function(e){var t,n,r,i=e.options,o=e.selectedIndex,a="select-one"===e.type,s=a?null:[],u=a?o+1:i.length;for(r=o<0?u:a?o:0;r<u;r++)if(((n=i[r]).selected||r===o)&&!n.disabled&&(!n.parentNode.disabled||!fe(n.parentNode,"optgroup"))){if(t=ce(n).val(),a)return t;s.push(t)}return s},set:function(e,t){var n,r,i=e.options,o=ce.makeArray(t),a=i.length;while(a--)((r=i[a]).selected=-1<ce.inArray(ce.valHooks.option.get(r),o))&&(n=!0);return n||(e.selectedIndex=-1),o}}}}),ce.each(["radio","checkbox"],function(){ce.valHooks[this]={set:function(e,t){if(Array.isArray(t))return e.checked=-1<ce.inArray(ce(e).val(),t)}},le.checkOn||(ce.valHooks[this].get=function(e){return null===e.getAttribute("value")?"on":e.value})});var Et=ie.location,jt={guid:Date.now()},At=/\?/;ce.parseXML=function(e){var t,n;if(!e||"string"!=typeof e)return null;try{t=(new ie.DOMParser).parseFromString(e,"text/xml")}catch(e){}return n=t&&t.getElementsByTagName("parsererror")[0],t&&!n||ce.error("Invalid XML: "+(n?ce.map(n.childNodes,function(e){return e.textContent}).join("\n"):e)),t};var Dt=/^(?:focusinfocus|focusoutblur)$/,Nt=function(e){e.stopPropagation()};ce.extend(ce.event,{trigger:function(e,t,n,r){var i,o,a,s,u,l,c,f,p=[n||C],d=ue.call(e,"type")?e.type:e,h=ue.call(e,"namespace")?e.namespace.split("."):[];if(o=f=a=n=n||C,3!==n.nodeType&&8!==n.nodeType&&!Dt.test(d+ce.event.triggered)&&(-1<d.indexOf(".")&&(d=(h=d.split(".")).shift(),h.sort()),u=d.indexOf(":")<0&&"on"+d,(e=e[ce.expando]?e:new ce.Event(d,"object"==typeof e&&e)).isTrigger=r?2:3,e.namespace=h.join("."),e.rnamespace=e.namespace?new RegExp("(^|\\.)"+h.join("\\.(?:.*\\.|)")+"(\\.|$)"):null,e.result=void 0,e.target||(e.target=n),t=null==t?[e]:ce.makeArray(t,[e]),c=ce.event.special[d]||{},r||!c.trigger||!1!==c.trigger.apply(n,t))){if(!r&&!c.noBubble&&!y(n)){for(s=c.delegateType||d,Dt.test(s+d)||(o=o.parentNode);o;o=o.parentNode)p.push(o),a=o;a===(n.ownerDocument||C)&&p.push(a.defaultView||a.parentWindow||ie)}i=0;while((o=p[i++])&&!e.isPropagationStopped())f=o,e.type=1<i?s:c.bindType||d,(l=(_.get(o,"events")||Object.create(null))[e.type]&&_.get(o,"handle"))&&l.apply(o,t),(l=u&&o[u])&&l.apply&&$(o)&&(e.result=l.apply(o,t),!1===e.result&&e.preventDefault());return e.type=d,r||e.isDefaultPrevented()||c._default&&!1!==c._default.apply(p.pop(),t)||!$(n)||u&&v(n[d])&&!y(n)&&((a=n[u])&&(n[u]=null),ce.event.triggered=d,e.isPropagationStopped()&&f.addEventListener(d,Nt),n[d](),e.isPropagationStopped()&&f.removeEventListener(d,Nt),ce.event.triggered=void 0,a&&(n[u]=a)),e.result}},simulate:function(e,t,n){var r=ce.extend(new ce.Event,n,{type:e,isSimulated:!0});ce.event.trigger(r,null,t)}}),ce.fn.extend({trigger:function(e,t){return this.each(function(){ce.event.trigger(e,t,this)})},triggerHandler:function(e,t){var n=this[0];if(n)return ce.event.trigger(e,t,n,!0)}});var qt=/\[\]$/,Lt=/\r?\n/g,Ht=/^(?:submit|button|image|reset|file)$/i,Ot=/^(?:input|select|textarea|keygen)/i;function Pt(n,e,r,i){var t;if(Array.isArray(e))ce.each(e,function(e,t){r||qt.test(n)?i(n,t):Pt(n+"["+("object"==typeof t&&null!=t?e:"")+"]",t,r,i)});else if(r||"object"!==x(e))i(n,e);else for(t in e)Pt(n+"["+t+"]",e[t],r,i)}ce.param=function(e,t){var n,r=[],i=function(e,t){var n=v(t)?t():t;r[r.length]=encodeURIComponent(e)+"="+encodeURIComponent(null==n?"":n)};if(null==e)return"";if(Array.isArray(e)||e.jquery&&!ce.isPlainObject(e))ce.each(e,function(){i(this.name,this.value)});else for(n in e)Pt(n,e[n],t,i);return r.join("&")},ce.fn.extend({serialize:function(){return ce.param(this.serializeArray())},serializeArray:function(){return this.map(function(){var e=ce.prop(this,"elements");return e?ce.makeArray(e):this}).filter(function(){var e=this.type;return this.name&&!ce(this).is(":disabled")&&Ot.test(this.nodeName)&&!Ht.test(e)&&(this.checked||!we.test(e))}).map(function(e,t){var n=ce(this).val();return null==n?null:Array.isArray(n)?ce.map(n,function(e){return{name:t.name,value:e.replace(Lt,"\r\n")}}):{name:t.name,value:n.replace(Lt,"\r\n")}}).get()}});var Mt=/%20/g,Rt=/#.*$/,It=/([?&])_=[^&]*/,Wt=/^(.*?):[ \t]*([^\r\n]*)$/gm,Ft=/^(?:GET|HEAD)$/,$t=/^\/\//,Bt={},_t={},zt="*/".concat("*"),Xt=C.createElement("a");function Ut(o){return function(e,t){"string"!=typeof e&&(t=e,e="*");var n,r=0,i=e.toLowerCase().match(D)||[];if(v(t))while(n=i[r++])"+"===n[0]?(n=n.slice(1)||"*",(o[n]=o[n]||[]).unshift(t)):(o[n]=o[n]||[]).push(t)}}function Vt(t,i,o,a){var s={},u=t===_t;function l(e){var r;return s[e]=!0,ce.each(t[e]||[],function(e,t){var n=t(i,o,a);return"string"!=typeof n||u||s[n]?u?!(r=n):void 0:(i.dataTypes.unshift(n),l(n),!1)}),r}return l(i.dataTypes[0])||!s["*"]&&l("*")}function Gt(e,t){var n,r,i=ce.ajaxSettings.flatOptions||{};for(n in t)void 0!==t[n]&&((i[n]?e:r||(r={}))[n]=t[n]);return r&&ce.extend(!0,e,r),e}Xt.href=Et.href,ce.extend({active:0,lastModified:{},etag:{},ajaxSettings:{url:Et.href,type:"GET",isLocal:/^(?:about|app|app-storage|.+-extension|file|res|widget):$/.test(Et.protocol),global:!0,processData:!0,async:!0,contentType:"application/x-www-form-urlencoded; charset=UTF-8",accepts:{"*":zt,text:"text/plain",html:"text/html",xml:"application/xml, text/xml",json:"application/json, text/javascript"},contents:{xml:/\bxml\b/,html:/\bhtml/,json:/\bjson\b/},responseFields:{xml:"responseXML",text:"responseText",json:"responseJSON"},converters:{"* text":String,"text html":!0,"text json":JSON.parse,"text xml":ce.parseXML},flatOptions:{url:!0,context:!0}},ajaxSetup:function(e,t){return t?Gt(Gt(e,ce.ajaxSettings),t):Gt(ce.ajaxSettings,e)},ajaxPrefilter:Ut(Bt),ajaxTransport:Ut(_t),ajax:function(e,t){"object"==typeof e&&(t=e,e=void 0),t=t||{};var c,f,p,n,d,r,h,g,i,o,v=ce.ajaxSetup({},t),y=v.context||v,m=v.context&&(y.nodeType||y.jquery)?ce(y):ce.event,x=ce.Deferred(),b=ce.Callbacks("once memory"),w=v.statusCode||{},a={},s={},u="canceled",T={readyState:0,getResponseHeader:function(e){var t;if(h){if(!n){n={};while(t=Wt.exec(p))n[t[1].toLowerCase()+" "]=(n[t[1].toLowerCase()+" "]||[]).concat(t[2])}t=n[e.toLowerCase()+" "]}return null==t?null:t.join(", ")},getAllResponseHeaders:function(){return h?p:null},setRequestHeader:function(e,t){return null==h&&(e=s[e.toLowerCase()]=s[e.toLowerCase()]||e,a[e]=t),this},overrideMimeType:function(e){return null==h&&(v.mimeType=e),this},statusCode:function(e){var t;if(e)if(h)T.always(e[T.status]);else for(t in e)w[t]=[w[t],e[t]];return this},abort:function(e){var t=e||u;return c&&c.abort(t),l(0,t),this}};if(x.promise(T),v.url=((e||v.url||Et.href)+"").replace($t,Et.protocol+"//"),v.type=t.method||t.type||v.method||v.type,v.dataTypes=(v.dataType||"*").toLowerCase().match(D)||[""],null==v.crossDomain){r=C.createElement("a");try{r.href=v.url,r.href=r.href,v.crossDomain=Xt.protocol+"//"+Xt.host!=r.protocol+"//"+r.host}catch(e){v.crossDomain=!0}}if(v.data&&v.processData&&"string"!=typeof v.data&&(v.data=ce.param(v.data,v.traditional)),Vt(Bt,v,t,T),h)return T;for(i in(g=ce.event&&v.global)&&0==ce.active++&&ce.event.trigger("ajaxStart"),v.type=v.type.toUpperCase(),v.hasContent=!Ft.test(v.type),f=v.url.replace(Rt,""),v.hasContent?v.data&&v.processData&&0===(v.contentType||"").indexOf("application/x-www-form-urlencoded")&&(v.data=v.data.replace(Mt,"+")):(o=v.url.slice(f.length),v.data&&(v.processData||"string"==typeof v.data)&&(f+=(At.test(f)?"&":"?")+v.data,delete v.data),!1===v.cache&&(f=f.replace(It,"$1"),o=(At.test(f)?"&":"?")+"_="+jt.guid+++o),v.url=f+o),v.ifModified&&(ce.lastModified[f]&&T.setRequestHeader("If-Modified-Since",ce.lastModified[f]),ce.etag[f]&&T.setRequestHeader("If-None-Match",ce.etag[f])),(v.data&&v.hasContent&&!1!==v.contentType||t.contentType)&&T.setRequestHeader("Content-Type",v.contentType),T.setRequestHeader("Accept",v.dataTypes[0]&&v.accepts[v.dataTypes[0]]?v.accepts[v.dataTypes[0]]+("*"!==v.dataTypes[0]?", "+zt+"; q=0.01":""):v.accepts["*"]),v.headers)T.setRequestHeader(i,v.headers[i]);if(v.beforeSend&&(!1===v.beforeSend.call(y,T,v)||h))return T.abort();if(u="abort",b.add(v.complete),T.done(v.success),T.fail(v.error),c=Vt(_t,v,t,T)){if(T.readyState=1,g&&m.trigger("ajaxSend",[T,v]),h)return T;v.async&&0<v.timeout&&(d=ie.setTimeout(function(){T.abort("timeout")},v.timeout));try{h=!1,c.send(a,l)}catch(e){if(h)throw e;l(-1,e)}}else l(-1,"No Transport");function l(e,t,n,r){var i,o,a,s,u,l=t;h||(h=!0,d&&ie.clearTimeout(d),c=void 0,p=r||"",T.readyState=0<e?4:0,i=200<=e&&e<300||304===e,n&&(s=function(e,t,n){var r,i,o,a,s=e.contents,u=e.dataTypes;while("*"===u[0])u.shift(),void 0===r&&(r=e.mimeType||t.getResponseHeader("Content-Type"));if(r)for(i in s)if(s[i]&&s[i].test(r)){u.unshift(i);break}if(u[0]in n)o=u[0];else{for(i in n){if(!u[0]||e.converters[i+" "+u[0]]){o=i;break}a||(a=i)}o=o||a}if(o)return o!==u[0]&&u.unshift(o),n[o]}(v,T,n)),!i&&-1<ce.inArray("script",v.dataTypes)&&ce.inArray("json",v.dataTypes)<0&&(v.converters["text script"]=function(){}),s=function(e,t,n,r){var i,o,a,s,u,l={},c=e.dataTypes.slice();if(c[1])for(a in e.converters)l[a.toLowerCase()]=e.converters[a];o=c.shift();while(o)if(e.responseFields[o]&&(n[e.responseFields[o]]=t),!u&&r&&e.dataFilter&&(t=e.dataFilter(t,e.dataType)),u=o,o=c.shift())if("*"===o)o=u;else if("*"!==u&&u!==o){if(!(a=l[u+" "+o]||l["* "+o]))for(i in l)if((s=i.split(" "))[1]===o&&(a=l[u+" "+s[0]]||l["* "+s[0]])){!0===a?a=l[i]:!0!==l[i]&&(o=s[0],c.unshift(s[1]));break}if(!0!==a)if(a&&e["throws"])t=a(t);else try{t=a(t)}catch(e){return{state:"parsererror",error:a?e:"No conversion from "+u+" to "+o}}}return{state:"success",data:t}}(v,s,T,i),i?(v.ifModified&&((u=T.getResponseHeader("Last-Modified"))&&(ce.lastModified[f]=u),(u=T.getResponseHeader("etag"))&&(ce.etag[f]=u)),204===e||"HEAD"===v.type?l="nocontent":304===e?l="notmodified":(l=s.state,o=s.data,i=!(a=s.error))):(a=l,!e&&l||(l="error",e<0&&(e=0))),T.status=e,T.statusText=(t||l)+"",i?x.resolveWith(y,[o,l,T]):x.rejectWith(y,[T,l,a]),T.statusCode(w),w=void 0,g&&m.trigger(i?"ajaxSuccess":"ajaxError",[T,v,i?o:a]),b.fireWith(y,[T,l]),g&&(m.trigger("ajaxComplete",[T,v]),--ce.active||ce.event.trigger("ajaxStop")))}return T},getJSON:function(e,t,n){return ce.get(e,t,n,"json")},getScript:function(e,t){return ce.get(e,void 0,t,"script")}}),ce.each(["get","post"],function(e,i){ce[i]=function(e,t,n,r){return v(t)&&(r=r||n,n=t,t=void 0),ce.ajax(ce.extend({url:e,type:i,dataType:r,data:t,success:n},ce.isPlainObject(e)&&e))}}),ce.ajaxPrefilter(function(e){var t;for(t in e.headers)"content-type"===t.toLowerCase()&&(e.contentType=e.headers[t]||"")}),ce._evalUrl=function(e,t,n){return ce.ajax({url:e,type:"GET",dataType:"script",cache:!0,async:!1,global:!1,converters:{"text script":function(){}},dataFilter:function(e){ce.globalEval(e,t,n)}})},ce.fn.extend({wrapAll:function(e){var t;return this[0]&&(v(e)&&(e=e.call(this[0])),t=ce(e,this[0].ownerDocument).eq(0).clone(!0),this[0].parentNode&&t.insertBefore(this[0]),t.map(function(){var e=this;while(e.firstElementChild)e=e.firstElementChild;return e}).append(this)),this},wrapInner:function(n){return v(n)?this.each(function(e){ce(this).wrapInner(n.call(this,e))}):this.each(function(){var e=ce(this),t=e.contents();t.length?t.wrapAll(n):e.append(n)})},wrap:function(t){var n=v(t);return this.each(function(e){ce(this).wrapAll(n?t.call(this,e):t)})},unwrap:function(e){return this.parent(e).not("body").each(function(){ce(this).replaceWith(this.childNodes)}),this}}),ce.expr.pseudos.hidden=function(e){return!ce.expr.pseudos.visible(e)},ce.expr.pseudos.visible=function(e){return!!(e.offsetWidth||e.offsetHeight||e.getClientRects().length)},ce.ajaxSettings.xhr=function(){try{return new ie.XMLHttpRequest}catch(e){}};var Yt={0:200,1223:204},Qt=ce.ajaxSettings.xhr();le.cors=!!Qt&&"withCredentials"in Qt,le.ajax=Qt=!!Qt,ce.ajaxTransport(function(i){var o,a;if(le.cors||Qt&&!i.crossDomain)return{send:function(e,t){var n,r=i.xhr();if(r.open(i.type,i.url,i.async,i.username,i.password),i.xhrFields)for(n in i.xhrFields)r[n]=i.xhrFields[n];for(n in i.mimeType&&r.overrideMimeType&&r.overrideMimeType(i.mimeType),i.crossDomain||e["X-Requested-With"]||(e["X-Requested-With"]="XMLHttpRequest"),e)r.setRequestHeader(n,e[n]);o=function(e){return function(){o&&(o=a=r.onload=r.onerror=r.onabort=r.ontimeout=r.onreadystatechange=null,"abort"===e?r.abort():"error"===e?"number"!=typeof r.status?t(0,"error"):t(r.status,r.statusText):t(Yt[r.status]||r.status,r.statusText,"text"!==(r.responseType||"text")||"string"!=typeof r.responseText?{binary:r.response}:{text:r.responseText},r.getAllResponseHeaders()))}},r.onload=o(),a=r.onerror=r.ontimeout=o("error"),void 0!==r.onabort?r.onabort=a:r.onreadystatechange=function(){4===r.readyState&&ie.setTimeout(function(){o&&a()})},o=o("abort");try{r.send(i.hasContent&&i.data||null)}catch(e){if(o)throw e}},abort:function(){o&&o()}}}),ce.ajaxPrefilter(function(e){e.crossDomain&&(e.contents.script=!1)}),ce.ajaxSetup({accepts:{script:"text/javascript, application/javascript, application/ecmascript, application/x-ecmascript"},contents:{script:/\b(?:java|ecma)script\b/},converters:{"text script":function(e){return ce.globalEval(e),e}}}),ce.ajaxPrefilter("script",function(e){void 0===e.cache&&(e.cache=!1),e.crossDomain&&(e.type="GET")}),ce.ajaxTransport("script",function(n){var r,i;if(n.crossDomain||n.scriptAttrs)return{send:function(e,t){r=ce("<script>").attr(n.scriptAttrs||{}).prop({charset:n.scriptCharset,src:n.url}).on("load error",i=function(e){r.remove(),i=null,e&&t("error"===e.type?404:200,e.type)}),C.head.appendChild(r[0])},abort:function(){i&&i()}}});var Jt,Kt=[],Zt=/(=)\?(?=&|$)|\?\?/;ce.ajaxSetup({jsonp:"callback",jsonpCallback:function(){var e=Kt.pop()||ce.expando+"_"+jt.guid++;return this[e]=!0,e}}),ce.ajaxPrefilter("json jsonp",function(e,t,n){var r,i,o,a=!1!==e.jsonp&&(Zt.test(e.url)?"url":"string"==typeof e.data&&0===(e.contentType||"").indexOf("application/x-www-form-urlencoded")&&Zt.test(e.data)&&"data");if(a||"jsonp"===e.dataTypes[0])return r=e.jsonpCallback=v(e.jsonpCallback)?e.jsonpCallback():e.jsonpCallback,a?e[a]=e[a].replace(Zt,"$1"+r):!1!==e.jsonp&&(e.url+=(At.test(e.url)?"&":"?")+e.jsonp+"="+r),e.converters["script json"]=function(){return o||ce.error(r+" was not called"),o[0]},e.dataTypes[0]="json",i=ie[r],ie[r]=function(){o=arguments},n.always(function(){void 0===i?ce(ie).removeProp(r):ie[r]=i,e[r]&&(e.jsonpCallback=t.jsonpCallback,Kt.push(r)),o&&v(i)&&i(o[0]),o=i=void 0}),"script"}),le.createHTMLDocument=((Jt=C.implementation.createHTMLDocument("").body).innerHTML="<form></form><form></form>",2===Jt.childNodes.length),ce.parseHTML=function(e,t,n){return"string"!=typeof e?[]:("boolean"==typeof t&&(n=t,t=!1),t||(le.createHTMLDocument?((r=(t=C.implementation.createHTMLDocument("")).createElement("base")).href=C.location.href,t.head.appendChild(r)):t=C),o=!n&&[],(i=w.exec(e))?[t.createElement(i[1])]:(i=Ae([e],t,o),o&&o.length&&ce(o).remove(),ce.merge([],i.childNodes)));var r,i,o},ce.fn.load=function(e,t,n){var r,i,o,a=this,s=e.indexOf(" ");return-1<s&&(r=Tt(e.slice(s)),e=e.slice(0,s)),v(t)?(n=t,t=void 0):t&&"object"==typeof t&&(i="POST"),0<a.length&&ce.ajax({url:e,type:i||"GET",dataType:"html",data:t}).done(function(e){o=arguments,a.html(r?ce("<div>").append(ce.parseHTML(e)).find(r):e)}).always(n&&function(e,t){a.each(function(){n.apply(this,o||[e.responseText,t,e])})}),this},ce.expr.pseudos.animated=function(t){return ce.grep(ce.timers,function(e){return t===e.elem}).length},ce.offset={setOffset:function(e,t,n){var r,i,o,a,s,u,l=ce.css(e,"position"),c=ce(e),f={};"static"===l&&(e.style.position="relative"),s=c.offset(),o=ce.css(e,"top"),u=ce.css(e,"left"),("absolute"===l||"fixed"===l)&&-1<(o+u).indexOf("auto")?(a=(r=c.position()).top,i=r.left):(a=parseFloat(o)||0,i=parseFloat(u)||0),v(t)&&(t=t.call(e,n,ce.extend({},s))),null!=t.top&&(f.top=t.top-s.top+a),null!=t.left&&(f.left=t.left-s.left+i),"using"in t?t.using.call(e,f):c.css(f)}},ce.fn.extend({offset:function(t){if(arguments.length)return void 0===t?this:this.each(function(e){ce.offset.setOffset(this,t,e)});var e,n,r=this[0];return r?r.getClientRects().length?(e=r.getBoundingClientRect(),n=r.ownerDocument.defaultView,{top:e.top+n.pageYOffset,left:e.left+n.pageXOffset}):{top:0,left:0}:void 0},position:function(){if(this[0]){var e,t,n,r=this[0],i={top:0,left:0};if("fixed"===ce.css(r,"position"))t=r.getBoundingClientRect();else{t=this.offset(),n=r.ownerDocument,e=r.offsetParent||n.documentElement;while(e&&(e===n.body||e===n.documentElement)&&"static"===ce.css(e,"position"))e=e.parentNode;e&&e!==r&&1===e.nodeType&&((i=ce(e).offset()).top+=ce.css(e,"borderTopWidth",!0),i.left+=ce.css(e,"borderLeftWidth",!0))}return{top:t.top-i.top-ce.css(r,"marginTop",!0),left:t.left-i.left-ce.css(r,"marginLeft",!0)}}},offsetParent:function(){return this.map(function(){var e=this.offsetParent;while(e&&"static"===ce.css(e,"position"))e=e.offsetParent;return e||J})}}),ce.each({scrollLeft:"pageXOffset",scrollTop:"pageYOffset"},function(t,i){var o="pageYOffset"===i;ce.fn[t]=function(e){return M(this,function(e,t,n){var r;if(y(e)?r=e:9===e.nodeType&&(r=e.defaultView),void 0===n)return r?r[i]:e[t];r?r.scrollTo(o?r.pageXOffset:n,o?n:r.pageYOffset):e[t]=n},t,e,arguments.length)}}),ce.each(["top","left"],function(e,n){ce.cssHooks[n]=Ye(le.pixelPosition,function(e,t){if(t)return t=Ge(e,n),_e.test(t)?ce(e).position()[n]+"px":t})}),ce.each({Height:"height",Width:"width"},function(a,s){ce.each({padding:"inner"+a,content:s,"":"outer"+a},function(r,o){ce.fn[o]=function(e,t){var n=arguments.length&&(r||"boolean"!=typeof e),i=r||(!0===e||!0===t?"margin":"border");return M(this,function(e,t,n){var r;return y(e)?0===o.indexOf("outer")?e["inner"+a]:e.document.documentElement["client"+a]:9===e.nodeType?(r=e.documentElement,Math.max(e.body["scroll"+a],r["scroll"+a],e.body["offset"+a],r["offset"+a],r["client"+a])):void 0===n?ce.css(e,t,i):ce.style(e,t,n,i)},s,n?e:void 0,n)}})}),ce.each(["ajaxStart","ajaxStop","ajaxComplete","ajaxError","ajaxSuccess","ajaxSend"],function(e,t){ce.fn[t]=function(e){return this.on(t,e)}}),ce.fn.extend({bind:function(e,t,n){return this.on(e,null,t,n)},unbind:function(e,t){return this.off(e,null,t)},delegate:function(e,t,n,r){return this.on(t,e,n,r)},undelegate:function(e,t,n){return 1===arguments.length?this.off(e,"**"):this.off(t,e||"**",n)},hover:function(e,t){return this.on("mouseenter",e).on("mouseleave",t||e)}}),ce.each("blur focus focusin focusout resize scroll click dblclick mousedown mouseup mousemove mouseover mouseout mouseenter mouseleave change select submit keydown keypress keyup contextmenu".split(" "),function(e,n){ce.fn[n]=function(e,t){return 0<arguments.length?this.on(n,null,e,t):this.trigger(n)}});var en=/^[\s\uFEFF\xA0]+|([^\s\uFEFF\xA0])[\s\uFEFF\xA0]+$/g;ce.proxy=function(e,t){var n,r,i;if("string"==typeof t&&(n=e[t],t=e,e=n),v(e))return r=ae.call(arguments,2),(i=function(){return e.apply(t||this,r.concat(ae.call(arguments)))}).guid=e.guid=e.guid||ce.guid++,i},ce.holdReady=function(e){e?ce.readyWait++:ce.ready(!0)},ce.isArray=Array.isArray,ce.parseJSON=JSON.parse,ce.nodeName=fe,ce.isFunction=v,ce.isWindow=y,ce.camelCase=F,ce.type=x,ce.now=Date.now,ce.isNumeric=function(e){var t=ce.type(e);return("number"===t||"string"===t)&&!isNaN(e-parseFloat(e))},ce.trim=function(e){return null==e?"":(e+"").replace(en,"$1")},"function"==typeof define&&define.amd&&define("jquery",[],function(){return ce});var tn=ie.jQuery,nn=ie.$;return ce.noConflict=function(e){return ie.$===ce&&(ie.$=nn),e&&ie.jQuery===ce&&(ie.jQuery=tn),ce},"undefined"==typeof e&&(ie.jQuery=ie.$=ce),ce});
		</script>
		<script>
			//src="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/js/bootstrap.bundle.min.js" integrity="sha384-ka7Sk0Gln4gmtz2MlQnikT1wXgYsOg+OMhuP+IlRH9sENBO0LRn5q+8nbTov4+1p" crossorigin="anonymous"
			/*!
				* Bootstrap v5.1.3 (https://getbootstrap.com/)
				* Copyright 2011-2021 The Bootstrap Authors (https://github.com/twbs/bootstrap/graphs/contributors)
				* Licensed under MIT (https://github.com/twbs/bootstrap/blob/main/LICENSE)
			*/
			!function(t,e){"object"==typeof exports&&"undefined"!=typeof module?module.exports=e(require("@popperjs/core")):"function"==typeof define&&define.amd?define(["@popperjs/core"],e):(t="undefined"!=typeof globalThis?globalThis:t||self).bootstrap=e(t.Popper)}(this,(function(t){"use strict";function e(t){if(t&&t.__esModule)return t;const e=Object.create(null);if(t)for(const i in t)if("default"!==i){const s=Object.getOwnPropertyDescriptor(t,i);Object.defineProperty(e,i,s.get?s:{enumerable:!0,get:()=>t[i]})}return e.default=t,Object.freeze(e)}const i=e(t),s="transitionend",n=t=>{let e=t.getAttribute("data-bs-target");if(!e||"#"===e){let i=t.getAttribute("href");if(!i||!i.includes("#")&&!i.startsWith("."))return null;i.includes("#")&&!i.startsWith("#")&&(i=`#${i.split("#")[1]}`),e=i&&"#"!==i?i.trim():null}return e},o=t=>{const e=n(t);return e&&document.querySelector(e)?e:null},r=t=>{const e=n(t);return e?document.querySelector(e):null},a=t=>{t.dispatchEvent(new Event(s))},l=t=>!(!t||"object"!=typeof t)&&(void 0!==t.jquery&&(t=t[0]),void 0!==t.nodeType),c=t=>l(t)?t.jquery?t[0]:t:"string"==typeof t&&t.length>0?document.querySelector(t):null,h=(t,e,i)=>{Object.keys(i).forEach((s=>{const n=i[s],o=e[s],r=o&&l(o)?"element":null==(a=o)?`${a}`:{}.toString.call(a).match(/\s([a-z]+)/i)[1].toLowerCase();var a;if(!new RegExp(n).test(r))throw new TypeError(`${t.toUpperCase()}: Option "${s}" provided type "${r}" but expected type "${n}".`)}))},d=t=>!(!l(t)||0===t.getClientRects().length)&&"visible"===getComputedStyle(t).getPropertyValue("visibility"),u=t=>!t||t.nodeType!==Node.ELEMENT_NODE||!!t.classList.contains("disabled")||(void 0!==t.disabled?t.disabled:t.hasAttribute("disabled")&&"false"!==t.getAttribute("disabled")),g=t=>{if(!document.documentElement.attachShadow)return null;if("function"==typeof t.getRootNode){const e=t.getRootNode();return e instanceof ShadowRoot?e:null}return t instanceof ShadowRoot?t:t.parentNode?g(t.parentNode):null},_=()=>{},f=t=>{t.offsetHeight},p=()=>{const{jQuery:t}=window;return t&&!document.body.hasAttribute("data-bs-no-jquery")?t:null},m=[],b=()=>"rtl"===document.documentElement.dir,v=t=>{var e;e=()=>{const e=p();if(e){const i=t.NAME,s=e.fn[i];e.fn[i]=t.jQueryInterface,e.fn[i].Constructor=t,e.fn[i].noConflict=()=>(e.fn[i]=s,t.jQueryInterface)}},"loading"===document.readyState?(m.length||document.addEventListener("DOMContentLoaded",(()=>{m.forEach((t=>t()))})),m.push(e)):e()},y=t=>{"function"==typeof t&&t()},E=(t,e,i=!0)=>{if(!i)return void y(t);const n=(t=>{if(!t)return 0;let{transitionDuration:e,transitionDelay:i}=window.getComputedStyle(t);const s=Number.parseFloat(e),n=Number.parseFloat(i);return s||n?(e=e.split(",")[0],i=i.split(",")[0],1e3*(Number.parseFloat(e)+Number.parseFloat(i))):0})(e)+5;let o=!1;const r=({target:i})=>{i===e&&(o=!0,e.removeEventListener(s,r),y(t))};e.addEventListener(s,r),setTimeout((()=>{o||a(e)}),n)},w=(t,e,i,s)=>{let n=t.indexOf(e);if(-1===n)return t[!i&&s?t.length-1:0];const o=t.length;return n+=i?1:-1,s&&(n=(n+o)%o),t[Math.max(0,Math.min(n,o-1))]},A=/[^.]*(?=\..*)\.|.*/,T=/\..*/,C=/::\d+$/,k={};let L=1;const S={mouseenter:"mouseover",mouseleave:"mouseout"},O=/^(mouseenter|mouseleave)/i,N=new Set(["click","dblclick","mouseup","mousedown","contextmenu","mousewheel","DOMMouseScroll","mouseover","mouseout","mousemove","selectstart","selectend","keydown","keypress","keyup","orientationchange","touchstart","touchmove","touchend","touchcancel","pointerdown","pointermove","pointerup","pointerleave","pointercancel","gesturestart","gesturechange","gestureend","focus","blur","change","reset","select","submit","focusin","focusout","load","unload","beforeunload","resize","move","DOMContentLoaded","readystatechange","error","abort","scroll"]);function D(t,e){return e&&`${e}::${L++}`||t.uidEvent||L++}function I(t){const e=D(t);return t.uidEvent=e,k[e]=k[e]||{},k[e]}function P(t,e,i=null){const s=Object.keys(t);for(let n=0,o=s.length;n<o;n++){const o=t[s[n]];if(o.originalHandler===e&&o.delegationSelector===i)return o}return null}function x(t,e,i){const s="string"==typeof e,n=s?i:e;let o=H(t);return N.has(o)||(o=t),[s,n,o]}function M(t,e,i,s,n){if("string"!=typeof e||!t)return;if(i||(i=s,s=null),O.test(e)){const t=t=>function(e){if(!e.relatedTarget||e.relatedTarget!==e.delegateTarget&&!e.delegateTarget.contains(e.relatedTarget))return t.call(this,e)};s?s=t(s):i=t(i)}const[o,r,a]=x(e,i,s),l=I(t),c=l[a]||(l[a]={}),h=P(c,r,o?i:null);if(h)return void(h.oneOff=h.oneOff&&n);const d=D(r,e.replace(A,"")),u=o?function(t,e,i){return function s(n){const o=t.querySelectorAll(e);for(let{target:r}=n;r&&r!==this;r=r.parentNode)for(let a=o.length;a--;)if(o[a]===r)return n.delegateTarget=r,s.oneOff&&$.off(t,n.type,e,i),i.apply(r,[n]);return null}}(t,i,s):function(t,e){return function i(s){return s.delegateTarget=t,i.oneOff&&$.off(t,s.type,e),e.apply(t,[s])}}(t,i);u.delegationSelector=o?i:null,u.originalHandler=r,u.oneOff=n,u.uidEvent=d,c[d]=u,t.addEventListener(a,u,o)}function j(t,e,i,s,n){const o=P(e[i],s,n);o&&(t.removeEventListener(i,o,Boolean(n)),delete e[i][o.uidEvent])}function H(t){return t=t.replace(T,""),S[t]||t}const $={on(t,e,i,s){M(t,e,i,s,!1)},one(t,e,i,s){M(t,e,i,s,!0)},off(t,e,i,s){if("string"!=typeof e||!t)return;const[n,o,r]=x(e,i,s),a=r!==e,l=I(t),c=e.startsWith(".");if(void 0!==o){if(!l||!l[r])return;return void j(t,l,r,o,n?i:null)}c&&Object.keys(l).forEach((i=>{!function(t,e,i,s){const n=e[i]||{};Object.keys(n).forEach((o=>{if(o.includes(s)){const s=n[o];j(t,e,i,s.originalHandler,s.delegationSelector)}}))}(t,l,i,e.slice(1))}));const h=l[r]||{};Object.keys(h).forEach((i=>{const s=i.replace(C,"");if(!a||e.includes(s)){const e=h[i];j(t,l,r,e.originalHandler,e.delegationSelector)}}))},trigger(t,e,i){if("string"!=typeof e||!t)return null;const s=p(),n=H(e),o=e!==n,r=N.has(n);let a,l=!0,c=!0,h=!1,d=null;return o&&s&&(a=s.Event(e,i),s(t).trigger(a),l=!a.isPropagationStopped(),c=!a.isImmediatePropagationStopped(),h=a.isDefaultPrevented()),r?(d=document.createEvent("HTMLEvents"),d.initEvent(n,l,!0)):d=new CustomEvent(e,{bubbles:l,cancelable:!0}),void 0!==i&&Object.keys(i).forEach((t=>{Object.defineProperty(d,t,{get:()=>i[t]})})),h&&d.preventDefault(),c&&t.dispatchEvent(d),d.defaultPrevented&&void 0!==a&&a.preventDefault(),d}},B=new Map,z={set(t,e,i){B.has(t)||B.set(t,new Map);const s=B.get(t);s.has(e)||0===s.size?s.set(e,i):console.error(`Bootstrap doesn't allow more than one instance per element. Bound instance: ${Array.from(s.keys())[0]}.`)},get:(t,e)=>B.has(t)&&B.get(t).get(e)||null,remove(t,e){if(!B.has(t))return;const i=B.get(t);i.delete(e),0===i.size&&B.delete(t)}};class R{constructor(t){(t=c(t))&&(this._element=t,z.set(this._element,this.constructor.DATA_KEY,this))}dispose(){z.remove(this._element,this.constructor.DATA_KEY),$.off(this._element,this.constructor.EVENT_KEY),Object.getOwnPropertyNames(this).forEach((t=>{this[t]=null}))}_queueCallback(t,e,i=!0){E(t,e,i)}static getInstance(t){return z.get(c(t),this.DATA_KEY)}static getOrCreateInstance(t,e={}){return this.getInstance(t)||new this(t,"object"==typeof e?e:null)}static get VERSION(){return"5.1.3"}static get NAME(){throw new Error('You have to implement the static method "NAME", for each component!')}static get DATA_KEY(){return`bs.${this.NAME}`}static get EVENT_KEY(){return`.${this.DATA_KEY}`}}const F=(t,e="hide")=>{const i=`click.dismiss${t.EVENT_KEY}`,s=t.NAME;$.on(document,i,`[data-bs-dismiss="${s}"]`,(function(i){if(["A","AREA"].includes(this.tagName)&&i.preventDefault(),u(this))return;const n=r(this)||this.closest(`.${s}`);t.getOrCreateInstance(n)[e]()}))};class q extends R{static get NAME(){return"alert"}close(){if($.trigger(this._element,"close.bs.alert").defaultPrevented)return;this._element.classList.remove("show");const t=this._element.classList.contains("fade");this._queueCallback((()=>this._destroyElement()),this._element,t)}_destroyElement(){this._element.remove(),$.trigger(this._element,"closed.bs.alert"),this.dispose()}static jQueryInterface(t){return this.each((function(){const e=q.getOrCreateInstance(this);if("string"==typeof t){if(void 0===e[t]||t.startsWith("_")||"constructor"===t)throw new TypeError(`No method named "${t}"`);e[t](this)}}))}}F(q,"close"),v(q);const W='[data-bs-toggle="button"]';class U extends R{static get NAME(){return"button"}toggle(){this._element.setAttribute("aria-pressed",this._element.classList.toggle("active"))}static jQueryInterface(t){return this.each((function(){const e=U.getOrCreateInstance(this);"toggle"===t&&e[t]()}))}}function K(t){return"true"===t||"false"!==t&&(t===Number(t).toString()?Number(t):""===t||"null"===t?null:t)}function V(t){return t.replace(/[A-Z]/g,(t=>`-${t.toLowerCase()}`))}$.on(document,"click.bs.button.data-api",W,(t=>{t.preventDefault();const e=t.target.closest(W);U.getOrCreateInstance(e).toggle()})),v(U);const X={setDataAttribute(t,e,i){t.setAttribute(`data-bs-${V(e)}`,i)},removeDataAttribute(t,e){t.removeAttribute(`data-bs-${V(e)}`)},getDataAttributes(t){if(!t)return{};const e={};return Object.keys(t.dataset).filter((t=>t.startsWith("bs"))).forEach((i=>{let s=i.replace(/^bs/,"");s=s.charAt(0).toLowerCase()+s.slice(1,s.length),e[s]=K(t.dataset[i])})),e},getDataAttribute:(t,e)=>K(t.getAttribute(`data-bs-${V(e)}`)),offset(t){const e=t.getBoundingClientRect();return{top:e.top+window.pageYOffset,left:e.left+window.pageXOffset}},position:t=>({top:t.offsetTop,left:t.offsetLeft})},Y={find:(t,e=document.documentElement)=>[].concat(...Element.prototype.querySelectorAll.call(e,t)),findOne:(t,e=document.documentElement)=>Element.prototype.querySelector.call(e,t),children:(t,e)=>[].concat(...t.children).filter((t=>t.matches(e))),parents(t,e){const i=[];let s=t.parentNode;for(;s&&s.nodeType===Node.ELEMENT_NODE&&3!==s.nodeType;)s.matches(e)&&i.push(s),s=s.parentNode;return i},prev(t,e){let i=t.previousElementSibling;for(;i;){if(i.matches(e))return[i];i=i.previousElementSibling}return[]},next(t,e){let i=t.nextElementSibling;for(;i;){if(i.matches(e))return[i];i=i.nextElementSibling}return[]},focusableChildren(t){const e=["a","button","input","textarea","select","details","[tabindex]",'[contenteditable="true"]'].map((t=>`${t}:not([tabindex^="-"])`)).join(", ");return this.find(e,t).filter((t=>!u(t)&&d(t)))}},Q="carousel",G={interval:5e3,keyboard:!0,slide:!1,pause:"hover",wrap:!0,touch:!0},Z={interval:"(number|boolean)",keyboard:"boolean",slide:"(boolean|string)",pause:"(string|boolean)",wrap:"boolean",touch:"boolean"},J="next",tt="prev",et="left",it="right",st={ArrowLeft:it,ArrowRight:et},nt="slid.bs.carousel",ot="active",rt=".active.carousel-item";class at extends R{constructor(t,e){super(t),this._items=null,this._interval=null,this._activeElement=null,this._isPaused=!1,this._isSliding=!1,this.touchTimeout=null,this.touchStartX=0,this.touchDeltaX=0,this._config=this._getConfig(e),this._indicatorsElement=Y.findOne(".carousel-indicators",this._element),this._touchSupported="ontouchstart"in document.documentElement||navigator.maxTouchPoints>0,this._pointerEvent=Boolean(window.PointerEvent),this._addEventListeners()}static get Default(){return G}static get NAME(){return Q}next(){this._slide(J)}nextWhenVisible(){!document.hidden&&d(this._element)&&this.next()}prev(){this._slide(tt)}pause(t){t||(this._isPaused=!0),Y.findOne(".carousel-item-next, .carousel-item-prev",this._element)&&(a(this._element),this.cycle(!0)),clearInterval(this._interval),this._interval=null}cycle(t){t||(this._isPaused=!1),this._interval&&(clearInterval(this._interval),this._interval=null),this._config&&this._config.interval&&!this._isPaused&&(this._updateInterval(),this._interval=setInterval((document.visibilityState?this.nextWhenVisible:this.next).bind(this),this._config.interval))}to(t){this._activeElement=Y.findOne(rt,this._element);const e=this._getItemIndex(this._activeElement);if(t>this._items.length-1||t<0)return;if(this._isSliding)return void $.one(this._element,nt,(()=>this.to(t)));if(e===t)return this.pause(),void this.cycle();const i=t>e?J:tt;this._slide(i,this._items[t])}_getConfig(t){return t={...G,...X.getDataAttributes(this._element),..."object"==typeof t?t:{}},h(Q,t,Z),t}_handleSwipe(){const t=Math.abs(this.touchDeltaX);if(t<=40)return;const e=t/this.touchDeltaX;this.touchDeltaX=0,e&&this._slide(e>0?it:et)}_addEventListeners(){this._config.keyboard&&$.on(this._element,"keydown.bs.carousel",(t=>this._keydown(t))),"hover"===this._config.pause&&($.on(this._element,"mouseenter.bs.carousel",(t=>this.pause(t))),$.on(this._element,"mouseleave.bs.carousel",(t=>this.cycle(t)))),this._config.touch&&this._touchSupported&&this._addTouchEventListeners()}_addTouchEventListeners(){const t=t=>this._pointerEvent&&("pen"===t.pointerType||"touch"===t.pointerType),e=e=>{t(e)?this.touchStartX=e.clientX:this._pointerEvent||(this.touchStartX=e.touches[0].clientX)},i=t=>{this.touchDeltaX=t.touches&&t.touches.length>1?0:t.touches[0].clientX-this.touchStartX},s=e=>{t(e)&&(this.touchDeltaX=e.clientX-this.touchStartX),this._handleSwipe(),"hover"===this._config.pause&&(this.pause(),this.touchTimeout&&clearTimeout(this.touchTimeout),this.touchTimeout=setTimeout((t=>this.cycle(t)),500+this._config.interval))};Y.find(".carousel-item img",this._element).forEach((t=>{$.on(t,"dragstart.bs.carousel",(t=>t.preventDefault()))})),this._pointerEvent?($.on(this._element,"pointerdown.bs.carousel",(t=>e(t))),$.on(this._element,"pointerup.bs.carousel",(t=>s(t))),this._element.classList.add("pointer-event")):($.on(this._element,"touchstart.bs.carousel",(t=>e(t))),$.on(this._element,"touchmove.bs.carousel",(t=>i(t))),$.on(this._element,"touchend.bs.carousel",(t=>s(t))))}_keydown(t){if(/input|textarea/i.test(t.target.tagName))return;const e=st[t.key];e&&(t.preventDefault(),this._slide(e))}_getItemIndex(t){return this._items=t&&t.parentNode?Y.find(".carousel-item",t.parentNode):[],this._items.indexOf(t)}_getItemByOrder(t,e){const i=t===J;return w(this._items,e,i,this._config.wrap)}_triggerSlideEvent(t,e){const i=this._getItemIndex(t),s=this._getItemIndex(Y.findOne(rt,this._element));return $.trigger(this._element,"slide.bs.carousel",{relatedTarget:t,direction:e,from:s,to:i})}_setActiveIndicatorElement(t){if(this._indicatorsElement){const e=Y.findOne(".active",this._indicatorsElement);e.classList.remove(ot),e.removeAttribute("aria-current");const i=Y.find("[data-bs-target]",this._indicatorsElement);for(let e=0;e<i.length;e++)if(Number.parseInt(i[e].getAttribute("data-bs-slide-to"),10)===this._getItemIndex(t)){i[e].classList.add(ot),i[e].setAttribute("aria-current","true");break}}}_updateInterval(){const t=this._activeElement||Y.findOne(rt,this._element);if(!t)return;const e=Number.parseInt(t.getAttribute("data-bs-interval"),10);e?(this._config.defaultInterval=this._config.defaultInterval||this._config.interval,this._config.interval=e):this._config.interval=this._config.defaultInterval||this._config.interval}_slide(t,e){const i=this._directionToOrder(t),s=Y.findOne(rt,this._element),n=this._getItemIndex(s),o=e||this._getItemByOrder(i,s),r=this._getItemIndex(o),a=Boolean(this._interval),l=i===J,c=l?"carousel-item-start":"carousel-item-end",h=l?"carousel-item-next":"carousel-item-prev",d=this._orderToDirection(i);if(o&&o.classList.contains(ot))return void(this._isSliding=!1);if(this._isSliding)return;if(this._triggerSlideEvent(o,d).defaultPrevented)return;if(!s||!o)return;this._isSliding=!0,a&&this.pause(),this._setActiveIndicatorElement(o),this._activeElement=o;const u=()=>{$.trigger(this._element,nt,{relatedTarget:o,direction:d,from:n,to:r})};if(this._element.classList.contains("slide")){o.classList.add(h),f(o),s.classList.add(c),o.classList.add(c);const t=()=>{o.classList.remove(c,h),o.classList.add(ot),s.classList.remove(ot,h,c),this._isSliding=!1,setTimeout(u,0)};this._queueCallback(t,s,!0)}else s.classList.remove(ot),o.classList.add(ot),this._isSliding=!1,u();a&&this.cycle()}_directionToOrder(t){return[it,et].includes(t)?b()?t===et?tt:J:t===et?J:tt:t}_orderToDirection(t){return[J,tt].includes(t)?b()?t===tt?et:it:t===tt?it:et:t}static carouselInterface(t,e){const i=at.getOrCreateInstance(t,e);let{_config:s}=i;"object"==typeof e&&(s={...s,...e});const n="string"==typeof e?e:s.slide;if("number"==typeof e)i.to(e);else if("string"==typeof n){if(void 0===i[n])throw new TypeError(`No method named "${n}"`);i[n]()}else s.interval&&s.ride&&(i.pause(),i.cycle())}static jQueryInterface(t){return this.each((function(){at.carouselInterface(this,t)}))}static dataApiClickHandler(t){const e=r(this);if(!e||!e.classList.contains("carousel"))return;const i={...X.getDataAttributes(e),...X.getDataAttributes(this)},s=this.getAttribute("data-bs-slide-to");s&&(i.interval=!1),at.carouselInterface(e,i),s&&at.getInstance(e).to(s),t.preventDefault()}}$.on(document,"click.bs.carousel.data-api","[data-bs-slide], [data-bs-slide-to]",at.dataApiClickHandler),$.on(window,"load.bs.carousel.data-api",(()=>{const t=Y.find('[data-bs-ride="carousel"]');for(let e=0,i=t.length;e<i;e++)at.carouselInterface(t[e],at.getInstance(t[e]))})),v(at);const lt="collapse",ct={toggle:!0,parent:null},ht={toggle:"boolean",parent:"(null|element)"},dt="show",ut="collapse",gt="collapsing",_t="collapsed",ft=":scope .collapse .collapse",pt='[data-bs-toggle="collapse"]';class mt extends R{constructor(t,e){super(t),this._isTransitioning=!1,this._config=this._getConfig(e),this._triggerArray=[];const i=Y.find(pt);for(let t=0,e=i.length;t<e;t++){const e=i[t],s=o(e),n=Y.find(s).filter((t=>t===this._element));null!==s&&n.length&&(this._selector=s,this._triggerArray.push(e))}this._initializeChildren(),this._config.parent||this._addAriaAndCollapsedClass(this._triggerArray,this._isShown()),this._config.toggle&&this.toggle()}static get Default(){return ct}static get NAME(){return lt}toggle(){this._isShown()?this.hide():this.show()}show(){if(this._isTransitioning||this._isShown())return;let t,e=[];if(this._config.parent){const t=Y.find(ft,this._config.parent);e=Y.find(".collapse.show, .collapse.collapsing",this._config.parent).filter((e=>!t.includes(e)))}const i=Y.findOne(this._selector);if(e.length){const s=e.find((t=>i!==t));if(t=s?mt.getInstance(s):null,t&&t._isTransitioning)return}if($.trigger(this._element,"show.bs.collapse").defaultPrevented)return;e.forEach((e=>{i!==e&&mt.getOrCreateInstance(e,{toggle:!1}).hide(),t||z.set(e,"bs.collapse",null)}));const s=this._getDimension();this._element.classList.remove(ut),this._element.classList.add(gt),this._element.style[s]=0,this._addAriaAndCollapsedClass(this._triggerArray,!0),this._isTransitioning=!0;const n=`scroll${s[0].toUpperCase()+s.slice(1)}`;this._queueCallback((()=>{this._isTransitioning=!1,this._element.classList.remove(gt),this._element.classList.add(ut,dt),this._element.style[s]="",$.trigger(this._element,"shown.bs.collapse")}),this._element,!0),this._element.style[s]=`${this._element[n]}px`}hide(){if(this._isTransitioning||!this._isShown())return;if($.trigger(this._element,"hide.bs.collapse").defaultPrevented)return;const t=this._getDimension();this._element.style[t]=`${this._element.getBoundingClientRect()[t]}px`,f(this._element),this._element.classList.add(gt),this._element.classList.remove(ut,dt);const e=this._triggerArray.length;for(let t=0;t<e;t++){const e=this._triggerArray[t],i=r(e);i&&!this._isShown(i)&&this._addAriaAndCollapsedClass([e],!1)}this._isTransitioning=!0,this._element.style[t]="",this._queueCallback((()=>{this._isTransitioning=!1,this._element.classList.remove(gt),this._element.classList.add(ut),$.trigger(this._element,"hidden.bs.collapse")}),this._element,!0)}_isShown(t=this._element){return t.classList.contains(dt)}_getConfig(t){return(t={...ct,...X.getDataAttributes(this._element),...t}).toggle=Boolean(t.toggle),t.parent=c(t.parent),h(lt,t,ht),t}_getDimension(){return this._element.classList.contains("collapse-horizontal")?"width":"height"}_initializeChildren(){if(!this._config.parent)return;const t=Y.find(ft,this._config.parent);Y.find(pt,this._config.parent).filter((e=>!t.includes(e))).forEach((t=>{const e=r(t);e&&this._addAriaAndCollapsedClass([t],this._isShown(e))}))}_addAriaAndCollapsedClass(t,e){t.length&&t.forEach((t=>{e?t.classList.remove(_t):t.classList.add(_t),t.setAttribute("aria-expanded",e)}))}static jQueryInterface(t){return this.each((function(){const e={};"string"==typeof t&&/show|hide/.test(t)&&(e.toggle=!1);const i=mt.getOrCreateInstance(this,e);if("string"==typeof t){if(void 0===i[t])throw new TypeError(`No method named "${t}"`);i[t]()}}))}}$.on(document,"click.bs.collapse.data-api",pt,(function(t){("A"===t.target.tagName||t.delegateTarget&&"A"===t.delegateTarget.tagName)&&t.preventDefault();const e=o(this);Y.find(e).forEach((t=>{mt.getOrCreateInstance(t,{toggle:!1}).toggle()}))})),v(mt);const bt="dropdown",vt="Escape",yt="Space",Et="ArrowUp",wt="ArrowDown",At=new RegExp("ArrowUp|ArrowDown|Escape"),Tt="click.bs.dropdown.data-api",Ct="keydown.bs.dropdown.data-api",kt="show",Lt='[data-bs-toggle="dropdown"]',St=".dropdown-menu",Ot=b()?"top-end":"top-start",Nt=b()?"top-start":"top-end",Dt=b()?"bottom-end":"bottom-start",It=b()?"bottom-start":"bottom-end",Pt=b()?"left-start":"right-start",xt=b()?"right-start":"left-start",Mt={offset:[0,2],boundary:"clippingParents",reference:"toggle",display:"dynamic",popperConfig:null,autoClose:!0},jt={offset:"(array|string|function)",boundary:"(string|element)",reference:"(string|element|object)",display:"string",popperConfig:"(null|object|function)",autoClose:"(boolean|string)"};class Ht extends R{constructor(t,e){super(t),this._popper=null,this._config=this._getConfig(e),this._menu=this._getMenuElement(),this._inNavbar=this._detectNavbar()}static get Default(){return Mt}static get DefaultType(){return jt}static get NAME(){return bt}toggle(){return this._isShown()?this.hide():this.show()}show(){if(u(this._element)||this._isShown(this._menu))return;const t={relatedTarget:this._element};if($.trigger(this._element,"show.bs.dropdown",t).defaultPrevented)return;const e=Ht.getParentFromElement(this._element);this._inNavbar?X.setDataAttribute(this._menu,"popper","none"):this._createPopper(e),"ontouchstart"in document.documentElement&&!e.closest(".navbar-nav")&&[].concat(...document.body.children).forEach((t=>$.on(t,"mouseover",_))),this._element.focus(),this._element.setAttribute("aria-expanded",!0),this._menu.classList.add(kt),this._element.classList.add(kt),$.trigger(this._element,"shown.bs.dropdown",t)}hide(){if(u(this._element)||!this._isShown(this._menu))return;const t={relatedTarget:this._element};this._completeHide(t)}dispose(){this._popper&&this._popper.destroy(),super.dispose()}update(){this._inNavbar=this._detectNavbar(),this._popper&&this._popper.update()}_completeHide(t){$.trigger(this._element,"hide.bs.dropdown",t).defaultPrevented||("ontouchstart"in document.documentElement&&[].concat(...document.body.children).forEach((t=>$.off(t,"mouseover",_))),this._popper&&this._popper.destroy(),this._menu.classList.remove(kt),this._element.classList.remove(kt),this._element.setAttribute("aria-expanded","false"),X.removeDataAttribute(this._menu,"popper"),$.trigger(this._element,"hidden.bs.dropdown",t))}_getConfig(t){if(t={...this.constructor.Default,...X.getDataAttributes(this._element),...t},h(bt,t,this.constructor.DefaultType),"object"==typeof t.reference&&!l(t.reference)&&"function"!=typeof t.reference.getBoundingClientRect)throw new TypeError(`${bt.toUpperCase()}: Option "reference" provided type "object" without a required "getBoundingClientRect" method.`);return t}_createPopper(t){if(void 0===i)throw new TypeError("Bootstrap's dropdowns require Popper (https://popper.js.org)");let e=this._element;"parent"===this._config.reference?e=t:l(this._config.reference)?e=c(this._config.reference):"object"==typeof this._config.reference&&(e=this._config.reference);const s=this._getPopperConfig(),n=s.modifiers.find((t=>"applyStyles"===t.name&&!1===t.enabled));this._popper=i.createPopper(e,this._menu,s),n&&X.setDataAttribute(this._menu,"popper","static")}_isShown(t=this._element){return t.classList.contains(kt)}_getMenuElement(){return Y.next(this._element,St)[0]}_getPlacement(){const t=this._element.parentNode;if(t.classList.contains("dropend"))return Pt;if(t.classList.contains("dropstart"))return xt;const e="end"===getComputedStyle(this._menu).getPropertyValue("--bs-position").trim();return t.classList.contains("dropup")?e?Nt:Ot:e?It:Dt}_detectNavbar(){return null!==this._element.closest(".navbar")}_getOffset(){const{offset:t}=this._config;return"string"==typeof t?t.split(",").map((t=>Number.parseInt(t,10))):"function"==typeof t?e=>t(e,this._element):t}_getPopperConfig(){const t={placement:this._getPlacement(),modifiers:[{name:"preventOverflow",options:{boundary:this._config.boundary}},{name:"offset",options:{offset:this._getOffset()}}]};return"static"===this._config.display&&(t.modifiers=[{name:"applyStyles",enabled:!1}]),{...t,..."function"==typeof this._config.popperConfig?this._config.popperConfig(t):this._config.popperConfig}}_selectMenuItem({key:t,target:e}){const i=Y.find(".dropdown-menu .dropdown-item:not(.disabled):not(:disabled)",this._menu).filter(d);i.length&&w(i,e,t===wt,!i.includes(e)).focus()}static jQueryInterface(t){return this.each((function(){const e=Ht.getOrCreateInstance(this,t);if("string"==typeof t){if(void 0===e[t])throw new TypeError(`No method named "${t}"`);e[t]()}}))}static clearMenus(t){if(t&&(2===t.button||"keyup"===t.type&&"Tab"!==t.key))return;const e=Y.find(Lt);for(let i=0,s=e.length;i<s;i++){const s=Ht.getInstance(e[i]);if(!s||!1===s._config.autoClose)continue;if(!s._isShown())continue;const n={relatedTarget:s._element};if(t){const e=t.composedPath(),i=e.includes(s._menu);if(e.includes(s._element)||"inside"===s._config.autoClose&&!i||"outside"===s._config.autoClose&&i)continue;if(s._menu.contains(t.target)&&("keyup"===t.type&&"Tab"===t.key||/input|select|option|textarea|form/i.test(t.target.tagName)))continue;"click"===t.type&&(n.clickEvent=t)}s._completeHide(n)}}static getParentFromElement(t){return r(t)||t.parentNode}static dataApiKeydownHandler(t){if(/input|textarea/i.test(t.target.tagName)?t.key===yt||t.key!==vt&&(t.key!==wt&&t.key!==Et||t.target.closest(St)):!At.test(t.key))return;const e=this.classList.contains(kt);if(!e&&t.key===vt)return;if(t.preventDefault(),t.stopPropagation(),u(this))return;const i=this.matches(Lt)?this:Y.prev(this,Lt)[0],s=Ht.getOrCreateInstance(i);if(t.key!==vt)return t.key===Et||t.key===wt?(e||s.show(),void s._selectMenuItem(t)):void(e&&t.key!==yt||Ht.clearMenus());s.hide()}}$.on(document,Ct,Lt,Ht.dataApiKeydownHandler),$.on(document,Ct,St,Ht.dataApiKeydownHandler),$.on(document,Tt,Ht.clearMenus),$.on(document,"keyup.bs.dropdown.data-api",Ht.clearMenus),$.on(document,Tt,Lt,(function(t){t.preventDefault(),Ht.getOrCreateInstance(this).toggle()})),v(Ht);const $t=".fixed-top, .fixed-bottom, .is-fixed, .sticky-top",Bt=".sticky-top";class zt{constructor(){this._element=document.body}getWidth(){const t=document.documentElement.clientWidth;return Math.abs(window.innerWidth-t)}hide(){const t=this.getWidth();this._disableOverFlow(),this._setElementAttributes(this._element,"paddingRight",(e=>e+t)),this._setElementAttributes($t,"paddingRight",(e=>e+t)),this._setElementAttributes(Bt,"marginRight",(e=>e-t))}_disableOverFlow(){this._saveInitialAttribute(this._element,"overflow"),this._element.style.overflow="hidden"}_setElementAttributes(t,e,i){const s=this.getWidth();this._applyManipulationCallback(t,(t=>{if(t!==this._element&&window.innerWidth>t.clientWidth+s)return;this._saveInitialAttribute(t,e);const n=window.getComputedStyle(t)[e];t.style[e]=`${i(Number.parseFloat(n))}px`}))}reset(){this._resetElementAttributes(this._element,"overflow"),this._resetElementAttributes(this._element,"paddingRight"),this._resetElementAttributes($t,"paddingRight"),this._resetElementAttributes(Bt,"marginRight")}_saveInitialAttribute(t,e){const i=t.style[e];i&&X.setDataAttribute(t,e,i)}_resetElementAttributes(t,e){this._applyManipulationCallback(t,(t=>{const i=X.getDataAttribute(t,e);void 0===i?t.style.removeProperty(e):(X.removeDataAttribute(t,e),t.style[e]=i)}))}_applyManipulationCallback(t,e){l(t)?e(t):Y.find(t,this._element).forEach(e)}isOverflowing(){return this.getWidth()>0}}const Rt={className:"modal-backdrop",isVisible:!0,isAnimated:!1,rootElement:"body",clickCallback:null},Ft={className:"string",isVisible:"boolean",isAnimated:"boolean",rootElement:"(element|string)",clickCallback:"(function|null)"},qt="show",Wt="mousedown.bs.backdrop";class Ut{constructor(t){this._config=this._getConfig(t),this._isAppended=!1,this._element=null}show(t){this._config.isVisible?(this._append(),this._config.isAnimated&&f(this._getElement()),this._getElement().classList.add(qt),this._emulateAnimation((()=>{y(t)}))):y(t)}hide(t){this._config.isVisible?(this._getElement().classList.remove(qt),this._emulateAnimation((()=>{this.dispose(),y(t)}))):y(t)}_getElement(){if(!this._element){const t=document.createElement("div");t.className=this._config.className,this._config.isAnimated&&t.classList.add("fade"),this._element=t}return this._element}_getConfig(t){return(t={...Rt,..."object"==typeof t?t:{}}).rootElement=c(t.rootElement),h("backdrop",t,Ft),t}_append(){this._isAppended||(this._config.rootElement.append(this._getElement()),$.on(this._getElement(),Wt,(()=>{y(this._config.clickCallback)})),this._isAppended=!0)}dispose(){this._isAppended&&($.off(this._element,Wt),this._element.remove(),this._isAppended=!1)}_emulateAnimation(t){E(t,this._getElement(),this._config.isAnimated)}}const Kt={trapElement:null,autofocus:!0},Vt={trapElement:"element",autofocus:"boolean"},Xt=".bs.focustrap",Yt="backward";class Qt{constructor(t){this._config=this._getConfig(t),this._isActive=!1,this._lastTabNavDirection=null}activate(){const{trapElement:t,autofocus:e}=this._config;this._isActive||(e&&t.focus(),$.off(document,Xt),$.on(document,"focusin.bs.focustrap",(t=>this._handleFocusin(t))),$.on(document,"keydown.tab.bs.focustrap",(t=>this._handleKeydown(t))),this._isActive=!0)}deactivate(){this._isActive&&(this._isActive=!1,$.off(document,Xt))}_handleFocusin(t){const{target:e}=t,{trapElement:i}=this._config;if(e===document||e===i||i.contains(e))return;const s=Y.focusableChildren(i);0===s.length?i.focus():this._lastTabNavDirection===Yt?s[s.length-1].focus():s[0].focus()}_handleKeydown(t){"Tab"===t.key&&(this._lastTabNavDirection=t.shiftKey?Yt:"forward")}_getConfig(t){return t={...Kt,..."object"==typeof t?t:{}},h("focustrap",t,Vt),t}}const Gt="modal",Zt="Escape",Jt={backdrop:!0,keyboard:!0,focus:!0},te={backdrop:"(boolean|string)",keyboard:"boolean",focus:"boolean"},ee="hidden.bs.modal",ie="show.bs.modal",se="resize.bs.modal",ne="click.dismiss.bs.modal",oe="keydown.dismiss.bs.modal",re="mousedown.dismiss.bs.modal",ae="modal-open",le="show",ce="modal-static";class he extends R{constructor(t,e){super(t),this._config=this._getConfig(e),this._dialog=Y.findOne(".modal-dialog",this._element),this._backdrop=this._initializeBackDrop(),this._focustrap=this._initializeFocusTrap(),this._isShown=!1,this._ignoreBackdropClick=!1,this._isTransitioning=!1,this._scrollBar=new zt}static get Default(){return Jt}static get NAME(){return Gt}toggle(t){return this._isShown?this.hide():this.show(t)}show(t){this._isShown||this._isTransitioning||$.trigger(this._element,ie,{relatedTarget:t}).defaultPrevented||(this._isShown=!0,this._isAnimated()&&(this._isTransitioning=!0),this._scrollBar.hide(),document.body.classList.add(ae),this._adjustDialog(),this._setEscapeEvent(),this._setResizeEvent(),$.on(this._dialog,re,(()=>{$.one(this._element,"mouseup.dismiss.bs.modal",(t=>{t.target===this._element&&(this._ignoreBackdropClick=!0)}))})),this._showBackdrop((()=>this._showElement(t))))}hide(){if(!this._isShown||this._isTransitioning)return;if($.trigger(this._element,"hide.bs.modal").defaultPrevented)return;this._isShown=!1;const t=this._isAnimated();t&&(this._isTransitioning=!0),this._setEscapeEvent(),this._setResizeEvent(),this._focustrap.deactivate(),this._element.classList.remove(le),$.off(this._element,ne),$.off(this._dialog,re),this._queueCallback((()=>this._hideModal()),this._element,t)}dispose(){[window,this._dialog].forEach((t=>$.off(t,".bs.modal"))),this._backdrop.dispose(),this._focustrap.deactivate(),super.dispose()}handleUpdate(){this._adjustDialog()}_initializeBackDrop(){return new Ut({isVisible:Boolean(this._config.backdrop),isAnimated:this._isAnimated()})}_initializeFocusTrap(){return new Qt({trapElement:this._element})}_getConfig(t){return t={...Jt,...X.getDataAttributes(this._element),..."object"==typeof t?t:{}},h(Gt,t,te),t}_showElement(t){const e=this._isAnimated(),i=Y.findOne(".modal-body",this._dialog);this._element.parentNode&&this._element.parentNode.nodeType===Node.ELEMENT_NODE||document.body.append(this._element),this._element.style.display="block",this._element.removeAttribute("aria-hidden"),this._element.setAttribute("aria-modal",!0),this._element.setAttribute("role","dialog"),this._element.scrollTop=0,i&&(i.scrollTop=0),e&&f(this._element),this._element.classList.add(le),this._queueCallback((()=>{this._config.focus&&this._focustrap.activate(),this._isTransitioning=!1,$.trigger(this._element,"shown.bs.modal",{relatedTarget:t})}),this._dialog,e)}_setEscapeEvent(){this._isShown?$.on(this._element,oe,(t=>{this._config.keyboard&&t.key===Zt?(t.preventDefault(),this.hide()):this._config.keyboard||t.key!==Zt||this._triggerBackdropTransition()})):$.off(this._element,oe)}_setResizeEvent(){this._isShown?$.on(window,se,(()=>this._adjustDialog())):$.off(window,se)}_hideModal(){this._element.style.display="none",this._element.setAttribute("aria-hidden",!0),this._element.removeAttribute("aria-modal"),this._element.removeAttribute("role"),this._isTransitioning=!1,this._backdrop.hide((()=>{document.body.classList.remove(ae),this._resetAdjustments(),this._scrollBar.reset(),$.trigger(this._element,ee)}))}_showBackdrop(t){$.on(this._element,ne,(t=>{this._ignoreBackdropClick?this._ignoreBackdropClick=!1:t.target===t.currentTarget&&(!0===this._config.backdrop?this.hide():"static"===this._config.backdrop&&this._triggerBackdropTransition())})),this._backdrop.show(t)}_isAnimated(){return this._element.classList.contains("fade")}_triggerBackdropTransition(){if($.trigger(this._element,"hidePrevented.bs.modal").defaultPrevented)return;const{classList:t,scrollHeight:e,style:i}=this._element,s=e>document.documentElement.clientHeight;!s&&"hidden"===i.overflowY||t.contains(ce)||(s||(i.overflowY="hidden"),t.add(ce),this._queueCallback((()=>{t.remove(ce),s||this._queueCallback((()=>{i.overflowY=""}),this._dialog)}),this._dialog),this._element.focus())}_adjustDialog(){const t=this._element.scrollHeight>document.documentElement.clientHeight,e=this._scrollBar.getWidth(),i=e>0;(!i&&t&&!b()||i&&!t&&b())&&(this._element.style.paddingLeft=`${e}px`),(i&&!t&&!b()||!i&&t&&b())&&(this._element.style.paddingRight=`${e}px`)}_resetAdjustments(){this._element.style.paddingLeft="",this._element.style.paddingRight=""}static jQueryInterface(t,e){return this.each((function(){const i=he.getOrCreateInstance(this,t);if("string"==typeof t){if(void 0===i[t])throw new TypeError(`No method named "${t}"`);i[t](e)}}))}}$.on(document,"click.bs.modal.data-api",'[data-bs-toggle="modal"]',(function(t){const e=r(this);["A","AREA"].includes(this.tagName)&&t.preventDefault(),$.one(e,ie,(t=>{t.defaultPrevented||$.one(e,ee,(()=>{d(this)&&this.focus()}))}));const i=Y.findOne(".modal.show");i&&he.getInstance(i).hide(),he.getOrCreateInstance(e).toggle(this)})),F(he),v(he);const de="offcanvas",ue={backdrop:!0,keyboard:!0,scroll:!1},ge={backdrop:"boolean",keyboard:"boolean",scroll:"boolean"},_e="show",fe=".offcanvas.show",pe="hidden.bs.offcanvas";class me extends R{constructor(t,e){super(t),this._config=this._getConfig(e),this._isShown=!1,this._backdrop=this._initializeBackDrop(),this._focustrap=this._initializeFocusTrap(),this._addEventListeners()}static get NAME(){return de}static get Default(){return ue}toggle(t){return this._isShown?this.hide():this.show(t)}show(t){this._isShown||$.trigger(this._element,"show.bs.offcanvas",{relatedTarget:t}).defaultPrevented||(this._isShown=!0,this._element.style.visibility="visible",this._backdrop.show(),this._config.scroll||(new zt).hide(),this._element.removeAttribute("aria-hidden"),this._element.setAttribute("aria-modal",!0),this._element.setAttribute("role","dialog"),this._element.classList.add(_e),this._queueCallback((()=>{this._config.scroll||this._focustrap.activate(),$.trigger(this._element,"shown.bs.offcanvas",{relatedTarget:t})}),this._element,!0))}hide(){this._isShown&&($.trigger(this._element,"hide.bs.offcanvas").defaultPrevented||(this._focustrap.deactivate(),this._element.blur(),this._isShown=!1,this._element.classList.remove(_e),this._backdrop.hide(),this._queueCallback((()=>{this._element.setAttribute("aria-hidden",!0),this._element.removeAttribute("aria-modal"),this._element.removeAttribute("role"),this._element.style.visibility="hidden",this._config.scroll||(new zt).reset(),$.trigger(this._element,pe)}),this._element,!0)))}dispose(){this._backdrop.dispose(),this._focustrap.deactivate(),super.dispose()}_getConfig(t){return t={...ue,...X.getDataAttributes(this._element),..."object"==typeof t?t:{}},h(de,t,ge),t}_initializeBackDrop(){return new Ut({className:"offcanvas-backdrop",isVisible:this._config.backdrop,isAnimated:!0,rootElement:this._element.parentNode,clickCallback:()=>this.hide()})}_initializeFocusTrap(){return new Qt({trapElement:this._element})}_addEventListeners(){$.on(this._element,"keydown.dismiss.bs.offcanvas",(t=>{this._config.keyboard&&"Escape"===t.key&&this.hide()}))}static jQueryInterface(t){return this.each((function(){const e=me.getOrCreateInstance(this,t);if("string"==typeof t){if(void 0===e[t]||t.startsWith("_")||"constructor"===t)throw new TypeError(`No method named "${t}"`);e[t](this)}}))}}$.on(document,"click.bs.offcanvas.data-api",'[data-bs-toggle="offcanvas"]',(function(t){const e=r(this);if(["A","AREA"].includes(this.tagName)&&t.preventDefault(),u(this))return;$.one(e,pe,(()=>{d(this)&&this.focus()}));const i=Y.findOne(fe);i&&i!==e&&me.getInstance(i).hide(),me.getOrCreateInstance(e).toggle(this)})),$.on(window,"load.bs.offcanvas.data-api",(()=>Y.find(fe).forEach((t=>me.getOrCreateInstance(t).show())))),F(me),v(me);const be=new Set(["background","cite","href","itemtype","longdesc","poster","src","xlink:href"]),ve=/^(?:(?:https?|mailto|ftp|tel|file|sms):|[^#&/:?]*(?:[#/?]|$))/i,ye=/^data:(?:image\/(?:bmp|gif|jpeg|jpg|png|tiff|webp)|video\/(?:mpeg|mp4|ogg|webm)|audio\/(?:mp3|oga|ogg|opus));base64,[\d+/a-z]+=*$/i,Ee=(t,e)=>{const i=t.nodeName.toLowerCase();if(e.includes(i))return!be.has(i)||Boolean(ve.test(t.nodeValue)||ye.test(t.nodeValue));const s=e.filter((t=>t instanceof RegExp));for(let t=0,e=s.length;t<e;t++)if(s[t].test(i))return!0;return!1};function we(t,e,i){if(!t.length)return t;if(i&&"function"==typeof i)return i(t);const s=(new window.DOMParser).parseFromString(t,"text/html"),n=[].concat(...s.body.querySelectorAll("*"));for(let t=0,i=n.length;t<i;t++){const i=n[t],s=i.nodeName.toLowerCase();if(!Object.keys(e).includes(s)){i.remove();continue}const o=[].concat(...i.attributes),r=[].concat(e["*"]||[],e[s]||[]);o.forEach((t=>{Ee(t,r)||i.removeAttribute(t.nodeName)}))}return s.body.innerHTML}const Ae="tooltip",Te=new Set(["sanitize","allowList","sanitizeFn"]),Ce={animation:"boolean",template:"string",title:"(string|element|function)",trigger:"string",delay:"(number|object)",html:"boolean",selector:"(string|boolean)",placement:"(string|function)",offset:"(array|string|function)",container:"(string|element|boolean)",fallbackPlacements:"array",boundary:"(string|element)",customClass:"(string|function)",sanitize:"boolean",sanitizeFn:"(null|function)",allowList:"object",popperConfig:"(null|object|function)"},ke={AUTO:"auto",TOP:"top",RIGHT:b()?"left":"right",BOTTOM:"bottom",LEFT:b()?"right":"left"},Le={animation:!0,template:'<div class="tooltip" role="tooltip"><div class="tooltip-arrow"></div><div class="tooltip-inner"></div></div>',trigger:"hover focus",title:"",delay:0,html:!1,selector:!1,placement:"top",offset:[0,0],container:!1,fallbackPlacements:["top","right","bottom","left"],boundary:"clippingParents",customClass:"",sanitize:!0,sanitizeFn:null,allowList:{"*":["class","dir","id","lang","role",/^aria-[\w-]*$/i],a:["target","href","title","rel"],area:[],b:[],br:[],col:[],code:[],div:[],em:[],hr:[],h1:[],h2:[],h3:[],h4:[],h5:[],h6:[],i:[],img:["src","srcset","alt","title","width","height"],li:[],ol:[],p:[],pre:[],s:[],small:[],span:[],sub:[],sup:[],strong:[],u:[],ul:[]},popperConfig:null},Se={HIDE:"hide.bs.tooltip",HIDDEN:"hidden.bs.tooltip",SHOW:"show.bs.tooltip",SHOWN:"shown.bs.tooltip",INSERTED:"inserted.bs.tooltip",CLICK:"click.bs.tooltip",FOCUSIN:"focusin.bs.tooltip",FOCUSOUT:"focusout.bs.tooltip",MOUSEENTER:"mouseenter.bs.tooltip",MOUSELEAVE:"mouseleave.bs.tooltip"},Oe="fade",Ne="show",De="show",Ie="out",Pe=".tooltip-inner",xe=".modal",Me="hide.bs.modal",je="hover",He="focus";class $e extends R{constructor(t,e){if(void 0===i)throw new TypeError("Bootstrap's tooltips require Popper (https://popper.js.org)");super(t),this._isEnabled=!0,this._timeout=0,this._hoverState="",this._activeTrigger={},this._popper=null,this._config=this._getConfig(e),this.tip=null,this._setListeners()}static get Default(){return Le}static get NAME(){return Ae}static get Event(){return Se}static get DefaultType(){return Ce}enable(){this._isEnabled=!0}disable(){this._isEnabled=!1}toggleEnabled(){this._isEnabled=!this._isEnabled}toggle(t){if(this._isEnabled)if(t){const e=this._initializeOnDelegatedTarget(t);e._activeTrigger.click=!e._activeTrigger.click,e._isWithActiveTrigger()?e._enter(null,e):e._leave(null,e)}else{if(this.getTipElement().classList.contains(Ne))return void this._leave(null,this);this._enter(null,this)}}dispose(){clearTimeout(this._timeout),$.off(this._element.closest(xe),Me,this._hideModalHandler),this.tip&&this.tip.remove(),this._disposePopper(),super.dispose()}show(){if("none"===this._element.style.display)throw new Error("Please use show on visible elements");if(!this.isWithContent()||!this._isEnabled)return;const t=$.trigger(this._element,this.constructor.Event.SHOW),e=g(this._element),s=null===e?this._element.ownerDocument.documentElement.contains(this._element):e.contains(this._element);if(t.defaultPrevented||!s)return;"tooltip"===this.constructor.NAME&&this.tip&&this.getTitle()!==this.tip.querySelector(Pe).innerHTML&&(this._disposePopper(),this.tip.remove(),this.tip=null);const n=this.getTipElement(),o=(t=>{do{t+=Math.floor(1e6*Math.random())}while(document.getElementById(t));return t})(this.constructor.NAME);n.setAttribute("id",o),this._element.setAttribute("aria-describedby",o),this._config.animation&&n.classList.add(Oe);const r="function"==typeof this._config.placement?this._config.placement.call(this,n,this._element):this._config.placement,a=this._getAttachment(r);this._addAttachmentClass(a);const{container:l}=this._config;z.set(n,this.constructor.DATA_KEY,this),this._element.ownerDocument.documentElement.contains(this.tip)||(l.append(n),$.trigger(this._element,this.constructor.Event.INSERTED)),this._popper?this._popper.update():this._popper=i.createPopper(this._element,n,this._getPopperConfig(a)),n.classList.add(Ne);const c=this._resolvePossibleFunction(this._config.customClass);c&&n.classList.add(...c.split(" ")),"ontouchstart"in document.documentElement&&[].concat(...document.body.children).forEach((t=>{$.on(t,"mouseover",_)}));const h=this.tip.classList.contains(Oe);this._queueCallback((()=>{const t=this._hoverState;this._hoverState=null,$.trigger(this._element,this.constructor.Event.SHOWN),t===Ie&&this._leave(null,this)}),this.tip,h)}hide(){if(!this._popper)return;const t=this.getTipElement();if($.trigger(this._element,this.constructor.Event.HIDE).defaultPrevented)return;t.classList.remove(Ne),"ontouchstart"in document.documentElement&&[].concat(...document.body.children).forEach((t=>$.off(t,"mouseover",_))),this._activeTrigger.click=!1,this._activeTrigger.focus=!1,this._activeTrigger.hover=!1;const e=this.tip.classList.contains(Oe);this._queueCallback((()=>{this._isWithActiveTrigger()||(this._hoverState!==De&&t.remove(),this._cleanTipClass(),this._element.removeAttribute("aria-describedby"),$.trigger(this._element,this.constructor.Event.HIDDEN),this._disposePopper())}),this.tip,e),this._hoverState=""}update(){null!==this._popper&&this._popper.update()}isWithContent(){return Boolean(this.getTitle())}getTipElement(){if(this.tip)return this.tip;const t=document.createElement("div");t.innerHTML=this._config.template;const e=t.children[0];return this.setContent(e),e.classList.remove(Oe,Ne),this.tip=e,this.tip}setContent(t){this._sanitizeAndSetContent(t,this.getTitle(),Pe)}_sanitizeAndSetContent(t,e,i){const s=Y.findOne(i,t);e||!s?this.setElementContent(s,e):s.remove()}setElementContent(t,e){if(null!==t)return l(e)?(e=c(e),void(this._config.html?e.parentNode!==t&&(t.innerHTML="",t.append(e)):t.textContent=e.textContent)):void(this._config.html?(this._config.sanitize&&(e=we(e,this._config.allowList,this._config.sanitizeFn)),t.innerHTML=e):t.textContent=e)}getTitle(){const t=this._element.getAttribute("data-bs-original-title")||this._config.title;return this._resolvePossibleFunction(t)}updateAttachment(t){return"right"===t?"end":"left"===t?"start":t}_initializeOnDelegatedTarget(t,e){return e||this.constructor.getOrCreateInstance(t.delegateTarget,this._getDelegateConfig())}_getOffset(){const{offset:t}=this._config;return"string"==typeof t?t.split(",").map((t=>Number.parseInt(t,10))):"function"==typeof t?e=>t(e,this._element):t}_resolvePossibleFunction(t){return"function"==typeof t?t.call(this._element):t}_getPopperConfig(t){const e={placement:t,modifiers:[{name:"flip",options:{fallbackPlacements:this._config.fallbackPlacements}},{name:"offset",options:{offset:this._getOffset()}},{name:"preventOverflow",options:{boundary:this._config.boundary}},{name:"arrow",options:{element:`.${this.constructor.NAME}-arrow`}},{name:"onChange",enabled:!0,phase:"afterWrite",fn:t=>this._handlePopperPlacementChange(t)}],onFirstUpdate:t=>{t.options.placement!==t.placement&&this._handlePopperPlacementChange(t)}};return{...e,..."function"==typeof this._config.popperConfig?this._config.popperConfig(e):this._config.popperConfig}}_addAttachmentClass(t){this.getTipElement().classList.add(`${this._getBasicClassPrefix()}-${this.updateAttachment(t)}`)}_getAttachment(t){return ke[t.toUpperCase()]}_setListeners(){this._config.trigger.split(" ").forEach((t=>{if("click"===t)$.on(this._element,this.constructor.Event.CLICK,this._config.selector,(t=>this.toggle(t)));else if("manual"!==t){const e=t===je?this.constructor.Event.MOUSEENTER:this.constructor.Event.FOCUSIN,i=t===je?this.constructor.Event.MOUSELEAVE:this.constructor.Event.FOCUSOUT;$.on(this._element,e,this._config.selector,(t=>this._enter(t))),$.on(this._element,i,this._config.selector,(t=>this._leave(t)))}})),this._hideModalHandler=()=>{this._element&&this.hide()},$.on(this._element.closest(xe),Me,this._hideModalHandler),this._config.selector?this._config={...this._config,trigger:"manual",selector:""}:this._fixTitle()}_fixTitle(){const t=this._element.getAttribute("title"),e=typeof this._element.getAttribute("data-bs-original-title");(t||"string"!==e)&&(this._element.setAttribute("data-bs-original-title",t||""),!t||this._element.getAttribute("aria-label")||this._element.textContent||this._element.setAttribute("aria-label",t),this._element.setAttribute("title",""))}_enter(t,e){e=this._initializeOnDelegatedTarget(t,e),t&&(e._activeTrigger["focusin"===t.type?He:je]=!0),e.getTipElement().classList.contains(Ne)||e._hoverState===De?e._hoverState=De:(clearTimeout(e._timeout),e._hoverState=De,e._config.delay&&e._config.delay.show?e._timeout=setTimeout((()=>{e._hoverState===De&&e.show()}),e._config.delay.show):e.show())}_leave(t,e){e=this._initializeOnDelegatedTarget(t,e),t&&(e._activeTrigger["focusout"===t.type?He:je]=e._element.contains(t.relatedTarget)),e._isWithActiveTrigger()||(clearTimeout(e._timeout),e._hoverState=Ie,e._config.delay&&e._config.delay.hide?e._timeout=setTimeout((()=>{e._hoverState===Ie&&e.hide()}),e._config.delay.hide):e.hide())}_isWithActiveTrigger(){for(const t in this._activeTrigger)if(this._activeTrigger[t])return!0;return!1}_getConfig(t){const e=X.getDataAttributes(this._element);return Object.keys(e).forEach((t=>{Te.has(t)&&delete e[t]})),(t={...this.constructor.Default,...e,..."object"==typeof t&&t?t:{}}).container=!1===t.container?document.body:c(t.container),"number"==typeof t.delay&&(t.delay={show:t.delay,hide:t.delay}),"number"==typeof t.title&&(t.title=t.title.toString()),"number"==typeof t.content&&(t.content=t.content.toString()),h(Ae,t,this.constructor.DefaultType),t.sanitize&&(t.template=we(t.template,t.allowList,t.sanitizeFn)),t}_getDelegateConfig(){const t={};for(const e in this._config)this.constructor.Default[e]!==this._config[e]&&(t[e]=this._config[e]);return t}_cleanTipClass(){const t=this.getTipElement(),e=new RegExp(`(^|\\s)${this._getBasicClassPrefix()}\\S+`,"g"),i=t.getAttribute("class").match(e);null!==i&&i.length>0&&i.map((t=>t.trim())).forEach((e=>t.classList.remove(e)))}_getBasicClassPrefix(){return"bs-tooltip"}_handlePopperPlacementChange(t){const{state:e}=t;e&&(this.tip=e.elements.popper,this._cleanTipClass(),this._addAttachmentClass(this._getAttachment(e.placement)))}_disposePopper(){this._popper&&(this._popper.destroy(),this._popper=null)}static jQueryInterface(t){return this.each((function(){const e=$e.getOrCreateInstance(this,t);if("string"==typeof t){if(void 0===e[t])throw new TypeError(`No method named "${t}"`);e[t]()}}))}}v($e);const Be={...$e.Default,placement:"right",offset:[0,8],trigger:"click",content:"",template:'<div class="popover" role="tooltip"><div class="popover-arrow"></div><h3 class="popover-header"></h3><div class="popover-body"></div></div>'},ze={...$e.DefaultType,content:"(string|element|function)"},Re={HIDE:"hide.bs.popover",HIDDEN:"hidden.bs.popover",SHOW:"show.bs.popover",SHOWN:"shown.bs.popover",INSERTED:"inserted.bs.popover",CLICK:"click.bs.popover",FOCUSIN:"focusin.bs.popover",FOCUSOUT:"focusout.bs.popover",MOUSEENTER:"mouseenter.bs.popover",MOUSELEAVE:"mouseleave.bs.popover"};class Fe extends $e{static get Default(){return Be}static get NAME(){return"popover"}static get Event(){return Re}static get DefaultType(){return ze}isWithContent(){return this.getTitle()||this._getContent()}setContent(t){this._sanitizeAndSetContent(t,this.getTitle(),".popover-header"),this._sanitizeAndSetContent(t,this._getContent(),".popover-body")}_getContent(){return this._resolvePossibleFunction(this._config.content)}_getBasicClassPrefix(){return"bs-popover"}static jQueryInterface(t){return this.each((function(){const e=Fe.getOrCreateInstance(this,t);if("string"==typeof t){if(void 0===e[t])throw new TypeError(`No method named "${t}"`);e[t]()}}))}}v(Fe);const qe="scrollspy",We={offset:10,method:"auto",target:""},Ue={offset:"number",method:"string",target:"(string|element)"},Ke="active",Ve=".nav-link, .list-group-item, .dropdown-item",Xe="position";class Ye extends R{constructor(t,e){super(t),this._scrollElement="BODY"===this._element.tagName?window:this._element,this._config=this._getConfig(e),this._offsets=[],this._targets=[],this._activeTarget=null,this._scrollHeight=0,$.on(this._scrollElement,"scroll.bs.scrollspy",(()=>this._process())),this.refresh(),this._process()}static get Default(){return We}static get NAME(){return qe}refresh(){const t=this._scrollElement===this._scrollElement.window?"offset":Xe,e="auto"===this._config.method?t:this._config.method,i=e===Xe?this._getScrollTop():0;this._offsets=[],this._targets=[],this._scrollHeight=this._getScrollHeight(),Y.find(Ve,this._config.target).map((t=>{const s=o(t),n=s?Y.findOne(s):null;if(n){const t=n.getBoundingClientRect();if(t.width||t.height)return[X[e](n).top+i,s]}return null})).filter((t=>t)).sort(((t,e)=>t[0]-e[0])).forEach((t=>{this._offsets.push(t[0]),this._targets.push(t[1])}))}dispose(){$.off(this._scrollElement,".bs.scrollspy"),super.dispose()}_getConfig(t){return(t={...We,...X.getDataAttributes(this._element),..."object"==typeof t&&t?t:{}}).target=c(t.target)||document.documentElement,h(qe,t,Ue),t}_getScrollTop(){return this._scrollElement===window?this._scrollElement.pageYOffset:this._scrollElement.scrollTop}_getScrollHeight(){return this._scrollElement.scrollHeight||Math.max(document.body.scrollHeight,document.documentElement.scrollHeight)}_getOffsetHeight(){return this._scrollElement===window?window.innerHeight:this._scrollElement.getBoundingClientRect().height}_process(){const t=this._getScrollTop()+this._config.offset,e=this._getScrollHeight(),i=this._config.offset+e-this._getOffsetHeight();if(this._scrollHeight!==e&&this.refresh(),t>=i){const t=this._targets[this._targets.length-1];this._activeTarget!==t&&this._activate(t)}else{if(this._activeTarget&&t<this._offsets[0]&&this._offsets[0]>0)return this._activeTarget=null,void this._clear();for(let e=this._offsets.length;e--;)this._activeTarget!==this._targets[e]&&t>=this._offsets[e]&&(void 0===this._offsets[e+1]||t<this._offsets[e+1])&&this._activate(this._targets[e])}}_activate(t){this._activeTarget=t,this._clear();const e=Ve.split(",").map((e=>`${e}[data-bs-target="${t}"],${e}[href="${t}"]`)),i=Y.findOne(e.join(","),this._config.target);i.classList.add(Ke),i.classList.contains("dropdown-item")?Y.findOne(".dropdown-toggle",i.closest(".dropdown")).classList.add(Ke):Y.parents(i,".nav, .list-group").forEach((t=>{Y.prev(t,".nav-link, .list-group-item").forEach((t=>t.classList.add(Ke))),Y.prev(t,".nav-item").forEach((t=>{Y.children(t,".nav-link").forEach((t=>t.classList.add(Ke)))}))})),$.trigger(this._scrollElement,"activate.bs.scrollspy",{relatedTarget:t})}_clear(){Y.find(Ve,this._config.target).filter((t=>t.classList.contains(Ke))).forEach((t=>t.classList.remove(Ke)))}static jQueryInterface(t){return this.each((function(){const e=Ye.getOrCreateInstance(this,t);if("string"==typeof t){if(void 0===e[t])throw new TypeError(`No method named "${t}"`);e[t]()}}))}}$.on(window,"load.bs.scrollspy.data-api",(()=>{Y.find('[data-bs-spy="scroll"]').forEach((t=>new Ye(t)))})),v(Ye);const Qe="active",Ge="fade",Ze="show",Je=".active",ti=":scope > li > .active";class ei extends R{static get NAME(){return"tab"}show(){if(this._element.parentNode&&this._element.parentNode.nodeType===Node.ELEMENT_NODE&&this._element.classList.contains(Qe))return;let t;const e=r(this._element),i=this._element.closest(".nav, .list-group");if(i){const e="UL"===i.nodeName||"OL"===i.nodeName?ti:Je;t=Y.find(e,i),t=t[t.length-1]}const s=t?$.trigger(t,"hide.bs.tab",{relatedTarget:this._element}):null;if($.trigger(this._element,"show.bs.tab",{relatedTarget:t}).defaultPrevented||null!==s&&s.defaultPrevented)return;this._activate(this._element,i);const n=()=>{$.trigger(t,"hidden.bs.tab",{relatedTarget:this._element}),$.trigger(this._element,"shown.bs.tab",{relatedTarget:t})};e?this._activate(e,e.parentNode,n):n()}_activate(t,e,i){const s=(!e||"UL"!==e.nodeName&&"OL"!==e.nodeName?Y.children(e,Je):Y.find(ti,e))[0],n=i&&s&&s.classList.contains(Ge),o=()=>this._transitionComplete(t,s,i);s&&n?(s.classList.remove(Ze),this._queueCallback(o,t,!0)):o()}_transitionComplete(t,e,i){if(e){e.classList.remove(Qe);const t=Y.findOne(":scope > .dropdown-menu .active",e.parentNode);t&&t.classList.remove(Qe),"tab"===e.getAttribute("role")&&e.setAttribute("aria-selected",!1)}t.classList.add(Qe),"tab"===t.getAttribute("role")&&t.setAttribute("aria-selected",!0),f(t),t.classList.contains(Ge)&&t.classList.add(Ze);let s=t.parentNode;if(s&&"LI"===s.nodeName&&(s=s.parentNode),s&&s.classList.contains("dropdown-menu")){const e=t.closest(".dropdown");e&&Y.find(".dropdown-toggle",e).forEach((t=>t.classList.add(Qe))),t.setAttribute("aria-expanded",!0)}i&&i()}static jQueryInterface(t){return this.each((function(){const e=ei.getOrCreateInstance(this);if("string"==typeof t){if(void 0===e[t])throw new TypeError(`No method named "${t}"`);e[t]()}}))}}$.on(document,"click.bs.tab.data-api",'[data-bs-toggle="tab"], [data-bs-toggle="pill"], [data-bs-toggle="list"]',(function(t){["A","AREA"].includes(this.tagName)&&t.preventDefault(),u(this)||ei.getOrCreateInstance(this).show()})),v(ei);const ii="toast",si="hide",ni="show",oi="showing",ri={animation:"boolean",autohide:"boolean",delay:"number"},ai={animation:!0,autohide:!0,delay:5e3};class li extends R{constructor(t,e){super(t),this._config=this._getConfig(e),this._timeout=null,this._hasMouseInteraction=!1,this._hasKeyboardInteraction=!1,this._setListeners()}static get DefaultType(){return ri}static get Default(){return ai}static get NAME(){return ii}show(){$.trigger(this._element,"show.bs.toast").defaultPrevented||(this._clearTimeout(),this._config.animation&&this._element.classList.add("fade"),this._element.classList.remove(si),f(this._element),this._element.classList.add(ni),this._element.classList.add(oi),this._queueCallback((()=>{this._element.classList.remove(oi),$.trigger(this._element,"shown.bs.toast"),this._maybeScheduleHide()}),this._element,this._config.animation))}hide(){this._element.classList.contains(ni)&&($.trigger(this._element,"hide.bs.toast").defaultPrevented||(this._element.classList.add(oi),this._queueCallback((()=>{this._element.classList.add(si),this._element.classList.remove(oi),this._element.classList.remove(ni),$.trigger(this._element,"hidden.bs.toast")}),this._element,this._config.animation)))}dispose(){this._clearTimeout(),this._element.classList.contains(ni)&&this._element.classList.remove(ni),super.dispose()}_getConfig(t){return t={...ai,...X.getDataAttributes(this._element),..."object"==typeof t&&t?t:{}},h(ii,t,this.constructor.DefaultType),t}_maybeScheduleHide(){this._config.autohide&&(this._hasMouseInteraction||this._hasKeyboardInteraction||(this._timeout=setTimeout((()=>{this.hide()}),this._config.delay)))}_onInteraction(t,e){switch(t.type){case"mouseover":case"mouseout":this._hasMouseInteraction=e;break;case"focusin":case"focusout":this._hasKeyboardInteraction=e}if(e)return void this._clearTimeout();const i=t.relatedTarget;this._element===i||this._element.contains(i)||this._maybeScheduleHide()}_setListeners(){$.on(this._element,"mouseover.bs.toast",(t=>this._onInteraction(t,!0))),$.on(this._element,"mouseout.bs.toast",(t=>this._onInteraction(t,!1))),$.on(this._element,"focusin.bs.toast",(t=>this._onInteraction(t,!0))),$.on(this._element,"focusout.bs.toast",(t=>this._onInteraction(t,!1)))}_clearTimeout(){clearTimeout(this._timeout),this._timeout=null}static jQueryInterface(t){return this.each((function(){const e=li.getOrCreateInstance(this,t);if("string"==typeof t){if(void 0===e[t])throw new TypeError(`No method named "${t}"`);e[t](this)}}))}}return F(li),v(li),{Alert:q,Button:U,Carousel:at,Collapse:mt,Dropdown:Ht,Modal:he,Offcanvas:me,Popover:Fe,ScrollSpy:Ye,Tab:ei,Toast:li,Tooltip:$e}}));
		</script>
		<script>
			//src="https://unpkg.com/bootstrap-table@1.22.4/dist/bootstrap-table.min.js"
			/**
			  * bootstrap-table - An extended table to integration with some of the most widely used CSS frameworks. (Supports Bootstrap, Semantic UI, Bulma, Material Design, Foundation)
			  * @version v1.22.4
			  * @homepage https://bootstrap-table.com
			  * @author wenzhixin <wenzhixin2010@gmail.com> (http://wenzhixin.net.cn/)
			  * @license MIT
			*/
			!function(t,e){"object"==typeof exports&&"undefined"!=typeof module?module.exports=e(require("jquery")):"function"==typeof define&&define.amd?define(["jquery"],e):(t="undefined"!=typeof globalThis?globalThis:t||self).BootstrapTable=e(t.jQuery)}(this,(function(t){"use strict";function e(t){var e=function(t,e){if("object"!=typeof t||!t)return t;var i=t[Symbol.toPrimitive];if(void 0!==i){var n=i.call(t,e||"default");if("object"!=typeof n)return n;throw new TypeError("@@toPrimitive must return a primitive value.")}return("string"===e?String:Number)(t)}(t,"string");return"symbol"==typeof e?e:String(e)}function i(t){return i="function"==typeof Symbol&&"symbol"==typeof Symbol.iterator?function(t){return typeof t}:function(t){return t&&"function"==typeof Symbol&&t.constructor===Symbol&&t!==Symbol.prototype?"symbol":typeof t},i(t)}function n(t,e){if(!(t instanceof e))throw new TypeError("Cannot call a class as a function")}function o(t,i){for(var n=0;n<i.length;n++){var o=i[n];o.enumerable=o.enumerable||!1,o.configurable=!0,"value"in o&&(o.writable=!0),Object.defineProperty(t,e(o.key),o)}}function r(t,e,i){return e&&o(t.prototype,e),i&&o(t,i),Object.defineProperty(t,"prototype",{writable:!1}),t}function a(t,e){return function(t){if(Array.isArray(t))return t}(t)||function(t,e){var i=null==t?null:"undefined"!=typeof Symbol&&t[Symbol.iterator]||t["@@iterator"];if(null!=i){var n,o,r,a,s=[],l=!0,c=!1;try{if(r=(i=i.call(t)).next,0===e){if(Object(i)!==i)return;l=!1}else for(;!(l=(n=r.call(i)).done)&&(s.push(n.value),s.length!==e);l=!0);}catch(t){c=!0,o=t}finally{try{if(!l&&null!=i.return&&(a=i.return(),Object(a)!==a))return}finally{if(c)throw o}}return s}}(t,e)||l(t,e)||function(){throw new TypeError("Invalid attempt to destructure non-iterable instance.\nIn order to be iterable, non-array objects must have a [Symbol.iterator]() method.")}()}function s(t){return function(t){if(Array.isArray(t))return c(t)}(t)||function(t){if("undefined"!=typeof Symbol&&null!=t[Symbol.iterator]||null!=t["@@iterator"])return Array.from(t)}(t)||l(t)||function(){throw new TypeError("Invalid attempt to spread non-iterable instance.\nIn order to be iterable, non-array objects must have a [Symbol.iterator]() method.")}()}function l(t,e){if(t){if("string"==typeof t)return c(t,e);var i=Object.prototype.toString.call(t).slice(8,-1);return"Object"===i&&t.constructor&&(i=t.constructor.name),"Map"===i||"Set"===i?Array.from(t):"Arguments"===i||/^(?:Ui|I)nt(?:8|16|32)(?:Clamped)?Array$/.test(i)?c(t,e):void 0}}function c(t,e){(null==e||e>t.length)&&(e=t.length);for(var i=0,n=new Array(e);i<e;i++)n[i]=t[i];return n}function h(t,e){var i="undefined"!=typeof Symbol&&t[Symbol.iterator]||t["@@iterator"];if(!i){if(Array.isArray(t)||(i=l(t))||e&&t&&"number"==typeof t.length){i&&(t=i);var n=0,o=function(){};return{s:o,n:function(){return n>=t.length?{done:!0}:{done:!1,value:t[n++]}},e:function(t){throw t},f:o}}throw new TypeError("Invalid attempt to iterate non-iterable instance.\nIn order to be iterable, non-array objects must have a [Symbol.iterator]() method.")}var r,a=!0,s=!1;return{s:function(){i=i.call(t)},n:function(){var t=i.next();return a=t.done,t},e:function(t){s=!0,r=t},f:function(){try{a||null==i.return||i.return()}finally{if(s)throw r}}}}var u="undefined"!=typeof globalThis?globalThis:"undefined"!=typeof window?window:"undefined"!=typeof global?global:"undefined"!=typeof self?self:{},d=function(t){return t&&t.Math===Math&&t},p=d("object"==typeof globalThis&&globalThis)||d("object"==typeof window&&window)||d("object"==typeof self&&self)||d("object"==typeof u&&u)||d("object"==typeof u&&u)||function(){return this}()||Function("return this")(),f={},g=function(t){try{return!!t()}catch(t){return!0}},v=!g((function(){return 7!==Object.defineProperty({},1,{get:function(){return 7}})[1]})),b=!g((function(){var t=function(){}.bind();return"function"!=typeof t||t.hasOwnProperty("prototype")})),m=b,y=Function.prototype.call,w=m?y.bind(y):function(){return y.apply(y,arguments)},S={},x={}.propertyIsEnumerable,O=Object.getOwnPropertyDescriptor,k=O&&!x.call({1:2},1);S.f=k?function(t){var e=O(this,t);return!!e&&e.enumerable}:x;var C,P,T=function(t,e){return{enumerable:!(1&t),configurable:!(2&t),writable:!(4&t),value:e}},I=b,A=Function.prototype,$=A.call,R=I&&A.bind.bind($,$),E=I?R:function(t){return function(){return $.apply(t,arguments)}},j=E,_=j({}.toString),F=j("".slice),N=function(t){return F(_(t),8,-1)},D=g,V=N,B=Object,L=E("".split),H=D((function(){return!B("z").propertyIsEnumerable(0)}))?function(t){return"String"===V(t)?L(t,""):B(t)}:B,M=function(t){return null==t},U=M,z=TypeError,q=function(t){if(U(t))throw new z("Can't call method on "+t);return t},W=H,G=q,K=function(t){return W(G(t))},Y="object"==typeof document&&document.all,J=void 0===Y&&void 0!==Y?function(t){return"function"==typeof t||t===Y}:function(t){return"function"==typeof t},X=J,Q=function(t){return"object"==typeof t?null!==t:X(t)},Z=p,tt=J,et=function(t){return tt(t)?t:void 0},it=function(t,e){return arguments.length<2?et(Z[t]):Z[t]&&Z[t][e]},nt=E({}.isPrototypeOf),ot="undefined"!=typeof navigator&&String(navigator.userAgent)||"",rt=p,at=ot,st=rt.process,lt=rt.Deno,ct=st&&st.versions||lt&&lt.version,ht=ct&&ct.v8;ht&&(P=(C=ht.split("."))[0]>0&&C[0]<4?1:+(C[0]+C[1])),!P&&at&&(!(C=at.match(/Edge\/(\d+)/))||C[1]>=74)&&(C=at.match(/Chrome\/(\d+)/))&&(P=+C[1]);var ut=P,dt=ut,pt=g,ft=p.String,gt=!!Object.getOwnPropertySymbols&&!pt((function(){var t=Symbol("symbol detection");return!ft(t)||!(Object(t)instanceof Symbol)||!Symbol.sham&&dt&&dt<41})),vt=gt&&!Symbol.sham&&"symbol"==typeof Symbol.iterator,bt=it,mt=J,yt=nt,wt=Object,St=vt?function(t){return"symbol"==typeof t}:function(t){var e=bt("Symbol");return mt(e)&&yt(e.prototype,wt(t))},xt=String,Ot=function(t){try{return xt(t)}catch(t){return"Object"}},kt=J,Ct=Ot,Pt=TypeError,Tt=function(t){if(kt(t))return t;throw new Pt(Ct(t)+" is not a function")},It=Tt,At=M,$t=function(t,e){var i=t[e];return At(i)?void 0:It(i)},Rt=w,Et=J,jt=Q,_t=TypeError,Ft={exports:{}},Nt=p,Dt=Object.defineProperty,Vt=function(t,e){try{Dt(Nt,t,{value:e,configurable:!0,writable:!0})}catch(i){Nt[t]=e}return e},Bt=p,Lt=Vt,Ht="__core-js_shared__",Mt=Ft.exports=Bt[Ht]||Lt(Ht,{});(Mt.versions||(Mt.versions=[])).push({version:"3.36.0",mode:"global",copyright:"© 2014-2024 Denis Pushkarev (zloirock.ru)",license:"https://github.com/zloirock/core-js/blob/v3.36.0/LICENSE",source:"https://github.com/zloirock/core-js"});var Ut=Ft.exports,zt=Ut,qt=function(t,e){return zt[t]||(zt[t]=e||{})},Wt=q,Gt=Object,Kt=function(t){return Gt(Wt(t))},Yt=Kt,Jt=E({}.hasOwnProperty),Xt=Object.hasOwn||function(t,e){return Jt(Yt(t),e)},Qt=E,Zt=0,te=Math.random(),ee=Qt(1..toString),ie=function(t){return"Symbol("+(void 0===t?"":t)+")_"+ee(++Zt+te,36)},ne=qt,oe=Xt,re=ie,ae=gt,se=vt,le=p.Symbol,ce=ne("wks"),he=se?le.for||le:le&&le.withoutSetter||re,ue=function(t){return oe(ce,t)||(ce[t]=ae&&oe(le,t)?le[t]:he("Symbol."+t)),ce[t]},de=w,pe=Q,fe=St,ge=$t,ve=function(t,e){var i,n;if("string"===e&&Et(i=t.toString)&&!jt(n=Rt(i,t)))return n;if(Et(i=t.valueOf)&&!jt(n=Rt(i,t)))return n;if("string"!==e&&Et(i=t.toString)&&!jt(n=Rt(i,t)))return n;throw new _t("Can't convert object to primitive value")},be=TypeError,me=ue("toPrimitive"),ye=function(t,e){if(!pe(t)||fe(t))return t;var i,n=ge(t,me);if(n){if(void 0===e&&(e="default"),i=de(n,t,e),!pe(i)||fe(i))return i;throw new be("Can't convert object to primitive value")}return void 0===e&&(e="number"),ve(t,e)},we=ye,Se=St,xe=function(t){var e=we(t,"string");return Se(e)?e:e+""},Oe=Q,ke=p.document,Ce=Oe(ke)&&Oe(ke.createElement),Pe=function(t){return Ce?ke.createElement(t):{}},Te=Pe,Ie=!v&&!g((function(){return 7!==Object.defineProperty(Te("div"),"a",{get:function(){return 7}}).a})),Ae=v,$e=w,Re=S,Ee=T,je=K,_e=xe,Fe=Xt,Ne=Ie,De=Object.getOwnPropertyDescriptor;f.f=Ae?De:function(t,e){if(t=je(t),e=_e(e),Ne)try{return De(t,e)}catch(t){}if(Fe(t,e))return Ee(!$e(Re.f,t,e),t[e])};var Ve={},Be=v&&g((function(){return 42!==Object.defineProperty((function(){}),"prototype",{value:42,writable:!1}).prototype})),Le=Q,He=String,Me=TypeError,Ue=function(t){if(Le(t))return t;throw new Me(He(t)+" is not an object")},ze=v,qe=Ie,We=Be,Ge=Ue,Ke=xe,Ye=TypeError,Je=Object.defineProperty,Xe=Object.getOwnPropertyDescriptor,Qe="enumerable",Ze="configurable",ti="writable";Ve.f=ze?We?function(t,e,i){if(Ge(t),e=Ke(e),Ge(i),"function"==typeof t&&"prototype"===e&&"value"in i&&ti in i&&!i.writable){var n=Xe(t,e);n&&n.writable&&(t[e]=i.value,i={configurable:Ze in i?i.configurable:n.configurable,enumerable:Qe in i?i.enumerable:n.enumerable,writable:!1})}return Je(t,e,i)}:Je:function(t,e,i){if(Ge(t),e=Ke(e),Ge(i),qe)try{return Je(t,e,i)}catch(t){}if("get"in i||"set"in i)throw new Ye("Accessors not supported");return"value"in i&&(t[e]=i.value),t};var ei=Ve,ii=T,ni=v?function(t,e,i){return ei.f(t,e,ii(1,i))}:function(t,e,i){return t[e]=i,t},oi={exports:{}},ri=v,ai=Xt,si=Function.prototype,li=ri&&Object.getOwnPropertyDescriptor,ci=ai(si,"name"),hi={EXISTS:ci,PROPER:ci&&"something"===function(){}.name,CONFIGURABLE:ci&&(!ri||ri&&li(si,"name").configurable)},ui=J,di=Ut,pi=E(Function.toString);ui(di.inspectSource)||(di.inspectSource=function(t){return pi(t)});var fi,gi,vi,bi=di.inspectSource,mi=J,yi=p.WeakMap,wi=mi(yi)&&/native code/.test(String(yi)),Si=ie,xi=qt("keys"),Oi=function(t){return xi[t]||(xi[t]=Si(t))},ki={},Ci=wi,Pi=p,Ti=Q,Ii=ni,Ai=Xt,$i=Ut,Ri=Oi,Ei=ki,ji="Object already initialized",_i=Pi.TypeError,Fi=Pi.WeakMap;if(Ci||$i.state){var Ni=$i.state||($i.state=new Fi);Ni.get=Ni.get,Ni.has=Ni.has,Ni.set=Ni.set,fi=function(t,e){if(Ni.has(t))throw new _i(ji);return e.facade=t,Ni.set(t,e),e},gi=function(t){return Ni.get(t)||{}},vi=function(t){return Ni.has(t)}}else{var Di=Ri("state");Ei[Di]=!0,fi=function(t,e){if(Ai(t,Di))throw new _i(ji);return e.facade=t,Ii(t,Di,e),e},gi=function(t){return Ai(t,Di)?t[Di]:{}},vi=function(t){return Ai(t,Di)}}var Vi={set:fi,get:gi,has:vi,enforce:function(t){return vi(t)?gi(t):fi(t,{})},getterFor:function(t){return function(e){var i;if(!Ti(e)||(i=gi(e)).type!==t)throw new _i("Incompatible receiver, "+t+" required");return i}}},Bi=E,Li=g,Hi=J,Mi=Xt,Ui=v,zi=hi.CONFIGURABLE,qi=bi,Wi=Vi.enforce,Gi=Vi.get,Ki=String,Yi=Object.defineProperty,Ji=Bi("".slice),Xi=Bi("".replace),Qi=Bi([].join),Zi=Ui&&!Li((function(){return 8!==Yi((function(){}),"length",{value:8}).length})),tn=String(String).split("String"),en=oi.exports=function(t,e,i){"Symbol("===Ji(Ki(e),0,7)&&(e="["+Xi(Ki(e),/^Symbol\(([^)]*)\).*$/,"$1")+"]"),i&&i.getter&&(e="get "+e),i&&i.setter&&(e="set "+e),(!Mi(t,"name")||zi&&t.name!==e)&&(Ui?Yi(t,"name",{value:e,configurable:!0}):t.name=e),Zi&&i&&Mi(i,"arity")&&t.length!==i.arity&&Yi(t,"length",{value:i.arity});try{i&&Mi(i,"constructor")&&i.constructor?Ui&&Yi(t,"prototype",{writable:!1}):t.prototype&&(t.prototype=void 0)}catch(t){}var n=Wi(t);return Mi(n,"source")||(n.source=Qi(tn,"string"==typeof e?e:"")),t};Function.prototype.toString=en((function(){return Hi(this)&&Gi(this).source||qi(this)}),"toString");var nn=oi.exports,on=J,rn=Ve,an=nn,sn=Vt,ln=function(t,e,i,n){n||(n={});var o=n.enumerable,r=void 0!==n.name?n.name:e;if(on(i)&&an(i,r,n),n.global)o?t[e]=i:sn(e,i);else{try{n.unsafe?t[e]&&(o=!0):delete t[e]}catch(t){}o?t[e]=i:rn.f(t,e,{value:i,enumerable:!1,configurable:!n.nonConfigurable,writable:!n.nonWritable})}return t},cn={},hn=Math.ceil,un=Math.floor,dn=Math.trunc||function(t){var e=+t;return(e>0?un:hn)(e)},pn=function(t){var e=+t;return e!=e||0===e?0:dn(e)},fn=pn,gn=Math.max,vn=Math.min,bn=function(t,e){var i=fn(t);return i<0?gn(i+e,0):vn(i,e)},mn=pn,yn=Math.min,wn=function(t){var e=mn(t);return e>0?yn(e,9007199254740991):0},Sn=wn,xn=function(t){return Sn(t.length)},On=K,kn=bn,Cn=xn,Pn=function(t){return function(e,i,n){var o=On(e),r=Cn(o);if(0===r)return!t&&-1;var a,s=kn(n,r);if(t&&i!=i){for(;r>s;)if((a=o[s++])!=a)return!0}else for(;r>s;s++)if((t||s in o)&&o[s]===i)return t||s||0;return!t&&-1}},Tn={includes:Pn(!0),indexOf:Pn(!1)},In=Xt,An=K,$n=Tn.indexOf,Rn=ki,En=E([].push),jn=function(t,e){var i,n=An(t),o=0,r=[];for(i in n)!In(Rn,i)&&In(n,i)&&En(r,i);for(;e.length>o;)In(n,i=e[o++])&&(~$n(r,i)||En(r,i));return r},_n=["constructor","hasOwnProperty","isPrototypeOf","propertyIsEnumerable","toLocaleString","toString","valueOf"],Fn=jn,Nn=_n.concat("length","prototype");cn.f=Object.getOwnPropertyNames||function(t){return Fn(t,Nn)};var Dn={};Dn.f=Object.getOwnPropertySymbols;var Vn=it,Bn=cn,Ln=Dn,Hn=Ue,Mn=E([].concat),Un=Vn("Reflect","ownKeys")||function(t){var e=Bn.f(Hn(t)),i=Ln.f;return i?Mn(e,i(t)):e},zn=Xt,qn=Un,Wn=f,Gn=Ve,Kn=g,Yn=J,Jn=/#|\.prototype\./,Xn=function(t,e){var i=Zn[Qn(t)];return i===eo||i!==to&&(Yn(e)?Kn(e):!!e)},Qn=Xn.normalize=function(t){return String(t).replace(Jn,".").toLowerCase()},Zn=Xn.data={},to=Xn.NATIVE="N",eo=Xn.POLYFILL="P",io=Xn,no=p,oo=f.f,ro=ni,ao=ln,so=Vt,lo=function(t,e,i){for(var n=qn(e),o=Gn.f,r=Wn.f,a=0;a<n.length;a++){var s=n[a];zn(t,s)||i&&zn(i,s)||o(t,s,r(e,s))}},co=io,ho=function(t,e){var i,n,o,r,a,s=t.target,l=t.global,c=t.stat;if(i=l?no:c?no[s]||so(s,{}):no[s]&&no[s].prototype)for(n in e){if(r=e[n],o=t.dontCallGetSet?(a=oo(i,n))&&a.value:i[n],!co(l?n:s+(c?".":"#")+n,t.forced)&&void 0!==o){if(typeof r==typeof o)continue;lo(r,o)}(t.sham||o&&o.sham)&&ro(r,"sham",!0),ao(i,n,r,t)}},uo=N,po=Array.isArray||function(t){return"Array"===uo(t)},fo=TypeError,go=function(t){if(t>9007199254740991)throw fo("Maximum allowed index exceeded");return t},vo=v,bo=Ve,mo=T,yo=function(t,e,i){vo?bo.f(t,e,mo(0,i)):t[e]=i},wo={};wo[ue("toStringTag")]="z";var So="[object z]"===String(wo),xo=So,Oo=J,ko=N,Co=ue("toStringTag"),Po=Object,To="Arguments"===ko(function(){return arguments}()),Io=xo?ko:function(t){var e,i,n;return void 0===t?"Undefined":null===t?"Null":"string"==typeof(i=function(t,e){try{return t[e]}catch(t){}}(e=Po(t),Co))?i:To?ko(e):"Object"===(n=ko(e))&&Oo(e.callee)?"Arguments":n},Ao=E,$o=g,Ro=J,Eo=Io,jo=bi,_o=function(){},Fo=it("Reflect","construct"),No=/^\s*(?:class|function)\b/,Do=Ao(No.exec),Vo=!No.test(_o),Bo=function(t){if(!Ro(t))return!1;try{return Fo(_o,[],t),!0}catch(t){return!1}},Lo=function(t){if(!Ro(t))return!1;switch(Eo(t)){case"AsyncFunction":case"GeneratorFunction":case"AsyncGeneratorFunction":return!1}try{return Vo||!!Do(No,jo(t))}catch(t){return!0}};Lo.sham=!0;var Ho=!Fo||$o((function(){var t;return Bo(Bo.call)||!Bo(Object)||!Bo((function(){t=!0}))||t}))?Lo:Bo,Mo=po,Uo=Ho,zo=Q,qo=ue("species"),Wo=Array,Go=function(t){var e;return Mo(t)&&(e=t.constructor,(Uo(e)&&(e===Wo||Mo(e.prototype))||zo(e)&&null===(e=e[qo]))&&(e=void 0)),void 0===e?Wo:e},Ko=function(t,e){return new(Go(t))(0===e?0:e)},Yo=g,Jo=ut,Xo=ue("species"),Qo=function(t){return Jo>=51||!Yo((function(){var e=[];return(e.constructor={})[Xo]=function(){return{foo:1}},1!==e[t](Boolean).foo}))},Zo=ho,tr=g,er=po,ir=Q,nr=Kt,or=xn,rr=go,ar=yo,sr=Ko,lr=Qo,cr=ut,hr=ue("isConcatSpreadable"),ur=cr>=51||!tr((function(){var t=[];return t[hr]=!1,t.concat()[0]!==t})),dr=function(t){if(!ir(t))return!1;var e=t[hr];return void 0!==e?!!e:er(t)};Zo({target:"Array",proto:!0,arity:1,forced:!ur||!lr("concat")},{concat:function(t){var e,i,n,o,r,a=nr(this),s=sr(a,0),l=0;for(e=-1,n=arguments.length;e<n;e++)if(dr(r=-1===e?a:arguments[e]))for(o=or(r),rr(l+o),i=0;i<o;i++,l++)i in r&&ar(s,l,r[i]);else rr(l+1),ar(s,l++,r);return s.length=l,s}});var pr=N,fr=E,gr=function(t){if("Function"===pr(t))return fr(t)},vr=Tt,br=b,mr=gr(gr.bind),yr=function(t,e){return vr(t),void 0===e?t:br?mr(t,e):function(){return t.apply(e,arguments)}},wr=H,Sr=Kt,xr=xn,Or=Ko,kr=E([].push),Cr=function(t){var e=1===t,i=2===t,n=3===t,o=4===t,r=6===t,a=7===t,s=5===t||r;return function(l,c,h,u){for(var d,p,f=Sr(l),g=wr(f),v=xr(g),b=yr(c,h),m=0,y=u||Or,w=e?y(l,v):i||a?y(l,0):void 0;v>m;m++)if((s||m in g)&&(p=b(d=g[m],m,f),t))if(e)w[m]=p;else if(p)switch(t){case 3:return!0;case 5:return d;case 6:return m;case 2:kr(w,d)}else switch(t){case 4:return!1;case 7:kr(w,d)}return r?-1:n||o?o:w}},Pr={forEach:Cr(0),map:Cr(1),filter:Cr(2),some:Cr(3),every:Cr(4),find:Cr(5),findIndex:Cr(6),filterReject:Cr(7)},Tr=Pr.filter;ho({target:"Array",proto:!0,forced:!Qo("filter")},{filter:function(t){return Tr(this,t,arguments.length>1?arguments[1]:void 0)}});var Ir={},Ar=jn,$r=_n,Rr=Object.keys||function(t){return Ar(t,$r)},Er=v,jr=Be,_r=Ve,Fr=Ue,Nr=K,Dr=Rr;Ir.f=Er&&!jr?Object.defineProperties:function(t,e){Fr(t);for(var i,n=Nr(e),o=Dr(e),r=o.length,a=0;r>a;)_r.f(t,i=o[a++],n[i]);return t};var Vr,Br=it("document","documentElement"),Lr=Ue,Hr=Ir,Mr=_n,Ur=ki,zr=Br,qr=Pe,Wr=Oi("IE_PROTO"),Gr=function(){},Kr=function(t){return"<script>"+t+"</"+"script>"},Yr=function(t){t.write(Kr("")),t.close();var e=t.parentWindow.Object;return t=null,e},Jr=function(){try{Vr=new ActiveXObject("htmlfile")}catch(t){}var t,e;Jr="undefined"!=typeof document?document.domain&&Vr?Yr(Vr):((e=qr("iframe")).style.display="none",zr.appendChild(e),e.src=String("javascript:"),(t=e.contentWindow.document).open(),t.write(Kr("document.F=Object")),t.close(),t.F):Yr(Vr);for(var i=Mr.length;i--;)delete Jr.prototype[Mr[i]];return Jr()};Ur[Wr]=!0;var Xr=Object.create||function(t,e){var i;return null!==t?(Gr.prototype=Lr(t),i=new Gr,Gr.prototype=null,i[Wr]=t):i=Jr(),void 0===e?i:Hr.f(i,e)},Qr=ue,Zr=Xr,ta=Ve.f,ea=Qr("unscopables"),ia=Array.prototype;void 0===ia[ea]&&ta(ia,ea,{configurable:!0,value:Zr(null)});var na=function(t){ia[ea][t]=!0},oa=ho,ra=Pr.find,aa=na,sa="find",la=!0;sa in[]&&Array(1).find((function(){la=!1})),oa({target:"Array",proto:!0,forced:la},{find:function(t){return ra(this,t,arguments.length>1?arguments[1]:void 0)}}),aa(sa);var ca=ho,ha=Pr.findIndex,ua=na,da="findIndex",pa=!0;da in[]&&Array(1).findIndex((function(){pa=!1})),ca({target:"Array",proto:!0,forced:pa},{findIndex:function(t){return ha(this,t,arguments.length>1?arguments[1]:void 0)}}),ua(da);var fa=Tn.includes,ga=na;ho({target:"Array",proto:!0,forced:g((function(){return!Array(1).includes()}))},{includes:function(t){return fa(this,t,arguments.length>1?arguments[1]:void 0)}}),ga("includes");var va=g,ba=function(t,e){var i=[][t];return!!i&&va((function(){i.call(null,e||function(){return 1},1)}))},ma=ho,ya=Tn.indexOf,wa=ba,Sa=gr([].indexOf),xa=!!Sa&&1/Sa([1],1,-0)<0;ma({target:"Array",proto:!0,forced:xa||!wa("indexOf")},{indexOf:function(t){var e=arguments.length>1?arguments[1]:void 0;return xa?Sa(this,t,e)||0:ya(this,t,e)}});var Oa,ka,Ca,Pa={},Ta=!g((function(){function t(){}return t.prototype.constructor=null,Object.getPrototypeOf(new t)!==t.prototype})),Ia=Xt,Aa=J,$a=Kt,Ra=Ta,Ea=Oi("IE_PROTO"),ja=Object,_a=ja.prototype,Fa=Ra?ja.getPrototypeOf:function(t){var e=$a(t);if(Ia(e,Ea))return e[Ea];var i=e.constructor;return Aa(i)&&e instanceof i?i.prototype:e instanceof ja?_a:null},Na=g,Da=J,Va=Q,Ba=Fa,La=ln,Ha=ue("iterator"),Ma=!1;[].keys&&("next"in(Ca=[].keys())?(ka=Ba(Ba(Ca)))!==Object.prototype&&(Oa=ka):Ma=!0);var Ua=!Va(Oa)||Na((function(){var t={};return Oa[Ha].call(t)!==t}));Ua&&(Oa={}),Da(Oa[Ha])||La(Oa,Ha,(function(){return this}));var za={IteratorPrototype:Oa,BUGGY_SAFARI_ITERATORS:Ma},qa=Ve.f,Wa=Xt,Ga=ue("toStringTag"),Ka=function(t,e,i){t&&!i&&(t=t.prototype),t&&!Wa(t,Ga)&&qa(t,Ga,{configurable:!0,value:e})},Ya=za.IteratorPrototype,Ja=Xr,Xa=T,Qa=Ka,Za=Pa,ts=function(){return this},es=E,is=Tt,ns=Q,os=function(t){return ns(t)||null===t},rs=String,as=TypeError,ss=function(t,e,i){try{return es(is(Object.getOwnPropertyDescriptor(t,e)[i]))}catch(t){}},ls=Ue,cs=function(t){if(os(t))return t;throw new as("Can't set "+rs(t)+" as a prototype")},hs=Object.setPrototypeOf||("__proto__"in{}?function(){var t,e=!1,i={};try{(t=ss(Object.prototype,"__proto__","set"))(i,[]),e=i instanceof Array}catch(t){}return function(i,n){return ls(i),cs(n),e?t(i,n):i.__proto__=n,i}}():void 0),us=ho,ds=w,ps=J,fs=function(t,e,i,n){var o=e+" Iterator";return t.prototype=Ja(Ya,{next:Xa(+!n,i)}),Qa(t,o,!1),Za[o]=ts,t},gs=Fa,vs=hs,bs=Ka,ms=ni,ys=ln,ws=Pa,Ss=hi.PROPER,xs=hi.CONFIGURABLE,Os=za.IteratorPrototype,ks=za.BUGGY_SAFARI_ITERATORS,Cs=ue("iterator"),Ps="keys",Ts="values",Is="entries",As=function(){return this},$s=K,Rs=na,Es=Pa,js=Vi,_s=Ve.f,Fs=function(t,e,i,n,o,r,a){fs(i,e,n);var s,l,c,h=function(t){if(t===o&&g)return g;if(!ks&&t&&t in p)return p[t];switch(t){case Ps:case Ts:case Is:return function(){return new i(this,t)}}return function(){return new i(this)}},u=e+" Iterator",d=!1,p=t.prototype,f=p[Cs]||p["@@iterator"]||o&&p[o],g=!ks&&f||h(o),v="Array"===e&&p.entries||f;if(v&&(s=gs(v.call(new t)))!==Object.prototype&&s.next&&(gs(s)!==Os&&(vs?vs(s,Os):ps(s[Cs])||ys(s,Cs,As)),bs(s,u,!0)),Ss&&o===Ts&&f&&f.name!==Ts&&(xs?ms(p,"name",Ts):(d=!0,g=function(){return ds(f,this)})),o)if(l={values:h(Ts),keys:r?g:h(Ps),entries:h(Is)},a)for(c in l)(ks||d||!(c in p))&&ys(p,c,l[c]);else us({target:e,proto:!0,forced:ks||d},l);return p[Cs]!==g&&ys(p,Cs,g,{name:o}),ws[e]=g,l},Ns=function(t,e){return{value:t,done:e}},Ds=v,Vs="Array Iterator",Bs=js.set,Ls=js.getterFor(Vs),Hs=Fs(Array,"Array",(function(t,e){Bs(this,{type:Vs,target:$s(t),index:0,kind:e})}),(function(){var t=Ls(this),e=t.target,i=t.index++;if(!e||i>=e.length)return t.target=void 0,Ns(void 0,!0);switch(t.kind){case"keys":return Ns(i,!1);case"values":return Ns(e[i],!1)}return Ns([i,e[i]],!1)}),"values"),Ms=Es.Arguments=Es.Array;if(Rs("keys"),Rs("values"),Rs("entries"),Ds&&"values"!==Ms.name)try{_s(Ms,"name",{value:"values"})}catch(t){}var Us=ho,zs=H,qs=K,Ws=ba,Gs=E([].join);Us({target:"Array",proto:!0,forced:zs!==Object||!Ws("join",",")},{join:function(t){return Gs(qs(this),void 0===t?",":t)}});var Ks=Pr.map;ho({target:"Array",proto:!0,forced:!Qo("map")},{map:function(t){return Ks(this,t,arguments.length>1?arguments[1]:void 0)}});var Ys=ho,Js=po,Xs=E([].reverse),Qs=[1,2];Ys({target:"Array",proto:!0,forced:String(Qs)===String(Qs.reverse())},{reverse:function(){return Js(this)&&(this.length=this.length),Xs(this)}});var Zs=E([].slice),tl=ho,el=po,il=Ho,nl=Q,ol=bn,rl=xn,al=K,sl=yo,ll=ue,cl=Zs,hl=Qo("slice"),ul=ll("species"),dl=Array,pl=Math.max;tl({target:"Array",proto:!0,forced:!hl},{slice:function(t,e){var i,n,o,r=al(this),a=rl(r),s=ol(t,a),l=ol(void 0===e?a:e,a);if(el(r)&&(i=r.constructor,(il(i)&&(i===dl||el(i.prototype))||nl(i)&&null===(i=i[ul]))&&(i=void 0),i===dl||void 0===i))return cl(r,s,l);for(n=new(void 0===i?dl:i)(pl(l-s,0)),o=0;s<l;s++,o++)s in r&&sl(n,o,r[s]);return n.length=o,n}});var fl=Ot,gl=TypeError,vl=function(t,e){if(!delete t[e])throw new gl("Cannot delete property "+fl(e)+" of "+fl(t))},bl=Io,ml=String,yl=function(t){if("Symbol"===bl(t))throw new TypeError("Cannot convert a Symbol value to a string");return ml(t)},wl=Zs,Sl=Math.floor,xl=function(t,e){var i=t.length;if(i<8)for(var n,o,r=1;r<i;){for(o=r,n=t[r];o&&e(t[o-1],n)>0;)t[o]=t[--o];o!==r++&&(t[o]=n)}else for(var a=Sl(i/2),s=xl(wl(t,0,a),e),l=xl(wl(t,a),e),c=s.length,h=l.length,u=0,d=0;u<c||d<h;)t[u+d]=u<c&&d<h?e(s[u],l[d])<=0?s[u++]:l[d++]:u<c?s[u++]:l[d++];return t},Ol=xl,kl=ot.match(/firefox\/(\d+)/i),Cl=!!kl&&+kl[1],Pl=/MSIE|Trident/.test(ot),Tl=ot.match(/AppleWebKit\/(\d+)\./),Il=!!Tl&&+Tl[1],Al=ho,$l=E,Rl=Tt,El=Kt,jl=xn,_l=vl,Fl=yl,Nl=g,Dl=Ol,Vl=ba,Bl=Cl,Ll=Pl,Hl=ut,Ml=Il,Ul=[],zl=$l(Ul.sort),ql=$l(Ul.push),Wl=Nl((function(){Ul.sort(void 0)})),Gl=Nl((function(){Ul.sort(null)})),Kl=Vl("sort"),Yl=!Nl((function(){if(Hl)return Hl<70;if(!(Bl&&Bl>3)){if(Ll)return!0;if(Ml)return Ml<603;var t,e,i,n,o="";for(t=65;t<76;t++){switch(e=String.fromCharCode(t),t){case 66:case 69:case 70:case 72:i=3;break;case 68:case 71:i=4;break;default:i=2}for(n=0;n<47;n++)Ul.push({k:e+n,v:i})}for(Ul.sort((function(t,e){return e.v-t.v})),n=0;n<Ul.length;n++)e=Ul[n].k.charAt(0),o.charAt(o.length-1)!==e&&(o+=e);return"DGBEFHACIJK"!==o}}));Al({target:"Array",proto:!0,forced:Wl||!Gl||!Kl||!Yl},{sort:function(t){void 0!==t&&Rl(t);var e=El(this);if(Yl)return void 0===t?zl(e):zl(e,t);var i,n,o=[],r=jl(e);for(n=0;n<r;n++)n in e&&ql(o,e[n]);for(Dl(o,function(t){return function(e,i){return void 0===i?-1:void 0===e?1:void 0!==t?+t(e,i)||0:Fl(e)>Fl(i)?1:-1}}(t)),i=jl(o),n=0;n<i;)e[n]=o[n++];for(;n<r;)_l(e,n++);return e}});var Jl=v,Xl=po,Ql=TypeError,Zl=Object.getOwnPropertyDescriptor,tc=Jl&&!function(){if(void 0!==this)return!0;try{Object.defineProperty([],"length",{writable:!1}).length=1}catch(t){return t instanceof TypeError}}(),ec=ho,ic=Kt,nc=bn,oc=pn,rc=xn,ac=tc?function(t,e){if(Xl(t)&&!Zl(t,"length").writable)throw new Ql("Cannot set read only .length");return t.length=e}:function(t,e){return t.length=e},sc=go,lc=Ko,cc=yo,hc=vl,uc=Qo("splice"),dc=Math.max,pc=Math.min;ec({target:"Array",proto:!0,forced:!uc},{splice:function(t,e){var i,n,o,r,a,s,l=ic(this),c=rc(l),h=nc(t,c),u=arguments.length;for(0===u?i=n=0:1===u?(i=0,n=c-h):(i=u-2,n=pc(dc(oc(e),0),c-h)),sc(c+i-n),o=lc(l,n),r=0;r<n;r++)(a=h+r)in l&&cc(o,r,l[a]);if(o.length=n,i<n){for(r=h;r<c-n;r++)s=r+i,(a=r+n)in l?l[s]=l[a]:hc(l,s);for(r=c;r>c-n+i;r--)hc(l,r-1)}else if(i>n)for(r=c-n;r>h;r--)s=r+i-1,(a=r+n-1)in l?l[s]=l[a]:hc(l,s);for(r=0;r<i;r++)l[r+h]=arguments[r+2];return ac(l,c-n+i),o}});var fc=p,gc=J,vc=Q,bc=hs,mc=function(t,e,i){var n,o;return bc&&gc(n=e.constructor)&&n!==i&&vc(o=n.prototype)&&o!==i.prototype&&bc(t,o),t},yc=E(1..valueOf),wc="\t\n\v\f\r                　\u2028\u2029\ufeff",Sc=q,xc=yl,Oc=wc,kc=E("".replace),Cc=RegExp("^["+Oc+"]+"),Pc=RegExp("(^|[^"+Oc+"])["+Oc+"]+$"),Tc=function(t){return function(e){var i=xc(Sc(e));return 1&t&&(i=kc(i,Cc,"")),2&t&&(i=kc(i,Pc,"$1")),i}},Ic={start:Tc(1),end:Tc(2),trim:Tc(3)},Ac=ho,$c=v,Rc=p,Ec=fc,jc=E,_c=io,Fc=Xt,Nc=mc,Dc=nt,Vc=St,Bc=ye,Lc=g,Hc=cn.f,Mc=f.f,Uc=Ve.f,zc=yc,qc=Ic.trim,Wc="Number",Gc=Rc.Number;Ec.Number;var Kc=Gc.prototype,Yc=Rc.TypeError,Jc=jc("".slice),Xc=jc("".charCodeAt),Qc=function(t){var e=Bc(t,"number");return"bigint"==typeof e?e:Zc(e)},Zc=function(t){var e,i,n,o,r,a,s,l,c=Bc(t,"number");if(Vc(c))throw new Yc("Cannot convert a Symbol value to a number");if("string"==typeof c&&c.length>2)if(c=qc(c),43===(e=Xc(c,0))||45===e){if(88===(i=Xc(c,2))||120===i)return NaN}else if(48===e){switch(Xc(c,1)){case 66:case 98:n=2,o=49;break;case 79:case 111:n=8,o=55;break;default:return+c}for(a=(r=Jc(c,2)).length,s=0;s<a;s++)if((l=Xc(r,s))<48||l>o)return NaN;return parseInt(r,n)}return+c},th=_c(Wc,!Gc(" 0o1")||!Gc("0b1")||Gc("+0x1")),eh=function(t){return Dc(Kc,t)&&Lc((function(){zc(t)}))},ih=function(t){var e=arguments.length<1?0:Gc(Qc(t));return eh(this)?Nc(Object(e),this,ih):e};ih.prototype=Kc,th&&(Kc.constructor=ih),Ac({global:!0,constructor:!0,wrap:!0,forced:th},{Number:ih});th&&function(t,e){for(var i,n=$c?Hc(e):"MAX_VALUE,MIN_VALUE,NaN,NEGATIVE_INFINITY,POSITIVE_INFINITY,EPSILON,MAX_SAFE_INTEGER,MIN_SAFE_INTEGER,isFinite,isInteger,isNaN,isSafeInteger,parseFloat,parseInt,fromString,range".split(","),o=0;n.length>o;o++)Fc(e,i=n[o])&&!Fc(t,i)&&Uc(t,i,Mc(e,i))}(Ec.Number,Gc);var nh=v,oh=E,rh=w,ah=g,sh=Rr,lh=Dn,ch=S,hh=Kt,uh=H,dh=Object.assign,ph=Object.defineProperty,fh=oh([].concat),gh=!dh||ah((function(){if(nh&&1!==dh({b:1},dh(ph({},"a",{enumerable:!0,get:function(){ph(this,"b",{value:3,enumerable:!1})}}),{b:2})).b)return!0;var t={},e={},i=Symbol("assign detection"),n="abcdefghijklmnopqrst";return t[i]=7,n.split("").forEach((function(t){e[t]=t})),7!==dh({},t)[i]||sh(dh({},e)).join("")!==n}))?function(t,e){for(var i=hh(t),n=arguments.length,o=1,r=lh.f,a=ch.f;n>o;)for(var s,l=uh(arguments[o++]),c=r?fh(sh(l),r(l)):sh(l),h=c.length,u=0;h>u;)s=c[u++],nh&&!rh(a,l,s)||(i[s]=l[s]);return i}:dh,vh=gh;ho({target:"Object",stat:!0,arity:2,forced:Object.assign!==vh},{assign:vh});var bh=v,mh=g,yh=E,wh=Fa,Sh=Rr,xh=K,Oh=yh(S.f),kh=yh([].push),Ch=bh&&mh((function(){var t=Object.create(null);return t[2]=2,!Oh(t,2)})),Ph=function(t){return function(e){for(var i,n=xh(e),o=Sh(n),r=Ch&&null===wh(n),a=o.length,s=0,l=[];a>s;)i=o[s++],bh&&!(r?i in n:Oh(n,i))||kh(l,t?[i,n[i]]:n[i]);return l}},Th={entries:Ph(!0),values:Ph(!1)}.entries;ho({target:"Object",stat:!0},{entries:function(t){return Th(t)}});var Ih=Kt,Ah=Rr;ho({target:"Object",stat:!0,forced:g((function(){Ah(1)}))},{keys:function(t){return Ah(Ih(t))}});var $h=Io,Rh=So?{}.toString:function(){return"[object "+$h(this)+"]"};So||ln(Object.prototype,"toString",Rh,{unsafe:!0});var Eh=p,jh=g,_h=yl,Fh=Ic.trim,Nh=E("".charAt),Dh=Eh.parseFloat,Vh=Eh.Symbol,Bh=Vh&&Vh.iterator,Lh=1/Dh("\t\n\v\f\r                　\u2028\u2029\ufeff-0")!=-1/0||Bh&&!jh((function(){Dh(Object(Bh))}))?function(t){var e=Fh(_h(t)),i=Dh(e);return 0===i&&"-"===Nh(e,0)?-0:i}:Dh;ho({global:!0,forced:parseFloat!==Lh},{parseFloat:Lh});var Hh=p,Mh=g,Uh=E,zh=yl,qh=Ic.trim,Wh=wc,Gh=Hh.parseInt,Kh=Hh.Symbol,Yh=Kh&&Kh.iterator,Jh=/^[+-]?0x/i,Xh=Uh(Jh.exec),Qh=8!==Gh(Wh+"08")||22!==Gh(Wh+"0x16")||Yh&&!Mh((function(){Gh(Object(Yh))}))?function(t,e){var i=qh(zh(t));return Gh(i,e>>>0||(Xh(Jh,i)?16:10))}:Gh;ho({global:!0,forced:parseInt!==Qh},{parseInt:Qh});var Zh=Q,tu=N,eu=ue("match"),iu=function(t){var e;return Zh(t)&&(void 0!==(e=t[eu])?!!e:"RegExp"===tu(t))},nu=Ue,ou=function(){var t=nu(this),e="";return t.hasIndices&&(e+="d"),t.global&&(e+="g"),t.ignoreCase&&(e+="i"),t.multiline&&(e+="m"),t.dotAll&&(e+="s"),t.unicode&&(e+="u"),t.unicodeSets&&(e+="v"),t.sticky&&(e+="y"),e},ru=w,au=Xt,su=nt,lu=ou,cu=RegExp.prototype,hu=function(t){var e=t.flags;return void 0!==e||"flags"in cu||au(t,"flags")||!su(cu,t)?e:ru(lu,t)},uu=g,du=p.RegExp,pu=uu((function(){var t=du("a","y");return t.lastIndex=2,null!==t.exec("abcd")})),fu=pu||uu((function(){return!du("a","y").sticky})),gu={BROKEN_CARET:pu||uu((function(){var t=du("^r","gy");return t.lastIndex=2,null!==t.exec("str")})),MISSED_STICKY:fu,UNSUPPORTED_Y:pu},vu=Ve.f,bu=nn,mu=Ve,yu=it,wu=function(t,e,i){return i.get&&bu(i.get,e,{getter:!0}),i.set&&bu(i.set,e,{setter:!0}),mu.f(t,e,i)},Su=v,xu=ue("species"),Ou=g,ku=p.RegExp,Cu=Ou((function(){var t=ku(".","s");return!(t.dotAll&&t.test("\n")&&"s"===t.flags)})),Pu=g,Tu=p.RegExp,Iu=Pu((function(){var t=Tu("(?<a>b)","g");return"b"!==t.exec("b").groups.a||"bc"!=="b".replace(t,"$<a>c")})),Au=v,$u=p,Ru=E,Eu=io,ju=mc,_u=ni,Fu=Xr,Nu=cn.f,Du=nt,Vu=iu,Bu=yl,Lu=hu,Hu=gu,Mu=function(t,e,i){i in t||vu(t,i,{configurable:!0,get:function(){return e[i]},set:function(t){e[i]=t}})},Uu=ln,zu=g,qu=Xt,Wu=Vi.enforce,Gu=function(t){var e=yu(t);Su&&e&&!e[xu]&&wu(e,xu,{configurable:!0,get:function(){return this}})},Ku=Cu,Yu=Iu,Ju=ue("match"),Xu=$u.RegExp,Qu=Xu.prototype,Zu=$u.SyntaxError,td=Ru(Qu.exec),ed=Ru("".charAt),id=Ru("".replace),nd=Ru("".indexOf),od=Ru("".slice),rd=/^\?<[^\s\d!#%&*+<=>@^][^\s!#%&*+<=>@^]*>/,ad=/a/g,sd=/a/g,ld=new Xu(ad)!==ad,cd=Hu.MISSED_STICKY,hd=Hu.UNSUPPORTED_Y,ud=Au&&(!ld||cd||Ku||Yu||zu((function(){return sd[Ju]=!1,Xu(ad)!==ad||Xu(sd)===sd||"/a/i"!==String(Xu(ad,"i"))})));if(Eu("RegExp",ud)){for(var dd=function(t,e){var i,n,o,r,a,s,l=Du(Qu,this),c=Vu(t),h=void 0===e,u=[],d=t;if(!l&&c&&h&&t.constructor===dd)return t;if((c||Du(Qu,t))&&(t=t.source,h&&(e=Lu(d))),t=void 0===t?"":Bu(t),e=void 0===e?"":Bu(e),d=t,Ku&&"dotAll"in ad&&(n=!!e&&nd(e,"s")>-1)&&(e=id(e,/s/g,"")),i=e,cd&&"sticky"in ad&&(o=!!e&&nd(e,"y")>-1)&&hd&&(e=id(e,/y/g,"")),Yu&&(r=function(t){for(var e,i=t.length,n=0,o="",r=[],a=Fu(null),s=!1,l=!1,c=0,h="";n<=i;n++){if("\\"===(e=ed(t,n)))e+=ed(t,++n);else if("]"===e)s=!1;else if(!s)switch(!0){case"["===e:s=!0;break;case"("===e:td(rd,od(t,n+1))&&(n+=2,l=!0),o+=e,c++;continue;case">"===e&&l:if(""===h||qu(a,h))throw new Zu("Invalid capture group name");a[h]=!0,r[r.length]=[h,c],l=!1,h="";continue}l?h+=e:o+=e}return[o,r]}(t),t=r[0],u=r[1]),a=ju(Xu(t,e),l?this:Qu,dd),(n||o||u.length)&&(s=Wu(a),n&&(s.dotAll=!0,s.raw=dd(function(t){for(var e,i=t.length,n=0,o="",r=!1;n<=i;n++)"\\"!==(e=ed(t,n))?r||"."!==e?("["===e?r=!0:"]"===e&&(r=!1),o+=e):o+="[\\s\\S]":o+=e+ed(t,++n);return o}(t),i)),o&&(s.sticky=!0),u.length&&(s.groups=u)),t!==d)try{_u(a,"source",""===d?"(?:)":d)}catch(t){}return a},pd=Nu(Xu),fd=0;pd.length>fd;)Mu(dd,Xu,pd[fd++]);Qu.constructor=dd,dd.prototype=Qu,Uu($u,"RegExp",dd,{constructor:!0})}Gu("RegExp");var gd=w,vd=E,bd=yl,md=ou,yd=gu,wd=Xr,Sd=Vi.get,xd=Cu,Od=Iu,kd=qt("native-string-replace",String.prototype.replace),Cd=RegExp.prototype.exec,Pd=Cd,Td=vd("".charAt),Id=vd("".indexOf),Ad=vd("".replace),$d=vd("".slice),Rd=function(){var t=/a/,e=/b*/g;return gd(Cd,t,"a"),gd(Cd,e,"a"),0!==t.lastIndex||0!==e.lastIndex}(),Ed=yd.BROKEN_CARET,jd=void 0!==/()??/.exec("")[1];(Rd||jd||Ed||xd||Od)&&(Pd=function(t){var e,i,n,o,r,a,s,l=this,c=Sd(l),h=bd(t),u=c.raw;if(u)return u.lastIndex=l.lastIndex,e=gd(Pd,u,h),l.lastIndex=u.lastIndex,e;var d=c.groups,p=Ed&&l.sticky,f=gd(md,l),g=l.source,v=0,b=h;if(p&&(f=Ad(f,"y",""),-1===Id(f,"g")&&(f+="g"),b=$d(h,l.lastIndex),l.lastIndex>0&&(!l.multiline||l.multiline&&"\n"!==Td(h,l.lastIndex-1))&&(g="(?: "+g+")",b=" "+b,v++),i=new RegExp("^(?:"+g+")",f)),jd&&(i=new RegExp("^"+g+"$(?!\\s)",f)),Rd&&(n=l.lastIndex),o=gd(Cd,p?i:l,b),p?o?(o.input=$d(o.input,v),o[0]=$d(o[0],v),o.index=l.lastIndex,l.lastIndex+=o[0].length):l.lastIndex=0:Rd&&o&&(l.lastIndex=l.global?o.index+o[0].length:n),jd&&o&&o.length>1&&gd(kd,o[0],i,(function(){for(r=1;r<arguments.length-2;r++)void 0===arguments[r]&&(o[r]=void 0)})),o&&d)for(o.groups=a=wd(null),r=0;r<d.length;r++)a[(s=d[r])[0]]=o[s[1]];return o});var _d=Pd;ho({target:"RegExp",proto:!0,forced:/./.exec!==_d},{exec:_d});var Fd=hi.PROPER,Nd=ln,Dd=Ue,Vd=yl,Bd=g,Ld=hu,Hd="toString",Md=RegExp.prototype,Ud=Md.toString,zd=Bd((function(){return"/a/b"!==Ud.call({source:"a",flags:"b"})})),qd=Fd&&Ud.name!==Hd;(zd||qd)&&Nd(Md,Hd,(function(){var t=Dd(this);return"/"+Vd(t.source)+"/"+Vd(Ld(t))}),{unsafe:!0});var Wd=iu,Gd=TypeError,Kd=function(t){if(Wd(t))throw new Gd("The method doesn't accept regular expressions");return t},Yd=ue("match"),Jd=function(t){var e=/./;try{"/./"[t](e)}catch(i){try{return e[Yd]=!1,"/./"[t](e)}catch(t){}}return!1},Xd=ho,Qd=Kd,Zd=q,tp=yl,ep=Jd,ip=E("".indexOf);Xd({target:"String",proto:!0,forced:!ep("includes")},{includes:function(t){return!!~ip(tp(Zd(this)),tp(Qd(t)),arguments.length>1?arguments[1]:void 0)}});var np=b,op=Function.prototype,rp=op.apply,ap=op.call,sp="object"==typeof Reflect&&Reflect.apply||(np?ap.bind(rp):function(){return ap.apply(rp,arguments)}),lp=w,cp=ln,hp=_d,up=g,dp=ue,pp=ni,fp=dp("species"),gp=RegExp.prototype,vp=function(t,e,i,n){var o=dp(t),r=!up((function(){var e={};return e[o]=function(){return 7},7!==""[t](e)})),a=r&&!up((function(){var e=!1,i=/a/;return"split"===t&&((i={}).constructor={},i.constructor[fp]=function(){return i},i.flags="",i[o]=/./[o]),i.exec=function(){return e=!0,null},i[o](""),!e}));if(!r||!a||i){var s=/./[o],l=e(o,""[t],(function(t,e,i,n,o){var a=e.exec;return a===hp||a===gp.exec?r&&!o?{done:!0,value:lp(s,e,i,n)}:{done:!0,value:lp(t,i,e,n)}:{done:!1}}));cp(String.prototype,t,l[0]),cp(gp,o,l[1])}n&&pp(gp[o],"sham",!0)},bp=E,mp=pn,yp=yl,wp=q,Sp=bp("".charAt),xp=bp("".charCodeAt),Op=bp("".slice),kp=function(t){return function(e,i){var n,o,r=yp(wp(e)),a=mp(i),s=r.length;return a<0||a>=s?t?"":void 0:(n=xp(r,a))<55296||n>56319||a+1===s||(o=xp(r,a+1))<56320||o>57343?t?Sp(r,a):n:t?Op(r,a,a+2):o-56320+(n-55296<<10)+65536}},Cp={codeAt:kp(!1),charAt:kp(!0)}.charAt,Pp=function(t,e,i){return e+(i?Cp(t,e).length:1)},Tp=E,Ip=Kt,Ap=Math.floor,$p=Tp("".charAt),Rp=Tp("".replace),Ep=Tp("".slice),jp=/\$([$&'`]|\d{1,2}|<[^>]*>)/g,_p=/\$([$&'`]|\d{1,2})/g,Fp=w,Np=Ue,Dp=J,Vp=N,Bp=_d,Lp=TypeError,Hp=function(t,e){var i=t.exec;if(Dp(i)){var n=Fp(i,t,e);return null!==n&&Np(n),n}if("RegExp"===Vp(t))return Fp(Bp,t,e);throw new Lp("RegExp#exec called on incompatible receiver")},Mp=sp,Up=w,zp=E,qp=vp,Wp=g,Gp=Ue,Kp=J,Yp=M,Jp=pn,Xp=wn,Qp=yl,Zp=q,tf=Pp,ef=$t,nf=function(t,e,i,n,o,r){var a=i+t.length,s=n.length,l=_p;return void 0!==o&&(o=Ip(o),l=jp),Rp(r,l,(function(r,l){var c;switch($p(l,0)){case"$":return"$";case"&":return t;case"`":return Ep(e,0,i);case"'":return Ep(e,a);case"<":c=o[Ep(l,1,-1)];break;default:var h=+l;if(0===h)return r;if(h>s){var u=Ap(h/10);return 0===u?r:u<=s?void 0===n[u-1]?$p(l,1):n[u-1]+$p(l,1):r}c=n[h-1]}return void 0===c?"":c}))},of=Hp,rf=ue("replace"),af=Math.max,sf=Math.min,lf=zp([].concat),cf=zp([].push),hf=zp("".indexOf),uf=zp("".slice),df="$0"==="a".replace(/./,"$0"),pf=!!/./[rf]&&""===/./[rf]("a","$0");qp("replace",(function(t,e,i){var n=pf?"$":"$0";return[function(t,i){var n=Zp(this),o=Yp(t)?void 0:ef(t,rf);return o?Up(o,t,n,i):Up(e,Qp(n),t,i)},function(t,o){var r=Gp(this),a=Qp(t);if("string"==typeof o&&-1===hf(o,n)&&-1===hf(o,"$<")){var s=i(e,r,a,o);if(s.done)return s.value}var l=Kp(o);l||(o=Qp(o));var c,h=r.global;h&&(c=r.unicode,r.lastIndex=0);for(var u,d=[];null!==(u=of(r,a))&&(cf(d,u),h);){""===Qp(u[0])&&(r.lastIndex=tf(a,Xp(r.lastIndex),c))}for(var p,f="",g=0,v=0;v<d.length;v++){for(var b,m=Qp((u=d[v])[0]),y=af(sf(Jp(u.index),a.length),0),w=[],S=1;S<u.length;S++)cf(w,void 0===(p=u[S])?p:String(p));var x=u.groups;if(l){var O=lf([m],w,y,a);void 0!==x&&cf(O,x),b=Qp(Mp(o,void 0,O))}else b=nf(m,a,y,w,x,o);y>=g&&(f+=uf(a,g,y)+b,g=y+m.length)}return f+uf(a,g)}]}),!!Wp((function(){var t=/./;return t.exec=function(){var t=[];return t.groups={a:"7"},t},"7"!=="".replace(t,"$<a>")}))||!df||pf);var ff=Object.is||function(t,e){return t===e?0!==t||1/t==1/e:t!=t&&e!=e},gf=w,vf=Ue,bf=M,mf=q,yf=ff,wf=yl,Sf=$t,xf=Hp;vp("search",(function(t,e,i){return[function(e){var i=mf(this),n=bf(e)?void 0:Sf(e,t);return n?gf(n,e,i):new RegExp(e)[t](wf(i))},function(t){var n=vf(this),o=wf(t),r=i(e,n,o);if(r.done)return r.value;var a=n.lastIndex;yf(a,0)||(n.lastIndex=0);var s=xf(n,o);return yf(n.lastIndex,a)||(n.lastIndex=a),null===s?-1:s.index}]}));var Of=Ho,kf=Ot,Cf=TypeError,Pf=Ue,Tf=function(t){if(Of(t))return t;throw new Cf(kf(t)+" is not a constructor")},If=M,Af=ue("species"),$f=w,Rf=E,Ef=vp,jf=Ue,_f=M,Ff=q,Nf=function(t,e){var i,n=Pf(t).constructor;return void 0===n||If(i=Pf(n)[Af])?e:Tf(i)},Df=Pp,Vf=wn,Bf=yl,Lf=$t,Hf=Hp,Mf=g,Uf=gu.UNSUPPORTED_Y,zf=Math.min,qf=Rf([].push),Wf=Rf("".slice),Gf=!Mf((function(){var t=/(?:)/,e=t.exec;t.exec=function(){return e.apply(this,arguments)};var i="ab".split(t);return 2!==i.length||"a"!==i[0]||"b"!==i[1]})),Kf="c"==="abbc".split(/(b)*/)[1]||4!=="test".split(/(?:)/,-1).length||2!=="ab".split(/(?:ab)*/).length||4!==".".split(/(.?)(.?)/).length||".".split(/()()/).length>1||"".split(/.?/).length;Ef("split",(function(t,e,i){var n="0".split(void 0,0).length?function(t,i){return void 0===t&&0===i?[]:$f(e,this,t,i)}:e;return[function(e,i){var o=Ff(this),r=_f(e)?void 0:Lf(e,t);return r?$f(r,e,o,i):$f(n,Bf(o),e,i)},function(t,o){var r=jf(this),a=Bf(t);if(!Kf){var s=i(n,r,a,o,n!==e);if(s.done)return s.value}var l=Nf(r,RegExp),c=r.unicode,h=(r.ignoreCase?"i":"")+(r.multiline?"m":"")+(r.unicode?"u":"")+(Uf?"g":"y"),u=new l(Uf?"^(?:"+r.source+")":r,h),d=void 0===o?4294967295:o>>>0;if(0===d)return[];if(0===a.length)return null===Hf(u,a)?[a]:[];for(var p=0,f=0,g=[];f<a.length;){u.lastIndex=Uf?0:f;var v,b=Hf(u,Uf?Wf(a,f):a);if(null===b||(v=zf(Vf(u.lastIndex+(Uf?f:0)),a.length))===p)f=Df(a,f,c);else{if(qf(g,Wf(a,p,f)),g.length===d)return g;for(var m=1;m<=b.length-1;m++)if(qf(g,b[m]),g.length===d)return g;f=p=v}}return qf(g,Wf(a,p)),g}]}),Kf||!Gf,Uf);var Yf=hi.PROPER,Jf=g,Xf=wc,Qf=Ic.trim;ho({target:"String",proto:!0,forced:function(t){return Jf((function(){return!!Xf[t]()||"​᠎"!=="​᠎"[t]()||Yf&&Xf[t].name!==t}))}("trim")},{trim:function(){return Qf(this)}});var Zf={CSSRuleList:0,CSSStyleDeclaration:0,CSSValueList:0,ClientRectList:0,DOMRectList:0,DOMStringList:0,DOMTokenList:1,DataTransferItemList:0,FileList:0,HTMLAllCollection:0,HTMLCollection:0,HTMLFormElement:0,HTMLSelectElement:0,MediaList:0,MimeTypeArray:0,NamedNodeMap:0,NodeList:1,PaintRequestList:0,Plugin:0,PluginArray:0,SVGLengthList:0,SVGNumberList:0,SVGPathSegList:0,SVGPointList:0,SVGStringList:0,SVGTransformList:0,SourceBufferList:0,StyleSheetList:0,TextTrackCueList:0,TextTrackList:0,TouchList:0},tg=Pe("span").classList,eg=tg&&tg.constructor&&tg.constructor.prototype,ig=eg===Object.prototype?void 0:eg,ng=Pr.forEach,og=ba("forEach")?[].forEach:function(t){return ng(this,t,arguments.length>1?arguments[1]:void 0)},rg=p,ag=Zf,sg=ig,lg=og,cg=ni,hg=function(t){if(t&&t.forEach!==lg)try{cg(t,"forEach",lg)}catch(e){t.forEach=lg}};for(var ug in ag)ag[ug]&&hg(rg[ug]&&rg[ug].prototype);hg(sg);var dg=p,pg=Zf,fg=ig,gg=Hs,vg=ni,bg=Ka,mg=ue("iterator"),yg=gg.values,wg=function(t,e){if(t){if(t[mg]!==yg)try{vg(t,mg,yg)}catch(e){t[mg]=yg}if(bg(t,e,!0),pg[e])for(var i in gg)if(t[i]!==gg[i])try{vg(t,i,gg[i])}catch(e){t[i]=gg[i]}}};for(var Sg in pg)wg(dg[Sg]&&dg[Sg].prototype,Sg);wg(fg,"DOMTokenList");var xg=Kt,Og=Fa,kg=Ta;ho({target:"Object",stat:!0,forced:g((function(){Og(1)})),sham:!kg},{getPrototypeOf:function(t){return Og(xg(t))}});var Cg,Pg=ho,Tg=gr,Ig=f.f,Ag=wn,$g=yl,Rg=Kd,Eg=q,jg=Jd,_g=Tg("".slice),Fg=Math.min,Ng=jg("endsWith");Pg({target:"String",proto:!0,forced:!!(Ng||(Cg=Ig(String.prototype,"endsWith"),!Cg||Cg.writable))&&!Ng},{endsWith:function(t){var e=$g(Eg(this));Rg(t);var i=arguments.length>1?arguments[1]:void 0,n=e.length,o=void 0===i?n:Fg(Ag(i),n),r=$g(t);return _g(e,o-r.length,o)===r}});var Dg=w,Vg=Ue,Bg=M,Lg=wn,Hg=yl,Mg=q,Ug=$t,zg=Pp,qg=Hp;vp("match",(function(t,e,i){return[function(e){var i=Mg(this),n=Bg(e)?void 0:Ug(e,t);return n?Dg(n,e,i):new RegExp(e)[t](Hg(i))},function(t){var n=Vg(this),o=Hg(t),r=i(e,n,o);if(r.done)return r.value;if(!n.global)return qg(n,o);var a=n.unicode;n.lastIndex=0;for(var s,l=[],c=0;null!==(s=qg(n,o));){var h=Hg(s[0]);l[c]=h,""===h&&(n.lastIndex=zg(o,Lg(n.lastIndex),a)),c++}return 0===c?null:l}]}));var Wg=ho,Gg=gr,Kg=f.f,Yg=wn,Jg=yl,Xg=Kd,Qg=q,Zg=Jd,tv=Gg("".slice),ev=Math.min,iv=Zg("startsWith"),nv=!iv&&!!function(){var t=Kg(String.prototype,"startsWith");return t&&!t.writable}();Wg({target:"String",proto:!0,forced:!nv&&!iv},{startsWith:function(t){var e=Jg(Qg(this));Xg(t);var i=Yg(ev(arguments.length>1?arguments[1]:void 0,e.length)),n=Jg(t);return tv(e,i,i+n.length)===n}});var ov={getBootstrapVersion:function(){var e=5;try{var i=t.fn.dropdown.Constructor.VERSION;void 0!==i&&(e=parseInt(i,10))}catch(t){}try{var n=bootstrap.Tooltip.VERSION;void 0!==n&&(e=parseInt(n,10))}catch(t){}return e},getIconsPrefix:function(t){return{bootstrap3:"glyphicon",bootstrap4:"fa",bootstrap5:"bi","bootstrap-table":"icon",bulma:"fa",foundation:"fa",materialize:"material-icons",semantic:"fa"}[t]||"fa"},getIcons:function(t){return{glyphicon:{paginationSwitchDown:"glyphicon-collapse-down icon-chevron-down",paginationSwitchUp:"glyphicon-collapse-up icon-chevron-up",refresh:"glyphicon-refresh icon-refresh",toggleOff:"glyphicon-list-alt icon-list-alt",toggleOn:"glyphicon-list-alt icon-list-alt",columns:"glyphicon-th icon-th",detailOpen:"glyphicon-plus icon-plus",detailClose:"glyphicon-minus icon-minus",fullscreen:"glyphicon-fullscreen",search:"glyphicon-search",clearSearch:"glyphicon-trash"},fa:{paginationSwitchDown:"fa-caret-square-down",paginationSwitchUp:"fa-caret-square-up",refresh:"fa-sync",toggleOff:"fa-toggle-off",toggleOn:"fa-toggle-on",columns:"fa-th-list",detailOpen:"fa-plus",detailClose:"fa-minus",fullscreen:"fa-arrows-alt",search:"fa-search",clearSearch:"fa-trash"},bi:{paginationSwitchDown:"bi-caret-down-square",paginationSwitchUp:"bi-caret-up-square",refresh:"bi-arrow-clockwise",toggleOff:"bi-toggle-off",toggleOn:"bi-toggle-on",columns:"bi-list-ul",detailOpen:"bi-plus",detailClose:"bi-dash",fullscreen:"bi-arrows-move",search:"bi-search",clearSearch:"bi-trash"},icon:{paginationSwitchDown:"icon-arrow-up-circle",paginationSwitchUp:"icon-arrow-down-circle",refresh:"icon-refresh-cw",toggleOff:"icon-toggle-right",toggleOn:"icon-toggle-right",columns:"icon-list",detailOpen:"icon-plus",detailClose:"icon-minus",fullscreen:"icon-maximize",search:"icon-search",clearSearch:"icon-trash-2"},"material-icons":{paginationSwitchDown:"grid_on",paginationSwitchUp:"grid_off",refresh:"refresh",toggleOff:"tablet",toggleOn:"tablet_android",columns:"view_list",detailOpen:"add",detailClose:"remove",fullscreen:"fullscreen",sort:"sort",search:"search",clearSearch:"delete"}}[t]||{}},getSearchInput:function(e){return"string"==typeof e.options.searchSelector?t(e.options.searchSelector):e.$toolbar.find(".search input")},extend:function(){for(var t=this,e=arguments.length,n=new Array(e),o=0;o<e;o++)n[o]=arguments[o];var r,a=n[0]||{},s=1,l=!1;for("boolean"==typeof a&&(l=a,a=n[s]||{},s++),"object"!==i(a)&&"function"!=typeof a&&(a={});s<n.length;s++){var c=n[s];if(null!=c)for(var h in c){var u=c[h];if("__proto__"!==h&&a!==u){var d=Array.isArray(u);if(l&&u&&(this.isObject(u)||d)){var p=a[h];if(d&&Array.isArray(p)&&p.every((function(e){return!t.isObject(e)&&!Array.isArray(e)}))){a[h]=u;continue}r=d&&!Array.isArray(p)?[]:d||this.isObject(p)?p:{},a[h]=this.extend(l,r,u)}else void 0!==u&&(a[h]=u)}}}return a},sprintf:function(t){for(var e=arguments.length,i=new Array(e>1?e-1:0),n=1;n<e;n++)i[n-1]=arguments[n];var o=!0,r=0,a=t.replace(/%s/g,(function(){var t=i[r++];return void 0===t?(o=!1,""):t}));return o?a:""},isObject:function(t){if("object"!==i(t)||null===t)return!1;for(var e=t;null!==Object.getPrototypeOf(e);)e=Object.getPrototypeOf(e);return Object.getPrototypeOf(t)===e},isEmptyObject:function(){var t=arguments.length>0&&void 0!==arguments[0]?arguments[0]:{};return 0===Object.entries(t).length&&t.constructor===Object},isNumeric:function(t){return!isNaN(parseFloat(t))&&isFinite(t)},getFieldTitle:function(t,e){var i,n=h(t);try{for(n.s();!(i=n.n()).done;){var o=i.value;if(o.field===e)return o.title}}catch(t){n.e(t)}finally{n.f()}return""},setFieldIndex:function(t){var e,i=0,n=[],o=h(t[0]);try{for(o.s();!(e=o.n()).done;){i+=e.value.colspan||1}}catch(t){o.e(t)}finally{o.f()}for(var r=0;r<t.length;r++){n[r]=[];for(var a=0;a<i;a++)n[r][a]=!1}for(var s=0;s<t.length;s++){var l,c=h(t[s]);try{for(c.s();!(l=c.n()).done;){var u=l.value,d=u.rowspan||1,p=u.colspan||1,f=n[s].indexOf(!1);u.colspanIndex=f,1===p?(u.fieldIndex=f,void 0===u.field&&(u.field=f)):u.colspanGroup=u.colspan;for(var g=0;g<d;g++)for(var v=0;v<p;v++)n[s+g][f+v]=!0}}catch(t){c.e(t)}finally{c.f()}}},normalizeAccent:function(t){return"string"!=typeof t?t:t.normalize("NFD").replace(/[\u0300-\u036f]/g,"")},updateFieldGroup:function(t,e){var i,n,o=(i=[]).concat.apply(i,s(t)),r=h(t);try{for(r.s();!(n=r.n()).done;){var a,l=h(n.value);try{for(l.s();!(a=l.n()).done;){var c=a.value;if(c.colspanGroup>1){for(var u=0,d=function(t){var e=o.filter((function(e){return e.fieldIndex===t})),i=e[e.length-1];if(e.length>1)for(var n=0;n<e.length-1;n++)e[n].visible=i.visible;i.visible&&u++},p=c.colspanIndex;p<c.colspanIndex+c.colspanGroup;p++)d(p);c.colspan=u,c.visible=u>0}}}catch(t){l.e(t)}finally{l.f()}}}catch(t){r.e(t)}finally{r.f()}if(!(t.length<2)){var f,g=h(e);try{var v=function(){var t=f.value,e=o.filter((function(e){return e.fieldIndex===t.fieldIndex}));if(e.length>1){var i,n=h(e);try{for(n.s();!(i=n.n()).done;){i.value.visible=t.visible}}catch(t){n.e(t)}finally{n.f()}}};for(g.s();!(f=g.n()).done;)v()}catch(t){g.e(t)}finally{g.f()}}},getScrollBarWidth:function(){if(void 0===this.cachedWidth){var e=t("<div/>").addClass("fixed-table-scroll-inner"),i=t("<div/>").addClass("fixed-table-scroll-outer");i.append(e),t("body").append(i);var n=e[0].offsetWidth;i.css("overflow","scroll");var o=e[0].offsetWidth;n===o&&(o=i[0].clientWidth),i.remove(),this.cachedWidth=n-o}return this.cachedWidth},calculateObjectValue:function(t,e,n,o){var r=e;if("string"==typeof e){var a=e.split(".");if(a.length>1){r=window;var l,c=h(a);try{for(c.s();!(l=c.n()).done;){r=r[l.value]}}catch(t){c.e(t)}finally{c.f()}}else r=window[e]}return null!==r&&"object"===i(r)?r:"function"==typeof r?r.apply(t,n||[]):!r&&"string"==typeof e&&n&&this.sprintf.apply(this,[e].concat(s(n)))?this.sprintf.apply(this,[e].concat(s(n))):o},compareObjects:function(t,e,i){var n=Object.keys(t),o=Object.keys(e);if(i&&n.length!==o.length)return!1;for(var r=0,a=n;r<a.length;r++){var s=a[r];if(o.includes(s)&&t[s]!==e[s])return!1}return!0},regexCompare:function(t,e){try{var i=e.match(/^\/(.*?)\/([gim]*)$/);if(-1!==t.toString().search(i?new RegExp(i[1],i[2]):new RegExp(e,"gim")))return!0}catch(t){return!1}return!1},escapeApostrophe:function(t){return t.toString().replace(/'/g,"&#39;")},escapeHTML:function(t){return t?t.toString().replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;").replace(/"/g,"&quot;").replace(/'/g,"&#39;"):t},unescapeHTML:function(t){return"string"==typeof t&&t?t.toString().replace(/&amp;/g,"&").replace(/&lt;/g,"<").replace(/&gt;/g,">").replace(/&quot;/g,'"').replace(/&#39;/g,"'"):t},removeHTML:function(t){return t?t.toString().replace(/(<([^>]+)>)/gi,"").replace(/&[#A-Za-z0-9]+;/gi,"").trim():t},getRealDataAttr:function(t){for(var e=0,i=Object.entries(t);e<i.length;e++){var n=a(i[e],2),o=n[0],r=n[1],s=o.split(/(?=[A-Z])/).join("-").toLowerCase();s!==o&&(t[s]=r,delete t[o])}return t},getItemField:function(t,e,i){var n=arguments.length>3&&void 0!==arguments[3]?arguments[3]:void 0,o=t;if(void 0!==n&&(i=n),"string"!=typeof e||t.hasOwnProperty(e))return i?this.escapeHTML(t[e]):t[e];var r,a=e.split("."),s=h(a);try{for(s.s();!(r=s.n()).done;){var l=r.value;o=o&&o[l]}}catch(t){s.e(t)}finally{s.f()}return i?this.escapeHTML(o):o},isIEBrowser:function(){return navigator.userAgent.includes("MSIE ")||/Trident.*rv:11\./.test(navigator.userAgent)},findIndex:function(t,e){var i,n=h(t);try{for(n.s();!(i=n.n()).done;){var o=i.value;if(JSON.stringify(o)===JSON.stringify(e))return t.indexOf(o)}}catch(t){n.e(t)}finally{n.f()}return-1},trToData:function(e,i){var n=this,o=[],r=[];return i.each((function(i,a){var s=t(a),l={};l._id=s.attr("id"),l._class=s.attr("class"),l._data=n.getRealDataAttr(s.data()),l._style=s.attr("style"),s.find(">td,>th").each((function(o,a){for(var s=t(a),c=+s.attr("colspan")||1,h=+s.attr("rowspan")||1,u=o;r[i]&&r[i][u];u++);for(var d=u;d<u+c;d++)for(var p=i;p<i+h;p++)r[p]||(r[p]=[]),r[p][d]=!0;var f=e[u].field;l[f]=n.escapeApostrophe(s.html().trim()),l["_".concat(f,"_id")]=s.attr("id"),l["_".concat(f,"_class")]=s.attr("class"),l["_".concat(f,"_rowspan")]=s.attr("rowspan"),l["_".concat(f,"_colspan")]=s.attr("colspan"),l["_".concat(f,"_title")]=s.attr("title"),l["_".concat(f,"_data")]=n.getRealDataAttr(s.data()),l["_".concat(f,"_style")]=s.attr("style")})),o.push(l)})),o},sort:function(t,e,i,n,o,r){if(null==t&&(t=""),null==e&&(e=""),n.sortStable&&t===e&&(t=o,e=r),this.isNumeric(t)&&this.isNumeric(e))return(t=parseFloat(t))<(e=parseFloat(e))?-1*i:t>e?i:0;if(n.sortEmptyLast){if(""===t)return 1;if(""===e)return-1}return t===e?0:("string"!=typeof t&&(t=t.toString()),-1===t.localeCompare(e)?-1*i:i)},getEventName:function(t){var e=arguments.length>1&&void 0!==arguments[1]?arguments[1]:"";return e=e||"".concat(+new Date).concat(~~(1e6*Math.random())),"".concat(t,"-").concat(e)},hasDetailViewIcon:function(t){return t.detailView&&t.detailViewIcon&&!t.cardView},getDetailViewIndexOffset:function(t){return this.hasDetailViewIcon(t)&&"right"!==t.detailViewAlign?1:0},checkAutoMergeCells:function(t){var e,i=h(t);try{for(i.s();!(e=i.n()).done;)for(var n=e.value,o=0,r=Object.keys(n);o<r.length;o++){var a=r[o];if(a.startsWith("_")&&(a.endsWith("_rowspan")||a.endsWith("_colspan")))return!0}}catch(t){i.e(t)}finally{i.f()}return!1},deepCopy:function(t){return void 0===t?t:this.extend(!0,Array.isArray(t)?[]:{},t)},debounce:function(t,e,i){var n;return function(){var o=this,r=arguments,a=function(){n=null,i||t.apply(o,r)},s=i&&!n;clearTimeout(n),n=setTimeout(a,e),s&&t.apply(o,r)}}},rv=ov.getBootstrapVersion(),av={3:{classes:{buttonsPrefix:"btn",buttons:"default",buttonsGroup:"btn-group",buttonsDropdown:"btn-group",pull:"pull",inputGroup:"input-group",inputPrefix:"input-",input:"form-control",select:"form-control",paginationDropdown:"btn-group dropdown",dropup:"dropup",dropdownActive:"active",paginationActive:"active",buttonActive:"active"},html:{toolbarDropdown:['<ul class="dropdown-menu" role="menu">',"</ul>"],toolbarDropdownItem:'<li class="dropdown-item-marker" role="menuitem"><label>%s</label></li>',toolbarDropdownSeparator:'<li class="divider"></li>',pageDropdown:['<ul class="dropdown-menu" role="menu">',"</ul>"],pageDropdownItem:'<li role="menuitem" class="%s"><a href="#">%s</a></li>',dropdownCaret:'<span class="caret"></span>',pagination:['<ul class="pagination%s">',"</ul>"],paginationItem:'<li class="page-item%s"><a class="page-link" aria-label="%s" href="javascript:void(0)">%s</a></li>',icon:'<i class="%s %s"></i>',inputGroup:'<div class="input-group">%s<span class="input-group-btn">%s</span></div>',searchInput:'<input class="%s%s" type="text" placeholder="%s">',searchButton:'<button class="%s" type="button" name="search" title="%s">%s %s</button>',searchClearButton:'<button class="%s" type="button" name="clearSearch" title="%s">%s %s</button>'}},4:{classes:{buttonsPrefix:"btn",buttons:"secondary",buttonsGroup:"btn-group",buttonsDropdown:"btn-group",pull:"float",inputGroup:"btn-group",inputPrefix:"form-control-",input:"form-control",select:"form-control",paginationDropdown:"btn-group dropdown",dropup:"dropup",dropdownActive:"active",paginationActive:"active",buttonActive:"active"},html:{toolbarDropdown:['<div class="dropdown-menu dropdown-menu-right">',"</div>"],toolbarDropdownItem:'<label class="dropdown-item dropdown-item-marker">%s</label>',pageDropdown:['<div class="dropdown-menu">',"</div>"],pageDropdownItem:'<a class="dropdown-item %s" href="#">%s</a>',toolbarDropdownSeparator:'<div class="dropdown-divider"></div>',dropdownCaret:'<span class="caret"></span>',pagination:['<ul class="pagination%s">',"</ul>"],paginationItem:'<li class="page-item%s"><a class="page-link" aria-label="%s" href="javascript:void(0)">%s</a></li>',icon:'<i class="%s %s"></i>',inputGroup:'<div class="input-group">%s<div class="input-group-append">%s</div></div>',searchInput:'<input class="%s%s" type="text" placeholder="%s">',searchButton:'<button class="%s" type="button" name="search" title="%s">%s %s</button>',searchClearButton:'<button class="%s" type="button" name="clearSearch" title="%s">%s %s</button>'}},5:{classes:{buttonsPrefix:"btn",buttons:"secondary",buttonsGroup:"btn-group",buttonsDropdown:"btn-group",pull:"float",inputGroup:"btn-group",inputPrefix:"form-control-",input:"form-control",select:"form-select",paginationDropdown:"btn-group dropdown",dropup:"dropup",dropdownActive:"active",paginationActive:"active",buttonActive:"active"},html:{dataToggle:"data-bs-toggle",toolbarDropdown:['<div class="dropdown-menu dropdown-menu-end">',"</div>"],toolbarDropdownItem:'<label class="dropdown-item dropdown-item-marker">%s</label>',pageDropdown:['<div class="dropdown-menu">',"</div>"],pageDropdownItem:'<a class="dropdown-item %s" href="#">%s</a>',toolbarDropdownSeparator:'<div class="dropdown-divider"></div>',dropdownCaret:'<span class="caret"></span>',pagination:['<ul class="pagination%s">',"</ul>"],paginationItem:'<li class="page-item%s"><a class="page-link" aria-label="%s" href="javascript:void(0)">%s</a></li>',icon:'<i class="%s %s"></i>',inputGroup:'<div class="input-group">%s%s</div>',searchInput:'<input class="%s%s" type="text" placeholder="%s">',searchButton:'<button class="%s" type="button" name="search" title="%s">%s %s</button>',searchClearButton:'<button class="%s" type="button" name="clearSearch" title="%s">%s %s</button>'}}}[rv],sv={height:void 0,classes:"table table-bordered table-hover",buttons:{},theadClasses:"",headerStyle:function(t){return{}},rowStyle:function(t,e){return{}},rowAttributes:function(t,e){return{}},undefinedText:"-",locale:void 0,virtualScroll:!1,virtualScrollItemHeight:void 0,sortable:!0,sortClass:void 0,silentSort:!0,sortEmptyLast:!1,sortName:void 0,sortOrder:void 0,sortReset:!1,sortStable:!1,sortResetPage:!1,rememberOrder:!1,serverSort:!0,customSort:void 0,columns:[[]],data:[],url:void 0,method:"get",cache:!0,contentType:"application/json",dataType:"json",ajax:void 0,ajaxOptions:{},queryParams:function(t){return t},queryParamsType:"limit",responseHandler:function(t){return t},totalField:"total",totalNotFilteredField:"totalNotFiltered",dataField:"rows",footerField:"footer",pagination:!1,paginationParts:["pageInfo","pageSize","pageList"],showExtendedPagination:!1,paginationLoop:!0,sidePagination:"client",totalRows:0,totalNotFiltered:0,pageNumber:1,pageSize:10,pageList:[10,25,50,100],paginationHAlign:"right",paginationVAlign:"bottom",paginationDetailHAlign:"left",paginationPreText:"&lsaquo;",paginationNextText:"&rsaquo;",paginationSuccessivelySize:5,paginationPagesBySide:1,paginationUseIntermediate:!1,paginationLoadMore:!1,search:!1,searchable:!1,searchHighlight:!1,searchOnEnterKey:!1,strictSearch:!1,regexSearch:!1,searchSelector:!1,visibleSearch:!1,showButtonIcons:!0,showButtonText:!1,showSearchButton:!1,showSearchClearButton:!1,trimOnSearch:!0,searchAlign:"right",searchTimeOut:500,searchText:"",customSearch:void 0,showHeader:!0,showFooter:!1,footerStyle:function(t){return{}},searchAccentNeutralise:!1,showColumns:!1,showColumnsToggleAll:!1,showColumnsSearch:!1,minimumCountColumns:1,showPaginationSwitch:!1,showRefresh:!1,showToggle:!1,showFullscreen:!1,smartDisplay:!0,escape:!1,escapeTitle:!0,filterOptions:{filterAlgorithm:"and"},idField:void 0,selectItemName:"btSelectItem",clickToSelect:!1,ignoreClickToSelectOn:function(t){var e=t.tagName;return["A","BUTTON"].includes(e)},singleSelect:!1,checkboxHeader:!0,maintainMetaData:!1,multipleSelectRow:!1,uniqueId:void 0,cardView:!1,detailView:!1,detailViewIcon:!0,detailViewByClick:!1,detailViewAlign:"left",detailFormatter:function(t,e){return""},detailFilter:function(t,e){return!0},toolbar:void 0,toolbarAlign:"left",buttonsToolbar:void 0,buttonsAlign:"right",buttonsOrder:["paginationSwitch","refresh","toggle","fullscreen","columns"],buttonsPrefix:av.classes.buttonsPrefix,buttonsClass:av.classes.buttons,iconsPrefix:void 0,icons:{},iconSize:void 0,fixedScroll:!1,loadingFontSize:"auto",loadingTemplate:function(t){return'<span class="loading-wrap">\n      <span class="loading-text">'.concat(t,'</span>\n      <span class="animation-wrap"><span class="animation-dot"></span></span>\n      </span>\n    ')},onAll:function(t,e){return!1},onClickCell:function(t,e,i,n){return!1},onDblClickCell:function(t,e,i,n){return!1},onClickRow:function(t,e){return!1},onDblClickRow:function(t,e){return!1},onSort:function(t,e){return!1},onCheck:function(t){return!1},onUncheck:function(t){return!1},onCheckAll:function(t){return!1},onUncheckAll:function(t){return!1},onCheckSome:function(t){return!1},onUncheckSome:function(t){return!1},onLoadSuccess:function(t){return!1},onLoadError:function(t){return!1},onColumnSwitch:function(t,e){return!1},onColumnSwitchAll:function(t){return!1},onPageChange:function(t,e){return!1},onSearch:function(t){return!1},onToggle:function(t){return!1},onPreBody:function(t){return!1},onPostBody:function(){return!1},onPostHeader:function(){return!1},onPostFooter:function(){return!1},onExpandRow:function(t,e,i){return!1},onCollapseRow:function(t,e){return!1},onRefreshOptions:function(t){return!1},onRefresh:function(t){return!1},onResetView:function(){return!1},onScrollBody:function(){return!1},onTogglePagination:function(t){return!1},onVirtualScroll:function(t,e){return!1}},lv={formatLoadingMessage:function(){return"Loading, please wait"},formatRecordsPerPage:function(t){return"".concat(t," rows per page")},formatShowingRows:function(t,e,i,n){return void 0!==n&&n>0&&n>i?"Showing ".concat(t," to ").concat(e," of ").concat(i," rows (filtered from ").concat(n," total rows)"):"Showing ".concat(t," to ").concat(e," of ").concat(i," rows")},formatSRPaginationPreText:function(){return"previous page"},formatSRPaginationPageText:function(t){return"to page ".concat(t)},formatSRPaginationNextText:function(){return"next page"},formatDetailPagination:function(t){return"Showing ".concat(t," rows")},formatSearch:function(){return"Search"},formatClearSearch:function(){return"Clear Search"},formatNoMatches:function(){return"No matching records found"},formatPaginationSwitch:function(){return"Hide/Show pagination"},formatPaginationSwitchDown:function(){return"Show pagination"},formatPaginationSwitchUp:function(){return"Hide pagination"},formatRefresh:function(){return"Refresh"},formatToggleOn:function(){return"Show card view"},formatToggleOff:function(){return"Hide card view"},formatColumns:function(){return"Columns"},formatColumnsToggleAll:function(){return"Toggle all"},formatFullscreen:function(){return"Fullscreen"},formatAllRows:function(){return"All"}},cv={field:void 0,title:void 0,titleTooltip:void 0,class:void 0,width:void 0,widthUnit:"px",rowspan:void 0,colspan:void 0,align:void 0,halign:void 0,falign:void 0,valign:void 0,cellStyle:void 0,radio:!1,checkbox:!1,checkboxEnabled:!0,clickToSelect:!0,showSelectTitle:!1,sortable:!1,sortName:void 0,order:"asc",sorter:void 0,visible:!0,switchable:!0,switchableLabel:void 0,cardVisible:!0,searchable:!0,formatter:void 0,footerFormatter:void 0,footerStyle:void 0,detailFormatter:void 0,searchFormatter:!0,searchHighlightFormatter:!1,escape:void 0,events:void 0};Object.assign(sv,lv);var hv={VERSION:"1.22.4",THEME:"bootstrap".concat(rv),CONSTANTS:av,DEFAULTS:sv,COLUMN_DEFAULTS:cv,METHODS:["getOptions","refreshOptions","getData","getSelections","load","append","prepend","remove","removeAll","insertRow","updateRow","getRowByUniqueId","updateByUniqueId","removeByUniqueId","updateCell","updateCellByUniqueId","showRow","hideRow","getHiddenRows","showColumn","hideColumn","getVisibleColumns","getHiddenColumns","showAllColumns","hideAllColumns","mergeCells","checkAll","uncheckAll","checkInvert","check","uncheck","checkBy","uncheckBy","refresh","destroy","resetView","showLoading","hideLoading","togglePagination","toggleFullscreen","toggleView","resetSearch","filterBy","sortBy","scrollTo","getScrollPosition","selectPage","prevPage","nextPage","toggleDetailView","expandRow","collapseRow","expandRowByUniqueId","collapseRowByUniqueId","expandAllRows","collapseAllRows","updateColumnTitle","updateFormatText"],EVENTS:{"all.bs.table":"onAll","click-row.bs.table":"onClickRow","dbl-click-row.bs.table":"onDblClickRow","click-cell.bs.table":"onClickCell","dbl-click-cell.bs.table":"onDblClickCell","sort.bs.table":"onSort","check.bs.table":"onCheck","uncheck.bs.table":"onUncheck","check-all.bs.table":"onCheckAll","uncheck-all.bs.table":"onUncheckAll","check-some.bs.table":"onCheckSome","uncheck-some.bs.table":"onUncheckSome","load-success.bs.table":"onLoadSuccess","load-error.bs.table":"onLoadError","column-switch.bs.table":"onColumnSwitch","column-switch-all.bs.table":"onColumnSwitchAll","page-change.bs.table":"onPageChange","search.bs.table":"onSearch","toggle.bs.table":"onToggle","pre-body.bs.table":"onPreBody","post-body.bs.table":"onPostBody","post-header.bs.table":"onPostHeader","post-footer.bs.table":"onPostFooter","expand-row.bs.table":"onExpandRow","collapse-row.bs.table":"onCollapseRow","refresh-options.bs.table":"onRefreshOptions","reset-view.bs.table":"onResetView","refresh.bs.table":"onRefresh","scroll-body.bs.table":"onScrollBody","toggle-pagination.bs.table":"onTogglePagination","virtual-scroll.bs.table":"onVirtualScroll"},LOCALES:{en:lv,"en-US":lv}},uv=function(){function t(e){var i=this;n(this,t),this.rows=e.rows,this.scrollEl=e.scrollEl,this.contentEl=e.contentEl,this.callback=e.callback,this.itemHeight=e.itemHeight,this.cache={},this.scrollTop=this.scrollEl.scrollTop,this.initDOM(this.rows,e.fixedScroll),this.scrollEl.scrollTop=this.scrollTop,this.lastCluster=0;var o=function(){i.lastCluster!==(i.lastCluster=i.getNum())&&(i.initDOM(i.rows),i.callback(i.startIndex,i.endIndex))};this.scrollEl.addEventListener("scroll",o,!1),this.destroy=function(){i.contentEl.innerHtml="",i.scrollEl.removeEventListener("scroll",o,!1)}}return r(t,[{key:"initDOM",value:function(t,e){void 0===this.clusterHeight&&(this.cache.scrollTop=this.scrollEl.scrollTop,this.cache.data=this.contentEl.innerHTML=t[0]+t[0]+t[0],this.getRowsHeight(t));var i=this.initData(t,this.getNum(e)),n=i.rows.join(""),o=this.checkChanges("data",n),r=this.checkChanges("top",i.topOffset),a=this.checkChanges("bottom",i.bottomOffset),s=[];o&&r?(i.topOffset&&s.push(this.getExtra("top",i.topOffset)),s.push(n),i.bottomOffset&&s.push(this.getExtra("bottom",i.bottomOffset)),this.startIndex=i.start,this.endIndex=i.end,this.contentEl.innerHTML=s.join(""),e&&(this.contentEl.scrollTop=this.cache.scrollTop)):a&&(this.contentEl.lastChild.style.height="".concat(i.bottomOffset,"px"))}},{key:"getRowsHeight",value:function(){if(void 0===this.itemHeight){var t=this.contentEl.children,e=t[Math.floor(t.length/2)];this.itemHeight=e.offsetHeight}this.blockHeight=50*this.itemHeight,this.clusterRows=200,this.clusterHeight=4*this.blockHeight}},{key:"getNum",value:function(t){return this.scrollTop=t?this.cache.scrollTop:this.scrollEl.scrollTop,Math.floor(this.scrollTop/(this.clusterHeight-this.blockHeight))||0}},{key:"initData",value:function(t,e){if(t.length<50)return{topOffset:0,bottomOffset:0,rowsAbove:0,rows:t};var i=Math.max((this.clusterRows-50)*e,0),n=i+this.clusterRows,o=Math.max(i*this.itemHeight,0),r=Math.max((t.length-n)*this.itemHeight,0),a=[],s=i;o<1&&s++;for(var l=i;l<n;l++)t[l]&&a.push(t[l]);return{start:i,end:n,topOffset:o,bottomOffset:r,rowsAbove:s,rows:a}}},{key:"checkChanges",value:function(t,e){var i=e!==this.cache[t];return this.cache[t]=e,i}},{key:"getExtra",value:function(t,e){var i=document.createElement("tr");return i.className="virtual-scroll-".concat(t),e&&(i.style.height="".concat(e,"px")),i.outerHTML}}]),t}(),dv=function(){function e(i,o){n(this,e),this.options=o,this.$el=t(i),this.$el_=this.$el.clone(),this.timeoutId_=0,this.timeoutFooter_=0}return r(e,[{key:"init",value:function(){this.initConstants(),this.initLocale(),this.initContainer(),this.initTable(),this.initHeader(),this.initData(),this.initHiddenRows(),this.initToolbar(),this.initPagination(),this.initBody(),this.initSearchText(),this.initServer()}},{key:"initConstants",value:function(){var e=this.options;this.constants=hv.CONSTANTS,this.constants.theme=t.fn.bootstrapTable.theme,this.constants.dataToggle=this.constants.html.dataToggle||"data-toggle";var n=ov.getIconsPrefix(t.fn.bootstrapTable.theme);"string"==typeof e.icons&&(e.icons=ov.calculateObjectValue(null,e.icons)),e.iconsPrefix=e.iconsPrefix||t.fn.bootstrapTable.defaults.iconsPrefix||n,e.icons=Object.assign(ov.getIcons(e.iconsPrefix),t.fn.bootstrapTable.defaults.icons,e.icons);var o=e.buttonsPrefix?"".concat(e.buttonsPrefix,"-"):"";this.constants.buttonsClass=[e.buttonsPrefix,o+e.buttonsClass,ov.sprintf("".concat(o,"%s"),e.iconSize)].join(" ").trim(),this.buttons=ov.calculateObjectValue(this,e.buttons,[],{}),"object"!==i(this.buttons)&&(this.buttons={})}},{key:"initLocale",value:function(){if(this.options.locale){var i=t.fn.bootstrapTable.locales,n=this.options.locale.split(/-|_/);n[0]=n[0].toLowerCase(),n[1]&&(n[1]=n[1].toUpperCase());var o={};i[this.options.locale]?o=i[this.options.locale]:i[n.join("-")]?o=i[n.join("-")]:i[n[0]]&&(o=i[n[0]]),this._defaultLocales=this._defaultLocales||{};for(var r=0,s=Object.entries(o);r<s.length;r++){var l=a(s[r],2),c=l[0],h=l[1],u=this._defaultLocales.hasOwnProperty(c)?this._defaultLocales[c]:e.DEFAULTS[c];this.options[c]===u&&(this.options[c]=h,this._defaultLocales[c]=h)}}}},{key:"initContainer",value:function(){var e=["top","both"].includes(this.options.paginationVAlign)?'<div class="fixed-table-pagination clearfix"></div>':"",i=["bottom","both"].includes(this.options.paginationVAlign)?'<div class="fixed-table-pagination"></div>':"",n=ov.calculateObjectValue(this.options,this.options.loadingTemplate,[this.options.formatLoadingMessage()]);this.$container=t('\n      <div class="bootstrap-table '.concat(this.constants.theme,'">\n      <div class="fixed-table-toolbar"></div>\n      ').concat(e,'\n      <div class="fixed-table-container">\n      <div class="fixed-table-header"><table></table></div>\n      <div class="fixed-table-body">\n      <div class="fixed-table-loading">\n      ').concat(n,'\n      </div>\n      </div>\n      <div class="fixed-table-footer"></div>\n      </div>\n      ').concat(i,"\n      </div>\n    ")),this.$container.insertAfter(this.$el),this.$tableContainer=this.$container.find(".fixed-table-container"),this.$tableHeader=this.$container.find(".fixed-table-header"),this.$tableBody=this.$container.find(".fixed-table-body"),this.$tableLoading=this.$container.find(".fixed-table-loading"),this.$tableFooter=this.$el.find("tfoot"),this.options.buttonsToolbar?this.$toolbar=t("body").find(this.options.buttonsToolbar):this.$toolbar=this.$container.find(".fixed-table-toolbar"),this.$pagination=this.$container.find(".fixed-table-pagination"),this.$tableBody.append(this.$el),this.$container.after('<div class="clearfix"></div>'),this.$el.addClass(this.options.classes),this.$tableLoading.addClass(this.options.classes),this.options.height&&(this.$tableContainer.addClass("fixed-height"),this.options.showFooter&&this.$tableContainer.addClass("has-footer"),this.options.classes.split(" ").includes("table-bordered")&&(this.$tableBody.append('<div class="fixed-table-border"></div>'),this.$tableBorder=this.$tableBody.find(".fixed-table-border"),this.$tableLoading.addClass("fixed-table-border")),this.$tableFooter=this.$container.find(".fixed-table-footer"))}},{key:"initTable",value:function(){var i=this,n=[];if(this.$header=this.$el.find(">thead"),this.$header.length?this.options.theadClasses&&this.$header.addClass(this.options.theadClasses):this.$header=t('<thead class="'.concat(this.options.theadClasses,'"></thead>')).appendTo(this.$el),this._headerTrClasses=[],this._headerTrStyles=[],this.$header.find("tr").each((function(e,o){var r=t(o),a=[];r.find("th").each((function(e,i){var n=t(i);void 0!==n.data("field")&&n.data("field","".concat(n.data("field")));var o=Object.assign({},n.data());for(var r in o)t.fn.bootstrapTable.columnDefaults.hasOwnProperty(r)&&delete o[r];a.push(ov.extend({},{_data:ov.getRealDataAttr(o),title:n.html(),class:n.attr("class"),titleTooltip:n.attr("title"),rowspan:n.attr("rowspan")?+n.attr("rowspan"):void 0,colspan:n.attr("colspan")?+n.attr("colspan"):void 0},n.data()))})),n.push(a),r.attr("class")&&i._headerTrClasses.push(r.attr("class")),r.attr("style")&&i._headerTrStyles.push(r.attr("style"))})),Array.isArray(this.options.columns[0])||(this.options.columns=[this.options.columns]),this.options.columns=ov.extend(!0,[],n,this.options.columns),this.columns=[],this.fieldsColumnsIndex=[],ov.setFieldIndex(this.options.columns),this.options.columns.forEach((function(t,n){t.forEach((function(t,o){var r=ov.extend({},e.COLUMN_DEFAULTS,t,{passed:t});void 0!==r.fieldIndex&&(i.columns[r.fieldIndex]=r,i.fieldsColumnsIndex[r.field]=r.fieldIndex),i.options.columns[n][o]=r}))})),!this.options.data.length){var o=ov.trToData(this.columns,this.$el.find(">tbody>tr"));o.length&&(this.options.data=o,this.fromHtml=!0)}this.options.pagination&&"server"!==this.options.sidePagination||(this.footerData=ov.trToData(this.columns,this.$el.find(">tfoot>tr"))),this.footerData&&this.$el.find("tfoot").html("<tr></tr>"),!this.options.showFooter||this.options.cardView?this.$tableFooter.hide():this.$tableFooter.show()}},{key:"initHeader",value:function(){var e=this,n={},o=[];this.header={fields:[],styles:[],classes:[],formatters:[],detailFormatters:[],events:[],sorters:[],sortNames:[],cellStyles:[],searchables:[]},ov.updateFieldGroup(this.options.columns,this.columns),this.options.columns.forEach((function(t,r){var s=[];s.push("<tr".concat(ov.sprintf(' class="%s"',e._headerTrClasses[r])," ").concat(ov.sprintf(' style="%s"',e._headerTrStyles[r]),">"));var l="";if(0===r&&ov.hasDetailViewIcon(e.options)){var c=e.options.columns.length>1?' rowspan="'.concat(e.options.columns.length,'"'):"";l='<th class="detail"'.concat(c,'>\n          <div class="fht-cell"></div>\n          </th>')}l&&"right"!==e.options.detailViewAlign&&s.push(l),t.forEach((function(t,o){var l=ov.sprintf(' class="%s"',t.class),c=t.widthUnit,h=parseFloat(t.width),u=t.halign?t.halign:t.align,d=ov.sprintf("text-align: %s; ",u),p=ov.sprintf("text-align: %s; ",t.align),f=ov.sprintf("vertical-align: %s; ",t.valign);if(f+=ov.sprintf("width: %s; ",!t.checkbox&&!t.radio||h?h?h+c:void 0:t.showSelectTitle?void 0:"36px"),void 0!==t.fieldIndex||t.visible){var g=ov.calculateObjectValue(null,e.options.headerStyle,[t]),v=[],b=[],m="";if(g&&g.css)for(var y=0,w=Object.entries(g.css);y<w.length;y++){var S=a(w[y],2),x=S[0],O=S[1];v.push("".concat(x,": ").concat(O))}if(g&&g.classes&&(m=ov.sprintf(' class="%s"',t.class?[t.class,g.classes].join(" "):g.classes)),void 0!==t.fieldIndex){if(e.header.fields[t.fieldIndex]=t.field,e.header.styles[t.fieldIndex]=p+f,e.header.classes[t.fieldIndex]=l,e.header.formatters[t.fieldIndex]=t.formatter,e.header.detailFormatters[t.fieldIndex]=t.detailFormatter,e.header.events[t.fieldIndex]=t.events,e.header.sorters[t.fieldIndex]=t.sorter,e.header.sortNames[t.fieldIndex]=t.sortName,e.header.cellStyles[t.fieldIndex]=t.cellStyle,e.header.searchables[t.fieldIndex]=t.searchable,!t.visible)return;if(e.options.cardView&&!t.cardVisible)return;n[t.field]=t}if(Object.keys(t._data||{}).length>0)for(var k=0,C=Object.entries(t._data);k<C.length;k++){var P=a(C[k],2),T=P[0],I=P[1];b.push("data-".concat(T,"='").concat("object"===i(I)?JSON.stringify(I):I,"'"))}s.push("<th".concat(ov.sprintf(' title="%s"',t.titleTooltip)),t.checkbox||t.radio?ov.sprintf(' class="bs-checkbox %s"',t.class||""):m||l,ov.sprintf(' style="%s"',d+f+v.join("; ")||void 0),ov.sprintf(' rowspan="%s"',t.rowspan),ov.sprintf(' colspan="%s"',t.colspan),ov.sprintf(' data-field="%s"',t.field),0===o&&r>0?" data-not-first-th":"",b.length>0?b.join(" "):"",">"),s.push(ov.sprintf('<div class="th-inner %s">',e.options.sortable&&t.sortable?"sortable".concat("center"===u?" sortable-center":""," both"):""));var A=e.options.escape&&e.options.escapeTitle?ov.escapeHTML(t.title):t.title,$=A;t.checkbox&&(A="",!e.options.singleSelect&&e.options.checkboxHeader&&(A='<label><input name="btSelectAll" type="checkbox" /><span></span></label>'),e.header.stateField=t.field),t.radio&&(A="",e.header.stateField=t.field),!A&&t.showSelectTitle&&(A+=$),s.push(A),s.push("</div>"),s.push('<div class="fht-cell"></div>'),s.push("</div>"),s.push("</th>")}})),l&&"right"===e.options.detailViewAlign&&s.push(l),s.push("</tr>"),s.length>3&&o.push(s.join(""))})),this.$header.html(o.join("")),this.$header.find("th[data-field]").each((function(e,i){t(i).data(n[t(i).data("field")])})),this.$container.off("click",".th-inner").on("click",".th-inner",(function(i){var n=t(i.currentTarget);if(e.options.detailView&&!n.parent().hasClass("bs-checkbox")&&n.closest(".bootstrap-table")[0]!==e.$container[0])return!1;e.options.sortable&&n.parent().data().sortable&&e.onSort(i)}));var r=ov.getEventName("resize.bootstrap-table",this.$el.attr("id"));t(window).off(r),!this.options.showHeader||this.options.cardView?(this.$header.hide(),this.$tableHeader.hide(),this.$tableLoading.css("top",0)):(this.$header.show(),this.$tableHeader.show(),this.$tableLoading.css("top",this.$header.outerHeight()+1),this.getCaret(),t(window).on(r,(function(){return e.resetView()}))),this.$selectAll=this.$header.find('[name="btSelectAll"]'),this.$selectAll.off("click").on("click",(function(i){i.stopPropagation();var n=t(i.currentTarget).prop("checked");e[n?"checkAll":"uncheckAll"](),e.updateSelected()}))}},{key:"initData",value:function(t,e){"append"===e?this.options.data=this.options.data.concat(t):"prepend"===e?this.options.data=[].concat(t).concat(this.options.data):(t=t||ov.deepCopy(this.options.data),this.options.data=Array.isArray(t)?t:t[this.options.dataField]),this.data=s(this.options.data),this.options.sortReset&&(this.unsortedData=s(this.data)),"server"!==this.options.sidePagination&&this.initSort()}},{key:"initSort",value:function(){var t=this,e=this.options.sortName,i="desc"===this.options.sortOrder?-1:1,n=this.header.fields.indexOf(this.options.sortName),o=0;-1!==n?(this.options.sortStable&&this.data.forEach((function(t,e){t.hasOwnProperty("_position")||(t._position=e)})),this.options.customSort?ov.calculateObjectValue(this.options,this.options.customSort,[this.options.sortName,this.options.sortOrder,this.data]):this.data.sort((function(o,r){t.header.sortNames[n]&&(e=t.header.sortNames[n]);var a=ov.getItemField(o,e,t.options.escape),s=ov.getItemField(r,e,t.options.escape),l=ov.calculateObjectValue(t.header,t.header.sorters[n],[a,s,o,r]);return void 0!==l?t.options.sortStable&&0===l?i*(o._position-r._position):i*l:ov.sort(a,s,i,t.options,o._position,r._position)})),void 0!==this.options.sortClass&&(clearTimeout(o),o=setTimeout((function(){t.$el.removeClass(t.options.sortClass);var e=t.$header.find('[data-field="'.concat(t.options.sortName,'"]')).index();t.$el.find("tr td:nth-child(".concat(e+1,")")).addClass(t.options.sortClass)}),250))):this.options.sortReset&&(this.data=s(this.unsortedData))}},{key:"sortBy",value:function(t){this.options.sortName=t.field,this.options.sortOrder=t.hasOwnProperty("sortOrder")?t.sortOrder:"asc",this._sort()}},{key:"onSort",value:function(e){var i=e.type,n=e.currentTarget,o="keypress"===i?t(n):t(n).parent(),r=this.$header.find("th").eq(o.index());if(this.$header.add(this.$header_).find("span.order").remove(),this.options.sortName===o.data("field")){var a=this.options.sortOrder,s=this.columns[this.fieldsColumnsIndex[o.data("field")]].sortOrder||this.columns[this.fieldsColumnsIndex[o.data("field")]].order;void 0===a?this.options.sortOrder="asc":"asc"===a?this.options.sortOrder=this.options.sortReset?"asc"===s?"desc":void 0:"desc":"desc"===this.options.sortOrder&&(this.options.sortOrder=this.options.sortReset?"desc"===s?"asc":void 0:"asc"),void 0===this.options.sortOrder&&(this.options.sortName=void 0)}else this.options.sortName=o.data("field"),this.options.rememberOrder?this.options.sortOrder="asc"===o.data("order")?"desc":"asc":this.options.sortOrder=this.columns[this.fieldsColumnsIndex[o.data("field")]].sortOrder||this.columns[this.fieldsColumnsIndex[o.data("field")]].order;o.add(r).data("order",this.options.sortOrder),this.getCaret(),this._sort()}},{key:"_sort",value:function(){if("server"===this.options.sidePagination&&this.options.serverSort)return this.options.pageNumber=1,void this.initServer(this.options.silentSort);this.options.pagination&&this.options.sortResetPage&&(this.options.pageNumber=1,this.initPagination()),this.trigger("sort",this.options.sortName,this.options.sortOrder),this.initSort(),this.initBody()}},{key:"initToolbar",value:function(){var e,n=this,o=this.options,r=[],s=0,l=0;this.$toolbar.find(".bs-bars").children().length&&t("body").append(t(o.toolbar)),this.$toolbar.html(""),"string"!=typeof o.toolbar&&"object"!==i(o.toolbar)||t(ov.sprintf('<div class="bs-bars %s-%s"></div>',this.constants.classes.pull,o.toolbarAlign)).appendTo(this.$toolbar).append(t(o.toolbar)),r=['<div class="'.concat(["columns","columns-".concat(o.buttonsAlign),this.constants.classes.buttonsGroup,"".concat(this.constants.classes.pull,"-").concat(o.buttonsAlign)].join(" "),'">')],"string"==typeof o.buttonsOrder&&(o.buttonsOrder=o.buttonsOrder.replace(/\[|\]| |'/g,"").split(",")),this.buttons=Object.assign(this.buttons,{paginationSwitch:{text:o.pagination?o.formatPaginationSwitchUp():o.formatPaginationSwitchDown(),icon:o.pagination?o.icons.paginationSwitchDown:o.icons.paginationSwitchUp,render:!1,event:this.togglePagination,attributes:{"aria-label":o.formatPaginationSwitch(),title:o.formatPaginationSwitch()}},refresh:{text:o.formatRefresh(),icon:o.icons.refresh,render:!1,event:this.refresh,attributes:{"aria-label":o.formatRefresh(),title:o.formatRefresh()}},toggle:{text:o.formatToggleOn(),icon:o.icons.toggleOff,render:!1,event:this.toggleView,attributes:{"aria-label":o.formatToggleOn(),title:o.formatToggleOn()}},fullscreen:{text:o.formatFullscreen(),icon:o.icons.fullscreen,render:!1,event:this.toggleFullscreen,attributes:{"aria-label":o.formatFullscreen(),title:o.formatFullscreen()}},columns:{render:!1,html:function(){var t=[];if(t.push('<div class="keep-open '.concat(n.constants.classes.buttonsDropdown,'">\n            <button class="').concat(n.constants.buttonsClass,' dropdown-toggle" type="button" ').concat(n.constants.dataToggle,'="dropdown"\n            aria-label="').concat(o.formatColumns(),'" title="').concat(o.formatColumns(),'">\n            ').concat(o.showButtonIcons?ov.sprintf(n.constants.html.icon,o.iconsPrefix,o.icons.columns):"","\n            ").concat(o.showButtonText?o.formatColumns():"","\n            ").concat(n.constants.html.dropdownCaret,"\n            </button>\n            ").concat(n.constants.html.toolbarDropdown[0])),o.showColumnsSearch&&(t.push(ov.sprintf(n.constants.html.toolbarDropdownItem,ov.sprintf('<input type="text" class="%s" name="columnsSearch" placeholder="%s" autocomplete="off">',n.constants.classes.input,o.formatSearch()))),t.push(n.constants.html.toolbarDropdownSeparator)),o.showColumnsToggleAll){var e=n.getVisibleColumns().length===n.columns.filter((function(t){return!n.isSelectionColumn(t)})).length;t.push(ov.sprintf(n.constants.html.toolbarDropdownItem,ov.sprintf('<input type="checkbox" class="toggle-all" %s> <span>%s</span>',e?'checked="checked"':"",o.formatColumnsToggleAll()))),t.push(n.constants.html.toolbarDropdownSeparator)}var i=0;return n.columns.forEach((function(t){t.visible&&i++})),n.columns.forEach((function(e,r){if(!n.isSelectionColumn(e)&&(!o.cardView||e.cardVisible)){var a=e.visible?' checked="checked"':"",s=i<=o.minimumCountColumns&&a?' disabled="disabled"':"";e.switchable&&(t.push(ov.sprintf(n.constants.html.toolbarDropdownItem,ov.sprintf('<input type="checkbox" data-field="%s" value="%s"%s%s> <span>%s</span>',e.field,r,a,s,e.switchableLabel?e.switchableLabel:e.title))),l++)}})),t.push(n.constants.html.toolbarDropdown[1],"</div>"),t.join("")}}});for(var c={},u=0,d=Object.entries(this.buttons);u<d.length;u++){var p=a(d[u],2),f=p[0],g=p[1],v=void 0;if(g.hasOwnProperty("html"))"function"==typeof g.html?v=g.html():"string"==typeof g.html&&(v=g.html);else{var b=this.constants.buttonsClass;if(g.hasOwnProperty("attributes")&&g.attributes.class&&(b+=" ".concat(g.attributes.class)),v='<button class="'.concat(b,'" type="button" name="').concat(f,'"'),g.hasOwnProperty("attributes"))for(var m=0,y=Object.entries(g.attributes);m<y.length;m++){var w=a(y[m],2),S=w[0],x=w[1];"class"!==S&&(v+=" ".concat(S,'="').concat(x,'"'))}v+=">",o.showButtonIcons&&g.hasOwnProperty("icon")&&(v+="".concat(ov.sprintf(this.constants.html.icon,o.iconsPrefix,g.icon)," ")),o.showButtonText&&g.hasOwnProperty("text")&&(v+=g.text),v+="</button>"}c[f]=v;var O="show".concat(f.charAt(0).toUpperCase()).concat(f.substring(1)),k=o[O];!(!g.hasOwnProperty("render")||g.hasOwnProperty("render")&&g.render)||void 0!==k&&!0!==k||(o[O]=!0),o.buttonsOrder.includes(f)||o.buttonsOrder.push(f)}var C,P=h(o.buttonsOrder);try{for(P.s();!(C=P.n()).done;){var T=C.value;o["show".concat(T.charAt(0).toUpperCase()).concat(T.substring(1))]&&r.push(c[T])}}catch(t){P.e(t)}finally{P.f()}r.push("</div>"),(this.showToolbar||r.length>2)&&this.$toolbar.append(r.join(""));for(var I=function(){var t=a($[A],2),e=t[0],i=t[1];if(i.hasOwnProperty("event")){if("function"==typeof i.event||"string"==typeof i.event){var o="string"==typeof i.event?window[i.event]:i.event;return n.$toolbar.find('button[name="'.concat(e,'"]')).off("click").on("click",(function(){return o.call(n)})),1}for(var r=function(){var t=a(l[s],2),i=t[0],o=t[1],r="string"==typeof o?window[o]:o;n.$toolbar.find('button[name="'.concat(e,'"]')).off(i).on(i,(function(){return r.call(n)}))},s=0,l=Object.entries(i.event);s<l.length;s++)r()}},A=0,$=Object.entries(this.buttons);A<$.length;A++)I();if(o.showColumns){var R=(e=this.$toolbar.find(".keep-open")).find('input[type="checkbox"]:not(".toggle-all")'),E=e.find('input[type="checkbox"].toggle-all');if(l<=o.minimumCountColumns&&e.find("input").prop("disabled",!0),e.find("li, label").off("click").on("click",(function(t){t.stopImmediatePropagation()})),R.off("click").on("click",(function(e){var i=e.currentTarget,o=t(i);n._toggleColumn(o.val(),o.prop("checked"),!1),n.trigger("column-switch",o.data("field"),o.prop("checked")),E.prop("checked",R.filter(":checked").length===n.columns.filter((function(t){return!n.isSelectionColumn(t)})).length)})),E.off("click").on("click",(function(e){var i=e.currentTarget;n._toggleAllColumns(t(i).prop("checked")),n.trigger("column-switch-all",t(i).prop("checked"))})),o.showColumnsSearch){var j=e.find('[name="columnsSearch"]'),_=e.find(".dropdown-item-marker");j.on("keyup paste change",(function(e){var i=e.currentTarget,n=t(i).val().toLowerCase();_.show(),R.each((function(e,i){var o=t(i).parents(".dropdown-item-marker");o.text().toLowerCase().includes(n)||o.hide()}))}))}}var F=function(t){var e=t.is("select")?"change":"keyup drop blur mouseup";t.off(e).on(e,(function(t){o.searchOnEnterKey&&13!==t.keyCode||[37,38,39,40].includes(t.keyCode)||(clearTimeout(s),s=setTimeout((function(){n.onSearch({currentTarget:t.currentTarget})}),o.searchTimeOut))}))};if((o.search||this.showSearchClearButton)&&"string"!=typeof o.searchSelector){r=[];var N=ov.sprintf(this.constants.html.searchButton,this.constants.buttonsClass,o.formatSearch(),o.showButtonIcons?ov.sprintf(this.constants.html.icon,o.iconsPrefix,o.icons.search):"",o.showButtonText?o.formatSearch():""),D=ov.sprintf(this.constants.html.searchClearButton,this.constants.buttonsClass,o.formatClearSearch(),o.showButtonIcons?ov.sprintf(this.constants.html.icon,o.iconsPrefix,o.icons.clearSearch):"",o.showButtonText?o.formatClearSearch():""),V='<input class="'.concat(this.constants.classes.input,"\n        ").concat(ov.sprintf(" %s%s",this.constants.classes.inputPrefix,o.iconSize),'\n        search-input" type="search" aria-label="').concat(o.formatSearch(),'" placeholder="').concat(o.formatSearch(),'" autocomplete="off">'),B=V;if(o.showSearchButton||o.showSearchClearButton){var L=(o.showSearchButton?N:"")+(o.showSearchClearButton?D:"");B=o.search?ov.sprintf(this.constants.html.inputGroup,V,L):L}r.push(ov.sprintf('\n        <div class="'.concat(this.constants.classes.pull,"-").concat(o.searchAlign," search ").concat(this.constants.classes.inputGroup,'">\n          %s\n        </div>\n      '),B)),this.$toolbar.append(r.join(""));var H=ov.getSearchInput(this);o.showSearchButton?(this.$toolbar.find(".search button[name=search]").off("click").on("click",(function(){clearTimeout(s),s=setTimeout((function(){n.onSearch({currentTarget:H})}),o.searchTimeOut)})),o.searchOnEnterKey&&F(H)):F(H),o.showSearchClearButton&&this.$toolbar.find(".search button[name=clearSearch]").click((function(){n.resetSearch()}))}else"string"==typeof o.searchSelector&&F(ov.getSearchInput(this))}},{key:"onSearch",value:function(){var e=arguments.length>0&&void 0!==arguments[0]?arguments[0]:{},i=e.currentTarget,n=e.firedByInitSearchText,o=!(arguments.length>1&&void 0!==arguments[1])||arguments[1];if(void 0!==i&&t(i).length&&o){var r=t(i).val().trim();if(this.options.trimOnSearch&&t(i).val()!==r&&t(i).val(r),this.searchText===r)return;var a=ov.getSearchInput(this),s=i instanceof jQuery?i:t(i);(s.is(a)||s.hasClass("search-input"))&&(this.searchText=r,this.options.searchText=r)}n||(this.options.pageNumber=1),this.initSearch(),n?"client"===this.options.sidePagination&&this.updatePagination():this.updatePagination(),this.trigger("search",this.searchText)}},{key:"initSearch",value:function(){var t=this;if(this.filterOptions=this.filterOptions||this.options.filterOptions,"server"!==this.options.sidePagination){if(this.options.customSearch)return this.data=ov.calculateObjectValue(this.options,this.options.customSearch,[this.options.data,this.searchText,this.filterColumns]),this.options.sortReset&&(this.unsortedData=s(this.data)),void this.initSort();var e=this.searchText&&(this.fromHtml?ov.escapeHTML(this.searchText):this.searchText),i=e?e.toLowerCase():"",n=ov.isEmptyObject(this.filterColumns)?null:this.filterColumns;this.options.searchAccentNeutralise&&(i=ov.normalizeAccent(i)),"function"==typeof this.filterOptions.filterAlgorithm?this.data=this.options.data.filter((function(e){return t.filterOptions.filterAlgorithm.apply(null,[e,n])})):"string"==typeof this.filterOptions.filterAlgorithm&&(this.data=n?this.options.data.filter((function(e){var i=t.filterOptions.filterAlgorithm;if("and"===i){for(var o in n)if(Array.isArray(n[o])&&!n[o].includes(e[o])||!Array.isArray(n[o])&&e[o]!==n[o])return!1}else if("or"===i){var r=!1;for(var a in n)(Array.isArray(n[a])&&n[a].includes(e[a])||!Array.isArray(n[a])&&e[a]===n[a])&&(r=!0);return r}return!0})):s(this.options.data));var o=this.getVisibleFields();this.data=i?this.data.filter((function(n,r){for(var a=0;a<t.header.fields.length;a++)if(t.header.searchables[a]&&(!t.options.visibleSearch||-1!==o.indexOf(t.header.fields[a]))){var s=ov.isNumeric(t.header.fields[a])?parseInt(t.header.fields[a],10):t.header.fields[a],l=t.columns[t.fieldsColumnsIndex[s]],c=void 0;if("string"!=typeof s||n.hasOwnProperty(s))c=n[s];else{c=n;for(var h=s.split("."),u=0;u<h.length;u++){if(null===c[h[u]]){c=null;break}c=c[h[u]]}}if(t.options.searchAccentNeutralise&&(c=ov.normalizeAccent(c)),l&&l.searchFormatter&&(c=ov.calculateObjectValue(l,t.header.formatters[a],[c,n,r,l.field],c)),"string"==typeof c||"number"==typeof c){if(t.options.strictSearch&&"".concat(c).toLowerCase()===i||t.options.regexSearch&&ov.regexCompare(c,e))return!0;var d=/(?:(<=|=>|=<|>=|>|<)(?:\s+)?(-?\d+)?|(-?\d+)?(\s+)?(<=|=>|=<|>=|>|<))/gm.exec(t.searchText),p=!1;if(d){var f=d[1]||"".concat(d[5],"l"),g=d[2]||d[3],v=parseInt(c,10),b=parseInt(g,10);switch(f){case">":case"<l":p=v>b;break;case"<":case">l":p=v<b;break;case"<=":case"=<":case">=l":case"=>l":p=v<=b;break;case">=":case"=>":case"<=l":case"=<l":p=v>=b}}if(p||"".concat(c).toLowerCase().includes(i))return!0}}return!1})):this.data,this.options.sortReset&&(this.unsortedData=s(this.data)),this.initSort()}}},{key:"initPagination",value:function(){var t=this,e=this.options;if(e.pagination){this.$pagination.show();var i,n,o,r,a,s,l,c=[],h=!1,u=this.getData({includeHiddenRows:!1}),d=e.pageList;if("string"==typeof d&&(d=d.replace(/\[|\]| /g,"").toLowerCase().split(",")),d=d.map((function(t){return"string"==typeof t?t.toLowerCase()===e.formatAllRows().toLowerCase()||["all","unlimited"].includes(t.toLowerCase())?e.formatAllRows():+t:t})),this.paginationParts=e.paginationParts,"string"==typeof this.paginationParts&&(this.paginationParts=this.paginationParts.replace(/\[|\]| |'/g,"").split(",")),"server"!==e.sidePagination&&(e.totalRows=u.length),this.totalPages=0,e.totalRows&&(e.pageSize===e.formatAllRows()&&(e.pageSize=e.totalRows,h=!0),this.totalPages=1+~~((e.totalRows-1)/e.pageSize),e.totalPages=this.totalPages),this.totalPages>0&&e.pageNumber>this.totalPages&&(e.pageNumber=this.totalPages),this.pageFrom=(e.pageNumber-1)*e.pageSize+1,this.pageTo=e.pageNumber*e.pageSize,this.pageTo>e.totalRows&&(this.pageTo=e.totalRows),this.options.pagination&&"server"!==this.options.sidePagination&&(this.options.totalNotFiltered=this.options.data.length),this.options.showExtendedPagination||(this.options.totalNotFiltered=void 0),(this.paginationParts.includes("pageInfo")||this.paginationParts.includes("pageInfoShort")||this.paginationParts.includes("pageSize"))&&c.push('<div class="'.concat(this.constants.classes.pull,"-").concat(e.paginationDetailHAlign,' pagination-detail">')),this.paginationParts.includes("pageInfo")||this.paginationParts.includes("pageInfoShort")){var p=this.options.totalRows+("client"===this.options.sidePagination&&this.options.paginationLoadMore&&!this._paginationLoaded?" +":""),f=this.paginationParts.includes("pageInfoShort")?e.formatDetailPagination(p):e.formatShowingRows(this.pageFrom,this.pageTo,p,e.totalNotFiltered);c.push('<span class="pagination-info">\n      '.concat(f,"\n      </span>"))}if(this.paginationParts.includes("pageSize")){c.push('<div class="page-list">');var g=['<div class="'.concat(this.constants.classes.paginationDropdown,'">\n        <button class="').concat(this.constants.buttonsClass,' dropdown-toggle" type="button" ').concat(this.constants.dataToggle,'="dropdown">\n        <span class="page-size">\n        ').concat(h?e.formatAllRows():e.pageSize,"\n        </span>\n        ").concat(this.constants.html.dropdownCaret,"\n        </button>\n        ").concat(this.constants.html.pageDropdown[0])];d.forEach((function(i,n){var o;(!e.smartDisplay||0===n||d[n-1]<e.totalRows||i===e.formatAllRows())&&(o=h?i===e.formatAllRows()?t.constants.classes.dropdownActive:"":i===e.pageSize?t.constants.classes.dropdownActive:"",g.push(ov.sprintf(t.constants.html.pageDropdownItem,o,i)))})),g.push("".concat(this.constants.html.pageDropdown[1],"</div>")),c.push(e.formatRecordsPerPage(g.join("")))}if((this.paginationParts.includes("pageInfo")||this.paginationParts.includes("pageInfoShort")||this.paginationParts.includes("pageSize"))&&c.push("</div></div>"),this.paginationParts.includes("pageList")){c.push('<div class="'.concat(this.constants.classes.pull,"-").concat(e.paginationHAlign,' pagination">'),ov.sprintf(this.constants.html.pagination[0],ov.sprintf(" pagination-%s",e.iconSize)),ov.sprintf(this.constants.html.paginationItem," page-pre",e.formatSRPaginationPreText(),e.paginationPreText)),this.totalPages<e.paginationSuccessivelySize?(n=1,o=this.totalPages):o=(n=e.pageNumber-e.paginationPagesBySide)+2*e.paginationPagesBySide,e.pageNumber<e.paginationSuccessivelySize-1&&(o=e.paginationSuccessivelySize),e.paginationSuccessivelySize>this.totalPages-n&&(n=n-(e.paginationSuccessivelySize-(this.totalPages-n))+1),n<1&&(n=1),o>this.totalPages&&(o=this.totalPages);var v=Math.round(e.paginationPagesBySide/2),b=function(i){var n=arguments.length>1&&void 0!==arguments[1]?arguments[1]:"";return ov.sprintf(t.constants.html.paginationItem,n+(i===e.pageNumber?" ".concat(t.constants.classes.paginationActive):""),e.formatSRPaginationPageText(i),i)};if(n>1){var m=e.paginationPagesBySide;for(m>=n&&(m=n-1),i=1;i<=m;i++)c.push(b(i));n-1===m+1?(i=n-1,c.push(b(i))):n-1>m&&(n-2*e.paginationPagesBySide>e.paginationPagesBySide&&e.paginationUseIntermediate?(i=Math.round((n-v)/2+v),c.push(b(i," page-intermediate"))):c.push(ov.sprintf(this.constants.html.paginationItem," page-first-separator disabled","","...")))}for(i=n;i<=o;i++)c.push(b(i));if(this.totalPages>o){var y=this.totalPages-(e.paginationPagesBySide-1);for(o>=y&&(y=o+1),o+1===y-1?(i=o+1,c.push(b(i))):y>o+1&&(this.totalPages-o>2*e.paginationPagesBySide&&e.paginationUseIntermediate?(i=Math.round((this.totalPages-v-o)/2+o),c.push(b(i," page-intermediate"))):c.push(ov.sprintf(this.constants.html.paginationItem," page-last-separator disabled","","..."))),i=y;i<=this.totalPages;i++)c.push(b(i))}c.push(ov.sprintf(this.constants.html.paginationItem," page-next",e.formatSRPaginationNextText(),e.paginationNextText)),c.push(this.constants.html.pagination[1],"</div>")}this.$pagination.html(c.join(""));var w=["bottom","both"].includes(e.paginationVAlign)?" ".concat(this.constants.classes.dropup):"";this.$pagination.last().find(".page-list > div").addClass(w),e.onlyInfoPagination||(r=this.$pagination.find(".page-list a"),a=this.$pagination.find(".page-pre"),s=this.$pagination.find(".page-next"),l=this.$pagination.find(".page-item").not(".page-next, .page-pre, .page-last-separator, .page-first-separator"),this.totalPages<=1&&this.$pagination.find("div.pagination").hide(),e.smartDisplay&&(d.length<2||e.totalRows<=d[0])&&this.$pagination.find("div.page-list").hide(),this.$pagination[this.getData().length?"show":"hide"](),e.paginationLoop||(1===e.pageNumber&&a.addClass("disabled"),e.pageNumber===this.totalPages&&s.addClass("disabled")),h&&(e.pageSize=e.formatAllRows()),r.off("click").on("click",(function(e){return t.onPageListChange(e)})),a.off("click").on("click",(function(e){return t.onPagePre(e)})),s.off("click").on("click",(function(e){return t.onPageNext(e)})),l.off("click").on("click",(function(e){return t.onPageNumber(e)})))}else this.$pagination.hide()}},{key:"updatePagination",value:function(e){e&&t(e.currentTarget).hasClass("disabled")||(this.options.maintainMetaData||this.resetRows(),this.initPagination(),this.trigger("page-change",this.options.pageNumber,this.options.pageSize),"server"===this.options.sidePagination||"client"===this.options.sidePagination&&this.options.paginationLoadMore&&!this._paginationLoaded&&this.options.pageNumber===this.totalPages?this.initServer():this.initBody())}},{key:"onPageListChange",value:function(e){e.preventDefault();var i=t(e.currentTarget);return i.parent().addClass(this.constants.classes.dropdownActive).siblings().removeClass(this.constants.classes.dropdownActive),this.options.pageSize=i.text().toUpperCase()===this.options.formatAllRows().toUpperCase()?this.options.formatAllRows():+i.text(),this.$toolbar.find(".page-size").text(this.options.pageSize),this.updatePagination(e),!1}},{key:"onPagePre",value:function(e){if(!t(e.target).hasClass("disabled"))return e.preventDefault(),this.options.pageNumber-1==0?this.options.pageNumber=this.options.totalPages:this.options.pageNumber--,this.updatePagination(e),!1}},{key:"onPageNext",value:function(e){if(!t(e.target).hasClass("disabled"))return e.preventDefault(),this.options.pageNumber+1>this.options.totalPages?this.options.pageNumber=1:this.options.pageNumber++,this.updatePagination(e),!1}},{key:"onPageNumber",value:function(e){if(e.preventDefault(),this.options.pageNumber!==+t(e.currentTarget).text())return this.options.pageNumber=+t(e.currentTarget).text(),this.updatePagination(e),!1}},{key:"initRow",value:function(t,e,n,o){var r=this,s=[],l={},c=[],h="",u={},d=[];if(!(ov.findIndex(this.hiddenRows,t)>-1)){if((l=ov.calculateObjectValue(this.options,this.options.rowStyle,[t,e],l))&&l.css)for(var p=0,f=Object.entries(l.css);p<f.length;p++){var g=a(f[p],2),v=g[0],b=g[1];c.push("".concat(v,": ").concat(b))}if(u=ov.calculateObjectValue(this.options,this.options.rowAttributes,[t,e],u))for(var m=0,y=Object.entries(u);m<y.length;m++){var w=a(y[m],2),S=w[0],x=w[1];d.push("".concat(S,'="').concat(ov.escapeHTML(x),'"'))}if(t._data&&!ov.isEmptyObject(t._data))for(var O=0,k=Object.entries(t._data);O<k.length;O++){var C=a(k[O],2),P=C[0],T=C[1];if("index"===P)return;h+=" data-".concat(P,"='").concat("object"===i(T)?JSON.stringify(T):T,"'")}s.push("<tr",ov.sprintf(" %s",d.length?d.join(" "):void 0),ov.sprintf(' id="%s"',Array.isArray(t)?void 0:t._id),ov.sprintf(' class="%s"',l.classes||(Array.isArray(t)?void 0:t._class)),ov.sprintf(' style="%s"',Array.isArray(t)?void 0:t._style),' data-index="'.concat(e,'"'),ov.sprintf(' data-uniqueid="%s"',ov.getItemField(t,this.options.uniqueId,!1)),ov.sprintf(' data-has-detail-view="%s"',this.options.detailView&&ov.calculateObjectValue(null,this.options.detailFilter,[e,t])?"true":void 0),ov.sprintf("%s",h),">"),this.options.cardView&&s.push('<td colspan="'.concat(this.header.fields.length,'"><div class="card-views">'));var I="";return ov.hasDetailViewIcon(this.options)&&(I="<td>",ov.calculateObjectValue(null,this.options.detailFilter,[e,t])&&(I+='\n          <a class="detail-icon" href="#">\n          '.concat(ov.sprintf(this.constants.html.icon,this.options.iconsPrefix,this.options.icons.detailOpen),"\n          </a>\n        ")),I+="</td>"),I&&"right"!==this.options.detailViewAlign&&s.push(I),this.header.fields.forEach((function(i,n){var o=r.columns[n],l="",h=ov.getItemField(t,i,r.options.escape,o.escape),u="",d="",p={},f="",g=r.header.classes[n],v="",b="",m="",y="",w="",S="";if((!r.fromHtml&&!r.autoMergeCells||void 0!==h||o.checkbox||o.radio)&&o.visible&&(!r.options.cardView||o.cardVisible)){if(c.concat([r.header.styles[n]]).length&&(b+="".concat(c.concat([r.header.styles[n]]).join("; "))),t["_".concat(i,"_style")]&&(b+="".concat(t["_".concat(i,"_style")])),b&&(v=' style="'.concat(b,'"')),t["_".concat(i,"_id")]&&(f=ov.sprintf(' id="%s"',t["_".concat(i,"_id")])),t["_".concat(i,"_class")]&&(g=ov.sprintf(' class="%s"',t["_".concat(i,"_class")])),t["_".concat(i,"_rowspan")]&&(y=ov.sprintf(' rowspan="%s"',t["_".concat(i,"_rowspan")])),t["_".concat(i,"_colspan")]&&(w=ov.sprintf(' colspan="%s"',t["_".concat(i,"_colspan")])),t["_".concat(i,"_title")]&&(S=ov.sprintf(' title="%s"',t["_".concat(i,"_title")])),(p=ov.calculateObjectValue(r.header,r.header.cellStyles[n],[h,t,e,i],p)).classes&&(g=' class="'.concat(p.classes,'"')),p.css){for(var x=[],O=0,k=Object.entries(p.css);O<k.length;O++){var C=a(k[O],2),P=C[0],T=C[1];x.push("".concat(P,": ").concat(T))}v=' style="'.concat(x.concat(r.header.styles[n]).join("; "),'"')}if(u=ov.calculateObjectValue(o,r.header.formatters[n],[h,t,e,i],h),o.checkbox||o.radio||(u=null==u?r.options.undefinedText:u),o.searchable&&r.searchText&&r.options.searchHighlight&&!o.checkbox&&!o.radio){var I="",A=r.searchText.replace(/[.*+?^${}()|[\]\\]/g,"\\$&");if(r.options.searchAccentNeutralise){var $=new RegExp("".concat(ov.normalizeAccent(A)),"gmi").exec(ov.normalizeAccent(u));$&&(A=u.substring($.index,$.index+A.length))}var R=new RegExp("(".concat(A,")"),"gim"),E="<mark>$1</mark>";if(u&&/<(?=.*? .*?\/ ?>|br|hr|input|!--|wbr)[a-z]+.*?>|<([a-z]+).*?<\/\1>/i.test(u)){var j=(new DOMParser).parseFromString(u.toString(),"text/html").documentElement.textContent,_=j.replace(R,E);j=j.replace(/[.*+?^${}()|[\]\\]/g,"\\$&"),I=u.replace(new RegExp("(>\\s*)(".concat(j,")(\\s*)"),"gm"),"$1".concat(_,"$3"))}else I=u.toString().replace(R,E);u=ov.calculateObjectValue(o,o.searchHighlightFormatter,[u,r.searchText],I)}if(t["_".concat(i,"_data")]&&!ov.isEmptyObject(t["_".concat(i,"_data")]))for(var F=0,N=Object.entries(t["_".concat(i,"_data")]);F<N.length;F++){var D=a(N[F],2),V=D[0],B=D[1];if("index"===V)return;m+=" data-".concat(V,'="').concat(B,'"')}if(o.checkbox||o.radio){d=o.checkbox?"checkbox":d,d=o.radio?"radio":d;var L=o.class||"",H=ov.isObject(u)&&u.hasOwnProperty("checked")?u.checked:(!0===u||h)&&!1!==u,M=!o.checkboxEnabled||u&&u.disabled;l=[r.options.cardView?'<div class="card-view '.concat(L,'">'):'<td class="bs-checkbox '.concat(L,'"').concat(g).concat(v,">"),'<label>\n            <input\n            data-index="'.concat(e,'"\n            name="').concat(r.options.selectItemName,'"\n            type="').concat(d,'"\n            ').concat(ov.sprintf('value="%s"',t[r.options.idField]),"\n            ").concat(ov.sprintf('checked="%s"',H?"checked":void 0),"\n            ").concat(ov.sprintf('disabled="%s"',M?"disabled":void 0)," />\n            <span></span>\n            </label>"),r.header.formatters[n]&&"string"==typeof u?u:"",r.options.cardView?"</div>":"</td>"].join(""),t[r.header.stateField]=!0===u||!!h||u&&u.checked}else if(r.options.cardView){var U=r.options.showHeader?'<span class="card-view-title '.concat(p.classes||"",'"').concat(v,">").concat(ov.getFieldTitle(r.columns,i),"</span>"):"";l='<div class="card-view">'.concat(U,'<span class="card-view-value ').concat(p.classes||"",'"').concat(v,">").concat(u,"</span></div>"),r.options.smartDisplay&&""===u&&(l='<div class="card-view"></div>')}else l="<td".concat(f).concat(g).concat(v).concat(m).concat(y).concat(w).concat(S,">").concat(u,"</td>");s.push(l)}})),I&&"right"===this.options.detailViewAlign&&s.push(I),this.options.cardView&&s.push("</div></td>"),s.push("</tr>"),s.join("")}}},{key:"initBody",value:function(e,i){var n=this,o=this.getData();this.trigger("pre-body",o),this.$body=this.$el.find(">tbody"),this.$body.length||(this.$body=t("<tbody></tbody>").appendTo(this.$el)),this.options.pagination&&"server"!==this.options.sidePagination||(this.pageFrom=1,this.pageTo=o.length);var r=[],a=t(document.createDocumentFragment()),s=!1,l=[];this.autoMergeCells=ov.checkAutoMergeCells(o.slice(this.pageFrom-1,this.pageTo));for(var c=this.pageFrom-1;c<this.pageTo;c++){var h=o[c],u=this.initRow(h,c,o,a);if(s=s||!!u,u&&"string"==typeof u){var d=this.options.uniqueId;if(d&&h.hasOwnProperty(d)){var p=h[d],f=this.$body.find(ov.sprintf('> tr[data-uniqueid="%s"][data-has-detail-view]',p)).next();f.is("tr.detail-view")&&(l.push(c),i&&p===i||(u+=f[0].outerHTML))}this.options.virtualScroll?r.push(u):a.append(u)}}s?this.options.virtualScroll?(this.virtualScroll&&this.virtualScroll.destroy(),this.virtualScroll=new uv({rows:r,fixedScroll:e,scrollEl:this.$tableBody[0],contentEl:this.$body[0],itemHeight:this.options.virtualScrollItemHeight,callback:function(t,e){n.fitHeader(),n.initBodyEvent(),n.trigger("virtual-scroll",t,e)}})):this.$body.html(a):this.$body.html('<tr class="no-records-found">'.concat(ov.sprintf('<td colspan="%s">%s</td>',this.getVisibleFields().length+ov.getDetailViewIndexOffset(this.options),this.options.formatNoMatches()),"</tr>")),l.forEach((function(t){n.expandRow(t)})),e||this.scrollTo(0),this.initBodyEvent(),this.initFooter(),this.resetView(),this.updateSelected(),"server"!==this.options.sidePagination&&(this.options.totalRows=o.length),this.trigger("post-body",o)}},{key:"initBodyEvent",value:function(){var e=this;this.$body.find("> tr[data-index] > td").off("click dblclick").on("click dblclick",(function(i){var n=t(i.currentTarget);if(!(n.find(".detail-icon").length||n.index()-ov.getDetailViewIndexOffset(e.options)<0)){var o=n.parent(),r=t(i.target).parents(".card-views").children(),a=t(i.target).parents(".card-view"),s=o.data("index"),l=e.data[s],c=e.options.cardView?r.index(a):n[0].cellIndex,h=e.getVisibleFields()[c-ov.getDetailViewIndexOffset(e.options)],u=e.columns[e.fieldsColumnsIndex[h]],d=ov.getItemField(l,h,e.options.escape,u.escape);if(e.trigger("click"===i.type?"click-cell":"dbl-click-cell",h,d,l,n),e.trigger("click"===i.type?"click-row":"dbl-click-row",l,o,h),"click"===i.type&&e.options.clickToSelect&&u.clickToSelect&&!ov.calculateObjectValue(e.options,e.options.ignoreClickToSelectOn,[i.target])){var p=o.find(ov.sprintf('[name="%s"]',e.options.selectItemName));p.length&&p[0].click()}"click"===i.type&&e.options.detailViewByClick&&e.toggleDetailView(s,e.header.detailFormatters[e.fieldsColumnsIndex[h]])}})).off("mousedown").on("mousedown",(function(t){e.multipleSelectRowCtrlKey=t.ctrlKey||t.metaKey,e.multipleSelectRowShiftKey=t.shiftKey})),this.$body.find("> tr[data-index] > td > .detail-icon").off("click").on("click",(function(i){return i.preventDefault(),e.toggleDetailView(t(i.currentTarget).parent().parent().data("index")),!1})),this.$selectItem=this.$body.find(ov.sprintf('[name="%s"]',this.options.selectItemName)),this.$selectItem.off("click").on("click",(function(i){i.stopImmediatePropagation();var n=t(i.currentTarget);e._toggleCheck(n.prop("checked"),n.data("index"))})),this.header.events.forEach((function(i,n){var o=i;if(o){if("string"==typeof o&&(o=ov.calculateObjectValue(null,o)),!o)throw new Error("Unknown event in the scope: ".concat(i));var r=e.header.fields[n],a=e.getVisibleFields().indexOf(r);if(-1!==a){a+=ov.getDetailViewIndexOffset(e.options);var s=function(i){if(!o.hasOwnProperty(i))return 1;var n=o[i];e.$body.find(">tr:not(.no-records-found)").each((function(o,s){var l=t(s),c=l.find(e.options.cardView?".card-views>.card-view":">td").eq(a),h=i.indexOf(" "),u=i.substring(0,h),d=i.substring(h+1);c.find(d).off(u).on(u,(function(t){var i=l.data("index"),o=e.data[i],a=o[r];n.apply(e,[t,a,o,i])}))}))};for(var l in o)s(l)}}}))}},{key:"initServer",value:function(e,i,n){var o=this,r={},a=this.header.fields.indexOf(this.options.sortName),s={searchText:this.searchText,sortName:this.options.sortName,sortOrder:this.options.sortOrder};if(this.header.sortNames[a]&&(s.sortName=this.header.sortNames[a]),this.options.pagination&&"server"===this.options.sidePagination&&(s.pageSize=this.options.pageSize===this.options.formatAllRows()?this.options.totalRows:this.options.pageSize,s.pageNumber=this.options.pageNumber),n||this.options.url||this.options.ajax){if("limit"===this.options.queryParamsType&&(s={search:s.searchText,sort:s.sortName,order:s.sortOrder},this.options.pagination&&"server"===this.options.sidePagination&&(s.offset=this.options.pageSize===this.options.formatAllRows()?0:this.options.pageSize*(this.options.pageNumber-1),s.limit=this.options.pageSize,0!==s.limit&&this.options.pageSize!==this.options.formatAllRows()||delete s.limit)),this.options.search&&"server"===this.options.sidePagination&&this.options.searchable&&this.columns.filter((function(t){return t.searchable})).length){s.searchable=[];var l,c=h(this.columns);try{for(c.s();!(l=c.n()).done;){var u=l.value;!u.checkbox&&u.searchable&&(this.options.visibleSearch&&u.visible||!this.options.visibleSearch)&&s.searchable.push(u.field)}}catch(t){c.e(t)}finally{c.f()}}if(ov.isEmptyObject(this.filterColumnsPartial)||(s.filter=JSON.stringify(this.filterColumnsPartial,null)),ov.extend(s,i||{}),!1!==(r=ov.calculateObjectValue(this.options,this.options.queryParams,[s],r))){e||this.showLoading();var d=ov.extend({},ov.calculateObjectValue(null,this.options.ajaxOptions),{type:this.options.method,url:n||this.options.url,data:"application/json"===this.options.contentType&&"post"===this.options.method?JSON.stringify(r):r,cache:this.options.cache,contentType:this.options.contentType,dataType:this.options.dataType,success:function(t,i,n){var r=ov.calculateObjectValue(o.options,o.options.responseHandler,[t,n],t);"client"===o.options.sidePagination&&o.options.paginationLoadMore&&(o._paginationLoaded=o.data.length===r.length),o.load(r),o.trigger("load-success",r,n&&n.status,n),e||o.hideLoading(),"server"===o.options.sidePagination&&o.options.pageNumber>1&&r[o.options.totalField]>0&&!r[o.options.dataField].length&&o.updatePagination()},error:function(t){if(t&&0===t.status&&o._xhrAbort)o._xhrAbort=!1;else{var i=[];"server"===o.options.sidePagination&&((i={})[o.options.totalField]=0,i[o.options.dataField]=[]),o.load(i),o.trigger("load-error",t&&t.status,t),e||o.hideLoading()}}});return this.options.ajax?ov.calculateObjectValue(this,this.options.ajax,[d],null):(this._xhr&&4!==this._xhr.readyState&&(this._xhrAbort=!0,this._xhr.abort()),this._xhr=t.ajax(d)),r}}}},{key:"initSearchText",value:function(){if(this.options.search&&(this.searchText="",""!==this.options.searchText)){var t=ov.getSearchInput(this);t.val(this.options.searchText),this.onSearch({currentTarget:t,firedByInitSearchText:!0})}}},{key:"getCaret",value:function(){var e=this;this.$header.find("th").each((function(i,n){t(n).find(".sortable").removeClass("desc asc").addClass(t(n).data("field")===e.options.sortName?e.options.sortOrder:"both")}))}},{key:"updateSelected",value:function(){var e=this.$selectItem.filter(":enabled").length&&this.$selectItem.filter(":enabled").length===this.$selectItem.filter(":enabled").filter(":checked").length;this.$selectAll.add(this.$selectAll_).prop("checked",e),this.$selectItem.each((function(e,i){t(i).closest("tr")[t(i).prop("checked")?"addClass":"removeClass"]("selected")}))}},{key:"updateRows",value:function(){var e=this;this.$selectItem.each((function(i,n){e.data[t(n).data("index")][e.header.stateField]=t(n).prop("checked")}))}},{key:"resetRows",value:function(){var t,e=h(this.data);try{for(e.s();!(t=e.n()).done;){var i=t.value;this.$selectAll.prop("checked",!1),this.$selectItem.prop("checked",!1),this.header.stateField&&(i[this.header.stateField]=!1)}}catch(t){e.e(t)}finally{e.f()}this.initHiddenRows()}},{key:"trigger",value:function(i){for(var n,o,r="".concat(i,".bs.table"),a=arguments.length,s=new Array(a>1?a-1:0),l=1;l<a;l++)s[l-1]=arguments[l];(n=this.options)[e.EVENTS[r]].apply(n,[].concat(s,[this])),this.$el.trigger(t.Event(r,{sender:this}),s),(o=this.options).onAll.apply(o,[r].concat([].concat(s,[this]))),this.$el.trigger(t.Event("all.bs.table",{sender:this}),[r,s])}},{key:"resetHeader",value:function(){var t=this;clearTimeout(this.timeoutId_),this.timeoutId_=setTimeout((function(){return t.fitHeader()}),this.$el.is(":hidden")?100:0)}},{key:"fitHeader",value:function(){var e=this;if(this.$el.is(":hidden"))this.timeoutId_=setTimeout((function(){return e.fitHeader()}),100);else{var i=this.$tableBody.get(0),n=this.hasScrollBar&&i.scrollHeight>i.clientHeight+this.$header.outerHeight()?ov.getScrollBarWidth():0;this.$el.css("margin-top",-this.$header.outerHeight());var o=this.$tableHeader.find(":focus");if(o.length>0){var r=o.parents("th");if(r.length>0){var a=r.attr("data-field");if(void 0!==a){var s=this.$header.find("[data-field='".concat(a,"']"));s.length>0&&s.find(":input").addClass("focus-temp")}}}this.$header_=this.$header.clone(!0,!0),this.$selectAll_=this.$header_.find('[name="btSelectAll"]'),this.$tableHeader.css("margin-right",n).find("table").css("width",this.$el.outerWidth()).html("").attr("class",this.$el.attr("class")).append(this.$header_),this.$tableLoading.css("width",this.$el.outerWidth());var l=t(".focus-temp:visible:eq(0)");l.length>0&&(l.focus(),this.$header.find(".focus-temp").removeClass("focus-temp")),this.$header.find("th[data-field]").each((function(i,n){e.$header_.find(ov.sprintf('th[data-field="%s"]',t(n).data("field"))).data(t(n).data())}));for(var c=this.getVisibleFields(),h=this.$header_.find("th"),u=this.$body.find(">tr:not(.no-records-found,.virtual-scroll-top)").eq(0);u.length&&u.find('>td[colspan]:not([colspan="1"])').length;)u=u.next();var d=u.find("> *").length;u.find("> *").each((function(i,n){var o=t(n);if(ov.hasDetailViewIcon(e.options)&&(0===i&&"right"!==e.options.detailViewAlign||i===d-1&&"right"===e.options.detailViewAlign)){var r=h.filter(".detail"),a=r.innerWidth()-r.find(".fht-cell").width();r.find(".fht-cell").width(o.innerWidth()-a)}else{var s=i-ov.getDetailViewIndexOffset(e.options),l=e.$header_.find(ov.sprintf('th[data-field="%s"]',c[s]));l.length>1&&(l=t(h[o[0].cellIndex]));var u=l.innerWidth()-l.find(".fht-cell").width();l.find(".fht-cell").width(o.innerWidth()-u)}})),this.horizontalScroll(),this.trigger("post-header")}}},{key:"initFooter",value:function(){if(this.options.showFooter&&!this.options.cardView){var t=this.getData(),e=[],i="";ov.hasDetailViewIcon(this.options)&&(i='<th class="detail"><div class="th-inner"></div><div class="fht-cell"></div></th>'),i&&"right"!==this.options.detailViewAlign&&e.push(i);var n,o=h(this.columns);try{for(o.s();!(n=o.n()).done;){var r,s,l=n.value,c=[],u={},d=ov.sprintf(' class="%s"',l.class);if(!(!l.visible||this.footerData&&this.footerData.length>0&&!(l.field in this.footerData[0]))){if(this.options.cardView&&!l.cardVisible)return;if(r=ov.sprintf("text-align: %s; ",l.falign?l.falign:l.align),s=ov.sprintf("vertical-align: %s; ",l.valign),(u=ov.calculateObjectValue(null,l.footerStyle||this.options.footerStyle,[l]))&&u.css)for(var p=0,f=Object.entries(u.css);p<f.length;p++){var g=a(f[p],2),v=g[0],b=g[1];c.push("".concat(v,": ").concat(b))}u&&u.classes&&(d=ov.sprintf(' class="%s"',l.class?[l.class,u.classes].join(" "):u.classes)),e.push("<th",d,ov.sprintf(' style="%s"',r+s+c.concat().join("; ")||void 0));var m=0;this.footerData&&this.footerData.length>0&&(m=this.footerData[0]["_".concat(l.field,"_colspan")]||0),m&&e.push(' colspan="'.concat(m,'" ')),e.push(">"),e.push('<div class="th-inner">');var y="";this.footerData&&this.footerData.length>0&&(y=this.footerData[0][l.field]||""),e.push(ov.calculateObjectValue(l,l.footerFormatter,[t,y],y)),e.push("</div>"),e.push('<div class="fht-cell"></div>'),e.push("</div>"),e.push("</th>")}}}catch(t){o.e(t)}finally{o.f()}i&&"right"===this.options.detailViewAlign&&e.push(i),this.options.height||this.$tableFooter.length||(this.$el.append("<tfoot><tr></tr></tfoot>"),this.$tableFooter=this.$el.find("tfoot")),this.$tableFooter.find("tr").length||this.$tableFooter.html("<table><thead><tr></tr></thead></table>"),this.$tableFooter.find("tr").html(e.join("")),this.trigger("post-footer",this.$tableFooter)}}},{key:"fitFooter",value:function(){var e=this;if(this.$el.is(":hidden"))setTimeout((function(){return e.fitFooter()}),100);else{var i=this.$tableBody.get(0),n=this.hasScrollBar&&i.scrollHeight>i.clientHeight+this.$header.outerHeight()?ov.getScrollBarWidth():0;this.$tableFooter.css("margin-right",n).find("table").css("width",this.$el.outerWidth()).attr("class",this.$el.attr("class"));var o=this.$tableFooter.find("th"),r=this.$body.find(">tr:first-child:not(.no-records-found)");for(o.find(".fht-cell").width("auto");r.length&&r.find('>td[colspan]:not([colspan="1"])').length;)r=r.next();var a=r.find("> *").length;r.find("> *").each((function(i,n){var r=t(n);if(ov.hasDetailViewIcon(e.options)&&(0===i&&"left"===e.options.detailViewAlign||i===a-1&&"right"===e.options.detailViewAlign)){var s=o.filter(".detail"),l=s.innerWidth()-s.find(".fht-cell").width();s.find(".fht-cell").width(r.innerWidth()-l)}else{var c=o.eq(i),h=c.innerWidth()-c.find(".fht-cell").width();c.find(".fht-cell").width(r.innerWidth()-h)}})),this.horizontalScroll()}}},{key:"horizontalScroll",value:function(){var t=this;this.$tableBody.off("scroll").on("scroll",(function(){var e=t.$tableBody.scrollLeft();t.options.showHeader&&t.options.height&&t.$tableHeader.scrollLeft(e),t.options.showFooter&&!t.options.cardView&&t.$tableFooter.scrollLeft(e),t.trigger("scroll-body",t.$tableBody)}))}},{key:"getVisibleFields",value:function(){var t,e=[],i=h(this.header.fields);try{for(i.s();!(t=i.n()).done;){var n=t.value,o=this.columns[this.fieldsColumnsIndex[n]];o&&o.visible&&(!this.options.cardView||o.cardVisible)&&e.push(n)}}catch(t){i.e(t)}finally{i.f()}return e}},{key:"initHiddenRows",value:function(){this.hiddenRows=[]}},{key:"getOptions",value:function(){var t=ov.extend({},this.options);return delete t.data,ov.extend(!0,{},t)}},{key:"refreshOptions",value:function(t){ov.compareObjects(this.options,t,!0)||(this.options=ov.extend(this.options,t),this.trigger("refresh-options",this.options),this.destroy(),this.init())}},{key:"getData",value:function(t){var e=this,i=this.options.data;if(!(this.searchText||this.options.customSearch||void 0!==this.options.sortName||this.enableCustomSort)&&ov.isEmptyObject(this.filterColumns)&&"function"!=typeof this.options.filterOptions.filterAlgorithm&&ov.isEmptyObject(this.filterColumnsPartial)||t&&t.unfiltered||(i=this.data),t&&!t.includeHiddenRows){var n=this.getHiddenRows();i=i.filter((function(t){return-1===ov.findIndex(n,t)}))}return t&&t.useCurrentPage&&(i=i.slice(this.pageFrom-1,this.pageTo)),t&&t.formatted&&i.forEach((function(t){for(var i=0,n=Object.entries(t);i<n.length;i++){var o=a(n[i],2),r=o[0],s=o[1],l=e.columns[e.fieldsColumnsIndex[r]];if(!l)return;t[r]=ov.calculateObjectValue(l,e.header.formatters[l.fieldIndex],[s,t,t.index,l.field],s)}})),i}},{key:"getSelections",value:function(){var t=this;return(this.options.maintainMetaData?this.options.data:this.data).filter((function(e){return!0===e[t.header.stateField]}))}},{key:"load",value:function(t){var e,i=t;this.options.pagination&&"server"===this.options.sidePagination&&(this.options.totalRows=i[this.options.totalField],this.options.totalNotFiltered=i[this.options.totalNotFilteredField],this.footerData=i[this.options.footerField]?[i[this.options.footerField]]:void 0),e=this.options.fixedScroll||i.fixedScroll,i=Array.isArray(i)?i:i[this.options.dataField],this.initData(i),this.initSearch(),this.initPagination(),this.initBody(e)}},{key:"append",value:function(t){this.initData(t,"append"),this.initSearch(),this.initPagination(),this.initSort(),this.initBody(!0)}},{key:"prepend",value:function(t){this.initData(t,"prepend"),this.initSearch(),this.initPagination(),this.initSort(),this.initBody(!0)}},{key:"remove",value:function(t){for(var e=0,i=this.options.data.length-1;i>=0;i--){var n=this.options.data[i],o=ov.getItemField(n,t.field,this.options.escape,n.escape);void 0===o&&"$index"!==t.field||(!n.hasOwnProperty(t.field)&&"$index"===t.field&&t.values.includes(i)||t.values.includes(o))&&(e++,this.options.data.splice(i,1))}e&&("server"===this.options.sidePagination&&(this.options.totalRows-=e,this.data=s(this.options.data)),this.initSearch(),this.initPagination(),this.initSort(),this.initBody(!0))}},{key:"removeAll",value:function(){this.options.data.length>0&&(this.options.data.splice(0,this.options.data.length),this.initSearch(),this.initPagination(),this.initBody(!0))}},{key:"insertRow",value:function(t){t.hasOwnProperty("index")&&t.hasOwnProperty("row")&&(this.options.data.splice(t.index,0,t.row),this.initSearch(),this.initPagination(),this.initSort(),this.initBody(!0))}},{key:"updateRow",value:function(t){var e,i=h(Array.isArray(t)?t:[t]);try{for(i.s();!(e=i.n()).done;){var n=e.value;n.hasOwnProperty("index")&&n.hasOwnProperty("row")&&(n.hasOwnProperty("replace")&&n.replace?this.options.data[n.index]=n.row:ov.extend(this.options.data[n.index],n.row))}}catch(t){i.e(t)}finally{i.f()}this.initSearch(),this.initPagination(),this.initSort(),this.initBody(!0)}},{key:"getRowByUniqueId",value:function(t){var e,i,n=this.options.uniqueId,o=t,r=null;for(e=this.options.data.length-1;e>=0;e--){i=this.options.data[e];var a=ov.getItemField(i,n,this.options.escape,i.escape);if(void 0!==a&&("string"==typeof a?o=o.toString():"number"==typeof a&&(Number(a)===a&&a%1==0?o=parseInt(o,10):a===Number(a)&&0!==a&&(o=parseFloat(o))),a===o)){r=i;break}}return r}},{key:"updateByUniqueId",value:function(t){var e,i=null,n=h(Array.isArray(t)?t:[t]);try{for(n.s();!(e=n.n()).done;){var o=e.value;if(o.hasOwnProperty("id")&&o.hasOwnProperty("row")){var r=this.options.data.indexOf(this.getRowByUniqueId(o.id));-1!==r&&(o.hasOwnProperty("replace")&&o.replace?this.options.data[r]=o.row:ov.extend(this.options.data[r],o.row),i=o.id)}}}catch(t){n.e(t)}finally{n.f()}this.initSearch(),this.initPagination(),this.initSort(),this.initBody(!0,i)}},{key:"removeByUniqueId",value:function(t){var e=this.options.data.length,i=this.getRowByUniqueId(t);i&&this.options.data.splice(this.options.data.indexOf(i),1),e!==this.options.data.length&&("server"===this.options.sidePagination&&(this.options.totalRows-=1,this.data=s(this.options.data)),this.initSearch(),this.initPagination(),this.initBody(!0))}},{key:"_updateCellOnly",value:function(e,i){var n=this.initRow(this.options.data[i],i),o=this.getVisibleFields().indexOf(e);-1!==o&&(o+=ov.getDetailViewIndexOffset(this.options),this.$body.find(">tr[data-index=".concat(i,"]")).find(">td:eq(".concat(o,")")).replaceWith(t(n).find(">td:eq(".concat(o,")"))),this.initBodyEvent(),this.initFooter(),this.resetView(),this.updateSelected())}},{key:"updateCell",value:function(t){t.hasOwnProperty("index")&&t.hasOwnProperty("field")&&t.hasOwnProperty("value")&&(this.options.data[t.index][t.field]=t.value,!1!==t.reinit?(this.initSort(),this.initBody(!0)):this._updateCellOnly(t.field,t.index))}},{key:"updateCellByUniqueId",value:function(t){var e=this;(Array.isArray(t)?t:[t]).forEach((function(t){var i=t.id,n=t.field,o=t.value,r=e.options.data.indexOf(e.getRowByUniqueId(i));-1!==r&&(e.options.data[r][n]=o)})),!1!==t.reinit?(this.initSort(),this.initBody(!0)):this._updateCellOnly(t.field,this.options.data.indexOf(this.getRowByUniqueId(t.id)))}},{key:"showRow",value:function(t){this._toggleRow(t,!0)}},{key:"hideRow",value:function(t){this._toggleRow(t,!1)}},{key:"_toggleRow",value:function(t,e){var i;if(t.hasOwnProperty("index")?i=this.getData()[t.index]:t.hasOwnProperty("uniqueId")&&(i=this.getRowByUniqueId(t.uniqueId)),i){var n=ov.findIndex(this.hiddenRows,i);e||-1!==n?e&&n>-1&&this.hiddenRows.splice(n,1):this.hiddenRows.push(i),this.initBody(!0),this.initPagination()}}},{key:"getHiddenRows",value:function(t){if(t)return this.initHiddenRows(),this.initBody(!0),void this.initPagination();var e,i=[],n=h(this.getData());try{for(n.s();!(e=n.n()).done;){var o=e.value;this.hiddenRows.includes(o)&&i.push(o)}}catch(t){n.e(t)}finally{n.f()}return this.hiddenRows=i,i}},{key:"showColumn",value:function(t){var e=this;(Array.isArray(t)?t:[t]).forEach((function(t){e._toggleColumn(e.fieldsColumnsIndex[t],!0,!0)}))}},{key:"hideColumn",value:function(t){var e=this;(Array.isArray(t)?t:[t]).forEach((function(t){e._toggleColumn(e.fieldsColumnsIndex[t],!1,!0)}))}},{key:"_toggleColumn",value:function(t,e,i){if(-1!==t&&this.columns[t].visible!==e&&(this.columns[t].visible=e,this.initHeader(),this.initSearch(),this.initPagination(),this.initBody(),this.options.showColumns)){var n=this.$toolbar.find('.keep-open input:not(".toggle-all")').prop("disabled",!1);i&&n.filter(ov.sprintf('[value="%s"]',t)).prop("checked",e),n.filter(":checked").length<=this.options.minimumCountColumns&&n.filter(":checked").prop("disabled",!0)}}},{key:"getVisibleColumns",value:function(){var t=this;return this.columns.filter((function(e){return e.visible&&!t.isSelectionColumn(e)}))}},{key:"getHiddenColumns",value:function(){return this.columns.filter((function(t){return!t.visible}))}},{key:"isSelectionColumn",value:function(t){return t.radio||t.checkbox}},{key:"showAllColumns",value:function(){this._toggleAllColumns(!0)}},{key:"hideAllColumns",value:function(){this._toggleAllColumns(!1)}},{key:"_toggleAllColumns",value:function(e){var i,n=this,o=h(this.columns.slice().reverse());try{for(o.s();!(i=o.n()).done;){var r=i.value;if(r.switchable){if(!e&&this.options.showColumns&&this.getVisibleColumns().filter((function(t){return t.switchable})).length===this.options.minimumCountColumns)continue;r.visible=e}}}catch(t){o.e(t)}finally{o.f()}if(this.initHeader(),this.initSearch(),this.initPagination(),this.initBody(),this.options.showColumns){var a=this.$toolbar.find('.keep-open input[type="checkbox"]:not(".toggle-all")').prop("disabled",!1);e?a.prop("checked",e):a.get().reverse().forEach((function(i){a.filter(":checked").length>n.options.minimumCountColumns&&t(i).prop("checked",e)})),a.filter(":checked").length<=this.options.minimumCountColumns&&a.filter(":checked").prop("disabled",!0)}}},{key:"mergeCells",value:function(t){var e,i,n=t.index,o=this.getVisibleFields().indexOf(t.field),r=t.rowspan||1,a=t.colspan||1,s=this.$body.find(">tr[data-index]");o+=ov.getDetailViewIndexOffset(this.options);var l=s.eq(n).find(">td").eq(o);if(!(n<0||o<0||n>=this.data.length)){for(e=n;e<n+r;e++)for(i=o;i<o+a;i++)s.eq(e).find(">td").eq(i).hide();l.attr("rowspan",r).attr("colspan",a).show()}}},{key:"checkAll",value:function(){this._toggleCheckAll(!0)}},{key:"uncheckAll",value:function(){this._toggleCheckAll(!1)}},{key:"_toggleCheckAll",value:function(t){var e=this.getSelections();this.$selectAll.add(this.$selectAll_).prop("checked",t),this.$selectItem.filter(":enabled").prop("checked",t),this.updateRows(),this.updateSelected();var i=this.getSelections();t?this.trigger("check-all",i,e):this.trigger("uncheck-all",i,e)}},{key:"checkInvert",value:function(){var e=this.$selectItem.filter(":enabled"),i=e.filter(":checked");e.each((function(e,i){t(i).prop("checked",!t(i).prop("checked"))})),this.updateRows(),this.updateSelected(),this.trigger("uncheck-some",i),i=this.getSelections(),this.trigger("check-some",i)}},{key:"check",value:function(t){this._toggleCheck(!0,t)}},{key:"uncheck",value:function(t){this._toggleCheck(!1,t)}},{key:"_toggleCheck",value:function(t,e){var i=this.$selectItem.filter('[data-index="'.concat(e,'"]')),n=this.data[e];if(i.is(":radio")||this.options.singleSelect||this.options.multipleSelectRow&&!this.multipleSelectRowCtrlKey&&!this.multipleSelectRowShiftKey){var o,r=h(this.options.data);try{for(r.s();!(o=r.n()).done;){o.value[this.header.stateField]=!1}}catch(t){r.e(t)}finally{r.f()}this.$selectItem.filter(":checked").not(i).prop("checked",!1)}if(n[this.header.stateField]=t,this.options.multipleSelectRow){if(this.multipleSelectRowShiftKey&&this.multipleSelectRowLastSelectedIndex>=0)for(var s=a(this.multipleSelectRowLastSelectedIndex<e?[this.multipleSelectRowLastSelectedIndex,e]:[e,this.multipleSelectRowLastSelectedIndex],2),l=s[0],c=s[1],u=l+1;u<c;u++)this.data[u][this.header.stateField]=!0,this.$selectItem.filter('[data-index="'.concat(u,'"]')).prop("checked",!0);this.multipleSelectRowCtrlKey=!1,this.multipleSelectRowShiftKey=!1,this.multipleSelectRowLastSelectedIndex=t?e:-1}i.prop("checked",t),this.updateSelected(),this.trigger(t?"check":"uncheck",this.data[e],i)}},{key:"checkBy",value:function(t){this._toggleCheckBy(!0,t)}},{key:"uncheckBy",value:function(t){this._toggleCheckBy(!1,t)}},{key:"_toggleCheckBy",value:function(t,e){var i=this;if(e.hasOwnProperty("field")&&e.hasOwnProperty("values")){var n=[];this.data.forEach((function(o,r){if(!o.hasOwnProperty(e.field))return!1;if(e.values.includes(o[e.field])){var a=i.$selectItem.filter(":enabled").filter(ov.sprintf('[data-index="%s"]',r)),s=!!e.hasOwnProperty("onlyCurrentPage")&&e.onlyCurrentPage;if(!(a=t?a.not(":checked"):a.filter(":checked")).length&&s)return;a.prop("checked",t),o[i.header.stateField]=t,n.push(o),i.trigger(t?"check":"uncheck",o,a)}})),this.updateSelected(),this.trigger(t?"check-some":"uncheck-some",n)}}},{key:"refresh",value:function(t){t&&t.url&&(this.options.url=t.url),t&&t.pageNumber&&(this.options.pageNumber=t.pageNumber),t&&t.pageSize&&(this.options.pageSize=t.pageSize),this.trigger("refresh",this.initServer(t&&t.silent,t&&t.query,t&&t.url))}},{key:"destroy",value:function(){this.$el.insertBefore(this.$container),t(this.options.toolbar).insertBefore(this.$el),this.$container.next().remove(),this.$container.remove(),this.$el.html(this.$el_.html()).css("margin-top","0").attr("class",this.$el_.attr("class")||"");var e=ov.getEventName("resize.bootstrap-table",this.$el.attr("id"));t(window).off(e)}},{key:"resetView",value:function(t){var e=0;if(t&&t.height&&(this.options.height=t.height),this.$tableContainer.toggleClass("has-card-view",this.options.cardView),this.options.height){var i=this.$tableBody.get(0);this.hasScrollBar=i.scrollWidth>i.clientWidth}if(!this.options.cardView&&this.options.showHeader&&this.options.height?(this.$tableHeader.show(),this.resetHeader(),e+=this.$header.outerHeight(!0)+1):(this.$tableHeader.hide(),this.trigger("post-header")),!this.options.cardView&&this.options.showFooter&&(this.$tableFooter.show(),this.fitFooter(),this.options.height&&(e+=this.$tableFooter.outerHeight(!0))),this.$container.hasClass("fullscreen"))this.$tableContainer.css("height",""),this.$tableContainer.css("width","");else if(this.options.height){this.$tableBorder&&(this.$tableBorder.css("width",""),this.$tableBorder.css("height",""));var n=this.$toolbar.outerHeight(!0),o=this.$pagination.outerHeight(!0),r=this.options.height-n-o,a=this.$tableBody.find(">table"),s=a.outerHeight();if(this.$tableContainer.css("height","".concat(r,"px")),this.$tableBorder&&a.is(":visible")){var l=r-s-2;this.hasScrollBar&&(l-=ov.getScrollBarWidth()),this.$tableBorder.css("width","".concat(a.outerWidth(),"px")),this.$tableBorder.css("height","".concat(l,"px"))}}this.options.cardView?(this.$el.css("margin-top","0"),this.$tableContainer.css("padding-bottom","0"),this.$tableFooter.hide()):(this.getCaret(),this.$tableContainer.css("padding-bottom","".concat(e,"px"))),this.trigger("reset-view")}},{key:"showLoading",value:function(){this.$tableLoading.toggleClass("open",!0);var t=this.options.loadingFontSize;"auto"===this.options.loadingFontSize&&(t=.04*this.$tableLoading.width(),t=Math.max(12,t),t=Math.min(32,t),t="".concat(t,"px")),this.$tableLoading.find(".loading-text").css("font-size",t)}},{key:"hideLoading",value:function(){this.$tableLoading.toggleClass("open",!1)}},{key:"togglePagination",value:function(){this.options.pagination=!this.options.pagination;var t=this.options.showButtonIcons?this.options.pagination?this.options.icons.paginationSwitchDown:this.options.icons.paginationSwitchUp:"",e=this.options.showButtonText?this.options.pagination?this.options.formatPaginationSwitchUp():this.options.formatPaginationSwitchDown():"";this.$toolbar.find('button[name="paginationSwitch"]').html("".concat(ov.sprintf(this.constants.html.icon,this.options.iconsPrefix,t)," ").concat(e)),this.updatePagination(),this.trigger("toggle-pagination",this.options.pagination)}},{key:"toggleFullscreen",value:function(){this.$el.closest(".bootstrap-table").toggleClass("fullscreen"),this.resetView()}},{key:"toggleView",value:function(){this.options.cardView=!this.options.cardView,this.initHeader();var t=this.options.showButtonIcons?this.options.cardView?this.options.icons.toggleOn:this.options.icons.toggleOff:"",e=this.options.showButtonText?this.options.cardView?this.options.formatToggleOff():this.options.formatToggleOn():"";this.$toolbar.find('button[name="toggle"]').html("".concat(ov.sprintf(this.constants.html.icon,this.options.iconsPrefix,t)," ").concat(e)).attr("aria-label",e).attr("title",e),this.initBody(),this.trigger("toggle",this.options.cardView)}},{key:"resetSearch",value:function(t){var e=ov.getSearchInput(this),i=t||"";e.val(i),this.searchText=i,this.onSearch({currentTarget:e},!1)}},{key:"filterBy",value:function(t,e){this.filterOptions=ov.isEmptyObject(e)?this.options.filterOptions:ov.extend(this.options.filterOptions,e),this.filterColumns=ov.isEmptyObject(t)?{}:t,this.options.pageNumber=1,this.initSearch(),this.updatePagination()}},{key:"scrollTo",value:function(e){var n={unit:"px",value:0};"object"===i(e)?n=Object.assign(n,e):"string"==typeof e&&"bottom"===e?n.value=this.$tableBody[0].scrollHeight:"string"!=typeof e&&"number"!=typeof e||(n.value=e);var o=n.value;"rows"===n.unit&&(o=0,this.$body.find("> tr:lt(".concat(n.value,")")).each((function(e,i){o+=t(i).outerHeight(!0)}))),this.$tableBody.scrollTop(o)}},{key:"getScrollPosition",value:function(){return this.$tableBody.scrollTop()}},{key:"selectPage",value:function(t){t>0&&t<=this.options.totalPages&&(this.options.pageNumber=t,this.updatePagination())}},{key:"prevPage",value:function(){this.options.pageNumber>1&&(this.options.pageNumber--,this.updatePagination())}},{key:"nextPage",value:function(){this.options.pageNumber<this.options.totalPages&&(this.options.pageNumber++,this.updatePagination())}},{key:"toggleDetailView",value:function(t,e){this.$body.find(ov.sprintf('> tr[data-index="%s"]',t)).next().is("tr.detail-view")?this.collapseRow(t):this.expandRow(t,e),this.resetView()}},{key:"expandRow",value:function(t,e){var i=this.data[t],n=this.$body.find(ov.sprintf('> tr[data-index="%s"][data-has-detail-view]',t));if(this.options.detailViewIcon&&n.find("a.detail-icon").html(ov.sprintf(this.constants.html.icon,this.options.iconsPrefix,this.options.icons.detailClose)),!n.next().is("tr.detail-view")){n.after(ov.sprintf('<tr class="detail-view"><td colspan="%s"></td></tr>',n.children("td").length));var o=n.next().find("td"),r=e||this.options.detailFormatter,a=ov.calculateObjectValue(this.options,r,[t,i,o],"");1===o.length&&o.append(a),this.trigger("expand-row",t,i,o)}}},{key:"expandRowByUniqueId",value:function(t){var e=this.getRowByUniqueId(t);e&&this.expandRow(this.data.indexOf(e))}},{key:"collapseRow",value:function(t){var e=this.data[t],i=this.$body.find(ov.sprintf('> tr[data-index="%s"][data-has-detail-view]',t));i.next().is("tr.detail-view")&&(this.options.detailViewIcon&&i.find("a.detail-icon").html(ov.sprintf(this.constants.html.icon,this.options.iconsPrefix,this.options.icons.detailOpen)),this.trigger("collapse-row",t,e,i.next()),i.next().remove())}},{key:"collapseRowByUniqueId",value:function(t){var e=this.getRowByUniqueId(t);e&&this.collapseRow(this.data.indexOf(e))}},{key:"expandAllRows",value:function(){for(var e=this.$body.find("> tr[data-index][data-has-detail-view]"),i=0;i<e.length;i++)this.expandRow(t(e[i]).data("index"))}},{key:"collapseAllRows",value:function(){for(var e=this.$body.find("> tr[data-index][data-has-detail-view]"),i=0;i<e.length;i++)this.collapseRow(t(e[i]).data("index"))}},{key:"updateColumnTitle",value:function(e){e.hasOwnProperty("field")&&e.hasOwnProperty("title")&&(this.columns[this.fieldsColumnsIndex[e.field]].title=this.options.escape&&this.options.escapeTitle?ov.escapeHTML(e.title):e.title,this.columns[this.fieldsColumnsIndex[e.field]].visible&&(this.$header.find("th[data-field]").each((function(i,n){if(t(n).data("field")===e.field)return t(t(n).find(".th-inner")[0]).text(e.title),!1})),this.resetView()))}},{key:"updateFormatText",value:function(t,e){/^format/.test(t)&&this.options[t]&&("string"==typeof e?this.options[t]=function(){return e}:"function"==typeof e&&(this.options[t]=e),this.initToolbar(),this.initPagination(),this.initBody())}}]),e}();return dv.VERSION=hv.VERSION,dv.DEFAULTS=hv.DEFAULTS,dv.LOCALES=hv.LOCALES,dv.COLUMN_DEFAULTS=hv.COLUMN_DEFAULTS,dv.METHODS=hv.METHODS,dv.EVENTS=hv.EVENTS,t.BootstrapTable=dv,t.fn.bootstrapTable=function(e){for(var n=arguments.length,o=new Array(n>1?n-1:0),r=1;r<n;r++)o[r-1]=arguments[r];var a;return this.each((function(n,r){var s=t(r).data("bootstrap.table");if("string"==typeof e){var l;if(!hv.METHODS.includes(e))throw new Error("Unknown method: ".concat(e));if(!s)return;return a=(l=s)[e].apply(l,o),void("destroy"===e&&t(r).removeData("bootstrap.table"))}if(s)console.warn("You cannot initialize the table more than once!");else{var c=ov.extend(!0,{},dv.DEFAULTS,t(r).data(),"object"===i(e)&&e);s=new t.BootstrapTable(r,c),t(r).data("bootstrap.table",s),s.init()}})),void 0===a?this:a},t.fn.bootstrapTable.Constructor=dv,t.fn.bootstrapTable.theme=hv.THEME,t.fn.bootstrapTable.VERSION=hv.VERSION,t.fn.bootstrapTable.defaults=dv.DEFAULTS,t.fn.bootstrapTable.columnDefaults=dv.COLUMN_DEFAULTS,t.fn.bootstrapTable.events=dv.EVENTS,t.fn.bootstrapTable.locales=dv.LOCALES,t.fn.bootstrapTable.methods=dv.METHODS,t.fn.bootstrapTable.utils=ov,t((function(){t('[data-toggle="table"]').bootstrapTable()})),dv}));
				</script>
				<script>
					//src="https://unpkg.com/bootstrap-table@1.22.4/dist/extensions/filter-control/bootstrap-table-filter-control.min.js"
					/**
					  * bootstrap-table - An extended table to integration with some of the most widely used CSS frameworks. (Supports Bootstrap, Semantic UI, Bulma, Material Design, Foundation)
					  * @version v1.22.4
					  * @homepage https://bootstrap-table.com
					  * @author wenzhixin <wenzhixin2010@gmail.com> (http://wenzhixin.net.cn/)
					  * @license MIT
					*/
					!function(t,e){"object"==typeof exports&&"undefined"!=typeof module?e(require("jquery")):"function"==typeof define&&define.amd?define(["jquery"],e):e((t="undefined"!=typeof globalThis?globalThis:t||self).jQuery)}(this,(function(t){"use strict";function e(t,e,n){return e=c(e),function(t,e){if(e&&("object"==typeof e||"function"==typeof e))return e;if(void 0!==e)throw new TypeError("Derived constructors may only return object or undefined");return function(t){if(void 0===t)throw new ReferenceError("this hasn't been initialised - super() hasn't been called");return t}(t)}(t,r()?Reflect.construct(e,n||[],c(t).constructor):e.apply(t,n))}function r(){try{var t=!Boolean.prototype.valueOf.call(Reflect.construct(Boolean,[],(function(){})))}catch(t){}return(r=function(){return!!t})()}function n(t){var e=function(t,e){if("object"!=typeof t||!t)return t;var r=t[Symbol.toPrimitive];if(void 0!==r){var n=r.call(t,e||"default");if("object"!=typeof n)return n;throw new TypeError("@@toPrimitive must return a primitive value.")}return("string"===e?String:Number)(t)}(t,"string");return"symbol"==typeof e?e:String(e)}function o(t){return o="function"==typeof Symbol&&"symbol"==typeof Symbol.iterator?function(t){return typeof t}:function(t){return t&&"function"==typeof Symbol&&t.constructor===Symbol&&t!==Symbol.prototype?"symbol":typeof t},o(t)}function i(t,e){if(!(t instanceof e))throw new TypeError("Cannot call a class as a function")}function a(t,e){for(var r=0;r<e.length;r++){var o=e[r];o.enumerable=o.enumerable||!1,o.configurable=!0,"value"in o&&(o.writable=!0),Object.defineProperty(t,n(o.key),o)}}function c(t){return c=Object.setPrototypeOf?Object.getPrototypeOf.bind():function(t){return t.__proto__||Object.getPrototypeOf(t)},c(t)}function l(t,e){return l=Object.setPrototypeOf?Object.setPrototypeOf.bind():function(t,e){return t.__proto__=e,t},l(t,e)}function u(t,e){for(;!Object.prototype.hasOwnProperty.call(t,e)&&null!==(t=c(t)););return t}function s(){return s="undefined"!=typeof Reflect&&Reflect.get?Reflect.get.bind():function(t,e,r){var n=u(t,e);if(n){var o=Object.getOwnPropertyDescriptor(n,e);return o.get?o.get.call(arguments.length<3?t:r):o.value}},s.apply(this,arguments)}function f(t){return function(t){if(Array.isArray(t))return p(t)}(t)||function(t){if("undefined"!=typeof Symbol&&null!=t[Symbol.iterator]||null!=t["@@iterator"])return Array.from(t)}(t)||function(t,e){if(!t)return;if("string"==typeof t)return p(t,e);var r=Object.prototype.toString.call(t).slice(8,-1);"Object"===r&&t.constructor&&(r=t.constructor.name);if("Map"===r||"Set"===r)return Array.from(t);if("Arguments"===r||/^(?:Ui|I)nt(?:8|16|32)(?:Clamped)?Array$/.test(r))return p(t,e)}(t)||function(){throw new TypeError("Invalid attempt to spread non-iterable instance.\nIn order to be iterable, non-array objects must have a [Symbol.iterator]() method.")}()}function p(t,e){(null==e||e>t.length)&&(e=t.length);for(var r=0,n=new Array(e);r<e;r++)n[r]=t[r];return n}var h="undefined"!=typeof globalThis?globalThis:"undefined"!=typeof window?window:"undefined"!=typeof global?global:"undefined"!=typeof self?self:{},d=function(t){return t&&t.Math===Math&&t},v=d("object"==typeof globalThis&&globalThis)||d("object"==typeof window&&window)||d("object"==typeof self&&self)||d("object"==typeof h&&h)||d("object"==typeof h&&h)||function(){return this}()||Function("return this")(),g={},y=function(t){try{return!!t()}catch(t){return!0}},b=!y((function(){return 7!==Object.defineProperty({},1,{get:function(){return 7}})[1]})),m=!y((function(){var t=function(){}.bind();return"function"!=typeof t||t.hasOwnProperty("prototype")})),w=m,S=Function.prototype.call,C=w?S.bind(S):function(){return S.apply(S,arguments)},O={},T={}.propertyIsEnumerable,j=Object.getOwnPropertyDescriptor,x=j&&!T.call({1:2},1);O.f=x?function(t){var e=j(this,t);return!!e&&e.enumerable}:T;var E,P,k=function(t,e){return{enumerable:!(1&t),configurable:!(2&t),writable:!(4&t),value:e}},A=m,I=Function.prototype,R=I.call,_=A&&I.bind.bind(R,R),L=A?_:function(t){return function(){return R.apply(t,arguments)}},D=L,F=D({}.toString),M=D("".slice),N=function(t){return M(F(t),8,-1)},$=y,V=N,z=Object,H=L("".split),B=$((function(){return!z("z").propertyIsEnumerable(0)}))?function(t){return"String"===V(t)?H(t,""):z(t)}:z,U=function(t){return null==t},G=U,W=TypeError,K=function(t){if(G(t))throw new W("Can't call method on "+t);return t},q=B,Y=K,J=function(t){return q(Y(t))},X="object"==typeof document&&document.all,Q=void 0===X&&void 0!==X?function(t){return"function"==typeof t||t===X}:function(t){return"function"==typeof t},Z=Q,tt=function(t){return"object"==typeof t?null!==t:Z(t)},et=v,rt=Q,nt=function(t){return rt(t)?t:void 0},ot=function(t,e){return arguments.length<2?nt(et[t]):et[t]&&et[t][e]},it=L({}.isPrototypeOf),at="undefined"!=typeof navigator&&String(navigator.userAgent)||"",ct=v,lt=at,ut=ct.process,st=ct.Deno,ft=ut&&ut.versions||st&&st.version,pt=ft&&ft.v8;pt&&(P=(E=pt.split("."))[0]>0&&E[0]<4?1:+(E[0]+E[1])),!P&&lt&&(!(E=lt.match(/Edge\/(\d+)/))||E[1]>=74)&&(E=lt.match(/Chrome\/(\d+)/))&&(P=+E[1]);var ht=P,dt=ht,vt=y,gt=v.String,yt=!!Object.getOwnPropertySymbols&&!vt((function(){var t=Symbol("symbol detection");return!gt(t)||!(Object(t)instanceof Symbol)||!Symbol.sham&&dt&&dt<41})),bt=yt&&!Symbol.sham&&"symbol"==typeof Symbol.iterator,mt=ot,wt=Q,St=it,Ct=Object,Ot=bt?function(t){return"symbol"==typeof t}:function(t){var e=mt("Symbol");return wt(e)&&St(e.prototype,Ct(t))},Tt=String,jt=function(t){try{return Tt(t)}catch(t){return"Object"}},xt=Q,Et=jt,Pt=TypeError,kt=function(t){if(xt(t))return t;throw new Pt(Et(t)+" is not a function")},At=kt,It=U,Rt=function(t,e){var r=t[e];return It(r)?void 0:At(r)},_t=C,Lt=Q,Dt=tt,Ft=TypeError,Mt={exports:{}},Nt=v,$t=Object.defineProperty,Vt=function(t,e){try{$t(Nt,t,{value:e,configurable:!0,writable:!0})}catch(r){Nt[t]=e}return e},zt=v,Ht=Vt,Bt="__core-js_shared__",Ut=Mt.exports=zt[Bt]||Ht(Bt,{});(Ut.versions||(Ut.versions=[])).push({version:"3.36.0",mode:"global",copyright:"© 2014-2024 Denis Pushkarev (zloirock.ru)",license:"https://github.com/zloirock/core-js/blob/v3.36.0/LICENSE",source:"https://github.com/zloirock/core-js"});var Gt=Mt.exports,Wt=Gt,Kt=function(t,e){return Wt[t]||(Wt[t]=e||{})},qt=K,Yt=Object,Jt=function(t){return Yt(qt(t))},Xt=Jt,Qt=L({}.hasOwnProperty),Zt=Object.hasOwn||function(t,e){return Qt(Xt(t),e)},te=L,ee=0,re=Math.random(),ne=te(1..toString),oe=function(t){return"Symbol("+(void 0===t?"":t)+")_"+ne(++ee+re,36)},ie=Kt,ae=Zt,ce=oe,le=yt,ue=bt,se=v.Symbol,fe=ie("wks"),pe=ue?se.for||se:se&&se.withoutSetter||ce,he=function(t){return ae(fe,t)||(fe[t]=le&&ae(se,t)?se[t]:pe("Symbol."+t)),fe[t]},de=C,ve=tt,ge=Ot,ye=Rt,be=function(t,e){var r,n;if("string"===e&&Lt(r=t.toString)&&!Dt(n=_t(r,t)))return n;if(Lt(r=t.valueOf)&&!Dt(n=_t(r,t)))return n;if("string"!==e&&Lt(r=t.toString)&&!Dt(n=_t(r,t)))return n;throw new Ft("Can't convert object to primitive value")},me=TypeError,we=he("toPrimitive"),Se=function(t,e){if(!ve(t)||ge(t))return t;var r,n=ye(t,we);if(n){if(void 0===e&&(e="default"),r=de(n,t,e),!ve(r)||ge(r))return r;throw new me("Can't convert object to primitive value")}return void 0===e&&(e="number"),be(t,e)},Ce=Ot,Oe=function(t){var e=Se(t,"string");return Ce(e)?e:e+""},Te=tt,je=v.document,xe=Te(je)&&Te(je.createElement),Ee=function(t){return xe?je.createElement(t):{}},Pe=Ee,ke=!b&&!y((function(){return 7!==Object.defineProperty(Pe("div"),"a",{get:function(){return 7}}).a})),Ae=b,Ie=C,Re=O,_e=k,Le=J,De=Oe,Fe=Zt,Me=ke,Ne=Object.getOwnPropertyDescriptor;g.f=Ae?Ne:function(t,e){if(t=Le(t),e=De(e),Me)try{return Ne(t,e)}catch(t){}if(Fe(t,e))return _e(!Ie(Re.f,t,e),t[e])};var $e={},Ve=b&&y((function(){return 42!==Object.defineProperty((function(){}),"prototype",{value:42,writable:!1}).prototype})),ze=tt,He=String,Be=TypeError,Ue=function(t){if(ze(t))return t;throw new Be(He(t)+" is not an object")},Ge=b,We=ke,Ke=Ve,qe=Ue,Ye=Oe,Je=TypeError,Xe=Object.defineProperty,Qe=Object.getOwnPropertyDescriptor,Ze="enumerable",tr="configurable",er="writable";$e.f=Ge?Ke?function(t,e,r){if(qe(t),e=Ye(e),qe(r),"function"==typeof t&&"prototype"===e&&"value"in r&&er in r&&!r.writable){var n=Qe(t,e);n&&n.writable&&(t[e]=r.value,r={configurable:tr in r?r.configurable:n.configurable,enumerable:Ze in r?r.enumerable:n.enumerable,writable:!1})}return Xe(t,e,r)}:Xe:function(t,e,r){if(qe(t),e=Ye(e),qe(r),We)try{return Xe(t,e,r)}catch(t){}if("get"in r||"set"in r)throw new Je("Accessors not supported");return"value"in r&&(t[e]=r.value),t};var rr=$e,nr=k,or=b?function(t,e,r){return rr.f(t,e,nr(1,r))}:function(t,e,r){return t[e]=r,t},ir={exports:{}},ar=b,cr=Zt,lr=Function.prototype,ur=ar&&Object.getOwnPropertyDescriptor,sr=cr(lr,"name"),fr={EXISTS:sr,PROPER:sr&&"something"===function(){}.name,CONFIGURABLE:sr&&(!ar||ar&&ur(lr,"name").configurable)},pr=Q,hr=Gt,dr=L(Function.toString);pr(hr.inspectSource)||(hr.inspectSource=function(t){return dr(t)});var vr,gr,yr,br=hr.inspectSource,mr=Q,wr=v.WeakMap,Sr=mr(wr)&&/native code/.test(String(wr)),Cr=oe,Or=Kt("keys"),Tr=function(t){return Or[t]||(Or[t]=Cr(t))},jr={},xr=Sr,Er=v,Pr=tt,kr=or,Ar=Zt,Ir=Gt,Rr=Tr,_r=jr,Lr="Object already initialized",Dr=Er.TypeError,Fr=Er.WeakMap;if(xr||Ir.state){var Mr=Ir.state||(Ir.state=new Fr);Mr.get=Mr.get,Mr.has=Mr.has,Mr.set=Mr.set,vr=function(t,e){if(Mr.has(t))throw new Dr(Lr);return e.facade=t,Mr.set(t,e),e},gr=function(t){return Mr.get(t)||{}},yr=function(t){return Mr.has(t)}}else{var Nr=Rr("state");_r[Nr]=!0,vr=function(t,e){if(Ar(t,Nr))throw new Dr(Lr);return e.facade=t,kr(t,Nr,e),e},gr=function(t){return Ar(t,Nr)?t[Nr]:{}},yr=function(t){return Ar(t,Nr)}}var $r={set:vr,get:gr,has:yr,enforce:function(t){return yr(t)?gr(t):vr(t,{})},getterFor:function(t){return function(e){var r;if(!Pr(e)||(r=gr(e)).type!==t)throw new Dr("Incompatible receiver, "+t+" required");return r}}},Vr=L,zr=y,Hr=Q,Br=Zt,Ur=b,Gr=fr.CONFIGURABLE,Wr=br,Kr=$r.enforce,qr=$r.get,Yr=String,Jr=Object.defineProperty,Xr=Vr("".slice),Qr=Vr("".replace),Zr=Vr([].join),tn=Ur&&!zr((function(){return 8!==Jr((function(){}),"length",{value:8}).length})),en=String(String).split("String"),rn=ir.exports=function(t,e,r){"Symbol("===Xr(Yr(e),0,7)&&(e="["+Qr(Yr(e),/^Symbol\(([^)]*)\).*$/,"$1")+"]"),r&&r.getter&&(e="get "+e),r&&r.setter&&(e="set "+e),(!Br(t,"name")||Gr&&t.name!==e)&&(Ur?Jr(t,"name",{value:e,configurable:!0}):t.name=e),tn&&r&&Br(r,"arity")&&t.length!==r.arity&&Jr(t,"length",{value:r.arity});try{r&&Br(r,"constructor")&&r.constructor?Ur&&Jr(t,"prototype",{writable:!1}):t.prototype&&(t.prototype=void 0)}catch(t){}var n=Kr(t);return Br(n,"source")||(n.source=Zr(en,"string"==typeof e?e:"")),t};Function.prototype.toString=rn((function(){return Hr(this)&&qr(this).source||Wr(this)}),"toString");var nn=ir.exports,on=Q,an=$e,cn=nn,ln=Vt,un=function(t,e,r,n){n||(n={});var o=n.enumerable,i=void 0!==n.name?n.name:e;if(on(r)&&cn(r,i,n),n.global)o?t[e]=r:ln(e,r);else{try{n.unsafe?t[e]&&(o=!0):delete t[e]}catch(t){}o?t[e]=r:an.f(t,e,{value:r,enumerable:!1,configurable:!n.nonConfigurable,writable:!n.nonWritable})}return t},sn={},fn=Math.ceil,pn=Math.floor,hn=Math.trunc||function(t){var e=+t;return(e>0?pn:fn)(e)},dn=function(t){var e=+t;return e!=e||0===e?0:hn(e)},vn=dn,gn=Math.max,yn=Math.min,bn=dn,mn=Math.min,wn=function(t){var e=bn(t);return e>0?mn(e,9007199254740991):0},Sn=wn,Cn=function(t){return Sn(t.length)},On=J,Tn=function(t,e){var r=vn(t);return r<0?gn(r+e,0):yn(r,e)},jn=Cn,xn=function(t){return function(e,r,n){var o=On(e),i=jn(o);if(0===i)return!t&&-1;var a,c=Tn(n,i);if(t&&r!=r){for(;i>c;)if((a=o[c++])!=a)return!0}else for(;i>c;c++)if((t||c in o)&&o[c]===r)return t||c||0;return!t&&-1}},En={includes:xn(!0),indexOf:xn(!1)},Pn=Zt,kn=J,An=En.indexOf,In=jr,Rn=L([].push),_n=function(t,e){var r,n=kn(t),o=0,i=[];for(r in n)!Pn(In,r)&&Pn(n,r)&&Rn(i,r);for(;e.length>o;)Pn(n,r=e[o++])&&(~An(i,r)||Rn(i,r));return i},Ln=["constructor","hasOwnProperty","isPrototypeOf","propertyIsEnumerable","toLocaleString","toString","valueOf"],Dn=_n,Fn=Ln.concat("length","prototype");sn.f=Object.getOwnPropertyNames||function(t){return Dn(t,Fn)};var Mn={};Mn.f=Object.getOwnPropertySymbols;var Nn=ot,$n=sn,Vn=Mn,zn=Ue,Hn=L([].concat),Bn=Nn("Reflect","ownKeys")||function(t){var e=$n.f(zn(t)),r=Vn.f;return r?Hn(e,r(t)):e},Un=Zt,Gn=Bn,Wn=g,Kn=$e,qn=y,Yn=Q,Jn=/#|\.prototype\./,Xn=function(t,e){var r=Zn[Qn(t)];return r===eo||r!==to&&(Yn(e)?qn(e):!!e)},Qn=Xn.normalize=function(t){return String(t).replace(Jn,".").toLowerCase()},Zn=Xn.data={},to=Xn.NATIVE="N",eo=Xn.POLYFILL="P",ro=Xn,no=v,oo=g.f,io=or,ao=un,co=Vt,lo=function(t,e,r){for(var n=Gn(e),o=Kn.f,i=Wn.f,a=0;a<n.length;a++){var c=n[a];Un(t,c)||r&&Un(r,c)||o(t,c,i(e,c))}},uo=ro,so=function(t,e){var r,n,o,i,a,c=t.target,l=t.global,u=t.stat;if(r=l?no:u?no[c]||co(c,{}):no[c]&&no[c].prototype)for(n in e){if(i=e[n],o=t.dontCallGetSet?(a=oo(r,n))&&a.value:r[n],!uo(l?n:c+(u?".":"#")+n,t.forced)&&void 0!==o){if(typeof i==typeof o)continue;lo(i,o)}(t.sham||o&&o.sham)&&io(i,"sham",!0),ao(r,n,i,t)}},fo=N,po=Array.isArray||function(t){return"Array"===fo(t)},ho=TypeError,vo=b,go=$e,yo=k,bo={};bo[he("toStringTag")]="z";var mo="[object z]"===String(bo),wo=mo,So=Q,Co=N,Oo=he("toStringTag"),To=Object,jo="Arguments"===Co(function(){return arguments}()),xo=wo?Co:function(t){var e,r,n;return void 0===t?"Undefined":null===t?"Null":"string"==typeof(r=function(t,e){try{return t[e]}catch(t){}}(e=To(t),Oo))?r:jo?Co(e):"Object"===(n=Co(e))&&So(e.callee)?"Arguments":n},Eo=L,Po=y,ko=Q,Ao=xo,Io=br,Ro=function(){},_o=ot("Reflect","construct"),Lo=/^\s*(?:class|function)\b/,Do=Eo(Lo.exec),Fo=!Lo.test(Ro),Mo=function(t){if(!ko(t))return!1;try{return _o(Ro,[],t),!0}catch(t){return!1}},No=function(t){if(!ko(t))return!1;switch(Ao(t)){case"AsyncFunction":case"GeneratorFunction":case"AsyncGeneratorFunction":return!1}try{return Fo||!!Do(Lo,Io(t))}catch(t){return!0}};No.sham=!0;var $o=!_o||Po((function(){var t;return Mo(Mo.call)||!Mo(Object)||!Mo((function(){t=!0}))||t}))?No:Mo,Vo=po,zo=$o,Ho=tt,Bo=he("species"),Uo=Array,Go=function(t){var e;return Vo(t)&&(e=t.constructor,(zo(e)&&(e===Uo||Vo(e.prototype))||Ho(e)&&null===(e=e[Bo]))&&(e=void 0)),void 0===e?Uo:e},Wo=function(t,e){return new(Go(t))(0===e?0:e)},Ko=y,qo=ht,Yo=he("species"),Jo=function(t){return qo>=51||!Ko((function(){var e=[];return(e.constructor={})[Yo]=function(){return{foo:1}},1!==e[t](Boolean).foo}))},Xo=so,Qo=y,Zo=po,ti=tt,ei=Jt,ri=Cn,ni=function(t){if(t>9007199254740991)throw ho("Maximum allowed index exceeded");return t},oi=function(t,e,r){vo?go.f(t,e,yo(0,r)):t[e]=r},ii=Wo,ai=Jo,ci=ht,li=he("isConcatSpreadable"),ui=ci>=51||!Qo((function(){var t=[];return t[li]=!1,t.concat()[0]!==t})),si=function(t){if(!ti(t))return!1;var e=t[li];return void 0!==e?!!e:Zo(t)};Xo({target:"Array",proto:!0,arity:1,forced:!ui||!ai("concat")},{concat:function(t){var e,r,n,o,i,a=ei(this),c=ii(a,0),l=0;for(e=-1,n=arguments.length;e<n;e++)if(si(i=-1===e?a:arguments[e]))for(o=ri(i),ni(l+o),r=0;r<o;r++,l++)r in i&&oi(c,l,i[r]);else ni(l+1),oi(c,l++,i);return c.length=l,c}});var fi=N,pi=L,hi=function(t){if("Function"===fi(t))return pi(t)},di=kt,vi=m,gi=hi(hi.bind),yi=function(t,e){return di(t),void 0===e?t:vi?gi(t,e):function(){return t.apply(e,arguments)}},bi=yi,mi=B,wi=Jt,Si=Cn,Ci=Wo,Oi=L([].push),Ti=function(t){var e=1===t,r=2===t,n=3===t,o=4===t,i=6===t,a=7===t,c=5===t||i;return function(l,u,s,f){for(var p,h,d=wi(l),v=mi(d),g=Si(v),y=bi(u,s),b=0,m=f||Ci,w=e?m(l,g):r||a?m(l,0):void 0;g>b;b++)if((c||b in v)&&(h=y(p=v[b],b,d),t))if(e)w[b]=h;else if(h)switch(t){case 3:return!0;case 5:return p;case 6:return b;case 2:Oi(w,p)}else switch(t){case 4:return!1;case 7:Oi(w,p)}return i?-1:n||o?o:w}},ji={forEach:Ti(0),map:Ti(1),filter:Ti(2),some:Ti(3),every:Ti(4),find:Ti(5),findIndex:Ti(6),filterReject:Ti(7)},xi=ji.filter;so({target:"Array",proto:!0,forced:!Jo("filter")},{filter:function(t){return xi(this,t,arguments.length>1?arguments[1]:void 0)}});var Ei={},Pi=_n,ki=Ln,Ai=Object.keys||function(t){return Pi(t,ki)},Ii=b,Ri=Ve,_i=$e,Li=Ue,Di=J,Fi=Ai;Ei.f=Ii&&!Ri?Object.defineProperties:function(t,e){Li(t);for(var r,n=Di(e),o=Fi(e),i=o.length,a=0;i>a;)_i.f(t,r=o[a++],n[r]);return t};var Mi,Ni=ot("document","documentElement"),$i=Ue,Vi=Ei,zi=Ln,Hi=jr,Bi=Ni,Ui=Ee,Gi=Tr("IE_PROTO"),Wi=function(){},Ki=function(t){return"<script>"+t+"</"+"script>"},qi=function(t){t.write(Ki("")),t.close();var e=t.parentWindow.Object;return t=null,e},Yi=function(){try{Mi=new ActiveXObject("htmlfile")}catch(t){}var t,e;Yi="undefined"!=typeof document?document.domain&&Mi?qi(Mi):((e=Ui("iframe")).style.display="none",Bi.appendChild(e),e.src=String("javascript:"),(t=e.contentWindow.document).open(),t.write(Ki("document.F=Object")),t.close(),t.F):qi(Mi);for(var r=zi.length;r--;)delete Yi.prototype[zi[r]];return Yi()};Hi[Gi]=!0;var Ji=Object.create||function(t,e){var r;return null!==t?(Wi.prototype=$i(t),r=new Wi,Wi.prototype=null,r[Gi]=t):r=Yi(),void 0===e?r:Vi.f(r,e)},Xi=he,Qi=Ji,Zi=$e.f,ta=Xi("unscopables"),ea=Array.prototype;void 0===ea[ta]&&Zi(ea,ta,{configurable:!0,value:Qi(null)});var ra=function(t){ea[ta][t]=!0},na=so,oa=ji.find,ia=ra,aa="find",ca=!0;aa in[]&&Array(1).find((function(){ca=!1})),na({target:"Array",proto:!0,forced:ca},{find:function(t){return oa(this,t,arguments.length>1?arguments[1]:void 0)}}),ia(aa);var la=En.includes,ua=ra;so({target:"Array",proto:!0,forced:y((function(){return!Array(1).includes()}))},{includes:function(t){return la(this,t,arguments.length>1?arguments[1]:void 0)}}),ua("includes");var sa=y,fa=function(t,e){var r=[][t];return!!r&&sa((function(){r.call(null,e||function(){return 1},1)}))},pa=so,ha=En.indexOf,da=fa,va=hi([].indexOf),ga=!!va&&1/va([1],1,-0)<0;pa({target:"Array",proto:!0,forced:ga||!da("indexOf")},{indexOf:function(t){var e=arguments.length>1?arguments[1]:void 0;return ga?va(this,t,e)||0:ha(this,t,e)}});var ya=b,ba=L,ma=C,wa=y,Sa=Ai,Ca=Mn,Oa=O,Ta=Jt,ja=B,xa=Object.assign,Ea=Object.defineProperty,Pa=ba([].concat),ka=!xa||wa((function(){if(ya&&1!==xa({b:1},xa(Ea({},"a",{enumerable:!0,get:function(){Ea(this,"b",{value:3,enumerable:!1})}}),{b:2})).b)return!0;var t={},e={},r=Symbol("assign detection"),n="abcdefghijklmnopqrst";return t[r]=7,n.split("").forEach((function(t){e[t]=t})),7!==xa({},t)[r]||Sa(xa({},e)).join("")!==n}))?function(t,e){for(var r=Ta(t),n=arguments.length,o=1,i=Ca.f,a=Oa.f;n>o;)for(var c,l=ja(arguments[o++]),u=i?Pa(Sa(l),i(l)):Sa(l),s=u.length,f=0;s>f;)c=u[f++],ya&&!ma(a,l,c)||(r[c]=l[c]);return r}:xa,Aa=ka;so({target:"Object",stat:!0,arity:2,forced:Object.assign!==Aa},{assign:Aa});var Ia=Jt,Ra=Ai;so({target:"Object",stat:!0,forced:y((function(){Ra(1)}))},{keys:function(t){return Ra(Ia(t))}});var _a=xo,La=mo?{}.toString:function(){return"[object "+_a(this)+"]"};mo||un(Object.prototype,"toString",La,{unsafe:!0});var Da=!y((function(){function t(){}return t.prototype.constructor=null,Object.getPrototypeOf(new t)!==t.prototype})),Fa=Zt,Ma=Q,Na=Jt,$a=Da,Va=Tr("IE_PROTO"),za=Object,Ha=za.prototype,Ba=$a?za.getPrototypeOf:function(t){var e=Na(t);if(Fa(e,Va))return e[Va];var r=e.constructor;return Ma(r)&&e instanceof r?r.prototype:e instanceof za?Ha:null},Ua=b,Ga=y,Wa=L,Ka=Ba,qa=Ai,Ya=J,Ja=Wa(O.f),Xa=Wa([].push),Qa=Ua&&Ga((function(){var t=Object.create(null);return t[2]=2,!Ja(t,2)})),Za=function(t){return function(e){for(var r,n=Ya(e),o=qa(n),i=Qa&&null===Ka(n),a=o.length,c=0,l=[];a>c;)r=o[c++],Ua&&!(i?r in n:Ja(n,r))||Xa(l,t?[r,n[r]]:n[r]);return l}},tc={entries:Za(!0),values:Za(!1)}.values;so({target:"Object",stat:!0},{values:function(t){return tc(t)}});var ec=xo,rc=String,nc=function(t){if("Symbol"===ec(t))throw new TypeError("Cannot convert a Symbol value to a string");return rc(t)},oc="\t\n\v\f\r                　\u2028\u2029\ufeff",ic=K,ac=nc,cc=oc,lc=L("".replace),uc=RegExp("^["+cc+"]+"),sc=RegExp("(^|[^"+cc+"])["+cc+"]+$"),fc=function(t){return function(e){var r=ac(ic(e));return 1&t&&(r=lc(r,uc,"")),2&t&&(r=lc(r,sc,"$1")),r}},pc={start:fc(1),end:fc(2),trim:fc(3)},hc=v,dc=y,vc=L,gc=nc,yc=pc.trim,bc=oc,mc=hc.parseInt,wc=hc.Symbol,Sc=wc&&wc.iterator,Cc=/^[+-]?0x/i,Oc=vc(Cc.exec),Tc=8!==mc(bc+"08")||22!==mc(bc+"0x16")||Sc&&!dc((function(){mc(Object(Sc))}))?function(t,e){var r=yc(gc(t));return mc(r,e>>>0||(Oc(Cc,r)?16:10))}:mc;so({global:!0,forced:parseInt!==Tc},{parseInt:Tc});var jc,xc,Ec,Pc,kc="process"===N(v.process),Ac=L,Ic=kt,Rc=tt,_c=function(t){return Rc(t)||null===t},Lc=String,Dc=TypeError,Fc=function(t,e,r){try{return Ac(Ic(Object.getOwnPropertyDescriptor(t,e)[r]))}catch(t){}},Mc=Ue,Nc=function(t){if(_c(t))return t;throw new Dc("Can't set "+Lc(t)+" as a prototype")},$c=Object.setPrototypeOf||("__proto__"in{}?function(){var t,e=!1,r={};try{(t=Fc(Object.prototype,"__proto__","set"))(r,[]),e=r instanceof Array}catch(t){}return function(r,n){return Mc(r),Nc(n),e?t(r,n):r.__proto__=n,r}}():void 0),Vc=$e.f,zc=Zt,Hc=he("toStringTag"),Bc=nn,Uc=$e,Gc=ot,Wc=function(t,e,r){return r.get&&Bc(r.get,e,{getter:!0}),r.set&&Bc(r.set,e,{setter:!0}),Uc.f(t,e,r)},Kc=b,qc=he("species"),Yc=it,Jc=TypeError,Xc=$o,Qc=jt,Zc=TypeError,tl=Ue,el=function(t){if(Xc(t))return t;throw new Zc(Qc(t)+" is not a constructor")},rl=U,nl=he("species"),ol=function(t,e){var r,n=tl(t).constructor;return void 0===n||rl(r=tl(n)[nl])?e:el(r)},il=m,al=Function.prototype,cl=al.apply,ll=al.call,ul="object"==typeof Reflect&&Reflect.apply||(il?ll.bind(cl):function(){return ll.apply(cl,arguments)}),sl=L([].slice),fl=TypeError,pl=/(?:ipad|iphone|ipod).*applewebkit/i.test(at),hl=v,dl=ul,vl=yi,gl=Q,yl=Zt,bl=y,ml=Ni,wl=sl,Sl=Ee,Cl=function(t,e){if(t<e)throw new fl("Not enough arguments");return t},Ol=pl,Tl=kc,jl=hl.setImmediate,xl=hl.clearImmediate,El=hl.process,Pl=hl.Dispatch,kl=hl.Function,Al=hl.MessageChannel,Il=hl.String,Rl=0,_l={},Ll="onreadystatechange";bl((function(){jc=hl.location}));var Dl=function(t){if(yl(_l,t)){var e=_l[t];delete _l[t],e()}},Fl=function(t){return function(){Dl(t)}},Ml=function(t){Dl(t.data)},Nl=function(t){hl.postMessage(Il(t),jc.protocol+"//"+jc.host)};jl&&xl||(jl=function(t){Cl(arguments.length,1);var e=gl(t)?t:kl(t),r=wl(arguments,1);return _l[++Rl]=function(){dl(e,void 0,r)},xc(Rl),Rl},xl=function(t){delete _l[t]},Tl?xc=function(t){El.nextTick(Fl(t))}:Pl&&Pl.now?xc=function(t){Pl.now(Fl(t))}:Al&&!Ol?(Pc=(Ec=new Al).port2,Ec.port1.onmessage=Ml,xc=vl(Pc.postMessage,Pc)):hl.addEventListener&&gl(hl.postMessage)&&!hl.importScripts&&jc&&"file:"!==jc.protocol&&!bl(Nl)?(xc=Nl,hl.addEventListener("message",Ml,!1)):xc=Ll in Sl("script")?function(t){ml.appendChild(Sl("script")).onreadystatechange=function(){ml.removeChild(this),Dl(t)}}:function(t){setTimeout(Fl(t),0)});var $l={set:jl,clear:xl},Vl=v,zl=b,Hl=Object.getOwnPropertyDescriptor,Bl=function(){this.head=null,this.tail=null};Bl.prototype={add:function(t){var e={item:t,next:null},r=this.tail;r?r.next=e:this.head=e,this.tail=e},get:function(){var t=this.head;if(t)return null===(this.head=t.next)&&(this.tail=null),t.item}};var Ul,Gl,Wl,Kl,ql,Yl=Bl,Jl=/ipad|iphone|ipod/i.test(at)&&"undefined"!=typeof Pebble,Xl=/web0s(?!.*chrome)/i.test(at),Ql=v,Zl=function(t){if(!zl)return Vl[t];var e=Hl(Vl,t);return e&&e.value},tu=yi,eu=$l.set,ru=Yl,nu=pl,ou=Jl,iu=Xl,au=kc,cu=Ql.MutationObserver||Ql.WebKitMutationObserver,lu=Ql.document,uu=Ql.process,su=Ql.Promise,fu=Zl("queueMicrotask");if(!fu){var pu=new ru,hu=function(){var t,e;for(au&&(t=uu.domain)&&t.exit();e=pu.get();)try{e()}catch(t){throw pu.head&&Ul(),t}t&&t.enter()};nu||au||iu||!cu||!lu?!ou&&su&&su.resolve?((Kl=su.resolve(void 0)).constructor=su,ql=tu(Kl.then,Kl),Ul=function(){ql(hu)}):au?Ul=function(){uu.nextTick(hu)}:(eu=tu(eu,Ql),Ul=function(){eu(hu)}):(Gl=!0,Wl=lu.createTextNode(""),new cu(hu).observe(Wl,{characterData:!0}),Ul=function(){Wl.data=Gl=!Gl}),fu=function(t){pu.head||Ul(),pu.add(t)}}var du=fu,vu=function(t){try{return{error:!1,value:t()}}catch(t){return{error:!0,value:t}}},gu=v.Promise,yu="object"==typeof Deno&&Deno&&"object"==typeof Deno.version,bu=!yu&&!kc&&"object"==typeof window&&"object"==typeof document,mu=v,wu=gu,Su=Q,Cu=ro,Ou=br,Tu=he,ju=bu,xu=yu,Eu=ht;wu&&wu.prototype;var Pu=Tu("species"),ku=!1,Au=Su(mu.PromiseRejectionEvent),Iu=Cu("Promise",(function(){var t=Ou(wu),e=t!==String(wu);if(!e&&66===Eu)return!0;if(!Eu||Eu<51||!/native code/.test(t)){var r=new wu((function(t){t(1)})),n=function(t){t((function(){}),(function(){}))};if((r.constructor={})[Pu]=n,!(ku=r.then((function(){}))instanceof n))return!0}return!e&&(ju||xu)&&!Au})),Ru={CONSTRUCTOR:Iu,REJECTION_EVENT:Au,SUBCLASSING:ku},_u={},Lu=kt,Du=TypeError,Fu=function(t){var e,r;this.promise=new t((function(t,n){if(void 0!==e||void 0!==r)throw new Du("Bad Promise constructor");e=t,r=n})),this.resolve=Lu(e),this.reject=Lu(r)};_u.f=function(t){return new Fu(t)};var Mu,Nu,$u,Vu=so,zu=kc,Hu=v,Bu=C,Uu=un,Gu=$c,Wu=function(t,e,r){t&&!r&&(t=t.prototype),t&&!zc(t,Hc)&&Vc(t,Hc,{configurable:!0,value:e})},Ku=function(t){var e=Gc(t);Kc&&e&&!e[qc]&&Wc(e,qc,{configurable:!0,get:function(){return this}})},qu=kt,Yu=Q,Ju=tt,Xu=function(t,e){if(Yc(e,t))return t;throw new Jc("Incorrect invocation")},Qu=ol,Zu=$l.set,ts=du,es=function(t,e){try{1===arguments.length?console.error(t):console.error(t,e)}catch(t){}},rs=vu,ns=Yl,os=$r,is=gu,as=_u,cs="Promise",ls=Ru.CONSTRUCTOR,us=Ru.REJECTION_EVENT,ss=Ru.SUBCLASSING,fs=os.getterFor(cs),ps=os.set,hs=is&&is.prototype,ds=is,vs=hs,gs=Hu.TypeError,ys=Hu.document,bs=Hu.process,ms=as.f,ws=ms,Ss=!!(ys&&ys.createEvent&&Hu.dispatchEvent),Cs="unhandledrejection",Os=function(t){var e;return!(!Ju(t)||!Yu(e=t.then))&&e},Ts=function(t,e){var r,n,o,i=e.value,a=1===e.state,c=a?t.ok:t.fail,l=t.resolve,u=t.reject,s=t.domain;try{c?(a||(2===e.rejection&&ks(e),e.rejection=1),!0===c?r=i:(s&&s.enter(),r=c(i),s&&(s.exit(),o=!0)),r===t.promise?u(new gs("Promise-chain cycle")):(n=Os(r))?Bu(n,r,l,u):l(r)):u(i)}catch(t){s&&!o&&s.exit(),u(t)}},js=function(t,e){t.notified||(t.notified=!0,ts((function(){for(var r,n=t.reactions;r=n.get();)Ts(r,t);t.notified=!1,e&&!t.rejection&&Es(t)})))},xs=function(t,e,r){var n,o;Ss?((n=ys.createEvent("Event")).promise=e,n.reason=r,n.initEvent(t,!1,!0),Hu.dispatchEvent(n)):n={promise:e,reason:r},!us&&(o=Hu["on"+t])?o(n):t===Cs&&es("Unhandled promise rejection",r)},Es=function(t){Bu(Zu,Hu,(function(){var e,r=t.facade,n=t.value;if(Ps(t)&&(e=rs((function(){zu?bs.emit("unhandledRejection",n,r):xs(Cs,r,n)})),t.rejection=zu||Ps(t)?2:1,e.error))throw e.value}))},Ps=function(t){return 1!==t.rejection&&!t.parent},ks=function(t){Bu(Zu,Hu,(function(){var e=t.facade;zu?bs.emit("rejectionHandled",e):xs("rejectionhandled",e,t.value)}))},As=function(t,e,r){return function(n){t(e,n,r)}},Is=function(t,e,r){t.done||(t.done=!0,r&&(t=r),t.value=e,t.state=2,js(t,!0))},Rs=function(t,e,r){if(!t.done){t.done=!0,r&&(t=r);try{if(t.facade===e)throw new gs("Promise can't be resolved itself");var n=Os(e);n?ts((function(){var r={done:!1};try{Bu(n,e,As(Rs,r,t),As(Is,r,t))}catch(e){Is(r,e,t)}})):(t.value=e,t.state=1,js(t,!1))}catch(e){Is({done:!1},e,t)}}};if(ls&&(vs=(ds=function(t){Xu(this,vs),qu(t),Bu(Mu,this);var e=fs(this);try{t(As(Rs,e),As(Is,e))}catch(t){Is(e,t)}}).prototype,(Mu=function(t){ps(this,{type:cs,done:!1,notified:!1,parent:!1,reactions:new ns,rejection:!1,state:0,value:void 0})}).prototype=Uu(vs,"then",(function(t,e){var r=fs(this),n=ms(Qu(this,ds));return r.parent=!0,n.ok=!Yu(t)||t,n.fail=Yu(e)&&e,n.domain=zu?bs.domain:void 0,0===r.state?r.reactions.add(n):ts((function(){Ts(n,r)})),n.promise})),Nu=function(){var t=new Mu,e=fs(t);this.promise=t,this.resolve=As(Rs,e),this.reject=As(Is,e)},as.f=ms=function(t){return t===ds||undefined===t?new Nu(t):ws(t)},Yu(is)&&hs!==Object.prototype)){$u=hs.then,ss||Uu(hs,"then",(function(t,e){var r=this;return new ds((function(t,e){Bu($u,r,t,e)})).then(t,e)}),{unsafe:!0});try{delete hs.constructor}catch(t){}Gu&&Gu(hs,vs)}Vu({global:!0,constructor:!0,wrap:!0,forced:ls},{Promise:ds}),Wu(ds,cs,!1),Ku(cs);var _s={},Ls=_s,Ds=he("iterator"),Fs=Array.prototype,Ms=xo,Ns=Rt,$s=U,Vs=_s,zs=he("iterator"),Hs=function(t){if(!$s(t))return Ns(t,zs)||Ns(t,"@@iterator")||Vs[Ms(t)]},Bs=C,Us=kt,Gs=Ue,Ws=jt,Ks=Hs,qs=TypeError,Ys=C,Js=Ue,Xs=Rt,Qs=yi,Zs=C,tf=Ue,ef=jt,rf=function(t){return void 0!==t&&(Ls.Array===t||Fs[Ds]===t)},nf=Cn,of=it,af=function(t,e){var r=arguments.length<2?Ks(t):e;if(Us(r))return Gs(Bs(r,t));throw new qs(Ws(t)+" is not iterable")},cf=Hs,lf=function(t,e,r){var n,o;Js(t);try{if(!(n=Xs(t,"return"))){if("throw"===e)throw r;return r}n=Ys(n,t)}catch(t){o=!0,n=t}if("throw"===e)throw r;if(o)throw n;return Js(n),r},uf=TypeError,sf=function(t,e){this.stopped=t,this.result=e},ff=sf.prototype,pf=function(t,e,r){var n,o,i,a,c,l,u,s=r&&r.that,f=!(!r||!r.AS_ENTRIES),p=!(!r||!r.IS_RECORD),h=!(!r||!r.IS_ITERATOR),d=!(!r||!r.INTERRUPTED),v=Qs(e,s),g=function(t){return n&&lf(n,"normal",t),new sf(!0,t)},y=function(t){return f?(tf(t),d?v(t[0],t[1],g):v(t[0],t[1])):d?v(t,g):v(t)};if(p)n=t.iterator;else if(h)n=t;else{if(!(o=cf(t)))throw new uf(ef(t)+" is not iterable");if(rf(o)){for(i=0,a=nf(t);a>i;i++)if((c=y(t[i]))&&of(ff,c))return c;return new sf(!1)}n=af(t,o)}for(l=p?t.next:n.next;!(u=Zs(l,n)).done;){try{c=y(u.value)}catch(t){lf(n,"throw",t)}if("object"==typeof c&&c&&of(ff,c))return c}return new sf(!1)},hf=he("iterator"),df=!1;try{var vf=0,gf={next:function(){return{done:!!vf++}},return:function(){df=!0}};gf[hf]=function(){return this},Array.from(gf,(function(){throw 2}))}catch(t){}var yf=gu,bf=function(t,e){try{if(!e&&!df)return!1}catch(t){return!1}var r=!1;try{var n={};n[hf]=function(){return{next:function(){return{done:r=!0}}}},t(n)}catch(t){}return r},mf=Ru.CONSTRUCTOR||!bf((function(t){yf.all(t).then(void 0,(function(){}))})),wf=C,Sf=kt,Cf=_u,Of=vu,Tf=pf;so({target:"Promise",stat:!0,forced:mf},{all:function(t){var e=this,r=Cf.f(e),n=r.resolve,o=r.reject,i=Of((function(){var r=Sf(e.resolve),i=[],a=0,c=1;Tf(t,(function(t){var l=a++,u=!1;c++,wf(r,e,t).then((function(t){u||(u=!0,i[l]=t,--c||n(i))}),o)})),--c||n(i)}));return i.error&&o(i.value),r.promise}});var jf=so,xf=Ru.CONSTRUCTOR,Ef=gu,Pf=ot,kf=Q,Af=un,If=Ef&&Ef.prototype;if(jf({target:"Promise",proto:!0,forced:xf,real:!0},{catch:function(t){return this.then(void 0,t)}}),kf(Ef)){var Rf=Pf("Promise").prototype.catch;If.catch!==Rf&&Af(If,"catch",Rf,{unsafe:!0})}var _f=C,Lf=kt,Df=_u,Ff=vu,Mf=pf;so({target:"Promise",stat:!0,forced:mf},{race:function(t){var e=this,r=Df.f(e),n=r.reject,o=Ff((function(){var o=Lf(e.resolve);Mf(t,(function(t){_f(o,e,t).then(r.resolve,n)}))}));return o.error&&n(o.value),r.promise}});var Nf=_u;so({target:"Promise",stat:!0,forced:Ru.CONSTRUCTOR},{reject:function(t){var e=Nf.f(this);return(0,e.reject)(t),e.promise}});var $f=Ue,Vf=tt,zf=_u,Hf=so,Bf=Ru.CONSTRUCTOR,Uf=function(t,e){if($f(t),Vf(e)&&e.constructor===t)return e;var r=zf.f(t);return(0,r.resolve)(e),r.promise};ot("Promise"),Hf({target:"Promise",stat:!0,forced:Bf},{resolve:function(t){return Uf(this,t)}});var Gf,Wf,Kf=Ue,qf=function(){var t=Kf(this),e="";return t.hasIndices&&(e+="d"),t.global&&(e+="g"),t.ignoreCase&&(e+="i"),t.multiline&&(e+="m"),t.dotAll&&(e+="s"),t.unicode&&(e+="u"),t.unicodeSets&&(e+="v"),t.sticky&&(e+="y"),e},Yf=y,Jf=v.RegExp,Xf=Yf((function(){var t=Jf("a","y");return t.lastIndex=2,null!==t.exec("abcd")})),Qf=Xf||Yf((function(){return!Jf("a","y").sticky})),Zf={BROKEN_CARET:Xf||Yf((function(){var t=Jf("^r","gy");return t.lastIndex=2,null!==t.exec("str")})),MISSED_STICKY:Qf,UNSUPPORTED_Y:Xf},tp=y,ep=v.RegExp,rp=tp((function(){var t=ep(".","s");return!(t.dotAll&&t.test("\n")&&"s"===t.flags)})),np=y,op=v.RegExp,ip=np((function(){var t=op("(?<a>b)","g");return"b"!==t.exec("b").groups.a||"bc"!=="b".replace(t,"$<a>c")})),ap=C,cp=L,lp=nc,up=qf,sp=Zf,fp=Ji,pp=$r.get,hp=rp,dp=ip,vp=Kt("native-string-replace",String.prototype.replace),gp=RegExp.prototype.exec,yp=gp,bp=cp("".charAt),mp=cp("".indexOf),wp=cp("".replace),Sp=cp("".slice),Cp=(Wf=/b*/g,ap(gp,Gf=/a/,"a"),ap(gp,Wf,"a"),0!==Gf.lastIndex||0!==Wf.lastIndex),Op=sp.BROKEN_CARET,Tp=void 0!==/()??/.exec("")[1];(Cp||Tp||Op||hp||dp)&&(yp=function(t){var e,r,n,o,i,a,c,l=this,u=pp(l),s=lp(t),f=u.raw;if(f)return f.lastIndex=l.lastIndex,e=ap(yp,f,s),l.lastIndex=f.lastIndex,e;var p=u.groups,h=Op&&l.sticky,d=ap(up,l),v=l.source,g=0,y=s;if(h&&(d=wp(d,"y",""),-1===mp(d,"g")&&(d+="g"),y=Sp(s,l.lastIndex),l.lastIndex>0&&(!l.multiline||l.multiline&&"\n"!==bp(s,l.lastIndex-1))&&(v="(?: "+v+")",y=" "+y,g++),r=new RegExp("^(?:"+v+")",d)),Tp&&(r=new RegExp("^"+v+"$(?!\\s)",d)),Cp&&(n=l.lastIndex),o=ap(gp,h?r:l,y),h?o?(o.input=Sp(o.input,g),o[0]=Sp(o[0],g),o.index=l.lastIndex,l.lastIndex+=o[0].length):l.lastIndex=0:Cp&&o&&(l.lastIndex=l.global?o.index+o[0].length:n),Tp&&o&&o.length>1&&ap(vp,o[0],r,(function(){for(i=1;i<arguments.length-2;i++)void 0===arguments[i]&&(o[i]=void 0)})),o&&p)for(o.groups=a=fp(null),i=0;i<p.length;i++)a[(c=p[i])[0]]=o[c[1]];return o});var jp=yp;so({target:"RegExp",proto:!0,forced:/./.exec!==jp},{exec:jp});var xp=C,Ep=Zt,Pp=it,kp=qf,Ap=RegExp.prototype,Ip=fr.PROPER,Rp=un,_p=Ue,Lp=nc,Dp=y,Fp=function(t){var e=t.flags;return void 0!==e||"flags"in Ap||Ep(t,"flags")||!Pp(Ap,t)?e:xp(kp,t)},Mp="toString",Np=RegExp.prototype,$p=Np.toString,Vp=Dp((function(){return"/a/b"!==$p.call({source:"a",flags:"b"})})),zp=Ip&&$p.name!==Mp;(Vp||zp)&&Rp(Np,Mp,(function(){var t=_p(this);return"/"+Lp(t.source)+"/"+Lp(Fp(t))}),{unsafe:!0});var Hp=tt,Bp=N,Up=he("match"),Gp=function(t){var e;return Hp(t)&&(void 0!==(e=t[Up])?!!e:"RegExp"===Bp(t))},Wp=TypeError,Kp=function(t){if(Gp(t))throw new Wp("The method doesn't accept regular expressions");return t},qp=he("match"),Yp=function(t){var e=/./;try{"/./"[t](e)}catch(r){try{return e[qp]=!1,"/./"[t](e)}catch(t){}}return!1},Jp=so,Xp=Kp,Qp=K,Zp=nc,th=Yp,eh=L("".indexOf);Jp({target:"String",proto:!0,forced:!th("includes")},{includes:function(t){return!!~eh(Zp(Qp(this)),Zp(Xp(t)),arguments.length>1?arguments[1]:void 0)}});var rh=C,nh=un,oh=jp,ih=y,ah=he,ch=or,lh=ah("species"),uh=RegExp.prototype,sh=function(t,e,r,n){var o=ah(t),i=!ih((function(){var e={};return e[o]=function(){return 7},7!==""[t](e)})),a=i&&!ih((function(){var e=!1,r=/a/;return"split"===t&&((r={}).constructor={},r.constructor[lh]=function(){return r},r.flags="",r[o]=/./[o]),r.exec=function(){return e=!0,null},r[o](""),!e}));if(!i||!a||r){var c=/./[o],l=e(o,""[t],(function(t,e,r,n,o){var a=e.exec;return a===oh||a===uh.exec?i&&!o?{done:!0,value:rh(c,e,r,n)}:{done:!0,value:rh(t,r,e,n)}:{done:!1}}));nh(String.prototype,t,l[0]),nh(uh,o,l[1])}n&&ch(uh[o],"sham",!0)},fh=L,ph=dn,hh=nc,dh=K,vh=fh("".charAt),gh=fh("".charCodeAt),yh=fh("".slice),bh=function(t){return function(e,r){var n,o,i=hh(dh(e)),a=ph(r),c=i.length;return a<0||a>=c?t?"":void 0:(n=gh(i,a))<55296||n>56319||a+1===c||(o=gh(i,a+1))<56320||o>57343?t?vh(i,a):n:t?yh(i,a,a+2):o-56320+(n-55296<<10)+65536}},mh={codeAt:bh(!1),charAt:bh(!0)}.charAt,wh=function(t,e,r){return e+(r?mh(t,e).length:1)},Sh=C,Ch=Ue,Oh=Q,Th=N,jh=jp,xh=TypeError,Eh=function(t,e){var r=t.exec;if(Oh(r)){var n=Sh(r,t,e);return null!==n&&Ch(n),n}if("RegExp"===Th(t))return Sh(jh,t,e);throw new xh("RegExp#exec called on incompatible receiver")},Ph=C,kh=L,Ah=sh,Ih=Ue,Rh=U,_h=K,Lh=ol,Dh=wh,Fh=wn,Mh=nc,Nh=Rt,$h=Eh,Vh=y,zh=Zf.UNSUPPORTED_Y,Hh=Math.min,Bh=kh([].push),Uh=kh("".slice),Gh=!Vh((function(){var t=/(?:)/,e=t.exec;t.exec=function(){return e.apply(this,arguments)};var r="ab".split(t);return 2!==r.length||"a"!==r[0]||"b"!==r[1]})),Wh="c"==="abbc".split(/(b)*/)[1]||4!=="test".split(/(?:)/,-1).length||2!=="ab".split(/(?:ab)*/).length||4!==".".split(/(.?)(.?)/).length||".".split(/()()/).length>1||"".split(/.?/).length;Ah("split",(function(t,e,r){var n="0".split(void 0,0).length?function(t,r){return void 0===t&&0===r?[]:Ph(e,this,t,r)}:e;return[function(e,r){var o=_h(this),i=Rh(e)?void 0:Nh(e,t);return i?Ph(i,e,o,r):Ph(n,Mh(o),e,r)},function(t,o){var i=Ih(this),a=Mh(t);if(!Wh){var c=r(n,i,a,o,n!==e);if(c.done)return c.value}var l=Lh(i,RegExp),u=i.unicode,s=(i.ignoreCase?"i":"")+(i.multiline?"m":"")+(i.unicode?"u":"")+(zh?"g":"y"),f=new l(zh?"^(?:"+i.source+")":i,s),p=void 0===o?4294967295:o>>>0;if(0===p)return[];if(0===a.length)return null===$h(f,a)?[a]:[];for(var h=0,d=0,v=[];d<a.length;){f.lastIndex=zh?0:d;var g,y=$h(f,zh?Uh(a,d):a);if(null===y||(g=Hh(Fh(f.lastIndex+(zh?d:0)),a.length))===h)d=Dh(a,d,u);else{if(Bh(v,Uh(a,h,d)),v.length===p)return v;for(var b=1;b<=y.length-1;b++)if(Bh(v,y[b]),v.length===p)return v;d=h=g}}return Bh(v,Uh(a,h)),v}]}),Wh||!Gh,zh);var Kh=fr.PROPER,qh=y,Yh=oc,Jh=pc.trim;so({target:"String",proto:!0,forced:function(t){return qh((function(){return!!Yh[t]()||"​᠎"!=="​᠎"[t]()||Kh&&Yh[t].name!==t}))}("trim")},{trim:function(){return Jh(this)}});var Xh=Ee("span").classList,Qh=Xh&&Xh.constructor&&Xh.constructor.prototype,Zh=Qh===Object.prototype?void 0:Qh,td=ji.forEach,ed=fa("forEach")?[].forEach:function(t){return td(this,t,arguments.length>1?arguments[1]:void 0)},rd=v,nd={CSSRuleList:0,CSSStyleDeclaration:0,CSSValueList:0,ClientRectList:0,DOMRectList:0,DOMStringList:0,DOMTokenList:1,DataTransferItemList:0,FileList:0,HTMLAllCollection:0,HTMLCollection:0,HTMLFormElement:0,HTMLSelectElement:0,MediaList:0,MimeTypeArray:0,NamedNodeMap:0,NodeList:1,PaintRequestList:0,Plugin:0,PluginArray:0,SVGLengthList:0,SVGNumberList:0,SVGPathSegList:0,SVGPointList:0,SVGStringList:0,SVGTransformList:0,SourceBufferList:0,StyleSheetList:0,TextTrackCueList:0,TextTrackList:0,TouchList:0},od=Zh,id=ed,ad=or,cd=function(t){if(t&&t.forEach!==id)try{ad(t,"forEach",id)}catch(e){t.forEach=id}};for(var ld in nd)nd[ld]&&cd(rd[ld]&&rd[ld].prototype);cd(od);var ud=so,sd=B,fd=J,pd=fa,hd=L([].join);ud({target:"Array",proto:!0,forced:sd!==Object||!pd("join",",")},{join:function(t){return hd(fd(this),void 0===t?",":t)}});var dd=jt,vd=TypeError,gd=sl,yd=Math.floor,bd=function(t,e){var r=t.length;if(r<8)for(var n,o,i=1;i<r;){for(o=i,n=t[i];o&&e(t[o-1],n)>0;)t[o]=t[--o];o!==i++&&(t[o]=n)}else for(var a=yd(r/2),c=bd(gd(t,0,a),e),l=bd(gd(t,a),e),u=c.length,s=l.length,f=0,p=0;f<u||p<s;)t[f+p]=f<u&&p<s?e(c[f],l[p])<=0?c[f++]:l[p++]:f<u?c[f++]:l[p++];return t},md=bd,wd=at.match(/firefox\/(\d+)/i),Sd=!!wd&&+wd[1],Cd=/MSIE|Trident/.test(at),Od=at.match(/AppleWebKit\/(\d+)\./),Td=!!Od&&+Od[1],jd=so,xd=L,Ed=kt,Pd=Jt,kd=Cn,Ad=function(t,e){if(!delete t[e])throw new vd("Cannot delete property "+dd(e)+" of "+dd(t))},Id=nc,Rd=y,_d=md,Ld=fa,Dd=Sd,Fd=Cd,Md=ht,Nd=Td,$d=[],Vd=xd($d.sort),zd=xd($d.push),Hd=Rd((function(){$d.sort(void 0)})),Bd=Rd((function(){$d.sort(null)})),Ud=Ld("sort"),Gd=!Rd((function(){if(Md)return Md<70;if(!(Dd&&Dd>3)){if(Fd)return!0;if(Nd)return Nd<603;var t,e,r,n,o="";for(t=65;t<76;t++){switch(e=String.fromCharCode(t),t){case 66:case 69:case 70:case 72:r=3;break;case 68:case 71:r=4;break;default:r=2}for(n=0;n<47;n++)$d.push({k:e+n,v:r})}for($d.sort((function(t,e){return e.v-t.v})),n=0;n<$d.length;n++)e=$d[n].k.charAt(0),o.charAt(o.length-1)!==e&&(o+=e);return"DGBEFHACIJK"!==o}}));jd({target:"Array",proto:!0,forced:Hd||!Bd||!Ud||!Gd},{sort:function(t){void 0!==t&&Ed(t);var e=Pd(this);if(Gd)return void 0===t?Vd(e):Vd(e,t);var r,n,o=[],i=kd(e);for(n=0;n<i;n++)n in e&&zd(o,e[n]);for(_d(o,function(t){return function(e,r){return void 0===r?-1:void 0===e?1:void 0!==t?+t(e,r)||0:Id(e)>Id(r)?1:-1}}(t)),r=kd(o),n=0;n<r;)e[n]=o[n++];for(;n<i;)Ad(e,n++);return e}});var Wd=C,Kd=Ue,qd=U,Yd=wn,Jd=nc,Xd=K,Qd=Rt,Zd=wh,tv=Eh;sh("match",(function(t,e,r){return[function(e){var r=Xd(this),n=qd(e)?void 0:Qd(e,t);return n?Wd(n,e,r):new RegExp(e)[t](Jd(r))},function(t){var n=Kd(this),o=Jd(t),i=r(e,n,o);if(i.done)return i.value;if(!n.global)return tv(n,o);var a=n.unicode;n.lastIndex=0;for(var c,l=[],u=0;null!==(c=tv(n,o));){var s=Jd(c[0]);l[u]=s,""===s&&(n.lastIndex=Zd(o,Yd(n.lastIndex),a)),u++}return 0===u?null:l}]}));var ev=L,rv=Jt,nv=Math.floor,ov=ev("".charAt),iv=ev("".replace),av=ev("".slice),cv=/\$([$&'`]|\d{1,2}|<[^>]*>)/g,lv=/\$([$&'`]|\d{1,2})/g,uv=ul,sv=C,fv=L,pv=sh,hv=y,dv=Ue,vv=Q,gv=U,yv=dn,bv=wn,mv=nc,wv=K,Sv=wh,Cv=Rt,Ov=function(t,e,r,n,o,i){var a=r+t.length,c=n.length,l=lv;return void 0!==o&&(o=rv(o),l=cv),iv(i,l,(function(i,l){var u;switch(ov(l,0)){case"$":return"$";case"&":return t;case"`":return av(e,0,r);case"'":return av(e,a);case"<":u=o[av(l,1,-1)];break;default:var s=+l;if(0===s)return i;if(s>c){var f=nv(s/10);return 0===f?i:f<=c?void 0===n[f-1]?ov(l,1):n[f-1]+ov(l,1):i}u=n[s-1]}return void 0===u?"":u}))},Tv=Eh,jv=he("replace"),xv=Math.max,Ev=Math.min,Pv=fv([].concat),kv=fv([].push),Av=fv("".indexOf),Iv=fv("".slice),Rv="$0"==="a".replace(/./,"$0"),_v=!!/./[jv]&&""===/./[jv]("a","$0");pv("replace",(function(t,e,r){var n=_v?"$":"$0";return[function(t,r){var n=wv(this),o=gv(t)?void 0:Cv(t,jv);return o?sv(o,t,n,r):sv(e,mv(n),t,r)},function(t,o){var i=dv(this),a=mv(t);if("string"==typeof o&&-1===Av(o,n)&&-1===Av(o,"$<")){var c=r(e,i,a,o);if(c.done)return c.value}var l=vv(o);l||(o=mv(o));var u,s=i.global;s&&(u=i.unicode,i.lastIndex=0);for(var f,p=[];null!==(f=Tv(i,a))&&(kv(p,f),s);){""===mv(f[0])&&(i.lastIndex=Sv(a,bv(i.lastIndex),u))}for(var h,d="",v=0,g=0;g<p.length;g++){for(var y,b=mv((f=p[g])[0]),m=xv(Ev(yv(f.index),a.length),0),w=[],S=1;S<f.length;S++)kv(w,void 0===(h=f[S])?h:String(h));var C=f.groups;if(l){var O=Pv([b],w,m,a);void 0!==C&&kv(O,C),y=mv(uv(o,void 0,O))}else y=Ov(b,a,m,w,C,o);m>=v&&(d+=Iv(a,v,m)+y,v=m+b.length)}return d+Iv(a,v)}]}),!!hv((function(){var t=/./;return t.exec=function(){var t=[];return t.groups={a:"7"},t},"7"!=="".replace(t,"$<a>")}))||!Rv||_v);var Lv,Dv=so,Fv=hi,Mv=g.f,Nv=wn,$v=nc,Vv=Kp,zv=K,Hv=Yp,Bv=Fv("".slice),Uv=Math.min,Gv=Hv("startsWith");Dv({target:"String",proto:!0,forced:!!(Gv||(Lv=Mv(String.prototype,"startsWith"),!Lv||Lv.writable))&&!Gv},{startsWith:function(t){var e=$v(zv(this));Vv(t);var r=Nv(Uv(arguments.length>1?arguments[1]:void 0,e.length)),n=$v(t);return Bv(e,r,r+n.length)===n}});var Wv=t.fn.bootstrapTable.utils;function Kv(t){var e=arguments.length>1&&void 0!==arguments[1]&&arguments[1],r=e?t.constants.classes.select:t.constants.classes.input;return t.options.iconSize?Wv.sprintf("%s %s-%s",r,r,t.options.iconSize):r}function qv(e){return e.options.filterControlContainer?t("".concat(e.options.filterControlContainer)):e.options.height&&e._initialized?e.$tableContainer.find(".fixed-table-header table thead"):e.$header}function Yv(e){return t.inArray(e,[37,38,39,40])>-1}function Jv(t){return qv(t).find('select, input:not([type="checkbox"]):not([type="radio"])')}function Xv(t,e,r,n,o){var i=null==e?"":e.toString().trim();if(i=Wv.removeHTML(Wv.unescapeHTML(i)),r=Wv.removeHTML(Wv.unescapeHTML(r)),!function(t,e){for(var r=function(t){return t[0].options}(t),n=0;n<r.length;n++)if(r[n].value===Wv.unescapeHTML(e))return!0;return!1}(t,i)){var a=new Option(r,i,!1,o?i===n||r===n:i===n);t.get(0).add(a)}}function Qv(t,e,r){var n=t.get(0);if("server"!==e){for(var o=new Array,i=0;i<n.options.length;i++)o[i]=new Array,o[i][0]=n.options[i].text,o[i][1]=n.options[i].value,o[i][2]=n.options[i].selected;for(o.sort((function(t,n){return Wv.sort(t[0],n[0],"desc"===e?-1:1,r)}));n.options.length>0;)n.options[0]=null;for(var a=0;a<o.length;a++){var c=new Option(o[a][0],o[a][1],!1,o[a][2]);n.add(c)}}}function Zv(t){var e=t.$tableHeader;e.css("height",e.find("table").outerHeight(!0))}function tg(e){if(t(e).is("input[type=search]")){var r=0;if("selectionStart"in e)r=e.selectionStart;else if("selection"in document){e.focus();var n=document.selection.createRange(),o=document.selection.createRange().text.length;n.moveStart("character",-e.value.length),r=n.text.length-o}return r}return-1}function eg(e){var r=Jv(e);e._valuesFilterControl=[],r.each((function(){var r=t(this),n=ng(r.attr("class").split(" ").filter((function(t){return t.startsWith("bootstrap-table-filter-control-")})));r=e.options.height&&!e.options.filterControlContainer?e.$el.find(".fixed-table-header .".concat(n)):e.options.filterControlContainer?t("".concat(e.options.filterControlContainer," .").concat(n)):e.$el.find(".".concat(n)),e._valuesFilterControl.push({field:r.closest("[data-field]").data("field"),value:r.val(),position:tg(r.get(0)),hasFocus:r.is(":focus")})}))}function rg(e){var r=null,n=[],o=Jv(e);if(e._valuesFilterControl.length>0){var i=[];o.each((function(o,a){var c,l,u=t(a);if(r=u.closest("[data-field]").data("field"),(n=e._valuesFilterControl.filter((function(t){return t.field===r}))).length>0&&(n[0].hasFocus||n[0].value)){var s=(c=u.get(0),l=n[0],function(){if(l.hasFocus&&c.focus(),Array.isArray(l.value)){var e=t(c);t.each(l.value,(function(t,r){e.find(Wv.sprintf("option[value='%s']",r)).prop("selected",!0)}))}else c.value=l.value;!function(t,e){try{if(t)if(t.createTextRange){var r=t.createTextRange();r.move("character",e),r.select()}else t.setSelectionRange(e,e)}catch(t){}}(c,l.position)});i.push(s)}})),i.length>0&&i.forEach((function(t){return t()}))}}function ng(t){return String(t).replace(/([:.\[\],])/g,"\\$1")}function og(e){var r=e.options.data;t.each(e.header.fields,(function(t,n){var i,a,c,l,u=e.columns[e.fieldsColumnsIndex[n]],s=qv(e).find("select.bootstrap-table-filter-control-".concat(ng(u.field)));if(c=(a=u).filterControl,l=a.searchable,c&&"select"===c.toLowerCase()&&l&&(void 0===(i=u.filterData)||"column"===i.toLowerCase())&&function(t){return t&&t.length>0}(s)){s[0].multiple||0!==s.get(s.length-1).options.length||Xv(s,"",u.filterControlPlaceholder||" ",u.filterDefault);for(var f={},p=0;p<r.length;p++){var h=Wv.getItemField(r[p],n,!1),d=e.options.editable&&u.editable?u._formatter:e.header.formatters[t],v=Wv.calculateObjectValue(e.header,d,[h,r[p],p],h);null==h&&(h=v,u._forceFormatter=!0),u.filterDataCollector&&(v=Wv.calculateObjectValue(e.header,u.filterDataCollector,[h,r[p],v],v)),u.searchFormatter&&(h=v),f[v]=h,"object"!==o(v)||null===v||v.forEach((function(t){Xv(s,t,t,u.filterDefault)}))}for(var g in f)Xv(s,f[g],g,u.filterDefault);e.options.sortSelectOptions&&Qv(s,u.filterOrderBy,e.options)}}))}function ig(e,r){var n,o=!1;t.each(e.columns,(function(i,a){if(n=[],a.visible||e.options.filterControlContainer&&t(".bootstrap-table-filter-control-".concat(ng(a.field))).length>=1){if(a.filterControl||e.options.filterControlContainer)if(e.options.filterControlContainer){var c=t(".bootstrap-table-filter-control-".concat(ng(a.field)));t.each(c,(function(e,r){var n=t(r);if(!n.is("[type=radio]")){var o=a.filterControlPlaceholder||"";n.attr("placeholder",o).val(a.filterDefault)}n.attr("data-field",a.field)})),o=!0}else{var l=a.filterControl.toLowerCase();n.push('<div class="filter-control">'),o=!0,a.searchable&&e.options.filterTemplate[l]&&n.push(e.options.filterTemplate[l](e,a,a.filterControlPlaceholder?a.filterControlPlaceholder:"",a.filterDefault))}else n.push('<div class="no-filter-control"></div>');if(a.filterControl&&""!==a.filterDefault&&void 0!==a.filterDefault&&(t.isEmptyObject(e.filterColumnsPartial)&&(e.filterColumnsPartial={}),a.field in e.filterColumnsPartial||(e.filterColumnsPartial[a.field]=a.filterDefault)),t.each(r.find("th"),(function(e,r){var o=t(r);if(o.data("field")===a.field)return o.find(".filter-control").remove(),o.find(".fht-cell").html(n.join("")),!1})),a.filterData&&"column"!==a.filterData.toLowerCase()){var u,s,f=function(t,e){for(var r=Object.keys(t),n=0;n<r.length;n++)if(r[n]===e)return t[e];return null}(cg,a.filterData.substring(0,a.filterData.indexOf(":")));if(!f)throw new SyntaxError('Error. You should use any of these allowed filter data methods: var, obj, json, url, func. Use like this: var: {key: "value"}');u=a.filterData.substring(a.filterData.indexOf(":")+1,a.filterData.length),Xv(s=r.find(".bootstrap-table-filter-control-".concat(ng(a.field))),"",a.filterControlPlaceholder,a.filterDefault,!0),f(e,u,s,e.options.filterOrderBy,a.filterDefault)}}})),o?(r.off("keyup","input").on("keyup","input",(function(r,n){var o=r.currentTarget,i=r.keyCode;if(i=n?n.keyCode:i,!(e.options.searchOnEnterKey&&13!==i||Yv(i))){var a=t(o);a.is(":checkbox")||a.is(":radio")||(clearTimeout(o.timeoutId||0),o.timeoutId=setTimeout((function(){e.onColumnSearch({currentTarget:o,keyCode:i})}),e.options.searchTimeOut))}})),r.off("change","select",".fc-multipleselect").on("change","select",".fc-multipleselect",(function(r){var n=r.currentTarget,o=r.keyCode,i=t(n),a=i.val();if(Array.isArray(a))for(var c=0;c<a.length;c++)a[c]&&a[c].length>0&&a[c].trim()&&i.find('option[value="'.concat(a[c],'"]')).attr("selected",!0);else a&&a.length>0&&a.trim()?(i.find("option[selected]").removeAttr("selected"),i.find('option[value="'.concat(a,'"]')).attr("selected",!0)):i.find("option[selected]").removeAttr("selected");clearTimeout(n.timeoutId||0),n.timeoutId=setTimeout((function(){e.onColumnSearch({currentTarget:n,keyCode:o})}),e.options.searchTimeOut)})),r.off("mouseup","input:not([type=radio])").on("mouseup","input:not([type=radio])",(function(r){var n=r.currentTarget,o=r.keyCode,i=t(n);""!==i.val()&&setTimeout((function(){""===i.val()&&(clearTimeout(n.timeoutId||0),n.timeoutId=setTimeout((function(){e.onColumnSearch({currentTarget:n,keyCode:o})}),e.options.searchTimeOut))}),1)})),r.off("change","input[type=radio]").on("change","input[type=radio]",(function(t){var r=t.currentTarget,n=t.keyCode;clearTimeout(r.timeoutId||0),r.timeoutId=setTimeout((function(){e.onColumnSearch({currentTarget:r,keyCode:n})}),e.options.searchTimeOut)})),r.find(".date-filter-control").length>0&&t.each(e.columns,(function(t,n){var o=n.filterDefault,i=n.filterControl,a=n.field,c=n.filterDatepickerOptions;if(void 0!==i&&"datepicker"===i.toLowerCase()){var l=r.find(".date-filter-control.bootstrap-table-filter-control-".concat(ng(a)));o&&l.value(o),c.min&&l.attr("min",c.min),c.max&&l.attr("max",c.max),c.step&&l.attr("step",c.step),c.pattern&&l.attr("pattern",c.pattern),l.on("change",(function(t){var r=t.currentTarget;clearTimeout(r.timeoutId||0),r.timeoutId=setTimeout((function(){e.onColumnSearch({currentTarget:r})}),e.options.searchTimeOut)}))}})),"server"!==e.options.sidePagination&&e.triggerSearch(),e.options.filterControlVisible||r.find(".filter-control, .no-filter-control").hide()):r.find(".filter-control, .no-filter-control").hide(),e.trigger("created-controls")}function ag(e){e.options.height&&(0!==e.$tableContainer.find(".fixed-table-header table thead").length&&e.$header.children().find("th[data-field]").each((function(r,n){if("bs-checkbox"!==n.classList[0]){var o=t(n),i=o.data("field"),a=e.$tableContainer.find("th[data-field='".concat(i,"']")).not(o),c=o.find("input"),l=a.find("input");c.length>0&&l.length>0&&c.val()!==l.val()&&c.val(l.val())}})))}var cg={func:function(t,e,r,n,o){var i=window[e].apply();for(var a in i)Xv(r,a,i[a],o);t.options.sortSelectOptions&&Qv(r,n,t.options),rg(t)},obj:function(t,e,r,n,o){var i=e.split("."),a=i.shift(),c=window[a];for(var l in i.length>0&&i.forEach((function(t){c=c[t]})),c)Xv(r,l,c[l],o);t.options.sortSelectOptions&&Qv(r,n,t.options),rg(t)},var:function(t,e,r,n,o){var i=window[e],a=Array.isArray(i);for(var c in i)Xv(r,a?i[c]:c,i[c],o,!0);t.options.sortSelectOptions&&Qv(r,n,t.options),rg(t)},url:function(e,r,n,o,i){t.ajax({url:r,dataType:"json",success:function(t){for(var r in t)Xv(n,r,t[r],i);e.options.sortSelectOptions&&Qv(n,o,e.options),rg(e)}})},json:function(t,e,r,n,o){var i=JSON.parse(e);for(var a in i)Xv(r,a,i[a],o);t.options.sortSelectOptions&&Qv(r,n,t.options),rg(t)}},lg=t.fn.bootstrapTable.utils;Object.assign(t.fn.bootstrapTable.defaults,{filterControl:!1,filterControlVisible:!0,filterControlMultipleSearch:!1,filterControlMultipleSearchDelimiter:",",onColumnSearch:function(t,e){return!1},onCreatedControls:function(){return!1},alignmentSelectControlOptions:void 0,filterTemplate:{input:function(t,e,r,n){return lg.sprintf('<input type="search" class="%s bootstrap-table-filter-control-%s search-input" style="width: 100%;" placeholder="%s" value="%s">',Kv(t),e.field,void 0===r?"":r,void 0===n?"":n)},select:function(t,e){return lg.sprintf('<select class="%s bootstrap-table-filter-control-%s %s" %s style="width: 100%;" dir="%s"></select>',Kv(t,!0),e.field,"","",function(t){switch(void 0===t?"left":t.toLowerCase()){case"left":default:return"ltr";case"right":return"rtl";case"auto":return"auto"}}(t.options.alignmentSelectControlOptions))},datepicker:function(t,e,r){return lg.sprintf('<input type="date" class="%s date-filter-control bootstrap-table-filter-control-%s" style="width: 100%;" value="%s">',Kv(t),e.field,void 0===r?"":r)}},searchOnEnterKey:!1,showFilterControlSwitch:!1,sortSelectOptions:!1,_valuesFilterControl:[],_initialized:!1,_isRendering:!1,_usingMultipleSelect:!1}),Object.assign(t.fn.bootstrapTable.columnDefaults,{filterControl:void 0,filterControlMultipleSelect:!1,filterControlMultipleSelectOptions:{},filterDataCollector:void 0,filterData:void 0,filterDatepickerOptions:{},filterStrictSearch:!1,filterStartsWithSearch:!1,filterControlPlaceholder:"",filterDefault:"",filterOrderBy:"asc",filterCustomSearch:void 0}),Object.assign(t.fn.bootstrapTable.events,{"column-search.bs.table":"onColumnSearch","created-controls.bs.table":"onCreatedControls"}),Object.assign(t.fn.bootstrapTable.defaults.icons,{filterControlSwitchHide:{bootstrap3:"glyphicon-zoom-out icon-zoom-out",bootstrap5:"bi-zoom-out",materialize:"zoom_out"}[t.fn.bootstrapTable.theme]||"fa-search-minus",filterControlSwitchShow:{bootstrap3:"glyphicon-zoom-in icon-zoom-in",bootstrap5:"bi-zoom-in",materialize:"zoom_in"}[t.fn.bootstrapTable.theme]||"fa-search-plus"}),Object.assign(t.fn.bootstrapTable.locales,{formatFilterControlSwitch:function(){return"Hide/Show controls"},formatFilterControlSwitchHide:function(){return"Hide controls"},formatFilterControlSwitchShow:function(){return"Show controls"},formatClearSearch:function(){return"Clear filters"}}),Object.assign(t.fn.bootstrapTable.defaults,t.fn.bootstrapTable.locales),t.fn.bootstrapTable.methods.push("triggerSearch"),t.fn.bootstrapTable.methods.push("clearFilterControl"),t.fn.bootstrapTable.methods.push("toggleFilterControl"),t.BootstrapTable=function(r){function n(){return i(this,n),e(this,n,arguments)}var u,p,h;return function(t,e){if("function"!=typeof e&&null!==e)throw new TypeError("Super expression must either be null or a function");t.prototype=Object.create(e&&e.prototype,{constructor:{value:t,writable:!0,configurable:!0}}),Object.defineProperty(t,"prototype",{writable:!1}),e&&l(t,e)}(n,r),u=n,p=[{key:"init",value:function(){var t=this;this.options.filterControl&&(this._valuesFilterControl=[],this._initialized=!1,this._usingMultipleSelect=!1,this._isRendering=!1,this.$el.on("reset-view.bs.table",lg.debounce((function(){og(t),rg(t)}),3)).on("toggle.bs.table",lg.debounce((function(e,r){t._initialized=!1,r||(og(t),rg(t),t._initialized=!0)}),1)).on("post-header.bs.table",lg.debounce((function(){og(t),rg(t)}),3)).on("column-switch.bs.table",lg.debounce((function(){rg(t),t.options.height&&t.fitHeader()}),1)).on("post-body.bs.table",lg.debounce((function(){t.options.height&&!t.options.filterControlContainer&&t.options.filterControlVisible&&Zv(t),t.$tableLoading.css("top",t.$header.outerHeight()+1)}),1)).on("all.bs.table",(function(){ag(t)}))),s(c(n.prototype),"init",this).call(this)}},{key:"initBody",value:function(){var t=this;s(c(n.prototype),"initBody",this).call(this),this.options.filterControl&&setTimeout((function(){og(t),rg(t)}),3)}},{key:"load",value:function(t){s(c(n.prototype),"load",this).call(this,t),this.options.filterControl&&(ig(this,qv(this)),rg(this))}},{key:"initHeader",value:function(){s(c(n.prototype),"initHeader",this).call(this),this.options.filterControl&&(ig(this,qv(this)),this._initialized=!0)}},{key:"initSearch",value:function(){var e=this,r=this,i=t.isEmptyObject(r.filterColumnsPartial)?null:r.filterColumnsPartial;s(c(n.prototype),"initSearch",this).call(this),"server"!==this.options.sidePagination&&null!==i&&(r.data=i?r.data.filter((function(n,a){var c=[],l=Object.keys(n),u=Object.keys(i),s=l.concat(u.filter((function(t){return!l.includes(t)})));return s.forEach((function(l){var u,s=r.columns[r.fieldsColumnsIndex[l]],f=i[l]||"",p=f.toLowerCase(),h=lg.unescapeHTML(lg.getItemField(n,l,!1));e.options.searchAccentNeutralise&&(p=lg.normalizeAccent(p));var d=[p];e.options.filterControlMultipleSearch&&(d=p.split(e.options.filterControlMultipleSearchDelimiter)),d.forEach((function(e){!0!==u&&(""===(e=e.trim())?u=!0:(s&&(s.searchFormatter||s._forceFormatter)&&(h=t.fn.bootstrapTable.utils.calculateObjectValue(s,r.header.formatters[t.inArray(l,r.header.fields)],[h,n,a],h)),-1!==t.inArray(l,r.header.fields)&&(null==h?u=!1:"object"===o(h)&&s.filterCustomSearch?c.push(r.isValueExpected(f,h,s,l)):"object"===o(h)&&Array.isArray(h)?h.forEach((function(t){u||(u=r.isValueExpected(e,t,s,l))})):"object"!==o(h)||Array.isArray(h)?"string"!=typeof h&&"number"!=typeof h&&"boolean"!=typeof h||(u=r.isValueExpected(e,h,s,l)):Object.values(h).forEach((function(t){u||(u=r.isValueExpected(e,t,s,l))})))))})),c.push(u)})),!c.includes(!1)})):r.data,r.unsortedData=f(r.data))}},{key:"isValueExpected",value:function(t,e,r,n){var o;"select"===r.filterControl&&(e=lg.removeHTML(e.toString().toLowerCase())),this.options.searchAccentNeutralise&&(e=lg.normalizeAccent(e)),o=r.filterStrictSearch||"select"===r.filterControl&&!1!==r.passed.filterStrictSearch?e.toString().toLowerCase()===t.toString().toLowerCase():r.filterStartsWithSearch?0==="".concat(e).toLowerCase().indexOf(t):"datepicker"===r.filterControl?new Date(e).getTime()===new Date(t).getTime():this.options.regexSearch?lg.regexCompare(e,t):"".concat(e).toLowerCase().includes(t);var i=/(?:(<=|=>|=<|>=|>|<)(?:\s+)?(\d+)?|(\d+)?(\s+)?(<=|=>|=<|>=|>|<))/gm.exec(t);if(i){var a=i[1]||"".concat(i[5],"l"),c=i[2]||i[3],l=parseInt(e,10),u=parseInt(c,10);switch(a){case">":case"<l":o=l>u;break;case"<":case">l":o=l<u;break;case"<=":case"=<":case">=l":case"=>l":o=l<=u;break;case">=":case"=>":case"<=l":case"=<l":o=l>=u}}if(r.filterCustomSearch){var s=lg.calculateObjectValue(r,r.filterCustomSearch,[t,e,n,this.options.data],!0);null!==s&&(o=s)}return o}},{key:"initColumnSearch",value:function(t){if(eg(this),t)for(var e in this.filterColumnsPartial=t,this.updatePagination(),t)this.trigger("column-search",e,t[e])}},{key:"initToolbar",value:function(){this.showToolbar=this.showToolbar||this.options.showFilterControlSwitch,this.showSearchClearButton=this.options.filterControl&&this.options.showSearchClearButton,this.options.showFilterControlSwitch&&(this.buttons=Object.assign(this.buttons,{filterControlSwitch:{text:this.options.filterControlVisible?this.options.formatFilterControlSwitchHide():this.options.formatFilterControlSwitchShow(),icon:this.options.filterControlVisible?this.options.icons.filterControlSwitchHide:this.options.icons.filterControlSwitchShow,event:this.toggleFilterControl,attributes:{"aria-label":this.options.formatFilterControlSwitch(),title:this.options.formatFilterControlSwitch()}}})),s(c(n.prototype),"initToolbar",this).call(this)}},{key:"resetSearch",value:function(t){this.options.filterControl&&this.options.showSearchClearButton&&this.clearFilterControl(),s(c(n.prototype),"resetSearch",this).call(this,t)}},{key:"clearFilterControl",value:function(){if(this.options.filterControl){var e=this,r=this.$el.closest("table"),n=function(){var e=[],r=document.cookie.match(/bs\.table\.(filterControl|searchText)/g),n=localStorage;if(r&&t.each(r,(function(r,n){var o=n;/./.test(o)&&(o=o.split(".").pop()),-1===t.inArray(o,e)&&e.push(o)})),n)for(var o=0;o<n.length;o++){var i=n.key(o);/./.test(i)&&(i=i.split(".").pop()),e.includes(i)||e.push(i)}return e}(),o=Jv(e),i=!1,a=0;if(t.each(e._valuesFilterControl,(function(t,e){i=!!i||""!==e.value,e.value=""})),t.each(o,(function(t,e){e.value=""})),rg(e),clearTimeout(a),a=setTimeout((function(){n&&n.length>0&&t.each(n,(function(t,r){void 0!==e.deleteCookie&&e.deleteCookie(r)}))}),e.options.searchTimeOut),i&&o.length>0&&(this.filterColumnsPartial={},o.eq(0).trigger("INPUT"===this.tagName?"keyup":"change",{keyCode:13}),e.options.sortName!==r.data("sortName")||e.options.sortOrder!==r.data("sortOrder"))){var c=this.$header.find(lg.sprintf('[data-field="%s"]',t(o[0]).closest("table").data("sortName")));c.length>0&&(e.onSort({type:"keypress",currentTarget:c}),t(c).find(".sortable").trigger("click"))}}}},{key:"onColumnSearch",value:function(e){var r=this,n=e.currentTarget;Yv(e.keyCode)||(eg(this),this.options.cookie?this._filterControlValuesLoaded=!0:this.options.pageNumber=1,t.isEmptyObject(this.filterColumnsPartial)&&(this.filterColumnsPartial={}),(this.options.searchOnEnterKey?Jv(this).toArray():[n]).forEach((function(e){var n=t(e),o=n.val(),i=o?o.trim():"",a=n.closest("[data-field]").data("field");r.trigger("column-search",a,i),i?r.filterColumnsPartial[a]=i:delete r.filterColumnsPartial[a]})),this.onSearch({currentTarget:n},!1))}},{key:"toggleFilterControl",value:function(){this.options.filterControlVisible=!this.options.filterControlVisible;var t=qv(this).find(".filter-control, .no-filter-control");this.options.filterControlVisible?t.show():(t.hide(),this.clearFilterControl()),this.options.height&&(this.$tableContainer.find(".fixed-table-header table thead").find(".filter-control, .no-filter-control").toggle(this.options.filterControlVisible),Zv(this));var e=this.options.showButtonIcons?this.options.filterControlVisible?this.options.icons.filterControlSwitchHide:this.options.icons.filterControlSwitchShow:"",r=this.options.showButtonText?this.options.filterControlVisible?this.options.formatFilterControlSwitchHide():this.options.formatFilterControlSwitchShow():"";this.$toolbar.find(">.columns").find(".filter-control-switch").html("".concat(lg.sprintf(this.constants.html.icon,this.options.iconsPrefix,e)," ").concat(r))}},{key:"triggerSearch",value:function(){Jv(this).each((function(){var e=t(this);e.is("select")?e.trigger("change"):e.trigger("keyup")}))}},{key:"_toggleColumn",value:function(t,e,r){this._initialized=!1,s(c(n.prototype),"_toggleColumn",this).call(this,t,e,r),ag(this)}}],p&&a(u.prototype,p),h&&a(u,h),Object.defineProperty(u,"prototype",{writable:!1}),n}(t.BootstrapTable)}));
		</script>
		<script>
			function headerStyle(column) {
				return {
				  css: {
				    'padding-left': '15px',
				    'padding-right': '15px',
				    'padding-top': '10px',
				    'padding-bottom': '10px'
				  },
				}
			}
		</script>
'@
}
function New-BootstrapAlert {
    [CmdletBinding()]
    param(
        [Parameter(
            Position = 0,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName
        )]
        [string[]]$Text,
        [Parameter(
            Position = 1
        )]
        [string]$Class = 'Info',
        [string]$Padding = ' p-2',
        [string]$AdditionalClasses
    )
    begin {}
    process {
        ForEach ($String in $Text) {
            "<div class=`"alert$Padding alert-$($Class.ToLower())$AdditionalClasses`">$String</div>"
        }
    }
    end {}
}
function New-BootstrapColumn {
    [OutputType([System.String])]
    [CmdletBinding()]
    param(
        [Parameter(
            Position = 0,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName
        )]
        [System.String[]]$Html,
        [Parameter(
            Position = 1
        )]
        [Int]$Width = 12
    )
    begin {
        $NewHtml = "<div class=`"container`"><div class=`"row justify-content-md-center`">"
    }
    process {
        ForEach ($OldHtml in $Html) {
            $NewHtml = "$NewHtml<div class=`"col col-lg-$Width`">$OldHtml</div>"
        }
    }
    end {
        $NewHtml = "$NewHtml</div></div>"
        return $NewHtml
    }
}
function New-BootstrapDiv {
    [CmdletBinding()]
    param(
        [Parameter(
            Position = 0,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName
        )]
        [string[]]$Text,
        [Parameter(
            Position = 1
        )]
        [string]$Class = 'h-100 p-1 bg-light border rounded-3'
    )
    begin {}
    process {
        ForEach ($String in $Text) {
            "<div class=`"alert alert-$($Class.ToLower())`">$String</div>"
        }
    }
    end {}
}
function New-BootstrapDivWithHeading {
    param (
        [string]$HeadingText,
        [uint16]$HeadingLevel = 5,
        [string]$Content,
        [hashtable]$HeadingsAndContent,
        [string]$Class = 'h-100 p-1 bg-light border rounded-3 small'
    )
    if ($PSBoundParameters.ContainsKey('HeadingsAndContent')) {
        [string]$Text = ForEach ($Key in $HeadingsAndContent.Keys) {
            (New-HtmlHeading $Key -Level $HeadingLevel) +
            $HeadingsAndContent[$Key]
        }
    } else {
        $Text = (New-HtmlHeading $HeadingText -Level $HeadingLevel) +
        $Content
    }
    New-BootstrapDiv -Text $Text -Class $Class
}
function New-BootstrapGrid {
    [CmdletBinding()]
    param(
        [Parameter(
            Position = 0,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName
        )]
        [System.String[]]$Html,
        [string]$Justify = 'Center'
    )
    begin {
        $String = @()
        [decimal]$ExactWidth = 12 / ($Html | Measure-Object).Count
        [int]$Width = [Math]::Floor($ExactWidth)
        $String += "<div class=`"container`"><div class=`"row justify-content-md-$($Justify.ToLower())`">"
    }
    process {
        ForEach ($OldHtml in $Html) {
            $String += "<div class=`"col col-lg-$Width`">$OldHtml</div>"
        }
    }
    end {
        $String += "</div></div>"
        $String -join ''
    }
}
Function New-BootstrapList {
    [CmdletBinding()]
    param(
        [Parameter(
            Position = 0,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName
        )]
        [System.String[]]$HtmlTable
    )
    begin {}
    process {
        ForEach ($Table in $HtmlTable) {
            [String]$NewTable = $Table -replace '<table>', '<table class="table table-striped">'
            Write-Output $NewTable
        }
    }
    end {}
}
function New-BootstrapPanel {
    [CmdletBinding()]
    param(
        [Parameter(
            Position = 0,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName
        )]
        [System.String[]]$Html,
        [string]$Class = 'default',
        [string]$Heading,
        [string]$Footer
    )
    begin {
        $String = @()
        $String += "<div class=`"panel panel-$($Class.ToLower())`">"
        if ($Heading) {
            $String += "<div class=`"panel-heading`">$Heading</div>"
        }
    }
    process {
        ForEach ($OldHtml in $Html) {
            $String += "<div class=`"panel-body`">$OldHtml</div>"
        }
    }
    end {
        if ($Footer) {
            $String += "<div class=`"panel-footer`">$Footer</div>"
        }
        $String += "</div>"
        $String -join ''
    }
}
function New-BootstrapReport {
    [CmdletBinding()]
    param(
        [String]$Title,
        [String]$Description,
        [String[]]$Body,
        [String]$TemplatePath,
        [switch]$JavaScript,
        [String]$ScriptPath,
        [String]$AdditionalScriptHtml
    )
    if ($PSBoundParameters.ContainsKey('TemplatePath')) {
        [String]$Report = Get-Content $TemplatePath -Raw
        if ($null -eq $Report) { Write-Warning "$TemplatePath not loaded.  Failure." }
    } else {
        [String]$Report = Get-BootstrapTemplate
    }
    if ($JavaScript) {
        [string]$ReportScript = Get-JavaScript
        $ReportScript = "$ReportScript$AdditionalScriptHtml"
    } else {
        $ReportScript = $AdditionalScriptHtml
    }
    $URLs = ($Body | Select-String -Pattern 'http[s]?:\/\/[^\s\"\<\>\#\%\{\}\|\\\^\~\[\]\`]*' -AllMatches).Matches.Value | Sort-Object -Unique
    foreach ($URL in $URLs) {
        if ($URL.Length -gt 50) {
            $Body = $Body.Replace($URL, "<a href=$URL>$($URL[0..46] -join '')...</a>")
        } else {
            $Body = $Body.Replace($URL, "<a href=$URL>$URL</a>")
        }
    }
    $Report = $Report.Replace('_ReportTitle_', $Title)
    $Report = $Report.Replace('_ReportDescription_', $Description)
    $Report = $Report.Replace('_ReportBody_', $Body)
    $Report = $Report.Replace('_ReportScript_', $ReportScript)
    return $Report
}
Function New-BootstrapTable {
    [CmdletBinding()]
    param(
        [Parameter(
            Position = 0,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName
        )]
        [System.String[]]$HtmlTable
    )
    begin {}
    process {
        ForEach ($Table in $HtmlTable) {
            $Table -replace '<table>', '<table class="table table-striped text-nowrap small table-sm">'
        }
    }
    end {}
}
function New-HtmlAnchor {
    [CmdletBinding()]
    param(
        [Parameter(
            Position = 0,
            ValueFromPipeline = $true,
            Mandatory = $true
        )]
        [String[]]$Element,
        [Parameter(Mandatory)]
        [String]$Name
    )
    begin {}
    process {
        Write-Output "<h$Level>$Text</h$Level>"
    }
    end {}
}
function New-HtmlHeading {
    [CmdletBinding()]
    param(
        [Parameter(
            Position = 0,
            ValueFromPipeline = $True
        )]
        [String[]]$Text,
        [ValidateRange(1, 6)]
        [Int16]$Level = 1
    )
    begin {}
    process {
        Write-Output "<h$Level>$Text</h$Level>"
    }
    end {}
}
function New-HtmlParagraph {
    [CmdletBinding()]
    param(
        [Parameter(
            Position = 0,
            ValueFromPipeline = $True
        )]
        [String[]]$Text,
        [ValidateRange(1, 6)]
        [Int16]$Level = 1
    )
    begin {}
    process {
        Write-Output "<h$Level>$Text</h$Level>"
    }
    end {}
}
function ConvertTo-DnsFqdn {
    param (
        [string]$ComputerName,
        [string]$ThisHostName = (HOSTNAME.EXE),
        [string]$WhoAmI = (whoami.EXE),
        [hashtable]$LogBuffer = @{}
    )
    $Log = @{
        ThisHostname = $ThisHostname
        Type         = 'Debug'
        Buffer       = $LogBuffer
        WhoAmI       = $WhoAmI
    }
    Write-LogMsg @Log -Text "[System.Net.Dns]::GetHostByName('$ComputerName')"
    [System.Net.Dns]::GetHostByName($ComputerName).HostName 
}
function Export-LogCsv {
    [OutputType([System.String])]
    [CmdletBinding()]
    param(
        [string]$LogFile,
        [hashtable]$Buffer = @{},
        [String]$ThisHostName = (HOSTNAME.EXE),
        [String]$WhoAmI = (whoami.EXE),
        [Hashtable]$LogBuffer = @{},
        [ValidateSet('Silent', 'Quiet', 'Success', 'Debug', 'Verbose', 'Output', 'Host', 'Warning', 'Error', 'Information', $null)]
        [String]$DebugOutputStream = 'Debug',
        [int]$ProgressParentId
    )
    $Log = @{
        Buffer       = $Buffer
        ThisHostname = $ThisHostname
        Type         = $DebugOutputStream
        WhoAmI       = $WhoAmI
    }
    Write-LogMsg @Log -Text "`$Buffer.Values | Sort-Object -Property Timestamp | Export-Csv -Delimiter '$('`t')' -NoTypeInformation -LiteralPath '$LogFile'"
    $Buffer.Values | Sort-Object -Property Timestamp |
    Export-Csv -Delimiter "`t" -NoTypeInformation -LiteralPath $LogFile
    Write-Information $LogFile
}
function Get-CurrentHostName {
}
function Get-CurrentWhoAmI {
    param (
        [string]$ThisHostName = (HOSTNAME.EXE),
        [string]$WhoAmI = (whoami.EXE),
        [hashtable]$LogBuffer = @{}
    )
    $WhoAmI -replace "^$ThisHostname\\", "$ThisHostname\" -replace "$ENV:USERNAME", $ENV:USERNAME
    if (-not $PSBoundParameters.ContainsKey('WhoAmI')) {
        $Log = @{
            ThisHostname = $ThisHostname
            Type         = 'Debug'
            Buffer       = $LogBuffer
            WhoAmI       = $WhoAmI
        }
        Write-LogMsg @Log -Text 'whoami.exe # This command was already run but is now being logged'
    }
}
function New-DatedSubfolder {
    param (
        [parameter(Mandatory)]
        [string]$Root,
        [string]$Suffix
    )
    $Year = Get-Date -Format 'yyyy'
    $Month = Get-Date -Format 'MM'
    $Timestamp = (Get-Date -Format s) -replace ':', '-'
    $NewDir = "$Root\$Year\$Month\$Timestamp$Suffix"
    $null = New-Item -ItemType Directory -Path $NewDir -ErrorAction SilentlyContinue
    Write-Output $NewDir
}
function Write-LogMsg {
    [OutputType([System.String])]
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromPipeline)]
        [string]$Text,
        [ValidateSet('Silent', 'Quiet', 'Success', 'Debug', 'Verbose', 'Output', 'Host', 'Warning', 'Error', 'Information', $null)]
        [string]$Type = 'Information',
        [bool]$AddPrefix = $true,
        [string]$LogFile,
        [bool]$PassThru = $false,
        [string]$ThisHostname = (HOSTNAME.EXE),
        [string]$WhoAmI = (whoami.EXE),
        [hashtable]$Buffer = @{},
        [hashtable[]]$Expand,
        [hashtable]$ExpandKeyMap = @{ Output = '$Parents' ; TargetPath = '$Parents' }
    )
    if ($Type -eq 'Silent') { return }
    $Timestamp = Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.ffffK'
    $OutputToPipeline = $false
    $PSCallStack = Get-PSCallStack
    $Location = $PSCallStack[1].Location
    $Command = $PSCallStack[1].Command
    ForEach ($Splat in $Expand) {
        ForEach ($Key in $Splat.Keys) {
            $Value = $ExpandKeyMap[$Key]
            if (-not $Value) {
                $Value = $Splat[$Key]
                if ($Value) {
                    switch ($Value.GetType().FullName) {
                        'System.Collections.Hashtable' {
                            $Value = "`$$Key"
                            break
                        }
                        'System.Collections.Hashtable+SyncHashtable' {
                            $Value = "`$$Key"
                            break
                        }
                        'System.Int32' {
                            $Value = "($Value)"
                            break
                        }
                        'System.UInt16' {
                            $Value = "($Value)"
                            break
                        }
                        default {
                            $Value = "'$Value'"
                        }
                    }
                } else {
                    continue 
                }
            }
            $Text = "$Text -$Key $Value"
        }
    }
    if ($AddPrefix) {
        $MessageToLog = "$Timestamp`t$ThisHostname`t$WhoAmI`t$Location`t$Command`t$($MyInvocation.ScriptLineNumber)`t$($Type)`t$($Text)"
    } else {
        $MessageToLog = $Text
    }
    Switch ($Type) {
        'Quiet' { break }
        'Success' { Write-Information "SUCCESS: $MessageToLog" ; break }
        'Debug' { Write-Debug "  $MessageToLog" ; break }
        'Verbose' { Write-Verbose $MessageToLog ; break }
        'Host' { Write-Host "HOST:    $MessageToLog" ; break }
        'Warning' { Write-Warning $MessageToLog ; break }
        'Error' { Write-Error $MessageToLog ; break }
        'Output' { $OutputToPipeline = $true ; break }
        default { Write-Information "INFO:    $MessageToLog" ; break }
    }
    if ($PSBoundParameters.ContainsKey('LogFile')) {
        $MessageToLog | Out-File $LogFile -Append
    }
    if ($PassThru -or $OutputToPipeline) {
        $MessageToLog
    }
    [string]$Guid = [guid]::NewGuid()
    [string]$Key = "$Timestamp$Guid"
    $Buffer[$Key] = [pscustomobject]@{
        Timestamp = $Timestamp
        Hostname  = $ThisHostname
        WhoAmI    = $WhoAmI
        Location  = $Location
        Command   = $Command
        Line      = $MyInvocation.ScriptLineNumber
        Type      = $Type
        Text      = $Text
    }
}
$Global:LogMessages = [hashtable]::Synchronized(@{})
function GetDirectories {
    param (
        [Parameter(Mandatory)]
        [string]$TargetPath,
        [string]$SearchPattern = '*',
        [System.IO.SearchOption]$SearchOption = [System.IO.SearchOption]::AllDirectories,
        [string]$DebugOutputStream = 'Debug',
        [string]$ThisHostname = (HOSTNAME.EXE),
        [string]$WhoAmI = (whoami.EXE),
        [hashtable]$LogBuffer = ([hashtable]::Synchronized(@{})),
        [System.Collections.Specialized.OrderedDictionary]$WarningCache = [ordered]@{}
    )
    $LogParams = @{
        ThisHostname = $ThisHostname
        Type         = $DebugOutputStream
        Buffer  = $LogBuffer
        WhoAmI       = $WhoAmI
    }
    Write-LogMsg @LogParams -Text "[System.IO.Directory]::GetDirectories('$TargetPath','$SearchPattern',[System.IO.SearchOption]::$SearchOption)"
    try {
        $result = [System.IO.Directory]::GetDirectories($TargetPath, $SearchPattern, $SearchOption)
        return $result
    }
    catch {
        $WarningCache[$_.Exception.Message.Replace('Exception calling "GetDirectories" with "3" argument(s): ', '').Replace('"', '')] = $null
    }
    Write-LogMsg @LogParams -Text "[System.IO.Directory]::GetDirectories('$TargetPath','$SearchPattern',[System.IO.SearchOption]::TopDirectoryOnly)"
    try {
        $result = [System.IO.Directory]::GetDirectories($TargetPath, $SearchPattern, [System.IO.SearchOption]::TopDirectoryOnly)
    }
    catch {
        $WarningCache[$_.Exception.Message.Replace('Exception calling "GetDirectories" with "3" argument(s): ', '').Replace('"', '')] = $null
        if (-not $PSBoundParameters.ContainsKey('WarningCache')) {
            $LogParams['Type'] = 'Warning' 
            ForEach ($Warning in $WarningCache.Keys) {
                Write-LogMsg @LogParams -Text $_.Exception.Message.Replace('Exception calling "GetDirectories" with "3" argument(s): ', '').Replace('"', '')
            }
        }
        return
    }
    $GetSubfolderParams = @{
        LogBuffer       = $LogBuffer
        ThisHostname      = $ThisHostname
        DebugOutputStream = $DebugOutputStream
        WhoAmI            = $WhoAmI
        SearchOption      = $SearchOption
        SearchPattern     = $SearchPattern
        WarningCache      = $WarningCache
    }
    ForEach ($Child in $result) {
        Write-LogMsg @LogParams -Text "[System.IO.Directory]::GetDirectories('$Child','$SearchPattern',[System.IO.SearchOption]::$SearchOption)"
        GetDirectories -TargetPath $Child @GetSubfolderParams
    }
    if (-not $PSBoundParameters.ContainsKey('WarningCache')) {
        if ($WarningCache.Keys.Count -ge 1) {
            $LogParams['Type'] = 'Warning' 
            Write-LogMsg @LogParams -Text "$($WarningCache.Keys.Count) errors while getting directories of '$TargetPath'.  See verbose log for details."
            $LogParams['Type'] = 'Verbose' 
            ForEach ($Warning in $WarningCache.Keys) {
                Write-LogMsg @LogParams -Text $Warning
            }
        }
    }
}
function ConvertTo-SimpleProperty {
    param (
        $InputObject,
        [string]$Property,
        [hashtable]$PropertyDictionary = @{},
        [string]$Prefix
    )
    $Value = $InputObject.$Property
    [string]$Type = $null
    if ($Value) {
        if (Get-Member -InputObject $Value -Name GetType) {
            [string]$Type = $Value.GetType().FullName
        }
        else {
            [string]$Type = 'System.DirectoryServices.DirectoryEntry'
        }
    }
    switch ($Type) {
        'System.DirectoryServices.DirectoryEntry' {
            $PropertyDictionary["$Prefix$Property"] = ConvertFrom-DirectoryEntry -DirectoryEntry $Value
        }
        'System.DirectoryServices.PropertyCollection' {
            $ThisObject = @{}
            $KeyCount = $Value.Keys.$KeyCount
            if (-not $KeyCount -gt 0) {
                continue
            }
            ForEach ($ThisProperty in $Value.Keys) {
                $ThisPropertyString = ConvertFrom-PropertyValueCollectionToString -PropertyValueCollection $Value[$ThisProperty]
                $ThisObject[$ThisProperty] = $ThisPropertyString
                $PropertyDictionary["$Prefix$ThisProperty"] = $ThisPropertyString
            }
            $PropertyDictionary["$Prefix$Property"] = [PSCustomObject]$ThisObject
            continue
        }
        'System.DirectoryServices.PropertyValueCollection' {
            $PropertyDictionary["$Prefix$Property"] = ConvertFrom-PropertyValueCollectionToString -PropertyValueCollection $Value
            continue
        }
        'System.Object[]' {
            $PropertyDictionary["$Prefix$Property"] = $Value
            continue
        }
        'System.Object' {
            $PropertyDictionary["$Prefix$Property"] = $Value
            continue
        }
        'System.DirectoryServices.SearchResult' {
            $PropertyDictionary["$Prefix$Property"] = ConvertFrom-SearchResult -SearchResult $Value
            continue
        }
        'System.DirectoryServices.ResultPropertyCollection' {
            $ThisObject = @{}
            ForEach ($ThisProperty in $Value.Keys) {
                $ThisPropertyString = ConvertFrom-ResultPropertyValueCollectionToString -ResultPropertyValueCollection $Value[$ThisProperty]
                $ThisObject[$ThisProperty] = $ThisPropertyString
                $PropertyDictionary["$Prefix$ThisProperty"] = $ThisPropertyString
            }
            $PropertyDictionary["$Prefix$Property"] = [PSCustomObject]$ThisObject
            continue
        }
        'System.DirectoryServices.ResultPropertyValueCollection' {
            $PropertyDictionary["$Prefix$Property"] = ConvertFrom-ResultPropertyValueCollectionToString -ResultPropertyValueCollection $Value
            continue
        }
        'System.Management.Automation.PSCustomObject' {
            $PropertyDictionary["$Prefix$Property"] = $Value
            continue
        }
        'System.Collections.Hashtable' {
            $PropertyDictionary["$Prefix$Property"] = [PSCustomObject]$Value
            continue
        }
        'System.Byte[]' {
            $PropertyDictionary["$Prefix$Property"] = ConvertTo-DecStringRepresentation -ByteArray $Value
        }
        default {
            $PropertyDictionary["$Prefix$Property"] = "$Value"
            continue
        }
    }
}
function Expand-Acl {
    param (
        [Parameter(
            ValueFromPipeline
        )]
        [PSObject]$InputObject
    )
    process {
        ForEach ($ThisInputObject in $InputObject) {
            $ObjectProperties = @{
                SourceAccessList = $ThisInputObject
            }
            $AllACEs = $ThisInputObject.Access
            $AceProperties = (Get-Member -InputObject $AllACEs[0] -MemberType Property, CodeProperty, ScriptProperty, NoteProperty).Name
            ForEach ($ThisACE in $AllACEs) {
                ForEach ($ThisProperty in $AceProperties) {
                    $ObjectProperties["$Prefix$ThisProperty"] = $ThisACE.$ThisProperty
                }
                [PSCustomObject]$ObjectProperties
            }
        }
    }
}
function Find-ServerNameInPath {
    [OutputType([System.String])]
    param (
        [string]$LiteralPath,
        [string]$ThisFqdn = ([System.Net.Dns]::GetHostByName((HOSTNAME.EXE)).HostName)
    )
    if ($LiteralPath[1] -eq '\') {
        $SkippedFirstTwoChars = $LiteralPath.Substring(2, $LiteralPath.Length - 2)
        $NextSlashIndex = $SkippedFirstTwoChars.IndexOf('\')
        $SkippedFirstTwoChars.Substring(0, $NextSlashIndex).Replace('?', $ThisFqdn)
    }
    else {
        $ThisFqdn
    }
}
function Format-SecurityPrincipalMember {
    param (
        [object[]]$ResolvedID,
        [string]$ParentIdentityReference,
        [object[]]$Access,
        [hashtable]$PrincipalsByResolvedID = ([hashtable]::Synchronized(@{}))
    )
    ForEach ($ID in $ResolvedID) {
        $Principal = $PrincipalsByResolvedID[$ID]
        $OutputProperties = @{
            Access                          = $Access
            ParentIdentityReferenceResolved = $ParentIdentityReference
        }
        if ($Principal.DirectoryEntry) {
            $InputProperties = (Get-Member -InputObject $Principal.DirectoryEntry -MemberType Property, CodeProperty, ScriptProperty, NoteProperty).Name
            ForEach ($ThisProperty in $InputProperties) {
                $OutputProperties[$ThisProperty] = $Principal.DirectoryEntry.$ThisProperty
            }
        }
        $InputProperties = (Get-Member -InputObject $Principal -MemberType Property, CodeProperty, ScriptProperty, NoteProperty).Name
        ForEach ($ThisProperty in $InputProperties) {
            $OutputProperties[$ThisProperty] = $Principal.$ThisProperty
        }
        [PSCustomObject]$OutputProperties
    }
}
function Format-SecurityPrincipalMemberUser {
    param ([object]$InputObject)
    if ($InputObject.Properties) {
        $sAmAccountName = $InputObject.Properties['sAmAccountName']
        if ("$sAmAccountName" -eq '') {
            $sAmAccountName = $InputObject.Properties['Name']
        }
    }
    if ("$sAmAccountName" -eq '') {
        $sAmAccountName = $InputObject.Name
    }
    "$($InputObject.Domain.Netbios)\$sAmAccountName"
}
function Format-SecurityPrincipalName {
    param ([object]$InputObject)
    if ($InputObject.DirectoryEntry.Properties) {
        $ThisName = $InputObject.DirectoryEntry.Properties['name']
    }
    if ("$ThisName" -eq '') {
        $InputObject.Name -replace [regex]::Escape("$($InputObject.DomainNetBios)\"), ''
    }
    else {
        $ThisName
    }
}
function Format-SecurityPrincipalUser {
    param ([object]$InputObject)
    if ($InputObject.Properties) {
        $sAmAccountName = $InputObject.Properties['sAmAccountName']
    }
    if ("$sAmAccountName" -eq '') {
        $InputObject.Name
    }
    else {
        $sAmAccountName
    }
}
function Get-DirectorySecurity {
    param(
        [string]$LiteralPath,
        [Switch]$IncludeInherited,
        [System.Security.AccessControl.AccessControlSections]$Sections = (
            [System.Security.AccessControl.AccessControlSections]::Access -bor
            [System.Security.AccessControl.AccessControlSections]::Owner -bor
            [System.Security.AccessControl.AccessControlSections]::Group),
        [bool]$IncludeExplicitRules = $true,
        [System.Type]$AccountType = [System.Security.Principal.SecurityIdentifier],
        [string]$DebugOutputStream = 'Debug',
        [string]$ThisHostname = (HOSTNAME.EXE),
        [string]$WhoAmI = (whoami.EXE),
        [System.Collections.Concurrent.ConcurrentDictionary[String, PSCustomObject]]$OwnerCache = [System.Collections.Concurrent.ConcurrentDictionary[String, PSCustomObject]]::new(),
        [hashtable]$LogBuffer = ([hashtable]::Synchronized(@{})),
        [hashtable]$ACLsByPath = [hashtable]::Synchronized(@{})
    )
    $LogParams = @{
        ThisHostname = $ThisHostname
        Type         = $DebugOutputStream
        Buffer       = $LogBuffer
        WhoAmI       = $WhoAmI
    }
    Write-LogMsg @LogParams -Text "[System.Security.AccessControl.DirectorySecurity]::new('$LiteralPath', '$Sections')"
    $DirectorySecurity = & { [System.Security.AccessControl.DirectorySecurity]::new(
            $LiteralPath,
            $Sections
        )
    } 2>$null
    if ($null -eq $DirectorySecurity) {
        $LogParams['Type'] = 'Warning' 
        Write-LogMsg @LogParams -Text "# Found no ACL for '$LiteralPath'"
        $LogParams['Type'] = $DebugOutputStream
        return
    }
    $AclProperties = @{
        PSTypeName = 'Permission.Item'
    }
    $AclPropertyNames = (Get-Member -InputObject $DirectorySecurity -MemberType Property, CodeProperty, ScriptProperty, NoteProperty).Name
    ForEach ($ThisProperty in $AclPropertyNames) {
        $AclProperties[$ThisProperty] = $DirectorySecurity.$ThisProperty
    }
    $AclProperties['Path'] = $LiteralPath
    Write-LogMsg @LogParams -Text "[System.Security.AccessControl.DirectorySecurity]::new('$LiteralPath', '$Sections').GetOwner([$AccountType])"
    $AclProperties['Owner'] = $DirectorySecurity.GetOwner($AccountType).Value
    Write-LogMsg @LogParams -Text "[System.Security.AccessControl.DirectorySecurity]::new('$LiteralPath', '$Sections').GetAccessRules(`$$IncludeExplicitRules, `$$IncludeInherited, [$AccountType])"
    $AclProperties['Access'] = $DirectorySecurity.GetAccessRules($IncludeExplicitRules, $IncludeInherited, $AccountType)
    $ACLsByPath[$LiteralPath] = [PSCustomObject]$AclProperties
}
function Get-FileSystemAccessRule {
    param(
        [System.Security.AccessControl.DirectorySecurity]$DirectorySecurity,
        [Switch]$IncludeInherited,
        [bool]$IncludeExplicitRules = $true,
        [System.Type]$AccountType = [System.Security.Principal.SecurityIdentifier],
        [string]$DebugOutputStream = 'Silent',
        [string]$TodaysHostname = (HOSTNAME.EXE),
        [string]$WhoAmI = (whoami.EXE),
        [hashtable]$LogBuffer = ([hashtable]::Synchronized(@{}))
    )
    $AccessRules = $DirectorySecurity.GetAccessRules($IncludeExplicitRules, $IncludeInherited, $AccountType)
    if ($AccessRules.Count -lt 1) {
        Write-LogMsg @LogParams -Text "# Found no matching access rules for '$LiteralPath'"
        return
    }
    $ACEPropertyNames = (Get-Member -InputObject $AccessRules[0] -MemberType Property, CodeProperty, ScriptProperty, NoteProperty).Name
    ForEach ($ThisAccessRule in $AccessRules) {
        $ACEProperties = @{
            SourceAccessList = $SourceAccessList
            Source           = 'Discretionary Access List'
        }
        ForEach ($ThisProperty in $ACEPropertyNames) {
            $ACEProperties[$ThisProperty] = $ThisAccessRule.$ThisProperty
        }
        [PSCustomObject]$ACEProperties
    }
    [PSCustomObject]@{
        SourceAccessList  = $SourceAccessList
        Source            = 'Ownership'
        IsInherited       = $false
        IdentityReference = $DirectorySecurity.Owner -replace '^O:', ''
        FileSystemRights  = [System.Security.AccessControl.FileSystemRights]::FullControl
        InheritanceFlags  = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
        PropagationFlags  = [System.Security.AccessControl.PropagationFlags]::None
        AccessControlType = [System.Security.AccessControl.AccessControlType]::Allow
    }
}
function Get-OwnerAce {
    param (
        [string]$Item,
        [hashtable]$ACLsByPath = [hashtable]::Synchronized(@{})
    )
    $InheritanceFlags = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
    $SourceAccessList = $ACLsByPath[$Item]
    $ThisParent = $Item.Substring(0, [math]::Max($Item.LastIndexOf('\'), 0)) 
    $ParentOwner = $ACLsByPath[$ThisParent].Owner
    if (
        $SourceAccessList.Owner -ne $ParentOwner -and
        $SourceAccessList.Owner -ne $ParentOwner.IdentityReference
    ) {
        $ACLsByPath[$Item].Owner = [PSCustomObject]@{
            IdentityReference = $SourceAccessList.Owner
            AccessControlType = [System.Security.AccessControl.AccessControlType]::Allow
            FileSystemRights  = [System.Security.AccessControl.FileSystemRights]::FullControl
            InheritanceFlags  = $InheritanceFlags
            IsInherited       = $false
            PropagationFlags  = [System.Security.AccessControl.PropagationFlags]::None
        }
    }
}
function Get-ServerFromFilePath {
    param (
        [string]$FilePath,
        [string]$ThisFqdn = ([System.Net.Dns]::GetHostByName((HOSTNAME.EXE)).HostName)
    )
    if ($FilePath[1] -eq '\') {
        $SkippedFirstTwoChars = $FilePath.Substring(2, $FilePath.Length - 2)
        $NextSlashIndex = $SkippedFirstTwoChars.IndexOf('\')
        $SkippedFirstTwoChars.Substring(0, $NextSlashIndex)
    }
    else {
        $ThisFqdn
    }
}
function Get-Subfolder {
    [CmdletBinding()]
    param (
        [string]$TargetPath,
        [int]$RecurseDepth = -1,
        [string]$DebugOutputStream = 'Debug',
        [string]$ThisHostname = (HOSTNAME.EXE),
        [string]$WhoAmI = (whoami.EXE),
        [hashtable]$LogBuffer = ([hashtable]::Synchronized(@{})),
        [hashtable]$Output = [hashtable]::Synchronized(@{})
    )
    $LogParams = @{
        ThisHostname = $ThisHostname
        Type         = $DebugOutputStream
        Buffer  = $LogBuffer
        WhoAmI       = $WhoAmI
    }
    $GetSubfolderParams = @{
        LogBuffer       = $LogBuffer
        ThisHostname      = $ThisHostname
        DebugOutputStream = $DebugOutputStream
        WhoAmI            = $WhoAmI
    }
    if ($RecurseDepth -eq -1) {
        $DepthString = '∞'
    }
    else {
        $DepthString = $RecurseDepth
    }
    $Output[$TargetPath] = if ($Host.Version.Major -gt 2) {
        switch ($RecurseDepth) {
            -1 {
                GetDirectories -TargetPath $TargetPath -SearchOption ([System.IO.SearchOption]::AllDirectories) @GetSubfolderParams
            }
            0 {}
            1 {
                GetDirectories -TargetPath $TargetPath -SearchOption ([System.IO.SearchOption]::TopDirectoryOnly) @GetSubfolderParams
            }
            Default {
                $RecurseDepth = $RecurseDepth - 1
                Write-LogMsg @LogParams -Text "Get-ChildItem '$TargetPath' -Force -Name -Recurse -Attributes Directory -Depth $RecurseDepth"
                (Get-ChildItem $TargetPath -Force -Recurse -Attributes Directory -Depth $RecurseDepth).FullName
            }
        }
    }
    else {
        Write-LogMsg @LogParams -Text "Get-ChildItem '$TargetPath' -Recurse"
        Get-ChildItem $TargetPath -Recurse | Where-Object -FilterScript { $_.PSIsContainer } | ForEach-Object { $_.FullName }
    }
}
function New-NtfsAclIssueReport {
    param (
        $FolderPermissions,
        $UserPermissions,
        [scriptblock]$GroupNameRule = { $true },
        [string]$ThisHostName = (HOSTNAME.EXE),
        [string]$WhoAmI = (whoami.EXE),
        [hashtable]$LogBuffer = ([hashtable]::Synchronized(@{}))
    )
    $LogParams = @{
        ThisHostname = $ThisHostname
        Type         = 'Verbose'
        Buffer       = $LogBuffer
        WhoAmI       = $WhoAmI
    }
    $IssuesDetected = $false
    $FoldersWithBrokenInheritance = $FolderPermissions |
    Select-Object -Skip 1 |
    Where-Object -FilterScript {
        @($_.Group.FolderInheritanceEnabled)[0] -eq $false -and
                (($_.Name -replace ([regex]::Escape($TargetPath)), '' -split '\\') | Measure-Object).Count -ne 2
    }
    $Count = ($FoldersWithBrokenInheritance | Measure-Object).Count
    if ($Count -gt 0) {
        $IssuesDetected = $true
        $Txt = "folders with broken inheritance: $($FoldersWithBrokenInheritance.Name -join "`r`n")"
    }
    else {
        $Txt = 'OK'
    }
    Write-LogMsg @LogParams -Text "$Count $Txt"
    $ViolatesNamingConvention = [scriptblock]::Create("!($GroupNameRule)")
    $NonCompliantGroups = $SecurityPrincipals |
    Where-Object -FilterScript { $_.ObjectType -contains 'Group' } |
    Where-Object -FilterScript $ViolatesNamingConvention |
    Select-Object -ExpandProperty Group |
    ForEach-Object { "$($_.IdentityReference) on '$($_.Path)'" }
    $Count = ($NonCompliantGroups | Measure-Object).Count
    if ($Count -gt 0) {
        $IssuesDetected = $true
        $Txt = "groups that don't match naming convention: $($NonCompliantGroups -join "`r`n")"
    }
    else {
        $Txt = 'OK'
    }
    Write-LogMsg @LogParams -Text "$Count $Txt"
    $UserACEs = $UserPermissions.Group |
    Where-Object -FilterScript {
        $_.ObjectType -contains 'User' -and
        $_.ACEIdentityReference -ne 'S-1-5-18' 
    } |
    ForEach-Object { "$($_.User) on '$($_.SourceAclPath)'" } |
    Sort-Object -Unique
    $Count = ($UserACEs | Measure-Object).Count
    if ($Count -gt 0) {
        $IssuesDetected = $true
        $Txt = "users with ACEs: $($UserACEs -join "`r`n")"
    }
    else {
        $Txt = 'OK'
    }
    Write-LogMsg @LogParams -Text "$Count $Txt"
    $SIDsToCleanup = $UserPermissions.Group.NtfsAccessControlEntries |
    Where-Object -FilterScript { $_.IdentityReference -match 'S-\d+-\d+-\d+-\d+-\d+\-\d+\-\d+' } |
    ForEach-Object { "$($_.IdentityReference) on '$($_.Path)'" } |
    Sort-Object -Unique
    $Count = ($SIDsToCleanup | Measure-Object).Count
    if ($Count -gt 0) {
        $IssuesDetected = $true
        $Txt = "ACEs for unresolvable SIDs: $($SIDsToCleanup -join "`r`n")"
    }
    else {
        $Txt = 'OK'
    }
    Write-LogMsg @LogParams -Text "$Count $Txt"
    $FoldersWithCreatorOwner = ($UserPermissions | ? { $_.Name -match 'CREATOR OWNER' }).Group.NtfsAccessControlEntries.Path | Sort -Unique
    $Count = ($FoldersWithCreatorOwner | Measure-Object).Count
    if ($Count -gt 0) {
        $IssuesDetected = $true
        $Txt = "folders with 'CREATOR OWNER' ACEs: $($FoldersWithCreatorOwner -join "`r`n")"
    }
    else {
        $Txt = 'OK'
    }
    Write-LogMsg @LogParams -Text "$Count $Txt"
    [PSCustomObject]@{
        IssueDetected                = $IssuesDetected
        FoldersWithBrokenInheritance = $FoldersWithBrokenInheritance
        NonCompliantGroups           = $NonCompliantGroups
        UserACEs                     = $UserACEs
        SIDsToCleanup                = $SIDsToCleanup
        FoldersWithCreatorOwner      = $FoldersWithCreatorOwner
    }
}
function Add-PsCommand {
    param(
        [Parameter(ValueFromPipeline = $true)]
        [powershell[]]$PowershellInterface,
        [Parameter(Position = 0)]
        $Command,
        [pscustomobject]$CommandInfo,
        [switch]$Force,
        [string]$DebugOutputStream = 'Silent',
        [string]$TodaysHostname = (HOSTNAME.EXE),
        [string]$WhoAmI = (whoami.EXE),
        [hashtable]$LogBuffer = $Global:LogMessages
    )
    begin {
        $LogParams = @{
            Buffer       = $LogBuffer
            ThisHostname = $TodaysHostname
            Type         = $DebugOutputStream
            WhoAmI       = $WhoAmI
        }
        $CommandInfoParams = @{
            DebugOutputStream = $DebugOutputStream
            TodaysHostname    = $TodaysHostname
            WhoAmI            = $WhoAmI
            LogBuffer         = $LogBuffer
        }
        if ($CommandInfo -eq $null) {
            $CommandInfo = Get-PsCommandInfo @CommandInfoParams -Command $Command
        }
    }
    process {
        ForEach ($ThisPowershell in $PowershellInterface) {
            switch ($CommandInfo.CommandType) {
                'Alias' {
                    $CommandInfo = Get-PsCommandInfo @CommandInfoParams -Command $CommandInfo.CommandInfo.Definition
                    $null = Add-PsCommand @CommandInfoParams -Command $CommandInfo.CommandInfo.Definition -CommandInfo $CommandInfo -PowershellInterface $ThisPowerShell
                }
                'Function' {
                    if ($Force) {
                        Write-LogMsg @LogParams -Text " # Adding command '$Command' of type '$($CommandInfo.CommandType)' (treating it as a command instead of a Function because -Force was used)"
                        Write-LogMsg @LogParams -Text "`$PowershellInterface.AddStatement().AddCommand('$Command')"
                        $null = $ThisPowershell.AddStatement().AddCommand($Command)
                    } else {
                        [string]$ThisFunction = "function $($CommandInfo.CommandInfo.Name) {`r`n$($CommandInfo.CommandInfo.Definition)`r`n}"
                        Write-LogMsg @LogParams -Text " # Adding Script (the Definition of a Function, `$CommandInfo.CommandInfo.Definition not expanded below for brevity)"
                        Write-LogMsg @LogParams -Text "`$PowershellInterface.AddScript('$ThisFunction')"
                        $null = $ThisPowershell.AddScript($ThisFunction)
                    }
                }
                'ExternalScript' {
                    Write-LogMsg @LogParams -Text " # Adding Script (the ScriptBlock of an ExternalScript, `$CommandInfo.ScriptBlock not expanded below for brevity)"
                    Write-LogMsg @LogParams -Text "`$PowershellInterface.AddScript('$($CommandInfo.ScriptBlock)')"
                    $null = $ThisPowershell.AddScript($CommandInfo.ScriptBlock)
                }
                'ScriptBlock' {
                    Write-LogMsg @LogParams -Text " # Adding Script (a ScriptBlock, not expanded below for brevity)"
                    Write-LogMsg @LogParams -Text "`$PowershellInterface.AddScript('$Command')"
                    $null = $ThisPowershell.AddScript($Command)
                }
                default {
                    Write-LogMsg @LogParams -Text " # Adding command '$Command' of type '$($CommandInfo.CommandType)'"
                    Write-LogMsg @LogParams -Text "`$PowershellInterface.AddStatement().AddCommand('$Command')"
                    $null = $ThisPowershell.AddStatement().AddCommand($Command)
                }
            }
        }
    }
}
function Add-PsModule {
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Runspaces.InitialSessionState]$InitialSessionState,
        [Parameter(
            Position = 0
        )]
        [System.Management.Automation.PSModuleInfo[]]$ModuleInfo,
        [string]$DebugOutputStream = 'Silent',
        [string]$TodaysHostname = (HOSTNAME.EXE),
        [string]$WhoAmI = (whoami.EXE),
        [hashtable]$LogBuffer = $Global:LogMessages
    )
    begin {
        $LogParams = @{
            Buffer       = $LogBuffer
            ThisHostname = $TodaysHostname
            Type         = $DebugOutputStream
            WhoAmI       = $WhoAmI
        }
    }
    process {
        ForEach ($ThisModule in $ModuleInfo) {
            switch ($ThisModule.ModuleType) {
                'Binary' {
                    Write-LogMsg @LogParams -Text "`$InitialSessionState.ImportPSModule('$($ThisModule.Name)')"
                    $InitialSessionState.ImportPSModule($ThisModule.Name)
                }
                'Script' {
                    $ModulePath = Split-Path -Path $ThisModule.Path -Parent
                    Write-LogMsg @LogParams -Text "`$InitialSessionState.ImportPSModulesFromPath('$ModulePath')"
                    $InitialSessionState.ImportPSModulesFromPath($ModulePath)
                }
                'Manifest' {
                    $ModulePath = Split-Path -Path $ThisModule.Path -Parent
                    Write-LogMsg @LogParams -Text "`$InitialSessionState.ImportPSModulesFromPath('$ModulePath')"
                    $InitialSessionState.ImportPSModulesFromPath($ModulePath)
                }
                default {
                }
            }
        }
    }
}
function Convert-FromPsCommandInfoToString {
    param (
        [Parameter (
            Mandatory,
            Position = 0
        )]
        [PSCustomObject[]]$CommandInfo,
        [string]$DebugOutputStream = 'Silent',
        [string]$TodaysHostname = (HOSTNAME.EXE),
        [string]$WhoAmI = (whoami.EXE),
        [hashtable]$LogBuffer = $Global:LogMessages
    )
    begin {
        $CommandInfoParams = @{
            DebugOutputStream = $DebugOutputStream
            TodaysHostname    = $TodaysHostname
            WhoAmI            = $WhoAmI
            LogBuffer       = $LogBuffer
        }
    }
    process {
        ForEach ($ThisCmd in $CommandInfo) {
            switch ($ThisCmd.CommandType) {
                'Alias' {
                    $ThisCmd = Get-PsCommandInfo @CommandInfoParams -Command $ThisCmd.CommandInfo.Definition
                    Convert-FromPsCommandInfoToString @CommandInfoParams -CommandInfo $ThisCmd
                }
                'Function' {
                    "function $($ThisCmd.CommandInfo.Name) {`r`n$($ThisCmd.CommandInfo.Definition)`r`n}"
                }
                'ExternalScript' {
                    "$($ThisCmd.ScriptBlock)"
                }
                'ScriptBlock' {
                    "$Command"
                }
                default {
                    "$Command"
                }
            }
        }
    }
}
function Expand-PsCommandInfo {
    param (
        [PSCustomObject]$PsCommandInfo,
        [hashtable]$Cache = [hashtable]::Synchronized(@{}),
        [string]$DebugOutputStream = 'Silent',
        [string]$TodaysHostname = (HOSTNAME.EXE),
        [string]$WhoAmI = (whoami.EXE),
        [hashtable]$LogBuffer = $Global:LogMessages
    )
    $CommandInfoParams = @{
        DebugOutputStream = $DebugOutputStream
        TodaysHostname    = $TodaysHostname
        WhoAmI            = $WhoAmI
        LogBuffer       = $LogBuffer
    }
    if (-not $PsCommandInfo.CommandInfo.Name) {
        $PsCommandInfo
    } else {
        $Cache[$PsCommandInfo.CommandInfo.Name] = $PsCommandInfo
    }
    $PsTokens = $null
    $TokenizerErrors = $null
    $AbstractSyntaxTree = [System.Management.Automation.Language.Parser]::ParseInput(
        $PsCommandInfo.CommandInfo.Scriptblock,
        [ref]$PsTokens,
        [ref]$TokenizerErrors
    )
    $AllPsTokens = Expand-PsToken -InputObject $PsTokens
    $CommandTokens = $AllPsTokens |
    Where-Object -FilterScript {
        $_.Kind -eq 'Generic' -and
        $_.TokenFlags.HasFlag([System.Management.Automation.Language.TokenFlags]::CommandName)
    }
    ForEach ($ThisCommandToken in $CommandTokens) {
        if (
            -not $Cache[$ThisCommandToken.Value] -and
            $ThisCommandToken.Value -notmatch '[\.\\]' 
        ) {
            $TokenCommandInfo = Get-PsCommandInfo @CommandInfoParams -Command $ThisCommandToken.Value
            $Cache[$ThisCommandToken.Value] = $TokenCommandInfo
            $null = Expand-PsCommandInfo @CommandInfoParams -PsCommandInfo $TokenCommandInfo -Cache $Cache
        }
    }
    ForEach ($ThisKey in $Cache.Keys) {
        $Cache[$ThisKey]
    }
}
function Expand-PsToken {
    param (
        [Parameter(
            Mandatory,
            Position = 0
        )]
        [psobject]$InputObject
    )
    process {
        if ($InputObject.GetType().FullName -eq 'Management.Automation.Language.StringExpandableToken]') {
            ForEach ($ThisToken in $InputObject.NestedTokens) {
                if ($ThisToken) {
                    Expand-PsToken -InputObject $ThisToken
                }
            }
        }
        $InputObject
    }
}
function Get-PsCommandInfo {
    param(
        $Command,
        [string]$DebugOutputStream = 'Silent',
        [string]$TodaysHostname = (HOSTNAME.EXE),
        [string]$WhoAmI = (whoami.EXE),
        [hashtable]$LogBuffer = $Global:LogMessages
    )
    $LogParams = @{
        Buffer       = $LogBuffer
        ThisHostname = $TodaysHostname
        Type         = $DebugOutputStream
        WhoAmI       = $WhoAmI
    }
    if ($Command.GetType().FullName -eq 'System.Management.Automation.ScriptBlock') {
        [string]$CommandType = 'ScriptBlock'
    } else {
        $CommandInfo = Get-Command $Command -ErrorAction SilentlyContinue
        [string]$CommandType = $CommandInfo.CommandType
        if ($CommandInfo.Source -like "*\*") {
            $ModuleInfo = Get-Module -Name $CommandInfo.Source -ListAvailable -ErrorAction SilentlyContinue
        } else {
            if ($CommandInfo.Source) {
                Write-LogMsg @LogParams -Text "Get-Module -Name '$($CommandInfo.Source)'"
                $ModuleInfo = Get-Module -Name $CommandInfo.Source -ErrorAction SilentlyContinue
            }
        }
    }
    if ($ModuleInfo.Path -like "*.ps1") {
        $ModuleInfo = $null
        $SourceModuleName = $null
    } else {
        $SourceModuleName = $CommandInfo.Source
    }
    Write-LogMsg @LogParams -Text " # $Command is a $CommandType"
    [pscustomobject]@{
        CommandInfo            = $CommandInfo
        ModuleInfo             = $ModuleInfo
        CommandType            = $CommandType
        SourceModuleDefinition = $ModuleInfo.Definition
        SourceModuleName       = $SourceModuleName
    }
}
function Open-Thread {
    Param(
        [Parameter(
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true
        )]
        $InputObject,
        [Parameter(
            Mandatory = $true
        )]
        [System.Management.Automation.Runspaces.RunspacePool]$RunspacePool,
        [string]$ObjectStringProperty,
        [Parameter(Mandatory = $true)]
        $Command,
        [pscustomobject[]]$CommandInfo,
        [string]$InputParameter = $null,
        [HashTable]$AddParam = @{},
        [string[]]$AddSwitch = @(),
        [string]$DebugOutputStream = 'Silent',
        [string]$TodaysHostname = (HOSTNAME.EXE),
        [string]$WhoAmI = (whoami.EXE),
        [hashtable]$LogBuffer = $Global:LogMessages,
        [int]$ProgressParentId
    )
    begin {
        $Progress = @{
            Activity = "Open-Thread -Command '$Command'"
        }
        if ($PSBoundParameters.ContainsKey('ProgressParentId')) {
            $Progress['ParentId'] = $ProgressParentId
            $Progress['Id'] = $ProgressParentId + 1
        } else {
            $Progress['Id'] = 0
        }
        $LogParams = @{
            Buffer       = $LogBuffer
            ThisHostname = $TodaysHostname
            Type         = $DebugOutputStream
            WhoAmI       = $WhoAmI
        }
        $CommandInfoParams = @{
            DebugOutputStream = $DebugOutputStream
            TodaysHostname    = $TodaysHostname
            WhoAmI            = $WhoAmI
            LogBuffer         = $LogBuffer
        }
        [int64]$CurrentObjectIndex = 0
        $ThreadCount = @($InputObject).Count
        Write-LogMsg @LogParams -Text " # Received $(($CommandInfo | Measure-Object).Count) PsCommandInfos from Split-Thread for '$Command'"
        if ($CommandInfo) {
            if (Test-Path $Command -ErrorAction SilentlyContinue) {
                $CommandStringForScriptDefinition = [System.Text.StringBuilder]::new(". '$Command'")
            } else {
                $CommandStringForScriptDefinition = [System.Text.StringBuilder]::new($Command)
            }
            $ScriptDefinition = [System.Text.StringBuilder]::new()
            $null = $ScriptDefinition.AppendLine('param (')
            If ([string]::IsNullOrEmpty($InputParameter)) {
                $null = $ScriptDefinition.Append("    `$PsRunspaceArgument1")
                $null = $CommandStringForScriptDefinition.Append(" `$PsRunspaceArgument1")
            } else {
                $null = $ScriptDefinition.Append("    `$$InputParameter")
                $null = $CommandStringForScriptDefinition.Append(" -$InputParameter `$$InputParameter")
            }
            ForEach ($ThisKey in $AddParam.Keys) {
                $null = $ScriptDefinition.Append(",`r`n    `$$ThisKey")
                $null = $CommandStringForScriptDefinition.Append(" -$ThisKey `$$ThisKey")
            }
            ForEach ($ThisSwitch in $AddSwitch) {
                $null = $ScriptDefinition.Append(",`r`n    [switch]`$", $ThisSwitch)
                $null = $CommandStringForScriptDefinition.Append(" -$ThisSwitch")
            }
            $null = $ScriptDefinition.AppendLine("`r`n)`r`n")
            Convert-FromPsCommandInfoToString @CommandInfoParams -CommandInfo $CommandInfo |
            ForEach-Object {
                $null = $ScriptDefinition.AppendLine("`r`n$_")
            }
            $null = $ScriptDefinition.AppendLine()
            Write-LogMsg @LogParams -Text " # Command string is $($CommandStringForScriptDefinition.ToString())"
            $CommandStringForScriptDefinition |
            ForEach-Object {
                $null = $ScriptDefinition.AppendLine("`r`n$_")
            }
            $null = $ScriptDefinition.AppendLine()
            $ScriptString = $ScriptDefinition.ToString()
            $ScriptBlock = [scriptblock]::Create($ScriptString)
        }
    }
    process {
        ForEach ($Object in $InputObject) {
            $CurrentObjectIndex++
            if ($ObjectStringProperty -ne '') {
                [string]$ObjectString = $Object."$ObjectStringProperty"
            } else {
                [string]$ObjectString = $Object.ToString()
            }
            Write-LogMsg @LogParams -Text "`$PowershellInterface = [powershell]::Create() # for '$Command' on '$ObjectString'"
            $PowershellInterface = [powershell]::Create()
            Write-LogMsg @LogParams -Text "`$PowershellInterface.RunspacePool = `$RunspacePool # for '$Command' on '$ObjectString'"
            $PowershellInterface.RunspacePool = $RunspacePool
            Write-LogMsg @LogParams -Text "`$PowershellInterface.Commands.Clear() # for '$Command' on '$ObjectString'"
            $null = $PowershellInterface.Commands.Clear()
            if ($ScriptBlock) {
                $null = Add-PsCommand @CommandInfoParams -Command $ScriptBlock -PowershellInterface $PowershellInterface 
                If ([string]::IsNullOrEmpty($InputParameter)) {
                    $InputParameter = 'PsRunspaceArgument1'
                }
            } else {
                $null = Add-PsCommand @CommandInfoParams -Command $Command -CommandInfo $CommandInfo -PowershellInterface $PowershellInterface -Force
            }
            If ([string]::IsNullOrEmpty($InputParameter)) {
                Write-LogMsg @LogParams -Text "`$PowershellInterface.AddArgument('$ObjectString') # for '$Command' on '$ObjectString'"
                $null = $PowershellInterface.AddArgument($Object)
                $InputParameterStringForDebug = " '$ObjectString'"
            } else {
                Write-LogMsg @LogParams -Text "`$PowershellInterface.AddParameter('$InputParameter', '$ObjectString') # for '$Command' on '$ObjectString'"
                $null = $PowershellInterface.AddParameter($InputParameter, $Object)
                $InputParameterStringForDebug = "-$InputParameter '$ObjectString'"
            }
            $AdditionalParameters = @()
            $AdditionalParameters = ForEach ($Key in $AddParam.Keys) {
                Write-LogMsg @LogParams -Text "`$PowershellInterface.AddParameter('$Key', '$($AddParam.$key)') # for '$Command' on '$ObjectString'"
                $null = $PowershellInterface.AddParameter($Key, $AddParam.$key)
                "-$Key '$($AddParam.$key)'"
            }
            $Switches = @()
            $Switches = ForEach ($Switch in $AddSwitch) {
                Write-LogMsg @LogParams -Text "`$PowershellInterface.AddParameter('$Switch') # for '$Command' on '$ObjectString'"
                $null = $PowershellInterface.AddParameter($Switch)
                "-$Switch"
            }
            $NewPercentComplete = $CurrentObjectIndex / $ThreadCount * 100
            if (($NewPercentComplete - $OldPercentComplete) -ge 1) {
                $OldPercentComplete = $NewPercentComplete
                $AdditionalParametersString = $AdditionalParameters -join ' '
                $SwitchParameterString = $Switches -join ' '
                $StatusString = "Invoking thread $CurrentObjectIndex`: $Command $InputParameterStringForDebug $AdditionalParametersString $SwitchParameterString"
                $Status = "$([int]$NewPercentComplete)% ($($ThreadCount - $CurrentObjectIndex) of $ThreadCount remain)"
                Write-Progress @Progress -CurrentOperation $StatusString -PercentComplete $NewPercentComplete -Status $Status
            }
            Write-LogMsg @LogParams -Text "`$Handle = `$PowershellInterface.BeginInvoke() # for '$Command' on '$ObjectString'"
            $Handle = $PowershellInterface.BeginInvoke()
            [PSCustomObject]@{
                Handle              = $Handle
                PowerShellInterface = $PowershellInterface
                Object              = $Object
                ObjectString        = $ObjectString
                Index               = $CurrentObjectIndex
                Command             = "$Command"
            }
        }
    }
    end {
        Write-Progress @Progress -Completed
    }
}
function Split-Thread {
    param (
        [Parameter(Mandatory = $true)]
        $Command,
        [Parameter(
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true
        )]
        $InputObject,
        $InputParameter = $null,
        [int]$Threads = (Get-CimInstance -ClassName CIM_Processor | Measure-Object -Sum -Property NumberOfLogicalProcessors).Sum,
        [int]$SleepTimer = 200,
        [int]$Timeout = 120,
        [HashTable]$AddParam = @{},
        [string[]]$AddSwitch = @(),
        [String[]]$AddModule,
        [string]$ObjectStringProperty,
        [string]$DebugOutputStream = 'Silent',
        [string]$TodaysHostname = (HOSTNAME.EXE),
        [string]$WhoAmI = (whoami.EXE),
        [hashtable]$LogBuffer = ([hashtable]::Synchronized(@{})),
        [int]$ProgressParentId
    )
    begin {
        $LogParams = @{
            Buffer       = $LogBuffer
            ThisHostname = $TodaysHostname
            Type         = $DebugOutputStream
            WhoAmI       = $WhoAmI
        }
        Write-LogMsg @LogParams -Text "`$InitialSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault() # for '$Command'"
        $InitialSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        $CommandInfoParams = @{
            DebugOutputStream = $DebugOutputStream
            TodaysHostname    = $TodaysHostname
            WhoAmI            = $WhoAmI
            LogBuffer         = $LogBuffer
        }
        $OriginalCommandInfo = Get-PsCommandInfo @CommandInfoParams -Command $Command
        Write-LogMsg @LogParams -Text " # Found 1 original PsCommandInfo for '$Command'"
        $CommandInfo = Expand-PsCommandInfo @CommandInfoParams -PsCommandInfo $OriginalCommandInfo
        Write-LogMsg @LogParams -Text " # Found $(($CommandInfo | Measure-Object).Count) nested PsCommandInfos for '$Command' ($($CommandInfo.CommandInfo.Name -join ','))"
        $ModulesToAdd = [System.Collections.Generic.List[System.Management.Automation.PSModuleInfo]]::new()
        ForEach ($Module in $AddModule) {
            Write-LogMsg @LogParams -Text "Get-Module -Name '$Module'"
            $ModuleObj = Get-Module -Name $Module -ErrorAction SilentlyContinue
            $null = $ModulesToAdd.Add($ModuleObj)
        }
        $CommandInfo.ModuleInfo |
        ForEach-Object {
            $null = $ModulesToAdd.Add($_)
        }
        $ModulesToAdd = $ModulesToAdd |
        Sort-Object -Property Name -Unique
        $CommandsToAdd = $CommandInfo |
        Where-Object -FilterScript {
            (
                -not $_.ModuleInfo.Name -or
                $ModulesToAdd.Name -notcontains $_.ModuleInfo.Name
            ) -and
            $_.CommandType -ne 'Cmdlet'
        }
        Write-LogMsg @LogParams -Text " # Found $(($CommandsToAdd | Measure-Object).Count) remaining PsCommandInfos to define for '$Command' (not in modules: $($CommandsToAdd.CommandInfo.Name -join ','))"
        if ($ModulesToAdd.Count -gt 0) {
            $null = Add-PsModule -InitialSessionState $InitialSessionState -ModuleInfo $ModulesToAdd @CommandInfoParams
        }
        $OutputStream = @('Debug', 'Verbose', 'Information', 'Warning', 'Error')
        ForEach ($ThisStream in $OutputStream) {
            if ($ThisStream -eq 'Error') {
                $VariableName = 'ErrorActionPreference'
            } else {
                $VariableName = "$($ThisStream)Preference"
            }
            $VariableValue = (Get-Variable -Name $VariableName).Value
            $VariableEntry = [System.Management.Automation.Runspaces.SessionStateVariableEntry]::new($VariableName, $VariableValue, '')
            $InitialSessionState.Variables.Add($VariableEntry)
        }
        Write-LogMsg @LogParams -Text "`$RunspacePool = [runspacefactory]::CreateRunspacePool(1, $Threads, `$InitialSessionState, `$Host) # for '$Command'"
        $RunspacePool = [runspacefactory]::CreateRunspacePool(1, $Threads, $InitialSessionState, $Host)
        Write-LogMsg @LogParams -Text "`$RunspacePool.Open() # for '$Command'"
        $RunspacePool.Open()
        $Global:TimedOut = $false
    }
    end {
        $AllInputObjects = $input
        Write-LogMsg @LogParams -Text " # Entered end block. Sending $(($CommandsToAdd | Measure-Object).Count) PsCommandInfos to Open-Thread for '$Command'"
        Write-LogMsg @LogParams -Text " # Received '$(($AllInputObjects | Measure-Object).Count)' objects with the `$input automatic variable."
        Write-LogMsg @LogParams -Text " # Received '$(($InputObject | Measure-Object).Count)' objects with the `InputObject parameter."
        $ThreadParameters = @{
            Command              = $Command
            InputParameter       = $InputParameter
            InputObject          = $AllInputObjects
            AddParam             = $AddParam
            AddSwitch            = $AddSwitch
            ObjectStringProperty = $ObjectStringProperty
            CommandInfo          = $CommandsToAdd
            RunspacePool         = $RunspacePool
            DebugOutputStream    = $DebugOutputStream
            WhoAmI               = $WhoAmI
            LogBuffer            = $LogBuffer
        }
        if ($PSBoundParameters.ContainsKey('ProgressParentId')) {
            $ThreadParameters['ProgressParentId'] = $ProgressParentId
        }
        $AllThreads = Open-Thread @ThreadParameters
        Write-LogMsg @LogParams -Text " # Received $(($AllThreads | Measure-Object).Count) threads from Open-Thread for $Command"
        $ThreadParameters = @{
            Thread            = $AllThreads
            Threads           = $Threads
            SleepTimer        = $SleepTimer
            Timeout           = $Timeout
            Dispose           = $true
            DebugOutputStream = $DebugOutputStream
            TodaysHostname    = $TodaysHostname
            WhoAmI            = $WhoAmI
            LogBuffer         = $LogBuffer
        }
        if ($PSBoundParameters.ContainsKey('ProgressParentId')) {
            $ThreadParameters['ProgressParentId'] = $ProgressParentId
        }
        Wait-Thread @ThreadParameters
        $VerbosePreference = 'Continue'
        if ($Global:TimedOut -eq $false) {
            Write-LogMsg @LogParams -Text "[System.Management.Automation.Runspaces.RunspacePool]::Close()"
            $null = $RunspacePool.Close()
            Write-LogMsg @LogParams -Text " # [System.Management.Automation.Runspaces.RunspacePool]::Close() completed"
            Write-LogMsg @LogParams -Text "[System.Management.Automation.Runspaces.RunspacePool]::Dispose()"
            $null = $RunspacePool.Dispose()
            Write-LogMsg @LogParams -Text " # [System.Management.Automation.Runspaces.RunspacePool]::Dispose() completed"
        } else {
            throw 'Split-Thread timeout reached'
        }
    }
}
function Wait-Thread {
    param (
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true
        )]
        [PSCustomObject[]]$Thread,
        [int]$Threads = 20,
        [int]$SleepTimer = 200,
        [int]$Timeout = 120,
        [switch]$Dispose,
        [string]$DebugOutputStream = 'Silent',
        [string]$TodaysHostname = (HOSTNAME.EXE),
        [string]$WhoAmI = (whoami.EXE),
        [hashtable]$LogBuffer = $Global:LogMessages,
        [int]$ProgressParentId
    )
    begin {
        $LogParams = @{
            Buffer       = $LogBuffer
            ThisHostname = $TodaysHostname
            Type         = $DebugOutputStream
            WhoAmI       = $WhoAmI
        }
        $StopWatch = [System.Diagnostics.Stopwatch]::new()
        $StopWatch.Start()
        $AllThreads = [System.Collections.Generic.List[PSCustomObject]]::new()
        $FirstThread = @($Thread)[0]
        $RunspacePool = $FirstThread.PowershellInterface.RunspacePool
        $CommandString = $FirstThread.Command
        $Progress = @{
            Activity = "Wait-Thread '$CommandString'"
        }
        if ($PSBoundParameters.ContainsKey('ProgressParentId')) {
            $Progress['ParentId'] = $ProgressParentId
            $Progress['Id'] = $ProgressParentId + 1
        } else {
            $Progress['Id'] = 0
        }
        $ThreadCount = @($Thread).Count
    }
    process {
        ForEach ($ThisThread in $Thread) {
            if ($ThisThread.Handle -eq $false) {
                Write-LogMsg @LogParams -Text "`$PowerShellInterface.Streams.ClearStreams() # for '$CommandString' on '$($ThisThread.ObjectString)'"
                $null = $ThisThread.PowerShellInterface.Streams.ClearStreams()
                $ThisThread
            } else {
                $null = $AllThreads.Add($ThisThread)
            }
        }
    }
    end {
        While (@($AllThreads | Where-Object -FilterScript { $null -ne $_.Handle }).Count -gt 0) {
            Write-LogMsg @LogParams -Text "Start-Sleep -Milliseconds $SleepTimer # for '$CommandString'"
            Start-Sleep -Milliseconds $SleepTimer
            if ($RunspacePool) { $AvailableRunspaces = $RunspacePool.GetAvailableRunspaces() }
            $CleanedUpThreads = [System.Collections.Generic.List[PSCustomObject]]::new()
            $CompletedThreads = [System.Collections.Generic.List[PSCustomObject]]::new()
            $IncompleteThreads = [System.Collections.Generic.List[PSCustomObject]]::new()
            ForEach ($ThisThread in $AllThreads) {
                if ($null -eq $ThisThread.Handle) {
                    $null = $CleanedUpThreads.Add($ThisThread)
                }
                if ($ThisThread.Handle.IsCompleted -eq $true) {
                    $null = $CompletedThreads.Add($ThisThread)
                }
                if ($ThisThread.Handle.IsCompleted -eq $false) {
                    $null = $IncompleteThreads.Add($ThisThread)
                }
            }
            $ActiveThreadCountString = "$($Threads - $AvailableRunspaces) of $Threads are active"
            Write-LogMsg @LogParams -Text " # $ActiveThreadCountString for '$CommandString'"
            Write-LogMsg @LogParams -Text " # $($CompletedThreads.Count) completed threads for '$CommandString'"
            Write-LogMsg @LogParams -Text " # $($CleanedUpThreads.Count) cleaned up threads for '$CommandString'"
            Write-LogMsg @LogParams -Text " # $($IncompleteThreads.Count) incomplete threads for '$CommandString'"
            $NewPercentComplete = $CleanedUpThreads.Count / $ThreadCount * 100
            if (($NewPercentComplete - $OldPercentComplete) -ge 1) {
                $OldPercentComplete = $NewPercentComplete
                $RemainingString = "$($IncompleteThreads.ObjectString)"
                If ($RemainingString.Length -gt 60) {
                    $RemainingString = $RemainingString.Substring(0, 60) + "..."
                }
                $CurrentOperation = "Waiting on threads - $ActiveThreadCountString`: $CommandString"
                $Status = "$([int]$NewPercentComplete)% ($($IncompleteThreads.Count) of $ThreadCount remain): $RemainingString"
                Write-Progress @Progress -PercentComplete $NewPercentComplete -CurrentOperation $CurrentOperation -Status $Status
            }
            ForEach ($CompletedThread in $CompletedThreads) {
                Write-LogMsg @LogParams -Text " # $($CompletedThread.PowerShellInterface.Streams.Progress.Count) Progress messages for '$CommandString' on '$($CompletedThread.ObjectString)'"
                Write-LogMsg @LogParams -Text " # $($CompletedThread.PowerShellInterface.Streams.Information.Count) Information messages for '$CommandString' on '$($CompletedThread.ObjectString)'"
                Write-LogMsg @LogParams -Text " # $($CompletedThread.PowerShellInterface.Streams.Verbose.Count) Verbose messages for '$CommandString' on '$($CompletedThread.ObjectString)'"
                Write-LogMsg @LogParams -Text " # $($CompletedThread.PowerShellInterface.Streams.Debug.Count) Debug messages for '$CommandString' on '$($CompletedThread.ObjectString)'"
                Write-LogMsg @LogParams -Text " # $($CompletedThread.PowerShellInterface.Streams.Warning.Count) Warning messages for '$CommandString' on '$($CompletedThread.ObjectString)'"
                Write-LogMsg @LogParams -Text "`$PowerShellInterface.Streams.ClearStreams() # for '$CommandString' on '$($CompletedThread.ObjectString)'"
                $null = $CompletedThread.PowerShellInterface.Streams.ClearStreams()
                Write-LogMsg @LogParams -Text "`$PowerShellInterface.EndInvoke(`$Handle) # for '$CommandString' on '$($CompletedThread.ObjectString)'"
                $ThreadOutput = $CompletedThread.PowerShellInterface.EndInvoke($CompletedThread.Handle)
                if (@($ThreadOutput).Count -gt 0) {
                    Write-LogMsg @LogParams -Text " # Output (count of $(@($ThreadOutput).Count)) received from thread $($CompletedThread.Index): $($CompletedThread.ObjectString)"
                } else {
                    Write-LogMsg @LogParams -Text " # Null result for thread $($CompletedThread.Index) ($($CompletedThread.ObjectString))"
                }
                if ($Dispose -eq $true) {
                    $ThreadOutput
                    Write-LogMsg @LogParams -Text "`$PowerShellInterface.Dispose() # for '$CommandString' on '$($CompletedThread.ObjectString)'"
                    $null = $CompletedThread.PowerShellInterface.Dispose()
                    $CompletedThread.PowerShellInterface = $null
                    $CompletedThread.Handle = $null
                } else {
                    Write-LogMsg @LogParams -Text " # Thread $($CompletedThread.Index) is finished opening for '$CommandString' on '$($CompletedThread.ObjectString)'"
                    $CompletedThread.Handle = $null
                    $CompletedThread
                }
                $StopWatch.Reset()
                $StopWatch.Start()
            }
            If ($StopWatch.ElapsedMilliseconds / 1000 -gt $Timeout) {
                Write-Warning "  Reached Timeout of $Timeout seconds. Skipping $($IncompleteThreads.Count) remaining threads: $RemainingString"
                $Global:TimedOut = $true
                $IncompleteThreads |
                ForEach-Object {
                    $_.Handle = $null
                    [PSCustomObject]@{
                        Handle              = $null
                        PowerShellInterface = $_.PowershellInterface
                        Object              = $_.Object
                        ObjectString        = $_.ObjectString
                        Index               = $_.CurrentObjectIndex
                        Command             = $_.Command
                    }
                }
            }
        }
        $StopWatch.Stop()
        Write-LogMsg @LogParams -Text " # Finished waiting for threads"
        Write-Progress @Progress -Completed
    }
}
Import-Module PsLogMessage -ErrorAction SilentlyContinue
function Format-PrtgXmlResult {
    param (
        [parameter(Mandatory)]
        [string]$Channel,
        [parameter(Mandatory)]
        [string]$Value,
        [string]$Unit = 'Custom',
        [string]$CustomUnit,
        [int]$ShowChart = 0,
        [string]$MaxError,
        [string]$MinError,
        [string]$MaxWarn,
        [string]$MinWarn,
        [switch]$Warning
    )
    $Xml = [System.Collections.Generic.List[string]]::new()
    $null = $Xml.Add('<result>')
    $null = $Xml.Add("  <channel>$Channel</channel>")
    $null = $Xml.Add("  <value>$Value</value>")
    $null = $Xml.Add("  <unit>$Unit</unit>")
    $null = $Xml.Add("  <showchart>$ShowChart</showchart>")
    if ($CustomUnit) {
        $null = $Xml.Add("  <customUnit>$CustomUnit</customUnit>")
    }
    if ($MaxError -or $MinError -or $MaxWarn -or $MinWarn) {
        $null = $Xml.Add("  <limitmode>1</limitmode>")
        if ($MaxError) {
            $null = $Xml.Add("  <limitmaxerror>$MaxError</limitmaxerror>")
        }
        if ($MinError) {
            $null = $Xml.Add("  <limitminerror>$MinError</limitminerror>")
        }
        if ($MaxWarn) {
            $null = $Xml.Add("  <limitmaxwarn>$MaxWarn</limitmaxwarn>")
        }
        if ($MinWarn) {
            $null = $Xml.Add("  <limitminwarn>$MinWarn</limitminwarn>")
        }
    }
    if ($Warning) {
        $null = $Xml.Add('  <Warning>1</Warning>')
    } else {
        $null = $Xml.Add('  <Warning>0</Warning>')
    }
    $null = $Xml.Add('</result>')
    $Xml
}
function Format-PrtgXmlSensorOutput {
    param (
        [Parameter(ValueFromPipeline)]
        [string[]]$PrtgXmlResult,
        [switch]$IssueDetected
    )
    begin {
        $Strings = [System.Collections.Generic.List[string]]::new()
        $null = $Strings.add("<prtg>")
    }
    process {
        foreach ($XmlResult in $PrtgXmlResult) {
            $null = $Strings.add($XmlResult)
        }
    }
    end {
        if ($IssueDetected) {
            $null = $Strings.add("<text>Issue detected, see sensor channels for details</text>")
        } else {
            $null = $Strings.add("<text>OK</text>")
        }
        $null = $Strings.add("</prtg>")
        $Strings
    }
}
function Send-PrtgXmlSensorOutput {
    param(
        [string]$XmlOutput,
        [string]$PrtgProbe,
        [string]$PrtgProtocol,
        [int]$PrtgPort,
        [string]$PrtgToken
    )
    $ResultToPost = @{
        Body            = $XMLOutput
        ContentType     = 'application/xml'
        Method          = 'Post'
        Uri             = "$PrtgProtocol`://$PrtgProbe`:$PrtgPort/$PrtgToken"
        UseBasicParsing = $true
    }
    if ($PrtgToken) {
        Write-Verbose "URI: $PrtgProtocol`://$PrtgProbe`:$PrtgPort/$PrtgToken"
        Invoke-WebRequest @ResultToPost
    }
}
    $StopWatch = [System.Diagnostics.Stopwatch]::new()
    $null = $StopWatch.Start()
    $ReportInstanceId = [guid]::NewGuid().ToString()
    $OutputDir = New-DatedSubfolder -Root $OutputDir -Suffix "_$ReportInstanceId"
    $TranscriptFile = "$OutputDir\PowerShellTranscript.log"
    Start-Transcript $TranscriptFile *>$null
    Write-Information $TranscriptFile
    $LogFile = "$OutputDir\Export-Permission.log"
    $DirectoryEntryCache = [hashtable]::Synchronized(@{}) 
    $DomainsBySID = [hashtable]::Synchronized(@{}) 
    $DomainsByNetbios = [hashtable]::Synchronized(@{}) 
    $DomainsByFqdn = [hashtable]::Synchronized(@{}) 
    $LogBuffer = [hashtable]::Synchronized(@{}) 
    $CimCache = [hashtable]::Synchronized(@{}) 
    $AclByPath = [hashtable]::Synchronized(@{}) 
    $AceByGUID = [hashtable]::Synchronized(@{}) 
    $AceGuidByID = [hashtable]::Synchronized(@{}) 
    $AceGuidByPath = [hashtable]::Synchronized(@{}) 
    $PrincipalByID = [hashtable]::Synchronized(@{}) 
    $Parents = [hashtable]::Synchronized(@{}) 
    $IdByShortName = [hashtable]::Synchronized(@{}) 
    $ShortNameByID = [hashtable]::Synchronized(@{}) 
    $ExcludeClassFilterContents = [hashtable]::Synchronized(@{}) 
    $IncludeAccountFilterContents = [hashtable]::Synchronized(@{}) 
    $ExcludeAccountFilterContents = [hashtable]::Synchronized(@{}) 
    $ThisHostname = HOSTNAME.EXE
    $WhoAmI = Get-CurrentWhoAmI -Buffer $LogBuffer -ThisHostName $ThisHostname
    $Threads = @{ ThreadCount = $ThreadCount }
    $LogThis = @{
        ThisHostname = $ThisHostname
        LogBuffer    = $LogBuffer
        WhoAmI       = $WhoAmI
    }
    $Log = @{
        ThisHostname = $ThisHostname
        Type         = 'Debug'
        Buffer       = $LogBuffer
        WhoAmI       = $WhoAmI
    }
    Write-LogMsg @Log -Text '$LogBuffer = [hashtable]::Synchronized(@{})'
    Write-LogMsg @Log -Text '$ThisHostname = HOSTNAME.EXE'
    Write-LogMsg @Log -Text "`$WhoAmI = Get-CurrentWhoAmI -ThisHostName '$ThisHostname' -Buffer `$LogBuffer"
    Write-LogMsg @Log -Text "`$ThisFqdn = ConvertTo-DnsFqdn -ComputerName '$ThisHostName'"
    $ThisFqdn = ConvertTo-DnsFqdn -ComputerName $ThisHostName @LogThis
    $CacheParams = @{
        DirectoryEntryCache = $DirectoryEntryCache
        DomainsByFqdn       = $DomainsByFqdn
        DomainsByNetbios    = $DomainsByNetbios
        DomainsBySid        = $DomainsBySid
        ThisFqdn            = $ThisFqdn
        ThreadCount         = $ThreadCount
    }
    Write-LogMsg @Log -Text '$TrustedDomains = Get-TrustedDomain' -Expand $LogThis
    $TrustedDomains = Get-TrustedDomain @LogThis
    $LogThis['ProgressParentId'] = 0
}
process {
    $ProgressUpdate = @{
        CurrentOperation = 'Resolve target paths to network paths such as UNC paths (including all DFS folder targets)'
        PercentComplete  = 5
        Status           = '5% (step 2 of 20) Resolve-PermissionTarget'
    }
    Write-Progress @Progress @ProgressUpdate
    $CommandParameters = @{
        CimCache   = $CimCache
        Output     = $Parents
        TargetPath = $TargetPath
    }
    Write-LogMsg @Log -Text 'Resolve-PermissionTarget' -Expand $CommandParameters, $LogThis -ExpandKeyMap @{ Output = '$Parents' }
    Resolve-PermissionTarget @CommandParameters @LogThis
}
end {
    $ProgressUpdate = @{
        CurrentOperation = 'Expand parent paths into the paths of their children'
        PercentComplete  = 10
        Status           = '10% (step 3 of 20) Expand-PermissionTarget'
    }
    Write-Progress @Progress @ProgressUpdate
    $CommandParameters = @{
        RecurseDepth = $RecurseDepth
        TargetPath   = $Parents
    }
    Write-LogMsg @Log -Text '$Items = Expand-PermissionTarget' -Expand $CommandParameters, $LogThis, $Threads -ExpandKeyMap @{ TargetPath = '$Parents' }
    $Items = Expand-PermissionTarget @CommandParameters @LogThis @Threads
    $ProgressUpdate = @{
        CurrentOperation = 'Get the ACL of each path'
        PercentComplete  = 15
        Status           = '15% (step 4 of 20) Get-AccessControlList'
    }
    Write-Progress @Progress @ProgressUpdate
    $CommandParameters = @{
        Output     = $AclByPath
        TargetPath = $Items
    }
    Write-LogMsg @Log -Text 'Get-AccessControlList' -Expand @{ Output = '$AclByPath'; TargetPath = '$Items' }, $LogThis, $Threads
    Get-AccessControlList @CommandParameters @LogThis @Threads
    $ProgressUpdate = @{
        CurrentOperation = 'Get the FQDN of this computer, each trusted domain, and each server in the paths'
        PercentComplete  = 20
        Status           = '20% (step 5 of 20) Find-ServerFqdn'
    }
    Write-Progress @Progress @ProgressUpdate
    $CommandParameters = @{
        Known      = $TrustedDomains.DomainFqdn
        TargetPath = $Items
        ThisFqdn   = $ThisFqdn
    }
    Write-LogMsg @Log -Text '$ServerFqdns = Find-ServerFqdn' -Expand $CommandParameters, $LogThis -ExpandKeyMap @{ TargetPath = '$Items' }
    $ServerFqdns = Find-ServerFqdn @CommandParameters @LogThis
    $ProgressUpdate = @{
        CurrentOperation = 'Query each FQDN to pre-populate caches, avoiding redundant ADSI and CIM queries'
        PercentComplete  = 25
        Status           = '25% (step 6 of 20) Initialize-Cache'
    }
    Write-Progress @Progress @ProgressUpdate
    $CommandParameters = @{
        CimCache = $CimCache
        Fqdn     = $ServerFqdns
    }
    Write-LogMsg @Log -Text 'Initialize-Cache' -Expand $CommandParameters, $LogThis, $CacheParams
    Initialize-Cache @CommandParameters @LogThis @CacheParams
    $ProgressUpdate = @{
        CurrentOperation = 'Resolve each identity reference to its SID and NTAccount name'
        PercentComplete  = 30
        Status           = '30% (step 7 of 20) Resolve-AccessControlList'
    }
    Write-Progress @Progress @ProgressUpdate
    $CommandParameters = @{
        ACLsByPath              = $AclByPath
        ACEsByGUID              = $AceByGUID
        AceGUIDsByPath          = $AceGuidByPath
        AceGUIDsByResolvedID    = $AceGuidByID
        CimCache                = $CimCache
        InheritanceFlagResolved = $InheritanceFlagResolved
    }
    Write-LogMsg @Log -Text 'Resolve-AccessControlList' -Expand $CommandParameters, $LogThis, $CacheParams
    Resolve-AccessControlList @CommandParameters @LogThis @CacheParams
    $ProgressUpdate = @{
        CurrentOperation = 'Get the current domain'
        PercentComplete  = 35
        Status           = '35% (step 8 of 20) Get-CurrentDomain'
    }
    Write-Progress @Progress @ProgressUpdate
    Write-LogMsg @Log -Text '$CurrentDomain = Get-CurrentDomain'
    $CurrentDomain = Get-CurrentDomain
    $ProgressUpdate = @{
        CurrentOperation = 'Use ADSI to get details about each resolved identity reference'
        PercentComplete  = 40
        Status           = '40% (step 9 of 20) Get-PermissionPrincipal'
    }
    Write-Progress @Progress @ProgressUpdate
    $CommandParameters = @{
        ACEsByResolvedID       = $AceGuidByID
        CimCache               = $CimCache
        CurrentDomain          = $CurrentDomain
        NoGroupMembers         = $NoMembers
        PrincipalsByResolvedID = $PrincipalByID
    }
    Write-LogMsg @Log -Text "Get-PermissionPrincipal" -Expand $CommandParameters, $LogThis, $CacheParams
    Get-PermissionPrincipal @CommandParameters @LogThis @CacheParams
    $ProgressUpdate = @{
        CurrentOperation = 'Join access rules with their associated accounts'
        PercentComplete  = 45
        Status           = '45% (step 10 of 20) Expand-Permission'
    }
    Write-Progress @Progress @ProgressUpdate
    $CommandParameters = @{
        AceGuidByPath          = $AceGuidByPath
        AceGUIDsByResolvedID   = $AceGuidByID
        ACEsByGUID             = $AceByGUID
        ACLsByPath             = $AclByPath
        Children               = $Items
        GroupBy                = $GroupBy
        PrincipalsByResolvedID = $PrincipalByID
        SplitBy                = $SplitBy
        TargetPath             = $Parents
    }
    Write-LogMsg @Log -Text "`$Permissions = Expand-Permission" -Expand $CommandParameters, $LogThis
    $Permissions = Expand-Permission @CommandParameters @LogThis
    $ProgressUpdate = @{
        CurrentOperation = 'Hide domain names and include/exclude accounts as specified'
        PercentComplete  = 50
        Status           = '50% (step 11 of 20) Select-UniqueAccountPermission'
    }
    Write-Progress @Progress @ProgressUpdate
    $CommandParameters = @{
        ExcludeAccount             = $ExcludeAccount
        ExcludeClassFilterContents = $ExcludeClassFilterContents
        ExcludeFilterContents      = $ExcludeAccountFilterContents
        IdByShortName              = $IdByShortName
        IgnoreDomain               = $IgnoreDomain
        IncludeAccount             = $IncludeAccount
        IncludeFilterContents      = $IncludeAccountFilterContents
        PrincipalByID              = $PrincipalByID
        ShortNameByID              = $ShortNameByID
    }
    Write-LogMsg @Log -Text 'Select-PermissionPrincipal' -Expand $CommandParameters, $LogThis
    Select-PermissionPrincipal @CommandParameters @LogThis
    $ProgressUpdate = @{
        CurrentOperation = 'Analyze the permissions against established best practices'
        PercentComplete  = 55
        Status           = '55% (step 12 of 20) Invoke-PermissionAnalyzer'
    }
    Write-Progress @Progress @ProgressUpdate
    $CommandParameters = @{
        AclByPath                = $AclByPath
        AllowDisabledInheritance = $Items
        AccountConvention        = $AccountConvention
        PrincipalByID            = $PrincipalByID
    }
    $BestPracticeEval = Invoke-PermissionAnalyzer @CommandParameters
    $ProgressUpdate = @{
        CurrentOperation = 'Format the permissions'
        PercentComplete  = 60
        Status           = '60 % (step 13 of 20) Format-Permission'
    }
    Write-Progress @Progress @ProgressUpdate
    $CommandParameters = @{
        Analysis                   = $BestPracticeEval
        ExcludeClassFilterContents = $ExcludeClassFilterContents
        FileFormat                 = $FileFormat
        GroupBy                    = $GroupBy
        IgnoreDomain               = $IgnoreDomain
        IncludeFilterContents      = $IncludeAccountFilterContents
        OutputFormat               = $OutputFormat
        Permission                 = $Permissions
        ShortNameByID              = $ShortNameByID
    }
    Write-LogMsg @Log -Text '$FormattedPermissions = Format-Permission' -Expand $CommandParameters
    $FormattedPermissions = Format-Permission @CommandParameters
    $ProgressUpdate = @{
        CurrentOperation = 'Export the report files'
        PercentComplete  = 65
        Status           = '65 % (step 14 of 20) Out-PermissionFile'
    }
    Write-Progress @Progress @ProgressUpdate
    $CommandParameters = @{
        BestPracticeEval = $BestPracticeEval ; TargetPath = $TargetPath ; Parent = $Parents ; AclByPath = $AclByPath ; AceByGUID = $AceByGUID ; PrincipalByID = $PrincipalByID ;
        Permission = $Permissions ; FormattedPermission = $FormattedPermissions ; BestPracticeIssue = $BestPracticeIssues ;
        Detail = $Detail ; ExcludeAccount = $ExcludeAccount ; ExcludeClass = $ExcludeClass ; FileFormat = $FileFormat ;
        GroupBy = $GroupBy ; IgnoreDomain = $IgnoreDomain ; OutputDir = $OutputDir ; OutputFormat = $OutputFormat ;
        NoMembers = $NoMembers ; RecurseDepth = $RecurseDepth ; SplitBy = $SplitBy ; Title = $Title ;
        LogFileList = $TranscriptFile, $LogFile ; LogParams = $Log ; StopWatch = $StopWatch
        ReportInstanceId = $ReportInstanceId ; WhoAmI = $WhoAmI ; ThisFqdn = $ThisFqdn
    }
    Write-LogMsg @Log -Text 'Out-PermissionFile' -Expand $CommandParameters
    $ReportFile = Out-PermissionFile @CommandParameters
    $ProgressUpdate = @{
        CurrentOperation = 'Open the HTML report file (if the -Interactive switch was used)'
        PercentComplete  = 70
        Status           = '70 % (step 15 of 20) Invoke-Item'
    }
    Write-Progress @Progress @ProgressUpdate
    if ($Interactive -and $ReportFile) {
        Write-LogMsg @Log -Text "Invoke-Item -Path '$ReportFile'"
        Invoke-Item -Path $ReportFile
    }
    $ProgressUpdate = @{
        CurrentOperation = 'Send the results to a PRTG Custom XML Push sensor for tracking'
        PercentComplete  = 75
        Status           = '75 % (step 16 of 20) Send-PrtgXmlSensorOutput'
    }
    Write-Progress @Progress @ProgressUpdate
    $CommandParameters = @{
        XmlOutput    = $XMLOutput
        PrtgProbe    = $PrtgProbe
        PrtgProtocol = $PrtgProtocol
        PrtgPort     = $PrtgPort
        PrtgToken    = $PrtgToken
    }
    Write-LogMsg @Log -Text 'Send-PrtgXmlSensorOutput' -Expand $CommandParameters
    Send-PrtgXmlSensorOutput @CommandParameters
    $ProgressUpdate = @{
        CurrentOperation = 'Output the result to the pipeline'
        PercentComplete  = 80
        Status           = '80 % (step 17 of 20) Out-Permission'
    }
    Write-Progress @Progress @ProgressUpdate
    $CommandParameters = @{
        FormattedPermission = $FormattedPermissions
        GroupBy             = $GroupBy
        OutputFormat        = $OutputFormat
    }
    Write-LogMsg @Log -Text 'Out-Permission' -Expand $CommandParameters -ExpandKeyMap @{ FormattedPermission = '$FormattedPermissions' }
    Out-Permission @CommandParameters
    $ProgressUpdate = @{
        CurrentOperation = 'Cleanup CIM sessions'
        PercentComplete  = 85
        Status           = '85 % (step 18 of 20) Remove-CachedCimSession'
    }
    Write-Progress @Progress @ProgressUpdate
    Write-LogMsg @Log -Text 'Remove-CachedCimSession -CimCache $CimCache'
    Remove-CachedCimSession -CimCache $CimCache
    $ProgressUpdate = @{
        CurrentOperation = 'Export the buffered log messages to a CSV file'
        PercentComplete  = 90
        Status           = '95 % (step 19 of 20) Export-LogCsv'
    }
    Write-Progress @Progress @ProgressUpdate
    $CommandParameters = @{
        Buffer  = $LogBuffer
        LogFile = $LogFile
    }
    Write-LogMsg @Log -Text 'Export-LogCsv' -Expand $CommandParameters, $LogThis -ExpandKeyMap @{ Buffer = '$LogBuffer' }
    Export-LogCsv @CommandParameters @LogThis
    Stop-Transcript  *>$null
    Write-Progress @Progress -Completed
}
