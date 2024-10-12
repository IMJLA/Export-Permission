
param (
    [uri]$Start,
    [uri]$Target
)

$Start.MakeRelativeUri($Target).ToString()
