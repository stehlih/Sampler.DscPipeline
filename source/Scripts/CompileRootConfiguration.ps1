Import-Module -Name DscBuildHelpers
$Error.Clear()

if (-not $ModuleVersion)
{
    $ModuleVersion = '0.0.0'
}

$environment = $node.Environment
if (-not $environment)
{
    $environment = 'NA'
}

#Compiling MOF from RSOP cache
$rsopCache = Get-DatumRsopCache

<#
This information is taken from build.yaml

Sampler.DscPipeline:
  DscCompositeResourceModules:
  - Name: CommonTasks
    Version: 0.3.259
  - PSDesiredStateConfiguration
#>

if (-not $BuildInfo.'Sampler.DscPipeline')
{
    Write-Error -Message "There are no modules to import defined in the 'build.yml'. Expected the element 'Sampler.DscPipeline'"
}
if (-not $BuildInfo.'Sampler.DscPipeline'.DscCompositeResourceModules)
{
    Write-Error -Message "There are no modules to import defined in the 'build.yml'. Expected the element 'Sampler.DscPipeline'.DscCompositeResourceModules"
}
if ($BuildInfo.'Sampler.DscPipeline'.DscCompositeResourceModules.Count -lt 1)
{
    Write-Error -Message "There are no modules to import defined in the 'build.yml'. Expected at least one module defined under 'Sampler.DscPipeline'.DscCompositeResourceModules"
}

Write-Host -Object "RootConfiguration will import these composite resource modules as defined in 'build.yaml':"
foreach ($module in $BuildInfo.'Sampler.DscPipeline'.DscCompositeResourceModules)
{
    if ($module -is [hashtable])
    {
        Write-Host -Object "`t- $($module.Name) ($($module.Version))"
    }
    else
    {
        Write-Host -Object "`t- $module"
    }
}

Write-Host -Object "Preloading available resources"
$availableResources = Get-DscResource

Write-Host -Object ''

$configData = @{}
$configData.Datum = $ConfigurationData.Datum

# Save the current PSModulePath to reset it at the end of MOF build for each node.
# In some circumstances the MOF compilation manipulates the PSModulePath and 
# are the cause of duplicate CIM class definition errors on the following nodes. 
$curPSModulePath = $env:PSModulePath

foreach ($node in $rsopCache.GetEnumerator())
{
    $importStatements = foreach ($configurationItem in $node.Value.Configurations)
    {
        $resource = $availableResources.Where({$_.Name -eq $configurationItem})
        if ($null -eq $resource)
        {
            Write-Debug -Message "No DSC resource found for configuration $configurationItem"
            continue
        }

        "Import-DscResource -ModuleName $($resource.ModuleName) -ModuleVersion $($resource.Version) -Name $($resource.Name)`n"
    }

    $rootConfiguration = Get-Content -Path $PSScriptRoot\RootConfiguration.ps1 -Raw
    $rootConfiguration = $rootConfiguration -replace '#<importStatements>', ($importStatements | Select-Object -Unique)

    Invoke-Expression -Command $rootConfiguration

    $configData.AllNodes = @([hashtable]$node.Value)
    try
    {
        $path = Join-Path -Path MOF -ChildPath $node.Value.Environment
        RootConfiguration -ConfigurationData $configData -OutputPath (Join-Path -Path $BuildOutput -ChildPath $path)
    }
    catch
    {
        Write-Host -Object "Error occured during compilation of node '$($node.NodeName)' : $($_.Exception.Message)" -ForegroundColor Red
        $relevantErrors = $Error | Where-Object Exception -IsNot [System.Management.Automation.ItemNotFoundException]
        Write-Host -Object ($relevantErrors[0..2] | Out-String) -ForegroundColor Red
    }
    finally
    {
        # reset PSModulePath to original value to reset changes by MOF compilation
        $env:PSModulePath = $curPSModulePath
    }
}
