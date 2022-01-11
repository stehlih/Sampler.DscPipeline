configuration RootConfiguration
{
    #<importStatements>

    $module = Get-Module -Name PSDesiredStateConfiguration
    & $module {
        param (
            [string]$ModuleVersion,
            [string]$Environment
        )
        $Script:PSTopConfigurationName = "MOF_$($Environment)_$($ModuleVersion)"
    } $ModuleVersion, $environment

    node $ConfigurationData.AllNodes.NodeName {
        Write-Host "`r`n$('-'*75)`r`n$($Node.Name) : $($Node.NodeName) : $(&$module { $Script:PSTopConfigurationName })" -ForegroundColor Yellow

        $configurationNames = Resolve-NodeProperty -PropertyPath 'Configurations' -Node $Node
        $global:node = $node #this makes the node variable being propagated into the configurations

        foreach ($configurationName in $configurationNames)
        {
            Write-Debug "`tLooking up params for $configurationName"
            $properties = Resolve-NodeProperty -PropertyPath $configurationName -DefaultValue @{}

            $dscError = [System.Collections.ArrayList]::new()

            (Get-DscSplattedResource -ResourceName $configurationName -ExecutionName $configurationName -Properties $properties -NoInvoke).Invoke($properties)

            if ($Error[0] -and $lastError -ne $Error[0])
            {
                $lastIndex = [Math]::Max(($Error.LastIndexOf($lastError) - 1), -1)
                if ($lastIndex -gt 0)
                {
                    $Error[0..$lastIndex].Foreach{
                        if ($message = Get-DscErrorMessage -Exception $_.Exception)
                        {
                            $null = $dscError.Add($message)
                        }
                    }
                }
                else
                {
                    if ($message = Get-DscErrorMessage -Exception $Error[0].Exception)
                    {
                        $null = $dscError.Add($message)
                    }
                }
                $lastError = $Error[0]
            }

            if ($dscError.Count -gt 0)
            {
                $warningMessage = "    $($Node.Name) : $($Node.Role) ::> $configurationName "
                $n = [System.Math]::Max(1, 100 - $warningMessage.Length)
                Write-Host "$warningMessage$('.' * $n)FAILED" -ForegroundColor Yellow
                $dscError.Foreach{
                    Write-Host "`t$message" -ForegroundColor Yellow
                }
            }
            else
            {
                $okMessage = "    $($Node.Name) : $($Node.Role) ::> $configurationName "
                $n = [System.Math]::Max(1, 100 - $okMessage.Length)
                Write-Host "$okMessage$('.' * $n)OK" -ForegroundColor Green
            }
        }
    }
    $global:node = $node = $null
}
