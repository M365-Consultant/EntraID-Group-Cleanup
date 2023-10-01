*** WORK IN PROGRESS ***

# EntraID-Group-Cleanup
This script is designed for an Azure Runbook to automatically remove users from an EntraID (AzureAD) group, based on the time of membership.
Please note that this script relies on the Audit Log to retrieve the timestamp of a user's addition to a group. As a result, the maximum timeframe available is determined by the retention period set for your Audit Log!

# Requirements
Before running the runbook, you need to set up an automation account with a managed identity.

The managed identity requires the following Graph Permissions:
   - User.Read.All
   - AuditLog.Read.All
   - Group.ReadWrite.All
   - Mail.Send

The script requires the following modules:
   - Microsoft.Graph.Authentication
   - Microsoft.Graph.Groups
   - Microsoft.Graph.Reports
   - Microsoft.Graph.Users
   - Microsoft.Graph.Users.Actions

# Parameters
There are a few parameters which must be set for a job run:
   - $groupID -> The Object-ID of a EntraID (AzureAD) group)
   - $timeCleanup -> The time in MINUTES, for how long a user should remain in the group (maximum is your Audit-Log retention!)
   - $mailMode -> This is controlling the mail behavior (enter the mode you want without ' )
      'always' - sends a mail on every run
      'removal' - sends a mail only if a user has been removed from a group
      'disabled' - never send a mail
   - $mailSender -> The mail-alias from which the mail will be send (can be a user-account or a shared-mailbox)
   - $mailRecipients -> The recpient(s) of a mail. If you want more than one recpient, you can seperate them with ;

