import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { httpsCallable } from 'firebase/functions';
import { Check, Clock3, Eye, RotateCcw } from 'lucide-react';
import { functions } from '../firebase';
import AdminStyles from '../styles/AdminStyles';
import PageHeader from '../components/ui/PageHeader';
import Badge from '../components/ui/Badge';
import DataTable from '../components/ui/DataTable';
import TableActions from '../components/ui/TableActions';
import ErrorState from '../components/ui/ErrorState';
import DetailDrawer from '../components/ui/DetailDrawer';

function BusinessPartnersStyles() {
  return (
    <style>{`
      .wwbp-page {
        display: flex;
        flex-direction: column;
        gap: var(--ww-space-5);
      }
      .wwbp-filterbar {
        display: inline-flex;
        align-items: center;
        gap: 6px;
        padding: 6px;
        border: 1px solid var(--ww-divider);
        border-radius: 12px;
        background: var(--ww-card);
        width: fit-content;
        max-width: 100%;
      }
      .wwbp-filterbar__item {
        min-height: 36px;
        padding: 8px 12px;
        border: 1px solid transparent;
        border-radius: 10px;
        background: transparent;
        color: var(--ww-text-sec);
        font-size: var(--ww-type-table-body-size);
        font-weight: 600;
        display: inline-flex;
        align-items: center;
        gap: 8px;
        white-space: nowrap;
        transition: background 0.12s ease, border-color 0.12s ease, color 0.12s ease;
      }
      .wwbp-filterbar__item:hover {
        background: var(--ww-hover);
        color: var(--ww-primary-dark);
      }
      .wwbp-filterbar__item.is-active {
        background: var(--ww-selected);
        border-color: var(--ww-chip-bg);
        color: var(--ww-primary-dark);
      }
      .wwbp-filterbar__count {
        min-width: 20px;
        height: 20px;
        padding: 0 6px;
        border-radius: 999px;
        background: var(--ww-elevated);
        color: var(--ww-text-sec);
        font-size: var(--ww-type-caption-size);
        font-weight: 700;
        display: inline-flex;
        align-items: center;
        justify-content: center;
      }
      .wwbp-filterbar__item.is-active .wwbp-filterbar__count {
        background: var(--ww-chip-bg);
        color: var(--ww-primary-dark);
      }
      .wwbp-name-cell {
        min-width: 0;
      }
      .wwbp-name-cell__title {
        font-size: var(--ww-type-body-size);
        font-weight: 600;
        color: var(--ww-text);
      }
      .wwbp-name-cell__meta {
        font-size: var(--ww-type-secondary-size);
        font-weight: var(--ww-type-secondary-weight);
        color: var(--ww-text-sec);
        margin-top: 3px;
        overflow-wrap: anywhere;
      }
      .wwbp-inline-actions {
        display: inline-flex;
        align-items: center;
        justify-content: flex-end;
        gap: 8px;
        flex-wrap: nowrap;
        white-space: nowrap;
      }
      .wwbp-success {
        margin-bottom: var(--ww-space-4);
      }
      .wwbp-empty {
        padding: 28px 24px;
      }
      .wwbp-table .wwa-table th:last-child,
      .wwbp-table .wwa-table td:last-child {
        width: 1%;
        white-space: nowrap;
      }
      .wwbp-layout {
        display: grid;
        grid-template-columns: minmax(0, 1fr);
        gap: var(--ww-space-5);
      }
      .wwbp-layout.has-drawer {
        grid-template-columns: minmax(0, 1fr) var(--ww-drawer-width);
        align-items: start;
      }
      .wwbp-detail-summary {
        display: flex;
        flex-direction: column;
        gap: 10px;
      }
      .wwbp-detail-name {
        font-size: var(--ww-type-section-title-size);
        font-weight: var(--ww-type-section-title-weight);
        color: var(--ww-primary-dark);
        line-height: 1.2;
      }
      .wwbp-detail-badges {
        display: flex;
        align-items: center;
        gap: 8px;
        flex-wrap: wrap;
      }
      .wwbp-detail-section {
        display: flex;
        flex-direction: column;
        gap: 12px;
      }
      .wwbp-detail-section + .wwbp-detail-section {
        padding-top: 20px;
        border-top: 1px solid var(--ww-divider);
      }
      .wwbp-detail-section-title {
        font-size: var(--ww-type-table-header-size);
        font-weight: var(--ww-type-table-header-weight);
        color: var(--ww-text-sec);
        text-transform: uppercase;
        letter-spacing: 0.05em;
      }
      .wwbp-detail-bio {
        font-size: var(--ww-type-body-size);
        color: var(--ww-text);
        line-height: 1.6;
        white-space: pre-wrap;
      }
      @media (max-width: 700px) {
        .wwbp-filterbar {
          width: 100%;
          justify-content: flex-start;
          overflow-x: auto;
        }
      }
      @media (max-width: 1100px) {
        .wwbp-layout.has-drawer {
          grid-template-columns: minmax(0, 1fr);
        }
      }
    `}</style>
  );
}

function BusinessPartners() {
  const [partners, setPartners] = useState([]);
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState('all');
  const [error, setError] = useState('');
  const [successMsg, setSuccessMsg] = useState('');
  const [processingUid, setProcessingUid] = useState(null);
  const [selectedPartner, setSelectedPartner] = useState(null);

  const fetchPartners = useCallback(async () => {
    setLoading(true);
    setError('');

    try {
      const adminListBusinessPartners = httpsCallable(functions, 'adminListBusinessPartners');
      const result = await adminListBusinessPartners();
      const data = result.data?.partners;
      setPartners(Array.isArray(data) ? data : []);
    } catch (err) {
      console.error('Failed to load business partners:', err);
      const detail = err?.code ? ` (${err.code})` : '';
      setError(`Failed to load business partners.${detail}`);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchPartners();
  }, [fetchPartners]);

  const counts = useMemo(() => {
    const pending = partners.filter((partner) => partner.status === 'pending').length;
    const approved = partners.filter((partner) => partner.status === 'approved').length;

    return {
      all: partners.length,
      pending,
      approved,
    };
  }, [partners]);

  const filtered =
    filter === 'all'
      ? partners
      : partners.filter((partner) => partner.status === filter);

  const statusTone = (status) => (status === 'approved' ? 'success' : 'warning');
  const hasRevocationReason = (value) =>
    typeof value === 'string' && value.trim() && value.trim().toLowerCase() !== 'no reason';

  const closeDrawer = () => setSelectedPartner(null);

  const handleApprove = async (partner) => {
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
      const adminApproveBusinessPartner = httpsCallable(functions, 'adminApproveBusinessPartner');

      await adminApproveBusinessPartner({
        partnerUid: partner.id,
        confirmation,
      });

      setPartners((prev) =>
        prev.map((item) =>
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

      setSelectedPartner((prev) =>
        prev && prev.id === partner.id
          ? {
              ...prev,
              isApproved: true,
              isVisible: true,
              status: 'approved',
              revocationReason: undefined,
            }
          : prev
      );

      setSuccessMsg(`${partner.name || 'Business partner'} approved successfully.`);
      setTimeout(() => setSuccessMsg(''), 3000);
    } catch (err) {
      console.error('Failed to approve business partner:', err);
      const detail = err?.code ? ` (${err.code})` : '';
      setError(`Failed to approve business partner.${detail}`);
    } finally {
      setProcessingUid(null);
    }
  };

  const handleRevoke = async (partner) => {
    const reason = window.prompt(`Enter the reason for revoking "${partner.name || partner.id}":`);

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
      const adminRevokeBusinessPartner = httpsCallable(functions, 'adminRevokeBusinessPartner');

      await adminRevokeBusinessPartner({
        partnerUid: partner.id,
        confirmation,
        reason: reason.trim(),
      });

      setPartners((prev) =>
        prev.map((item) =>
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

      setSelectedPartner((prev) =>
        prev && prev.id === partner.id
          ? {
              ...prev,
              isApproved: false,
              isVisible: false,
              status: 'pending',
              revocationReason: reason.trim(),
            }
          : prev
      );

      setSuccessMsg(`${partner.name || 'Business partner'} approval revoked successfully.`);
      setTimeout(() => setSuccessMsg(''), 3000);
    } catch (err) {
      console.error('Failed to revoke business partner:', err);
      const detail = err?.code ? ` (${err.code})` : '';
      setError(`Failed to revoke business partner.${detail} The coach may still have active clients or pending requests.`);
    } finally {
      setProcessingUid(null);
    }
  };

  const filters = [
    { key: 'all', label: 'All', count: counts.all },
    { key: 'pending', label: 'Pending', count: counts.pending },
    { key: 'approved', label: 'Approved', count: counts.approved },
  ];

  const columns = [
    {
      key: 'name',
      header: 'Name',
      render: (partner) => (
        <div className="wwbp-name-cell">
          <div className="wwbp-name-cell__title">{partner.name || 'Unnamed applicant'}</div>
          <div className="wwbp-name-cell__meta">{partner.email || 'No email provided'}</div>
        </div>
      ),
    },
    {
      key: 'type',
      header: 'Professional Type',
      render: (partner) => partner.type || 'No partner type provided',
    },
    {
      key: 'experience',
      header: 'Experience',
      render: (partner) => partner.experience || '—',
    },
    {
      key: 'status',
      header: 'Status',
      render: (partner) => <Badge tone={statusTone(partner.status)}>{partner.status === 'approved' ? 'Approved' : 'Pending'}</Badge>,
    },
  ];

  return (
    <div className="wwbp-page">
      <AdminStyles />
      <BusinessPartnersStyles />

      <PageHeader
        title="Business Partners"
        description="Review and manage professional applications"
        meta={`${partners.length} total applications`}
      />

      {error ? <ErrorState title="Failed to load business partners" message={error} /> : null}

      {successMsg ? (
        <div className="wwbp-success">
          <span className="wwa-status-pill">
            <span className="wwa-status-dot" />
            {successMsg}
          </span>
        </div>
      ) : null}

      {!loading ? (
        <div className="wwbp-filterbar" role="tablist" aria-label="Business partner status filters">
          {filters.map((item) => (
            <button
              key={item.key}
              type="button"
              role="tab"
              aria-selected={filter === item.key}
              className={`wwbp-filterbar__item ${filter === item.key ? 'is-active' : ''}`}
              onClick={() => setFilter(item.key)}
            >
              <span>{item.label}</span>
              <span className="wwbp-filterbar__count">{item.count}</span>
            </button>
          ))}
        </div>
      ) : null}

      <div className={`wwbp-layout ${selectedPartner ? 'has-drawer' : ''}`}>
        <DataTable
          className="wwbp-table"
          columns={columns}
          rows={filtered}
          loading={loading}
          loadingRows={6}
          dense
          emptyIcon={null}
          emptyTitle={filter === 'pending' ? 'No pending applications' : filter === 'approved' ? 'No approved applications' : 'No business partner applications'}
          emptyMessage={
            filter === 'pending'
              ? 'There are currently no business partner applications awaiting review.'
              : filter === 'approved'
                ? 'There are currently no approved business partners to display.'
                : 'There are currently no business partner applications to display.'
          }
          getRowKey={(partner) => partner.id}
          renderRowActions={(partner) => {
            const processing = processingUid === partner.id;

            return (
              <div className="wwbp-inline-actions">
                <button
                  type="button"
                  className="wwa-btn wwa-btn-sm wwa-btn-secondary"
                  onClick={() => setSelectedPartner(partner)}
                  aria-label={`View details for ${partner.name || 'business partner'}`}
                >
                  <Eye aria-hidden="true" size={14} strokeWidth={2} />
                  View
                </button>

                {partner.status === 'pending' ? (
                  <button
                    type="button"
                    className="wwa-btn wwa-btn-sm wwa-btn-success"
                    onClick={() => handleApprove(partner)}
                    disabled={processing}
                    aria-label={`Approve ${partner.name || 'business partner'}`}
                  >
                    <Check aria-hidden="true" size={14} strokeWidth={2} />
                    {processing ? 'Approving...' : 'Approve'}
                  </button>
                ) : null}

                <TableActions
                  label={`Actions for ${partner.name || 'business partner'}`}
                  items={
                    partner.status === 'approved'
                      ? [
                          {
                            key: 'revoke',
                            label: processing ? 'Revoking...' : 'Revoke approval',
                            tone: 'danger',
                            icon: <RotateCcw aria-hidden="true" size={14} strokeWidth={2} />,
                            disabled: processing,
                            onSelect: () => handleRevoke(partner),
                          },
                        ]
                      : [
                          {
                            key: 'pending-state',
                            label: partner.revocationReason ? 'Last revocation noted' : 'Awaiting review',
                            icon: <Clock3 aria-hidden="true" size={14} strokeWidth={2} />,
                            disabled: true,
                          },
                        ]
                  }
                />
              </div>
            );
          }}
        />

        {selectedPartner ? (
          <DetailDrawer
            title="Business Partner"
            open={Boolean(selectedPartner)}
            onClose={closeDrawer}
            summary={
              <div className="wwbp-detail-summary">
                <div className="wwbp-detail-name">{selectedPartner.name || 'Unnamed applicant'}</div>
                <div className="wwbp-detail-badges">
                  <Badge tone={statusTone(selectedPartner.status)}>
                    {selectedPartner.status === 'approved' ? 'Approved' : 'Pending'}
                  </Badge>
                </div>
              </div>
            }
          >
            <section className="wwbp-detail-section">
              <div className="wwbp-detail-section-title">Profile</div>
              <div className="wwa-detail-row">
                <div className="wwa-detail-label">Professional Type</div>
                <div className="wwa-detail-value">{selectedPartner.type || 'No partner type provided'}</div>
              </div>
              <div className="wwa-detail-row">
                <div className="wwa-detail-label">Experience</div>
                <div className="wwa-detail-value">{selectedPartner.experience || '—'}</div>
              </div>
              <div className="wwa-detail-row">
                <div className="wwa-detail-label">Email</div>
                <div className="wwa-detail-value">{selectedPartner.email || 'No email provided'}</div>
              </div>
              <div className="wwa-detail-row">
                <div className="wwa-detail-label">Status</div>
                <div className="wwa-detail-value">{selectedPartner.status === 'approved' ? 'Approved' : 'Pending'}</div>
              </div>
              {hasRevocationReason(selectedPartner.revocationReason) ? (
                <div className="wwa-detail-row">
                  <div className="wwa-detail-label">Last Revocation</div>
                  <div className="wwa-detail-value">{selectedPartner.revocationReason}</div>
                </div>
              ) : null}
            </section>

            <section className="wwbp-detail-section">
              <div className="wwbp-detail-section-title">About</div>
              <div className="wwbp-detail-bio">{selectedPartner.bio || 'No bio provided.'}</div>
            </section>
          </DetailDrawer>
        ) : null}
      </div>
    </div>
  );
}

export default BusinessPartners;
