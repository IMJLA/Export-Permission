BeforeDiscovery {

    if ($env:AppData) {
        $ParentFolderPath = "$env:AppData\TestFolder"
    } else {
        $ParentFolderPath = ".\TestFolder"
    }
    $ChildFolderPath = "$ParentFolderPath\Subfolder"
    $null = New-Item -ItemType Directory -Path $ChildFolderPath

    $ParentAcl = Get-Acl -Path $ParentFolderPath
    $ChildAcl = Get-Acl -Path $ChildFolderPath

    $ParentAcl.SetOwner('BUILTIN\Administrators')
    $ChildAcl.SetOwner('BUILTIN\Guests')

    Set-Acl -Path $ParentFolderPath -AclObject $ParentAcl
    Set-Acl -Path $ChildFolderPath -AclObject $ChildAcl

}

describe "Should include BUILTIN\Guests" {
    .\src\Export-Permission.ps1 -TargetPath $ParentFolderPath
}


