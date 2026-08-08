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
  proseList,
  authLink,
  mutedText,
  draftBanner,
} from "@/lib/auth-ui";

export const metadata = {
  title: "Privacy Policy -- games_tutor",
};

export default function PrivacyPage() {
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
          <div className={draftBanner}>
            <strong>Draft.</strong> This is a first-pass Privacy Policy, written to accurately
            describe what games_tutor actually collects and how it&apos;s handled today. It has not
            been reviewed by a lawyer and should not be treated as final until it has.
          </div>

          <h1 className={pageTitle}>Privacy Policy</h1>
          <p className={mutedText}>Last updated: [date -- fill in on publish]</p>

          <h2 className={proseHeading2}>What we collect</h2>
          <ul className={proseList}>
            <li>
              <strong className="text-zinc-900 dark:text-zinc-50">Account info:</strong> your email
              address and a hashed (never plain-text) password.
            </li>
            <li>
              <strong className="text-zinc-900 dark:text-zinc-50">Game data:</strong> every move you
              play, the engine&apos;s evaluation of each move, and game outcomes -- this is how your
              skill profile is calculated.
            </li>
            <li>
              <strong className="text-zinc-900 dark:text-zinc-50">Skill profile:</strong> an
              estimated chess/Go rating and confidence value, updated after each game.
            </li>
            <li>
              <strong className="text-zinc-900 dark:text-zinc-50">Voice session metadata:</strong>{" "}
              when a voice tutoring session happens, when it ends, its duration, and an estimated
              cost. <em>Not</em> the audio itself -- see below.
            </li>
            <li>
              <strong className="text-zinc-900 dark:text-zinc-50">IP address:</strong> used
              transiently to rate-limit login, registration, and password-reset attempts (abuse
              prevention). These rate-limit records expire automatically (within an hour) and
              aren&apos;t kept as a permanent log tied to your account.
            </li>
            <li>
              <strong className="text-zinc-900 dark:text-zinc-50">Preferences:</strong> things like
              your preferred voice and explanation depth, if you set them.
            </li>
          </ul>

          <h2 className={proseHeading2}>What we don&apos;t collect</h2>
          <p className={proseBody}>
            We do not receive or store your raw voice audio. Voice tutoring uses OpenAI&apos;s
            Realtime API over WebRTC: your browser streams audio directly to OpenAI using a
            short-lived credential our server mints for that session. The audio itself never passes
            through, or is stored on, our servers.
          </p>

          <h2 className={proseHeading2}>How we use it</h2>
          <p className={proseBody}>
            To run the service: authenticate you, run your games against real chess/Go engines,
            compute and improve your skill estimate over time, and (in tutoring sessions) give the
            voice tutor the board state, recent move quality, and your skill level as context so it
            can narrate accurately. We also use your email to send account-related messages (email
            confirmation, password reset) via SendGrid.
          </p>

          <h2 className={proseHeading2}>Who we share it with</h2>
          <ul className={proseList}>
            <li>
              <strong className="text-zinc-900 dark:text-zinc-50">OpenAI</strong> -- during a voice
              session, board/move/skill context is sent to OpenAI&apos;s Realtime API so the tutor
              can narrate your game; your browser also streams audio directly to OpenAI (see above).
            </li>
            <li>
              <strong className="text-zinc-900 dark:text-zinc-50">SendGrid</strong> -- to deliver
              transactional email (confirmation, password reset).
            </li>
          </ul>
          <p className={`${proseBody} mt-3`}>
            We do not sell your data, and we don&apos;t share it with anyone else.
          </p>

          <h2 className={proseHeading2}>Data retention and deletion</h2>
          <p className={proseBody}>
            We currently keep account, game, and skill-profile data for as long as your account
            exists. There is no self-service &quot;delete my account&quot; button yet -- if you want
            your account and associated data deleted, email us (below) and we&apos;ll do it
            manually. This is a known gap we intend to close with a proper self-service flow.
          </p>

          <h2 className={proseHeading2}>Security</h2>
          <p className={proseBody}>
            Passwords are hashed, not stored in plain text. All traffic to the service is encrypted
            (HTTPS/TLS). Login, registration, and password-reset endpoints are rate-limited to slow
            down automated abuse.
          </p>

          <h2 className={proseHeading2}>Children&apos;s privacy</h2>
          <p className={proseBody}>
            games_tutor is intended for users 13 and older (see our{" "}
            <a href="/terms" className={authLink}>
              Terms of Service
            </a>
            ). We do not currently have a technical age-gate at registration -- if you believe a
            child under 13 has created an account, please contact us and we will remove it.
          </p>

          <h2 className={proseHeading2}>Your rights</h2>
          <p className={proseBody}>
            You can request a copy of your data or request deletion at any time by emailing us
            (below).
          </p>

          <h2 className={proseHeading2}>Changes to this policy</h2>
          <p className={proseBody}>
            We may update this policy as the service changes. Material changes will be reflected by
            updating the date at the top of this page.
          </p>

          <h2 className={proseHeading2}>Contact</h2>
          <p className={proseBody}>
            <a href="mailto:pete@cyberiad.ai" className={authLink}>
              pete@cyberiad.ai
            </a>
          </p>
        </section>
      </main>
    </div>
  );
}
