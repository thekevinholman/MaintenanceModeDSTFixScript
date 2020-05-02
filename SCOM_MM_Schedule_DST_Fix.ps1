#=================================================================================
#  Powershell script to manually edit MM schedules to fix for DST
#  Run this script after a DST time change to get your schedules back on the right start time
#
#  Author: Kevin Holman
#  v1.3
#=================================================================================


# Constants section - modify stuff here:
#=================================================================================
# Assign script name variable for use in event logging.  
# ScriptName should be the same as the ID of the module that the script is contained in
$ScriptName = "SCOM.MMSchedule.DST.Edit"
$EventID = "4321"
[string]$LogFile = "C:\Temp\SCOM_MM_Schedule_Edit.log"
$SCOMServer = "localhost"
#=================================================================================


# Functions
#=================================================================================
#Function for logging to a file
Function Write-Log 
{
  [CmdletBinding()]
  Param(
  [Parameter(Mandatory=$False)]
  [ValidateSet("INFO","SUCCESS","WARN","ERROR","MISSING")]
  [String]$Result = "INFO",

  [Parameter(Mandatory=$True)]
  [string]$Message
  )

  $Stamp = (Get-Date).toString("yyyy/MM/dd HH:mm:ss")
  $Line = "$Stamp,$Result,$Message"
  Add-Content $LogFile -Value $Line
}
#=================================================================================


# Starting Script section - All scripts get this
#=================================================================================
# Gather the start time of the script
$StartTime = Get-Date
#Set variable to be used in logging events
$whoami = whoami
#Log script event that we are starting task
Write-Log -Result INFO -Message "Script is starting. Running as ($whoami)."
#=================================================================================


# Connect to local SCOM Management Group Section - If required
#=================================================================================
# I have found this to be the most reliable method to load SCOM modules for scripts running on Management Servers
# Clear any previous errors
$Error.Clear()
# Import the OperationsManager module and connect to the management group
$SCOMPowerShellKey = "HKLM:\SOFTWARE\Microsoft\System Center Operations Manager\12\Setup\Powershell\V2"
$SCOMModulePath = Join-Path (Get-ItemProperty $SCOMPowerShellKey).InstallDirectory "OperationsManager"
Import-module $SCOMModulePath
New-DefaultManagementGroupConnection $SCOMServer
IF ($Error) 
{ 
  $momapi.LogScriptEvent($ScriptName,$EventID,1,"`n FATAL ERROR: Unable to load OperationsManager module or unable to connect to Management Server. `n Terminating script. `n Error is: ($Error).")
  EXIT
}
#=================================================================================


# Begin MAIN script section
#=================================================================================
#Get SCOM Maintenance Schedules
$MMschedules = Get-SCOMMaintenanceScheduleList

$i=0
FOREACH ($schedule in $MMschedules)
{
  $ScheduleID = $schedule.ScheduleId.Guid
  $ScheduleObj = Get-SCOMMaintenanceSchedule -ID $ScheduleID
  $ScheduleName = $ScheduleObj.ScheduleName
  $ActiveStartTime = $ScheduleObj.ActiveStartTime
  $ActiveEndDate = $ScheduleObj.ActiveEndDate
  $ScheduleStatus = $ScheduleObj.Status

  #Check to see if the Schedule is currently running and skip if it is
  IF ($ScheduleStatus -ne "Running")
  {
    #Check to see if ActiveEndDate is in the past (Expired schedule) and only continue if it is
    IF ($ActiveEndDate -gt $StartTime)
    {
      #Check to see if Active Start time is in the future and skip if it is
      IF ($ActiveStartTime -lt $StartTime)
      {
        $ActiveStartHour = $ActiveStartTime.Hour
        $ActiveStartMinute = $ActiveStartTime.Minute
        $NewStartDateTime = Get-Date -Hour $ActiveStartHour -Minute $ActiveStartMinute -Second "00"
        Write-Host "Modifying ($ScheduleName) with existing start time of ($ActiveStartTime) to NEW start time of ($NewStartDateTime)."
        Write-Log -Result INFO -Message "Modifying ($ScheduleName) with existing start time of ($ActiveStartTime) to NEW start time of ($NewStartDateTime)."

        #Edit the schedule.  Comment out this line to test the script taking no action
        Edit-SCOMMaintenanceSchedule -ScheduleId $ScheduleID -ActiveStartTime $NewStartDateTime
        $i++  
      }
      ELSE
      {
        Write-Host "Skipping ($ScheduleName) because the schedule start time is in the future.  Current schedule start time is: ($ActiveStartTime)."
        Write-Log -Result INFO -Message "Skipping ($ScheduleName) because the schedule start time is in the future.  Current schedule start time is: ($ActiveStartTime)."  
      }
    }
    ELSE
    {
      Write-Host "Skipping ($ScheduleName) because the schedule end date is already expired.  Current schedule end date is: ($ActiveEndDate)."
      Write-Log -Result INFO -Message "Skipping ($ScheduleName) because the schedule end date is already expired.  Current schedule end date is: ($ActiveEndDate)."   
    }
  }
  ELSE
  {
    Write-Host "WARNING:  Skipping ($ScheduleName) because it is currently running.  Running schedules cannot be edited."
    Write-Log -Result WARN -Message "WARNING:  Skipping ($ScheduleName) because it is currently running.  Running schedules cannot be edited."   
  }
}
Write-Host "Operation complected.  Modified ($i) MM schedules."
Write-Log -Result INFO -Message "Operation completed.  Modified ($i) MM schedules."
#=================================================================================
# End MAIN script section


# End of script section
#=================================================================================
#Log an event for script ending and total execution time.
$EndTime = Get-Date
$ScriptTime = ($EndTime - $StartTime).TotalSeconds
Write-Log -Result INFO -Message "Script Completed. Script Runtime: ($ScriptTime) seconds."
#=================================================================================
# End of script