@{
    # Need a test to detect missing [CmdletBinding()] in public function
    # Need a test to detect missing pipeline support (at least 1 parameter needs to support [Parameter(ValueFromPipeline)])
    # Need a test to detect missing pipeline support (needs a process block)
    # Need a test to detect missing pipeline AND full collection support (process block needs to loop through the pipeline input parameter)
    # Need a test to detect .Net type accelerators (aliases) and a Fix to replace them with their corresponding fully-qualified types
    #####[System.Management.Automation.PSObject].Assembly.GetType("System.Management.Automation.TypeAccelerators")::Get
}
