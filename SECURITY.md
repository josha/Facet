# Security policy

## Reporting a vulnerability

Report it privately, through GitHub's **private vulnerability reporting** on this
repository: open the **Security** tab and choose **Report a vulnerability**. That
opens a report only the maintainer can see.

Do not open a public issue, and do not post the details in a discussion or a pull
request. If you cannot use the GitHub form, e-mail the maintainer at
**facetframework@gmail.com** with the same private care.

A useful report contains what you tried, what happened, the smallest reproduction
you have, the value of `Facet.VERSION` you saw it on, and the Roblox client or
Studio version if the behavior depends on it.

## What to expect

Facet is maintained by one person, and this project makes no service-level
promise. Honestly stated: you should expect an acknowledgement within about a
week, and a fix or an explanation of why the report is not a vulnerability once
the maintainer has reproduced it. If a week passes with no reply, send a follow-up
on the same private report rather than making it public.

When a report leads to a fix, the release notes will describe the problem and
credit the reporter, unless the reporter asks not to be named.

## Supported versions

| Version | Supported |
|---|---|
| The latest published release | Yes |
| Anything earlier | No |

Facet is pre-1.0 and moves forward rather than backward. Fixes land on the latest
release; there are no maintenance branches for older versions. Upgrade first, then
report if the problem is still there.

## What is in scope

Facet is a **client-side** user-interface library. It draws screens, reads input,
and holds display state on the player's own device. It never validates a game's
rules, and it must never be the thing that decides whether a player is allowed to
do something.

In scope, and worth reporting:

- Code in this repository that executes something a caller did not intend, for
  example a data path that reaches `loadstring` or requires an asset by an
  attacker-supplied id.
- A way for one player's client to make Facet leak or alter state that belongs to
  another player.
- A defect in an input, focus, or presentation path that makes a control act on a
  gesture the player did not make.
- Anything in the build, package, or release tooling that could publish material a
  maintainer did not approve.

Out of scope, because it describes how Roblox works rather than a defect in Facet:

- A player editing values on their own client. Every Roblox client is under its
  owner's control, which is why the server owns the truth. See
  [guide 6](docs/guide/06-client-server.md).
- A game that trusts a client-side Facet value instead of validating it on the
  server. That is a defect in the game, and guide 6 is the page that says so.
- A report that Facet cannot stop a player from seeing data the game already
  replicated to their client.
