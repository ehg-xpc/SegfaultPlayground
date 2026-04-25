# Azure DevOps Tips

## Prefer az CLI over ADO MCP server

Always use `az boards` / `az repos` CLI commands (or REST API via curl) instead of the ADO MCP server tools. The MCP server has limited endpoints (no PR threads), unclear field schemas, and less reliable error messages. The az CLI + REST API combo covers everything and is better documented.

## Linking work items to PRs (Artifact Links)

`az boards work-item relation add --relation-type ArtifactLink` does NOT work for artifact links like Pull Request links. The CLI only supports work-item-to-work-item relations (Related, Parent, Child, etc.), even though `ArtifactLink` appears in the valid relation types list.

To link a bug to a PR, use the REST API directly:

```bash
TOKEN=$(az account get-access-token --resource 499b84ac-1321-427f-aa17-267ca6975798 --query accessToken -o tsv)
curl -s -X PATCH "https://dev.azure.com/{org}/{project}/_apis/wit/workitems/{WORK_ITEM_ID}?api-version=7.0" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json-patch+json" \
  -d '[{"op":"add","path":"/relations/-","value":{"rel":"ArtifactLink","url":"vstfs:///Git/PullRequestId/{PROJECT_ID}%2f{REPO_ID}%2f{PR_NUMBER}","attributes":{"name":"Pull Request"}}}]'
```

The `vstfs:///` artifact URI format uses `%2f` (URL-encoded `/`) to separate project ID, repo ID, and PR number.

## az CLI ADO plugin: permission errors when creating PRs

If `az repos pr create` fails with access/permission errors on the `azure-devops` CLI extension, it's likely a Windows file ownership issue on the extension's dist-info directory. Fix with:

```cmd
takeown /F "%USERPROFILE%\.azure\cliextensions\azure-devops\azure_devops-1.0.2.dist-info" /R /D Y
icacls "%USERPROFILE%\.azure\cliextensions\azure-devops\azure_devops-1.0.2.dist-info" /reset /T
icacls "%USERPROFILE%\.azure\cliextensions\azure-devops" /reset /T /Q
```

This takes ownership and resets ACLs on the entire extension directory (~1782 files). The version in the path (`1.0.2`) may differ — check `%USERPROFILE%\.azure\cliextensions\azure-devops\` for the actual dist-info folder name.

## Re-queue PR policy evaluations (draft PRs)

Draft PRs don't auto-trigger builds on push. To re-queue a specific policy evaluation:

1. List evaluations to find the evaluation ID:
```bash
TOKEN=$(az account get-access-token --resource 499b84ac-1321-427f-aa17-267ca6975798 --query accessToken -o tsv)
curl -s "https://dev.azure.com/{org}/{project}/_apis/policy/evaluations?artifactId=vstfs:///CodeReview/CodeReviewId/{PROJECT_ID}/{PR_NUMBER}&api-version=7.0-preview.1" \
  -H "Authorization: Bearer $TOKEN"
```

2. Re-queue by PATCHing the evaluation:
```bash
curl -s -X PATCH "https://dev.azure.com/{org}/{project}/_apis/policy/evaluations/{EVALUATION_ID}?api-version=7.0-preview.1" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" -d '{}'
```

The artifact ID uses the project ID (not repo ID) with the PR number.

## Checking build results programmatically

```bash
# Get build timeline (includes all steps, errors, warnings)
curl -s "https://dev.azure.com/{org}/{project}/_apis/build/builds/{BUILD_ID}/timeline?api-version=7.0" \
  -H "Authorization: Bearer $TOKEN"
```

Filter for `result == 'failed'` records and inspect their `issues` array for error messages.

## az repos pr create: squash merge flag

`--merge-strategy squash` is NOT a valid argument. Use `--squash true` instead.

## Creating work items: iteration path format

The `az boards iteration project list` API returns paths with `\{Project}\Iteration\...` prefix, but the actual `System.IterationPath` field value omits the `Iteration\` segment. Always check an existing work item in the same project to confirm the format before creating items.

## Creating work items: HTML descriptions via az CLI

`az boards work-item create --description` truncates HTML content with special characters. For reliable HTML descriptions, use a Python script with `subprocess.run()` and pass the description via `--fields "System.Description=<html>"`. This avoids shell quoting issues.

Alternatively, create the item first, then update with `az boards work-item update --id {ID} --fields "System.Description=<html>"`.

## Finding current iteration

Query iterations: `az boards iteration project list --org ... --project {Project} --depth 5 -o json`
Then match today's date against `attributes.startDate` / `attributes.finishDate`.
