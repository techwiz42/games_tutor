# Stockfish attribution

games_tutor's chess opponent and move-analysis engine is
[Stockfish](https://stockfishchess.org/), licensed under the
[GNU General Public License v3.0](https://www.gnu.org/licenses/gpl-3.0.html).
Full copyright and author list: https://github.com/official-stockfish/Stockfish/blob/master/AUTHORS.

## How it's used here

Stockfish runs **server-side only**, as an independent OS subprocess the
backend talks to over the UCI protocol (via [binbo](https://github.com/DOBRO/binbo),
an Erlang/Elixir chess library with UCI engine support). The binary is never
compiled into the `games_tutor` release, never embedded in a build artifact
that ships to end-user devices, and never distributed. This is the same
pattern essentially every chess website/SaaS uses (Lichess included) and, per
Stockfish's own licensing FAQ, does not trigger the GPL's distribution
obligations for `games_tutor`'s own (independent, non-derivative) codebase.

## Where it comes from

Installed via the distro package (`apt-get install stockfish`, Debian
package version 16) in both `backend/Dockerfile`'s runtime image and this
project's local dev environment — not a vendored/modified binary. Source:
https://github.com/official-stockfish/Stockfish.

## Not legal advice

This note documents the actual technical arrangement (subprocess only, no
distribution) for anyone auditing the project later. It isn't a substitute
for real legal review if `games_tutor` is ever commercialized at a scale
where that matters.
