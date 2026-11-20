import { useState } from 'react';
import Markdown from 'react-markdown';
import styles from './App.module.css';
import 'bootstrap-icons/font/bootstrap-icons.css';

function App() {
  const [query, setQuery] = useState('');
  const [loading, setLoading] = useState(false);
  const [result, setResult] = useState(null);
  const [error, setError] = useState('');
  const [isOpen, setIsOpen] = useState(true);


  const sampleQuestions = [
    "How do I reduce noise and prevent hearing loss?",
    "What are the rules about danger of falling?",
    "What first aid equipment is required in a workplace?",
    "What are the rules and permits required for entering a confined space?",
    "What precautions are needed before working near electrical equipment?",
    "Does SafeWork mandate sunscreen?",
    "What is considered a hazardous task?",
    "What is the most important factor when assessing risk?"
  ];

  const handleAsk = async (questionToAsk) => {
    const q = questionToAsk || query;
    if (!q.trim()) return;

    setLoading(true);
    setError('');
    setResult(null);
    setIsOpen(false);

    try {
      const res = await fetch('/api/safety/ask', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ query: q })
      });

      if (!res.ok) throw new Error(`HTTP error ${res.status}`);
      const data = await res.json();
      setResult(data);
    } catch (err) {
      setError('Error connecting to Safety Assistant: ' + err.message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="container-fluid" style={{ fontFamily: 'system-ui, sans-serif', backgroundColor: '#f4f6f9', minHeight: '100vh', padding: '2rem 1rem' }}>
      <div className="col-12" style={{ maxWidth: '1200px', margin: '0 auto', backgroundColor: '#fff', borderRadius: '12px', boxShadow: '0 4px 12px rgba(0,0,0,0.08)', padding: '0 0 2rem 0', overflow: 'hidden' }}>

        {/* Looping video header */}
        <div>
          <div className={styles['video-container']}>
            <video autoPlay loop muted playsInline ref={(el) => { if (el) el.playbackRate = 0.2; }}>
              <source src="/video-bg.mp4" type="video/mp4" />
              Your browser does not support the video tag.
            </video>

            <div className={styles['video-title-overlay']}>
              <h1 className={styles['title-overlay']}>
                Site Safety Assistant
              </h1>
            </div>
          </div>
        </div>

        <div style={{ padding: '0 2rem' }}>
          <div className="row" style={{ textAlign: '', marginBottom: '2rem' }}>
          <div className="col-12" style={{ color: '#5f6368' }}>
            {/* <h1 style={{ color: '#1a73e8', margin: '0 0 0.5rem 0' }}>Site Safety Assistant</h1> */}
            {/* <p>
              AI-powered Workplace Safety Guidance grounded in <strong>SafeWork Australia Codes of Practice</strong>
            </p> */}
            <p style={{textAlign:'justify'}}>
              This application is powered by Retrieval-Augmented Generation (RAG) and Google Cloud Vertex AI Search. It searches across 12 free public <strong>SafeWork Australia Codes of Practice</strong> PDFs (approx 662 total pages) to retrieve relevant passages and generate grounded answers, with cited source references.
            </p>
            <p>
              Enter a question below to try it. Eg <span style={{padding:4, backgroundColor:'#f3f3f3', borderRadius:5}}>can I eat while working from heights</span>&nbsp;?
            </p>
          </div>
        </div>

        <div className="row" style={{ marginBottom: '1.5rem' }}>
          <div className="col-12 col-md-9" style={{ display: 'flex', gap: '0.5rem', marginBottom: '0.5rem' }}>
            <input
              type="text"
              placeholder="Ask a workplace safety question..."
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              onKeyDown={(e) => e.key === 'Enter' && handleAsk()}
              style={{ width: '100%', flex: 1, padding: '0.75rem 1rem', borderRadius: '8px', border: '1px solid #dadce0', fontSize: '1rem', outline: 'none' }}
            />
          </div>
          <div className="col-12 col-md-3">
            <button
              onClick={() => handleAsk()}
              disabled={loading || !query.trim()}
              style={{ width: '100%', padding: '0.75rem 1.5rem', backgroundColor: loading ? '#9aa0a6' : '#1a73e8', color: '#fff', border: 'none', borderRadius: '8px', fontSize: '1rem', fontWeight: '600', cursor: loading ? 'not-allowed' : 'pointer' }}
            >
              {loading ? 'Searching...' : 'Ask Assistant'}
            </button>
          </div>
        </div>

        <div className="row">
          <div className="col-12">
            <button className="btn btn-light" type="button" onClick={() => setIsOpen(!isOpen)} aria-expanded={isOpen}>
              <span className={styles['samp-span']}>Show sample questions:&nbsp;</span>
              {isOpen ? <i class="bi bi-chevron-down"></i> : <i class="bi bi-caret-down"></i> }
            </button>
            {isOpen && (
            <div className={`col-12 ${styles['sample-quest']}`}>
              {sampleQuestions.map((sq, idx) => (
                <button className={styles['sample-quest']} key={idx} onClick={() => { setQuery(sq); handleAsk(sq); }}>
                  {sq}
                </button>
              ))}
            </div>
            )}
          </div>
        </div>

        {loading && (
          <div style={{ textAlign: 'center', padding: '2rem', color: '#1a73e8' }}>
            <strong>Analyzing SafeWork Australia Codes of Practice...</strong>
          </div>
        )}

        {error && (
          <div style={{ padding: '1rem', backgroundColor: '#fce8e6', color: '#c5221f', borderRadius: '8px' }}>
            {error}
          </div>
        )}

        {result && (
          <div className={`row ${styles['response-blue']}`} style={{marginTop:10}}>
            <div style={{ padding: '1.25rem', backgroundColor: '#e8f0fe', borderRadius: '8px', border: '2px solid #4892f3', marginBottom: '1.5rem' }}>
              <h3 style={{ margin: '0 0 0.75rem 0', color: '#185abc' }}>Safety Guidance Response</h3>
              <div style={{ margin: 0, lineHeight: '1.6', color: '#202124' }}>
                <Markdown>{result.answer}</Markdown>
              </div>
            </div>

            {result.citations && result.citations.length > 0 && (
              <div>
                <h4 style={{ margin: '0 0 0.75rem 0', color: '#3c4043' }}>Source Documents & References</h4>
                <div style={{ display: 'flex', flexDirection: 'column', gap: '0.75rem' }}>
                  {result.citations.map((cit, idx) => (
                    <div key={idx} style={{ padding: '0.85rem', border: '1px solid #e8eaed', borderRadius: '8px', backgroundColor: '#f8f9fa' }}>
                      {cit.docUrl ? (
                        <a
                          href={cit.docUrl}
                          target="_blank"
                          rel="noopener noreferrer"
                          style={{ fontWeight: '600', color: '#1a73e8', fontSize: '0.95rem', textDecoration: 'none' }}
                        >
                          📄 {cit.documentTitle || 'SafeWork Australia Code of Practice'} ↗
                        </a>
                      ) : (
                        <div style={{ fontWeight: '600', color: '#1a73e8', fontSize: '0.9rem', marginBottom: '0.25rem' }}>
                          📄 {cit.documentTitle || 'SafeWork Australia Code of Practice'}
                        </div>
                      )}
                      {cit.snippet && (
                        <p style={{ margin: '0.3rem 0 0 0', fontSize: '0.85rem', color: '#5f6368', lineHeight: '1.4' }}>
                          "{cit.snippet}"
                        </p>
                      )}
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>
        )}
        </div>
      </div>
    </div>
  );
}

export default App;
