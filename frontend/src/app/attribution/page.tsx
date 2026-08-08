import {
  pageWrap,
  legalPageInner,
  navBar,
  navBrand,
  navBrandAccent,
  card,
  pageTitle,
  proseHeading2,
  proseBody,
  authLink,
  mutedText,
} from "@/lib/auth-ui";

export const metadata = {
  title: "Attribution -- games_tutor",
};

export default function AttributionPage() {
  return (
    <div className={pageWrap}>
      <header className={navBar}>
        <a href="/">
          <span className={navBrand}>
            games<span className={navBrandAccent}>_tutor</span>
          </span>
        </a>
      </header>

      <main className={legalPageInner}>
        <section className={card}>
          <h1 className={pageTitle}>Attribution</h1>
          <p className={proseBody}>
            games_tutor&apos;s chess and Go opponents, hints, and move analysis are powered by two
            independent, real chess/Go engines. Both run entirely on our servers -- neither engine,
            nor any neural network weights, are ever sent to your browser or device.
          </p>

          <h2 className={proseHeading2}>Stockfish (chess)</h2>
          <p className={proseBody}>
            Chess is powered by{" "}
            <a href="https://stockfishchess.org/" target="_blank" rel="noreferrer" className={authLink}>
              Stockfish
            </a>
            , licensed under the{" "}
            <a
              href="https://www.gnu.org/licenses/gpl-3.0.html"
              target="_blank"
              rel="noreferrer"
              className={authLink}
            >
              GNU General Public License v3.0
            </a>
            . Full copyright and author list:{" "}
            <a
              href="https://github.com/official-stockfish/Stockfish/blob/master/AUTHORS"
              target="_blank"
              rel="noreferrer"
              className={authLink}
            >
              official-stockfish/Stockfish/AUTHORS
            </a>
            .
          </p>
          <p className={`${proseBody} mt-3`}>
            Stockfish runs server-side only, as an independent process our backend talks to over the
            UCI protocol -- the same arrangement used by essentially every chess website (Lichess
            included).
          </p>

          <h2 className={proseHeading2}>KataGo (Go)</h2>
          <p className={proseBody}>
            Go is powered by{" "}
            <a
              href="https://github.com/lightvector/KataGo"
              target="_blank"
              rel="noreferrer"
              className={authLink}
            >
              KataGo
            </a>
            , licensed under the{" "}
            <a
              href="https://github.com/lightvector/KataGo/blob/master/LICENSE"
              target="_blank"
              rel="noreferrer"
              className={authLink}
            >
              MIT License
            </a>
            . We use KataGo v1.17.1 with a small neural network from KataGo&apos;s public{" "}
            <a
              href="https://katagoarchive.org/g170/neuralnets/"
              target="_blank"
              rel="noreferrer"
              className={authLink}
            >
              &quot;g170&quot; training archive
            </a>
            , chosen for fast move times on CPU-only servers.
          </p>
          <p className={`${proseBody} mt-3`}>
            Like Stockfish, KataGo runs server-side only, as an independent process our backend talks
            to over its JSON analysis protocol.
          </p>

          <p className={`${mutedText} mt-8 text-xs`}>
            This page documents the actual technical and licensing arrangement; it isn&apos;t legal
            advice.
          </p>
        </section>
      </main>
    </div>
  );
}
