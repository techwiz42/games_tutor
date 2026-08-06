export const metadata = {
  title: "Attribution -- games_tutor",
};

export default function AttributionPage() {
  return (
    <div style={{ padding: 24, maxWidth: 720 }}>
      <h1>Attribution</h1>
      <p>
        games_tutor&apos;s chess and Go opponents, hints, and move analysis are powered by two
        independent, real chess/Go engines. Both run entirely on our servers -- neither engine,
        nor any neural network weights, are ever sent to your browser or device.
      </p>

      <h2>Stockfish (chess)</h2>
      <p>
        Chess is powered by{" "}
        <a href="https://stockfishchess.org/" target="_blank" rel="noreferrer">
          Stockfish
        </a>
        , licensed under the{" "}
        <a href="https://www.gnu.org/licenses/gpl-3.0.html" target="_blank" rel="noreferrer">
          GNU General Public License v3.0
        </a>
        . Full copyright and author list:{" "}
        <a
          href="https://github.com/official-stockfish/Stockfish/blob/master/AUTHORS"
          target="_blank"
          rel="noreferrer"
        >
          official-stockfish/Stockfish/AUTHORS
        </a>
        .
      </p>
      <p>
        Stockfish runs server-side only, as an independent process our backend talks to over the
        UCI protocol -- the same arrangement used by essentially every chess website (Lichess
        included).
      </p>

      <h2>KataGo (Go)</h2>
      <p>
        Go is powered by{" "}
        <a href="https://github.com/lightvector/KataGo" target="_blank" rel="noreferrer">
          KataGo
        </a>
        , licensed under the{" "}
        <a href="https://github.com/lightvector/KataGo/blob/master/LICENSE" target="_blank" rel="noreferrer">
          MIT License
        </a>
        . We use KataGo v1.17.1 with a small neural network from KataGo&apos;s public{" "}
        <a href="https://katagoarchive.org/g170/neuralnets/" target="_blank" rel="noreferrer">
          &quot;g170&quot; training archive
        </a>
        , chosen for fast move times on CPU-only servers.
      </p>
      <p>
        Like Stockfish, KataGo runs server-side only, as an independent process our backend talks
        to over its JSON analysis protocol.
      </p>

      <p style={{ marginTop: 32, fontSize: "0.9em", color: "#666" }}>
        This page documents the actual technical and licensing arrangement; it isn&apos;t legal
        advice.
      </p>
    </div>
  );
}
