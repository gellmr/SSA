import { useState } from 'react';
import Markdown from 'react-markdown';

function App() {
  const [query, setQuery] = useState('');
  const [loading, setLoading] = useState(false);
  const [result, setResult] = useState(null);
  const [error, setError] = useState('');

  const sampleQuestions = [
    "What are the rules and permits required for entering a confined space?",
    "What first aid equipment is required in a workplace?",
    "How to manage noise hazards and prevent hearing loss at work?",
    "What are the requirements for managing risks of falls at workplaces?"
  ];

  const handleAsk = async (questionToAsk) => {
    const q = questionToAsk || query;
    if (!q.trim()) return;

    setLoading(true);
    setError('');
    setResult(null);

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
    <div style={{ fontFamily: 'system-ui, sans-serif', backgroundColor: '#f4f6f9', minHeight: '100vh', padding: '2rem 1rem' }}>
      <div style={{ maxWidth: '800px', margin: '0 auto', backgroundColor: '#fff', borderRadius: '12px', boxShadow: '0 4px 12px rgba(0,0,0,0.08)', padding: '2rem' }}>
        <div style={{ textAlign: 'center', marginBottom: '2rem' }}>
          <h1 style={{ color: '#1a73e8', margin: '0 0 0.5rem 0' }}>Site Safety Assistant</h1>
          <p style={{ color: '#5f6368', margin: 0 }}>AI-powered Workplace Safety Guidance grounded in <strong>SafeWork Australia Codes of Practice</strong></p>
        </div>

        <div style={{ marginBottom: '1.5rem' }}>
          <div style={{ display: 'flex', gap: '0.5rem', marginBottom: '1rem' }}>
            <input
              type="text"
              placeholder="Ask a workplace safety question..."
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              onKeyDown={(e) => e.key === 'Enter' && handleAsk()}
              style={{ flex: 1, padding: '0.75rem 1rem', borderRadius: '8px', border: '1px solid #dadce0', fontSize: '1rem', outline: 'none' }}
            />
            <button
              onClick={() => handleAsk()}
              disabled={loading || !query.trim()}
              style={{ padding: '0.75rem 1.5rem', backgroundColor: loading ? '#9aa0a6' : '#1a73e8', color: '#fff', border: 'none', borderRadius: '8px', fontSize: '1rem', fontWeight: '600', cursor: loading ? 'not-allowed' : 'pointer' }}
            >
              {loading ? 'Searching...' : 'Ask Assistant'}
            </button>
          </div>

          <div>
            <span style={{ fontSize: '0.85rem', color: '#5f6368', display: 'block', marginBottom: '0.5rem' }}>Sample questions:</span>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: '0.5rem' }}>
              {sampleQuestions.map((sq, idx) => (
                <button key={idx} onClick={() => { setQuery(sq); handleAsk(sq); }} style={{ backgroundColor: '#e8f0fe', color: '#1967d2', border: 'none', borderRadius: '16px', padding: '0.4rem 0.8rem', fontSize: '0.85rem', cursor: 'pointer' }}>
                  {sq}
                </button>
              ))}
            </div>
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
          <div>
            <div style={{ padding: '1.25rem', backgroundColor: '#e8f0fe', borderRadius: '8px', borderLeft: '4px solid #1a73e8', marginBottom: '1.5rem' }}>
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
  );
}

export default App;
