# MegaMicro Conductor Handoff

## Current state

MegaMicro can discover local Conductor workspaces and assign them to RGB keys. It reads each workspace's project name, city name, local path, and UUID from Conductor's local database.

Pressing an assigned Conductor key currently activates the Conductor desktop app. It cannot reliably select the exact assigned workspace.

Ghostty targeting is working: assigned keys can focus the correct terminal tab or pane.

## Blocker

Conductor does not currently expose a supported way to activate an existing local workspace by UUID.

The documented `conductor://` links do not solve this:

- `prompt` and `async` create new workspaces.
- `prompt` with `path` selects a repository but still creates a workspace.
- `linear_id` only targets work associated with a Linear issue.
- The copied HTTPS workspace URL opens Conductor's cloud application, not the local desktop workspace.
- Passing an unsupported UUID parameter to `conductor://` can create an unintended workspace.

Do not use the HTTPS workspace URL or guess undocumented `conductor://` parameters.

## Request for Conductor

We need a supported local deep link or CLI command that activates an existing desktop workspace by UUID, for example:

```text
conductor://workspace_id=<uuid>
```

or:

```text
conductor open-workspace <uuid>
```

It should activate Conductor, select the exact existing local workspace, work when the app is hidden or behind another app, never create a workspace or open the cloud app, and report a clear error for an unknown UUID.

## Resume plan

When Conductor provides this capability:

1. Update `AgentFocusService.focusConductorWorkspace` to invoke the supported deep link or CLI with the UUID already resolved by `conductorWorkspaceID`.
2. Retain simple Conductor app activation as the fallback when the UUID cannot be found or the command fails.
3. Test with at least two workspaces in different projects while Conductor is behind another application.
4. Verify that each assigned dashboard key always selects its corresponding workspace and never creates a new workspace.

## Relevant code

- `MegaMicro/Services/AgentFocusService.swift`
- `MegaMicro/App/AppState.swift`

