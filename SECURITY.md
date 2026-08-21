# Security policy

## Supported versions

| Version | Supported |
|---|---|
| latest release (`update.affectiion.ru/latest.json`) | yes |
| previous release | security fixes only |
| anything older | best effort, no guarantee |

The Linux client checks for updates on every start; staying on the latest
release is the safest path.

## Reporting a vulnerability

Please **do not** open a public issue for security problems — that
notifies attackers before a fix is out.

Send a private report instead:

1. GitHub: **Settings → Security → Advisories → "New draft security advisory"**
   (preferred — keeps the conversation in GitHub's private channel).
2. Or email the address listed on the GitHub profile page.

Please include:

- the affected version (output of `affection-vpn --version` or similar),
- reproduction steps,
- impact (what can an attacker do),
- how you found it.

I aim to acknowledge within 7 days and ship a fix within 30 days for
anything rated High or Critical. You are welcome to coordinate public
disclosure timing — I won't disclose a CVE on the timeline you set.

## Out of scope

- "I'd like this feature" / "please add X": not a vulnerability, use
  regular issues or discussions.
- Reports against the upstream VPN protocol (Xray/VLESS) or any
  third-party component: please report upstream.
