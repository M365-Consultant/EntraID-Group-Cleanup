<#PSScriptInfo
.VERSION 0.1
.GUID f5d6e7f2-9d1e-4d7b-9a4f-2f1b1c3d0c6a
.AUTHOR Dominik Gilgen
.COMPANYNAME Dominik Gilgen (Personal)
.COPYRIGHT 2023 Dominik Gilgen. All rights reserved.
.LICENSEURI https://github.com/M365-Consultant/EntraID-Group-Cleanup/blob/main/LICENSE
.PROJECTURI https://github.com/M365-Consultant/EntraID-Group-Cleanup/
.EXTERNALMODULEDEPENDENCIES Microsoft.Graph.Authentication,Microsoft.Graph.Groups,Microsoft.Graph.Reports,Microsoft.Graph.Users,Microsoft.Graph.Users.Actions
#>

<# 
.DESCRIPTION 
 Azure Runbook - Dynamic Group - MFA State
 
 This script is designed for an Azure Runbook to automatically remove users from an EntraID (AzureAD) group, based on the time of membership (max.30 days).
 Please note that this script relies on the Audit Log to retrieve the timestamp of a user's addition to a group. As a result, the maximum timeframe available is determined by the retention period set for your Audit Log!

 Before running the runbook, you need to set up an automation account with a managed identity.
 
 The managed identity requires the following Graph Permissions:
    - User.Read.All
    - AuditLog.Read.All
    - Group.ReadWrite.All
    - Mail.ReadWrite
    - Mail.Send

 The script requires the following modules:
    - Microsoft.Graph.Authentication
    - Microsoft.Graph.Groups
    - Microsoft.Graph.Reports
    - Microsoft.Graph.Users
    - Microsoft.Graph.Users.Actions
 

 There are a few parameters which must be set for a job run:
    - $groupID -> The Object-ID of a EntraID (AzureAD) group)
    - $timeCleanup -> The time in MINUTES, for how long a user should remain in the group (maximum is your Audit-Log retention!)
    - $mailMode -> This is controlling the mail behavior (enter the mode you want without ' )
        'always' - sends a mail on every run
        'removal' - sends a mail only if a user has been removed from a group
        'disabled' - never send a mail
    - $mailSender -> The mail-alias from which the mail will be send (can be a user-account or a shared-mailbox)
    - $mailRecipients -> The recpient(s) of a mail. If you want more than one recpient, you can seperate them with ;
#> 


Param
(
  [Parameter (Mandatory= $true)]
  [String] $groupID,
  [Parameter (Mandatory= $true)]
  [String] $timeCleanup,
  [Parameter (Mandatory= $false)]
  [String] $mailMode,
  [Parameter (Mandatory= $false)]
  [String] $mailSender,
  [Parameter (Mandatory= $false)]
  [String] $mailRecipients
)

#Connect to Microsoft Graph within Azure Automation
Connect-MgGraph -Identity


#Setting variables
$timeNow = (Get-Date).ToUniversalTime()
$groupMembers = Get-MgGroupMember -GroupId $groupID -All
$groupName = Get-MgGroup -GroupId $groupID
$filterAction = "activityDisplayName eq 'Add member to group'" 
$filterGroup = "targetResources/any(t:t/Id eq '"+$groupID+"')"

#Mail content
$mailContent = "<p style='font-weight:bold'>The Azure runbook for removing users from the group '" +$groupName.DisplayName+ "' has been executed.</p><br>"
$mailContentRemoved = "<p style='color: orange'>Those users has been removed from the group:</p>"
$mailContentNothing = "<br><p style='color: green'>Those users will remain in the group:</p>"


#Check group membership and remove users who have exceeded the cleanup time
foreach ($user in $groupMembers) {
    $userdetail = Get-MgUser -UserId $user.Id
    $filterUser = "targetResources/any(t:t/Id eq '"+$user.Id+"')"
    $audit = Get-MgAuditLogDirectoryAudit -filter "$filterAction and $filterUser and $filterGroup" -Top 1

    if($audit){
        $timeDiff = $timeNow - $audit.ActivityDateTime
        if ($timeDiff.TotalMinutes-gt $timeCleanup){
            $output = "Remove User: " + $userdetail.UserPrincipalName
            Write-Output $output
            $mailContentRemoved += $userdetail.UserPrincipalName + "<br>"
            Remove-MgGroupMemberByRef -GroupId $groupID -DirectoryObjectId $user.Id
        }
        else {
            $remaining = $timeCleanup - ([math]::round($timeDiff.TotalMinutes,0))
            $output = "Keep User: " + $userdetail.UserPrincipalName + " (" + $remaining +" min. remaining)"
            Write-Output $output
            $mailContentNothing += $userdetail.UserPrincipalName + " (" + $remaining +" min. remaining)<br>"
        }
    }
    else{
        $warningNoentryfound = "No audit-log entry found for "+$userdetail.UserPrincipalName
        Write-Warning $warningNoentryfound
        $mailContent += "<p style='color: red'>" + $warningNoentryfound + "</p><br>"
    }
}


# Sendmail
function runbookSendMail {
    $mailRecipientsArray = $mailRecipients.Split(";")
    $mailSubject = "Azure Runbook Report: Group Cleanup (" + $groupName.DisplayName + ")"
    $mailContent += $mailContentRemoved + $mailContentNothing
    $mailContent += "<br><br><p style='color: grey'>You can find additional details in the job history of this runbook.<br>Job finished at (UTC) " + (Get-Date).ToUniversalTime() + "<br>Job ID:"+ $PSPrivateMetadata.JobId.Guid + "</p>"

    $params = @{
            Message = @{
                Subject = $mailSubject
                Body = @{
                    ContentType = "html"
                    Content = $mailContent
                }
                ToRecipients = @(
                    foreach ($recipient in $mailRecipientsArray) {
                        @{
                            EmailAddress = @{
                                Address = $recipient
                            }
                        }
                    }
                )
            }
            SaveToSentItems = "false"
        }
        
    Send-MgUserMail -UserId $mailSender -BodyParameter $params
    Write-Output "Mail has been sent."
}

if ($mailMode -eq "always" -and $mailSender -and $mailRecipients) { runbookSendMail }
elseif ($mailMode -eq "removal" -and $mailSender -and $mailRecipients -and $groupMembers) { runbookSendMail }
elseif ($mailMode -eq "removal" -and $mailSender -and $mailRecipients) { Write-Output "No mail sent, because there are no members in the group to handel and mailmode is set to removal." }
elseif ($mailMode -eq "disabled"){ Write-Output "Mail function is disabled." }
else { Write-Warning "Mail settings are missing or incorrect" }


#Disconnect from Microsoft Graph within Azure Automation
Disconnect-MgGraph