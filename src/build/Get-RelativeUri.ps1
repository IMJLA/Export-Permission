
param (
    [string]$Start,
    [string]$Target
)

[System.IO.Path]::GetRelativePath($Start, $Start)
