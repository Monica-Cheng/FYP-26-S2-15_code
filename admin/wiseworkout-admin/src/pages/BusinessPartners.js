import React, { useState, useEffect } from 'react';
import { db } from '../firebase';
import { collection, getDocs, doc, updateDoc } from 'firebase/firestore';
import AdminStyles from '../styles/AdminStyles';
import PageHeader from '../components/ui/PageHeader';
import Badge from '../components/ui/Badge';
import EmptyState from '../components/ui/EmptyState';
import SkeletonBlock from '../components/ui/SkeletonBlock';

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


  const updateStatus = async (id, status, reason = '') => {
    const updateData = { status };
    if (reason) updateData.rejectionReason = reason;
    await updateDoc(doc(db, 'businessPartners', id), updateData);
    setPartners(prev => prev.map(p => p.id === id ? { ...p, status, rejectionReason: reason } : p));
  };

  const filtered = filter === 'all' ? partners : partners.filter(p => p.status === filter);

  const statusTone = (status) => status === 'approved' ? 'success' : status === 'rejected' ? 'danger' : 'warning';

  return (
    <div>
      <AdminStyles />
      <PageHeader
        title="Business Partners"
        subtitle={loading ? 'Loading business partners…' : `${partners.length} total applications`}
      />

      {loading ? (
        <SkeletonBlock height={320} />
      ) : (
        <>
          <div className="wwa-pill-group">
            {['all', 'pending', 'approved', 'rejected'].map(f => (
              <button
                key={f}
                onClick={() => setFilter(f)}
                className={`wwa-pill ${filter === f ? 'wwa-pill-active' : ''}`}
              >
                {f.charAt(0).toUpperCase() + f.slice(1)}
              </button>
            ))}
          </div>

          <div className="wwa-row-list">
            {filtered.map(partner => (
              <div key={partner.id} className="wwa-row-card">
                <div>
                  <div className="wwa-row-title">{partner.displayName || partner.businessName || '—'}</div>
                  <div className="wwa-row-sub">{partner.email || '—'}</div>
                  <div className="wwa-row-meta">{partner.specialization || '—'}</div>
                </div>

                <div className="wwa-row-actions">
                  <Badge tone={statusTone(partner.status)}>{partner.status || 'pending'}</Badge>

                  {(partner.status === 'pending' || !partner.status) && (
                    <>
                      <button
                        onClick={() => updateStatus(partner.id, 'approved')}
                        className="wwa-btn wwa-btn-success"
                      >
                        Approve
                      </button>

                      <button
                        onClick={() => {
                          const reason = window.prompt('Enter rejection reason for the applicant:');
                          if (reason !== null) updateStatus(partner.id, 'rejected', reason);
                        }}
                        className="wwa-btn wwa-btn-danger-solid"
                      >
                        Reject
                      </button>
                    </>
                  )}

                  {partner.status === 'approved' && (
                    <button
                      onClick={() => updateStatus(partner.id, 'rejected')}
                      className="wwa-btn wwa-btn-danger"
                    >
                      Revoke
                    </button>
                  )}
                </div>
              </div>
            ))}

            {filtered.length === 0 && (
              <EmptyState
                icon="🤝"
                title="No partners found"
                message={`No ${filter === 'all' ? '' : filter + ' '}partners found.`}
              />
            )}
          </div>
        </>
      )}
    </div>
  );
}

export default BusinessPartners;
