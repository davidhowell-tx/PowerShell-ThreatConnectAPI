<#
Author: David Howell  @DavidHowellTX
Last Modified: 05/10/2015
Version: 1

Thanks to Threat Connect for their awesome documentation on how to use the API.
#>

# Set the API Access ID, Secret Key, and Base URL for the API
# Place the values within the single quotes. If your Secret Key has a single quote in it, you may need to escape it by using the backtick before the single quote
[String]$Script:AccessID = ''
[String]$Script:SecretKey = ''
[String]$Script:APIBaseURL = 'https://api.threatconnect.com'

function Get-ThreatConnectHeaders {
	<#
	.SYNOPSIS
		Generates the HTTP headers for an API request.
		
	.DESCRIPTION
		Each API request must contain headers that include a HMAC-SHA256, Base64 encoded signature and the Unix Timestamp. This function handles creation of those headers.
		This command is intended to be used by other commands in the Threat Connect Module.  It is not intended to be used manually at the command line, unless for testing purposes.
	
	.PARAMETER RequestMethod
		The HTTP Request Method for the API request (GET, PUT, POST, DELETE)
	
	.PARAMETER URL
		The Child URL for the API Request (Exclude the root, eg. https://api.threatconnect.com should not be included)
		
	.EXAMPLE
		Get-ThreatConnectHeaders -RequestMethod "GET" -URL "/v2/owners"
	#>
	[CmdletBinding()]Param(
		[Parameter(Mandatory=$True)][String]$RequestMethod,
		[Parameter(Mandatory=$True)][String]$URL
	)
	# Calculate Unix UTC time
	[String]$Timestamp = [Math]::Floor([Decimal](Get-Date -Date (Get-Date).ToUniversalTime() -UFormat "%s"))
	# Create the HMAC-SHA256 Object to work with
	$HMACSHA256 = New-Object System.Security.Cryptography.HMACSHA256
	# Set the HMAC Key to the API Secret Key
	$HMACSHA256.Key = [System.Text.Encoding]::UTF8.GetBytes($Script:SecretKey)
	# Generate the HMAC Signature using API URI, Request Method, and Unix Time
	$HMACSignature = $HMACSHA256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes("$URL`:$RequestMethod`:$Timestamp"))
	# Base 64 Encode the HMAC Signature
	$HMACBase64 = [System.Convert]::ToBase64String($HMACSignature)
	# Craft the full Authorization Header
	$Authorization = "TC $($Script:AccessID)`:$HMACBase64"
	# Create a HashTable where we will add the Authorization information
	$Headers = New-Object System.Collections.Hashtable
	$Headers.Add("Timestamp",$Timestamp)
	$Headers.Add("Authorization",$Authorization)
	return $Headers
}

function Get-EscapedURIString {
	<#
	.SYNOPSIS
		Escapes special characters in the provided URI string (spaces become %20, etc.)
	
	.DESCRIPTION
		Uses System.URI's method "EscapeDataString" to convert special characters into their hex representation.
	
	.PARAMETER String
		The string that requires conversion
	
	.EXAMPLE
		Get-EscapedURIString -String "Test Escaping"
	#>
	
	[CmdletBinding()]Param(
		[Parameter(Mandatory=$True)][String]$String
	)
	
	# Use System.URI's "EscapeDataString" method to convert
	[System.Uri]::EscapeDataString($String)
}

function Get-TCOwners {
	<#
	.SYNOPSIS
		Gets a list of Owners visible to your API key.
	
	.DESCRIPTION
		Owners include your API Key's Organization, and any other communities to which it subscribes.
		
	.PARAMETER IndicatorType
		Optional paramter used to list all owners linked to a specific Indicator.  IndicatorType could be Host, EmailAddress, File, Address, or URL.
		Must be used along with the Indicator parameter.
		
	.PARAMETER Indicator
		Optional paramter used to list all owners linked to a specific Indicator.
		Must be used along with the IndicatorType parameter.
	
	.EXAMPLE
		Get-TCOwners
		
	.EXAMPLE
		Get-TCOwners -IndicatorType Address -Indicator <Indicator>
	
	.EXAMPLE
		Get-TCOwners -IndicatorType EmailAddress -Indicator <Indicator>
	
	.EXAMPLE
		Get-TCOwners -IndicatorType File -Indicator <Indicator>
	
	.EXAMPLE
		Get-TCOwners -IndicatorType Host -Indicator <Indicator>
	
	.EXAMPLE
		Get-TCOwners -IndicatorType URL -Indicator <Indicator>
	#>
	
	[CmdletBinding(DefaultParameterSetName='Default')]Param(
		[Parameter(Mandatory=$True,ParameterSetName='Indicator')]
			[ValidateSet('Address','EmailAddress','File','Host','URL')][String]$IndicatorType,
		[Parameter(Mandatory=$True,ParameterSetName='Indicator')]
			[ValidateNotNullOrEmpty()][String]$Indicator
	)
	
	# Construct the Child URL based on the Parameter Set that was chosen
	switch ($PSCmdlet.ParameterSetName) {
		"Indicator" {
			# Craft Indicator Child URL based on Indicator Type
			switch ($IndicatorType) {
				"Address" {
					$APIChildURL = "/v2/indicators/addresses/" + $Indicator + "/owners"
				}
				"EmailAddress" {
					$APIChildURL = "/v2/indicators/emailAddresses/" + $Indicator + "/owners"
				}
				"File" {
					$APIChildURL = "/v2/indicators/files/" + $Indicator + "/owners"
				}
				"Host" {
					$APIChildURL = "/v2/indicators/hosts/" + $Indicator + "/owners"
				}
				"URL" {
					# URLs need to be converted to a friendly format first
					$Indicator = Get-EscapedURIString -String $Indicator
					$APIChildURL = "/v2/indicators/urls/" + $Indicator + "/owners"
				}
			}
		}
		
		"Default" {
			$APIChildURL = "/v2/owners"
		}
	}
	
	# Generate the appropriate Headers for the API Request
	$AuthorizationHeaders = Get-ThreatConnectHeaders -RequestMethod "GET" -URL $APIChildURL
	
	# Create the URI using System.URI (This fixes the issues with URL encoding)
	$URI = New-Object System.Uri ($Script:APIBaseURL + $APIChildURL)
	if ($IndicatorType -eq "URL" -and $Indicator) { [URLFix]::ForceCanonicalPathAndQuery($URI) }
	
	# Query the API
	$Response = Invoke-RestMethod -Method "GET" -Uri $URI -Headers $AuthorizationHeaders -ErrorAction SilentlyContinue
	
	# Verify API Request Status as Success or Print the Error
	if ($Response.Status -eq "Success") {
		$Response.data | Get-Member -MemberType NoteProperty | Where-Object { $_.Name -ne "resultCount" } | Select-Object -ExpandProperty Name | ForEach-Object { $Response.data.$_ }
	} else {
		Write-Verbose "API Request failed with the following error:`n $($Response.Status)"
	}
}

function Get-TCAdversaries {
	<#
	.SYNOPSIS
		Gets a list of Adversaries from Threat Connect.  Default is all Adversaries for the API Key's organization
	
	.PARAMETER AdversaryID
		Optional Parameter to specify an Adversary ID for which to query.
		
	.PARAMETER EmailID
		Optional parameter used to list all Adversaries linked to a specific Email ID.
		
	.PARAMETER IncidentID
		Optional parameter used to list all Adversaries linked to a specific Incident ID.
		
	.PARAMETER SecurityLabel
		Optional parameter used to list all Adversaries with a specific Security Label.
		
	.PARAMETER SignatureID
		Optional parameter used to list all Adversaries linked to a specific Signature ID.
	
	.PARAMETER TagName
		Optional parameter used to list all Adversaries with a specific Tag.
	
	.PARAMETER ThreatID
		Optional parameter used to list all Adversaries linked to a specific Threat ID.
	
	.PARAMETER VictimID
		Optional parameter used to list all Adversaries linked to a specific Victim ID.
		
	.PARAMETER IndicatorType
		Optional paramter used to list all Adversaries linked to a specific Indicator.  IndicatorType could be Host, EmailAddress, File, Address, or URL.
		Must be used along with the Indicator parameter.
		
	.PARAMETER Indicator
		Optional paramter used to list all Adversaries linked to a specific Indicator.
		Must be used along with the IndicatorType parameter.
	
	.PARAMETER Owner
		Optional Parameter to define a specific Community (or other "Owner") from which to retrieve adversaries.
		This switch can be used alongside some of the other switches.
	
	.PARAMETER ResultStart
		Optional Parameter. Use when dealing with large number of results.
		If you use ResultLimit of 100, you can use a ResultStart value of 100 to show items 100 through 200.
	
	.PARAMETER ResultLimit
		Optional Parameter. Change the maximum number of results to display. Default is 100, Maximum is 500.
		
	.EXAMPLE
		Get-TCAdversaries
		
	.EXAMPLE
		Get-TCAdversaries -AdversaryID <AdversaryID>
		
	.EXAMPLE
		Get-TCAdversaries -EmailID <EmailID>
		
	.EXAMPLE
		Get-TCAdversaries -IncidentID <IncidentID>
	
	.EXAMPLE
		Get-TCAdversaries -SecurityLabel <SecurityLabel>
		
	.EXAMPLE
		Get-TCAdversaries -SignatureID <SignatureID>
		
	.EXAMPLE
		Get-TCAdversaries -TagName <TagName>
		
	.EXAMPLE
		Get-TCAdversaries -ThreatID <ThreatID>
		
	.EXAMPLE
		Get-TCAdversaries -VictimID <VictimID>
		
	.EXAMPLE
		Get-TCAdversaries -IndicatorType Address -Indicator <Indicator>
	
	.EXAMPLE
		Get-TCAdversaries -IndicatorType EmailAddress -Indicator <Indicator>
	
	.EXAMPLE
		Get-TCAdversaries -IndicatorType File -Indicator <Indicator>
	
	.EXAMPLE
		Get-TCAdversaries -IndicatorType Host -Indicator <Indicator>
	
	.EXAMPLE
		Get-TCAdversaries -IndicatorType URL -Indicator <Indicator>
	#>
	[CmdletBinding(DefaultParameterSetName='Default')]Param(
		[Parameter(Mandatory=$True,ParameterSetName='AdversaryID')]
			[ValidateNotNullOrEmpty()][String]$AdversaryID,
		[Parameter(Mandatory=$True,ParameterSetName='EmailID')]
			[ValidateNotNullOrEmpty()][String]$EmailID,
		[Parameter(Mandatory=$True,ParameterSetName='IncidentID')]
			[ValidateNotNullOrEmpty()][String]$IncidentID,
		[Parameter(Mandatory=$True,ParameterSetName='Indicator')]
			[ValidateSet('Address','EmailAddress','File','Host','URL')][String]$IndicatorType,
		[Parameter(Mandatory=$True,ParameterSetName='Indicator')]
			[ValidateNotNullOrEmpty()][String]$Indicator,
		[Parameter(Mandatory=$True,ParameterSetName='SecurityLabel')]
			[ValidateNotNullOrEmpty()][String]$SecurityLabel,
		[Parameter(Mandatory=$True,ParameterSetName='SignatureID')]
			[ValidateNotNullOrEmpty()][String]$SignatureID,
		[Parameter(Mandatory=$True,ParameterSetName='TagName')]
			[ValidateNotNullOrEmpty()][String]$TagName,
		[Parameter(Mandatory=$True,ParameterSetName='ThreatID')]
			[ValidateNotNullOrEmpty()][String]$ThreatID,
		[Parameter(Mandatory=$True,ParameterSetName='VictimID')]
			[ValidateNotNullOrEmpty()][String]$VictimID,
		[Parameter(Mandatory=$False,ParameterSetName='Default')]
		[Parameter(Mandatory=$False,ParameterSetName='Indicator')]
		[Parameter(Mandatory=$False,ParameterSetName='SecurityLabel')]
		[Parameter(Mandatory=$False,ParameterSetName='TagName')]
			[ValidateNotNullOrEmpty()][String]$Owner,
		[Parameter(Mandatory=$False,ParameterSetName='Default')]
		[Parameter(Mandatory=$False,ParameterSetName='Indicator')]
		[Parameter(Mandatory=$False,ParameterSetName='EmailID')]
		[Parameter(Mandatory=$False,ParameterSetName='IncidentID')]
		[Parameter(Mandatory=$False,ParameterSetName='SecurityLabel')]
		[Parameter(Mandatory=$False,ParameterSetName='SignatureID')]
		[Parameter(Mandatory=$False,ParameterSetName='TagName')]
		[Parameter(Mandatory=$False,ParameterSetName='ThreatID')]
		[Parameter(Mandatory=$False,ParameterSetName='VictimID')]
			[ValidateRange('1','500')][int]$ResultLimit=100,
		[Parameter(Mandatory=$False,ParameterSetName='Default')]
		[Parameter(Mandatory=$False,ParameterSetName='Indicator')]
		[Parameter(Mandatory=$False,ParameterSetName='EmailID')]
		[Parameter(Mandatory=$False,ParameterSetName='IncidentID')]
		[Parameter(Mandatory=$False,ParameterSetName='SecurityLabel')]
		[Parameter(Mandatory=$False,ParameterSetName='SignatureID')]
		[Parameter(Mandatory=$False,ParameterSetName='TagName')]
		[Parameter(Mandatory=$False,ParameterSetName='ThreatID')]
		[Parameter(Mandatory=$False,ParameterSetName='VictimID')]
			[ValidateNotNullOrEmpty()][int]$ResultStart
	)
	
	# Construct the Child URL based on the Parameter Set that was chosen
	switch ($PSCmdlet.ParameterSetName) {
		"AdversaryID" {
			$APIChildURL = "/v2/groups/adversaries/" + $AdversaryID
		}
		
		"EmailID" {
			$APIChildURL = "/v2/groups/emails/" + $EmailID + "/groups/adversaries"
		}
		
		"IncidentID" {
			$APIChildURL = "/v2/groups/incidents/" + $IncidentID + "/groups/adversaries"
		}
		
		"Indicator" {
			# Craft Indicator Child URL based on Indicator Type
			switch ($IndicatorType) {
				"Address" {
					$APIChildURL = "/v2/indicators/addresses/" + $Indicator + "/groups/adversaries"
				}
				"EmailAddress" {
					$APIChildURL = "/v2/indicators/emailAddresses/" + $Indicator + "/groups/adversaries"
				}
				"File" {
					$APIChildURL = "/v2/indicators/files/" + $Indicator + "/groups/adversaries"
				}
				"Host" {
					$APIChildURL = "/v2/indicators/hosts/" + $Indicator + "/groups/adversaries"
				}
				"URL" {
					# URLs need to be converted to a friendly format first
					$Indicator = Get-EscapedURIString -String $Indicator
					$APIChildURL = "/v2/indicators/urls/" + $Indicator + "/groups/adversaries"
				}
			}
		}

		"SecurityLabel" {
			# Need to escape the URI in case there are any spaces or special characters
			$SecurityLabel = Get-EscapedURIString -String $SecurityLabel
			$APIChildURL = "/v2/securityLabels/" + $SecurityLabel + "/groups/adversaries"
		}
		
		"SignatureID" {
			$APIChildURL = "/v2/groups/signatures/" + $SignatureID + "/groups/adversaries"
		}
		
		"TagName" {
			# Need to escape the URI in case there are any spaces or special characters
			$TagName = Get-EscapedURIString -String $TagName
			$APIChildURL = "/v2/tags/" + $TagName + "/groups/adversaries"		
		}
		
		"ThreatID" {
			$APIChildURL = "/v2/groups/threats/" + $ThreatID + "/groups/adversaries"
		}
		
		"VictimID" {
			$APIChildURL = "/v2/victims/" + $VictimID + "/groups/adversaries"
		}
		
		Default {
			# Use this if nothing else is specified
			$APIChildURL ="/v2/groups/adversaries"
		}
	}
	
	# Add to the URI if Owner, ResultStart, or ResultLimit was specified
	if ($Owner -and $ResultStart -and $ResultLimit -ne 100) {
		$APIChildURL = $APIChildURL + "?owner=" + (Get-EscapedURIString -String $Owner) + "&resultStart=" + $ResultStart + "&resultLimit=" + $ResultLimit
	} elseif ($Owner -and $ResultStart -and $ResultLimit -eq 100) {
		$APIChildURL = $APIChildURL + "?owner=" + (Get-EscapedURIString -String $Owner) + "&resultStart=" + $ResultStart
	} elseif ($Owner -and (-not $ResultStart) -and $ResultLimit -ne 100) {
		$APIChildURL = $APIChildURL + "?owner=" + (Get-EscapedURIString -String $Owner) + "&resultLimit=" + $ResultLimit
	} elseif ($Owner -and (-not $ResultStart) -and $ResultLimit -eq 100) {
		$APIChildURL = $APIChildURL + "?owner=" + (Get-EscapedURIString -String $Owner)
	} elseif ((-not $Owner) -and $ResultStart -and $ResultLimit -ne 100) {
		$APIChildURL = $APIChildURL + "?resultStart=" + $ResultStart + "&resultLimit=" + $ResultLimit
	} elseif ((-not $Owner) -and $ResultStart -and $ResultLimit -eq 100) {
		$APIChildURL = $APIChildURL + "?resultStart=" + $ResultStart
	} elseif ((-not $Owner) -and (-not $ResultStart) -and $ResultLimit -ne 100) {
		$APIChildURL = $APIChildURL + "?resultLimit=" + $ResultLimit
	}
	
	# Generate the appropriate Headers for the API Request
	$AuthorizationHeaders = Get-ThreatConnectHeaders -RequestMethod "GET" -URL $APIChildURL

	# Create the URI using System.URI (This fixes the issues with URL encoding)
	$URI = New-Object System.Uri ($Script:APIBaseURL + $APIChildURL)
	
	if ($IndicatorType -eq "URL" -and $Indicator) { [URLFix]::ForceCanonicalPathAndQuery($URI) }
	
	# Query the API
	$Response = Invoke-RestMethod -Method "GET" -Uri $URI -Headers $AuthorizationHeaders -ErrorAction SilentlyContinue
	
	# Verify API Request Status as Success or Print the Error
	if ($Response.Status -eq "Success") {
		$Response.data | Get-Member -MemberType NoteProperty | Where-Object { $_.Name -ne "resultCount" } | Select-Object -ExpandProperty Name | ForEach-Object { $Response.data.$_ }
	} else {
		Write-Verbose "API Request failed with the following error:`n $($Response.Status)"
	}
}

function Get-TCEmails {
	<#
	.SYNOPSIS
		Gets a list of emails from Threat Connect.  Default is all emails for the API Key's organization
	
	.PARAMETER AdversaryID
		Optional parameter used to list all emails linked to a specific Adversary ID.
		
	.PARAMETER EmailID
		Optional parameter used to specify an Email ID for which to query.
		
	.PARAMETER IncidentID
		Optional parameter used to list all emails linked to a specific Incident ID.
		
	.PARAMETER SecurityLabel
		Optional parameter used to list all emails with a specific Security Label.
		
	.PARAMETER SignatureID
		Optional parameter used to list all emails linked to a specific Signature ID.
	
	.PARAMETER TagName
		Optional parameter used to list all emails with a specific Tag.
	
	.PARAMETER ThreatID
		Optional parameter used to list all emails linked to a specific Threat ID.
	
	.PARAMETER VictimID
		Optional parameter used to list all emails linked to a specific Victim ID.
	
	.PARAMETER IndicatorType
		Optional paramter used to list all emails linked to a specific Indicator.  IndicatorType could be Host, EmailAddress, File, Address, or URL.
		Must be used along with the Indicator parameter.
		
	.PARAMETER Indicator
		Optional paramter used to list all emails linked to a specific Indicator.
		Must be used along with the IndicatorType parameter.
	
	.PARAMETER Owner
		Optional Parameter to define a specific Community (or other "Owner") from which to retrieve emails.
		This switch can be used alongside some of the other switches.
	
	.PARAMETER ResultStart
		Optional Parameter. Use when dealing with large number of results.
		If you use ResultLimit of 100, you can use a ResultStart value of 100 to show items 100 through 200.
	
	.PARAMETER ResultLimit
		Optional Parameter. Change the maximum number of results to display. Default is 100, Maximum is 500.

	.EXAMPLE
		Get-TCEmails
		
		This gives you a list of Emails for your default organization, but only includes basic information (Name, Email ID)
		
	.EXAMPLE
		Get-TCEmails -AdversaryID <AdversaryID>
		
	.EXAMPLE
		Get-TCEmails -EmailID <EmailID>
		
	.EXAMPLE
		Get-TCEmails -IncidentID <IncidentID>
	
	.EXAMPLE
		Get-TCEmails -SecurityLabel <SecurityLabel>
		
	.EXAMPLE
		Get-TCEmails -SignatureID <SignatureID>
		
	.EXAMPLE
		Get-TCEmails -TagName <TagName>
		
	.EXAMPLE
		Get-TCEmails -ThreatID <ThreatID>
		
	.EXAMPLE
		Get-TCEmails -VictimID <VictimID>
	
	.EXAMPLE
		Get-TCEmails -IndicatorType Address -Indicator <Indicator>
	
	.EXAMPLE
		Get-TCEmails -IndicatorType EmailAddress -Indicator <Indicator>
	
	.EXAMPLE
		Get-TCEmails -IndicatorType File -Indicator <Indicator>
	
	.EXAMPLE
		Get-TCEmails -IndicatorType Host -Indicator <Indicator>
	
	.EXAMPLE
		Get-TCEmails -IndicatorType URL -Indicator <Indicator>
	#>
	[CmdletBinding(DefaultParameterSetName='Default')]Param(
		[Parameter(Mandatory=$True,ParameterSetName='AdversaryID')]
			[ValidateNotNullOrEmpty()][String]$AdversaryID,
		[Parameter(Mandatory=$True,ParameterSetName='EmailID')]
			[ValidateNotNullOrEmpty()][String]$EmailID,
		[Parameter(Mandatory=$True,ParameterSetName='IncidentID')]
			[ValidateNotNullOrEmpty()][String]$IncidentID,
		[Parameter(Mandatory=$True,ParameterSetName='Indicator')]
			[ValidateSet('Address','EmailAddress','File','Host','URL')][String]$IndicatorType,
		[Parameter(Mandatory=$True,ParameterSetName='Indicator')]
			[ValidateNotNullOrEmpty()][String]$Indicator,
		[Parameter(Mandatory=$True,ParameterSetName='SecurityLabel')]
			[ValidateNotNullOrEmpty()][String]$SecurityLabel,
		[Parameter(Mandatory=$True,ParameterSetName='SignatureID')]
			[ValidateNotNullOrEmpty()][String]$SignatureID,
		[Parameter(Mandatory=$True,ParameterSetName='TagName')]
			[ValidateNotNullOrEmpty()][String]$TagName,
		[Parameter(Mandatory=$True,ParameterSetName='ThreatID')]
			[ValidateNotNullOrEmpty()][String]$ThreatID,
		[Parameter(Mandatory=$True,ParameterSetName='VictimID')]
			[ValidateNotNullOrEmpty()][String]$VictimID,
		[Parameter(Mandatory=$False,ParameterSetName='Default')]
		[Parameter(Mandatory=$False,ParameterSetName='Indicator')]
		[Parameter(Mandatory=$False,ParameterSetName='SecurityLabel')]
		[Parameter(Mandatory=$False,ParameterSetName='TagName')]
			[ValidateNotNullOrEmpty()][String]$Owner,
		[Parameter(Mandatory=$False,ParameterSetName='Default')]
		[Parameter(Mandatory=$False,ParameterSetName='Indicator')]
		[Parameter(Mandatory=$False,ParameterSetName='AdversaryID')]
		[Parameter(Mandatory=$False,ParameterSetName='IncidentID')]
		[Parameter(Mandatory=$False,ParameterSetName='SecurityLabel')]
		[Parameter(Mandatory=$False,ParameterSetName='SignatureID')]
		[Parameter(Mandatory=$False,ParameterSetName='TagName')]
		[Parameter(Mandatory=$False,ParameterSetName='ThreatID')]
		[Parameter(Mandatory=$False,ParameterSetName='VictimID')]
			[ValidateRange('1','500')][int]$ResultLimit=100,
		[Parameter(Mandatory=$False,ParameterSetName='Default')]
		[Parameter(Mandatory=$False,ParameterSetName='Indicator')]
		[Parameter(Mandatory=$False,ParameterSetName='AdversaryID')]
		[Parameter(Mandatory=$False,ParameterSetName='IncidentID')]
		[Parameter(Mandatory=$False,ParameterSetName='SecurityLabel')]
		[Parameter(Mandatory=$False,ParameterSetName='SignatureID')]
		[Parameter(Mandatory=$False,ParameterSetName='TagName')]
		[Parameter(Mandatory=$False,ParameterSetName='ThreatID')]
		[Parameter(Mandatory=$False,ParameterSetName='VictimID')]
			[ValidateNotNullOrEmpty()][int]$ResultStart
	)
	
	# Construct the Child URL based on the Parameter Set that was chosen
	switch ($PSCmdlet.ParameterSetName) {
		"AdversaryID" {
			$APIChildURL = "/v2/groups/adversaries/" + $AdversaryID + "/groups/emails"
		}
		
		"EmailID" {
			$APIChildURL = "/v2/groups/emails/" + $EmailID
		}
		
		"IncidentID" {
			$APIChildURL = "/v2/groups/incidents/" + $IncidentID + "/groups/emails"
		}
		
		"Indicator" {
			# Craft Indicator Child URL based on Indicator Type
			switch ($IndicatorType) {
				"Address" {
					$APIChildURL = "/v2/indicators/addresses/" + $Indicator + "/groups/emails"
				}
				"EmailAddress" {
					$APIChildURL = "/v2/indicators/emailAddresses/" + $Indicator + "/groups/emails"
				}
				"File" {
					$APIChildURL = "/v2/indicators/files/" + $Indicator + "/groups/emails"
				}
				"Host" {
					$APIChildURL = "/v2/indicators/hosts/" + $Indicator + "/groups/emails"
				}
				"URL" {
					# URLs need to be converted to a friendly format first
					$Indicator = Get-EscapedURIString -String $Indicator
					$APIChildURL = "/v2/indicators/urls/" + $Indicator + "/groups/emails"
				}
			}
		}
		
		"SecurityLabel" {
			# Need to escape the URI in case there are any spaces or special characters
			$SecurityLabel = Get-EscapedURIString -String $SecurityLabel
			$APIChildURL = "/v2/securityLabels/" + $SecurityLabel + "/groups/emails"
		}
		
		"SignatureID" {
			$APIChildURL = "/v2/groups/signatures/" + $SignatureID + "/groups/emails"
		}
		
		"TagName" {
			# Need to escape the URI in case there are any spaces or special characters
			$TagName = Get-EscapedURIString -String $TagName
			$APIChildURL = "/v2/tags/" + $TagName + "/groups/emails"		
		}		
		
		"ThreatID" {
			$APIChildURL = "/v2/groups/threats/" + $ThreatID + "/groups/emails"
		}

		"VictimID" {
			$APIChildURL = "/v2/victims/" + $VictimID + "/groups/emails"
		}
		
		Default {
			# Use this if nothing else is specified
			$APIChildURL ="/v2/groups/emails"
		}
	}

	# Add to the URI if Owner, ResultStart, or ResultLimit was specified
	if ($Owner -and $ResultStart -and $ResultLimit -ne 100) {
		$APIChildURL = $APIChildURL + "?owner=" + (Get-EscapedURIString -String $Owner) + "&resultStart=" + $ResultStart + "&resultLimit=" + $ResultLimit
	} elseif ($Owner -and $ResultStart -and $ResultLimit -eq 100) {
		$APIChildURL = $APIChildURL + "?owner=" + (Get-EscapedURIString -String $Owner) + "&resultStart=" + $ResultStart
	} elseif ($Owner -and (-not $ResultStart) -and $ResultLimit -ne 100) {
		$APIChildURL = $APIChildURL + "?owner=" + (Get-EscapedURIString -String $Owner) + "&resultLimit=" + $ResultLimit
	} elseif ($Owner -and (-not $ResultStart) -and $ResultLimit -eq 100) {
		$APIChildURL = $APIChildURL + "?owner=" + (Get-EscapedURIString -String $Owner)
	} elseif ((-not $Owner) -and $ResultStart -and $ResultLimit -ne 100) {
		$APIChildURL = $APIChildURL + "?resultStart=" + $ResultStart + "&resultLimit=" + $ResultLimit
	} elseif ((-not $Owner) -and $ResultStart -and $ResultLimit -eq 100) {
		$APIChildURL = $APIChildURL + "?resultStart=" + $ResultStart
	} elseif ((-not $Owner) -and (-not $ResultStart) -and $ResultLimit -ne 100) {
		$APIChildURL = $APIChildURL + "?resultLimit=" + $ResultLimit
	}
	
	# Generate the appropriate Headers for the API Request
	$AuthorizationHeaders = Get-ThreatConnectHeaders -RequestMethod "GET" -URL $APIChildURL
	
	# Create the URI using System.URI (This fixes the issues with URL encoding)
	$URI = New-Object System.Uri ($Script:APIBaseURL + $APIChildURL)
	
	if ($IndicatorType -eq "URL" -and $Indicator) { [URLFix]::ForceCanonicalPathAndQuery($URI) }
	
	# Query the API
	$Response = Invoke-RestMethod -Method "GET" -Uri $URI -Headers $AuthorizationHeaders -ErrorAction SilentlyContinue
	
	# Verify API Request Status as Success or Print the Error
	if ($Response.Status -eq "Success") {
		$Response.data | Get-Member -MemberType NoteProperty | Where-Object { $_.Name -ne "resultCount" } | Select-Object -ExpandProperty Name | ForEach-Object { $Response.data.$_ }
	} else {
		Write-Verbose "API Request failed with the following error:`n $($Response.Status)"
	}
}

function Get-TCGroups {
	<#
	.SYNOPSIS
		Gets a list of Groups from Threat Connect.  Default is all Groups for the API Key's organization
	
	.PARAMETER AdversaryID
		Optional parameter use to list all groups linked to a specific Adversary ID.
		
	.PARAMETER EmailID
		Optional parameter used to list all groups linked to a specific Email ID.
		
	.PARAMETER IncidentID
		Optional parameter used to list all groups linked to a specific Incident ID.
		
	.PARAMETER SecurityLabel
		Optional parameter used to list all groups with a specific Security Label.
		
	.PARAMETER SignatureID
		Optional parameter used to list all groups linked to a specific Signature ID.
	
	.PARAMETER TagName
		Optional parameter used to list all groups with a specific Tag.
	
	.PARAMETER ThreatID
		Optional parameter used to list all groups linked to a specific Threat ID.
	
	.PARAMETER VictimID
		Optional parameter used to list all groups linked to a specific Victim ID.
		
	.PARAMETER IndicatorType
		Optional paramter used to list all groups linked to a specific Indicator.  IndicatorType could be Host, EmailAddress, File, Address, or URL.
		Must be used along with the Indicator parameter.
		
	.PARAMETER Indicator
		Optional paramter used to list all groups linked to a specific Indicator.
		Must be used along with the IndicatorType parameter.
	
	.PARAMETER Owner
		Optional Parameter to define a specific Community (or other "Owner") from which to retrieve groups.
		This switch can be used alongside some of the other switches.
	
	.PARAMETER ResultStart
		Optional Parameter. Use when dealing with large number of results.
		If you use ResultLimit of 100, you can use a ResultStart value of 100 to show items 100 through 200.
	
	.PARAMETER ResultLimit
		Optional Parameter. Change the maximum number of results to display. Default is 100, Maximum is 500.

	.EXAMPLE
		Get-TCGroups
		
	.EXAMPLE
		Get-TCGroups -AdversaryID <AdversaryID>
		
	.EXAMPLE
		Get-TCGroups -EmailID <EmailID>
		
	.EXAMPLE
		Get-TCGroups -IncidentID <IncidentID>
	
	.EXAMPLE
		Get-TCGroups -SecurityLabel <SecurityLabel>
		
	.EXAMPLE
		Get-TCGroups -SignatureID <SignatureID>
		
	.EXAMPLE
		Get-TCGroups -TagName <TagName>
		
	.EXAMPLE
		Get-TCGroups -ThreatID <ThreatID>
		
	.EXAMPLE
		Get-TCGroups -VictimID <VictimID>
	
	.EXAMPLE
		Get-TCGroups -IndicatorType Address -Indicator <Indicator>
	
	.EXAMPLE
		Get-TCGroups -IndicatorType EmailAddress -Indicator <Indicator>
	
	.EXAMPLE
		Get-TCGroups -IndicatorType File -Indicator <Indicator>
	
	.EXAMPLE
		Get-TCGroups -IndicatorType Host -Indicator <Indicator>
	
	.EXAMPLE
		Get-TCGroups -IndicatorType URL -Indicator <Indicator>
	#>
	[CmdletBinding(DefaultParameterSetName='Default')]Param(
		[Parameter(Mandatory=$True,ParameterSetName='AdversaryID')]
			[ValidateNotNullOrEmpty()][String]$AdversaryID,
		[Parameter(Mandatory=$True,ParameterSetName='EmailID')]
			[ValidateNotNullOrEmpty()][String]$EmailID,
		[Parameter(Mandatory=$True,ParameterSetName='IncidentID')]
			[ValidateNotNullOrEmpty()][String]$IncidentID,
		[Parameter(Mandatory=$True,ParameterSetName='Indicator')]
			[ValidateSet('Address','EmailAddress','File','Host','URL')][String]$IndicatorType,
		[Parameter(Mandatory=$True,ParameterSetName='Indicator')]
			[ValidateNotNullOrEmpty()][String]$Indicator,
		[Parameter(Mandatory=$True,ParameterSetName='SecurityLabel')]
			[ValidateNotNullOrEmpty()][String]$SecurityLabel,
		[Parameter(Mandatory=$True,ParameterSetName='SignatureID')]
			[ValidateNotNullOrEmpty()][String]$SignatureID,
		[Parameter(Mandatory=$True,ParameterSetName='TagName')]
			[ValidateNotNullOrEmpty()][String]$TagName,
		[Parameter(Mandatory=$True,ParameterSetName='ThreatID')]
			[ValidateNotNullOrEmpty()][String]$ThreatID,
		[Parameter(Mandatory=$True,ParameterSetName='VictimID')]
			[ValidateNotNullOrEmpty()][String]$VictimID,
		[Parameter(Mandatory=$False,ParameterSetName='Default')]
		[Parameter(Mandatory=$False,ParameterSetName='Indicator')]
		[Parameter(Mandatory=$False,ParameterSetName='SecurityLabel')]
		[Parameter(Mandatory=$False,ParameterSetName='TagName')]
			[ValidateNotNullOrEmpty()][String]$Owner,
		[Parameter(Mandatory=$False)][ValidateRange('1','500')][int]$ResultLimit=100,
		[Parameter(Mandatory=$False)][ValidateNotNullOrEmpty()][int]$ResultStart
	)
	
	# Construct the Child URL based on the Parameter Set that was chosen
	switch ($PSCmdlet.ParameterSetName) {
		"AdversaryID" {
			$APIChildURL = "/v2/groups/adversaries/" + $AdversaryID + "/groups"
		}
		
		"EmailID" {
			$APIChildURL = "/v2/groups/emails/" + $EmailID + "/groups"
		}
		
		"IncidentID" {
			$APIChildURL = "/v2/groups/incidents/" + $IncidentID + "/groups"
		}
		
		"Indicator" {
			# Craft Indicator Child URL based on Indicator Type
			switch ($IndicatorType) {
				"Address" {
					$APIChildURL = "/v2/indicators/addresses/" + $Indicator + "/groups"
				}
				"EmailAddress" {
					$APIChildURL = "/v2/indicators/emailAddresses/" + $Indicator + "/groups"
				}
				"File" {
					$APIChildURL = "/v2/indicators/files/" + $Indicator + "/groups"
				}
				"Host" {
					$APIChildURL = "/v2/indicators/hosts/" + $Indicator + "/groups"
				}
				"URL" {
					# URLs need to be converted to a friendly format first
					$Indicator = Get-EscapedURIString -String $Indicator
					$APIChildURL = "/v2/indicators/urls/" + $Indicator + "/groups"
				}
			}
		}

		"SecurityLabel" {
			# Need to escape the URI in case there are any spaces or special characters
			$SecurityLabel = Get-EscapedURIString -String $SecurityLabel
			$APIChildURL = "/v2/securityLabels/" + $SecurityLabel + "/groups"
		}
		
		"SignatureID" {
			$APIChildURL = "/v2/groups/signatures/" + $SignatureID + "/groups"
		}
		
		"TagName" {
			# Need to escape the URI in case there are any spaces or special characters
			$TagName = Get-EscapedURIString -String $TagName
			$APIChildURL = "/v2/tags/" + $TagName + "/groups"		
		}
		
		"ThreatID" {
			$APIChildURL = "/v2/groups/threats/" + $ThreatID + "/groups"
		}
		
		"VictimID" {
			$APIChildURL = "/v2/victims/" + $VictimID + "/groups"
		}
		
		Default {
			# Use this if nothing else is specified
			$APIChildURL ="/v2/groups"
		}
	}

	# Add to the URI if Owner, ResultStart, or ResultLimit was specified
	if ($Owner -and $ResultStart -and $ResultLimit -ne 100) {
		$APIChildURL = $APIChildURL + "?owner=" + (Get-EscapedURIString -String $Owner) + "&resultStart=" + $ResultStart + "&resultLimit=" + $ResultLimit
	} elseif ($Owner -and $ResultStart -and $ResultLimit -eq 100) {
		$APIChildURL = $APIChildURL + "?owner=" + (Get-EscapedURIString -String $Owner) + "&resultStart=" + $ResultStart
	} elseif ($Owner -and (-not $ResultStart) -and $ResultLimit -ne 100) {
		$APIChildURL = $APIChildURL + "?owner=" + (Get-EscapedURIString -String $Owner) + "&resultLimit=" + $ResultLimit
	} elseif ($Owner -and (-not $ResultStart) -and $ResultLimit -eq 100) {
		$APIChildURL = $APIChildURL + "?owner=" + (Get-EscapedURIString -String $Owner)
	} elseif ((-not $Owner) -and $ResultStart -and $ResultLimit -ne 100) {
		$APIChildURL = $APIChildURL + "?resultStart=" + $ResultStart + "&resultLimit=" + $ResultLimit
	} elseif ((-not $Owner) -and $ResultStart -and $ResultLimit -eq 100) {
		$APIChildURL = $APIChildURL + "?resultStart=" + $ResultStart
	} elseif ((-not $Owner) -and (-not $ResultStart) -and $ResultLimit -ne 100) {
		$APIChildURL = $APIChildURL + "?resultLimit=" + $ResultLimit
	}
	
	# Generate the appropriate Headers for the API Request
	$AuthorizationHeaders = Get-ThreatConnectHeaders -RequestMethod "GET" -URL $APIChildURL
	
	# Create the URI using System.URI (This fixes the issues with URL encoding)
	$URI = New-Object System.Uri ($Script:APIBaseURL + $APIChildURL)
	
	if ($IndicatorType -eq "URL" -and $Indicator) { [URLFix]::ForceCanonicalPathAndQuery($URI) }
	
	# Query the API
	$Response = Invoke-RestMethod -Method "GET" -Uri $URI -Headers $AuthorizationHeaders -ErrorAction SilentlyContinue
	
	# Verify API Request Status as Success or Print the Error
	if ($Response.Status -eq "Success") {
		$Response.data | Get-Member -MemberType NoteProperty | Where-Object { $_.Name -ne "resultCount" } | Select-Object -ExpandProperty Name | ForEach-Object { $Response.data.$_ }
	} else {
		Write-Verbose "API Request failed with the following error:`n $($Response.Status)"
	}
}

function Get-TCIncidents {
	<#
	.SYNOPSIS
		Gets a list of incidents from Threat Connect.  Default is all incidents for the API Key's organization
	
	.PARAMETER AdversaryID
		Optional parameter used to list all incidents linked to a specific Adversary ID.
		
	.PARAMETER EmailID
		Optional parameter used to list all incidents linked to a specific Email ID.
		
	.PARAMETER IncidentID
		Optional parameter used to specify an Incident ID for which to query.
		
	.PARAMETER SecurityLabel
		Optional parameter used to list all incidents with a specific Security Label.
		
	.PARAMETER SignatureID
		Optional parameter used to list all incidents linked to a specific Signature ID.
	
	.PARAMETER TagName
		Optional parameter used to list all incidents with a specific Tag.
	
	.PARAMETER ThreatID
		Optional parameter used to list all incidents linked to a specific Threat ID.
	
	.PARAMETER VictimID
		Optional parameter used to list all incidents linked to a specific Victim ID.
		
	.PARAMETER IndicatorType
		Optional paramter used to list all incidents linked to a specific Indicator.  IndicatorType could be Host, EmailAddress, File, Address, or URL.
		Must be used along with the Indicator parameter.
		
	.PARAMETER Indicator
		Optional paramter used to list all incidents linked to a specific Indicator.
		Must be used along with the IndicatorType parameter.
	
	.PARAMETER Owner
		Optional Parameter to define a specific Community (or other "Owner") from which to retrieve incidents.
		This switch can be used alongside some of the other switches.
	
	.PARAMETER ResultStart
		Optional Parameter. Use when dealing with large number of results.
		If you use ResultLimit of 100, you can use a ResultStart value of 100 to show items 100 through 200.
	
	.PARAMETER ResultLimit
		Optional Parameter. Change the maximum number of results to display. Default is 100, Maximum is 500.

	.EXAMPLE
		Get-TCIncidents
		
	.EXAMPLE
		Get-TCIncidents -AdversaryID <AdversaryID>
		
	.EXAMPLE
		Get-TCIncidents -EmailID <EmailID>
		
	.EXAMPLE
		Get-TCIncidents -IncidentID <IncidentID>
	
	.EXAMPLE
		Get-TCIncidents -SecurityLabel <SecurityLabel>
		
	.EXAMPLE
		Get-TCIncidents -SignatureID <SignatureID>
		
	.EXAMPLE
		Get-TCIncidents -TagName <TagName>
		
	.EXAMPLE
		Get-TCIncidents -ThreatID <ThreatID>
		
	.EXAMPLE
		Get-TCIncidents -VictimID <VictimID>
		
	.EXAMPLE
		Get-TCIncidents -IndicatorType Address -Indicator <Indicator>
	
	.EXAMPLE
		Get-TCIncidents -IndicatorType EmailAddress -Indicator <Indicator>
	
	.EXAMPLE
		Get-TCIncidents -IndicatorType File -Indicator <Indicator>
	
	.EXAMPLE
		Get-TCIncidents -IndicatorType Host -Indicator <Indicator>
	
	.EXAMPLE
		Get-TCIncidents -IndicatorType URL -Indicator <Indicator>
	#>
	[CmdletBinding(DefaultParameterSetName='Default')]Param(
		[Parameter(Mandatory=$True,ParameterSetName='AdversaryID')]
			[ValidateNotNullOrEmpty()][String]$AdversaryID,
		[Parameter(Mandatory=$True,ParameterSetName='EmailID')]
			[ValidateNotNullOrEmpty()][String]$EmailID,
		[Parameter(Mandatory=$True,ParameterSetName='IncidentID')]
			[ValidateNotNullOrEmpty()][String]$IncidentID,
		[Parameter(Mandatory=$True,ParameterSetName='Indicator')]
			[ValidateSet('Address','EmailAddress','File','Host','URL')][String]$IndicatorType,
		[Parameter(Mandatory=$True,ParameterSetName='Indicator')]
			[ValidateNotNullOrEmpty()][String]$Indicator,
		[Parameter(Mandatory=$True,ParameterSetName='SecurityLabel')]
			[ValidateNotNullOrEmpty()][String]$SecurityLabel,
		[Parameter(Mandatory=$True,ParameterSetName='SignatureID')]
			[ValidateNotNullOrEmpty()][String]$SignatureID,
		[Parameter(Mandatory=$True,ParameterSetName='TagName')]
			[ValidateNotNullOrEmpty()][String]$TagName,
		[Parameter(Mandatory=$True,ParameterSetName='ThreatID')]
			[ValidateNotNullOrEmpty()][String]$ThreatID,
		[Parameter(Mandatory=$True,ParameterSetName='VictimID')]
			[ValidateNotNullOrEmpty()][String]$VictimID,
		[Parameter(Mandatory=$False,ParameterSetName='Default')]
		[Parameter(Mandatory=$False,ParameterSetName='Indicator')]
		[Parameter(Mandatory=$False,ParameterSetName='SecurityLabel')]
		[Parameter(Mandatory=$False,ParameterSetName='TagName')]
			[ValidateNotNullOrEmpty()][String]$Owner,
		[Parameter(Mandatory=$False,ParameterSetName='Default')]
		[Parameter(Mandatory=$False,ParameterSetName='Indicator')]
		[Parameter(Mandatory=$False,ParameterSetName='AdversaryID')]
		[Parameter(Mandatory=$False,ParameterSetName='EmailID')]
		[Parameter(Mandatory=$False,ParameterSetName='SecurityLabel')]
		[Parameter(Mandatory=$False,ParameterSetName='SignatureID')]
		[Parameter(Mandatory=$False,ParameterSetName='TagName')]
		[Parameter(Mandatory=$False,ParameterSetName='ThreatID')]
		[Parameter(Mandatory=$False,ParameterSetName='VictimID')]
			[ValidateRange('1','500')][int]$ResultLimit=100,
		[Parameter(Mandatory=$False,ParameterSetName='Default')]
		[Parameter(Mandatory=$False,ParameterSetName='Indicator')]
		[Parameter(Mandatory=$False,ParameterSetName='AdversaryID')]
		[Parameter(Mandatory=$False,ParameterSetName='EmailID')]
		[Parameter(Mandatory=$False,ParameterSetName='SecurityLabel')]
		[Parameter(Mandatory=$False,ParameterSetName='SignatureID')]
		[Parameter(Mandatory=$False,ParameterSetName='TagName')]
		[Parameter(Mandatory=$False,ParameterSetName='ThreatID')]
		[Parameter(Mandatory=$False,ParameterSetName='VictimID')]
			[ValidateNotNullOrEmpty()][int]$ResultStart
	)
	
	# Construct the Child URL based on the Parameter Set that was chosen
	switch ($PSCmdlet.ParameterSetName) {
		"AdversaryID" {
			$APIChildURL = "/v2/groups/adversaries/" + $AdversaryID + "/groups/incidents"
		}
		
		"EmailID" {
			$APIChildURL = "/v2/groups/emails/" + $EmailID + "/groups/incidents"
		}
		
		"IncidentID" {
			$APIChildURL = "/v2/groups/incidents/" + $IncidentID
		}
		
		"Indicator" {
			# Craft Indicator Child URL based on Indicator Type
			switch ($IndicatorType) {
				"Address" {
					$APIChildURL = "/v2/indicators/addresses/" + $Indicator + "/groups/incidents"
				}
				"EmailAddress" {
					$APIChildURL = "/v2/indicators/emailAddresses/" + $Indicator + "/groups/incidents"
				}
				"File" {
					$APIChildURL = "/v2/indicators/files/" + $Indicator + "/groups/incidents"
				}
				"Host" {
					$APIChildURL = "/v2/indicators/hosts/" + $Indicator + "/groups/incidents"
				}
				"URL" {
					# URLs need to be converted to a friendly format first
					$Indicator = Get-EscapedURIString -String $Indicator
					$APIChildURL = "/v2/indicators/urls/" + $Indicator + "/groups/incidents"
				}
			}
		}
		
		"SecurityLabel" {
			# Need to escape the URI in case there are any spaces or special characters
			$SecurityLabel = Get-EscapedURIString -String $SecurityLabel
			$APIChildURL = "/v2/securityLabels/" + $SecurityLabel + "/groups/incidents"
		}
		
		"SignatureID" {
			$APIChildURL = "/v2/groups/signatures/" + $SignatureID + "/groups/incidents"
		}
		
		"TagName" {
			# Need to escape the URI in case there are any spaces or special characters
			$TagName = Get-EscapedURIString -String $TagName
			$APIChildURL = "/v2/tags/" + $TagName + "/groups/incidents"		
		}
		
		"ThreatID" {
			$APIChildURL = "/v2/groups/threats/" + $ThreatID  + "/groups/incidents"
		}
		
		"VictimID" {
			$APIChildURL = "/v2/victims/" + $VictimID + "/groups/incidents"
		}
		
		Default {
			# Use this if nothing else is specified
			$APIChildURL ="/v2/groups/incidents"
		}
	}

	# Add to the URI if Owner, ResultStart, or ResultLimit was specified
	if ($Owner -and $ResultStart -and $ResultLimit -ne 100) {
		$APIChildURL = $APIChildURL + "?owner=" + (Get-EscapedURIString -String $Owner) + "&resultStart=" + $ResultStart + "&resultLimit=" + $ResultLimit
	} elseif ($Owner -and $ResultStart -and $ResultLimit -eq 100) {
		$APIChildURL = $APIChildURL + "?owner=" + (Get-EscapedURIString -String $Owner) + "&resultStart=" + $ResultStart
	} elseif ($Owner -and (-not $ResultStart) -and $ResultLimit -ne 100) {
		$APIChildURL = $APIChildURL + "?owner=" + (Get-EscapedURIString -String $Owner) + "&resultLimit=" + $ResultLimit
	} elseif ($Owner -and (-not $ResultStart) -and $ResultLimit -eq 100) {
		$APIChildURL = $APIChildURL + "?owner=" + (Get-EscapedURIString -String $Owner)
	} elseif ((-not $Owner) -and $ResultStart -and $ResultLimit -ne 100) {
		$APIChildURL = $APIChildURL + "?resultStart=" + $ResultStart + "&resultLimit=" + $ResultLimit
	} elseif ((-not $Owner) -and $ResultStart -and $ResultLimit -eq 100) {
		$APIChildURL = $APIChildURL + "?resultStart=" + $ResultStart
	} elseif ((-not $Owner) -and (-not $ResultStart) -and $ResultLimit -ne 100) {
		$APIChildURL = $APIChildURL + "?resultLimit=" + $ResultLimit
	}
	
	# Generate the appropriate Headers for the API Request
	$AuthorizationHeaders = Get-ThreatConnectHeaders -RequestMethod "GET" -URL $APIChildURL

	# Create the URI using System.URI (This fixes the issues with URL encoding)
	$URI = New-Object System.Uri ($Script:APIBaseURL + $APIChildURL)
	
	if ($IndicatorType -eq "URL" -and $Indicator) { [URLFix]::ForceCanonicalPathAndQuery($URI) }
	
	# Query the API
	$Response = Invoke-RestMethod -Method "GET" -Uri $URI -Headers $AuthorizationHeaders -ErrorAction SilentlyContinue
	
	# Verify API Request Status as Success or Print the Error
	if ($Response.Status -eq "Success") {
		$Response.data | Get-Member -MemberType NoteProperty | Where-Object { $_.Name -ne "resultCount" } | Select-Object -ExpandProperty Name | ForEach-Object { $Response.data.$_ }
	} else {
		Write-Verbose "API Request failed with the following error:`n $($Response.Status)"
	}
}

function Get-TCSignatures {
	<#
	.SYNOPSIS
		Gets a list of signatures from Threat Connect.  Default is all signatures for the API Key's organization
			
	.PARAMETER AdversaryID
		Optional parameter used to list all signatures linked to a specific Adversary ID.
		
	.PARAMETER EmailID
		Optional parameter used to list all signatures linked to a specific Email ID.
		
	.PARAMETER IncidentID
		Optional parameter used to list all signatures linked to a specific Incident ID.
		
	.PARAMETER SecurityLabel
		Optional parameter used to list all signatures with a specific Security Label.
		
	.PARAMETER SignatureID
		Optional parameter used to specify a Signature ID for which to query.
	
	.PARAMETER Download
		Optional parameter used in conjunction with SignatureID parameter that specifies to download the signature's content.
	
	.PARAMETER TagName
		Optional parameter used to list all signatures with a specific Tag.
	
	.PARAMETER ThreatID
		Optional parameter used to list all signatures linked to a specific Threat ID.
	
	.PARAMETER VictimID
		Optional parameter used to list all signatures linked to a specific Victim ID.
	
	.PARAMETER IndicatorType
		Optional paramter used to list all signatures linked to a specific Indicator.  IndicatorType could be Host, EmailAddress, File, Address, or URL.
		Must be used along with the Indicator parameter.
		
	.PARAMETER Indicator
		Optional paramter used to list all signatures linked to a specific Indicator.
		Must be used along with the IndicatorType parameter.
	
	.PARAMETER Owner
		Optional Parameter to define a specific Community (or other "Owner") from which to retrieve signatures.
		This switch can be used alongside some of the other switches.
	
	.PARAMETER ResultStart
		Optional Parameter. Use when dealing with large number of results.
		If you use ResultLimit of 100, you can use a ResultStart value of 100 to show items 100 through 200.
	
	.PARAMETER ResultLimit
		Optional Parameter. Change the maximum number of results to display. Default is 100, Maximum is 500.

	.EXAMPLE
		Get-TCSignatures
		
	.EXAMPLE
		Get-TCSignatures -AdversaryID <AdversaryID>
		
	.EXAMPLE
		Get-TCSignatures -EmailID <EmailID>
		
	.EXAMPLE
		Get-TCSignatures -IncidentID <IncidentID>
	
	.EXAMPLE
		Get-TCSignatures -SecurityLabel <SecurityLabel>
		
	.EXAMPLE
		Get-TCSignatures -SignatureID <SignatureID>
	
	.EXAMPLE
		Get-TCSignatures -SignatureID <SignatureID> -Download
		
	.EXAMPLE
		Get-TCSignatures -TagName <TagName>
		
	.EXAMPLE
		Get-TCSignatures -ThreatID <ThreatID>
		
	.EXAMPLE
		Get-TCSignatures -VictimID <VictimID>
	
	.EXAMPLE
		Get-TCSignatures -IndicatorType Address -Indicator <Indicator>
	
	.EXAMPLE
		Get-TCSignatures -IndicatorType EmailAddress -Indicator <Indicator>
	
	.EXAMPLE
		Get-TCSignatures -IndicatorType File -Indicator <Indicator>
	
	.EXAMPLE
		Get-TCSignatures -IndicatorType Host -Indicator <Indicator>
	
	.EXAMPLE
		Get-TCSignatures -IndicatorType URL -Indicator <Indicator>
	#>
	[CmdletBinding(DefaultParameterSetName='Default')]Param(
		[Parameter(Mandatory=$True,ParameterSetName='AdversaryID')]
			[ValidateNotNullOrEmpty()][String]$AdversaryID,
		[Parameter(Mandatory=$True,ParameterSetName='EmailID')]
			[ValidateNotNullOrEmpty()][String]$EmailID,
		[Parameter(Mandatory=$True,ParameterSetName='IncidentID')]
			[ValidateNotNullOrEmpty()][String]$IncidentID,
		[Parameter(Mandatory=$True,ParameterSetName='Indicator')]
			[ValidateSet('Address','EmailAddress','File','Host','URL')][String]$IndicatorType,
		[Parameter(Mandatory=$True,ParameterSetName='Indicator')]
			[ValidateNotNullOrEmpty()][String]$Indicator,
		[Parameter(Mandatory=$True,ParameterSetName='SecurityLabel')]
			[ValidateNotNullOrEmpty()][String]$SecurityLabel,
		[Parameter(Mandatory=$True,ParameterSetName='SignatureID')]
		[Parameter(Mandatory=$True,ParameterSetName='SignatureDownload')]
			[ValidateNotNullOrEmpty()][String]$SignatureID,
		[Parameter(Mandatory=$True,ParameterSetName='SignatureDownload')]
			[ValidateNotNull()][Switch]$Download,
		[Parameter(Mandatory=$True,ParameterSetName='TagName')]
			[ValidateNotNullOrEmpty()][String]$TagName,
		[Parameter(Mandatory=$True,ParameterSetName='ThreatID')]
			[ValidateNotNullOrEmpty()][String]$ThreatID,
		[Parameter(Mandatory=$True,ParameterSetName='VictimID')]
			[ValidateNotNullOrEmpty()][String]$VictimID,
		[Parameter(Mandatory=$False,ParameterSetName='Default')]
		[Parameter(Mandatory=$False,ParameterSetName='SecurityLabel')]
		[Parameter(Mandatory=$False,ParameterSetName='TagName')]
			[ValidateNotNullOrEmpty()][String]$Owner,
		[Parameter(Mandatory=$False,ParameterSetName='Default')]
		[Parameter(Mandatory=$False,ParameterSetName='Indicator')]
		[Parameter(Mandatory=$False,ParameterSetName='AdversaryID')]
		[Parameter(Mandatory=$False,ParameterSetName='EmailID')]
		[Parameter(Mandatory=$False,ParameterSetName='IncidentID')]
		[Parameter(Mandatory=$False,ParameterSetName='SecurityLabel')]
		[Parameter(Mandatory=$False,ParameterSetName='TagName')]
		[Parameter(Mandatory=$False,ParameterSetName='ThreatID')]
			[ValidateRange('1','500')][int]$ResultLimit=100,
		[Parameter(Mandatory=$False,ParameterSetName='Default')]
		[Parameter(Mandatory=$False,ParameterSetName='Indicator')]
		[Parameter(Mandatory=$False,ParameterSetName='AdversaryID')]
		[Parameter(Mandatory=$False,ParameterSetName='EmailID')]
		[Parameter(Mandatory=$False,ParameterSetName='IncidentID')]
		[Parameter(Mandatory=$False,ParameterSetName='SecurityLabel')]
		[Parameter(Mandatory=$False,ParameterSetName='TagName')]
		[Parameter(Mandatory=$False,ParameterSetName='ThreatID')]
			[ValidateNotNullOrEmpty()][int]$ResultStart
	)
	
	# Construct the Child URL based on the Parameter Set that was chosen
	switch ($PSCmdlet.ParameterSetName) {
		"AdversaryID" {
			$APIChildURL = "/v2/groups/adversaries/" + $AdversaryID + "/groups/signatures"
		}
		
		"EmailID" {
			$APIChildURL = "/v2/groups/emails/" + $EmailID + "/groups/signatures"
		}
		
		"IncidentID" {
			$APIChildURL = "/v2/groups/incidents/" + $IncidentID + "/groups/signatures"
		}
		
		"Indicator" {
			# Craft Indicator Child URL based on Indicator Type
			switch ($IndicatorType) {
				"Address" {
					$APIChildURL = "/v2/indicators/addresses/" + $Indicator + "/groups/signatures"
				}
				"EmailAddress" {
					$APIChildURL = "/v2/indicators/emailAddresses/" + $Indicator + "/groups/signatures"
				}
				"File" {
					$APIChildURL = "/v2/indicators/files/" + $Indicator + "/groups/signatures"
				}
				"Host" {
					$APIChildURL = "/v2/indicators/hosts/" + $Indicator + "/groups/signatures"
				}
				"URL" {
					# URLs need to be converted to a friendly format first
					$Indicator = Get-EscapedURIString -String $Indicator
					$APIChildURL = "/v2/indicators/urls/" + $Indicator + "/groups/signatures"
				}
			}
		}
		
		"SecurityLabel" {
			# Need to escape the URI in case there are any spaces or special characters
			$SecurityLabel = Get-EscapedURIString -String $SecurityLabel
			$APIChildURL = "/v2/securityLabels/" + $SecurityLabel + "/groups/signatures"
		}
		
		"SignatureDownload" {
			$APIChildURL = "/v2/groups/signatures/" + $SignatureID + "/download"
		}
		
		"SignatureID" {
			$APIChildURL = "/v2/groups/signatures/" + $SignatureID
		}
		
		"TagName" {
			# Need to escape the URI in case there are any spaces or special characters
			$TagName = Get-EscapedURIString -String $TagName
			$APIChildURL = "/v2/tags/" + $TagName + "/groups/signatures"		
		}		
		
		"ThreatID" {
			$APIChildURL = "/v2/groups/threats/" + $ThreatID + "/groups/signatures"
		}
		
		"VictimID" {
			$APIChildURL = "/v2/victims/" + $VictimID + "/groups/signatures"
		}
		
		Default {
			# Use this if nothing else is specified
			$APIChildURL ="/v2/groups/signatures"
		}
	}

	# Add to the URI if Owner, ResultStart, or ResultLimit was specified
	if ($Owner -and $ResultStart -and $ResultLimit -ne 100) {
		$APIChildURL = $APIChildURL + "?owner=" + (Get-EscapedURIString -String $Owner) + "&resultStart=" + $ResultStart + "&resultLimit=" + $ResultLimit
	} elseif ($Owner -and $ResultStart -and $ResultLimit -eq 100) {
		$APIChildURL = $APIChildURL + "?owner=" + (Get-EscapedURIString -String $Owner) + "&resultStart=" + $ResultStart
	} elseif ($Owner -and (-not $ResultStart) -and $ResultLimit -ne 100) {
		$APIChildURL = $APIChildURL + "?owner=" + (Get-EscapedURIString -String $Owner) + "&resultLimit=" + $ResultLimit
	} elseif ($Owner -and (-not $ResultStart) -and $ResultLimit -eq 100) {
		$APIChildURL = $APIChildURL + "?owner=" + (Get-EscapedURIString -String $Owner)
	} elseif ((-not $Owner) -and $ResultStart -and $ResultLimit -ne 100) {
		$APIChildURL = $APIChildURL + "?resultStart=" + $ResultStart + "&resultLimit=" + $ResultLimit
	} elseif ((-not $Owner) -and $ResultStart -and $ResultLimit -eq 100) {
		$APIChildURL = $APIChildURL + "?resultStart=" + $ResultStart
	} elseif ((-not $Owner) -and (-not $ResultStart) -and $ResultLimit -ne 100) {
		$APIChildURL = $APIChildURL + "?resultLimit=" + $ResultLimit
	}
	
	# Generate the appropriate Headers for the API Request
	$AuthorizationHeaders = Get-ThreatConnectHeaders -RequestMethod "GET" -URL $APIChildURL
	
	# Create the URI using System.URI (This fixes the issues with URL encoding)
	$URI = New-Object System.Uri ($Script:APIBaseURL + $APIChildURL)
	
	if ($IndicatorType -eq "URL" -and $Indicator) { [URLFix]::ForceCanonicalPathAndQuery($URI) }
	
	# Query the API
	$Response = Invoke-RestMethod -Method "GET" -Uri $URI -Headers $AuthorizationHeaders -ErrorAction SilentlyContinue
	
	# Verify API Request Status as Success or Print the Error
	if ($Response.Status -eq "Success") {
		$Response.data | Get-Member -MemberType NoteProperty | Where-Object { $_.Name -ne "resultCount" } | Select-Object -ExpandProperty Name | ForEach-Object { $Response.data.$_ }
	} else {
		Write-Verbose "API Request failed with the following error:`n $($Response.Status)"
	}
}

function Get-TCThreats {
	<#
	.SYNOPSIS
		Gets a list of threats from Threat Connect.  Default is all threats for the API Key's organization
	
	.PARAMETER AdversaryID
		Optional parameter used to list all threats linked to a specific Adversary ID.
		
	.PARAMETER EmailID
		Optional parameter used to list all threats linked to a specific Email ID.
		
	.PARAMETER IncidentID
		Optional parameter used to list all threats linked to a specific Incident ID.
		
	.PARAMETER IndicatorType
		Optional paramter used to list all threats linked to a specific Indicator.  IndicatorType could be Host, EmailAddress, File, Address, or URL.
		Must be used along with the Indicator parameter.
		
	.PARAMETER Indicator
		Optional paramter used to list all threats linked to a specific Indicator.
		Must be used along with the IndicatorType parameter.
		
	.PARAMETER SecurityLabel
		Optional parameter used to list all threats with a specific Security Label.
		
	.PARAMETER SignatureID
		Optional parameter used to list all threats linked to a specific Signature ID.
	
	.PARAMETER TagName
		Optional parameter used to list all threats with a specific Tag.
	
	.PARAMETER ThreatID
		Optional parameter used to specify a Threat ID for which to query.
	
	.PARAMETER VictimID
		Optional parameter used to list all threats linked to a specific Victim ID.
	
	.PARAMETER Owner
		Optional Parameter to define a specific Community (or other "Owner") from which to retrieve threats.
		This switch can be used alongside some of the other switches.
	
	.PARAMETER ResultStart
		Optional Parameter. Use when dealing with large number of results.
		If you use ResultLimit of 100, you can use a ResultStart value of 100 to show items 100 through 200.
	
	.PARAMETER ResultLimit
		Optional Parameter. Change the maximum number of results to display. Default is 100, Maximum is 500.

	.EXAMPLE
		Get-TCThreats
		
	.EXAMPLE
		Get-TCThreats -AdversaryID <AdversaryID>
		
	.EXAMPLE
		Get-TCThreats -EmailID <EmailID>
		
	.EXAMPLE
		Get-TCThreats -IncidentID <IncidentID>
	
	.EXAMPLE
		Get-TCThreats -SecurityLabel <SecurityLabel>
		
	.EXAMPLE
		Get-TCThreats -SignatureID <SignatureID>
		
	.EXAMPLE
		Get-TCThreats -TagName <TagName>
		
	.EXAMPLE
		Get-TCThreats -ThreatID <ThreatID>
		
	.EXAMPLE
		Get-TCThreats -VictimID <VictimID>
		
	.EXAMPLE
		Get-TCThreats -IndicatorType Address -Indicator <Indicator>
	
	.EXAMPLE
		Get-TCThreats -IndicatorType EmailAddress -Indicator <Indicator>
	
	.EXAMPLE
		Get-TCThreats -IndicatorType File -Indicator <Indicator>
	
	.EXAMPLE
		Get-TCThreats -IndicatorType Host -Indicator <Indicator>
	
	.EXAMPLE
		Get-TCThreats -IndicatorType URL -Indicator <Indicator>
	#>
	[CmdletBinding(DefaultParameterSetName='Default')]Param(
		[Parameter(Mandatory=$True,ParameterSetName='AdversaryID')]
			[ValidateNotNullOrEmpty()][String]$AdversaryID,
		[Parameter(Mandatory=$True,ParameterSetName='EmailID')]
			[ValidateNotNullOrEmpty()][String]$EmailID,
		[Parameter(Mandatory=$True,ParameterSetName='IncidentID')]
			[ValidateNotNullOrEmpty()][String]$IncidentID,
		[Parameter(Mandatory=$True,ParameterSetName='Indicator')]
			[ValidateSet('Address','EmailAddress','File','Host','URL')][String]$IndicatorType,
		[Parameter(Mandatory=$True,ParameterSetName='Indicator')]
			[ValidateNotNullOrEmpty()][String]$Indicator,
		[Parameter(Mandatory=$True,ParameterSetName='SecurityLabel')]
			[ValidateNotNullOrEmpty()][String]$SecurityLabel,
		[Parameter(Mandatory=$True,ParameterSetName='SignatureID')]
			[ValidateNotNullOrEmpty()][String]$SignatureID,
		[Parameter(Mandatory=$True,ParameterSetName='TagName')]
			[ValidateNotNullOrEmpty()][String]$TagName,
		[Parameter(Mandatory=$True,ParameterSetName='ThreatID')]
			[ValidateNotNullOrEmpty()][String]$ThreatID,
		[Parameter(Mandatory=$True,ParameterSetName='VictimID')]
			[ValidateNotNullOrEmpty()][String]$VictimID,
		[Parameter(Mandatory=$False,ParameterSetName='Default')]
		[Parameter(Mandatory=$False,ParameterSetName='Indicator')]
		[Parameter(Mandatory=$False,ParameterSetName='SecurityLabel')]
		[Parameter(Mandatory=$False,ParameterSetName='TagName')]
			[ValidateNotNullOrEmpty()][String]$Owner,
		[Parameter(Mandatory=$False,ParameterSetName='Default')]
		[Parameter(Mandatory=$False,ParameterSetName='Indicator')]
		[Parameter(Mandatory=$False,ParameterSetName='AdversaryID')]
		[Parameter(Mandatory=$False,ParameterSetName='EmailID')]
		[Parameter(Mandatory=$False,ParameterSetName='IncidentID')]
		[Parameter(Mandatory=$False,ParameterSetName='SecurityLabel')]
		[Parameter(Mandatory=$False,ParameterSetName='SignatureID')]
		[Parameter(Mandatory=$False,ParameterSetName='TagName')]
		[Parameter(Mandatory=$False,ParameterSetName='VictimID')]
			[ValidateRange('1','500')][int]$ResultLimit=100,
		[Parameter(Mandatory=$False,ParameterSetName='Default')]
		[Parameter(Mandatory=$False,ParameterSetName='Indicator')]
		[Parameter(Mandatory=$False,ParameterSetName='AdversaryID')]
		[Parameter(Mandatory=$False,ParameterSetName='EmailID')]
		[Parameter(Mandatory=$False,ParameterSetName='IncidentID')]
		[Parameter(Mandatory=$False,ParameterSetName='SecurityLabel')]
		[Parameter(Mandatory=$False,ParameterSetName='SignatureID')]
		[Parameter(Mandatory=$False,ParameterSetName='TagName')]
		[Parameter(Mandatory=$False,ParameterSetName='VictimID')]
			[ValidateNotNullOrEmpty()][int]$ResultStart
	)
	
	# Construct the Child URL based on the Parameter Set that was chosen
	switch ($PSCmdlet.ParameterSetName) {
		"AdversaryID" {
			$APIChildURL = "/v2/groups/adversaries/" + $AdversaryID + "/groups/threats"
		}
		
		"EmailID" {
			$APIChildURL = "/v2/groups/emails/" + $EmailID + "/groups/threats"
		}
		
		"IncidentID" {
			$APIChildURL = "/v2/groups/incidents/" + $IncidentID + "/groups/threats"
		}
		
		"Indicator" {
			# Craft Indicator Child URL based on Indicator Type
			switch ($IndicatorType) {
				"Address" {
					$APIChildURL = "/v2/indicators/addresses/" + $Indicator + "/groups/threats"
				}
				"EmailAddress" {
					$APIChildURL = "/v2/indicators/emailAddresses/" + $Indicator + "/groups/threats"
				}
				"File" {
					$APIChildURL = "/v2/indicators/files/" + $Indicator + "/groups/threats"
				}
				"Host" {
					$APIChildURL = "/v2/indicators/hosts/" + $Indicator + "/groups/threats"
				}
				"URL" {
					# URLs need to be converted to a friendly format first
					$Indicator = Get-EscapedURIString -String $Indicator
					$APIChildURL = "/v2/indicators/urls/" + $Indicator + "/groups/threats"
				}
			}
		}
		
		"SecurityLabel" {
			# Need to escape the URI in case there are any spaces or special characters
			$SecurityLabel = Get-EscapedURIString -String $SecurityLabel
			$APIChildURL = "/v2/securityLabels/" + $SecurityLabel + "/groups/threats"
		}
		
		"SignatureID" {
			$APIChildURL = "/v2/groups/signatures/" + $SignatureID + "/groups/threats"
		}
		
		"TagName" {
			# Need to escape the URI in case there are any spaces or special characters
			$TagName = Get-EscapedURIString -String $TagName
			$APIChildURL = "/v2/tags/" + $TagName + "/groups/threats"		
		}
		
		"ThreatID" {
			$APIChildURL = "/v2/groups/threats/" + $ThreatID
		}
		
		"VictimID" {
			$APIChildURL = "/v2/victims/" + $VictimID + "/groups/threats"
		}
		
		Default {
			# Use this if nothing else is specified
			$APIChildURL ="/v2/groups/threats"
		}
	}

	# Add to the URI if Owner, ResultStart, or ResultLimit was specified
	if ($Owner -and $ResultStart -and $ResultLimit -ne 100) {
		$APIChildURL = $APIChildURL + "?owner=" + (Get-EscapedURIString -String $Owner) + "&resultStart=" + $ResultStart + "&resultLimit=" + $ResultLimit
	} elseif ($Owner -and $ResultStart -and $ResultLimit -eq 100) {
		$APIChildURL = $APIChildURL + "?owner=" + (Get-EscapedURIString -String $Owner) + "&resultStart=" + $ResultStart
	} elseif ($Owner -and (-not $ResultStart) -and $ResultLimit -ne 100) {
		$APIChildURL = $APIChildURL + "?owner=" + (Get-EscapedURIString -String $Owner) + "&resultLimit=" + $ResultLimit
	} elseif ($Owner -and (-not $ResultStart) -and $ResultLimit -eq 100) {
		$APIChildURL = $APIChildURL + "?owner=" + (Get-EscapedURIString -String $Owner)
	} elseif ((-not $Owner) -and $ResultStart -and $ResultLimit -ne 100) {
		$APIChildURL = $APIChildURL + "?resultStart=" + $ResultStart + "&resultLimit=" + $ResultLimit
	} elseif ((-not $Owner) -and $ResultStart -and $ResultLimit -eq 100) {
		$APIChildURL = $APIChildURL + "?resultStart=" + $ResultStart
	} elseif ((-not $Owner) -and (-not $ResultStart) -and $ResultLimit -ne 100) {
		$APIChildURL = $APIChildURL + "?resultLimit=" + $ResultLimit
	}
	
	# Generate the appropriate Headers for the API Request
	$AuthorizationHeaders = Get-ThreatConnectHeaders -RequestMethod "GET" -URL $APIChildURL
	
	# Create the URI using System.URI (This fixes the issues with URL encoding)
	$URI = New-Object System.Uri ($Script:APIBaseURL + $APIChildURL)
	
	if ($IndicatorType -eq "URL" -and $Indicator) { [URLFix]::ForceCanonicalPathAndQuery($URI) }
	
	# Query the API
	$Response = Invoke-RestMethod -Method "GET" -Uri $URI -Headers $AuthorizationHeaders -ErrorAction SilentlyContinue
	
	# Verify API Request Status as Success or Print the Error
	if ($Response.Status -eq "Success") {
		$Response.data | Get-Member -MemberType NoteProperty | Where-Object { $_.Name -ne "resultCount" } | Select-Object -ExpandProperty Name | ForEach-Object { $Response.data.$_ }
	} else {
		Write-Verbose "API Request failed with the following error:`n $($Response.Status)"
	}
}

function Get-TCAttributes {
	<#
	.SYNOPSIS
		Gets a list of attributes for the specified "group".  (Group being Adversaries, Emails, Incidents, Signatures and Threats)
		
	.PARAMETER AdversaryID
		Optional parameter used to list all attributes linked to a specific Adversary ID.
	
	.PARAMETER EmailID
		Optional parameter used to list all attributes linked to a specific Email ID.
	
	.PARAMETER IncidentID
		Optional parameter used to list all attributes linked to a specific Incident ID.
	
	.PARAMETER SignatureID
		Optional parameter used to list all attributes linked to a specific Signature ID.
	
	.PARAMETER ThreatID
		Optional parameter used to list all attributes linked to a specific Threat ID.
		
	.PARAMETER IndicatorType
		Optional paramter used to list all attributes linked to a specific Indicator.  IndicatorType could be Host, EmailAddress, File, Address, or URL.
		Must be used along with the Indicator parameter.
		
	.PARAMETER Indicator
		Optional paramter used to list all attributes linked to a specific Indicator.
		Must be used along with the IndicatorType parameter.
	
	.PARAMETER Owner
		Optional Parameter to define a specific Community (or other "Owner") from which to retrieve attributes.
		This switch can be used alongside some of the other switches.
	
	.PARAMETER ResultStart
		Optional Parameter. Use when dealing with large number of results.
		If you use ResultLimit of 100, you can use a ResultStart value of 100 to show items 100 through 200.
	
	.PARAMETER ResultLimit
		Optional Parameter. Change the maximum number of results to display. Default is 100, Maximum is 500.
	
	.EXAMPLE
		Get-TCAttributes -AdversaryID "123456"
	
	.EXAMPLE
		Get-TCAttributes -EmailID <EmailID>
	
	.EXAMPLE
		Get-TCAttributes -IncidentID <IncidentID>
	
	.EXAMPLE
		Get-TCAttributes -SignatureID <SignatureID>
	
	.EXAMPLE
		Get-TCAttributes -ThreatID <ThreatID>
		
	.EXAMPLE
		Get-TCAttributes -IndicatorType Address -Indicator <Indicator>
	
	.EXAMPLE
		Get-TCAttributes -IndicatorType EmailAddress -Indicator <Indicator>
	
	.EXAMPLE
		Get-TCAttributes -IndicatorType File -Indicator <Indicator>
	
	.EXAMPLE
		Get-TCAttributes -IndicatorType Host -Indicator <Indicator>
	
	.EXAMPLE
		Get-TCAttributes -IndicatorType URL -Indicator <Indicator>
	#>
	[CmdletBinding()]Param(
		[Parameter(Mandatory=$True,ParameterSetName='AdversaryID')]
			[ValidateNotNullOrEmpty()][String]$AdversaryID,
		[Parameter(Mandatory=$True,ParameterSetName='EmailID')]
			[ValidateNotNullOrEmpty()][String]$EmailID,
		[Parameter(Mandatory=$True,ParameterSetName='IncidentID')]
			[ValidateNotNullOrEmpty()][String]$IncidentID,
		[Parameter(Mandatory=$True,ParameterSetName='Indicator')]
			[ValidateSet('Address','EmailAddress','File','Host','URL')][String]$IndicatorType,
		[Parameter(Mandatory=$True,ParameterSetName='Indicator')]
			[ValidateNotNullOrEmpty()][String]$Indicator,
		[Parameter(Mandatory=$True,ParameterSetName='SignatureID')]
			[ValidateNotNullOrEmpty()][String]$SignatureID,
		[Parameter(Mandatory=$True,ParameterSetName='ThreatID')]
			[ValidateNotNullOrEmpty()][String]$ThreatID,
		[Parameter(Mandatory=$False,ParameterSetName='Indicator')]
			[ValidateNotNullOrEmpty()][String]$Owner,
		[Parameter(Mandatory=$False)][ValidateRange('1','500')][int]$ResultLimit=100,
		[Parameter(Mandatory=$False)][ValidateNotNullOrEmpty()][int]$ResultStart
	)
	
	# Construct the Child URL based on the Parameter Set that was chosen
	switch ($PSCmdlet.ParameterSetName) {
		"AdversaryID" { 
			$APIChildURL = "/v2/groups/adversaries/" + $AdversaryID + "/attributes"
		}
		
		"EmailID" { 
			$APIChildURL = "/v2/groups/emails/" + $EmailID + "/attributes"
		}
		
		"IncidentID" { 
			$APIChildURL = "/v2/groups/incidents/" + $IncidentID + "/attributes"
		}
		
		"Indicator" {
			# Craft Indicator Child URL based on Indicator Type
			switch ($IndicatorType) {
				"Address" {
					$APIChildURL = "/v2/indicators/addresses/" + $Indicator + "/attributes"
				}
				"EmailAddress" {
					$APIChildURL = "/v2/indicators/emailAddresses/" + $Indicator + "/attributes"
				}
				"File" {
					$APIChildURL = "/v2/indicators/files/" + $Indicator + "/attributes"
				}
				"Host" {
					$APIChildURL = "/v2/indicators/hosts/" + $Indicator + "/attributes"
				}
				"URL" {
					# URLs need to be converted to a friendly format first
					$Indicator = Get-EscapedURIString -String $Indicator
					$APIChildURL = "/v2/indicators/urls/" + $Indicator + "/attributes"
				}
			}
		}
		
		"SignatureID" { 
			$APIChildURL = "/v2/groups/signatures/" + $SignatureID + "/attributes"
		}
		
		"ThreatID" { 
			$APIChildURL = "/v2/groups/threats/" + $ThreatID + "/attributes"
		}
	}
	
	# Add to the URI if Owner, ResultStart, or ResultLimit was specified
	if ($Owner -and $ResultStart -and $ResultLimit -ne 100) {
		$APIChildURL = $APIChildURL + "?owner=" + (Get-EscapedURIString -String $Owner) + "&resultStart=" + $ResultStart + "&resultLimit=" + $ResultLimit
	} elseif ($Owner -and $ResultStart -and $ResultLimit -eq 100) {
		$APIChildURL = $APIChildURL + "?owner=" + (Get-EscapedURIString -String $Owner) + "&resultStart=" + $ResultStart
	} elseif ($Owner -and (-not $ResultStart) -and $ResultLimit -ne 100) {
		$APIChildURL = $APIChildURL + "?owner=" + (Get-EscapedURIString -String $Owner) + "&resultLimit=" + $ResultLimit
	} elseif ($Owner -and (-not $ResultStart) -and $ResultLimit -eq 100) {
		$APIChildURL = $APIChildURL + "?owner=" + (Get-EscapedURIString -String $Owner)
	} elseif ((-not $Owner) -and $ResultStart -and $ResultLimit -ne 100) {
		$APIChildURL = $APIChildURL + "?resultStart=" + $ResultStart + "&resultLimit=" + $ResultLimit
	} elseif ((-not $Owner) -and $ResultStart -and $ResultLimit -eq 100) {
		$APIChildURL = $APIChildURL + "?resultStart=" + $ResultStart
	} elseif ((-not $Owner) -and (-not $ResultStart) -and $ResultLimit -ne 100) {
		$APIChildURL = $APIChildURL + "?resultLimit=" + $ResultLimit
	}

	# Generate the appropriate Headers for the API Request
	$AuthorizationHeaders = Get-ThreatConnectHeaders -RequestMethod "GET" -URL $APIChildURL
	
	# Create the URI using System.URI (This fixes the issues with URL encoding)
	$URI = New-Object System.Uri ($Script:APIBaseURL + $APIChildURL)
	
	if ($IndicatorType -eq "URL" -and $Indicator) { [URLFix]::ForceCanonicalPathAndQuery($URI) }
	
	# Query the API
	$Response = Invoke-RestMethod -Method "GET" -Uri $URI -Headers $AuthorizationHeaders -ErrorAction SilentlyContinue
	
	# Verify API Request Status as Success or Print the Error
	if ($Response.Status -eq "Success") {
		$Response.data | Get-Member -MemberType NoteProperty | Where-Object { $_.Name -ne "resultCount" } | Select-Object -ExpandProperty Name | ForEach-Object { $Response.data.$_ }
	} else {
		Write-Verbose "API Request failed with the following error:`n $($Response.Status)"
	}
}

function Get-TCSecurityLabels {
	<#
	.SYNOPSIS
		Gets a list of security labels from Threat Connect.  Default is all security labels for the API Key's organization
	
	.PARAMETER AdversaryID
		Optional parameter used to list all security labels linked to a specific Adversary ID.
		
	.PARAMETER EmailID
		Optional parameter used to list all security labels linked to a specific Email ID.
		
	.PARAMETER IncidentID
		Optional parameter used to list all security labels linked to a specific Incident ID.
		
	.PARAMETER SignatureID
		Optional parameter used to list all security labels linked to a specific Signature ID.
	
	.PARAMETER ThreatID
		Optional parameter used to list all security labels linked to a specific Threat ID.
	
	.PARAMETER IndicatorType
		Optional paramter used to list all security labels linked to a specific Indicator.  IndicatorType could be Host, EmailAddress, File, Address, or URL.
		Must be used along with the Indicator parameter.
		
	.PARAMETER Indicator
		Optional paramter used to list all security labels linked to a specific Indicator.
		Must be used along with the IndicatorType parameter.
	
	.PARAMETER Owner
		Optional Parameter to define a specific Community (or other "Owner") from which to retrieve security labels.
		This switch can be used alongside some of the other switches.
	
	.PARAMETER ResultStart
		Optional Parameter. Use when dealing with large number of results.
		If you use ResultLimit of 100, you can use a ResultStart value of 100 to show items 100 through 200.
	
	.PARAMETER ResultLimit
		Optional Parameter. Change the maximum number of results to display. Default is 100, Maximum is 500.

	.EXAMPLE
		Get-TCSecurityLabels
		
	.EXAMPLE
		Get-TCSecurityLabels -AdversaryID <AdversaryID>
		
	.EXAMPLE
		Get-TCSecurityLabels -EmailID <EmailID>
		
	.EXAMPLE
		Get-TCSecurityLabels -IncidentID <IncidentID>
	
	.EXAMPLE
		Get-TCSecurityLabels -SecurityLabel <SecurityLabel>
		
	.EXAMPLE
		Get-TCSecurityLabels -SignatureID <SignatureID>
		
	.EXAMPLE
		Get-TCSecurityLabels -ThreatID <ThreatID>
	
	.EXAMPLE
		Get-TCSecurityLabels -IndicatorType Address -Indicator <Indicator>
	
	.EXAMPLE
		Get-TCSecurityLabels -IndicatorType EmailAddress -Indicator <Indicator>
	
	.EXAMPLE
		Get-TCSecurityLabels -IndicatorType File -Indicator <Indicator>
	
	.EXAMPLE
		Get-TCSecurityLabels -IndicatorType Host -Indicator <Indicator>
	
	.EXAMPLE
		Get-TCSecurityLabels -IndicatorType URL -Indicator <Indicator>
		
	#>
	[CmdletBinding(DefaultParameterSetName='Default')]Param(
		[Parameter(Mandatory=$True,ParameterSetName='AdversaryID')]
			[ValidateNotNullOrEmpty()][String]$AdversaryID,
		[Parameter(Mandatory=$True,ParameterSetName='EmailID')]
			[ValidateNotNullOrEmpty()][String]$EmailID,
		[Parameter(Mandatory=$True,ParameterSetName='IncidentID')]
			[ValidateNotNullOrEmpty()][String]$IncidentID,
		[Parameter(Mandatory=$True,ParameterSetName='Indicator')]
			[ValidateSet('Address','EmailAddress','File','Host','URL')][String]$IndicatorType,
		[Parameter(Mandatory=$True,ParameterSetName='Indicator')]
			[ValidateNotNullOrEmpty()][String]$Indicator,
		[Parameter(Mandatory=$True,ParameterSetName='SecurityLabel')]
			[ValidateNotNullOrEmpty()][String]$SecurityLabel,
		[Parameter(Mandatory=$True,ParameterSetName='SignatureID')]
			[ValidateNotNullOrEmpty()][String]$SignatureID,
		[Parameter(Mandatory=$True,ParameterSetName='ThreatID')]
			[ValidateNotNullOrEmpty()][String]$ThreatID,
		[Parameter(Mandatory=$False,ParameterSetName='Default')]
		[Parameter(Mandatory=$False,ParameterSetName='Indicator')]
		[Parameter(Mandatory=$False,ParameterSetName='SecurityLabel')]
			[ValidateNotNullOrEmpty()][String]$Owner,
		[Parameter(Mandatory=$False,ParameterSetName='Default')]
		[Parameter(Mandatory=$False,ParameterSetName='Indicator')]
		[Parameter(Mandatory=$False,ParameterSetName='AdversaryID')]
		[Parameter(Mandatory=$False,ParameterSetName='EmailID')]
		[Parameter(Mandatory=$False,ParameterSetName='IncidentID')]
		[Parameter(Mandatory=$False,ParameterSetName='SignatureID')]
		[Parameter(Mandatory=$False,ParameterSetName='TagName')]
		[Parameter(Mandatory=$False,ParameterSetName='ThreatID')]
			[ValidateRange('1','500')][int]$ResultLimit=100,
		[Parameter(Mandatory=$False,ParameterSetName='Default')]
		[Parameter(Mandatory=$False,ParameterSetName='Indicator')]
		[Parameter(Mandatory=$False,ParameterSetName='AdversaryID')]
		[Parameter(Mandatory=$False,ParameterSetName='EmailID')]
		[Parameter(Mandatory=$False,ParameterSetName='IncidentID')]
		[Parameter(Mandatory=$False,ParameterSetName='SignatureID')]
		[Parameter(Mandatory=$False,ParameterSetName='TagName')]
		[Parameter(Mandatory=$False,ParameterSetName='ThreatID')]
			[ValidateNotNullOrEmpty()][int]$ResultStart
	)
	
	# Construct the Child URL based on the Parameter Set that was chosen
	switch ($PSCmdlet.ParameterSetName) {
		"AdversaryID" {
			$APIChildURL = "/v2/groups/adversaries/" + $AdversaryID + "/securityLabels"
		}
		
		"EmailID" {
			$APIChildURL = "/v2/groups/emails/" + $EmailID + "/securityLabels"
		}
		
		"IncidentID" {
			$APIChildURL = "/v2/groups/incidents/" + $IncidentID + "/securityLabels"
		}
		
		"Indicator" {
			# Craft Indicator Child URL based on Indicator Type
			switch ($IndicatorType) {
				"Address" {
					$APIChildURL = "/v2/indicators/addresses/" + $Indicator + "/securityLabels"
				}
				"EmailAddress" {
					$APIChildURL = "/v2/indicators/emailAddresses/" + $Indicator + "/securityLabels"
				}
				"File" {
					$APIChildURL = "/v2/indicators/files/" + $Indicator + "/securityLabels"
				}
				"Host" {
					$APIChildURL = "/v2/indicators/hosts/" + $Indicator + "/securityLabels"
				}
				"URL" {
					# URLs need to be converted to a friendly format first
					$Indicator = Get-EscapedURIString -String $Indicator
					$APIChildURL = "/v2/indicators/urls/" + $Indicator + "/securityLabels"
				}
			}
		}
		
		"SecurityLabel" {
			# Need to escape the URI in case there are any spaces or special characters
			$SecurityLabel = Get-EscapedURIString -String $SecurityLabel
			$APIChildURL = "/v2/securityLabels/" + $SecurityLabel
		}
		
		"SignatureID" {
			$APIChildURL = "/v2/groups/signatures/" + $SignatureID + "/securityLabels"
		}
		
		"ThreatID" {
			$APIChildURL = "/v2/groups/threats/" + $ThreatID + "/securityLabels"
		}
		
		Default {
			# Use this if nothing else is specified
			$APIChildURL ="/v2/securityLabels"
		}
	}

	# Add to the URI if Owner, ResultStart, or ResultLimit was specified
	if ($Owner -and $ResultStart -and $ResultLimit -ne 100) {
		$APIChildURL = $APIChildURL + "?owner=" + (Get-EscapedURIString -String $Owner) + "&resultStart=" + $ResultStart + "&resultLimit=" + $ResultLimit
	} elseif ($Owner -and $ResultStart -and $ResultLimit -eq 100) {
		$APIChildURL = $APIChildURL + "?owner=" + (Get-EscapedURIString -String $Owner) + "&resultStart=" + $ResultStart
	} elseif ($Owner -and (-not $ResultStart) -and $ResultLimit -ne 100) {
		$APIChildURL = $APIChildURL + "?owner=" + (Get-EscapedURIString -String $Owner) + "&resultLimit=" + $ResultLimit
	} elseif ($Owner -and (-not $ResultStart) -and $ResultLimit -eq 100) {
		$APIChildURL = $APIChildURL + "?owner=" + (Get-EscapedURIString -String $Owner)
	} elseif ((-not $Owner) -and $ResultStart -and $ResultLimit -ne 100) {
		$APIChildURL = $APIChildURL + "?resultStart=" + $ResultStart + "&resultLimit=" + $ResultLimit
	} elseif ((-not $Owner) -and $ResultStart -and $ResultLimit -eq 100) {
		$APIChildURL = $APIChildURL + "?resultStart=" + $ResultStart
	} elseif ((-not $Owner) -and (-not $ResultStart) -and $ResultLimit -ne 100) {
		$APIChildURL = $APIChildURL + "?resultLimit=" + $ResultLimit
	}
	
	# Generate the appropriate Headers for the API Request
	$AuthorizationHeaders = Get-ThreatConnectHeaders -RequestMethod "GET" -URL $APIChildURL
	
	# Create the URI using System.URI (This fixes the issues with URL encoding)
	$URI = New-Object System.Uri ($Script:APIBaseURL + $APIChildURL)
	
	if ($IndicatorType -eq "URL" -and $Indicator) { [URLFix]::ForceCanonicalPathAndQuery($URI) }
	
	# Query the API
	$Response = Invoke-RestMethod -Method "GET" -Uri $URI -Headers $AuthorizationHeaders -ErrorAction SilentlyContinue
	
	# Verify API Request Status as Success or Print the Error
	if ($Response.Status -eq "Success") {
		$Response.data | Get-Member -MemberType NoteProperty | Where-Object { $_.Name -ne "resultCount" } | Select-Object -ExpandProperty Name | ForEach-Object { $Response.data.$_ }
	} else {
		Write-Verbose "API Request failed with the following error:`n $($Response.Status)"
	}
}

function Get-TCTags {
	<#
	.SYNOPSIS
		Gets a list of tags from Threat Connect.  Default is all tags for the API Key's organization
	
	.PARAMETER AdversaryID
		Optional parameter used to list all tags linked to a specific Adversary ID.
		
	.PARAMETER EmailID
		Optional parameter used to list all tags linked to a specific Email ID.
		
	.PARAMETER IncidentID
		Optional parameter used to list all tags linked to a specific Incident ID.
		
	.PARAMETER SignatureID
		Optional parameter used to list all tags linked to a specific Signature ID.
	
	.PARAMETER TagName
		Optional parameter used to specify a Tag Name for which to query.
	
	.PARAMETER ThreatID
		Optional parameter used to list all tags linked to a specific Threat ID.
		
	.PARAMETER IndicatorType
		Optional paramter used to list all tags linked to a specific Indicator.  IndicatorType could be Host, EmailAddress, File, Address, or URL.
		Must be used along with the Indicator parameter.
		
	.PARAMETER Indicator
		Optional paramter used to list all tags linked to a specific Indicator.
		Must be used along with the IndicatorType parameter.
	
	.PARAMETER Owner
		Optional Parameter to define a specific Community (or other "Owner") from which to retrieve tags.
		This switch can be used alongside some of the other switches.
	
	.PARAMETER ResultStart
		Optional Parameter. Use when dealing with large number of results.
		If you use ResultLimit of 100, you can use a ResultStart value of 100 to show items 100 through 200.
	
	.PARAMETER ResultLimit
		Optional Parameter. Change the maximum number of results to display. Default is 100, Maximum is 500.
	
	.EXAMPLE
		Get-TCTags
		
	.EXAMPLE
		Get-TCTags -AdversaryID <AdversaryID>
		
	.EXAMPLE
		Get-TCTags -EmailID <EmailID>
		
	.EXAMPLE
		Get-TCTags -IncidentID <IncidentID>
		
	.EXAMPLE
		Get-TCTags -SignatureID <SignatureID>
		
	.EXAMPLE
		Get-TCTags -TagName <TagName>
		
	.EXAMPLE
		Get-TCTags -ThreatID <ThreatID>
		
	.EXAMPLE
		Get-TCTags -IndicatorType Address -Indicator <Indicator>
	
	.EXAMPLE
		Get-TCTags -IndicatorType EmailAddress -Indicator <Indicator>
	
	.EXAMPLE
		Get-TCTags -IndicatorType File -Indicator <Indicator>
	
	.EXAMPLE
		Get-TCTags -IndicatorType Host -Indicator <Indicator>
	
	.EXAMPLE
		Get-TCTags -IndicatorType URL -Indicator <Indicator>
		
	#>
	[CmdletBinding(DefaultParameterSetName='Default')]Param(
		[Parameter(Mandatory=$True,ParameterSetName='AdversaryID')]
			[ValidateNotNullOrEmpty()][String]$AdversaryID,
		[Parameter(Mandatory=$True,ParameterSetName='EmailID')]
			[ValidateNotNullOrEmpty()][String]$EmailID,
		[Parameter(Mandatory=$True,ParameterSetName='IncidentID')]
			[ValidateNotNullOrEmpty()][String]$IncidentID,
		[Parameter(Mandatory=$True,ParameterSetName='Indicator')]
			[ValidateSet('Address','EmailAddress','File','Host','URL')][String]$IndicatorType,
		[Parameter(Mandatory=$True,ParameterSetName='Indicator')]
			[ValidateNotNullOrEmpty()][String]$Indicator,
		[Parameter(Mandatory=$True,ParameterSetName='SignatureID')]
			[ValidateNotNullOrEmpty()][String]$SignatureID,
		[Parameter(Mandatory=$True,ParameterSetName='TagName')]
			[ValidateNotNullOrEmpty()][String]$TagName,
		[Parameter(Mandatory=$True,ParameterSetName='ThreatID')]
			[ValidateNotNullOrEmpty()][String]$ThreatID,
		[Parameter(Mandatory=$False,ParameterSetName='Default')]
		[Parameter(Mandatory=$False,ParameterSetName='Indicator')]
		[Parameter(Mandatory=$False,ParameterSetName='TagName')]
			[ValidateNotNullOrEmpty()][String]$Owner,
		[Parameter(Mandatory=$False,ParameterSetName='Default')]
		[Parameter(Mandatory=$False,ParameterSetName='Indicator')]
		[Parameter(Mandatory=$False,ParameterSetName='AdversaryID')]
		[Parameter(Mandatory=$False,ParameterSetName='EmailID')]
		[Parameter(Mandatory=$False,ParameterSetName='IncidentID')]
		[Parameter(Mandatory=$False,ParameterSetName='SecurityLabel')]
		[Parameter(Mandatory=$False,ParameterSetName='SignatureID')]
		[Parameter(Mandatory=$False,ParameterSetName='ThreatID')]
			[ValidateRange('1','500')][int]$ResultLimit=100,
		[Parameter(Mandatory=$False,ParameterSetName='Default')]
		[Parameter(Mandatory=$False,ParameterSetName='Indicator')]
		[Parameter(Mandatory=$False,ParameterSetName='AdversaryID')]
		[Parameter(Mandatory=$False,ParameterSetName='EmailID')]
		[Parameter(Mandatory=$False,ParameterSetName='IncidentID')]
		[Parameter(Mandatory=$False,ParameterSetName='SecurityLabel')]
		[Parameter(Mandatory=$False,ParameterSetName='SignatureID')]
		[Parameter(Mandatory=$False,ParameterSetName='ThreatID')]
			[ValidateNotNullOrEmpty()][int]$ResultStart
	)
	
	# Construct the Child URL based on the Parameter Set that was chosen
	switch ($PSCmdlet.ParameterSetName) {
		"AdversaryID" {
			$APIChildURL = "/v2/groups/adversaries/" + $AdversaryID + "/tags"
		}
		
		"EmailID" {
			$APIChildURL = "/v2/groups/emails/" + $EmailID + "/tags"
		}
		
		"IncidentID" {
			$APIChildURL = "/v2/groups/incidents/" + $IncidentID + "/tags"
		}
		
		"Indicator" {
			# Craft Indicator Child URL based on Indicator Type
			switch ($IndicatorType) {
				"Address" {
					$APIChildURL = "/v2/indicators/addresses/" + $Indicator + "/tags"
				}
				"EmailAddress" {
					$APIChildURL = "/v2/indicators/emailAddresses/" + $Indicator + "/tags"
				}
				"File" {
					$APIChildURL = "/v2/indicators/files/" + $Indicator + "/tags"
				}
				"Host" {
					$APIChildURL = "/v2/indicators/hosts/" + $Indicator + "/tags"
				}
				"URL" {
					# URLs need to be converted to a friendly format first
					$Indicator = Get-EscapedURIString -String $Indicator
					$APIChildURL = "/v2/indicators/urls/" + $Indicator + "/tags"
				}
			}
		}
		
		"SignatureID" {
			$APIChildURL = "/v2/groups/signatures/" + $SignatureID + "/tags"
		}
		
		"TagName" {
			# Need to escape the URI in case there are any spaces or special characters
			$TagName = Get-EscapedURIString -String $TagName
			$APIChildURL = "/v2/tags/" + $TagName
		}
		
		"ThreatID" {
			$APIChildURL = "/v2/groups/threats/" + $ThreatID + "/tags"
		}
		
		Default {
			# Use this if nothing else is specified
			$APIChildURL ="/v2/tags"
		}
	}

	# Add to the URI if Owner, ResultStart, or ResultLimit was specified
	if ($Owner -and $ResultStart -and $ResultLimit -ne 100) {
		$APIChildURL = $APIChildURL + "?owner=" + (Get-EscapedURIString -String $Owner) + "&resultStart=" + $ResultStart + "&resultLimit=" + $ResultLimit
	} elseif ($Owner -and $ResultStart -and $ResultLimit -eq 100) {
		$APIChildURL = $APIChildURL + "?owner=" + (Get-EscapedURIString -String $Owner) + "&resultStart=" + $ResultStart
	} elseif ($Owner -and (-not $ResultStart) -and $ResultLimit -ne 100) {
		$APIChildURL = $APIChildURL + "?owner=" + (Get-EscapedURIString -String $Owner) + "&resultLimit=" + $ResultLimit
	} elseif ($Owner -and (-not $ResultStart) -and $ResultLimit -eq 100) {
		$APIChildURL = $APIChildURL + "?owner=" + (Get-EscapedURIString -String $Owner)
	} elseif ((-not $Owner) -and $ResultStart -and $ResultLimit -ne 100) {
		$APIChildURL = $APIChildURL + "?resultStart=" + $ResultStart + "&resultLimit=" + $ResultLimit
	} elseif ((-not $Owner) -and $ResultStart -and $ResultLimit -eq 100) {
		$APIChildURL = $APIChildURL + "?resultStart=" + $ResultStart
	} elseif ((-not $Owner) -and (-not $ResultStart) -and $ResultLimit -ne 100) {
		$APIChildURL = $APIChildURL + "?resultLimit=" + $ResultLimit
	}
	
	# Generate the appropriate Headers for the API Request
	$AuthorizationHeaders = Get-ThreatConnectHeaders -RequestMethod "GET" -URL $APIChildURL
	
	# Create the URI using System.URI (This fixes the issues with URL encoding)
	$URI = New-Object System.Uri ($Script:APIBaseURL + $APIChildURL)
	
	if ($IndicatorType -eq "URL" -and $Indicator) { [URLFix]::ForceCanonicalPathAndQuery($URI) }
	
	# Query the API
	$Response = Invoke-RestMethod -Method "GET" -Uri $URI -Headers $AuthorizationHeaders -ErrorAction SilentlyContinue
	
	# Verify API Request Status as Success or Print the Error
	if ($Response.Status -eq "Success") {
		$Response.data | Get-Member -MemberType NoteProperty | Where-Object { $_.Name -ne "resultCount" } | Select-Object -ExpandProperty Name | ForEach-Object { $Response.data.$_ }
	} else {
		Write-Verbose "API Request failed with the following error:`n $($Response.Status)"
	}
}

function Get-TCVictims {
	<#
	.SYNOPSIS
		Gets a list of victims from Threat Connect.  Default is all victims for the API Key's organization
	
	.PARAMETER AdversaryID
		Optional parameter used to list all victims linked to a specific Adversary ID.
		
	.PARAMETER EmailID
		Optional parameter used to list all victims linked to a specific Email ID.
		
	.PARAMETER IncidentID
		Optional parameter used to list all victims linked to a specific Incident ID.
		
	.PARAMETER SignatureID
		Optional parameter used to list all victims linked to a specific Signature ID.
	
	.PARAMETER ThreatID
		Optional parameter used to list all victims linked to a specific Threat ID.
	
	.PARAMETER VictimID
		Optional parameter used to list a specific victim.
	
	.PARAMETER IndicatorType
		Optional paramter used to list all victims linked to a specific Indicator.  IndicatorType could be Host, EmailAddress, File, Address, or URL.
		Must be used along with the Indicator parameter.
		
	.PARAMETER Indicator
		Optional paramter used to list all victims linked to a specific Indicator.
		Must be used along with the IndicatorType parameter.
	
	.PARAMETER Owner
		Optional Parameter to define a specific Community (or other "Owner") from which to retrieve victims.
		This switch can be used alongside some of the other switches.
	
	.PARAMETER ResultStart
		Optional Parameter. Use when dealing with large number of results.
		If you use ResultLimit of 100, you can use a ResultStart value of 100 to show items 100 through 200.
	
	.PARAMETER ResultLimit
		Optional Parameter. Change the maximum number of results to display. Default is 100, Maximum is 500.

	.EXAMPLE
		Get-TCVictims
		
	.EXAMPLE
		Get-TCVictims -AdversaryID <AdversaryID>
		
	.EXAMPLE
		Get-TCVictims -EmailID <EmailID>
		
	.EXAMPLE
		Get-TCVictims -IncidentID <IncidentID>
		
	.EXAMPLE
		Get-TCVictims -SignatureID <SignatureID>
		
	.EXAMPLE
		Get-TCVictims -ThreatID <ThreatID>
		
	.EXAMPLE
		Get-TCVictims -IndicatorType Address -Indicator <Indicator>
	
	.EXAMPLE
		Get-TCVictims -IndicatorType EmailAddress -Indicator <Indicator>
	
	.EXAMPLE
		Get-TCVictims -IndicatorType File -Indicator <Indicator>
	
	.EXAMPLE
		Get-TCVictims -IndicatorType Host -Indicator <Indicator>
	
	.EXAMPLE
		Get-TCVictims -IndicatorType URL -Indicator <Indicator>
		
	#>
	[CmdletBinding(DefaultParameterSetName='Default')]Param(
		[Parameter(Mandatory=$True,ParameterSetName='AdversaryID')]
			[ValidateNotNullOrEmpty()][String]$AdversaryID,
		[Parameter(Mandatory=$True,ParameterSetName='EmailID')]
			[ValidateNotNullOrEmpty()][String]$EmailID,
		[Parameter(Mandatory=$True,ParameterSetName='IncidentID')]
			[ValidateNotNullOrEmpty()][String]$IncidentID,
		[Parameter(Mandatory=$True,ParameterSetName='Indicator')]
			[ValidateSet('Address','EmailAddress','File','Host','URL')][String]$IndicatorType,
		[Parameter(Mandatory=$True,ParameterSetName='Indicator')]
			[ValidateNotNullOrEmpty()][String]$Indicator,
		[Parameter(Mandatory=$True,ParameterSetName='SignatureID')]
			[ValidateNotNullOrEmpty()][String]$SignatureID,
		[Parameter(Mandatory=$True,ParameterSetName='ThreatID')]
			[ValidateNotNullOrEmpty()][String]$ThreatID,
		[Parameter(Mandatory=$True,ParameterSetName='VictimID')]
			[ValidateNotNullOrEmpty()][String]$VictimID,
		[Parameter(Mandatory=$False,ParameterSetName='Default')]
		[Parameter(Mandatory=$False,ParameterSetName='Indicator')]
			[ValidateNotNullOrEmpty()][String]$Owner,
		[Parameter(Mandatory=$False,ParameterSetName='Default')]
		[Parameter(Mandatory=$False,ParameterSetName='Indicator')]
		[Parameter(Mandatory=$False,ParameterSetName='AdversaryID')]
		[Parameter(Mandatory=$False,ParameterSetName='EmailID')]
		[Parameter(Mandatory=$False,ParameterSetName='IncidentID')]
		[Parameter(Mandatory=$False,ParameterSetName='SignatureID')]
		[Parameter(Mandatory=$False,ParameterSetName='ThreatID')]
			[ValidateRange('1','500')][int]$ResultLimit=100,
		[Parameter(Mandatory=$False,ParameterSetName='Default')]
		[Parameter(Mandatory=$False,ParameterSetName='Indicator')]
		[Parameter(Mandatory=$False,ParameterSetName='AdversaryID')]
		[Parameter(Mandatory=$False,ParameterSetName='EmailID')]
		[Parameter(Mandatory=$False,ParameterSetName='IncidentID')]
		[Parameter(Mandatory=$False,ParameterSetName='SignatureID')]
		[Parameter(Mandatory=$False,ParameterSetName='ThreatID')]
			[ValidateNotNullOrEmpty()][int]$ResultStart
	)
	
	# Construct the Child URL based on the Parameter Set that was chosen
	switch ($PSCmdlet.ParameterSetName) {
		"AdversaryID" {
			$APIChildURL = "/v2/groups/adversaries/" + $AdversaryID + "/victims"
		}
		
		"EmailID" {
			$APIChildURL = "/v2/groups/emails/" + $EmailID + "/victims"
		}
		
		"IncidentID" {
			$APIChildURL = "/v2/groups/incidents/" + $IncidentID + "/victims"
		}
		
		"Indicator" {
			# Craft Indicator Child URL based on Indicator Type
			switch ($IndicatorType) {
				"Address" {
					$APIChildURL = "/v2/indicators/addresses/" + $Indicator + "/victims"
				}
				"EmailAddress" {
					$APIChildURL = "/v2/indicators/emailAddresses/" + $Indicator + "/victims"
				}
				"File" {
					$APIChildURL = "/v2/indicators/files/" + $Indicator + "/victims"
				}
				"Host" {
					$APIChildURL = "/v2/indicators/hosts/" + $Indicator + "/victims"
				}
				"URL" {
					# URLs need to be converted to a friendly format first
					$Indicator = Get-EscapedURIString -String $Indicator
					$APIChildURL = "/v2/indicators/urls/" + $Indicator + "/victims"
				}
			}
		}
		
		"SignatureID" {
			$APIChildURL = "/v2/groups/signatures/" + $SignatureID + "/victims"
		}
		
		"ThreatID" {
			$APIChildURL = "/v2/groups/threats/" + $ThreatID + "/victims"
		}
		
		"VictimID" {
			$APIChildURL = "/v2/victims/" + $VictimID
		}
		
		Default {
			# Use this if nothing else is specified
			$APIChildURL ="/v2/victims"
		}
	}

	# Add to the URI if Owner, ResultStart, or ResultLimit was specified
	if ($Owner -and $ResultStart -and $ResultLimit -ne 100) {
		$APIChildURL = $APIChildURL + "?owner=" + (Get-EscapedURIString -String $Owner) + "&resultStart=" + $ResultStart + "&resultLimit=" + $ResultLimit
	} elseif ($Owner -and $ResultStart -and $ResultLimit -eq 100) {
		$APIChildURL = $APIChildURL + "?owner=" + (Get-EscapedURIString -String $Owner) + "&resultStart=" + $ResultStart
	} elseif ($Owner -and (-not $ResultStart) -and $ResultLimit -ne 100) {
		$APIChildURL = $APIChildURL + "?owner=" + (Get-EscapedURIString -String $Owner) + "&resultLimit=" + $ResultLimit
	} elseif ($Owner -and (-not $ResultStart) -and $ResultLimit -eq 100) {
		$APIChildURL = $APIChildURL + "?owner=" + (Get-EscapedURIString -String $Owner)
	} elseif ((-not $Owner) -and $ResultStart -and $ResultLimit -ne 100) {
		$APIChildURL = $APIChildURL + "?resultStart=" + $ResultStart + "&resultLimit=" + $ResultLimit
	} elseif ((-not $Owner) -and $ResultStart -and $ResultLimit -eq 100) {
		$APIChildURL = $APIChildURL + "?resultStart=" + $ResultStart
	} elseif ((-not $Owner) -and (-not $ResultStart) -and $ResultLimit -ne 100) {
		$APIChildURL = $APIChildURL + "?resultLimit=" + $ResultLimit
	}
	
	# Generate the appropriate Headers for the API Request
	$AuthorizationHeaders = Get-ThreatConnectHeaders -RequestMethod "GET" -URL $APIChildURL
	
	# Create the URI using System.URI (This fixes the issues with URL encoding)
	$URI = New-Object System.Uri ($Script:APIBaseURL + $APIChildURL)
	
	if ($IndicatorType -eq "URL" -and $Indicator) { [URLFix]::ForceCanonicalPathAndQuery($URI) }
	
	# Query the API
	$Response = Invoke-RestMethod -Method "GET" -Uri $URI -Headers $AuthorizationHeaders -ErrorAction SilentlyContinue
	
	# Verify API Request Status as Success or Print the Error
	if ($Response.Status -eq "Success") {
		$Response.data | Get-Member -MemberType NoteProperty | Where-Object { $_.Name -ne "resultCount" } | Select-Object -ExpandProperty Name | ForEach-Object { $Response.data.$_ }
	} else {
		Write-Verbose "API Request failed with the following error:`n $($Response.Status)"
	}
}

function Get-TCVictimAssets {
	<#
	.SYNOPSIS
		Gets a list of victim assets from Threat Connect.
	
	.PARAMETER AdversaryID
		Optional parameter used to list all victim assets linked to a specific Adversary ID.
		
	.PARAMETER EmailID
		Optional parameter used to list all victim assets linked to a specific Email ID.
		
	.PARAMETER IncidentID
		Optional parameter used to list all victim assets linked to a specific Incident ID.
		
	.PARAMETER SignatureID
		Optional parameter used to list all victim assets linked to a specific Signature ID.
	
	.PARAMETER ThreatID
		Optional parameter used to list all victim assets linked to a specific Threat ID.
	
	.PARAMETER VictimID
		Optional parameter used to list all victim assets linked to a specific Victim ID.
	
	.PARAMETER AssetType
		Optional parameter used to specify an asset type to return.
		Possible values are EmailAddress, NetworkAccount, PhoneNumber, SocialNetwork, WebSite.
	
	.PARAMETER IndicatorType
		Optional paramter used to list all victim assets linked to a specific Indicator.  IndicatorType could be Host, EmailAddress, File, Address, or URL.
		Must be used along with the Indicator parameter.
		
	.PARAMETER Indicator
		Optional paramter used to list all victim assets linked to a specific Indicator.
		Must be used along with the IndicatorType parameter.
	
	.PARAMETER Owner
		Optional Parameter to define a specific Community (or other "Owner") from which to retrieve victim assets.
		This switch can be used alongside some of the other switches.

	.EXAMPLE
		Get-TCVictimAssets
		
	.EXAMPLE
		Get-TCVictimAssets -AdversaryID <AdversaryID>
	
	.EXAMPLE
		Get-TCVictimAssets -AdversaryID <AdversaryID> -AssetType <AssetType>
	
	.EXAMPLE
		Get-TCVictimAssets -EmailID <EmailID>
	
	.EXAMPLE
		Get-TCVictimAssets -EmailID <EmailID> -AssetType <AssetType>
		
	.EXAMPLE
		Get-TCVictimAssets -IncidentID <IncidentID>
	
	.EXAMPLE
		Get-TCVictimAssets -IncidentID <IncidentID> -AssetType <AssetType>
		
	.EXAMPLE
		Get-TCVictimAssets -SignatureID <SignatureID>
	
	.EXAMPLE
		Get-TCVictimAssets -SignatureID <SignatureID> -AssetType <AssetType>
		
	.EXAMPLE
		Get-TCVictimAssets -ThreatID <ThreatID>
	
	.EXAMPLE
		Get-TCVictimAssets -ThreatID <ThreatID> -AssetType <AssetType>
	
	.EXAMPLE
		Get-TCVictimAssets -VictimID <VictimID>
	
	EXAMPLE
		Get-TCVictimAssets -VictimID <VictimID> -AssetType <AssetType>
		
	.EXAMPLE
		Get-TCVictimAssets -IndicatorType Address -Indicator <Indicator>
	
	.EXAMPLE
		Get-TCVictimAssets -IndicatorType EmailAddress -Indicator <Indicator>
	
	.EXAMPLE
		Get-TCVictimAssets -IndicatorType File -Indicator <Indicator>
	
	.EXAMPLE
		Get-TCVictimAssets -IndicatorType Host -Indicator <Indicator>
	
	.EXAMPLE
		Get-TCVictimAssets -IndicatorType URL -Indicator <Indicator>
		
	#>
	[CmdletBinding()]Param(
		[Parameter(Mandatory=$True,ParameterSetName='AdversaryID')]
			[ValidateNotNullOrEmpty()][String]$AdversaryID,
		[Parameter(Mandatory=$True,ParameterSetName='EmailID')]
			[ValidateNotNullOrEmpty()][String]$EmailID,
		[Parameter(Mandatory=$True,ParameterSetName='IncidentID')]
			[ValidateNotNullOrEmpty()][String]$IncidentID,
		[Parameter(Mandatory=$True,ParameterSetName='Indicator')]
			[ValidateSet('Address','EmailAddress','File','Host','URL')][String]$IndicatorType,
		[Parameter(Mandatory=$True,ParameterSetName='Indicator')]
			[ValidateNotNullOrEmpty()][String]$Indicator,
		[Parameter(Mandatory=$True,ParameterSetName='SignatureID')]
			[ValidateNotNullOrEmpty()][String]$SignatureID,
		[Parameter(Mandatory=$True,ParameterSetName='ThreatID')]
			[ValidateNotNullOrEmpty()][String]$ThreatID,
		[Parameter(Mandatory=$True,ParameterSetName='VictimID')]
			[ValidateNotNullOrEmpty()][String]$VictimID,
		[Parameter(Mandatory=$False,ParameterSetName='AdversaryID')]
		[Parameter(Mandatory=$False,ParameterSetName='EmailID')]
		[Parameter(Mandatory=$False,ParameterSetName='IncidentID')]
		[Parameter(Mandatory=$False,ParameterSetName='SignatureID')]
		[Parameter(Mandatory=$False,ParameterSetName='ThreatID')]
		[Parameter(Mandatory=$False,ParameterSetName='Indicator')]
		[Parameter(Mandatory=$False,ParameterSetName='VictimID')]
			[ValidateSet('EmailAddress','PhoneNumber','NetworkAccount','SocialNetwork','WebSite')][String]$AssetType,
		[Parameter(Mandatory=$False,ParameterSetName='Indicator')]
			[ValidateNotNullOrEmpty()][String]$Owner
	)
	
	# Construct the Child URL based on the Parameter Set that was chosen
	switch ($PSCmdlet.ParameterSetName) {
		"AdversaryID" {
			$APIChildURL = "/v2/groups/adversaries/" + $AdversaryID + "/victimAssets"
		}
		
		"EmailID" {
			$APIChildURL = "/v2/groups/emails/" + $EmailID + "/victimAssets"
		}
		
		"IncidentID" {
			$APIChildURL = "/v2/groups/incidents/" + $IncidentID + "/victimAssets"
		}
		
		"Indicator" {
			# Craft Indicator Child URL based on Indicator Type
			switch ($IndicatorType) {
				"Address" {
					$APIChildURL = "/v2/indicators/addresses/" + $Indicator + "/victimAssets"
				}
				"EmailAddress" {
					$APIChildURL = "/v2/indicators/emailAddresses/" + $Indicator + "/victimAssets"
				}
				"File" {
					$APIChildURL = "/v2/indicators/files/" + $Indicator + "/victimAssets"
				}
				"Host" {
					$APIChildURL = "/v2/indicators/hosts/" + $Indicator + "/victimAssets"
				}
				"URL" {
					# URLs need to be converted to a friendly format first
					$Indicator = Get-EscapedURIString -String $Indicator
					$APIChildURL = "/v2/indicators/urls/" + $Indicator + "/victimAssets"
				}
			}
		}
		
		"SignatureID" {
			$APIChildURL = "/v2/groups/signatures/" + $SignatureID + "/victimAssets"
		}
		
		"ThreatID" {
			$APIChildURL = "/v2/groups/threats/" + $ThreatID + "/victimAssets"
		}
		
		"VictimID" {
			$APIChildURL = "/v2/victims/" + $VictimID + "/victimAssets"
		}
	}
	
	# Add to the Child URL if an Asset Type was supplied
	if ($AssetType) {
		switch ($AssetType) {
			"EmailAddress" {
				$APIChildURL = $APIChildURL + "/emailAddresses"
			}
			
			"NetworkAccount" {
				$APIChildURL = $APIChildURL + "/networkAccounts"
			}
			
			"PhoneNumber" {
				$APIChildURL = $APIChildURL + "/phoneNumbers"
			}
			
			"SocialNetwork" {
				$APIChildURL = $APIChildURL + "/socialNetworks"
			}
			
			"WebSite" {
				$APIChildURL = $APIChildURL + "/webSites"
			}
		}	
	}

	# Add to the URI if Owner, ResultStart, or ResultLimit was specified
	if ($Owner) {
		$APIChildURL = $APIChildURL + "?owner=" + (Get-EscapedURIString -String $Owner)
	}
	
	# Generate the appropriate Headers for the API Request
	$AuthorizationHeaders = Get-ThreatConnectHeaders -RequestMethod "GET" -URL $APIChildURL
	
	# Create the URI using System.URI (This fixes the issues with URL encoding)
	$URI = New-Object System.Uri ($Script:APIBaseURL + $APIChildURL)
	
	if ($IndicatorType -eq "URL" -and $Indicator) { [URLFix]::ForceCanonicalPathAndQuery($URI) }
	
	# Query the API
	$Response = Invoke-RestMethod -Method "GET" -Uri $URI -Headers $AuthorizationHeaders -ErrorAction SilentlyContinue
	
	# Verify API Request Status as Success or Print the Error
	if ($Response.Status -eq "Success") {
		$Response.data | Get-Member -MemberType NoteProperty | Where-Object { $_.Name -ne "resultCount" } | Select-Object -ExpandProperty Name | ForEach-Object { $Response.data.$_ }
	} else {
		Write-Verbose "API Request failed with the following error:`n $($Response.Status)"
	}
}

function Get-TCIndicators {
	<#
	.SYNOPSIS
		Gets a list of indicators from Threat Connect.  Default is all indicators for the API Key's organization
	
	.PARAMETER AdversaryID
		Optional parameter used to list all indicators linked to a specific Adversary ID.
		
	.PARAMETER EmailID
		Optional parameter used to list all indicators linked to a specific Email ID.
		
	.PARAMETER IncidentID
		Optional parameter used to list all indicators linked to a specific Incident ID.
		
	.PARAMETER SecurityLabel
		Optional parameter used to list all indicators with a specific Security Label.
		
	.PARAMETER SignatureID
		Optional parameter used to list all indicators linked to a specific Signature ID.
	
	.PARAMETER TagName
		Optional parameter used to list all indicators with a specific Tag.
	
	.PARAMETER ThreatID
		Optional parameter used to list all indicators linked to a specific Threat ID.
	
	.PARAMETER VictimID
		Optional parameter used to list all indicators linked to a specific Victim ID.
		
	.PARAMETER IndicatorType
		Optional paramter used to list all indicators of a certain type.  IndicatorType could be Host, EmailAddress, File, Address, or URL.
		This parameter can be used alongside many of the other switches.
	
	.PARAMETER Indicator
		Optional paramter used to work with a specific indicator.  Must be used along with the IndicatorType parameter.
	
	.PARAMETER DNSResolutions
		Optional parameter to list the DNS Resolutions for a specific Host indicator.
	
	.PARAMETER FileOccurences
		Optional parameter to list the File Occurences for a specific File indicator.
	
	.PARAMETER Owner
		Optional Parameter to define a specific Community (or other "Owner") from which to retrieve indicators.
		This switch can be used alongside some of the other switches.
	
	.PARAMETER ResultStart
		Optional Parameter. Use when dealing with large number of results.
		If you use ResultLimit of 100, you can use a ResultStart value of 100 to show items 100 through 200.
	
	.PARAMETER ResultLimit
		Optional Parameter. Change the maximum number of results to display. Default is 100, Maximum is 500.
	
	.EXAMPLE
		Get-TCIndicators
		
	.EXAMPLE
		Get-TCIndicators -AdversaryID <AdversaryID>
	
	.EXAMPLE
		Get-TCIndicators -AdversaryID <AdversaryID> -IndicatorType <IndicatorType>
		
	.EXAMPLE
		Get-TCIndicators -EmailID <EmailID>
		
	.EXAMPLE
		Get-TCIndicators -EmailID <EmailID> -IndicatorType <IndicatorType>
		
	.EXAMPLE
		Get-TCIndicators -IncidentID <IncidentID>	
		
	.EXAMPLE
		Get-TCIndicators -IncidentID <IncidentID> -IndicatorType <IndicatorType>
	
	.EXAMPLE
		Get-TCIndicators -IndicatorType <IndicatorType>
	
	.EXAMPLE
		Get-TCIndicators -IndicatorType <IndicatorType> -Indicator <Indicator>
	
	.EXAMPLE
		Get-TCIndicators -IndicatorType Host -Indicator <Indicator> -DNSResolutions
	
	.EXAMPLE
		Get-TCIndicators -IndicatorType File -Indicator <Indicator> -FileOccurrences
	
	.EXAMPLE
		Get-TCIndicators -SecurityLabel <SecurityLabel>
		
	.EXAMPLE
		Get-TCIndicators -SecurityLabel <SecurityLabel> -IndicatorType <IndicatorType>
		
	.EXAMPLE
		Get-TCIndicators -SignatureID <SignatureID>
			
	.EXAMPLE
		Get-TCIndicators -SignatureID <SignatureID> -IndicatorType <IndicatorType>
		
	.EXAMPLE
		Get-TCIndicators -TagName <TagName>
			
	.EXAMPLE
		Get-TCIndicators -TagName <TagName> -IndicatorType <IndicatorType>
		
	.EXAMPLE
		Get-TCIndicators -ThreatID <ThreatID>
			
	.EXAMPLE
		Get-TCIndicators -ThreatID <ThreatID> -IndicatorType <IndicatorType>
		
	.EXAMPLE
		Get-TCIndicators -VictimID <VictimID>
			
	.EXAMPLE
		Get-TCIndicators -VictimID <VictimID> -IndicatorType <IndicatorType>
	#>
	[CmdletBinding(DefaultParameterSetName='Default')]Param(
		[Parameter(Mandatory=$True,ParameterSetName='AdversaryID')]
			[ValidateNotNullOrEmpty()][String]$AdversaryID,
		[Parameter(Mandatory=$True,ParameterSetName='EmailID')]
			[ValidateNotNullOrEmpty()][String]$EmailID,
		[Parameter(Mandatory=$True,ParameterSetName='IncidentID')]
			[ValidateNotNullOrEmpty()][String]$IncidentID,
		[Parameter(Mandatory=$False,ParameterSetName='AdversaryID')]
		[Parameter(Mandatory=$False,ParameterSetName='EmailID')]
		[Parameter(Mandatory=$False,ParameterSetName='IncidentID')]
		[Parameter(Mandatory=$True,ParameterSetName='Indicator')]
		[Parameter(Mandatory=$False,ParameterSetName='SecurityLabel')]
		[Parameter(Mandatory=$False,ParameterSetName='SignatureID')]
		[Parameter(Mandatory=$False,ParameterSetName='TagName')]
		[Parameter(Mandatory=$False,ParameterSetName='ThreatID')]
		[Parameter(Mandatory=$False,ParameterSetName='VictimID')]
			[ValidateSet('Address','EmailAddress','File','Host','URL')][String]$IndicatorType,
		[Parameter(Mandatory=$False,ParameterSetName='Indicator')]
			[ValidateNotNullOrEmpty()][String]$Indicator,
		[Parameter(Mandatory=$True,ParameterSetName='SecurityLabel')]
			[ValidateNotNullOrEmpty()][String]$SecurityLabel,
		[Parameter(Mandatory=$True,ParameterSetName='SignatureID')]
			[ValidateNotNullOrEmpty()][String]$SignatureID,
		[Parameter(Mandatory=$True,ParameterSetName='TagName')]
			[ValidateNotNullOrEmpty()][String]$TagName,
		[Parameter(Mandatory=$True,ParameterSetName='ThreatID')]
			[ValidateNotNullOrEmpty()][String]$ThreatID,
		[Parameter(Mandatory=$True,ParameterSetName='VictimID')]
			[ValidateNotNullOrEmpty()][String]$VictimID,
		[Parameter(Mandatory=$False,ParameterSetName='Default')]
		[Parameter(Mandatory=$False,ParameterSetName='Indicator')]
		[Parameter(Mandatory=$False,ParameterSetName='SecurityLabel')]
		[Parameter(Mandatory=$False,ParameterSetName='TagName')]
			[ValidateNotNullOrEmpty()][String]$Owner,
		[Parameter(Mandatory=$False,ParameterSetName='Default')]
		[Parameter(Mandatory=$False,ParameterSetName='Indicator')]
		[Parameter(Mandatory=$False,ParameterSetName='AdversaryID')]
		[Parameter(Mandatory=$False,ParameterSetName='EmailID')]
		[Parameter(Mandatory=$False,ParameterSetName='IncidentID')]
		[Parameter(Mandatory=$False,ParameterSetName='SecurityLabel')]
		[Parameter(Mandatory=$False,ParameterSetName='SignatureID')]
		[Parameter(Mandatory=$False,ParameterSetName='TagName')]
		[Parameter(Mandatory=$False,ParameterSetName='ThreatID')]
		[Parameter(Mandatory=$False,ParameterSetName='VictimID')]
			[ValidateRange('1','500')][int]$ResultLimit=100,
		[Parameter(Mandatory=$False,ParameterSetName='Default')]
		[Parameter(Mandatory=$False,ParameterSetName='Indicator')]
		[Parameter(Mandatory=$False,ParameterSetName='AdversaryID')]
		[Parameter(Mandatory=$False,ParameterSetName='EmailID')]
		[Parameter(Mandatory=$False,ParameterSetName='IncidentID')]
		[Parameter(Mandatory=$False,ParameterSetName='SecurityLabel')]
		[Parameter(Mandatory=$False,ParameterSetName='SignatureID')]
		[Parameter(Mandatory=$False,ParameterSetName='TagName')]
		[Parameter(Mandatory=$False,ParameterSetName='ThreatID')]
		[Parameter(Mandatory=$False,ParameterSetName='VictimID')]
			[ValidateNotNullOrEmpty()][int]$ResultStart
	)
	# Add the Dynamic Parameters DNSResolutions and FileOccurrences
	DynamicParam {
		# Initialize Parameter Dictionary
		$ParameterDictionary = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
		
		# If Host IndicatorType is selected, add DNSResolutions Parameter Availability
		if ($IndicatorType -eq "Host") {
			# Create attribute and attribute collection
			$DNSResolutionsAttribute = New-Object System.Management.Automation.ParameterAttribute
			$DNSResolutionsAttributeCollection = New-Object System.Collections.ObjectModel.Collection[System.Attribute]
			# Set the Parameter Properties
			$DNSResolutionsAttribute.Mandatory = $False
			$DNSResolutionsAttribute.ParameterSetName="Indicator"
			# Add to the Attribute Collection
			$DNSResolutionsAttributeCollection.Add($DNSResolutionsAttribute)
			# Create Parameter with Attribute Collection
			$DNSResolutionsParameter = New-Object System.Management.Automation.RuntimeDefinedParameter("DNSResolutions", [Switch], $DNSResolutionsAttributeCollection)
			# Add the Parameter to the Parameter Dictionary
			$ParameterDictionary.Add("DNSResolutions", $DNSResolutionsParameter)
		}
		
		# If File IndicatorType is selected, add FileOccurrences Parameter Availability
		if ($IndicatorType -eq "File") {
			# Create attribute and attribute collection
			$FileOccurrencesAttribute = New-Object System.Management.Automation.ParameterAttribute
			$FileOccurrencesAttributeCollection = New-Object System.Collections.ObjectModel.Collection[System.Attribute]
			# Set the Parameter Properties
			$FileOccurrencesAttribute.Mandatory = $False
			$FileOccurrencesAttribute.ParameterSetName = "Indicator"
			# Add to the Attribute Collection
			$FileOccurrencesAttributeCollection.Add($FileOccurrencesAttribute)
			# Create Parameter with Attribute Collection
			$FileOccurrencesParameter = New-Object System.Management.Automation.RuntimeDefinedParameter("FileOccurrences", [Switch], $FileOccurrencesAttributeCollection)
			$FileOccurrencesParameter.Value = $True
			# Add the Parameter to the Parameter Dictionary
			$ParameterDictionary.Add("FileOccurrences", $FileOccurrencesParameter)
		}
		return $ParameterDictionary
	}
	
	Process {
		# Construct the Child URL based on the Parameter Set that was chosen
		switch ($PSCmdlet.ParameterSetName) {
			"AdversaryID" {
				$APIChildURL = "/v2/groups/adversaries/" + $AdversaryID + "/indicators"
			}
			
			"EmailID" {
				$APIChildURL = "/v2/groups/emails/" + $EmailID + "/indicators"
			}
			
			"IncidentID" {
				$APIChildURL = "/v2/groups/incidents/" + $IncidentID + "/indicators"
			}
			
			"Indicator" {
				# Craft Indicator Child URL based on Indicator Type
				switch ($IndicatorType) {
					"Address" {
						$APIChildURL = "/v2/indicators/addresses"
					}
					"EmailAddress" {
						$APIChildURL = "/v2/indicators/emailAddresses"
					}
					"File" {
						$APIChildURL = "/v2/indicators/files"
						
					}
					"Host" {
						$APIChildURL = "/v2/indicators/hosts"
					}
					"URL" {
						$APIChildURL = "/v2/indicators/urls"
					}
				}
				
				if ($Indicator) {
					if ($IndicatorType -eq "URL") {
						# URLs need to be converted to a friendly format first
						$EscapedIndicator = Get-EscapedURIString -String $Indicator
						$APIChildURL = $APIChildURL + "/" + $EscapedIndicator
					} else {
						$APIChildURL = $APIChildURL + "/" + $Indicator
					}
					
					# Add to Child URL if File Occurrences were requested
					if ($PSBoundParameters.FileOccurrences) {
						$APIChildURL = $APIChildURL + "/fileOccurrences"
					}
					# Add to the Child URL if DNS Resolutions were requested
					if ($PSBoundParameters.DNSResolutions) {
						$APIChildURL = $APIChildURL + "/dnsResolutions"
					}
				}
			}
			
			"SecurityLabel" {
				# Need to escape the URI in case there are any spaces or special characters
				$SecurityLabel = Get-EscapedURIString -String $SecurityLabel
				$APIChildURL = "/v2/securityLabels/" + $SecurityLabel + "/indicators"
			}
			
			"SignatureID" {
				$APIChildURL = "/v2/groups/signatures/" + $SignatureID + "/indicators"
			}
			
			"TagName" {
				# Need to escape the URI in case there are any spaces or special characters
				$TagName = Get-EscapedURIString -String $TagName
				$APIChildURL = "/v2/tags/" + $TagName + "/indicators"
			}
			
			"ThreatID" {
				$APIChildURL = "/v2/groups/threats/" + $ThreatID + "/indicators"
			}
			
			"VictimID" {
				$APIChildURL = "/v2/victims/" + $VictimID + "/indicators"
			}
			
			Default {
				# Use this if nothing else is specified
				$APIChildURL ="/v2/indicators"
			}
		}
		
		if ($IndicatorType -and $PSCmdlet.ParameterSetName -ne "Indicator" ) {
			switch ($IndicatorType) {
				"Address" {
					$APIChildURL = $APIChildURL + "/addresses"
				}
				
				"Host" {
					$APIChildURL = $APIChildURL + "/hosts"
				}
				
				"EmailAddress" {
					$APIChildURL = $APIChildURL + "/emailAddresses"
				}
				
				"File" {
					$APIChildURL = $APIChildURL + "/files"
				}
				
				"URL" {
					$APIChildURL = $APIChildURL + "/urls"
				}
			}
		}
		

		# Add to the URI if Owner, ResultStart, or ResultLimit was specified
		if ($Owner -and $ResultStart -and $ResultLimit -ne 100) {
			$APIChildURL = $APIChildURL + "?owner=" + (Get-EscapedURIString -String $Owner) + "&resultStart=" + $ResultStart + "&resultLimit=" + $ResultLimit
		} elseif ($Owner -and $ResultStart -and $ResultLimit -eq 100) {
			$APIChildURL = $APIChildURL + "?owner=" + (Get-EscapedURIString -String $Owner) + "&resultStart=" + $ResultStart
		} elseif ($Owner -and (-not $ResultStart) -and $ResultLimit -ne 100) {
			$APIChildURL = $APIChildURL + "?owner=" + (Get-EscapedURIString -String $Owner) + "&resultLimit=" + $ResultLimit
		} elseif ($Owner -and (-not $ResultStart) -and $ResultLimit -eq 100) {
			$APIChildURL = $APIChildURL + "?owner=" + (Get-EscapedURIString -String $Owner)
		} elseif ((-not $Owner) -and $ResultStart -and $ResultLimit -ne 100) {
			$APIChildURL = $APIChildURL + "?resultStart=" + $ResultStart + "&resultLimit=" + $ResultLimit
		} elseif ((-not $Owner) -and $ResultStart -and $ResultLimit -eq 100) {
			$APIChildURL = $APIChildURL + "?resultStart=" + $ResultStart
		} elseif ((-not $Owner) -and (-not $ResultStart) -and $ResultLimit -ne 100) {
			$APIChildURL = $APIChildURL + "?resultLimit=" + $ResultLimit
		}
		
		# Generate the appropriate Headers for the API Request
		$AuthorizationHeaders = Get-ThreatConnectHeaders -RequestMethod "GET" -URL $APIChildURL
		
		# Create the URI using System.URI (This fixes the issues with URL encoding)
		$URI = New-Object System.Uri ($Script:APIBaseURL + $APIChildURL)
		
		if ($IndicatorType -eq "URL" -and $Indicator) { if ($IndicatorType -eq "URL" -and $Indicator) { [URLFix]::ForceCanonicalPathAndQuery($URI) } }
		
		# Query the API
		$Response = Invoke-RestMethod -Method "GET" -Uri $URI -Headers $AuthorizationHeaders -ErrorAction SilentlyContinue
		
		# Verify API Request Status as Success or Print the Error
		if ($Response.Status -eq "Success") {
			$Response.data | Get-Member -MemberType NoteProperty | Where-Object { $_.Name -ne "resultCount" } | Select-Object -ExpandProperty Name | ForEach-Object { $Response.data.$_ }
		} else {
			Write-Verbose "API Request failed with the following error:`n $($Response.Status)"
		}
	}
}

function New-TCAdversary {
	<#
	.SYNOPSIS
		Creates a new adversary in Threat Connect.
	
	.PARAMETER Name
		Name of the adversary to create.
		
	.EXAMPLE
		New-TCAdversary -Name <AdversaryName>
	#>
	[CmdletBinding()]Param(
		[Parameter(Mandatory=$True)][ValidateNotNullOrEmpty()][String]$Name
	)
	
	# Create a Custom Object and add the provided Name and Value variables to the object
	$CustomObject = "" | Select-Object -Property  name
	$CustomObject.name = $Name
	
	# Convert the Custom Object to JSON format for use with the API
	$JSONData = $CustomObject | ConvertTo-Json
	
	# Child URL for Adversary Creation
	$APIChildURL = "/v2/groups/adversaries"
	
	# Generate the appropriate Headers for the API Request
	$AuthorizationHeaders = Get-ThreatConnectHeaders -RequestMethod "POST" -URL $APIChildURL
	
	# Create the URI using System.URI (This fixes the issues with URL encoding)
	$URI = New-Object System.Uri ($Script:APIBaseURL + $APIChildURL)
	
	# Query the API
	$Response = Invoke-RestMethod -Method "POST" -Uri $URI -Headers $AuthorizationHeaders -Body $JSONData -ContentType "application/json" -ErrorAction SilentlyContinue
	
	# Verify API Request Status as Success or Print the Error
	if ($Response.Status -eq "Success") {
		$Response.data | Get-Member -MemberType NoteProperty | Where-Object { $_.Name -ne "resultCount" } | Select-Object -ExpandProperty Name | ForEach-Object { $Response.data.$_ }
	} else {
		Write-Verbose "API Request failed with the following error:`n $($Response.Status)"
	}
}

function New-TCEmail {
	<#
	.SYNOPSIS
		Creates a new email in Threat Connect.
	
	.PARAMETER Name
		Name of the email to create.
	
	.PARAMETER Header
		Header of the email to create.
	
	.PARAMETER Subject
		Subject of the email to create.
	
	.PARAMETER Body
		Body of the email to create.
	
	.PARAMETER To
		Optional parameter. To field for the email to create.
	
	.PARAMETER From
		Optional parameter. From field for the email to create.

	.EXAMPLE
		New-TCEmail -Name <EmailName> -Subject <Subject> -Body <Body> -Header <Header>
	
	.EXAMPLE
		New-TCEmail -Name <EmailName> -Subject <Subject> -Body <Body> -Header <Header> -To <To> -From <From>
	#>
	[CmdletBinding()]Param(
		[Parameter(Mandatory=$True)][ValidateNotNullOrEmpty()][String]$Name,
		[Parameter(Mandatory=$True)][ValidateNotNullOrEmpty()][String]$Subject,
		[Parameter(Mandatory=$True)][ValidateNotNullOrEmpty()][String]$Body,
		[Parameter(Mandatory=$True)][ValidateNotNullOrEmpty()][String]$Header,
		[Parameter(Mandatory=$False)][ValidateNotNullOrEmpty()][String]$To,
		[Parameter(Mandatory=$False)][ValidateNotNullOrEmpty()][String]$From
	)
	
	# Create a Custom Object and add the provided Name and Value variables to the object
	$CustomObject = "" | Select-Object -Property  name, subject, body, header
	$CustomObject.name = $Name
	$CustomObject.subject = $Subject
	$CustomObject.body = $Body
	$CustomObject.header = $Header
	
	# If the To field was supplied, add it to our custom object
	if ($To) {
		$CustomObject | Add-Member -MemberType NoteProperty -Name "to" -Value $To
	}
	# If the From field was supplied, add it to our custom object
	if ($From) {
		$CustomObject | Add-Member -MemberType NoteProperty -Name "from" -Value $From
	}
	
	# Convert the Custom Object to JSON format for use with the API
	$JSONData = $CustomObject | ConvertTo-Json
	
	# Child URL for Email Creation
	$APIChildURL = "/v2/groups/emails"
	
	# Generate the appropriate Headers for the API Request
	$AuthorizationHeaders = Get-ThreatConnectHeaders -RequestMethod "POST" -URL $APIChildURL
	
	# Create the URI using System.URI (This fixes the issues with URL encoding)
	$URI = New-Object System.Uri ($Script:APIBaseURL + $APIChildURL)
	
	if ($IndicatorType -eq "URL" -and $Indicator) { [URLFix]::ForceCanonicalPathAndQuery($URI) }
	
	# Query the API
	$Response = Invoke-RestMethod -Method "POST" -Uri $URI -Headers $AuthorizationHeaders -Body $JSONData -ContentType "application/json" -ErrorAction SilentlyContinue
	
	# Verify API Request Status as Success or Print the Error
	if ($Response.Status -eq "Success") {
		$Response.data | Get-Member -MemberType NoteProperty | Where-Object { $_.Name -ne "resultCount" } | Select-Object -ExpandProperty Name | ForEach-Object { $Response.data.$_ }
	} else {
		Write-Verbose "API Request failed with the following error:`n $($Response.Status)"
	}
}

function New-TCIncident {
	<#
	.SYNOPSIS
		Creates a new incident in Threat Connect.
	
	.PARAMETER Name
		Name of the incident to create.
	
	.PARAMETER EventDate
		The date the Incident occurred. The code attempts to convert the provided date to the format required by the API, but uses the computer's time zone from which the script is being run.
		
	.EXAMPLE
		New-TCIncident -Name <IncidentName> -EventDate "2015-01-01T14:00:00-06:00"
		
	.EXAMPLE
		New-TCIncident -Name <IncidentName> -EventDate (Get-Date -Date "10/01/2014 15:00:03" -Format "yyyy-MM-ddThh:mm:sszzzz")
	
	.EXAMPLE
		New-TCIncident -Name <IncidentName> -EventDate "10/01/2014 15:00:03"
	#>
	[CmdletBinding()]Param(
		[Parameter(Mandatory=$True)][ValidateNotNullOrEmpty()][String]$Name,
		[Parameter(Mandatory=$True)][ValidateNotNullOrEmpty()][String]$EventDate
	)
	
	Try { 
		$EventDate = Get-Date -Date $EventDate -Format "yyyy-MM-ddThh:mm:sszzzz" -ErrorAction Stop
	
		# Create a Custom Object and add the provided Name and Value variables to the object
		$CustomObject = "" | Select-Object -Property  name, eventDate
		$CustomObject.name = $Name
		$CustomObject.eventDate = $EventDate
	
		# Convert the Custom Object to JSON format for use with the API
		$JSONData = $CustomObject | ConvertTo-Json
		
		# Child URL for Adversary Creation
		$APIChildURL = "/v2/groups/incidents"
		
		# Generate the appropriate Headers for the API Request
		$AuthorizationHeaders = Get-ThreatConnectHeaders -RequestMethod "POST" -URL $APIChildURL
		
		# Create the URI using System.URI (This fixes the issues with URL encoding)
		$URI = New-Object System.Uri ($Script:APIBaseURL + $APIChildURL)
		
		if ($IndicatorType -eq "URL" -and $Indicator) { [URLFix]::ForceCanonicalPathAndQuery($URI) }
		
		# Query the API
		$Response = Invoke-RestMethod -Method "POST" -Uri $URI -Headers $AuthorizationHeaders -Body $JSONData -ContentType "application/json" -ErrorAction SilentlyContinue
		
		# Verify API Request Status as Success or Print the Error
		if ($Response.Status -eq "Success") {
			$Response.data | Get-Member -MemberType NoteProperty | Where-Object { $_.Name -ne "resultCount" } | Select-Object -ExpandProperty Name | ForEach-Object { $Response.data.$_ }
		} else {
			Write-Verbose "API Request failed with the following error:`n $($Response.Status)"
		}
	} Catch {
		return "Error converting EventDate to a properly formatted date/time for Threat Connect's API."
	}
}

function New-TCThreat {
	<#
	.SYNOPSIS
		Creates a new threat in Threat Connect.
	
	.PARAMETER Name
		Name of the threat to create.
		
	.EXAMPLE
		New-TCThreat -Name <ThreatName>
	#>
	[CmdletBinding()]Param(
		[Parameter(Mandatory=$True)][ValidateNotNullOrEmpty()][String]$Name
	)
	
	# Create a Custom Object and add the provided Name and Value variables to the object
	$CustomObject = "" | Select-Object -Property  name
	$CustomObject.name = $Name
	
	# Convert the Custom Object to JSON format for use with the API
	$JSONData = $CustomObject | ConvertTo-Json
	
	# Child URL for Adversary Creation
	$APIChildURL = "/v2/groups/threats"
	
	# Generate the appropriate Headers for the API Request
	$AuthorizationHeaders = Get-ThreatConnectHeaders -RequestMethod "POST" -URL $APIChildURL
	
	# Create the URI using System.URI (This fixes the issues with URL encoding)
	$URI = New-Object System.Uri ($Script:APIBaseURL + $APIChildURL)
	
	if ($IndicatorType -eq "URL" -and $Indicator) { [URLFix]::ForceCanonicalPathAndQuery($URI) }
	
	# Query the API
	$Response = Invoke-RestMethod -Method "POST" -Uri $URI -Headers $AuthorizationHeaders -Body $JSONData -ContentType "application/json" -ErrorAction SilentlyContinue
	
	# Verify API Request Status as Success or Print the Error
	if ($Response.Status -eq "Success") {
		$Response.data | Get-Member -MemberType NoteProperty | Where-Object { $_.Name -ne "resultCount" } | Select-Object -ExpandProperty Name | ForEach-Object { $Response.data.$_ }
	} else {
		Write-Verbose "API Request failed with the following error:`n $($Response.Status)"
	}
}

function New-TCSignature {
	<#
	.SYNOPSIS
		Creates a new signature in Threat Connect.
	
	.PARAMETER Name
		Name of the signature to create.
	
	.PARAMETER FileName
		Name of the signature file.
	
	.PARAMETER FileType
		Type of signature to create.  Values are Snort, Suricata, YARA, ClamAV, OpenIOC, CybOX, Bro.
	
	.PARAMETER FileText
		The content of the signature. The content needs to be properly escaped and encoded.
		
	.EXAMPLE
		New-TCSignature -Name <Name> -FileName <FileName.txt> -FileType <FileType> -FileText <FileText>
	#>
	[CmdletBinding()]Param(
		[Parameter(Mandatory=$True)][ValidateNotNullOrEmpty()][String]$Name,
		[Parameter(Mandatory=$True)][ValidateNotNullOrEmpty()][String]$FileName,
		[Parameter(Mandatory=$True)][ValidateSet('Snort','Suricata','YARA','ClamAV','OpenIOC','CybOX','Bro')][String]$FileType,
		[Parameter(Mandatory=$True)][ValidateNotNullOrEmpty()][String]$FileText
	)
	
	# Create a Custom Object and add the provided Name and Value variables to the object
	$CustomObject = "" | Select-Object -Property  name, fileName, fileType, fileText
	$CustomObject.name = $Name
	$CustomObject.fileName = $FileName
	$CustomObject.fileType = $FileType
	$CustomObject.fileText = $FileText
	
	# Convert the Custom Object to JSON format for use with the API
	$JSONData = $CustomObject | ConvertTo-Json
	
	# Child URL for Adversary Creation
	$APIChildURL = "/v2/groups/signatures"
	
	# Generate the appropriate Headers for the API Request
	$AuthorizationHeaders = Get-ThreatConnectHeaders -RequestMethod "POST" -URL $APIChildURL
	
	# Create the URI using System.URI (This fixes the issues with URL encoding)
	$URI = New-Object System.Uri ($Script:APIBaseURL + $APIChildURL)
	
	if ($IndicatorType -eq "URL" -and $Indicator) { [URLFix]::ForceCanonicalPathAndQuery($URI) }
	
	# Query the API
	$Response = Invoke-RestMethod -Method "POST" -Uri ($Script:APIBaseURL + $APIChildURL) -Headers $AuthorizationHeaders -Body $JSONData -ContentType "application/json" -ErrorAction SilentlyContinue
	
	# Verify API Request Status as Success or Print the Error
	if ($Response.Status -eq "Success") {
		$Response.data | Get-Member -MemberType NoteProperty | Where-Object { $_.Name -ne "resultCount" } | Select-Object -ExpandProperty Name | ForEach-Object { $Response.data.$_ }
	} else {
		Write-Verbose "API Request failed with the following error:`n $($Response.Status)"
	}
}

function New-TCAttribute {
	<#
	.SYNOPSIS
		Creates a new attribute in Threat Connect.
	
	.DESCRIPTION
		Must supply a specific "group" for which to add an attribute (Adversary, Email, Incident, Threat, Signature).
	
	.PARAMETER Name
		Name of the Attribute to add
	
	.PARAMETER Value
		Value of the Attribute to add
	
	.PARAMETER AdversaryID
		Adversary ID of the Adversary for which you want to create an attribute
	
	.PARAMETER EmailID
		Email ID of the Email for which you want to create an attribute
	
	.PARAMETER IncidentID
		Incident ID of the Incident for which you want to create an attribute
	
	.PARAMETER ThreatID
		Threat ID of the Threat for which you want to create an attribute
	
	.PARAMETER SignatureID
		Signature ID of the Signature for which you want to create an attribute
		
	.EXAMPLE
		New-TCAttribute -AdversaryID <AdversaryID> -Name Description -Value "Testing Description Creation"
			
	.EXAMPLE
		New-TCAttribute -EmailID <EmailID> -Name Description -Value "Testing Description Creation"
			
	.EXAMPLE
		New-TCAttribute -IncidentID <IncidentID> -Name Description -Value "Testing Description Creation"
			
	.EXAMPLE
		New-TCAttribute -ThreatID <ThreatID> -Name Description -Value "Testing Description Creation"
			
	.EXAMPLE
		New-TCAttribute -SignatureID <SignatureID> -Name Description -Value "Testing Description Creation"
	
	
	#>
	[CmdletBinding()]Param(
		[Parameter(Mandatory=$True,ParameterSetName='AdversaryID')]
			[ValidateNotNullOrEmpty()][int]$AdversaryID,
		[Parameter(Mandatory=$True,ParameterSetName='EmailID')]
			[ValidateNotNullOrEmpty()][int]$EmailID,
		[Parameter(Mandatory=$True,ParameterSetName='IncidentID')]
			[ValidateNotNullOrEmpty()][int]$IncidentID,
		[Parameter(Mandatory=$True,ParameterSetName='ThreatID')]
			[ValidateNotNullOrEmpty()][int]$ThreatID,
		[Parameter(Mandatory=$True,ParameterSetName='SignatureID')]
			[ValidateNotNullOrEmpty()][int]$SignatureID,
		[Parameter(Mandatory=$True)][ValidateNotNullOrEmpty()][String]$Name,
		[Parameter(Mandatory=$True)][ValidateNotNullOrEmpty()][String]$Value
	)
	
	# Create a Custom Object and add the provided Name and Value variables to the object
	$CustomObject = "" | Select-Object -Property  type, value
	$CustomObject.type = $Name
	$CustomObject.value = $Value
	
	# Convert the Custom Object to JSON format for use with the API
	$JSONData = $CustomObject | ConvertTo-Json
	
	# Switch to construct Child URL based on the parameters that were provided
	switch ($PSCmdlet.ParameterSetName) {
		"AdversaryID" {
			$APIChildURL = "/v2/groups/adversaries" + "/" + $AdversaryID + "/attributes"
		}
		
		"EmailID" {
			$APIChildURL = "/v2/groups/emails" + "/" + $AdversaryID + "/attributes"
		}
		
		"IncidentID" {
			$APIChildURL = "/v2/groups/incidents" + "/" + $AdversaryID + "/attributes"
		}
		
		"ThreatID" {
			$APIChildURL = "/v2/groups/threats" + "/" + $AdversaryID + "/attributes"
		}
		
		"SignatureID" {
			$APIChildURL = "/v2/groups/signatures" + "/" + $AdversaryID + "/attributes"
		}
	}
	
	# Generate the appropriate Headers for the API Request
	$AuthorizationHeaders = Get-ThreatConnectHeaders -RequestMethod "POST" -URL $APIChildURL
	
	# Create the URI using System.URI (This fixes the issues with URL encoding)
	$URI = New-Object System.Uri ($Script:APIBaseURL + $APIChildURL)
	
	if ($IndicatorType -eq "URL" -and $Indicator) { [URLFix]::ForceCanonicalPathAndQuery($URI) }
	
	# Query the API
	$Response = Invoke-RestMethod -Method "POST" -Uri $URI -Headers $AuthorizationHeaders -Body $JSONData -ContentType "application/json" -ErrorAction SilentlyContinue
	
	# Verify API Request Status as Success or Print the Error
	if ($Response.Status -eq "Success") {
		$Response.data | Get-Member -MemberType NoteProperty | Where-Object { $_.Name -ne "resultCount" } | Select-Object -ExpandProperty Name | ForEach-Object { $Response.data.$_ }
	} else {
		Write-Verbose "API Request failed with the following error:`n $($Response.Status)"
	}
}

function Set-TCAttribute {
	<#
	.SYNOPSIS
		Modify an Attribute for a group or indicator in Threat Connect. Groups include Adversaries, Emails, Incidents, Threats, Signatures.
	
	.PARAMETER AdversaryID
		Adversary ID of the Adversary for which you want to modify an attribute
	
	.PARAMETER EmailID
		Email ID of the Email for which you want to modify an attribute
	
	.PARAMETER IncidentID
		Incident ID of the Incident for which you want to modify an attribute
		
	.PARAMETER ThreatID
		Threat ID of the Threat for which you want to modify an attribute
		
	.PARAMETER SignatureID
		Signature ID of the Signature for which you want to modify an attribute
	
	.PARAMETER Name
		If you only know the name of the Attribute, you can use this parameter. It will perform Get-TCAttributes to determine the Attribute ID for you.
		Must be used with a group ID.
	
	.PARAMETER Value
		The new value for the attribute
		
	.EXAMPLE
		Set-AdversaryAttribute -AdversaryID <AdversaryID> -Name <AttributeName> -Value <NewValue>
	
	.EXAMPLE
		Set-AdversaryAttribute -EmailID <EmailID> -Name <AttributeName> -Value <NewValue>
	
	.EXAMPLE
		Set-AdversaryAttribute -IncidentID <IncidentID> -Name <AttributeName> -Value <NewValue>
	
	.EXAMPLE
		Set-AdversaryAttribute -ThreatID <ThreatID> -Name <AttributeName> -Value <NewValue>
	
	.EXAMPLE
		Set-AdversaryAttribute -SignatureID <SignatureID> -Name <AttributeName> -Value <NewValue>
	#>
	[CmdletBinding()]Param(
		[Parameter(Mandatory=$True,ParameterSetName='AdversaryIDName')]
		[Parameter(Mandatory=$True,ParameterSetName='AdversaryIDAttributeID')]
			[ValidateNotNullOrEmpty()][String]$AdversaryID,
		[Parameter(Mandatory=$True,ParameterSetName='EmailIDName')]
		[Parameter(Mandatory=$True,ParameterSetName='EmailIDAttributeID')]
			[ValidateNotNullOrEmpty()][String]$EmailID,
		[Parameter(Mandatory=$True,ParameterSetName='IncidentIDName')]
		[Parameter(Mandatory=$True,ParameterSetName='IncidentIDAttributeID')]
			[ValidateNotNullOrEmpty()][String]$IncidentID,
		[Parameter(Mandatory=$True,ParameterSetName='ThreatIDName')]
		[Parameter(Mandatory=$True,ParameterSetName='ThreatIDAttributeID')]
			[ValidateNotNullOrEmpty()][String]$ThreatID,
		[Parameter(Mandatory=$True,ParameterSetName='SignatureIDName')]
		[Parameter(Mandatory=$True,ParameterSetName='SignatureIDAttributeID')]
			[ValidateNotNullOrEmpty()][String]$SignatureID,
		[Parameter(Mandatory=$True,ParameterSetName='AdversaryIDAttributeID')]
		[Parameter(Mandatory=$True,ParameterSetName='EmailIDAttributeID')]
		[Parameter(Mandatory=$True,ParameterSetName='IncidentIDAttributeID')]
		[Parameter(Mandatory=$True,ParameterSetName='ThreatIDAttributeID')]
		[Parameter(Mandatory=$True,ParameterSetName='SignatureIDAttributeID')]
			[ValidateNotNullOrEmpty()][String]$AttributeID,
		[Parameter(Mandatory=$True,ParameterSetName='AdversaryIDName')]
		[Parameter(Mandatory=$True,ParameterSetName='EmailIDName')]
		[Parameter(Mandatory=$True,ParameterSetName='IncidentIDName')]
		[Parameter(Mandatory=$True,ParameterSetName='ThreatIDName')]
		[Parameter(Mandatory=$True,ParameterSetName='SignatureIDName')]
			[ValidateNotNullOrEmpty()][String]$Name,
		[Parameter(Mandatory=$True)][ValidateNotNullOrEmpty()][String]$Value
	)
	
	# Switch to process based on selected parameters
	switch($PSCmdlet.ParameterSetName) {
		"AdversaryIDName" {
			$AttributeInformation = Get-TCAttributes -AdversaryID $AdversaryID | Where-Object { $_.type -eq $Name }
			if ($AttributeInformation -ne $null -and $AttributeInformation -ne "") {
				$APIChildURL = "/v2/groups/adversaries/" + $AdversaryID + "/attributes/" + $AttributeInformation.id
			}
		}
		
		"EmailIDName" {
			$AttributeInformation = Get-TCAttributes -EmailID $EmailID | Where-Object { $_.type -eq $Name }
			if ($AttributeInformation -ne $null -and $AttributeInformation -ne "") {
				$APIChildURL = "/v2/groups/emails/" + $EmailID + "/attributes/" + $AttributeInformation.id
			}
		}
		
		"IncidentIDName" {
			$AttributeInformation = Get-TCAttributes -IncidentID $IncidentID | Where-Object { $_.type -eq $Name }
			if ($AttributeInformation -ne $null -and $AttributeInformation -ne "") {
				$APIChildURL = "/v2/groups/incidents/" + $IncidentID + "/attributes/" + $AttributeInformation.id
			}
		}
		
		"ThreatIDName" {
			$AttributeInformation = Get-TCAttributes -ThreatID $ThreatID | Where-Object { $_.type -eq $Name }
			if ($AttributeInformation -ne $null -and $AttributeInformation -ne "") {
				$APIChildURL = "/v2/groups/threats/" + $ThreatID + "/attributes/" + $AttributeInformation.id
			}
		}
		
		"SignatureIDName" {
			$AttributeInformation = Get-TCAttributes -SignatureID $SignatureID | Where-Object { $_.type -eq $Name }
			if ($AttributeInformation -ne $null -and $AttributeInformation -ne "") {
				$APIChildURL = "/v2/groups/signatures/" + $SignatureID + "/attributes/" + $AttributeInformation.id
			}
		}
		

		"AdversaryIDAttributeID" {
			$APIChildURL = "/v2/groups/adversaries/" + $AdversaryID + "/attributes/" + $AttributeID
		
		}
		
		"EmailIDAttributeID" {
			$APIChildURL = "/v2/groups/emails/" + $EmailID + "/attributes/" + $AttributeID
		}
		
		"IncidentIDAttributeID" {
			$APIChildURL = "/v2/groups/incidents/" + $IncidentID + "/attributes/" + $AttributeID
		}
		
		"ThreatIDAttributeID" {
			$APIChildURL = "/v2/groups/threats/" + $ThreatID + "/attributes/" + $AttributeID
		}
		
		"SignatureIDAttributeID" {
			$APIChildURL = "/v2/groups/signatures/" + $SignatureID + "/attributes/" + $AttributeID
		}
	}
	
	# Create a Custom Object and add the provided Value variable to the object
	$CustomObject = "" | Select-Object -Property value
	$CustomObject.value = $Value
	
	# Convert the Custom Object to JSON format for use with the API
	$JSONData = $CustomObject | ConvertTo-Json
	
	# Generate the appropriate Headers for the API Request
	$AuthorizationHeaders = Get-ThreatConnectHeaders -RequestMethod "PUT" -URL $APIChildURL
	
	# Create the URI using System.URI (This fixes the issues with URL encoding)
	$URI = New-Object System.Uri ($Script:APIBaseURL + $APIChildURL)
	
	# Query the API
	$Response = Invoke-RestMethod -Method "PUT" -Uri $URI -Headers $AuthorizationHeaders -Body $JSONData -ContentType "application/json" -ErrorAction SilentlyContinue
	
	# Verify API Request Status as Success or Print the Error
	if ($Response.Status -eq "Success") {
		$Response.data | Get-Member -MemberType NoteProperty | Where-Object { $_.Name -ne "resultCount" } | Select-Object -ExpandProperty Name | ForEach-Object { $Response.data.$_ }
	} else {
		Write-Verbose "API Request failed with the following error:`n $($Response.Status)"
	}
}


