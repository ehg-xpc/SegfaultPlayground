function Assert-HyperVAdmin {
    $principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    $isAdmin   = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $isAdmin) {
        # Hyper-V Administrators (S-1-5-32-578) is sufficient for all VM management operations.
        # Full admin is only needed for host-level changes (enabling the Hyper-V feature, etc.).
        $hvAdminSid = [System.Security.Principal.SecurityIdentifier]::new('S-1-5-32-578')
        $isHvAdmin  = [System.Security.Principal.WindowsIdentity]::GetCurrent().Groups -contains $hvAdminSid

        if (-not $isHvAdmin) {
            throw (
                'HyperVToolkit requires membership in the local Administrators or Hyper-V Administrators group. ' +
                "To add yourself: Add-LocalGroupMember -Group 'Hyper-V Administrators' -Member $env:USERNAME  (then re-login)"
            )
        }
    }

    $hvModule = Get-Module -Name Hyper-V -ListAvailable
    if (-not $hvModule) {
        throw 'The Hyper-V PowerShell module is not available on this system. Enable the Hyper-V management tools Windows feature.'
    }
}
