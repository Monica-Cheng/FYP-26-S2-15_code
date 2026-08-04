import React, { useState, useEffect } from 'react';
import { db } from '../firebase';
import { collection, getDocs } from 'firebase/firestore';
import AdminStyles from '../styles/AdminStyles';
import PageHeader from '../components/ui/PageHeader';
import Badge from '../components/ui/Badge';
import EmptyState from '../components/ui/EmptyState';
import SkeletonBlock from '../components/ui/SkeletonBlock';

function BusinessPartners() {
  const [partners, setPartners] = useState([]);
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState('all');
  const [error, setError] = useState('');

  useEffect(() => {
    const fetchPartners = async () => {
      setLoading(true);
      setError('');

      try {
        const snap = await getDocs(collection(db, 'businessPartners'));

        const data = snap.docs.map((document) => {
          const raw = document.data();

          let status = 'pending';

          if (raw.isApproved === true) {
            status = 'approved';
          } else if (raw.rejectionReason) {
            status = 'rejected';
          }

          return {
            id: document.id,
            ...raw,
            status,
          };
        });

        setPartners(data);
      } catch (err) {
        console.error(err);
        setError(
          err.code === 'permission-denied'
            ? 'Failed to load business partners. (permission-denied)'
            : 'Failed to load business partners.'
        );
      } finally {
        setLoading(false);
      }
    };

    fetchPartners();
  }, []);

  const filtered =
    filter === 'all'
      ? partners
      : partners.filter((partner) => partner.status === filter);

  const statusTone = (status) => {
    if (status === 'approved') return 'success';
    if (status === 'rejected') return 'danger';
    return 'warning';
  };

  return (
    <div>
      <AdminStyles />

      <PageHeader
        title="Business Partners"
        subtitle={
          loading
            ? 'Loading business partners…'
            : `${partners.length} total applications`
        }
      />

      {error && (
        <div
          style={{
            backgroundColor: '#fff0f0',
            color: '#cc0000',
            padding: '12px 16px',
            borderRadius: '10px',
            marginBottom: '18px',
          }}
        >
          {error}
        </div>
      )}

      {loading ? (
        <SkeletonBlock height={320} />
      ) : (
        <>
          <div className="wwa-pill-group">
            {['all', 'pending', 'approved', 'rejected'].map((item) => (
              <button
                key={item}
                onClick={() => setFilter(item)}
                className={`wwa-pill ${
                  filter === item ? 'wwa-pill-active' : ''
                }`}
              >
                {item.charAt(0).toUpperCase() + item.slice(1)}
              </button>
            ))}
          </div>

          <div className="wwa-row-list">
            {filtered.map((partner) => (
              <div key={partner.id} className="wwa-row-card">
                <div>
                  <div className="wwa-row-title">
                    {partner.name || 'Unnamed applicant'}
                  </div>

                  <div className="wwa-row-sub">
                    {partner.email || 'No email provided'}
                  </div>

                  <div className="wwa-row-meta">
                    {partner.type || 'No partner type provided'}
                  </div>

                  {partner.experience && (
                    <div className="wwa-row-meta">
                      Experience: {partner.experience}
                    </div>
                  )}
                </div>

                <div className="wwa-row-actions">
                  <Badge tone={statusTone(partner.status)}>
                    {partner.status}
                  </Badge>

                  {partner.status === 'pending' && (
                    <>
                      <button
                        type="button"
                        className="wwa-btn wwa-btn-success"
                        onClick={() =>
                          window.alert(
                            'Approve will be connected after the secure Cloud Function is added.'
                          )
                        }
                      >
                        Approve
                      </button>

                      <button
                        type="button"
                        className="wwa-btn wwa-btn-danger-solid"
                        onClick={() =>
                          window.alert(
                            'Reject will be connected after the secure Cloud Function is added.'
                          )
                        }
                      >
                        Reject
                      </button>
                    </>
                  )}

                  {partner.status === 'approved' && (
                    <button
                      type="button"
                      className="wwa-btn wwa-btn-danger"
                      onClick={() =>
                        window.alert(
                          'Revoke will be connected after the secure Cloud Function is added.'
                        )
                      }
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
                message={`No ${
                  filter === 'all' ? '' : `${filter} `
                }partners found.`}
              />
            )}
          </div>
        </>
      )}
    </div>
  );
}

export default BusinessPartners;