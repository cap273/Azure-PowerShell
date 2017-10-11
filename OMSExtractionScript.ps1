# Initializations
cls
$omsWorkspaceName = 'WMUSProdOMS01'
$subscriptionName = 'Infra Prod XPR'
$resourceGroupName = 'infraprodxpreastus2mrg'
$timeBlockSpaceMins = 2 #Generates ~3K of data every 3 mins
$daysOfHistoricalData = 6
$outputFolder = "C:\testuser\Desktop\OMS"
$ErrorActionPreference = 'Stop'

# Get current time and date as universal time. 
$currentDateTime = (Get-Date).ToUniversalTime()

# Convert current date and time to SortableDateTimePattern. Example output: 2017-01-25T21:04:34
$currentDateTimeSortable = Get-Date -Date $currentDateTime -Format s

# Get the date and time seven days ago, both DateTime format, and SortableDateTimePattern (string) format
$workingStartDateTime = $currentDateTime.AddDays(-$daysOfHistoricalData)
$workingStartDateTimeSortable = Get-Date -Date $workingStartDateTime -Format s

#Get the end date and time of the first block of time to be examined
$workingEndDateTime = $workingStartDateTime.AddMinutes($timeBlockSpaceMins)
$workingEndDateTimeSortable = Get-Date -Date $workingEndDateTime -Format s

# Get the OMS workspace object
$omsWorkSpace = Get-AzureRmOperationalInsightsWorkspace -ResourceGroupName $resourceGroupName `
                                                        -Name $omsWorkspaceName

# Define function to get data from Log Analytics in OMS
Function Get-Data {
    param(
        $resourceGroupName,
        $workspaceName,
        $dynamicQuery
    )

    # Initialize retry counter limit to get Log Analytics results
    $retryLimit = 10

    # Initialize current number of retries to get Log Analytics data
    $retryCount = 0

    # Initialize while-loop condition for retry
    $inProgress = $true

    while ($inProgress) {

        #Attempt to get the data from Log Analytics
        try{
            $result = Get-AzureRmOperationalInsightsSearchResults `
                -ResourceGroupName $resourceGroupName `
                -WorkspaceName $omsWorkspaceName `
                -Query "$dynamicQuery" `
                -Top 1000000

            #If an error was not returned, signal the while loop to finish
            $inProgress = $false
        }
        catch{
            
            #If there was an error retrieving data, update retry counter
            $retryCount++

            # If the trtry counter does not exceed retry limit, retry getting data
            if ($retryCount -le $retryLimit) {
                
                Write-Host "The cmdlet Get-AzureRmOperationalInsightsSearchResults failed. Retrying... current retry: $retryCount. Retry limit: $retryLimit"
                Continue

            } else{
                $ErrorMessage = $_.Exception.Message
                Write-Host "The cmdlet Get-AzureRmOperationalInsightsSearchResults failed with the following message:" -BackgroundColor Black -ForegroundColor Red
                throw "$ErrorMessage"
            }

        }
    }

    # Return the OMS query as a PowerShell object
    return $result.Value | ConvertFrom-Json
}

#Initialize an index counter
$index = 1


Write-Output "Current time: $currentDateTime"
Write-Output "Start date and time from which to begin search: $workingStartDateTime `n"

#Retrieve the Log Analytics data from OMS workspace in blocks of 10mins
#There is a limitation where each API call can only retreive a maximum of 5000 data rows at the same time
#Do until the block of time being looked at exceeds the time at which the script first started
do{

    # Set the query to execute against Log Analytics
    $dynamicQuery = "* Type=NetworkMonitoring AND TimeProcessed>=$workingStartDateTimeSortable AND TimeProcessed<$workingEndDateTimeSortable AND NOT(RuleName=Bentonville)"

    
    #Initialize a one-element array, and store results in first element of array (for compatibility with functionality below)
    $OMSQueryArray=@($false) * 1
    $OMSQueryArray[0] = Get-Data -resourceGroupName $resourceGroupName `
                                 -workspaceName $omsWorkspaceName `
                                 -dynamicQuery $dynamicQuery

    # Get number of data rows for this log search
    $numRows = ($OMSQueryArray[0] | Measure).Count

    Write-Output "Current date & time range: $workingStartDateTime to $workingEndDateTime"

    if ($numRows -ne 0) {
        if ($numRows -lt 5000) {

            Write-Output "Number of data rows in this time range: $numRows `n"
        }
        else{
            # Since original query returned more than 5000 results, split up into two queries, by source network
            $OMSQueryArray=@($false) * 2 #Reset arrays of query results, this time with two elements

            Write-Output "Original query exceeds 5000 results. Splitting up search results by Source Network... `n"

            # Execute query where SourceNetwork=InfraProdXPREastUS2evn03
            $dynamicQuery1 = "* Type=NetworkMonitoring AND TimeProcessed>=$workingStartDateTimeSortable AND TimeProcessed<$workingEndDateTimeSortable AND NOT(RuleName=Bentonville) AND SourceNetwork=InfraProdXPREastUS2evn03"

            $OMSQueryArray[0] = Get-Data -resourceGroupName $resourceGroupName `
                                 -workspaceName $omsWorkspaceName `
                                 -dynamicQuery $dynamicQuery1

            $numRows = ($OMSQueryArray[0] | Measure).Count

            if ($numRows -lt 5000) {

                Write-Output "Number of data rows in this time range for Source Network InfraProdXPREastUS2evn03: $numRows `n"
            }
            else{
                throw "Results for Source Network InfraProdXPREastUS2evn03 still over 5000 results."
            } 
        

            # Execute query where SourceNetwork=InfraProdXPRSCUSevn03
            $dynamicQuery2 = "* Type=NetworkMonitoring AND TimeProcessed>=$workingStartDateTimeSortable AND TimeProcessed<$workingEndDateTimeSortable AND NOT(RuleName=Bentonville) AND SourceNetwork=InfraProdXPRSCUSevn03"

            $OMSQueryArray[1] = Get-Data -resourceGroupName $resourceGroupName `
                                 -workspaceName $omsWorkspaceName `
                                 -dynamicQuery $dynamicQuery2

            $numRows = ($OMSQueryArray[1] | Measure).Count

            if ($numRows -lt 5000) {

                Write-Output "Number of data rows in this time range for Source Network InfraProdXPRSCUSevn03: $numRows `n"
            }
            else{
                throw "Results for Source Network InfraProdXPRSCUSevn03 still over 5000 results."
            }    
        }
    
        # Loop through all of the different OMS Queries executed
        foreach($OMSQuery in $OMSQueryArray) {

            # Initialize/reset the variable used to hold the output from OMS
            $VMMemoryDisk = @()  

            # Get the data from OMS into object
            foreach($OMS in $OMSQuery){
              $objAverage = New-Object System.Object
                $objAverage | Add-Member -type NoteProperty -name Name -value $OMS.Computer
                $objAverage | Add-Member -type NoteProperty -name Loss -value $OMS.Loss
                $objAverage | Add-Member -type NoteProperty -name TimeProcessed -value $OMS.TimeProcessed
                $objAverage | Add-Member -type NoteProperty -name HighLatency -value $OMS.HighLatency 
                $objAverage | Add-Member -type NoteProperty -name MedianLatency -value $OMS.MedianLatency
                $objAverage | Add-Member -type NoteProperty -name SourceNetworkNodeInterface -value $OMS.SourceNetworkNodeInterface 
                $objAverage | Add-Member -type NoteProperty -name DestinationNetworkNodeInterface -value $OMS.DestinationNetworkNodeInterface
                $objAverage | Add-Member -type NoteProperty -name SourceNetwork -value $OMS.SourceNetwork
                $objAverage | Add-Member -type NoteProperty -name DestinationNetwork -value $OMS.DestinationNetwork
                $objAverage | Add-Member -type NoteProperty -name SourceSubNetwork -value $OMS.SourceSubNetwork
                $objAverage | Add-Member -type NoteProperty -name DestinationSubNetwork -value $OMS.DestinationSubNetwork
                $objAverage | Add-Member -type NoteProperty -name SubType -value $OMS.SubType
                $objAverage | Add-Member -type NoteProperty -name Path -value $OMS.Path

                $VMMemoryDisk += $objAverage
            }
    
            # Set the name of the CSV file
            $outputFile = "output" + $index.ToString("00000") + ".csv"
            $path = Join-Path -Path $outputFolder -ChildPath $outputFile

            # Output object from OMS output to CSV
            $VMMemoryDisk | Export-Csv -Path $path -NoTypeInformation

            # Update index counter
            $index++
        }
    }
    else{ #If the number of data rows is 0, don't bother writing to a CSV file
        
        Write-Output "There are no data rows in this time range. `n"
    }
                     
    # Update the block of time in which to execute search
    $workingStartDateTime = $workingEndDateTime
    $workingStartDateTimeSortable = Get-Date -Date $workingStartDateTime -Format s

    $workingEndDateTime = $workingEndDateTime.AddMinutes($timeBlockSpaceMins)
    $workingEndDateTimeSortable = Get-Date -Date $workingEndDateTime -Format s

}until($currentDateTimeSortable -lt $workingEndDateTimeSortable )