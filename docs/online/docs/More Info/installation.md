TODO: Add this to the README

<h4>ERROR:</h4>

    Export-Permission : The term 'Export-Permission' is not recognized as the name of a cmdlet, function, script file, or
    operable program. Check the spelling of the name, or if a path was included, verify that the path is correct and try
    again.

<h4>CAUSE:</h4>

Earlier versions of the PowerShellGet module did not offer to add the directories targeted by the Install-Script cmdlet to $env:PATH persistently, but as of at least v2.2.4 they do (a prompt is presented), the next time you call Install-Script to perform an actual installation.

<h4>SOLUTION:</h4>

Use the latest version of the PowerShellGet module.  In an elevated PowerShell window (running as an administrator):

    Update-Module PowerShellGet

On old versions this may result in an error stating that because PowerShellGet module was not installed by Install-Module it cannot be updated by Update-Module.  In this case we can force the installation anyway:

    Install-Module PowerShellGet -AllowClobber -Force
    Exit # Exit PowerShell to ensure the old module version is not loaded

Then in a new elevated PowerShell window:

    Install-Script Export-Permission

Then, answer Yes to the prompt to add the PowerShell Scripts folder to the PATH environment variable:

    PATH Environment Variable Change
    Your system has not been configured with a default script installation path yet, which means you can only run a script
    by specifying the full path to the script file. This action places the script into the folder 'C:\Program
    Files\WindowsPowerShell\Scripts', and adds that folder to your PATH environment variable. Do you want to add the script
     installation path 'C:\Program Files\WindowsPowerShell\Scripts' to the PATH environment variable?
    [Y] Yes  [N] No  [S] Suspend  [?] Help (default is "Y"):

Then answer Yes to the prompt to install the script from PSGallery:

    Untrusted repository
    You are installing the scripts from an untrusted repository. If you trust this repository, change its
    InstallationPolicy value by running the Set-PSRepository cmdlet. Are you sure you want to install the scripts from
    'PSGallery'?
    [Y] Yes  [A] Yes to All  [N] No  [L] No to All  [S] Suspend  [?] Help (default is "N"):

Then any new powershell windows launched in the future will be able to run Export-Permission without specifying the full file path.
