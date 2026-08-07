export const metadata = {
  title: "Terms of Service -- games_tutor",
};

export default function TermsPage() {
  return (
    <div style={{ padding: 24, maxWidth: 720 }}>
      <div
        style={{
          background: "#fff3cd",
          color: "#664d03",
          border: "1px solid #ffe69c",
          borderRadius: 4,
          padding: "10px 14px",
          marginBottom: 24,
          fontSize: "0.9em",
        }}
      >
        <strong>Draft.</strong> This is a first-pass Terms of Service written to accurately
        describe what games_tutor actually does and collects. It has not been reviewed by a
        lawyer and should not be treated as final or legally binding until it has.
      </div>

      <h1>Terms of Service</h1>
      <p>Last updated: [date -- fill in on publish]</p>

      <h2>1. What this is</h2>
      <p>
        games_tutor is a chess and Go tutoring service. You play against real chess and Go
        engines (Stockfish and KataGo -- see our <a href="/attribution">Attribution page</a>),
        which also estimate your skill level and, in tutoring sessions, narrate and answer
        questions about the game using a real-time voice AI (OpenAI&apos;s Realtime API).
      </p>

      <h2>2. Eligibility</h2>
      <p>
        You must be at least 13 years old to create an account. games_tutor does not currently
        verify age at registration -- this is a stated requirement of using the service, not (yet)
        a technical restriction. If you are a parent or guardian and believe a child under 13 has
        created an account, contact us (below) and we will remove it.
      </p>

      <h2>3. Your account</h2>
      <p>
        You&apos;re responsible for keeping your login credentials secure and for all activity
        under your account. We store passwords hashed, never in plain text.
      </p>

      <h2>4. Acceptable use</h2>
      <p>
        Play fairly, don&apos;t attempt to abuse, overload, or circumvent rate limits on the
        service (including the real chess/Go engines and the voice service, both of which cost us
        real money per use), and don&apos;t use the service for anything illegal or to harass
        others.
      </p>

      <h2>5. Voice tutoring sessions</h2>
      <p>
        Voice sessions use OpenAI&apos;s Realtime API. Your browser connects directly to OpenAI
        over WebRTC to stream audio -- our servers mint a short-lived session credential and
        never receive or store your raw voice audio. Sessions are capped in length and rate to
        control cost; the moves, board state, and skill-estimate context the tutor uses to narrate
        your game are sent to OpenAI as part of that session. See our{" "}
        <a href="/privacy">Privacy Policy</a> for more detail.
      </p>

      <h2>6. Third-party engines and services</h2>
      <p>
        Chess and Go analysis is provided by Stockfish (GPLv3) and KataGo (MIT), running on our
        servers -- see <a href="/attribution">Attribution</a> for licenses and details.
        Transactional email is sent via SendGrid.
      </p>

      <h2>7. No warranty</h2>
      <p>
        games_tutor is provided &quot;as is.&quot; Skill estimates are an approximate heuristic,
        not a certified rating, and engine analysis (evaluations, &quot;best move&quot;
        suggestions, voice commentary) can be wrong. We make no guarantee the service will be
        available, uninterrupted, or error-free.
      </p>

      <h2>8. Limitation of liability</h2>
      <p>
        To the maximum extent permitted by law, games_tutor and its operator are not liable for
        any indirect, incidental, or consequential damages arising from your use of the service.
      </p>

      <h2>9. Termination</h2>
      <p>
        We may suspend or terminate accounts that violate these terms, in particular abuse of
        rate-limited, cost-incurring features (the real engine subprocesses and voice sessions).
        You can stop using the service, and request account deletion, at any time (see Contact).
      </p>

      <h2>10. Changes</h2>
      <p>
        We may update these terms as the service changes. Material changes will be reflected by
        updating the date at the top of this page.
      </p>

      <h2>11. Governing law</h2>
      <p>[Jurisdiction -- fill in on publish.]</p>

      <h2>12. Contact</h2>
      <p>
        Questions, account deletion requests, or reports of a child under 13 using the service:{" "}
        <a href="mailto:pete@cyberiad.ai">pete@cyberiad.ai</a>.
      </p>
    </div>
  );
}
