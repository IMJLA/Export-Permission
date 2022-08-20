BeforeDiscovery {

    if ($env:AppData) {
        $ParentFolderPath = "$env:AppData\TestFolder"
    } else {
        $ParentFolderPath = ".\TestFolder"
    }
    $ChildFolderPath = "$ParentFolderPath\Subfolder"
    $null = Remove-Item -Path $ChildFolderPath -Recurse -ErrorAction SilentlyContinue
    $null = New-Item -ItemType Directory -Path $ChildFolderPath -ErrorAction SilentlyContinue

    $ParentAcl = Get-Acl -Path $ParentFolderPath
    $ChildAcl = Get-Acl -Path $ChildFolderPath

    $ParentAcl.SetOwner('Administrators')
    $ChildAcl.SetOwner('Guests')

    Set-Acl -Path $ParentFolderPath -AclObject $ParentAcl
    Set-Acl -Path $ChildFolderPath -AclObject $ChildAcl

}

describe "Should include BUILTIN\Guests" {
    #.\src\Export-Permission.ps1 -TargetPath $ParentFolderPath
}


