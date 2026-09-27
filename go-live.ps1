[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-Location -LiteralPath $PSScriptRoot

function Write-Step([string]$Text) {
  Write-Host ""
  Write-Host "=== $Text ===" -ForegroundColor Cyan
}

function Require-Command([string]$Name) {
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "Required program not found: $Name"
  }
}

Write-Host "Interactive presentation publishing" -ForegroundColor Green
Write-Host "The Supabase secret will never be committed to GitHub."

Require-Command "git"
Require-Command "gh"
Require-Command "npx.cmd"

Write-Step "1. Check GitHub login"
& gh auth status
if ($LASTEXITCODE -ne 0) {
  throw "Sign in first: gh auth login --hostname github.com --git-protocol https --web --clipboard"
}

$repositoryName = Read-Host "Public repository name [gamification-live]"
if ([string]::IsNullOrWhiteSpace($repositoryName)) { $repositoryName = "gamification-live" }
if ($repositoryName -notmatch '^[A-Za-z0-9._-]+$') {
  throw "The repository name contains invalid characters."
}

$origin = (& git remote get-url origin 2>$null)
if ([string]::IsNullOrWhiteSpace($origin)) {
  Write-Host "Creating a public repository and uploading the local files..."
  & gh repo create $repositoryName --public --source . --remote origin --push --description "Interactive presentation about gamification"
  if ($LASTEXITCODE -ne 0) { throw "Could not create the GitHub repository." }
} else {
  Write-Host "Repository is already connected: $origin"
  & git push -u origin main
  if ($LASTEXITCODE -ne 0) { throw "Could not upload the files to GitHub." }
}

$repository = (& gh repo view --json nameWithOwner --jq .nameWithOwner).Trim()
if ([string]::IsNullOrWhiteSpace($repository)) { throw "Could not identify the repository URL." }

& gh api "repos/$repository/pages" *> $null
if ($LASTEXITCODE -ne 0) {
  $pagesBody = @{ build_type = "legacy"; source = @{ branch = "main"; path = "/" } } | ConvertTo-Json -Compress
  $pagesBody | & gh api --method POST "repos/$repository/pages" --input - *> $null
  if ($LASTEXITCODE -ne 0) {
    throw "Could not enable GitHub Pages. Enable Settings > Pages > Deploy from a branch > main > /(root)."
  }
}
Write-Host "GitHub Pages is enabled."

Write-Step "2. Connect Supabase"
Write-Host "Before continuing, create a free project at https://database.new"
Write-Host "Wait until the project status says it is ready."
Read-Host "Press Enter when the project is ready"

& npx.cmd --yes supabase@latest projects list *> $null
if ($LASTEXITCODE -ne 0) {
  Write-Host "Supabase will now ask you to sign in or paste a Personal Access Token."
  & npx.cmd --yes supabase@latest login
  if ($LASTEXITCODE -ne 0) { throw "Supabase login was not completed." }
}

$projectRef = Read-Host "Supabase Project ref (Settings > General > Reference ID)"
if ($projectRef -notmatch '^[a-z0-9]{10,32}$') { throw "The Project ref does not look valid." }

& npx.cmd --yes supabase@latest link --project-ref $projectRef
if ($LASTEXITCODE -ne 0) { throw "Could not link the Supabase project." }

Write-Host "Checking the database migration..."
& npx.cmd --yes supabase@latest db push --dry-run
if ($LASTEXITCODE -ne 0) { throw "The database check failed." }

Write-Host "Creating the tables and the server-side cooldown..."
& npx.cmd --yes supabase@latest db push
if ($LASTEXITCODE -ne 0) { throw "Could not apply the database migration." }

$presenterToken = ([guid]::NewGuid().ToString("N") + [guid]::NewGuid().ToString("N"))
& npx.cmd --yes supabase@latest secrets set "PRESENTER_TOKEN=$presenterToken" --project-ref $projectRef
if ($LASTEXITCODE -ne 0) { throw "Could not save the presenter code." }

Write-Host "Deploying the server function..."
& npx.cmd --yes supabase@latest functions deploy presentation-api --no-verify-jwt --project-ref $projectRef --use-api
if ($LASTEXITCODE -ne 0) { throw "Could not deploy the server function." }

$publishableKey = Read-Host "Supabase Publishable key (Connect > Publishable key)"
if ([string]::IsNullOrWhiteSpace($publishableKey)) { throw "The Publishable key is required." }

$projectUrl = "https://$projectRef.supabase.co"
$config = @"
window.PRESENTATION_CONFIG = {
  syncEnabled: true,
  supabaseUrl: "$projectUrl",
  supabasePublishableKey: "$publishableKey",
  defaultRoomId: "gamification-live"
};
"@
Set-Content -LiteralPath (Join-Path $PSScriptRoot "presentation-config.js") -Value $config -Encoding utf8
Set-Content -LiteralPath (Join-Path $PSScriptRoot "presenter-code.txt") -Value $presenterToken -Encoding utf8

Write-Step "3. Final publish"
& git add presentation-config.js
& git commit -m "Enable live presentation"
if ($LASTEXITCODE -ne 0) { throw "Could not save the public configuration." }
& git push
if ($LASTEXITCODE -ne 0) { throw "Could not upload the final configuration." }

$parts = $repository.Split('/')
$owner = $parts[0]
$repo = $parts[1]
$baseUrl = "https://$owner.github.io/$repo/"
$audienceUrl = "${baseUrl}?room=gamification-live"
$presenterUrl = "${baseUrl}?room=gamification-live&presenter=1"

Write-Host ""
Write-Host "DONE" -ForegroundColor Green
Write-Host "Audience:  $audienceUrl"
Write-Host "Presenter: $presenterUrl"
Write-Host "Presenter code saved locally at: $(Join-Path $PSScriptRoot 'presenter-code.txt')"
Write-Host "Presenter code: $presenterToken" -ForegroundColor Yellow
Write-Host ""
Write-Host "GitHub Pages may need a few minutes to update."
