# Demo of GroupBy Account

## Run the script and save the permissions in a variable

```powershell
$Perms = Export-Permission -SourcePath 'C:\' -GroupBy 'Account' -RecurseDepth 0
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
Item               Accounts
----               --------
\\TestPC\C$\ {TestPC\Administrator, TestPC\Administrators, TestPC\Authenticated Users, TestPC\GuestAccount…}
```

## Output the Accounts associated with the Network Paths

```powershell
$Perms.NetworkPaths.Accounts
```

### Command Output

```
AccountCaption                   Access
--------------                   ------
TestPC\Administrator       @{Path=\\TestPC\C$\; Access=Allow FullControl this folder, subfolders, and files; DuetoMembershipIn=TestPC\Administrators; SourceofAccess=Discretionary ACL; DisplayName=; Company=; Department=; Title=; Description=}
TestPC\Administrators      @{Path=\\TestPC\C$\; Access=Allow FullControl this folder, subfolders, and files; DuetoMembershipIn=; SourceofAccess=Discretionary ACL; DisplayName=; Company=; Department=; Title=; Description=}
TestPC\Authenticated Users {@{Path=\\TestPC\C$\; Access=Allow CreateDirectories this folder but not subfolders; DuetoMembershipIn=; SourceofAccess=Discretionary ACL; DisplayName=; Company=; Department=; Title=; Description=}, @{Path=\\TestPC\C$\; Access=Allow -536805376 this folder, subfolders, a…
TestPC\GuestAccount        @{Path=\\TestPC\C$\; Access=Allow ReadAndExecute, Synchronize this folder, subfolders, and files; DuetoMembershipIn=TestPC\Users; SourceofAccess=Discretionary ACL; DisplayName=; Company=; Department=; Title=; Description=}
TestPC\adminuser               @{Path=\\TestPC\C$\; Access=Allow FullControl this folder, subfolders, and files; DuetoMembershipIn=TestPC\Administrators; SourceofAccess=Discretionary ACL; DisplayName=; Company=; Department=; Title=; Description=}
TestPC\testuser         @{Path=\\TestPC\C$\; Access=Allow ReadAndExecute, Synchronize this folder, subfolders, and files; DuetoMembershipIn=TestPC\Users; SourceofAccess=Discretionary ACL; DisplayName=; Company=; Department=; Title=; Description=}
TestPC\TrustedInstaller    @{Path=\\TestPC\C$\; Access=Allow FullControl this folder, subfolders, and files; DuetoMembershipIn=; SourceofAccess=Ownership; DisplayName=; Company=; Department=; Title=; Description=}
TestPC\Users               @{Path=\\TestPC\C$\; Access=Allow ReadAndExecute, Synchronize this folder, subfolders, and files; DuetoMembershipIn=; SourceofAccess=Discretionary ACL; DisplayName=; Company=; Department=; Title=; Description=}
```

## Output the permissions associated with the first Account in the list

```powershell
$Perms.NetworkPaths.Accounts[0].PassThru
```

### Command Output

```
Path              : \\TestPC\C$\
Access            : Allow FullControl this folder, subfolders, and files
DuetoMembershipIn : TestPC\Administrators
SourceofAccess    : Discretionary ACL
DisplayName       :
Company           :
Department        :
Title             :
Description       :
```
