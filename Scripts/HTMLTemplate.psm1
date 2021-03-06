# HTML::Template::PS
# HTML::Template re-implemented in PowerShell 
# Original by http://sam.tregar.com/, found at http://search.cpan.org/~samtregar/
#
# Copyright Ian Gibbs 2010-2011 		flash666@yahoo.com
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
	
$version = '0.2.3'
$error_action = 'stop'                          # What the script should do when any action fails
$supported_tags = 'VAR|LOOP|IF|ELSE|UNLESS'

Function replaceElements($line, $params)
{
	$tags = $true

	# Make a record of whether params were all referenced or not, so we can carp if user
	# set a variable that could not be found in the template
	# $used_params = @{}
	# foreach($key in $params.Keys)
	# {
		# $used_params[$key] = $false
	# }
	
	while($tags -eq $true)
	{
		$options = [Text.RegularExpressions.RegExOptions]::IgnoreCase
		$tagMatchRegexp = New-Object -TypeName Text.RegularExpressions.Regex -ArgumentList $('<TMPL_(' + $supported_tags + ') NAME="*(\w+)"*>'),$options
		$matches = $tagMatchRegexp.Match($line)
		if(!$matches.Success)
		{
			$tags = $false

		}
		else
		{
			$tag = $matches.Groups[0].Value
			$type = $matches.Groups[1].Value
			$name = $matches.Groups[2].Value.ToLower()
			$location = $matches.Index
			$new_text = ""
			if($this.debug) { Write-Host "TAG $tag TYPE $type NAME $name" }
			if($type -imatch 'VAR')
			{
				# If we get passed DB values, and they are empty, you end up with
				# System.DBNull which Replace() doesn't know how to deal with. Call
				# ToString() on everything to make sure we only send strings to the output
				$new_text = ""
				if($params.ContainsKey($name))
				{
					$value = $params[$name]
					if($value -eq $null) { $value = "" }	# replace null with empty string to 
					$new_text = $value.ToString()			# prevent <- this from barfing
					# $used_params[$name] = $true
				}
				if($this.debug) { Write-Host "`tNEW_TEXT $new_text" }
				$tagReplaceRegexp = New-Object -TypeName Text.RegularExpressions.Regex -ArgumentList $tag,$options
				$line = $tagReplaceRegexp.Replace($line, $new_text, 1)
			}
			elseif($type -imatch 'LOOP')
			{
				# Assess the loop
				$loop = findClosingTag $line "/LOOP" ($location + $tag.Length) $tag
				$loop_items = @()
				if($params.ContainsKey($name))
				{
					$loop_items = $params[$name]
				}
				foreach($item in $loop_items)
				{
					$new_text = $new_text + (replaceElements $loop["contents"] $item)  # recursively resolve any
																					# elements inside the loop
					# $used_params[$name] = $true
				}
				$pre_tag = $line.substring(0, $location)
				$post_tag = $line.substring($loop["END_CLOSING_TAG"], $line.Length - $loop["END_CLOSING_TAG"])
				$line =  $pre_tag + $new_text + $post_tag
			}
			elseif($type -imatch 'IF' -Or $type -imatch 'UNLESS')
			{
				# Assess the conditional item
				$conditional = findClosingTag $line "/$type" ($location + $tag.Length) $tag
				# Is there an else, and is it before the closing tag (don't get confused by elses from further on in the text!)?
				$else = findClosingTag $line "ELSE" ($location + $tag.Length) $tag
				if($else["END_CLOSING_TAG"] -gt $conditional["START_CLOSING_TAG"])
				{
					$else["FOUND"] = $false
				}
				
				# Set the failure and success text according to if/else/unless
				if(!$else["FOUND"])
				{
					if($type -imatch 'IF')
					{
						$success_text = $conditional["contents"]
						$failure_text = ""
					}
					else
					{
						$failure_text = $conditional["contents"]
						$success_text = ""
					}
				}
				else
				{
					if($type -imatch 'IF')
					{
						$success_text = $else["contents"]
						$failure_text = $line.substring($else["END_CLOSING_TAG"], $conditional["START_CLOSING_TAG"] - $else["END_CLOSING_TAG"])
					}
					else
					{
						$failure_text = $else["contents"]
						$success_text = $line.substring($else["END_CLOSING_TAG"], $conditional["START_CLOSING_TAG"] - $else["END_CLOSING_TAG"])
					}
				}
				if($this.debug)
				{ 
					Write-Host "`tSUCCESS '$success_text'"
					Write-Host "`tFAILURE '$failure_text'"
					Write-Host "`tVALUE" $params[$name]
				}
				
				# Do a boolean conditional test on the param
				if($params[$name])
				{
					$new_text = $success_text
				}
				else
				{
					$new_text = $failure_text
				}
				if($this.debug) { Write-Host "`tNEW_TEXT $new_text" }
				$pre_tag = $line.substring(0, $location)
				$post_tag = $line.substring($conditional["END_CLOSING_TAG"], $line.Length - $conditional["END_CLOSING_TAG"])
				$line =  $pre_tag + $new_text + $post_tag
			}
			else
			{
				throw "html-template-ps: Unknown tag TMPL_$type"
			}
			#Write-Host $line
		}
	}

	# All is well
	return $line
}

# $line is the string to be searched
# $tag is the searched for. Provide the tag on its own if it is interrupting, like <TMPL_ELSE> after <TMPL_IF>
# [ie provide "ELSE"], or prefix it with a forward slash if it is closing, like </TMPL_IF> after <TMPL_IF>
# [ie provide "/IF"]
Function findClosingTag
{
	param([string]$line, [string]$tag, [int]$startIndex, [string]$openingTag)
	
	# Is it an interrupting tag?
	$search = ""
	if($tag.StartsWith("/"))
	{
		$search = "</TMPL_" + $tag.Substring(1) + ">"
	}
	else
	{
		$search = "<TMPL_" + $tag + ">"
	}
	$ifCloseRegexp = New-Object -TypeName Text.RegularExpressions.Regex -ArgumentList $search,$options
	$close_tag_matches = $ifCloseRegexp.Match($line, $startIndex)
	if(!$close_tag_matches.Success)
	{
		if($tag.StartsWith("/"))	# If it's a closing tag, then it must be present for the markup to be valid
		{
			throw "html-template-ps: <TMPL_" + $tag.Substring(1) + "> without closing </TMPL_" + $tag.Substring(1) + "> (" + $openingTag + ")"
		}
		else						# Otherwise it's optional (such as TMPL_ELSE)
		{
			return @{'FOUND' = $false}
		}
	}
	$start_close_tag = $close_tag_matches.Index
	$end_close_tag = $start_close_tag + 7 + $tag.Length
	$contents = $line.Substring($startIndex, $start_close_tag - $startIndex)
	return @{'FOUND' = $true; 'CONTENTS' = $contents; 'START_CLOSING_TAG' = $start_close_tag; 'END_CLOSING_TAG' = $end_close_tag}
}

<# 
 .Synopsis
  Uses template files to generate output based on data structures.

 .Description
  A re-implementation of the perl CPAN module HTML::Template. Used to 
  separate form from function. You can generate data structures in PowerShell, 
  write a template file with placeholders for the data, and then call this 
  module to generate the output. Ideal for creating HTML output from PowerShell
  without embedding the HTML into the program, making it easy for others
  to change the look of the output.

 .Parameter Params
  A hashtable of parameters that configure the new object and control the way 
  it behaves. Currently supported are:
		filename		Set to a string that lists the path to the template 
						file to be used to generate output


 .Example
	# Initialise a HTML template object
	$tmpl = New-HTMLTemplate @{ filename = "c:\test.tmpl"; }
	# Add a scalar element (TMPL_VAR)
	$tmpl.param("title","State Report")
	# Add a repeaing element, as might be displayed in a table (TMPL_LOOP)
	$tmpl.param("table", @( @{FRUIT = "apple"}, @{FRUIT = "orange"}, @{FRUIT = "banana"} ))
	# Generate the output
	Write-Output $tmpl.output()
#>
Function New-HTMLTemplate([hashtable]$params)
{
	if(!$params)
	{
		throw "html-template-ps: no parameters specified"
    }
    if($params["filename"].Length -lt 1)
    {
        throw "html-template-ps: prequired parameter 'filename' not specified"
    }
    if(!(Test-Path $params["filename"]))
    {
        throw $("html-template-ps: template file " + $params["filename"] + " does not exist")
    }
    
    $content = (Get-Content $params["filename"] | Out-String)
   
    $template = New-Object -typeName System.Object
    Add-Member -InputObject $template -MemberType NoteProperty -Name filename -Value $params["filename"]
    Add-Member -InputObject $template -MemberType NoteProperty -Name debug -Value $params["debug"]
    Add-Member -InputObject $template -MemberType NoteProperty -Name params -Value @{}
    Add-Member -InputObject $template -MemberType NoteProperty -Name template -Value $content
    Add-Member -InputObject $template -MemberType NoteProperty -Name version -Value $version
    Add-Member -InputObject $template -MemberType ScriptMethod -Name output -Value {
        return replaceElements $this.template $this.params
    }
    Add-Member -InputObject $template -MemberType ScriptMethod -Name param -Value {
        $key = $args[0].ToLower()
        $value = $args[1]
		# TODO: Deal with loops
		$options = [Text.RegularExpressions.RegExOptions]::IgnoreCase
		$pattern = $('<TMPL_(' + $supported_tags + ') NAME="*' + $key + '"*>')
		$tagMatchRegexp = New-Object -TypeName Text.RegularExpressions.Regex -ArgumentList $pattern,$options
		$matches = $tagMatchRegexp.Match($this.template)
		if($matches.Success)
		{
			$this.params[$key] = $value
			#Write-Host "Found param $key"
		}
		else
		{
			throw "html-template-ps: Attempt to set nonexistent parameter '$key' - this parameter name doesn't match any declarations in the template file"
		}
	}

    return $template
}
Export-ModuleMember -function New-HTMLTemplate
