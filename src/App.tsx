import { EVENT, getDaysUntilEvent } from './lib/event'
import { ANNOUNCEMENTS, COMMITTEES, CONTACT_EMAIL, PROGRAM } from './lib/publicContent'

const emailHref = `mailto:${CONTACT_EMAIL}?subject=${encodeURIComponent('SCT 1998–2002 reunion volunteer interest')}`

function App() {
  const daysUntil = getDaysUntilEvent(new Date())

  return (
    <>
      <a className="skip-link" href="#main-content">Skip to main content</a>

      <header className="site-header">
        <a className="brand" href="#top" aria-label="SCT 1998–2002 reunion home">
          <span className="brand__mark" aria-hidden="true">98–02</span>
          <span className="brand__name">Sona Silver Jubilee</span>
        </a>
        <nav aria-label="Primary navigation">
          <a href="#reunion">Reunion</a>
          <a href="#program">Program</a>
          <a href="#committees">Committees</a>
          <a href="#updates">Updates</a>
        </nav>
        <a className="button button--small button--dark" href={emailHref}>Help organize</a>
      </header>

      <main id="main-content">
        <section className="hero" id="top" aria-labelledby="page-title">
          <div className="hero__glow hero__glow--one" aria-hidden="true" />
          <div className="hero__glow hero__glow--two" aria-hidden="true" />
          <div className="hero__content">
            <p className="eyebrow">Sona College of Technology · 1998–2002 batch</p>
            <h1 id="page-title">25 years later,<br /><em>back where it began.</em></h1>
            <p className="hero__lead">
              Three days to reconnect with old friends, honor the journey, and build something meaningful together.
            </p>
            <div className="hero__actions">
              <a className="button button--gold" href="#program">Explore the weekend</a>
              <a className="text-link" href={emailHref}>Volunteer with the team <span aria-hidden="true">↗</span></a>
            </div>
            <dl className="hero__facts" aria-label="Reunion summary">
              <div><dt>When</dt><dd>{EVENT.displayDates}</dd></div>
              <div><dt>Where</dt><dd>Sona College of Technology</dd></div>
              <div><dt>Countdown</dt><dd>{daysUntil > 0 ? `${daysUntil.toLocaleString()} days` : 'We are here'}</dd></div>
            </dl>
          </div>

          <aside className="hero__card" aria-label="Save the date">
            <p>Silver Jubilee Reunion</p>
            <div className="date-lockup" aria-label="July 16 to 18, 2027">
              <span>July</span>
              <strong>16<span>—</span>18</strong>
              <span>2027</span>
            </div>
            <div className="hero__card-rule" />
            <p>{EVENT.venue}</p>
            <a href="#contact">Keep me informed <span aria-hidden="true">↓</span></a>
          </aside>
        </section>

        <section className="notice" aria-label="Latest announcement">
          <span className="notice__label">Now live</span>
          <p><strong>The reunion’s public home has opened.</strong> Registration and RSVP arrive in the next secure release.</p>
          <a href="#updates">Read updates <span aria-hidden="true">→</span></a>
        </section>

        <section className="section reunion" id="reunion" aria-labelledby="reunion-title">
          <div className="section-heading">
            <p className="section-kicker">Why we are gathering</p>
            <h2 id="reunion-title">More than a reunion.<br />A return to <em>our people.</em></h2>
            <p>From classrooms and corridors to careers and families, this is a chance to rediscover the community that shaped us.</p>
          </div>
          <div className="purpose-grid">
            <article>
              <span>01</span>
              <h3>Reconnect</h3>
              <p>Find classmates across departments and geographies, and bring the whole batch back into one circle.</p>
            </article>
            <article>
              <span>02</span>
              <h3>Celebrate</h3>
              <p>Honor our friendships, faculty, families, and twenty-five years of stories since graduation.</p>
            </article>
            <article>
              <span>03</span>
              <h3>Contribute</h3>
              <p>Channel the strength of our batch into a lasting gift and a stronger alumni community.</p>
            </article>
          </div>
        </section>

        <section className="section program" id="program" aria-labelledby="program-title">
          <div className="section-heading section-heading--light">
            <div>
              <p className="section-kicker">The three-day arc</p>
              <h2 id="program-title">A weekend built around <em>belonging.</em></h2>
            </div>
            <p>The program is intentionally high-level while committees finalize timings and family activities. Confirmed details will appear here first.</p>
          </div>
          <div className="program-list">
            {PROGRAM.map((item) => (
              <article className="program-card" key={item.number}>
                <div className="program-card__date"><span>{item.day}</span><strong>{item.date}</strong></div>
                <span className="program-card__number" aria-hidden="true">{item.number}</span>
                <div>
                  <h3>{item.title}</h3>
                  <p>{item.description}</p>
                </div>
                <ul aria-label={`${item.day} highlights`}>
                  {item.moments.map((moment) => <li key={moment}>{moment}</li>)}
                </ul>
              </article>
            ))}
          </div>
          <p className="program__note"><span aria-hidden="true">◆</span> Detailed timings are provisional until organizer review.</p>
        </section>

        <section className="section committees" id="committees" aria-labelledby="committees-title">
          <div className="section-heading section-heading--split">
            <div>
              <p className="section-kicker">Built by the batch</p>
              <h2 id="committees-title">Seven teams.<br /><em>One reunion.</em></h2>
            </div>
            <div>
              <p>Every successful reunion needs classmates who can turn good intentions into thoughtful action—wherever they live.</p>
              <a className="text-link text-link--burgundy" href={emailHref}>Tell us where you can help <span aria-hidden="true">↗</span></a>
            </div>
          </div>
          <div className="committee-grid">
            {COMMITTEES.map((committee) => (
              <article key={committee.number}>
                <span>{committee.number}</span>
                <h3>{committee.name}</h3>
                <p>{committee.purpose}</p>
              </article>
            ))}
          </div>
        </section>

        <section className="section updates" id="updates" aria-labelledby="updates-title">
          <div className="section-heading section-heading--split">
            <div>
              <p className="section-kicker">From the organizers</p>
              <h2 id="updates-title">Reunion <em>updates.</em></h2>
            </div>
            <p>Only organizer-approved public information appears here. Private alumni details will require verified access in a later release.</p>
          </div>
          <div className="announcement-list">
            {ANNOUNCEMENTS.map((announcement) => (
              <article key={`${announcement.date}-${announcement.title}`}>
                <div>
                  <span>{announcement.label}</span>
                  <time dateTime={announcement.date}>{announcement.displayDate}</time>
                </div>
                <h3>{announcement.title}</h3>
                <p>{announcement.body}</p>
              </article>
            ))}
          </div>
        </section>

        <section className="section contact" id="contact" aria-labelledby="contact-title">
          <div>
            <p className="section-kicker">Stay in the circle</p>
            <h2 id="contact-title">Help us bring<br /><em>everyone home.</em></h2>
          </div>
          <div className="contact__content">
            <p>Know a classmate we may have missed? Want to represent your department or join a committee? Write to the organizing team.</p>
            <a className="contact__email" href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL} <span aria-hidden="true">↗</span></a>
            <p className="contact__note">Please do not send sensitive personal or family information by email. Secure profile and RSVP collection will open in Phase 2.</p>
          </div>
        </section>

        <section className="privacy" id="privacy" aria-labelledby="privacy-title">
          <div>
            <p className="section-kicker">Privacy first</p>
            <h2 id="privacy-title">A public welcome,<br />with private details protected.</h2>
          </div>
          <div className="privacy__copy">
            <p>This public site contains event information only. It does not publish alumni contact details, family information, biographies, or photographs.</p>
            <p>When secure registration opens, personal information will be collected only for reunion operations and approved commemorative uses. Publication choices for biographies and photographs will remain separate and off by default.</p>
            <p className="privacy__status">Provisional notice · Full privacy and consent terms will be published before member registration opens.</p>
          </div>
        </section>
      </main>

      <footer>
        <a className="brand brand--footer" href="#top">
          <span className="brand__mark" aria-hidden="true">98–02</span>
          <span className="brand__name">Sona Silver Jubilee</span>
        </a>
        <p>July 16–18, 2027 · Salem, Tamil Nadu</p>
        <nav aria-label="Footer navigation">
          <a href="#updates">Updates</a>
          <a href="#privacy">Privacy</a>
          <a href={`mailto:${CONTACT_EMAIL}`}>Contact</a>
        </nav>
      </footer>
    </>
  )
}

export default App
