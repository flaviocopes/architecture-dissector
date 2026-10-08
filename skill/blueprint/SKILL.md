---
name: blueprint
description: Map an app's architecture for the Architecture Dissector Mac app, with a walkthrough that explains how it works, an overview that explains it in plain words, notes on what travels over each connection, flows for every workflow (what users, the owner and agents do, and what the app does on its own, by area), the data it stores (database tables, collections, JSON files and settings, field by field), and explainers (short videos about parts of the app, which Architecture Dissector plays from scenes you write), keep it current, and save versions, with the blueprint command. Use when asked to add or track an app in Architecture Dissector, map, draw, explain or update an app's architecture, add or improve its walkthrough, overview, component descriptions, connection notes, use cases, user flows or workflows, map its database schema, data model or storage, write explainers or explainer videos about how parts of an app work, record an architecture version or release, map an app's past versions, or after changing the structure, features or stored data of an app that blueprint list shows. Also use it to fill in what's missing across the tracked apps, like the data of every app that has none yet, and to look up how a tracked app is built or what it stores, like its tables and fields, before changing its code.
---

# Architecture Dissector

Architecture Dissector is a Mac app that draws the architecture of your apps, what people do with them, and the data they store, and plays explainers about them. It draws the architecture at three levels: an overview in plain words, the components in depth, and a technical view with every detail and connection note on the chart. Agents write each architecture as JSON with the `blueprint` command, and the app redraws it right away.

Explainers are written, not rendered: you list the scenes and what each one shows, and Architecture Dissector plays them in its own style. Don't make a Remotion project or a video file for them.

1. Run `blueprint guide` and follow it. It has the workflow, the JSON format, what makes a good architecture, and an example.
2. `blueprint list` shows the tracked apps. Inside an app folder, `blueprint status` shows what changed in the code since its architecture was saved.
3. After saving, `blueprint open` shows the app in Architecture Dissector, and `blueprint open --compare <version>` highlights what changed since that version, the schema included.

## Fill in what's missing

`blueprint list` has a MISSING column: the architecture, walkthrough, overview, connection notes, flows, data or explainers an app doesn't have yet. Flows count as missing when there are few of them or some lack an actor or area, so filling them in means mapping every workflow, not only adding the labels. Notes count as missing when most connections have none. When asked to fill in Architecture Dissector, run `blueprint list --missing data --json` (or architecture, walkthrough, overview, notes, flows, explainers) and add that part to every app it lists, one at a time, as `blueprint guide` describes in "Fill in what's missing". Each app's folder is in its path.

Older versions can miss parts too, when they were saved before those parts were mapped. When asked to add them to past versions, read each version's code from the git history and save it back with `--past`, as `blueprint guide` describes in "Fill in older versions".

## Look up an app before changing it

When you work on an app that `blueprint list` shows, read what's already mapped before you search the code:

- `blueprint show --data --json` prints what the app stores: the components that hold data, and every entity with its fields, types, keys, references and the files that define it.
- `blueprint show --json` prints the whole architecture: components and their roles, connections and their notes, the walkthrough, the overview, flows and data.
- `blueprint diff --json` lists what changed since the newest version, entities and fields included. Pass `--from <version>` for another one.

Run `blueprint status` first: if files changed since the save, the map may be behind the code.

If `blueprint` isn't on the PATH, use `/Applications/Architecture Dissector.app/Contents/Helpers/blueprint`. The app's Architecture Dissector → Install Command Line Tool menu item links it into `/usr/local/bin`.
