Workflow TestWorkflow 
{  
    Write-Output "variable in workflow"

    $testvar = InlineScript 
    {
        .\testscript.ps1
    }

    Write-Output $testvar
}
