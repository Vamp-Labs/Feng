# Feng demo video: shot list and edit plan

Companion to `docs/submission/demo-script.md` (timing, narration, click paths). This file says what to capture, what to overlay and how to cut it. Target length 3:00 (hard maximum 3:05). Output: 1920 by 1080, 30 fps, H.264 MP4, audio AAC. Upload as unlisted on YouTube (HackQuest also accepts a hosted mp4; 203 of 207 public submissions have a demo video, `docs/research/14-hackquest-submission.md` F5).

`[V2-PENDING: re-shoot beats that touch V2 features (test-funds button, slippage control, performance view, Live universe) once the V2 deployment is final; V1-only shots stay valid.]`

## Capture setup (once)

- Screen recorder at 1920 by 1080, 30 fps, cursor visible with a soft highlight, system audio off, microphone on a separate track (record narration after the screen takes if the room is noisy, then lay it over).
- Browser: one clean window, 100 percent zoom, dark theme, no bookmarks bar, no extensions icons, notifications off. Terminal: large font (20 pt or more), one tab, a dark theme, no prompt noise.
- Record every shot below as its own file named `NN-name.mp4` (for example `04-deposit.mp4`) so a retake replaces one file.
- Record from a network outside the ISP filter (hotspot or VPN), after `docs/submission/demo-script.md` pre-flight items 1 to 7 pass.
- Hide anything private: the demo email in the Privy modal is a throwaway address; never show an environment variable value, a private key or a `.env` file; the terminal shows only the keeper command and its output.

## Shot list

| # | File | Window | Capture | Overlay text | Narration beat | Notes |
|---|---|---|---|---|---|---|
| 1 | `01-hero.mp4` | 0:00 to 0:20 | Browser `/`, hero animation, pointer drifts to "Create a strategy" | Lower third: "Feng. Investment strategies as composable onchain primitives." | Beat 1 | Start the clip after the hero reveal finishes so the headline is not mid-animation. |
| 2 | `02-signin.mp4` | 0:20 to 0:35 | Nav "Connect wallet", Privy modal, email, code, nav badge and shortened address | none | Beat 2 first half | If the code email is slow, cut the wait. `[V2-PENDING: add the "Get test funds" click and the funded notice]` |
| 3 | `03-marketplace.mp4` | 0:35 to 0:50 | `/marketplace`, stats row, cards with NAV | Callout on the "Nested" stat: "2 nested strategies" (only if the number on screen is 2) | Beat 2 second half | Wait for NAV values, not dashes. |
| 4 | `04-core.mp4` | 0:50 to 1:10 | `/strategy/<CORE>`: "Depth 2" badge, NAV chip, "Constituents & weights" with two "Nested Strategy" badges | Callout: "Depth 2: AI Growth 40, Big Five Equal 40, TSLA 20" | Beat 3 | Scroll slowly; pause on the weights. |
| 5 | `05-child-nav.mp4` | 1:10 to 1:25 | Click a "Nested Strategy" badge, the child page and its NAV, back | Callout: "Parent NAV reads the child vault live" | Beat 3 end | Two seconds on the child NAV is enough. |
| 6 | `06-deposit.mp4` | 1:25 to 1:50 | Deposit panel: type 1000, preview, "Approve USDG", wallet prompt, "Deposit", "Confirmed on-chain." | Callout on the preview: "Preview before you sign" | Beat 4 | Cut both confirmation waits to under 1 second each. `[V2-PENDING: show the minimum-shares control]` |
| 7 | `07-explorer-deposit.mp4` | 1:50 to 2:00 | Explorer transaction page for the deposit | Lower third: "Real transaction on Robinhood Chain testnet (46630)" | Beat 4 end | Show the hash for two seconds. |
| 8 | `08-threshold.mp4` | 2:00 to 2:10 | `/strategy/<EVMO>`, amber "Threshold breached" badge in the Rebalance card | Callout: "TSLA 44 percent, max weight 40 percent" (use the figure on screen) | Beat 5 first sentences | Make sure the badge is amber before the take; do not recompute the number, read it from the page or `cast`. |
| 9 | `09-keeper.mp4` | 2:10 to 2:20 | Terminal: `scripts/keeper.sh robinhood-testnet 30 1`, the flagged vault and `performRebalance` line | Lower third: "Permissionless keeper: a plain address, no special role" | Beat 5 middle | Do not show any key variable. |
| 10 | `10-rebalanced.mp4` | 2:20 to 2:30 | Strategy page badge flips to "Up to date"; explorer logs tab shows the `Rebalanced` event with the keeper as sender | Lower third: "Sender is the keeper, not the deployer" | Beat 5 end | Refresh the logs tab before the take. |
| 11 | `11-create.mp4` | 2:30 to 2:42 | `/create`: tap AIGR and STRM chips, "Even split", name and ticker, max weight, interval, "Create strategy" | Callout: "Strategy Tokens as constituents" | Beat 6 | CORE and CONV appear as "Locked": leave them. |
| 12 | `12-created.mp4` | 2:42 to 2:50 | "Strategy created", "View strategy", "Depth 2" badge | none | Beat 6 end | Confirm the new strategy loads before cutting. |
| 13 | `13-redeem.mp4` | 2:50 to 2:56 | Redeem segment, amount, "You will receive", "Redeem", "Confirmed on-chain." | none | Beat 7 first sentence | One cut to the notice. |
| 14 | `14-endcard.png` | 2:56 to 3:00 | Static end card (built in the edit) | "Feng" and the tagline; live URL; repository URL `[V2-PENDING: repo URL]`; one line: "Real: chain, contracts, wallets, keeper. Mocked: stock tokens, USDG, prices." `[V2-PENDING: edit this line if the Live universe with real USDG shipped]` | Beat 7 end | The honesty line stays on screen for the full four seconds. |

Optional inserts if the edit has room (do not extend past 3:05):

- A 3-second architecture still from the README Mermaid diagram (or the FigJam export from E11-T5 `[V2-PENDING: only if the diagram was produced]`) between shots 5 and 6.
- A split screen of shots 9 and 10.

## Edit plan with `video-use`

1. Ingest the 14 clips; transcribe the narration track to check for stumbles.
2. Assemble in shot order; trim every transaction wait to under one second but keep one visible confirmation per transaction.
3. Lay narration from the script (`docs/submission/demo-script.md`); remove filler words; no background music unless it stays under the voice by 20 dB.
4. Add overlays from the table (lower thirds and callouts), the same font as the app (Poppins), at most one overlay on screen at a time, none longer than 4 seconds.
5. Burn in subtitles for sound-off viewing.
6. Add the end card; export 1080p MP4.
7. Play the export end to end, check timing against the windows above, and check that no overlay states anything the screen does not show (for example the TSLA weight, the "2 nested" count).

## Accuracy rules for the video

- Say "mock" for anything mocked. In the default universe the stock tokens, USDG and price feeds are our own test contracts, prices are constants and V1 custody is simulated by mint and burn (`README.md`, "What is real versus mocked"). `[V2-PENDING: if V2 and the Live universe shipped, say which universe each take uses.]`
- Do not say "real prices", "real swaps", "audited", "Chainlink feeds on testnet" or "mainnet".
- Show the explorer for at least two transactions (shots 7 and 10) so the chain claim is verifiable.
- Never record with a key, a seed phrase or an `.env*` file visible.

## Upload and check

1. Upload as unlisted to YouTube (title "Feng demo: composable strategy tokens on Robinhood Chain", description with the repository and live URLs `[V2-PENDING]`).
2. Open the link in a private window, logged out, on a phone and a laptop; it must play without a login.
3. Put the link into the HackQuest project profile `demoVideo` field (`docs/submission/hackquest-answers.md`) and into the README header `[V2-PENDING: README video link]`.
4. Keep the source clips and the project file outside the repository.
