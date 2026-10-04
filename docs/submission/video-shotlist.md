# Feng demo video: shot list and edit plan

Companion to `docs/submission/demo-script.md` (timing, narration, click paths). Target length 2:00 (hard maximum 2:05). Output: 1920 by 1080, 30 fps, H.264 MP4, audio AAC. Upload as unlisted on YouTube; HackQuest also accepts a hosted mp4.

## Capture setup (once)

- Screen recorder at 1920 by 1080, 30 fps, cursor visible with a soft highlight, system audio off, microphone on a separate track.
- Browser: one clean window, 100 percent zoom, dark theme, no bookmarks bar, no extension icons, notifications off.
- Record every shot as its own file named `NN-name.mp4` so a retake replaces one file, not the whole take.
- Record from a network outside any ISP filter, after `docs/submission/demo-script.md`'s pre-flight checks pass.
- Hide anything private: the sign-in email is a throwaway address; never show an environment variable value, a private key, or a `.env` file.

## Shot list

| # | File | Window | Capture | Overlay text | Narration beat | Notes |
|---|---|---|---|---|---|---|
| 1 | `01-explore.mp4` | 0:00–0:12 | Browser `/`, Explore page, Trending/New sections | Lower third: "Feng — turn what you believe into something others can discover and follow." | Beat 1 | Start after the hero/first paint settles. |
| 2 | `02-strategy.mp4` | 0:12–0:30 | Click into AI Will Win, thesis text, allocation bars, creator link | Callout: "Thesis: AI infrastructure will define the next decade." | Beat 2 | Pause two seconds on the thesis text so it's readable. |
| 3 | `03-follow.mp4` | 0:30–0:45 | Click "+ Follow", button flips to "✓ Following", follower count increments | Callout: "Follower count updates live, on chain" | Beat 3 | If sign-in is needed first, record it as its own short take and cut the wait. |
| 4 | `04-participate.mp4` | 0:45–1:10 | Participate panel: type 1000, testnet label visible, "Participate", wallet prompt, confirmation | Lower third: "Testnet transaction — not real money" | Beat 4 | Cut the confirmation wait to under one second; keep the tx hash on screen once. |
| 5 | `05-explorer.mp4` | 1:10–1:20 | Explorer tab showing the confirmed participate transaction | Lower third: "Real transaction on Robinhood Chain testnet (46630)" | Beat 5 first half | Paste the hash before recording so there's no dead time. |
| 6 | `06-portfolio.mp4` | 1:20–1:35 | `/positions`, the AI Will Win row (amount, allocation chips) | none | Beat 5 second half | Strategy-first view, no per-stock management shown. |
| 7 | `07-creator.mp4` | 1:35–1:50 | `@alex`'s creator profile: handle, bio, follower count, list of strategies | Callout: "Anyone can be a creator" | Beat 6 | Reached via the creator link on the strategy page. |
| 8 | `08-endcard.png` | 1:50–2:00 | Static end card (built in the edit) | "Feng" and the tagline; live URL `https://feng-thesis-launchpad.vercel.app`; repo `https://github.com/Vamp-Labs/Feng` | Beat 7 | Stays on screen for the full duration of beat 7. |

## Edit plan

1. Ingest the 7 clips plus the end card; transcribe the narration track to catch stumbles.
2. Assemble in shot order; trim every transaction wait to under one second, keeping one visible confirmation per transaction.
3. Lay narration from `docs/submission/demo-script.md`; remove filler words; no background music unless it stays under the voice by 20 dB.
4. Add the overlays from the table above, one on screen at a time, none longer than 4 seconds.
5. Burn in subtitles for sound-off viewing.
6. Add the end card; export 1080p MP4.
7. Play the export end to end against the timing windows above; confirm no overlay states a number the screen does not also show.

## Accuracy rules for the video

- Say "testnet" for the participate transaction; never say "real money" or imply it.
- Do not claim audited, mainnet, or real company ownership of the underlying mock stock tokens.
- Show the explorer for at least the one transaction (shot 5) so the chain claim is verifiable.
- Never record with a key, a seed phrase, or an `.env*` file visible.

## Upload and check

1. Upload as unlisted to YouTube (title "Feng demo: an investment thesis launchpad on Robinhood Chain testnet").
2. Open the link in a private window, logged out, on a phone and a laptop; it must play without a login.
3. Put the link into `docs/submission/hackquest-answers.md`'s `demoVideo` field and into the README.
4. Keep the source clips and the project file outside the repository.
