import React, { useState, useEffect, useCallback } from 'react';
import { functions } from '../firebase';
import { httpsCallable } from 'firebase/functions';
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
  const [successMsg, setSuccessMsg] = useState('');
  const [processingUid, setProcessingUid] = useState(null);

  const fetchPartners = useCallback(async () => {
    setLoading(true);
    setError('');

    try {
      const adminListBusinessPartners = httpsCallable(
        functions,
        'adminListBusinessPartners'
      );

      const result = await adminListBusinessPartners();
      const data = result.data?.partners;

      setPartners(
        Array.isArray(data) ? data : []
      );
    } catch (err) {
      console.error('Failed to load business partners:', err);

      const detail = err?.code ? ` (${err.code})` : '';

      setError(
        `Failed to load business partners.${detail}`
      );
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchPartners();
  }, [fetchPartners]);

  const filtered =
    filter === 'all'
      ? partners
      : partners.filter(
          partner => partner.status === filter
        );

  const statusTone = status =>
    status === 'approved' ? 'success' : 'warning';

  const handleApprove = async partner => {
    const confirmation = window.prompt(
      `Approve "${partner.name || partner.id}" as a coach?\n\n` +
      'This will make the coach visible in the Flutter professional directory.\n\n' +
      'Type APPROVE PARTNER exactly to continue:'
    );

    if (confirmation !== 'APPROVE PARTNER') return;

    setProcessingUid(partner.id);
    setError('');
    setSuccessMsg('');

    try {
      const adminApproveBusinessPartner = httpsCallable(
        functions,
        'adminApproveBusinessPartner'
      );

      await adminApproveBusinessPartner({
        partnerUid: partner.id,
        confirmation,
      });

      setPartners(prev =>
        prev.map(item =>
          item.id === partner.id
            ? {
                ...item,
                isApproved: true,
                isVisible: true,
                status: 'approved',
                revocationReason: undefined,
              }
            : item
        )
      );

      setSuccessMsg(
        `${partner.name || 'Business partner'} approved successfully.`
      );

      setTimeout(() => setSuccessMsg(''), 3000);
    } catch (err) {
      console.error('Failed to approve business partner:', err);

      const detail = err?.code ? ` (${err.code})` : '';

      setError(
        `Failed to approve business partner.${detail}`
      );
    } finally {
      setProcessingUid(null);
    }
  };

  const handleRevoke = async partner => {
    const reason = window.prompt(
      `Enter the reason for revoking "${partner.name || partner.id}":`
    );
  
    if (!reason || !reason.trim()) return;
  
    const confirmation = window.prompt(
      `Revoke coach approval for "${partner.name || partner.id}"?\n\n` +
      `Reason: ${reason.trim()}\n\n` +
      'Type REVOKE PARTNER exactly to continue:'
    );
  
    if (confirmation !== 'REVOKE PARTNER') return;
  
    setProcessingUid(partner.id);
    setError('');
    setSuccessMsg('');
  
    try {
      const adminRevokeBusinessPartner = httpsCallable(
        functions,
        'adminRevokeBusinessPartner'
      );
  
      await adminRevokeBusinessPartner({
        partnerUid: partner.id,
        confirmation,
        reason: reason.trim(),
      });
  
      setPartners(prev =>
        prev.map(item =>
          item.id === partner.id
            ? {
                ...item,
                isApproved: false,
                isVisible: false,
                status: 'pending',
                revocationReason: reason.trim(),
              }
            : item
        )
      );
  
      setSuccessMsg(
        `${partner.name || 'Business partner'} approval revoked successfully.`
      );
  
      setTimeout(() => setSuccessMsg(''), 3000);
    } catch (err) {
      console.error('Failed to revoke business partner:', err);
  
      const detail = err?.code ? ` (${err.code})` : '';
  
      setError(
        `Failed to revoke business partner.${detail} ` +
        'The coach may still have active clients or pending requests.'
      );
    } finally {
      setProcessingUid(null);
    }
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
          className="wwa-alert-error"
          style={{ marginBottom: 16 }}
        >
          {error}
        </div>
      )}

      {successMsg && (
        <div style={{ marginBottom: 16 }}>
          <span className="wwa-status-pill">
            <span className="wwa-status-dot" />
            {successMsg}
          </span>
        </div>
      )}

      {loading ? (
        <SkeletonBlock height={320} />
      ) : (
        <>
          <div className="wwa-pill-group">
            {['all', 'pending', 'approved'].map(item => (
              <button
                key={item}
                type="button"
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
            {filtered.map(partner => {
              const processing =
                processingUid === partner.id;

              return (
                <div
                  key={partner.id}
                  className="wwa-row-card"
                >
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

                    {partner.bio && (
                      <div className="wwa-row-meta">
                        Bio: {partner.bio}
                      </div>
                    )}

                    {Array.isArray(partner.credentialUrls) &&
                      partner.credentialUrls.length > 0 && (
                      <div className="wwa-row-meta">
                        Credentials:{' '}
                        {partner.credentialUrls.map((url, index) => (
                          <span key={url}>
                            {index > 0 && ', '}
                            <a
                              href={url}
                              target="_blank"
                              rel="noopener noreferrer"
                            >
                              View {index + 1}
                            </a>
                          </span>
                        ))}
                      </div>
                    )}

                    {partner.revocationReason && (
                      <div className="wwa-row-meta">
                        Last revocation reason: {partner.revocationReason}
                      </div>
                    )}
                  </div>
                  

                  <div className="wwa-row-actions">
                    <Badge tone={statusTone(partner.status)}>
                      {partner.status}
                    </Badge>

                    {partner.status === 'pending' && (
                      <button
                        type="button"
                        className="wwa-btn wwa-btn-success"
                        onClick={() => handleApprove(partner)}
                        disabled={processing}
                      >
                        {processing ? 'Approving...' : 'Approve'}
                      </button>
                    )}

                    {partner.status === 'approved' && (
                      <button
                        type="button"
                        className="wwa-btn wwa-btn-danger"
                        onClick={() => handleRevoke(partner)}
                        disabled={processing}
                      >
                        {processing ? 'Revoking...' : 'Revoke'}
                      </button>
                    )}
                  </div>
                </div>
              );
            })}

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