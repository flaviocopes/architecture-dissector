import Foundation

enum Guide {
  static var text: String {
    let nodeKinds = NodeKind.allCases.map { "  \(Terminal.pad($0.rawValue, 10)) \($0.help)" }.joined(separator: "\n")
    let edgeKinds = EdgeKind.allCases.map { "  \(Terminal.pad($0.rawValue, 10)) \($0.help)" }.joined(separator: "\n")
    let stepKinds = StepKind.allCases.map { "  \(Terminal.pad($0.rawValue, 10)) \($0.help)" }.joined(separator: "\n")
    let actors = FlowActor.allCases.map { "  \(Terminal.pad($0.rawValue, 10)) \($0.help)" }.joined(separator: "\n")
    return """
    # Mapping an app for Architecture Dissector

    Architecture Dissector draws an app's architecture as a diagram and shows how it changed between versions. \
    You write the architecture as JSON and save it with the blueprint command. The Architecture Dissector app redraws it right away.

    ## Map an app for the first time

    1. Run `blueprint list`. If the app isn't there, run `blueprint add <folder>`.
    2. Read the code: the entry points, the modules, where data lives, the services it calls, where each part runs.
    3. Write the architecture as JSON, in the format below, to a file like /tmp/<app>.json.
    4. Run `blueprint set --file /tmp/<app>.json` inside the app folder, or pass the app id: `blueprint set <app> --file ...`.
    5. If it prints errors, fix them and run it again. Warnings are saved anyway, but fix the ones you can.

    ## Update it after you change the app

    1. Run `blueprint status`. It lists the files that changed since the last save, by component, and the changed files no component covers.
    2. Run `blueprint show --json > /tmp/<app>.json` and edit the file. Keep the id of every component and entity that still exists, even when you rename it, and the name of every field, because Architecture Dissector compares versions by them. Update the walkthrough, overview, summaries, details, connection notes, flows, entities and explainers too when what they describe changed. Put new components in the overview block they belong to.
    3. Run `blueprint set --file /tmp/<app>.json`. Save it even when the architecture didn't change, so Architecture Dissector knows it's current.

    ## Save a version when the app ships

    After the architecture matches the release, run `blueprint snapshot --version 1.2.0`. \
    Without --version it uses the git tag on the current commit. `blueprint diff` then shows what changed since the newest version.

    ## Map releases that already shipped

    When asked for an app's history, map its older release tags too, oldest first:

    1. Extract the release without touching the repo: `mkdir -p /tmp/<app>-1.0.0 && git archive v1.0.0 | tar -x -C /tmp/<app>-1.0.0`
    2. Read the code there, and write its architecture. Reuse the ids of the newer architecture for the components and entities that already existed.
    3. Run `blueprint set --file /tmp/<app>-1.0.0.json --version 1.0.0 --past` in the app folder. It saves only that version, at the tag's commit, and leaves the current architecture alone.

    ## Fill in older versions

    Versions saved before an app's flows, data, explainers or overview were mapped don't have them, so the Architecture Dissector app leaves those versions out of the timeline on that tab. To add what an older version misses:

    1. Run `blueprint versions --json` to see the commit of each version, and extract that commit without touching the repo: `mkdir -p /tmp/<app>-1.0.0 && git archive <commit> | tar -x -C /tmp/<app>-1.0.0`. Use the version's tag, like v1.0.0, when it has no commit.
    2. Run `blueprint show --version 1.0.0 --json > /tmp/<app>-1.0.0.json`, and add what's missing from the code you extracted, as this guide describes. Reuse the ids of the current architecture for the flows, entities and blocks that already existed then, and leave the rest of the version as it is.
    3. Run `blueprint set --file /tmp/<app>-1.0.0.json --version 1.0.0 --past` in the app folder. It replaces that version, and leaves the current architecture alone.

    ## Fill in what's missing

    `blueprint list` shows what each app still misses: its architecture, its walkthrough, its overview, notes on its connections (when most have none), its flows (none, too few, or some without an actor or area), its explainers, or the data of an app that stores something. When asked to fill in Architecture Dissector, work through them app by app:

    1. Run `blueprint list --missing data --json`, or --missing architecture, walkthrough, overview, notes, flows or explainers. Each app comes with its id, and its folder in path.
    2. For each app, read the code in its folder, run `blueprint show <id> --json > /tmp/<id>.json`, add what's missing as this guide describes, and save it with `blueprint set <id> --file /tmp/<id>.json`. An app with no architecture yet gets mapped from scratch.
    3. Run the list again, until it says every app has it.

    Keep every id that's already there. Add the missing part, and change the rest only where the code shows it's wrong.

    ## What a good architecture looks like

    - 6 to 30 components. A component is what you'd draw on a whiteboard: a module, a group of screens, an API, a worker, a database, a third-party service. Not every file.
    - Groups say where things run or live: "Mac app", "CLI", "Cloudflare Worker", "Convex backend", "Files on disk", "External services". Put every component in a group, except users.
    - A connection points from the part that starts the interaction to the other one: the caller to the callee, the writer to the database, the user to the app.
    - Labels are 2 to 4 words, starting with a verb: "loads skills", "sends receipts", "stores sessions".
    - tech lists the frameworks, libraries and services it uses, like ["SwiftUI", "FSEvents"].
    - paths lists the files and folders that implement the component, relative to the app folder. Architecture Dissector uses them to show which components changed since the last save, so fill them in for every component that lives in the code.
    - Ids are lowercase with dashes, like app-store, and never change once saved.
    - No secrets, keys or personal data.

    ## Write it for someone new to the app

    People read the architecture in the app to understand how it works, so the words matter as much as the boxes. Keep every text short and plain, and write about this app, not about the technology in general.

    - The app's summary says what the app is and who it's for, in one or two sentences.
    - walkthrough has 3 to 6 steps that walk a newcomer through how the app works, in the order things happen: what starts it, where data goes, what runs in the background. Each step has a title of 2 to 5 words, a text of one or two short sentences, and the ids of the components it involves, so Architecture Dissector can highlight them.
    - A component's summary is its role in this app, in one sentence: what it does here and why the app needs it. "Keeps every day in one SQLite file, and is the only part that writes to it", not "A storage service".
    - details has up to 4 short points, under 15 words each, that make the role precise: what it owns, how it does its job, what depends on it, what to watch out for.

    ## Three levels: overview, in depth, technical

    Architecture Dissector draws the architecture at three levels, and opens on the overview. In Depth is the components and connections. \
    The other two need a part of their own.

    The overview explains the app to someone who has never seen it and doesn't code, as you'd explain it to a curious kid. \
    overview has 3 to 6 blocks, and Architecture Dissector draws an arrow between two blocks wherever their components connect:

    - name says what the block is in plain words, from the reader's side: "You", "The app on your Mac", "The server that sends your emails", "Where your notes are saved".
    - summary says what it does for the reader in one short sentence, with no jargon and no names of technologies: "Keeps every note you write, even when you're offline".
    - nodes lists the components it stands for. A component belongs to one block at most. Cover everything a user's request touches, and leave out build scripts, tests and release tooling.
    - Give the people who use the app a block of their own, like "You".
    - kind is optional: the component kind it's drawn as. Without one, it takes the kind of its first component, so list the main one first.

    The technical view writes each component's role, details, tech and files on its card, and each connection's note next to its arrow. \
    Give every connection a note: what travels over it, how and when, in one or two short sentences under 25 words. \
    Here technical words help: "POST /api/signups with the email as JSON, on every form submit", "Watches the folder with FSEvents and reloads after half a second", "Runs every night at 2:00 from a cron trigger".

    ## Flows: every workflow in the app

    The architecture shows how the app is built. Flows show every workflow that goes through it, each drawn as a flowchart in the app. \
    Map all of them, not only the main ones: a small app has 8 or more, a big one 30 or more. Go looking for each kind:

    - What people using it do, screen by screen and command by command.
    - What its owner does to run it: setup, configuration, deploys, releases, backups and restores, accounts and admin tasks.
    - What agents do through its CLI, API or MCP server.
    - What the app does on its own: scheduled jobs, syncs, update checks, notifications, imports, cleanups, and how it reacts to webhooks or files that change.

    Then, for each flow:

    - actor says whose workflow it is: user, owner, agent or app (see below). Architecture Dissector groups the flows by it.
    - area is the part of the app it belongs to, in 1 to 3 words: "Editor", "Sync", "Billing", "Releases". Reuse a handful of areas, usually 3 to 8, so flows of the same part sit together.
    - One flow per workflow, named the way its actor would say it: "Write today's note", "Restore a backup", "Let an agent add a todo", "Send the morning digest".
    - goal is the need behind it, in one sentence from the actor's side: "Jot down what you're working on before you forget".
    - Each flow has 3 to 10 steps, in order. A step's title says what happens in a few words ("Paste a link"), and its text adds what the person sees or what to know, in one short sentence.
    - kind says what the step is: action, system, decision or done (see below). End every flow on a done step.
    - lane says who does the step: "You", the app's name, "Agent", "GitHub". Keep it to 2 to 4 lanes per flow.
    - nodes lists the components that make the step happen, so people can jump from a step to the architecture.
    - Steps follow the order they're listed in. A decision lists where each choice goes in next, with labels: [{ "to": "step id", "label": "already running" }]. Any step can use next to jump or loop.
    - Ids are lowercase with dashes, unique among the flows, and step ids unique within their flow.

    ## Data: what the app stores

    entities lists what the app keeps: database tables, Convex or Firestore collections, JSON files, groups of settings, Keychain items. \
    Architecture Dissector draws them as a schema, field by field, and shows how the schema changed between versions.

    - One entity per kind of record. Leave out caches the app can rebuild, unless they help explain how it works.
    - store is the id of the component that holds it, usually a database or storage component.
    - name is what the code calls it: the table name, the file name like state.json, or the type name.
    - summary says what one record is, in one sentence: "One row per email on a product's waiting list".
    - fields lists what each record holds, in the order the code defines it. name is the name in the code, type is the type as the code writes it (text, integer, timestamp, String?, [Note]). Set "key": true on the field that identifies a record, "ref" to the id of the entity a field points to (a foreign key, or a list or object of another entity it holds), and a note of a few words when the name doesn't say enough.
    - details has up to 4 short points: what writes it, when it's cleaned up, how it migrates, what to watch out for.
    - paths lists the files that define it: the migration, the schema, the model type.
    - Entity ids never change once saved, and neither do field names unless the code renames the field. Architecture Dissector compares entities by id and fields by name, so a migration shows up as fields added, removed or changed.

    ## Explainers: short videos about parts of the app

    explainers are short videos that explain one part of the app each. You write what every scene shows and says. \
    Architecture Dissector plays them in the same style for every app: it opens with the title, moves the camera to what each scene shows on the real diagrams, highlights it, captions it, times each scene to its text, and adds the sound effects.

    - 2 to 6 explainers, each about something a newcomer would ask: "How a note gets saved", "What happens when you ship a release", "Where your settings live".
    - summary says what you learn from it, in one sentence.
    - 3 to 8 scenes, in the order things happen, from the big picture down to the detail.
    - A scene's title has 2 to 5 words, and its text one or two short sentences, under 30 words, about what's on screen.
    - Each scene shows one thing: components (nodes), steps of a flow (flow, and steps to highlight some of them), or entities. A scene that shows none of them is a title card, for an opening question or a closing point.
    - Show a few things at a time. The camera zooms to fit what a scene lists, so 1 to 4 components or entities read best.
    - Ids are lowercase with dashes and unique among the explainers.

    ## Format

    {
      "name": "the app's name",
      "summary": "what the app is and who it's for",
      "walkthrough": [{ "title": "...", "text": "...", "nodes": ["node ids"] }],
      "overview": [{ "id": "...", "name": "plain words", "summary": "what it does for you", "kind": "optional, a component kind", "nodes": ["node ids"] }],
      "groups": [{ "id": "...", "name": "...", "summary": "optional" }],
      "nodes": [{
        "id": "...", "name": "...", "kind": "one of the kinds below", "group": "a group id",
        "summary": "its role in the app", "details": ["..."], "tech": ["..."], "paths": ["..."]
      }],
      "edges": [{ "from": "a node id", "to": "a node id", "label": "...", "kind": "calls, reads, writes or sends", "note": "what travels over it, how and when" }],
      "flows": [{
        "id": "...", "title": "...", "goal": "the need, from the actor's side", "actor": "user, owner, agent or app", "area": "the part of the app",
        "steps": [{ "id": "...", "title": "...", "text": "...", "kind": "action", "lane": "You", "nodes": ["node ids"], "next": [{ "to": "step id", "label": "..." }] }]
      }],
      "entities": [{
        "id": "...", "name": "...", "store": "a node id", "summary": "what one record is", "details": ["..."], "paths": ["..."],
        "fields": [{ "name": "...", "type": "...", "key": true, "ref": "an entity id", "note": "..." }]
      }],
      "explainers": [{
        "id": "...", "title": "...", "summary": "what you learn from it",
        "scenes": [
          { "title": "...", "text": "...", "nodes": ["node ids"] },
          { "title": "...", "text": "...", "flow": "a flow id", "steps": ["step ids"] },
          { "title": "...", "text": "...", "entities": ["entity ids"] },
          { "title": "...", "text": "..." }
        ]
      }]
    }

    Component kinds:
    \(nodeKinds)

    Connection kinds:
    \(edgeKinds)

    Step kinds:
    \(stepKinds)

    Flow actors:
    \(actors)

    ## Example

    {
      "name": "Waiting Lists",
      "summary": "A site where makers collect signups for products they haven't launched yet.",
      "walkthrough": [
        { "title": "A visitor signs up", "text": "The landing page posts the form to the Signup API, which checks the email.", "nodes": ["visitor", "pages", "signup-api"] },
        { "title": "The signup is stored", "text": "Each signup becomes one row in D1, so a maker can export the list.", "nodes": ["signup-api", "db"] },
        { "title": "The visitor gets an email", "text": "Resend sends a confirmation, so the list only has real addresses.", "nodes": ["signup-api", "resend"] }
      ],
      "overview": [
        { "id": "you", "name": "You", "summary": "Find a product you like and leave your email", "nodes": ["visitor"] },
        { "id": "website", "name": "The website", "summary": "Shows each product with a form to join its list", "nodes": ["pages"] },
        { "id": "list-keeper", "name": "The list keeper", "summary": "Checks every email and keeps one list per product", "kind": "database", "nodes": ["signup-api", "db"] },
        { "id": "mail", "name": "The email service", "summary": "Sends you a note to confirm you're on the list", "nodes": ["resend"] }
      ],
      "groups": [
        { "id": "site", "name": "Astro site" },
        { "id": "cloudflare", "name": "Cloudflare" },
        { "id": "services", "name": "External services" }
      ],
      "nodes": [
        { "id": "visitor", "name": "Visitor", "kind": "user", "summary": "Signs up for a waiting list" },
        { "id": "pages", "name": "Landing pages", "kind": "client", "group": "site", "summary": "Shows each product and collects signups with one form", "tech": ["Astro"], "paths": ["src/pages/index.astro", "src/components"] },
        { "id": "signup-api", "name": "Signup API", "kind": "api", "group": "cloudflare", "summary": "The only way into the list: checks every signup before storing it",
          "details": ["Rejects duplicates and disposable emails", "Rate limits by IP", "Sends the confirmation after the insert succeeds"],
          "tech": ["Cloudflare Workers"], "paths": ["src/pages/api"] },
        { "id": "db", "name": "Database", "kind": "database", "group": "cloudflare", "summary": "Holds the products and every signup, one row each", "tech": ["D1"], "paths": ["migrations"] },
        { "id": "resend", "name": "Resend", "kind": "external", "group": "services", "summary": "Delivers the confirmation email" }
      ],
      "edges": [
        { "from": "visitor", "to": "pages", "label": "opens", "note": "A static page per product, served from Cloudflare's cache" },
        { "from": "pages", "to": "signup-api", "label": "posts the form", "note": "POST /api/signups with the product slug and email as JSON, on submit" },
        { "from": "signup-api", "to": "db", "label": "inserts signup", "kind": "writes", "note": "One INSERT per signup, after the duplicate check on product_id and email" },
        { "from": "signup-api", "to": "resend", "label": "sends confirmation", "kind": "sends", "note": "Resend's REST API, called after the insert commits, without waiting for delivery" }
      ],
      "flows": [
        {
          "id": "join-a-list", "title": "Join a waiting list", "goal": "Hear about a product the day it launches", "actor": "user", "area": "Signups",
          "steps": [
            { "id": "open", "title": "Open the product page", "kind": "action", "lane": "Visitor", "nodes": ["visitor", "pages"] },
            { "id": "submit", "title": "Enter an email", "text": "One field, no account needed.", "kind": "action", "lane": "Visitor", "nodes": ["pages"] },
            { "id": "check", "title": "Already on the list?", "kind": "decision", "lane": "Waiting Lists", "nodes": ["signup-api", "db"],
              "next": [{ "to": "store", "label": "new email" }, { "to": "known", "label": "already signed up" }] },
            { "id": "store", "title": "The signup is saved", "kind": "system", "lane": "Waiting Lists", "nodes": ["signup-api", "db"] },
            { "id": "email", "title": "A confirmation arrives", "text": "Sent by Resend within a minute.", "kind": "system", "lane": "Waiting Lists", "nodes": ["resend"], "next": [{ "to": "done" }] },
            { "id": "known", "title": "The page says you're already in", "kind": "system", "lane": "Waiting Lists", "nodes": ["pages"], "next": [{ "to": "done" }] },
            { "id": "done", "title": "You're on the list", "kind": "done", "lane": "Visitor" }
          ]
        },
        {
          "id": "export-a-list", "title": "Export a waiting list", "goal": "Email everyone on the list when the product launches", "actor": "owner", "area": "Lists",
          "steps": [
            { "id": "run", "title": "Run the export command", "text": "wrangler d1 execute with the export query.", "kind": "action", "lane": "Maker", "nodes": ["db"] },
            { "id": "rows", "title": "D1 returns the rows", "kind": "system", "lane": "Cloudflare", "nodes": ["db"] },
            { "id": "done", "title": "A CSV of every email", "kind": "done", "lane": "Maker" }
          ]
        },
        {
          "id": "send-confirmation", "title": "Send the confirmation", "goal": "Only keep emails that really exist", "actor": "app", "area": "Signups",
          "steps": [
            { "id": "insert", "title": "A signup is inserted", "kind": "system", "lane": "Waiting Lists", "nodes": ["signup-api", "db"] },
            { "id": "send", "title": "Resend sends the email", "kind": "system", "lane": "Resend", "nodes": ["resend"] },
            { "id": "done", "title": "The email is in the inbox", "kind": "done", "lane": "Resend" }
          ]
        }
      ],
      "entities": [
        { "id": "product", "name": "products", "store": "db", "summary": "One row per product a maker collects signups for", "paths": ["migrations/0001_products.sql"],
          "fields": [
            { "name": "id", "type": "integer", "key": true },
            { "name": "slug", "type": "text", "note": "unique, used in the page URL" },
            { "name": "name", "type": "text" },
            { "name": "launched_at", "type": "timestamp", "note": "empty until launch day" }
          ] },
        { "id": "signup", "name": "signups", "store": "db", "summary": "One row per email on a product's waiting list",
          "details": ["Written only by the Signup API", "Unique on product_id and email"], "paths": ["migrations/0002_signups.sql"],
          "fields": [
            { "name": "id", "type": "integer", "key": true },
            { "name": "product_id", "type": "integer", "ref": "product" },
            { "name": "email", "type": "text", "note": "lowercased" },
            { "name": "created_at", "type": "timestamp" }
          ] }
      ],
      "explainers": [
        {
          "id": "how-a-signup-is-saved", "title": "How a signup is saved", "summary": "What happens between the form and the confirmation email",
          "scenes": [
            { "title": "One form, one field", "text": "A visitor types an email on the product page and sends the form.", "nodes": ["visitor", "pages"] },
            { "title": "The API checks it", "text": "The Signup API rejects duplicates and disposable emails before anything is stored.", "flow": "join-a-list", "steps": ["check"] },
            { "title": "One row per signup", "text": "Each signup is a row that points to its product, unique per email.", "entities": ["signup", "product"] },
            { "title": "Then the email", "text": "Resend sends the confirmation only after the insert succeeds.", "nodes": ["signup-api", "resend"] }
          ]
        }
      ]
    }
    """
  }
}
