$LogPath = 'C:\Users\Owner\AppData\Roaming\Export-Permission\'
$Year = Get-ChildItem $LogPath -Directory | Sort -Descending | Select -First 1 -ExpandProperty Name
$Month = Get-ChildItem "$LogPath\$Year" -Directory | Sort -Descending | Select -First 1 -ExpandProperty Name
$Folder = Get-ChildItem "$LogPath\$Year\$Month" -Directory | Sort -Descending | Select -First 1 -ExpandProperty FullName
$File = "$Folder\Export-Permission.log"
$LogEntries = Import-Csv -Path $File -Delimiter "`t"
$ParentCommand = 'Export-Permission.ps1'
$CommandStartingIndex = 0
$CommandStart = $LogEntries[0].Timestamp

for ( $i = 0 ; $i -lt $LogEntries.Count ; $i++ ) {

    $ThisEntry = $LogEntries[$i]
    $j = $i + 1

    if ($j -lt $LogEntries.Count) {
        $NextEntry = $LogEntries[$j]
        $Timespan = New-TimeSpan -Start $ThisEntry.Timestamp -End $NextEntry.Timestamp
        $LogEntries[$i] | Add-Member -MemberType NoteProperty -Name EntryTook -Value $Timespan -Force
    }

    if (
        $NextEntry.Command -eq $ParentCommand
    ) {
        $Timespan = New-TimeSpan -Start $CommandStart -End $NextEntry.Timestamp
        $LogEntries[$CommandStartingIndex] | Add-Member -MemberType NoteProperty -Name CommandTook -Value $Timespan -Force
        $CommandStartingIndex = $j
        $CommandStart = $NextEntry.Timestamp
    }

}

$LogEntries | Where-Object -FilterScript { $_.CommandTook } | Select-Object CommandTook, Text
