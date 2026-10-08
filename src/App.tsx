import { EVENT, getDaysUntilEvent } from './lib/event'

function App() {
  const daysUntil = getDaysUntilEvent(new Date())

  return (
    <main>
      <section className="hero" aria-labelledby="page-title">
        <div className="eyebrow">1998–2002 batch · Silver Jubilee</div>
        <h1 id="page-title">Sona College of Technology</h1>
        <p className="lead">Our reunion portal is taking shape.</p>
        <div className="event-card">
          <span className="event-card__label">Save the dates</span>
          <strong>{EVENT.displayDates}</strong>
          <span>{EVENT.venue}</span>
        </div>
        <p className="countdown" aria-live="polite">
          {daysUntil > 0 ? `${daysUntil.toLocaleString()} days until we meet again` : 'Our reunion has arrived'}
        </p>
      </section>

      <section className="content" aria-labelledby="building-title">
        <div>
          <p className="section-kicker">Phase 0 is live</p>
          <h2 id="building-title">We are building the place that brings our batch back together.</h2>
        </div>
        <div className="feature-grid">
          <article><span>01</span><h3>Reconnect</h3><p>Find classmates and build a verified alumni directory.</p></article>
          <article><span>02</span><h3>Organize</h3><p>Form committees, volunteer, and make every responsibility visible.</p></article>
          <article><span>03</span><h3>Remember</h3><p>Share stories and photographs for our Silver Jubilee book.</p></article>
        </div>
        <p className="status">The public reunion foundation is next. Check back as we release each phase.</p>
      </section>
    </main>
  )
}

export default App
