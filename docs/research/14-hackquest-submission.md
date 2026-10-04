# 14 - HackQuest submission: registration status, form fields, rules, deadlines (R7 / E11-T1)

Read on **2026-10-03 14:23 to 14:35 UTC (21:23 to 21:35 WIB, 22:23 to 22:35 SGT)** from the user's machine. Sources are the live buildathon page, HackQuest's public GraphQL API (`https://api.hackquest.io/graphql`, no login), the page's public JS chunks, the Internet Archive and public blog posts. No login, signup, form submission or CAPTCHA was attempted. The Vercel bot checkpoint on `openhouse.arbitrum.io` was not bypassed.

## Summary

1. **The 01:01 SGT registration close is stale. Registration was extended.** The live API now says `registrationClose = 2026-10-04T15:58:00.000Z` (2026-10-04 23:58 SGT, 22:58 WIB), one minute before `submissionClose = 2026-10-04T15:59:00.000Z` (23:59 SGT, 22:59 WIB). The Internet Archive snapshot of the same page from 2026-09-25 17:02:55 UTC still shows `registrationClose = 2026-10-02T17:01:00.000Z`, which is the value `DEMO-NOTES.md` section 6 (read 2026-09-28) quoted. The live `currentStatus` array is `["REGISTER","SUBMIT","VOTE_NOT_OPEN","USER_NOT_REGISTER"]`, so the server treats both registration and submission as open right now. Hours left at 14:32 UTC: **25.42 h to registration close, 25.44 h to submission close.**
2. **Registration is a precondition for submitting.** The page's own button logic shows "Start Submit" only when the user's status contains both `SUBMIT` and `USER_REGISTERED`. An unregistered user gets "Start Register" while registration is open and no button after it closes. We cannot see the user's status without login, so the user must check it (checklist below). If the team is not registered, register now, before 2026-10-04 23:58 SGT, and do not wait.
3. **The live form has changed nothing since 2026-09-25** (the `submission` field array is byte-identical between the archive snapshot and today). It has 8 hackathon-specific questions, one contract-address input and a disabled Custom Track. **Every free-text input is capped at `maxCharacters: 300`**, including the three contract-address blocks. This constrains E11-T3.
4. **No video field is in the hackathon form, but HackQuest's project profile has `demoVideo` and `pitchVideo` fields.** Of the 207 projects already submitted, 203 have a `demoVideo` and 106 have a `pitchVideo`. Treat the demo video as effectively mandatory and the pitch video as optional. Whether HackQuest hard-requires `demoVideo` is not verifiable without login.
5. **Existing repos are explicitly allowed; a public repo is not required.** A private repo is allowed if `https://github.com/engineering-AF` is invited.
6. **The Custom Track field is disabled** (`"enabled":false,"options":[]`). There is no custom track to choose. The prize tracks are Overall Prize, Promising Products Track and Grants.
7. **Robinhood Chain reservation and USDG bonus are real and quoted verbatim below.** The reservation wording is ambiguous in the form and clearer in the Arbitrum blog.

## Findings

### F1. Deadlines (primary source: public GraphQL, queried 2026-10-03T14:24:15Z and re-queried 14:32:33Z)

Command: `curl -sS https://api.hackquest.io/graphql -H 'content-type: application/json' --data '{"query":"query($w: HackathonWhereUniqueInput!){findUniqueHackathon(where:$w){id name status currentStatus participants projectCount timeline{timeZone submissionOpen submissionClose registrationOpen registrationClose rewardTime}}}","variables":{"w":{"alias":"Arbitrum-Open-House-Singapore-Online-Buildathon"}}}'`

Output (verbatim): `{"data":{"findUniqueHackathon":{"id":"17bfad43-fdef-4432-a8d7-7595b7538c41","name":"Arbitrum Open House Singapore: Online Buildathon","status":"publish","currentStatus":["REGISTER","SUBMIT","VOTE_NOT_OPEN","USER_NOT_REGISTER"],"participants":1210,"projectCount":208,"timeline":{"timeZone":"Asia/Singapore","submissionOpen":"2026-09-13T17:01:00.000Z","submissionClose":"2026-10-04T15:59:00.000Z","registrationOpen":"2026-07-29T17:01:00.000Z","registrationClose":"2026-10-04T15:58:00.000Z","rewardTime":"2026-10-12T06:00:00.000Z"}}}}`

| Event | UTC | SGT (UTC+8, the page's `timeZone`) | WIB (UTC+7) |
|---|---|---|---|
| registrationOpen | 2026-07-29 17:01 | 2026-07-30 01:01 | 2026-07-30 00:01 |
| submissionOpen | 2026-09-13 17:01 | 2026-09-14 01:01 | 2026-09-14 00:01 |
| **registrationClose (live, extended)** | **2026-10-04 15:58** | **2026-10-04 23:58** | **2026-10-04 22:58** |
| **submissionClose** | **2026-10-04 15:59** | **2026-10-04 23:59** | **2026-10-04 22:59** |
| registrationClose (old, 2026-09-25 and 2026-09-28 value) | 2026-10-02 17:01 | 2026-10-03 01:01 | 2026-10-03 00:01 |
| rewardTime | 2026-10-12 06:00 | 2026-10-12 14:00 | 2026-10-12 13:00 |

- Clock at read time (`date`, `date -u`): `Sat Oct  3 09:32:33 PM WIB 2026`, `2026-10-03T14:32:33Z`, `Sat Oct  3 10:32:33 PM +08 2026`.
- Remaining at 14:32:33 UTC: registration 25.42 h, submission 25.44 h. The old registration close passed 21.5 h before the read.
- Evidence that this is a change: archive.org snapshot `https://web.archive.org/web/20260925170255id_/https://arbitrum-singapore.hackquest.io/buildathons/Arbitrum-Open-House-Singapore-Online-Buildathon` (CDX timestamp 20260925170255) contains `registrationClose":"2026-10-02T17:01:00.000Z"` and `submissionClose":"2026-10-04T15:59:00.000Z"`. The live page, fetched 2026-10-03T14:23:24Z, contains `registrationClose":"2026-10-04T15:58:00.000Z"`. The organiser changed the value between 2026-09-28 and 2026-10-03. I could not find an announcement of the extension (see Assumptions).
- Caution: this is a server value that the organiser can change again, and nothing public says the extension is final. HackQuest decides status server-side (`currentStatus`); the front end only renders it.
- The Arbitrum blog says the Buildathon runs "September 14 to October 4" and the web search summary of the HackQuest listing showed "2 days left" at its index time (a cached value, not used for the answer).

### F2. Can one submit after the old registrationClose of 2026-10-03 01:01 SGT?

- Yes, **if the team is already registered or registers before 2026-10-04 23:58 SGT**, because the live registration window is open until then and submission is open until 23:59 SGT.
- If the original close had stood and the team were unregistered, the UI would have offered nothing: button logic in the page chunk `https://arbitrum-singapore.hackquest.io/_next/static/chunks/58315-1eed7bbaee9ece1f.js` (the buildathon action button) returns, in order: `status==="draft"` Submit Preview or "Pending"; `"review"` "Reviewing"; `REGISTER_NOT_OPEN` "Upcoming"; if `REGISTER` is present then `USER_NOT_REGISTER` gives **"Start Register"**, `USER_CONTINUE_REGISTER` "Continue Register", `USER_PENDING_APPROVAL` "Pending", `USER_REJECT` "Register Again", `USER_WAITLIST` "Waitlist", `USER_APPROVAL_CONFIRM` "Confirm Attendance", `USER_REGISTERED` without `SUBMIT` "Registered"; if `REGISTER_CLOSE` and `SUBMIT_NOT_OPEN` it shows "Registered" or "Pending" or nothing; and otherwise **`SUBMIT` plus `USER_REGISTERED` gives "Start Submit"** (or "Submit Another Project" if `USER_SUBMITTED`). There is no branch that shows a submit button without `USER_REGISTERED`. I found no "late registration" or "submit without registering" rule in the public data or JS.
- Registration may involve approval states (`USER_PENDING_APPROVAL`, `USER_WAITLIST`, `USER_APPROVAL_CONFIRM`) in HackQuest's generic UI. The public form shows no approval question, and `1210` participants are registered against `208` projects, but whether this event auto-approves is **not verifiable without login**. The user must confirm that the status is "Registered", not "Pending" or "Waitlist".
- Team size: `info.needGroup` is `false` and the registration form has no team field. Team size limits for this event are not published in the public data (the group UI reads `minSize` and `maxSize` from a per-event config that the public query does not expose). Unknown.

### F3. Registration form (`info.application`, verbatim labels; needed only if the team has not yet registered)

Section "About":
- "First and Last Name" (required)
- "Location" (placeholder "e.g. Paris, France"; required)
- "Do you already have an idea for what to build during the Buildathon?" (mandatory, 300 chars; placeholder text: "What is the project/idea called? What problem(s) are you addressing with your project, and how does it solve those problems?")
- "Do you already have a project you're working on? Please share the website URL." (mandatory, 300 chars; placeholder: "Provide a link to your project's website in the following format: https://google.com. Type "N/A" if you don't have a website.")
- "Please share your Arbitrum One wallet address with us." (mandatory, 300 chars; "We need your wallet address so that we can distribute prizes. Prizes will be sent on the Arbitrum One network to your provided wallet address in case you win.")
- "Please agree to the terms & conditions and code of conduct." (radio: "I agree to the Terms & Conditions and Code of Conduct"; mandatory)
- "Would you like to sign up for the Arbitrum Builder Newsletter?" (radio: Yes, No; mandatory)
- "Add the referral code of the community you discovered Buildathon through." (optional, 300 chars)

Section "Contact": "Email" (required), "Telegram" (placeholder "Enter a Telegram Account"; not marked optional, so required).
Section "OnlineProfiles": "Github" (placeholder "Enter a GitHub Account"; required), "Twitter" ("Enter a Twitter Account"; required), "LinkedIn" (optional).

Note: `DEMO-NOTES.md` section 6 listed Email, Telegram, GitHub, Twitter and LinkedIn as submission fields. They are **registration** fields, entered once at registration. The submission form is F4.

### F4. Submission form (`info.submission`), every field verbatim, in order

All `input` fields below are `mandatory:true`, `optional:false`, **`maxCharacters:300`**. Placeholder (help) text is quoted from the API; HTML tags removed, line breaks kept.

1. **"Link to frontend/UI/website of your project"** - "Please provide us with a link to the frontend/UI/website of your project or demo."
2. **"List your Core Protocol/ Smart Contract Addresses"** - "List your core smart contract address(es), one per line, in the format:

   network: address — label

   Supported networks:
   Arbitrum One — Arbitrum L2 mainnet
   Arbitrum Nova — Arbitrum Nova
   Robinhood Chain — Robinhood Chain testnet
   Arbitrum Sepolia — Arbitrum testnet

   Example:
   Arbitrum One: 0xAbc...123 — Staking Contract
   Arbitrum Nova: 0xXyz...789 — Proxy Contract

   If your contracts are deployed on a network not listed above, please note it anyway and we'll follow up."
3. **"List your Factory/Pool Contracts (if applicable)"** - "Does your project use factory contracts or allow users to create pools, vaults, or other contracts dynamically (e.g. Uniswap-style pairs, lending pools)?

   If so, provide the factory contract address(es) we can use to track deployments, one per line, in the following format:

   network: address — label

   Example:
   Arbitrum One: 0xAbc...123 — Pair Factory 1
   Arbitrum One: 0xAbc...123 — Pair Factory 2

   If you don't have any Factory/Pool contracts, simply type N/A."
4. **"List your Token Contract Address (if applicable)"** - "List your Token Contract address(es), one per line, in the format:

   network: address — label

   Supported networks: (same four as in item 2)

   Example:
   Arbitrum One: 0xAbc...123 — Token Contract

   If your contracts are deployed on a network not listed above, please note it anyway and we'll follow up. if you don't have any Token Contract Address, simply type N/A."
5. **"Which parts of your code have been produced during the Buildathon?"** - "PLEASE NOTE: You do not need to create a new Github repo for your project. You can use an existing Github repo if you have one. If you use an existing github repo, please explain to us which parts of the code was produced during the Buildathon. Making logical and structured commits will help us understand your progress. If you are building in stealth, you can invite https://github.com/engineering-AF to your Github repo so we can judge your project without you having to make your code publicly available."
6. **"Which sponsor/partner technologies have you used as part of your project?"** - checkbox, multiple, mandatory, "Select all that apply." Options verbatim: `Have not used any`, `GMX`, `Robinhood Chain`, `Dune Analytics`, `ZeroDev`, `Fhenix`, `Alchemy`, `AWS`, `OpenZeppelin`, `Paxos/USDG`.
7. **"Contract Address"** - type `ContractAddress`, name `contract`, placeholder "Paste contract address here", `required:false`. A single address input (separate from the three blocks above). How it maps to a network is not visible without login.
8. **"Custom Track"** - type `CustomTrack`, `optional:true`, `"enabled":false`, `"options":[]`, `"required":false`, `"selectionMode":"single"`. Disabled with no options: nothing to select.

**Contract-address block format.** Exactly `network: address — label`, one per line. The separator before the label is an **em dash (U+2014, byte check `0x2014` with a space on each side)**, not a hyphen. The network names to use are `Robinhood Chain`, `Arbitrum Sepolia`, `Arbitrum One`, `Arbitrum Nova`. Example for Feng (placeholder address, not a real one): `Robinhood Chain: 0x0000000000000000000000000000000000000000 — Vault factory`. That line is 17 (network and colon and space) + 42 (address) + 3 (" — ") + 13 (label) = 75 characters plus a newline, so **a 300-character field holds about 3 to 4 such lines**. The core field, the factory field and the token field each have their own 300-character cap, so split addresses by role and keep labels short. The form says an unlisted network should be noted anyway.

Also in the hackathon-level data (not the form): `info.allowSubmission: true`, `needGroup: false`, `inWhiteList: false`.

### F5. Project profile fields (generic HackQuest project, from public GraphQL queries in the JS bundle and from 207 public submissions)

The query `Project` in the page bundle selects: `name`, `logo`, `oneLineIntro`, `description`, `tracks` (sector), `teachStack`, `demoVideo`, `pitchVideo`, `openSourceLink`, `wallet`, `projectProgress`, `fundraisingStatus`, `prizeTrack`, `ecology`, `team`, plus `fillProgress`. `FindProjectSubmitInfo` selects `prizeTrack`, `fields` (the form answers) and `contractAddress`. Labels and validation of the profile screens are in route chunks that load only after login, so **I could not read the label text or which ones block submission**. Evidence from the public API (`findUniqueProject`, 207 of 207 projects, run 2026-10-03):

| Field | Projects with a value | Reading |
|---|---|---|
| `demoVideo` | 203 / 207 | effectively always filled; treat as required |
| `pitchVideo` | 106 / 207 | optional |
| `openSourceLink` | 205 / 207 | effectively always filled |
| `wallet` | 166 / 207 | optional on the project |
| `fillProgress` | 100: 84, 90: 79, 80: 34, 70: 9, 60: 1 | all 207 have `isSubmit=true`, so submission does not need 100 percent |
| `prizeTrack` | most have all three of "Overall Prize", "Promising Products Track", "Grants" | the project picks tracks; 9 picked only "Overall Prize" |

Video links in the sample are YouTube (`https://youtu.be/...`) and HackQuest-hosted mp4 uploads (`https://assets.hackquest.io/hackathons/projects/demoVideo/...mp4`). `projectProgress` is a free-text "what was built" field (rich text) and `fundraisingStatus` another free-text field; public submissions fill both. Public example of the "built during buildathon" statement: project alias `Tape`.

### F6. Rules and prize wording relevant to Feng (verbatim from the live page; first line of the "Overall Prize" and "Promising Products Track" judging criteria)

- "Your project must be deployed on an Arbitrum chain to qualify. For example: Arbitrum Sepolia, Arbitrum One, Robinhood Chain, or others."
- "Projects are assessed on the following criteria:" "Smart contract quality - code following best practices, structured logically and efficiently, with minimal security vulnerabilities"; "Product-Market Fit - projects with clear potential to attract and retain users"; "Innovation and Creativity - original approaches that push boundaries"; "Real Problem Solving - applications that address genuine market needs."
- "Extra consideration is given to projects integrating Paxos' USDG stablecoin." (links to `https://docs.paxos.com/guides/stablecoin/usdg`). The form's sponsor list has the checkbox `Paxos/USDG`.
- "Note: At minimum, 1 of 3 prizes is reserved for a project building on Robinhood Chain. At minimum, 1 of 3 prizes is reserved for a project building on Arbitrum. All prizes are subject to development-tied milestones. Please refer to our Terms and Conditions for details."
- Clarification from the Arbitrum blog (via WebFetch summary, 2026-10-03): "A minimum of one of the top three spots will be reserved for a project building on the Robinhood Chain" in both the Open Category and the Promising Products Track. Together: at least one of the three podium places in each prize is held for a Robinhood Chain project. That is a reservation for the category, not a guarantee, and the criteria text does not define "building on Robinhood Chain". The form lists "Robinhood Chain — Robinhood Chain testnet" as a supported network, so a testnet deployment under that label is the form's own definition.
- Prize pool: Overall Prize 40,000 / 20,000 / 10,000 USDC (70,000 total); Promising Products Track 7,000 / 5,000 / 3,000 USDC (15,000); Grants 30,000 USDC "case-by-case ... not guaranteed" (`rewards` field, `totalRewards: 115000`). Prizes are paid on Arbitrum One to the wallet given at registration.
- Existing repos: allowed, with an explanation of what was produced in the Buildathon (item 5 above). The registration text also says "Bring an existing project or start from scratch" (page description).
- Public repo: **not required**. Stealth option via inviting `https://github.com/engineering-AF`.
- Video: none in the form's field list (F4); project profile has `demoVideo` and `pitchVideo` (F5).
- Custom track: disabled (F4 item 8). No restriction text exists because there is nothing to choose.
- Terms and Conditions PDF `https://openhouse.arbitrum.io/singapore_version_open_house_buildathon_terms___conditions.pdf` (linked as `info.conduct`): **not read**. `curl` got HTTP 429 with the "Vercel Security Checkpoint" page four times between 14:28 and 14:32 UTC, and WebFetch got HTTP 403. I did not try to bypass the checkpoint. Any rule that exists only in the PDF (eligibility, team size, milestone terms, late registration) is unknown.

### F7. Organiser contact and community channels (URLs only; none is specific to late registration)

- Discord: `https://discord.com/invite/arbitrum`, channel `#open-house` (named on the page: "Arbitrum Discord - Join #open-house to chat with fellow Builders", and in the Workshops tab: "Join the #open-house Channel on the Arbitrum Discord for the latest updates").
- Organiser email published in the API `links.email`: `swagtimus@arbitrum.foundation` (from the `links` object of the hackathon; I did not contact it).
- Organiser website `https://openhouse.arbitrum.io` (behind a Vercel checkpoint for curl); organiser X account `https://x.com/ArbitrumDevs`.
- Workshops and feedback calendar (visible only to registered users in the UI, but the text is in the public payload): Google Calendar id `c_86a05044df941b5164bb22ac407690d716055e9a79cad944cc92bb3be2275fa4@group.calendar.google.com`, ICS `https://calendar.google.com/calendar/ical/c_86a05044df941b5164bb22ac407690d716055e9a79cad944cc92bb3be2275fa4%40group.calendar.google.com/public/basic.ics`.
- Quicknode credits page (registered users): `https://quicknode.notion.site/arb-openh-sgp`.
- The blog page `https://blog.arbitrum.foundation/open-house-singapore-applications-are-now-open/` lists general support `support.arbitrum.io` (WebFetch summary; not specific to this event).
- No Telegram channel for the buildathon is published in the page data. HackQuest has no support link in the buildathon payload.

### F8. Competitive context (public gallery, 2026-10-03, 207 projects submitted)

207 submitted projects are visible through `projects(filter:{hackathonId:...})`. No project named Feng or Composable Strategy Marketplace is listed, which is expected before our submission. A crude keyword check (name, one-line intro, tech stack) finds about 86 mentioning Robinhood, about 37 mentioning USDG and about 25 mentioning vault, basket, portfolio, rebalance or strategy (Tape, Strike, Setpoint, Mirror-onchain, Basqit, Hyperalloy, AutoRange, BoringDeFi, T3trisfinance among them). The Robinhood Chain slot is contested and "strategy vault" is a crowded theme. This is context for the demo's differentiation (composability), not a rule.

## Recommendations

1. **Today, first, the user checks registration status (E0-T5).** Open `https://arbitrum-singapore.hackquest.io/buildathons/Arbitrum-Open-House-Singapore-Online-Buildathon` while logged in. The main button should read "Start Submit". "Registered" alone, "Pending", "Waitlist" or "Confirm Attendance" is a problem. "Start Register" means the team is not registered: register now, do not wait. Registration is open until 2026-10-04 23:58 SGT but the organiser could change that, so do it today.
2. If the button reads "Start Register", registering needs the registration form of F3 (name, location, idea and project-URL answers, Arbitrum One wallet, T&C radio, newsletter radio, email, Telegram, GitHub, Twitter). Prepare these values in advance (the answers must be max 300 characters each). If the button is missing or the page says registration closed, message `#open-house` on the Arbitrum Discord and email `swagtimus@arbitrum.foundation` the same hour and keep a screenshot.
3. Keep the contract-address blocks inside 300 characters each. Core field: the vault registry or factory-independent contracts, one per line; Factory field: the vault factory; Token field: the USDG and the five faucet stock tokens or N/A if none are ours. If more addresses are needed, put the full list in the README and say "full list: <repo>/README.md#deployed-addresses" as the last line, keeping the cap.
4. Plan on a **demo video link** in the project profile (E11-T6) even though the hackathon form has no video field, and a short "built during the buildathon" text (300 characters in the form, plus the longer project-progress field in the profile). Link the full explanation in the README.
5. Submit the final form **at least 6 hours before 2026-10-04 23:59 SGT** (about 17:59 SGT, 10:59 UTC, 16:59 WIB), as E11-T7 already says, because the server value can move and the form needs a logged-in session.
6. Make the repo reachable: either public, or private with `https://github.com/engineering-AF` invited as a collaborator. A public repo is safest for judges.
7. Select `Robinhood Chain` and `Paxos/USDG` in the sponsor checkbox only if they are true at the time of submission (USDG real, not the mock token); never tick `Paxos/USDG` for a mock-only deployment. `OpenZeppelin` is true if OZ v5 is imported.
8. Use the network label `Robinhood Chain` (the form's own label for the testnet) in every address line.

### Exact checklist of human actions on HackQuest (in order)

| # | Action | Where | Can wait until final submission? |
|---|---|---|---|
| 1 | Log in with the team's account and read the status button: it must say "Start Submit". If "Start Register": register (step 2). If "Pending" or "Waitlist": ask `#open-house` and the organiser email now | `https://arbitrum-singapore.hackquest.io/buildathons/Arbitrum-Open-House-Singapore-Online-Buildathon` | **No. Do today.** |
| 2 | If unregistered, complete registration (F3 fields), including the Arbitrum One wallet for prizes. Screenshot the "Registered" state | same page, "Start Register" button | **No. Do today** (closes 2026-10-04 23:58 SGT, may change) |
| 3 | Join the Discord `#open-house` channel (`https://discord.com/invite/arbitrum`) for organiser contact if anything fails | Discord | No, quick, do with step 1 |
| 4 | Click "Start Submit" once to create the project draft and read the project-profile labels and which ones are required. Save the draft. Do **not** press final submit. Report the exact labels to the team, especially whether demo video is required | same page, "Start Submit" | No. Do today so unknowns in F5 are resolved |
| 5 | Prepare the form values from `docs/submission/hackquest-answers.md` (E11-T3) to the 300-character caps | local | Yes (needs final addresses) |
| 6 | Upload or link the demo video; add the pitch video if one exists | project profile | Yes |
| 7 | Paste the frontend link, address blocks (`network: address — label`), "built during the buildathon" text, tick sponsor technologies, choose prize tracks | submission form | Yes |
| 8 | Final submit and screenshot the "Submitted" state ("Submit Another Project" appears after a success) | project page | Yes. Do at least 6 hours before 2026-10-04 23:59 SGT |

## Implications per role

- **User (human):** Steps 1 to 4 of the checklist cannot be delegated; they need your login. Step 1 resolves the biggest process risk named in plan section 0. Step 4 resolves the remaining unknown (project-profile requirements).
- **E11 documentation agent (E11-T3):** write `docs/submission/hackquest-answers.md` to the F4 labels, using the em dash and the 300-character caps. Keep a character counter in the file (for example each block followed by its length). Add an item for the project profile (demo video, pitch video, repo link, project-progress text, tracks, teach stack, wallet) because F4 does not cover them.
- **README and addresses agent (E11-T2, `gen-addresses-md.sh`):** the generated block must also emit a short `network: address — label` form of at most 300 characters per field and a link to the full list.
- **Contract and ops agents (E3, E4, E7):** the form's one "Contract Address" input and the three blocks make a short, stable, verified set of addresses valuable; avoid changing addresses after 2026-10-04 15:00 SGT. `Robinhood Chain` and `Paxos/USDG` ticks depend on E4's real-USDG status.
- **Demo and video (E11-T4, E11-T6):** a demo video is effectively expected by the platform. Ensure the video is a public or unlisted link that works while logged out.
- **Plan owner:** correct plan section 0 and E0-T5 (which say registration is closed and ask to confirm that submission "still opens"): the live close is 2026-10-04 23:58 SGT. Correct `DEMO-NOTES.md` section 6 (registration close and field grouping).

## Assumptions and open questions

Assumptions:
- The live API reflects what the organiser intends. I assume the extended `registrationClose` is deliberate, not a data error, because `currentStatus` contains `REGISTER` and the button code is driven by it.
- "Of the 207 projects, 203 have a demo video" implies the profile requires it. This is inference, not a quoted rule.
- The `maxCharacters: 300` values are enforced by the form. They may be a UI hint only, but plan for them.
- "1 of 3 prizes" means one of the top three places, per the Arbitrum blog (WebFetch summary, which could be imprecise).

Open questions (cannot be settled without login or the PDF):
1. Is the team registered, and in which state (Registered, Pending, Waitlist)?
2. Does registration require organiser approval for this event? (The UI supports it; the form shows no sign.)
3. What are the labels and requirements of the project-profile screens (name, logo, one-line intro, description, tracks, tech stack, demo video, pitch video, repo link, wallet, project progress, fundraising)?
4. Is there a team-size maximum? (`needGroup` is false; the config that holds `minSize` and `maxSize` is not public.)
5. What do the Terms and Conditions PDF say about eligibility, milestones, existing repos and late registration?
6. Is the extended registration close final, and was it announced anywhere (Discord `#open-house`, X)? I found no announcement.
7. How does the standalone "Contract Address" input relate to the three address blocks (one network, one address)?
8. How are the Robinhood Chain reserved places decided, and does a testnet-only deployment qualify? The form lists "Robinhood Chain — Robinhood Chain testnet" as a supported network, which is the best evidence we have.

## Sources

All read on 2026-10-03 (UTC times given).

- Live buildathon page, fetched 14:23:24Z: `https://arbitrum-singapore.hackquest.io/buildathons/Arbitrum-Open-House-Singapore-Online-Buildathon` (HTTP 200, 108795 bytes; data inside the page's React Query dehydrated state, query key `FindUniqueHackathon`).
- HackQuest public GraphQL, queried 14:24:15Z and 14:32:33Z: `https://api.hackquest.io/graphql` (found in the page's JS chunks; introspection is disabled, queries copied from the bundle). Queries run: `findUniqueHackathon` (timeline, status, info.needGroup), `projects(filter:{hackathonId})` (207 rows), `findUniqueProject(where:{alias})` (207 rows, fields demoVideo, pitchVideo, openSourceLink, wallet, prizeTrack, fillProgress, isSubmit).
- Page JS used for logic and query shapes: `https://arbitrum-singapore.hackquest.io/_next/static/chunks/58315-1eed7bbaee9ece1f.js` (action button), `.../29172-10c794f379adbff5.js` (status enum), `.../app/(dashboard)/buildathons/%5Balias%5D/page-9f658e3d2e30288c.js`, and 471 numbered chunks listed in `webpack-a0602710fb189b5c.js`.
- Internet Archive snapshot, 2026-09-25 17:02:55 UTC: `https://web.archive.org/web/20260925170255id_/https://arbitrum-singapore.hackquest.io/buildathons/Arbitrum-Open-House-Singapore-Online-Buildathon` (CDX listing at `https://web.archive.org/cdx/search/cdx?url=arbitrum-singapore.hackquest.io/buildathons*`).
- Registration and submit routes, fetched without login 14:2xZ: `https://arbitrum-singapore.hackquest.io/buildathon/17bfad43-fdef-4432-a8d7-7595b7538c41/register` and `.../null/submit`; both redirect to `/?redirect=...` (login wall); not entered.
- Terms and Conditions (not read): `https://openhouse.arbitrum.io/singapore_version_open_house_buildathon_terms___conditions.pdf` (HTTP 429 Vercel checkpoint via curl at 14:28:23Z, 14:28:33Z, 14:28:49Z, 14:29:19Z; HTTP 403 via WebFetch).
- Arbitrum blog via WebFetch, 2026-10-03: `https://blog.arbitrum.foundation/open-house-singapore-applications-are-now-open/`, `https://blog.arbitrum.foundation/builders-block-023-415k-in-prizes-at-open-house-singapore-apply-now/`, `https://luma.com/openhouse-singapore`.
- Earlier read inside the repo: `docs/handoffs/DEMO-NOTES.md` section 6 (written 2026-09-28), `docs/brainstorm/2026-10-03-feng-v2-plan.md` sections 0, 6 (E0-T5, E11) and 7 (R7).
- Local commands: `date` (`Sat Oct  3 09:32:33 PM WIB 2026`), `date -u` (`2026-10-03T14:32:33Z`), `TZ=Asia/Singapore date` (`Sat Oct  3 10:32:33 PM +08 2026`).

### Recommendation

1. Check registration status today at the buildathon URL (button must read "Start Submit"); if it reads "Start Register", register today (closes 2026-10-04 23:58 SGT).
2. Click "Start Submit" today to create a draft and read the project-profile requirements; do not final-submit.
3. Plan for a demo video link, a repo the judges can open (public, or private with `engineering-AF` invited) and address blocks of at most 300 characters each, in the exact form `network: address — label` with an em dash and the network name `Robinhood Chain`.
4. Do the final submission by about 2026-10-04 17:59 SGT (10:59 UTC, 16:59 WIB), at least 6 hours before the 23:59 SGT close.
5. Tick `Paxos/USDG` and `Robinhood Chain` only if true; choose all prize tracks Feng is eligible for.
6. Fix plan section 0, E0-T5 and `DEMO-NOTES.md` section 6 (registration close and field grouping).

### Still unknown

1. The team's own registration state and whether approval is required (needs login).
2. The labels and required flags of the project-profile screens, notably whether `demoVideo` blocks submission.
3. The content of the Terms and Conditions PDF (blocked by a Vercel checkpoint).
4. Whether the extended registration close is final and was announced; no announcement found.
5. Team-size limits for this event.
6. How the standalone "Contract Address" input maps to the three address blocks, and whether the 300-character cap is a hard server limit.
7. How "building on Robinhood Chain" is judged for the reserved places, and whether a testnet-only deployment qualifies.
