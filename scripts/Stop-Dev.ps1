#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess)]
param()

$arguments = @{ Action = 'Stop' }
if ($PSBoundParameters.ContainsKey('WhatIf')) {
    $arguments.WhatIf = $PSBoundParameters.WhatIf
}
if ($PSBoundParameters.ContainsKey('Confirm')) {
    $arguments.Confirm = $PSBoundParameters.Confirm
}
& (Join-Path $PSScriptRoot 'Set-DevState.ps1') @arguments
