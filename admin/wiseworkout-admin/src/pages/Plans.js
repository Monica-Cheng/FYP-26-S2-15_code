import React, { useState, useEffect } from 'react';
import { db } from '../firebase';
import { collection, getDocs } from 'firebase/firestore';

function Plans() {
  const [plans, setPlans] = useState([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');

  useEffect(() => {
    const fetchPlans = async () => {
      try {
        const snap = await getDocs(collection(db, 'plans'));
        const data = snap.docs.map(d => ({ id: d.id, ...d.data() }));
        setPlans(data);
      } catch (err) {
        console.error(err);
      }
      setLoading(false);
    };
    fetchPlans();
  }, []);

  const filtered = plans.filter(p =>
    (p.title || p.name || '').toLowerCase().includes(search.toLowerCase()) ||
    (p.level || '').toLowerCase().includes(search.toLowerCase())
  );

  if (loading) return <div style={{ color: '#888', fontSize: '14px' }}>Loading plans...</div>;

  return (
    <div>
      <h1 style={{ fontSize: '24px', fontWeight: '700', marginBottom: '8px' }}>Plans</h1>
      <p style={{ color: '#888', fontSize: '14px', marginBottom: '24px' }}>
        {plans.length} plans in the library
      </p>

      <input
        placeholder="Search plans..."
        value={search}
        onChange={e => setSearch(e.target.value)}
        style={{
          width: '100%', padding: '10px 14px', borderRadius: '8px',
          border: '1px solid #ddd', fontSize: '14px', marginBottom: '20px', outline: 'none',
        }}
      />

      <div style={{ backgroundColor: 'white', borderRadius: '12px', overflow: 'hidden' }}>
        <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '14px' }}>
          <thead>
            <tr style={{ backgroundColor: '#f8f8f8', borderBottom: '1px solid #eee' }}>
              {['Plan Name', 'Level', 'Duration', 'Days/Week', 'Equipment', 'Type'].map(h => (
                <th key={h} style={{ padding: '14px 16px', textAlign: 'left', fontWeight: '600', color: '#555' }}>{h}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {filtered.length === 0 ? (
              <tr>
                <td colSpan="6" style={{ padding: '40px', textAlign: 'center', color: '#aaa' }}>
                  No plans found.
                </td>
              </tr>
            ) : (
              filtered.map(plan => (
                <tr key={plan.id} style={{ borderBottom: '1px solid #f0f0f0' }}>
                  <td style={{ padding: '14px 16px', fontWeight: '500' }}>
                    {plan.title || plan.name || '—'}
                  </td>
                  <td style={{ padding: '14px 16px' }}>
                    <span style={{
                      padding: '3px 10px', borderRadius: '999px', fontSize: '12px',
                      backgroundColor: plan.level === 'Advanced' ? '#fff0f0' : plan.level === 'Intermediate' ? '#fff8e6' : '#e6f9f0',
                      color: plan.level === 'Advanced' ? '#cc3333' : plan.level === 'Intermediate' ? '#cc8800' : '#1a9e6a',
                    }}>
                      {plan.level || 'Beginner'}
                    </span>
                  </td>
                  <td style={{ padding: '14px 16px', color: '#666' }}>
                    {plan.durationWeeks ? `${plan.durationWeeks}w` : '—'}
                  </td>
                  <td style={{ padding: '14px 16px', color: '#666' }}>
                    {plan.daysPerWeek ? `${plan.daysPerWeek} days` : '—'}
                  </td>
                  <td style={{ padding: '14px 16px', color: '#666' }}>
                    {plan.equipment || '—'}
                  </td>
                  <td style={{ padding: '14px 16px' }}>
                    <span style={{
                      padding: '3px 10px', borderRadius: '999px', fontSize: '12px',
                      backgroundColor: '#f0f0ff', color: '#6c63ff',
                    }}>
                      {plan.type || plan.category || 'General'}
                    </span>
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}

export default Plans;