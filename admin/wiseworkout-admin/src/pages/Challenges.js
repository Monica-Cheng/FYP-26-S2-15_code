import React, { useState, useEffect } from 'react';
import { db } from '../firebase';
import { collection, getDocs, deleteDoc, doc } from 'firebase/firestore';

function Challenges() {
  const [challenges, setChallenges] = useState([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');

  useEffect(() => {
    const fetchChallenges = async () => {
      try {
        const snap = await getDocs(collection(db, 'challenges'));
        const data = snap.docs.map(d => ({ id: d.id, ...d.data() }));
        setChallenges(data);
      } catch (err) {
        console.error(err);
      }
      setLoading(false);
    };
    fetchChallenges();
  }, []);

  const handleDelete = async (id) => {
    if (!window.confirm('Remove this challenge from the platform?')) return;
    await deleteDoc(doc(db, 'challenges', id));
    setChallenges(prev => prev.filter(c => c.id !== id));
  };

  const filtered = challenges.filter(c =>
    (c.title || c.name || '').toLowerCase().includes(search.toLowerCase())
  );

  if (loading) return <div style={{ color: '#888', fontSize: '14px' }}>Loading challenges...</div>;

  return (
    <div>
      <h1 style={{ fontSize: '24px', fontWeight: '700', marginBottom: '8px' }}>Challenges</h1>
      <p style={{ color: '#888', fontSize: '14px', marginBottom: '24px' }}>
        {challenges.length} challenges on the platform
      </p>

      <input
        placeholder="Search challenges..."
        value={search}
        onChange={e => setSearch(e.target.value)}
        style={{
          width: '100%', padding: '10px 14px', borderRadius: '8px',
          border: '1px solid #ddd', fontSize: '14px', marginBottom: '20px', outline: 'none',
        }}
      />

      {filtered.length === 0 ? (
        <div style={{
          backgroundColor: 'white', borderRadius: '12px', padding: '60px',
          textAlign: 'center', color: '#aaa', fontSize: '14px',
        }}>
          No challenges found.
        </div>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
          {filtered.map(challenge => (
            <div key={challenge.id} style={{
              backgroundColor: 'white', borderRadius: '12px', padding: '20px',
              display: 'flex', alignItems: 'center', justifyContent: 'space-between',
            }}>
              <div>
                <div style={{ fontWeight: '600', fontSize: '15px' }}>
                  {challenge.title || challenge.name || '—'}
                </div>
                <div style={{ fontSize: '13px', color: '#888', marginTop: '4px' }}>
                  {challenge.description || '—'}
                </div>
                <div style={{ fontSize: '12px', color: '#aaa', marginTop: '4px' }}>
                  Type: {challenge.type || '—'} · 
                  Created by: {challenge.createdBy || 'system'}
                </div>
              </div>
              <button
                onClick={() => handleDelete(challenge.id)}
                style={{
                  padding: '8px 16px', borderRadius: '8px', fontSize: '13px',
                  border: 'none', backgroundColor: '#fff0f0', color: '#cc3333', fontWeight: '500',
                }}
              >
                Remove
              </button>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

export default Challenges;