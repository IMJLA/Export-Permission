# Demo of GroupBy Item

## Run the script and save the permissions in a variable

```powershell
$Perms = Export-Permission -SourcePath 'C:\' -GroupBy 'Item' -RecurseDepth 0
```

## Output the permissions

```powershell
$Perms
```

### Command Output

```
Path NetworkPaths
---- ------------
C:\  \\TestPC\C$\
```

## Output the Network Paths associated with the permissions

```powershell
$Perms.NetworkPaths
```

### Command Output

```
Item               Items
----               -----
\\TestPC\C$\ \\TestPC\C$\
```

## Output the Items associated with the Network Paths

```powershell
$Perms.NetworkPaths.Items
```

### Command Output

```
PS C:\Users\adminuser> $Perms.NetworkPaths.Items

Path               Access
----               ------
\\TestPC\C$\ {@{Account=TestPC\TrustedInstaller; Access=Allow FullControl this folder, subfolders, and files; DuetoMembershipIn=; SourceofAccess=Ownership; Name=TrustedInstaller; DisplayName=Windows Modules Installer; Company=; Department=; Title=; Description=Enables installation, modification, and…
```

## Output the permissions associated with the first Item in the list

```powershell
$Perms.NetworkPaths.Items[0].PassThru
```

### Command Output

```
Account           : TestPC\TrustedInstaller
Access            : Allow FullControl this folder, subfolders, and files
DuetoMembershipIn :
SourceofAccess    : Ownership
Name              : TrustedInstaller
DisplayName       : Windows Modules Installer
Company           :
Department        :
Title             :
Description       : Enables installation, modification, and removal of Windows updates and optional components. If this service is disabled, install or uninstall of Windows updates might fail for this computer.

Account           : TestPC\Users
Access            : Allow ReadAndExecute, Synchronize this folder, subfolders, and files
DuetoMembershipIn :
SourceofAccess    : Discretionary ACL
Name              : Users
DisplayName       :
Company           :
Department        :
Title             :
Description       : Users are prevented from making accidental or intentional system-wide changes and can run most applications

Account           : TestPC\adminuser
Access            : Allow FullControl this folder, subfolders, and files
DuetoMembershipIn : TestPC\Administrators
SourceofAccess    : Discretionary ACL
Name              : Owner
DisplayName       :
Company           :
Department        :
Title             :
Description       :

Account           : TestPC\Administrator
Access            : Allow FullControl this folder, subfolders, and files
DuetoMembershipIn : TestPC\Administrators
SourceofAccess    : Discretionary ACL
Name              : Administrator
DisplayName       :
Company           :
Department        :
Title             :
Description       : Built-in account for administering the computer/domain

Account           : TestPC\GuestAccount
Access            : Allow ReadAndExecute, Synchronize this folder, subfolders, and files
DuetoMembershipIn : TestPC\Users
SourceofAccess    : Discretionary ACL
Name              : GuestAccount
DisplayName       :
Company           :
Department        :
Title             :
Description       :

Account           : TestPC\testuser
Access            : Allow ReadAndExecute, Synchronize this folder, subfolders, and files
DuetoMembershipIn : TestPC\Users
SourceofAccess    : Discretionary ACL
Name              : testuser
DisplayName       :
Company           :
Department        :
Title             :
Description       :

Account           : TestPC\Authenticated Users
Access            : Allow CreateDirectories this folder but not subfolders
DuetoMembershipIn :
SourceofAccess    : Discretionary ACL
Name              : Authenticated Users
DisplayName       :
Company           :
Department        :
Title             :
Description       : TestPC\Authenticated Users

Account           : TestPC\Authenticated Users
Access            : Allow -536805376 this folder, subfolders, and files
DuetoMembershipIn :
SourceofAccess    : Discretionary ACL
Name              : Authenticated Users
DisplayName       :
Company           :
Department        :
Title             :
Description       : TestPC\Authenticated Users

Account           : TestPC\Administrators
Access            : Allow FullControl this folder, subfolders, and files
DuetoMembershipIn :
SourceofAccess    : Discretionary ACL
Name              : Administrators
DisplayName       :
Company           :
Department        :
Title             :
Description       : Administrators have complete and unrestricted access to the computer/domain

PS C:\Users\adminuser> $Perms.NetworkPaths.Items[0].PassThru

Account           : TestPC\TrustedInstaller
Access            : Allow FullControl this folder, subfolders, and files
DuetoMembershipIn :
SourceofAccess    : Ownership
Name              : TrustedInstaller
DisplayName       : Windows Modules Installer
Company           :
Department        :
Title             :
Description       : Enables installation, modification, and removal of Windows updates and optional components. If this service is disabled, install or uninstall of Windows updates might fail for this computer.

Account           : TestPC\Users
Access            : Allow ReadAndExecute, Synchronize this folder, subfolders, and files
DuetoMembershipIn :
SourceofAccess    : Discretionary ACL
Name              : Users
DisplayName       :
Company           :
Department        :
Title             :
Description       : Users are prevented from making accidental or intentional system-wide changes and can run most applications

Account           : TestPC\adminuser
Access            : Allow FullControl this folder, subfolders, and files
DuetoMembershipIn : TestPC\Administrators
SourceofAccess    : Discretionary ACL
Name              : Owner
DisplayName       :
Company           :
Department        :
Title             :
Description       :

Account           : TestPC\Administrator
Access            : Allow FullControl this folder, subfolders, and files
DuetoMembershipIn : TestPC\Administrators
SourceofAccess    : Discretionary ACL
Name              : Administrator
DisplayName       :
Company           :
Department        :
Title             :
Description       : Built-in account for administering the computer/domain

Account           : TestPC\GuestAccount
Access            : Allow ReadAndExecute, Synchronize this folder, subfolders, and files
DuetoMembershipIn : TestPC\Users
SourceofAccess    : Discretionary ACL
Name              : GuestAccount
DisplayName       :
Company           :
Department        :
Title             :
Description       :

Account           : TestPC\testuser
Access            : Allow ReadAndExecute, Synchronize this folder, subfolders, and files
DuetoMembershipIn : TestPC\Users
SourceofAccess    : Discretionary ACL
Name              : testuser
DisplayName       :
Company           :
Department        :
Title             :
Description       :

Account           : TestPC\Authenticated Users
Access            : Allow CreateDirectories this folder but not subfolders
DuetoMembershipIn :
SourceofAccess    : Discretionary ACL
Name              : Authenticated Users
DisplayName       :
Company           :
Department        :
Title             :
Description       : TestPC\Authenticated Users

Account           : TestPC\Authenticated Users
Access            : Allow -536805376 this folder, subfolders, and files
DuetoMembershipIn :
SourceofAccess    : Discretionary ACL
Name              : Authenticated Users
DisplayName       :
Company           :
Department        :
Title             :
Description       : TestPC\Authenticated Users

Account           : TestPC\Administrators
Access            : Allow FullControl this folder, subfolders, and files
DuetoMembershipIn :
SourceofAccess    : Discretionary ACL
Name              : Administrators
DisplayName       :
Company           :
Department        :
Title             :
Description       : Administrators have complete and unrestricted access to the computer/domain
```
