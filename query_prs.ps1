# Usage examples in comments
<#
.SYNOPSIS
    Queries GitHub repositories for open pull requests by a specific user.

.DESCRIPTION
    This script reads a JSON file containing GitHub repository information and 
    queries each repository for open pull requests created by a specified user.

.PARAMETER Username
    The GitHub username to search for pull requests.

.PARAMETER JsonFile
    Path to the JSON file containing repository information. 
    Defaults to "my-github-repos.json" if not specified.

.PARAMETER GitHubToken
    GitHub personal access token for API authentication.
    If not provided, will use the GITHUB_TOKEN environment variable.

.EXAMPLE
    .\query_prs.ps1 
    defauts to the username hardcoded in the script and uses the default JSON file.
    
.EXAMPLE
    .\query_prs.ps1 -Username "jane-smith" -JsonFile "repos.json"
    
.EXAMPLE
    .\query_prs.ps1 -Username "dev-user" -GitHubToken "ghp_xxxxxxxxxxxx"

.NOTES
    Requires PowerShell 3.0 or later.
    GitHub API rate limits apply (60 requests per hour without token, 5000 with token).
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$Username,
    
    [Parameter(Mandatory=$false)]
    [string]$JsonFile = "my-github-repos.json",
    
    [Parameter(Mandatory=$false)]
    [string]$GitHubToken = $env:GITHUB_TOKEN
)

function Get-GitHubPullRequests {
    param(
        [string]$RepoOwner,
        [string]$RepoName,
        [string]$Username,
        [string]$Token 
    )
    
    $uri = "https://api.github.com/repos/$RepoOwner/$RepoName/pulls?state=open&sort=created&direction=desc"
    
    $headers = @{
        'Accept' = 'application/vnd.github.v3+json'
        'User-Agent' = 'GitHub-PR-Checker-PowerShell'
    }
    
    if ($Token) {
        $headers['Authorization'] = "token $Token"
    }
    
    try {
        $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
        $userPRs = $response | Where-Object { $_.user.login -eq $Username }
        return $userPRs
    }
    catch {
        Write-Host "Error querying $RepoOwner/$RepoName : $($_.Exception.Message)" -ForegroundColor Red
        return @()
    }
}

function Extract-RepoInfo {
    param([string]$RepoUrl)
    
    if ($RepoUrl -match 'github\.com/([^/]+)/([^/]+)') {
        return @{
            Owner = $Matches[1]
            Name = $Matches[2]
        }
    }
    return $null
}

# Main script execution
Write-Host "GitHub Pull Request Checker" -ForegroundColor Cyan
Write-Host "=========================" -ForegroundColor Cyan

# Check if JSON file exists
if (-not (Test-Path $JsonFile)) {
    Write-Host "Error: JSON file '$JsonFile' not found" -ForegroundColor Red
    exit 1
}

# Read and parse JSON file
try {
    $jsonContent = Get-Content $JsonFile -Raw | ConvertFrom-Json
    $repositories = $jsonContent.repositories
}
catch {
    Write-Host "Error parsing JSON file: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "Checking for open pull requests by user: $Username" -ForegroundColor Green
Write-Host ("=" * 60) -ForegroundColor Gray

$totalPRs = 0

foreach ($repo in $repositories) {
    $repoInfo = Extract-RepoInfo -RepoUrl $repo.url
    
    if (-not $repoInfo) {
        Write-Host "Skipping invalid URL: $($repo.url)" -ForegroundColor Yellow
        continue
    }
    
    Write-Host "`nChecking $($repoInfo.Owner)/$($repoInfo.Name)..." -ForegroundColor White
    
    $userPRs = Get-GitHubPullRequests -RepoOwner $repoInfo.Owner -RepoName $repoInfo.Name -Username $Username -Token $GitHubToken
    
    if ($userPRs.Count -eq 0) {
        Write-Host "  No open PRs found for $Username" -ForegroundColor Gray
    }
    else {
        Write-Host "  Found $($userPRs.Count) open PR(s) for $Username :" -ForegroundColor Green
        foreach ($pr in $userPRs) {
            Write-Host "    • #$($pr.number): $($pr.title)" -ForegroundColor White
            Write-Host "      Created: $($pr.created_at)" -ForegroundColor Gray
            Write-Host "      URL: $($pr.html_url)" -ForegroundColor Blue
        }
        $totalPRs += $userPRs.Count
    }
}

Write-Host "`n$("=" * 60)" -ForegroundColor Gray
Write-Host "Summary: Found $totalPRs total open pull requests for $Username" -ForegroundColor Cyan


