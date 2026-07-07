import React, { useState, useEffect } from 'react';
import { db } from '../firebase';
import { collection, getDocs, doc, updateDoc } from 'firebase/firestore';

function BusinessPartners() {
  const [partners, setPartners] = useState([]);
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState('all');

  useEffect(() => {
    const fetchPartners = async () => {
      try {
        const snap = await getDocs(collection(db, 'businessPartners'));
        const data = snap.docs.map(d => ({ id: d.id, ...d.data() }));
        setPartners(data);
      } catch (err) {
        console.error(err);
      }
      setLoading(false);
    };
    fetchPartners();
  }, []);

  const updateStatus = async (id, status) => {
    await updateDoc(doc(db, 'businessPartners', id), { status });
    setPartners(prev => prev.map(p => p.id === id ? { ...p, status } : p));
  };

  const filtered = filter === 'all' ? partners : partners.filter(p => p.status === filter);

  if (loading) return <div style={{ color: '#888', fontSize: '14px' }}>Loading business partners...</div>;

  return (
    <div>
      <h1 style={{ fontSize: '24px', fontWeight: '700', marginBottom: '8px' }}>Business Partners</h1>
      <p style={{ color: '#888', fontSize: '14px', marginBottom: '24px' }}>{partners.length} total applications</p>

      <div style={{ display: 'flex', gap: '8px', marginBottom: '20px' }}>
        {['all', 'pending', 'approved', 'rejected'].map(f => (
          <button
            key={f}
            onClick={() => setFilter(f)}
            style={{
              padding: '8px 16px', borderRadius: '8px', fontSize: '13px',
              border: 'none', fontWeight: '500', cursor: 'pointer',
              backgroundColor: filter === f ? '#6c63ff' : '#eee',
              color: filter === f ? 'white' : '#555',
            }}
          >
            {f.charAt(0).toUpperCase() + f.slice(1)}
          </button>
        ))}
      </div>

      <div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
        {filtered.map(partner => (
          <div key={partner.id} style={{
            backgroundColor: 'white', borderRadius: '12px', padding: '20px',
            display: 'flex', alignItems: 'center', justifyContent: 'space-between',
          }}>
            <div>
              <div style={{ fontWeight: '600', fontSize: '15px' }}>{partner.displayName || partner.businessName || '—'}</div>
              <div style={{ fontSize: '13px', color: '#888', marginTop: '4px' }}>{partner.email || '—'}</div>
              <div style={{ fontSize: '13px', color: '#aaa', marginTop: '2px' }}>{partner.specialization || '—'}</div>
            </div>

            <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
              <span style={{
                padding: '4px 12px', borderRadius: '999px', fontSize: '12px', fontWeight: '500',
                backgroundColor: partner.status === 'approved' ? '#e6f9f0' : partner.status === 'rejected' ? '#fff0f0' : '#fff8e6',
                color: partner.status === 'approved' ? '#1a9e6a' : partner.status === 'rejected' ? '#cc3333' : '#cc8800',
              }}>
                {partner.status || 'pending'}
              </span>

              {(partner.status === 'pending' || !partner.status) && (
                <>
                  <button
                    onClick={() => updateStatus(partner.id, 'approved')}
                    style={{
                      padding: '8px 16px', borderRadius: '8px', fontSize: '13px',
                      border: 'none', backgroundColor: '#06d6a0', color: 'white', fontWeight: '500',
                    }}
                  >
                    Approve
                  </button>
                  <button
                    onClick={() => updateStatus(partner.id, 'rejected')}
                    style={{
                      padding: '8px 16px', borderRadius: '8px', fontSize: '13px',
                      border: 'none', backgroundColor: '#ff6b6b', color: 'white', fontWeight: '500',
                    }}
                  >
                    Reject
                  </button>
                </>
              )}

              {partner.status === 'approved' && (
                <button
                  onClick={() => updateStatus(partner.id, 'rejected')}
                  style={{
                    padding: '8px 16px', borderRadius: '8px', fontSize: '13px',
                    border: 'none', backgroundColor: '#fff0f0', color: '#cc3333', fontWeight: '500',
                  }}
                >
                  Revoke
                </button>
              )}
            </div>
          </div>
        ))}

        {filtered.length === 0 && (
          <div style={{ color: '#aaa', fontSize: '14px', textAlign: 'center', padding: '40px' }}>
            No {filter === 'all' ? '' : filter} partners found.
          </div>
        )}
      </div>
    </div>
  );
}

export default BusinessPartners;